class_name MazGeneratorG1
extends RefCounted
## Generador de mazmorras MAZ, versión G1 (PROYECTO §6.6, ADR 022).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA EXIGE GEN NUEVO: copiar este fichero
## a core/gen/maz/legacy/, registrar G2 y añadir seeds doradas nuevas.
##
## Puro y determinista (CLAUDE.md §6): solo enteros, todo el azar sale del Rng
## recibido y de sus hijos (Rng.fork = hash64, PROYECTO §5.2), listas en orden
## fijo y diccionarios solo consultados por clave, nunca recorridos.
##
## Jerarquía de semillas:
##   raíz ── fork("stairs", 0)        casillas de las escaleras entre niveles
##        └─ fork("level", i)         nivel i
##             ├─ fork("forced", k)    forma de la sala forzada k (escalera)
##             ├─ fork("room_try", t)  intento t de colocar una sala
##             ├─ fork("links", 0)     bucles extra
##             ├─ fork("corridor", c)  trazado del pasillo c
##             ├─ fork("exit", e)      salida e (solo nivel 0)
##             ├─ fork("doors", 0)     tipos de puerta y secretas
##             └─ fork("traps", 0)     trampas
##
## Algoritmo por nivel (coste ~O(casillas + salas² + longitud de pasillos)):
## 1. Salas forzadas: una centrada en cada casilla de escalera que toca a este
##    nivel (la misma casilla arriba y abajo: plantas coherentes en 3D).
## 2. Salas aleatorias hasta `rooms` (máximo rooms × 30 intentos, contador
##    determinista): rectángulo (construida) o mancha de cueva (autómata
##    celular de mayoría dentro de un círculo + componente conexa del
##    centro). Cada sala reserva su huella más una casilla de margen: dos salas
##    nunca se tocan, y todas quedan a >= 1 casilla del borde.
## 3. Conexión: árbol de expansión mínima (Prim, distancia de la rejilla) +
##    bucles extra (corridor_pct % de salas - 1, elegidos entre los pares más
##    cercanos). Cada pasillo es un camino por aristas que en cada paso reduce
##    la distancia al destino (Manhattan en la cuadrada, hexagonal en hex),
##    tendiendo a seguir recto; si se atasca en el borde, BFS.
## 4. Salidas (nivel 0): pasillo desde una sala a una casilla del borde, que
##    forma una zona de 1 casilla (la primera, "entrance").
## 5. Aristas: entre dos casillas transitables de zonas distintas, si una es
##    una sala construida o una salida: puerta donde la cruza un pasillo,
##    muro fino en el resto. Cuevas y pasillos se funden sin aristas.
## 6. Puertas secretas y trampas según densidad (por 10 salas del nivel).
##
## Garantía de accesibilidad: todo pasillo es un camino de pasos por arista
## y cada cambio de zona a lo largo de él es una puerta o un vano; todas las
## salas están en el árbol y las escaleras unen los niveles. Los tests lo
## comprueban con Connectivity sobre muchas semillas.

const SCALE: String = "MAZ"
const GEN: int = 1

const SIZE_IDS: PackedStringArray = ["auto", "small", "medium", "large", "huge"]
## Ancho × alto en casillas de cada tamaño (índice 0 = auto, sin uso).
const SIZE_DIMS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(32, 24), Vector2i(48, 36), Vector2i(64, 48), Vector2i(96, 72)]
## "auto": el tamaño más pequeño cuyo máximo de salas cubre `rooms`.
const AUTO_MAX_ROOMS: PackedInt32Array = [0, 6, 14, 28, 64]

## Estilos (ADR 015), por índice de STYLE_IDS: lados de sala construida,
## radio de cueva y probabilidad (‰) de que una sala de "mixed" sea cueva.
const STYLE_IDS: PackedStringArray = ["human", "dwarf", "elf"]
const STYLE_SIDE_MIN: PackedInt32Array = [3, 4, 3]
const STYLE_SIDE_MAX: PackedInt32Array = [7, 9, 6]
const STYLE_CAVE_R_MIN: PackedInt32Array = [2, 2, 2]
const STYLE_CAVE_R_MAX: PackedInt32Array = [4, 3, 5]
const STYLE_MIXED_CAVE_PERMILLE: PackedInt32Array = [500, 250, 750]

const ATTEMPTS_PER_ROOM: int = 30
## Media anchura de la sala forzada de una escalera (5×5 o cueva de radio 2).
const FORCED_HALF: int = 2
const CAVE_FLOOR_PERMILLE: int = 600
const CAVE_STEPS: int = 3
## Probabilidad de que un pasillo siga en la misma dirección.
const KEEP_DIR_PERMILLE: int = 750
## Ensanchar túneles en el modo cueva.
const TUNNEL_WIDEN_PERMILLE: int = 300
const ARCH_PERMILLE: int = 250
const LOCKED_PERMILLE: int = 120
const TRAP_IDS: PackedStringArray = ["pit", "darts", "net", "alarm"]


## Parámetros ya resueltos del código (todos los campos del esquema MAZ G1).
class Params:
	extends RefCounted
	var rooms: int = 12
	var layout: String = "built"
	var grid_kind: String = "square"
	var corridor_pct: int = 30
	var size_id: String = "auto"
	var exits: int = 1
	var levels: int = 1
	var trap_density: int = 3
	var secret_density: int = 2
	var style: int = 0


## Sala colocada en un nivel.
class RoomInfo:
	extends RefCounted
	var id: int = 0
	var cave: bool = false
	## Casilla de la sala desde la que salen los pasillos.
	var anchor: Vector2i = Vector2i.ZERO


## Estado de construcción de un nivel.
class LevelBuild:
	extends RefCounted
	var level: MapLevel
	var grid: GridGeometry
	## 1 = ocupado por una sala o su margen.
	var reserved: PackedByteArray = PackedByteArray()
	var rooms: Array[RoomInfo] = []
	## id de zona -> lleva puertas y muros en su contorno (sala construida o
	## salida). Solo se consulta por clave.
	var walled: Dictionary[int, bool] = {}
	## id de zona -> es una salida (entrada incluida).
	var exit_zone: Dictionary[int, bool] = {}
	## Pasillos trazados, como índices de casilla.
	var paths: Array[PackedInt32Array] = []

	func _init(p_level: MapLevel) -> void:
		level = p_level
		grid = p_level.grid
		reserved.resize(grid.cell_count())
		reserved.fill(0)


## Punto de entrada registrado en GeneratorRegistry.
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var p: Params = params_from(code)
	var dims: Vector2i = map_size(p.size_id, p.rooms)
	var doc: MapDocument = MapDocument.create(p.grid_kind, dims.x, dims.y, p.levels)
	if doc == null:
		return null
	var stair_cells: Array[Vector2i] = _stair_cells(doc.grid, p.levels, rng.fork("stairs", 0))
	for li: int in p.levels:
		var forced: Array[Vector2i] = []
		if li > 0:
			forced.append(stair_cells[li - 1])
		if li < p.levels - 1:
			forced.append(stair_cells[li])
		_generate_level(doc, li, p, forced, rng.fork("level", li))
	for i: int in stair_cells.size():
		var s: Vector2i = stair_cells[i]
		_add_stair(doc, i, s, i + 1)
		_add_stair(doc, i + 1, s, i)
	return doc


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var rooms: int = code.params["rooms"]
	var layout: String = code.params["layout"]
	var grid_kind: String = code.params["grid"]
	var corridor_pct: int = code.params["corridor_pct"]
	var size_id: String = code.params["size"]
	var exits: int = code.params["exits"]
	var levels: int = code.params["levels"]
	var traps: int = code.params["trap_density"]
	var secrets: int = code.params["secret_door_density"]
	var style: String = code.params["style"]
	p.rooms = rooms
	p.layout = layout
	p.grid_kind = grid_kind
	p.corridor_pct = corridor_pct
	p.size_id = size_id
	p.exits = exits
	p.levels = levels
	p.trap_density = traps
	p.secret_density = secrets
	p.style = maxi(0, STYLE_IDS.find(style))
	return p


## Ancho × alto del mapa para un tamaño ("auto" lo deduce de `rooms`).
static func map_size(size_id: String, rooms: int) -> Vector2i:
	var i: int = SIZE_IDS.find(size_id)
	if i <= 0:
		i = 1
		while i < SIZE_IDS.size() - 1 and rooms > AUTO_MAX_ROOMS[i]:
			i += 1
	return SIZE_DIMS[i]


# --- Escaleras ----------------------------------------------------------------

## Casilla de la escalera entre el nivel i y el i+1. Alterna mitad izquierda y
## derecha del mapa, con columnas [3, w/2-4] y [w/2+3, w-4]: dos escaleras
## seguidas quedan a >= 7 columnas, así que sus salas forzadas (5×5 más
## margen) nunca chocan.
static func _stair_cells(grid: GridGeometry, levels: int, rng: Rng) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var left: bool = rng.chance_permille(500)
	var w: int = grid.width
	var h: int = grid.height
	for i: int in levels - 1:
		var x: int = rng.range_int(3, w / 2 - 4) if left else rng.range_int(w / 2 + 3, w - 4)
		var y: int = rng.range_int(3, h - 4)
		out.append(Vector2i(x, y))
		left = not left
	return out


static func _add_stair(doc: MapDocument, level_index: int, cell: Vector2i, to_level: int) -> void:
	var s: MapStair = MapStair.new()
	s.id = doc.allocate_id()
	s.cell = cell
	s.to_level = to_level
	s.to_cell = cell
	s.facing = 0
	doc.level(level_index).add_stair(s)


# --- Nivel --------------------------------------------------------------------

static func _generate_level(doc: MapDocument, li: int, p: Params, forced: Array[Vector2i], rng: Rng) -> void:
	var b: LevelBuild = LevelBuild.new(doc.level(li))
	for k: int in forced.size():
		_place_forced_room(doc, b, p, forced[k], rng.fork("forced", k))
	var target: int = maxi(p.rooms, forced.size())
	var tries: int = p.rooms * ATTEMPTS_PER_ROOM
	for t: int in tries:
		if b.rooms.size() >= target:
			break
		_try_place_room(doc, b, p, rng.fork("room_try", t))
	_connect_rooms(b, p, rng)
	if li == 0:
		for e: int in p.exits:
			_add_exit(doc, b, e, rng.fork("exit", e))
	var doors: PackedInt64Array = _build_edges(b)
	_assign_doors(b, p, doors, rng.fork("doors", 0))
	_place_traps(doc, b, p, forced, rng.fork("traps", 0))


static func _is_cave_room(p: Params, rng: Rng) -> bool:
	if p.layout == "cave":
		return true
	if p.layout == "mixed":
		return rng.chance_permille(STYLE_MIXED_CAVE_PERMILLE[p.style])
	return false


static func _place_forced_room(doc: MapDocument, b: LevelBuild, p: Params, center: Vector2i, rng: Rng) -> void:
	var cave: bool = _is_cave_room(p, rng)
	if cave:
		_carve_cave_room(doc, b, center, FORCED_HALF, rng)
	else:
		var origin: Vector2i = center - Vector2i(FORCED_HALF, FORCED_HALF)
		var side: int = 2 * FORCED_HALF + 1
		_carve_built_room(doc, b, origin, Vector2i(side, side))


static func _try_place_room(doc: MapDocument, b: LevelBuild, p: Params, rng: Rng) -> void:
	var grid: GridGeometry = b.grid
	var w: int = grid.width
	var h: int = grid.height
	if _is_cave_room(p, rng):
		var r: int = rng.range_int(STYLE_CAVE_R_MIN[p.style], STYLE_CAVE_R_MAX[p.style])
		var center: Vector2i = Vector2i(rng.range_int(r + 1, w - r - 2), rng.range_int(r + 1, h - r - 2))
		if not _is_free(b, grid.cells_in_radius(center, r)):
			return
		_carve_cave_room(doc, b, center, r, rng)
		return
	var size: Vector2i = Vector2i(
		rng.range_int(STYLE_SIDE_MIN[p.style], STYLE_SIDE_MAX[p.style]),
		rng.range_int(STYLE_SIDE_MIN[p.style], STYLE_SIDE_MAX[p.style]))
	var origin: Vector2i = Vector2i(rng.range_int(1, w - 1 - size.x), rng.range_int(1, h - 1 - size.y))
	if not _is_free(b, _rect(origin, size)):
		return
	_carve_built_room(doc, b, origin, size)


static func _rect(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			out.append(origin + Vector2i(x, y))
	return out


static func _is_free(b: LevelBuild, cells: Array[Vector2i]) -> bool:
	for c: Vector2i in cells:
		var i: int = b.grid.index_of(c)
		if i < 0 or b.reserved[i] != 0:
			return false
	return true


static func _reserve(b: LevelBuild, cells: Array[Vector2i]) -> void:
	for c: Vector2i in cells:
		var i: int = b.grid.index_of(c)
		if i >= 0:
			b.reserved[i] = 1


static func _new_zone(doc: MapDocument, b: LevelBuild, kind: String, walled: bool) -> MapRoom:
	var room: MapRoom = MapRoom.make(doc.allocate_id(), kind)
	b.level.add_room(room)
	if walled:
		b.walled[room.id] = true
	return room


static func _carve_built_room(doc: MapDocument, b: LevelBuild, origin: Vector2i, size: Vector2i) -> void:
	var zone: MapRoom = _new_zone(doc, b, MapRoom.KIND_ROOM, true)
	for c: Vector2i in _rect(origin, size):
		b.level.set_terrain(c, Terrain.FLOOR)
		b.level.set_room_id(c, zone.id)
	_reserve(b, _rect(origin - Vector2i.ONE, size + Vector2i(2, 2)))
	var info: RoomInfo = RoomInfo.new()
	info.id = zone.id
	info.anchor = origin + Vector2i(size.x / 2, size.y / 2)
	b.rooms.append(info)


## Cueva: autómata celular de mayoría dentro del círculo de radio r (lo de
## fuera cuenta como roca), con el núcleo de radio 1 siempre suelo; se queda
## solo la componente conexa (por aristas) del centro.
static func _carve_cave_room(doc: MapDocument, b: LevelBuild, center: Vector2i, r: int, rng: Rng) -> void:
	var grid: GridGeometry = b.grid
	var region: Array[Vector2i] = grid.cells_in_radius(center, r)
	var state: PackedByteArray = PackedByteArray()
	state.resize(grid.cell_count())
	state.fill(0)
	for c: Vector2i in region:
		var core: bool = grid.distance(center, c) <= 1
		state[grid.index_of(c)] = 1 if core or rng.chance_permille(CAVE_FLOOR_PERMILLE) else 0
	var nd: int = grid.direction_count()
	for step: int in CAVE_STEPS:
		var next: PackedByteArray = state.duplicate()
		for c: Vector2i in region:
			if grid.distance(center, c) <= 1:
				continue
			var floors: int = 0
			for d: int in nd:
				var ni: int = grid.index_of(grid.neighbor(c, d))
				if ni >= 0 and state[ni] == 1:
					floors += 1
			var walls: int = nd - floors
			if walls * 2 > nd:
				next[grid.index_of(c)] = 0
			elif walls * 2 < nd:
				next[grid.index_of(c)] = 1
		state = next
	# Componente del centro (BFS por aristas, orden fijo de direcciones).
	var zone: MapRoom = _new_zone(doc, b, MapRoom.KIND_CAVE, false)
	var start: int = grid.index_of(center)
	var queue: PackedInt32Array = PackedInt32Array([start])
	state[start] = 2
	var head: int = 0
	while head < queue.size():
		var ci: int = queue[head]
		head += 1
		var cell: Vector2i = grid.cell_at(ci)
		b.level.set_terrain(cell, Terrain.FLOOR)
		b.level.set_room_id(cell, zone.id)
		for d: int in grid.edge_direction_count():
			var ni: int = grid.index_of(grid.neighbor(cell, d))
			if ni >= 0 and state[ni] == 1:
				state[ni] = 2
				queue.append(ni)
	_reserve(b, grid.cells_in_radius(center, r + 1))
	var info: RoomInfo = RoomInfo.new()
	info.id = zone.id
	info.cave = true
	info.anchor = center
	b.rooms.append(info)


# --- Pasillos -----------------------------------------------------------------

## Distancia que reduce cada paso de un pasillo: Manhattan en la cuadrada
## (solo pasos ortogonales) y la hexagonal en hex. Sin preguntar por la
## rejilla: ortogonales + 2 × diagonales + hex.
static func _metric(grid: GridGeometry, a: Vector2i, b: Vector2i) -> int:
	var c: PackedInt32Array = grid.step_counts(a, b)
	return c[0] + 2 * c[1] + c[2]


## Los pasillos no pisan la fila/columna del borde, salvo su destino (salida).
static func _walkable(grid: GridGeometry, c: Vector2i, target: Vector2i) -> bool:
	if c == target:
		return true
	return c.x >= 1 and c.y >= 1 and c.x <= grid.width - 2 and c.y <= grid.height - 2


## Camino por aristas de `from` a `to` (ambos incluidos). Vacío si no existe.
static func _walk(grid: GridGeometry, from: Vector2i, to: Vector2i, rng: Rng) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from]
	var cur: Vector2i = from
	var last_dir: int = -1
	var m: int = _metric(grid, cur, to)
	while cur != to:
		var options: PackedInt32Array = PackedInt32Array()
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(cur, d)
			if _walkable(grid, n, to) and _metric(grid, n, to) < m:
				options.append(d)
		if options.is_empty():
			var rest: Array[Vector2i] = _bfs(grid, cur, to)
			if rest.is_empty():
				var none: Array[Vector2i] = []
				return none
			for k: int in range(1, rest.size()):
				path.append(rest[k])
			return path
		var dir: int
		if options.has(last_dir) and rng.chance_permille(KEEP_DIR_PERMILLE):
			dir = last_dir
		else:
			dir = options[rng.pick_index(options.size())]
		cur = grid.neighbor(cur, dir)
		path.append(cur)
		last_dir = dir
		m = _metric(grid, cur, to)
	return path


## Camino más corto por aristas (BFS, orden fijo); vacío si no hay.
static func _bfs(grid: GridGeometry, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start: int = grid.index_of(from)
	var goal: int = grid.index_of(to)
	if start < 0 or goal < 0:
		return out
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(grid.cell_count())
	prev.fill(-2)
	prev[start] = -1
	var queue: PackedInt32Array = PackedInt32Array([start])
	var head: int = 0
	while head < queue.size() and prev[goal] == -2:
		var ci: int = queue[head]
		head += 1
		var cell: Vector2i = grid.cell_at(ci)
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(cell, d)
			var ni: int = grid.index_of(n)
			if ni < 0 or prev[ni] != -2 or not _walkable(grid, n, to):
				continue
			prev[ni] = ci
			queue.append(ni)
	if prev[goal] == -2:
		return out
	var at: int = goal
	while at >= 0:
		out.append(grid.cell_at(at))
		at = prev[at]
	out.reverse()
	return out


## Excava el camino (solo la roca pasa a suelo de pasillo, zona 0) y lo guarda.
static func _carve_path(b: LevelBuild, path: Array[Vector2i]) -> void:
	var idx: PackedInt32Array = PackedInt32Array()
	for c: Vector2i in path:
		if b.level.get_terrain(c) == Terrain.VOID:
			b.level.set_terrain(c, Terrain.FLOOR)
		idx.append(b.grid.index_of(c))
	b.paths.append(idx)


static func _connect_rooms(b: LevelBuild, p: Params, rng: Rng) -> void:
	var n: int = b.rooms.size()
	if n < 2:
		return
	var grid: GridGeometry = b.grid
	# Prim O(n²); empates por índice menor.
	var pairs: Array[Vector2i] = []
	var in_tree: Dictionary[int, bool] = {}
	var used: PackedByteArray = PackedByteArray()
	used.resize(n)
	used.fill(0)
	var best_d: PackedInt64Array = PackedInt64Array()
	best_d.resize(n)
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(n)
	used[0] = 1
	for j: int in n:
		best_d[j] = grid.distance(b.rooms[0].anchor, b.rooms[j].anchor)
		parent[j] = 0
	for step: int in n - 1:
		var pick: int = -1
		for j: int in n:
			if used[j] == 0 and (pick < 0 or best_d[j] < best_d[pick]):
				pick = j
		used[pick] = 1
		var i0: int = mini(parent[pick], pick)
		var j0: int = maxi(parent[pick], pick)
		pairs.append(Vector2i(i0, j0))
		in_tree[i0 * n + j0] = true
		for j: int in n:
			if used[j] == 0:
				var dj: int = grid.distance(b.rooms[pick].anchor, b.rooms[j].anchor)
				if dj < best_d[j]:
					best_d[j] = dj
					parent[j] = pick
	# Bucles extra entre los pares más cercanos que no están en el árbol.
	var want: int = ((n - 1) * p.corridor_pct + 50) / 100
	if want > 0:
		var keys: PackedInt64Array = PackedInt64Array()
		for i: int in n:
			for j: int in range(i + 1, n):
				if not in_tree.has(i * n + j):
					var dist: int = grid.distance(b.rooms[i].anchor, b.rooms[j].anchor)
					keys.append(dist * n * n + i * n + j)
		keys.sort()
		var pool: Array = []
		for k: int in mini(keys.size(), want * 3):
			pool.append(keys[k])
		var links: Rng = rng.fork("links", 0)
		links.shuffle(pool)
		for k: int in mini(want, pool.size()):
			var key: int = pool[k]
			var rest: int = key % (n * n)
			pairs.append(Vector2i(rest / n, rest % n))
	for c: int in pairs.size():
		var crng: Rng = rng.fork("corridor", c)
		var a: RoomInfo = b.rooms[pairs[c].x]
		var z: RoomInfo = b.rooms[pairs[c].y]
		var path: Array[Vector2i] = _walk(grid, a.anchor, z.anchor, crng)
		_carve_path(b, path)
		if p.layout == "cave":
			_widen(b, path, crng)


## Túneles de cueva: cada casilla puede abrir una vecina más (roca interior).
static func _widen(b: LevelBuild, path: Array[Vector2i], rng: Rng) -> void:
	# Las casillas abiertas son vecinas por arista de una casilla del túnel y
	# de su misma zona (0): quedan conectadas sin tocar las aristas.
	var grid: GridGeometry = b.grid
	for c: Vector2i in path:
		if not rng.chance_permille(TUNNEL_WIDEN_PERMILLE):
			continue
		var n: Vector2i = grid.neighbor(c, rng.pick_index(grid.edge_direction_count()))
		if _walkable(grid, n, Vector2i(-1, -1)) and b.level.get_terrain(n) == Terrain.VOID:
			b.level.set_terrain(n, Terrain.FLOOR)


# --- Salidas ------------------------------------------------------------------

static func _add_exit(doc: MapDocument, b: LevelBuild, e: int, rng: Rng) -> void:
	if b.rooms.is_empty():
		return
	var room: RoomInfo = b.rooms[rng.pick_index(b.rooms.size())]
	var side: int = rng.pick_index(4)
	var target: Vector2i = _border_target(b, room.anchor, side)
	var path: Array[Vector2i] = _walk(b.grid, room.anchor, target, rng)
	if path.is_empty():
		return
	_carve_path(b, path)
	var zone: MapRoom = _new_zone(doc, b, MapRoom.KIND_ENTRANCE if e == 0 else MapRoom.KIND_EXIT, true)
	b.exit_zone[zone.id] = true
	b.level.set_room_id(target, zone.id)


## Casilla del borde (`side`: 0 arriba, 1 derecha, 2 abajo, 3 izquierda) lo
## más alineada posible con `anchor`, sin esquinas, libre y sin otra salida
## al lado. Recorre desplazamientos 0, +1, -1, +2, -2… (determinista).
static func _border_target(b: LevelBuild, anchor: Vector2i, side: int) -> Vector2i:
	var grid: GridGeometry = b.grid
	var horizontal: bool = side == 0 or side == 2
	var length: int = grid.width if horizontal else grid.height
	var fixed: int = 0
	if side == 1:
		fixed = grid.width - 1
	elif side == 2:
		fixed = grid.height - 1
	var start: int = anchor.x if horizontal else anchor.y
	for k: int in 2 * length:
		var off: int = (k + 1) / 2 if k % 2 == 1 else -(k / 2)
		var pos: int = start + off
		if pos < 1 or pos > length - 2:
			continue
		var cell: Vector2i = Vector2i(pos, fixed) if horizontal else Vector2i(fixed, pos)
		var step: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		if b.level.get_terrain(cell) != Terrain.VOID:
			continue
		if b.level.get_terrain(cell - step) != Terrain.VOID or b.level.get_terrain(cell + step) != Terrain.VOID:
			continue
		return cell
	return Vector2i(start, fixed) if horizontal else Vector2i(fixed, start)


# --- Puertas, muros y trampas -------------------------------------------------

## Pone muros finos y devuelve los ids (ordenados) de las aristas que serán
## puertas: las que cruza un pasillo entre dos zonas cuando una lleva contorno.
static func _build_edges(b: LevelBuild) -> PackedInt64Array:
	var grid: GridGeometry = b.grid
	var level: MapLevel = b.level
	var portals: Dictionary[int, bool] = {}
	for path: PackedInt32Array in b.paths:
		for k: int in range(1, path.size()):
			var a: Vector2i = grid.cell_at(path[k - 1])
			var c: Vector2i = grid.cell_at(path[k])
			if level.get_room_id(a) == level.get_room_id(c):
				continue
			var dir: int = grid.direction_between(a, c)
			if dir >= 0 and dir < grid.edge_direction_count():
				portals[grid.edge_id(a, dir)] = true
	var doors: PackedInt64Array = PackedInt64Array()
	var half: int = grid.edge_direction_count() / 2
	for i: int in grid.cell_count():
		var cell: Vector2i = grid.cell_at(i)
		if not Terrain.is_passable(level.terrain[i]):
			continue
		var za: int = level.room_ids[i]
		for d: int in half:
			var nb: Vector2i = grid.neighbor(cell, d)
			var ni: int = grid.index_of(nb)
			if ni < 0 or not Terrain.is_passable(level.terrain[ni]):
				continue
			var zb: int = level.room_ids[ni]
			if za == zb or not (b.walled.has(za) or b.walled.has(zb)):
				continue
			var id: int = grid.edge_id(cell, d)
			if portals.has(id):
				doors.append(id)
			else:
				level.set_edge_by_id(id, MapEdge.make(MapEdge.KIND_WALL))
	doors.sort()
	return doors


static func _assign_doors(b: LevelBuild, p: Params, doors: PackedInt64Array, rng: Rng) -> void:
	var level: MapLevel = b.level
	var room_count: int = _room_count(b)
	var secret_want: int = (room_count * p.secret_density + 5) / 10
	# Candidatas a secreta: no tocan una salida (la entrada no se esconde).
	var candidates: Array = []
	for id: int in doors:
		var cells: Array[Vector2i] = b.grid.edge_cells(id)
		if b.exit_zone.has(level.get_room_id(cells[0])) or b.exit_zone.has(level.get_room_id(cells[1])):
			continue
		candidates.append(id)
	var secret: Dictionary[int, bool] = {}
	for k: int in mini(secret_want, candidates.size()):
		var pick: int = rng.pick_index(candidates.size())
		var sid: int = candidates[pick]
		candidates.remove_at(pick)
		secret[sid] = true
	for id: int in doors:
		var value: int
		if secret.has(id):
			value = MapEdge.make(MapEdge.KIND_SECRET_DOOR)
		elif rng.chance_permille(ARCH_PERMILLE):
			value = MapEdge.make(MapEdge.KIND_ARCH)
		elif rng.chance_permille(LOCKED_PERMILLE):
			value = MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_LOCKED)
		else:
			value = MapEdge.make(MapEdge.KIND_DOOR)
		level.set_edge_by_id(id, value)


## Salas del nivel (construidas y cuevas; sin salidas).
static func _room_count(b: LevelBuild) -> int:
	return b.rooms.size()


static func _place_traps(doc: MapDocument, b: LevelBuild, p: Params, forced: Array[Vector2i], rng: Rng) -> void:
	var level: MapLevel = b.level
	var want: int = (_room_count(b) * p.trap_density + 5) / 10
	if want <= 0:
		return
	var is_room: Dictionary[int, bool] = {}
	for r: RoomInfo in b.rooms:
		is_room[r.id] = true
	var candidates: Array[Vector2i] = []
	for i: int in b.grid.cell_count():
		var c: Vector2i = b.grid.cell_at(i)
		if Terrain.is_passable(level.terrain[i]) and is_room.has(level.room_ids[i]) and not forced.has(c):
			candidates.append(c)
	for k: int in mini(want, candidates.size()):
		var pick: int = rng.pick_index(candidates.size())
		var t: MapTrap = MapTrap.new()
		t.id = doc.allocate_id()
		t.cell = candidates[pick]
		t.trap_id = TRAP_IDS[rng.pick_index(TRAP_IDS.size())]
		t.hidden = true
		t.armed = true
		level.add_trap(t)
		candidates.remove_at(pick)
