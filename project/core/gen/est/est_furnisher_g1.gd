class_name EstFurnisherG1
extends RefCounted
## Amueblado de una estancia, versión G1 (PROYECTO §6.5, ADR 023). Es la API
## que reutilizarán EDI (F3) y, con un GEN nuevo, MAZ: amuebla un conjunto de
## casillas dado de un MapLevel, sin tocar terreno ni aristas.
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en el catálogo, en los tipos
## de estancia o en los estilos) EXIGE SUBIR EL GEN DE EST: copiar a legacy/.
##
## Reglas (todas con enteros, listas en orden fijo y azar solo del Rng):
## 1. Primero los objetos `required` del tipo, en orden; luego opcionales
##    elegidos por peso (peso × % del estilo / 100) hasta
##    round(casillas × clutter / 40), sin pasar de su `max`. Si un opcional no
##    cabe, se descarta para el resto de la estancia.
## 2. Candidatos de un objeto: (casilla de anclaje, orientación) en orden por
##    filas y dirección; se queda con los que caben enteros en la estancia, sin
##    pisar otro objeto ni una casilla de entrada (la de dentro de cada puerta)
##    y cumplen sus etiquetas:
##    - against_wall (contra_pared): alguna casilla tiene fuera de la estancia
##      la vecina de su espalda (dirección opuesta a la orientación);
##    - center (centro): todas las vecinas por arista de su huella están en
##      la estancia;
##    - near:<id> (junto_a): alguna casilla a distancia 1 de un objeto <id> ya
##      colocado (si no hay ninguno, no se coloca).
## 3. Se prueban hasta CANDIDATE_TRIES candidatos al azar (sin repetir). Uno
##    que bloquea el paso solo se acepta si mantiene el PASILLO LIBRE: todas
##    las casillas libres (sin objeto que bloquee) siguen conectadas entre sí
##    y con las entradas, y todo objeto interactuable tiene una casilla libre
##    alcanzable en su huella o junto a ella.
## Coste: O(objetos × (casillas × orientaciones + intentos × casillas)).

const CANDIDATE_TRIES: int = 16
const CLUTTER_DIVISOR: int = 40


## Estado de una estancia en amueblado.
class State:
	extends RefCounted
	var doc: MapDocument
	var level: MapLevel
	var grid: GridGeometry
	var cells: Array[Vector2i] = []
	var in_room: PackedByteArray = PackedByteArray()
	var is_entry: PackedByteArray = PackedByteArray()
	var occupied: PackedByteArray = PackedByteArray()
	var blocked: PackedByteArray = PackedByteArray()
	var entries: PackedInt32Array = PackedInt32Array()
	## id de catálogo -> índices de las casillas de sus objetos colocados.
	var cells_by_id: Dictionary[String, PackedInt32Array] = {}
	## Huellas (índices) de los objetos interactuables colocados.
	var interactive: Array[PackedInt32Array] = []
	var placed: int = 0

	func _init(p_doc: MapDocument, level_index: int, room_cells: Array[Vector2i], entry_cells: Array[Vector2i]) -> void:
		doc = p_doc
		level = p_doc.level(level_index)
		grid = level.grid
		var n: int = grid.cell_count()
		in_room = _zeros(n)
		is_entry = _zeros(n)
		occupied = _zeros(n)
		blocked = _zeros(n)
		for c: Vector2i in room_cells:
			var i: int = grid.index_of(c)
			if i >= 0 and in_room[i] == 0:
				in_room[i] = 1
		# Orden por filas, independiente del orden recibido.
		for i: int in n:
			if in_room[i] == 1:
				cells.append(grid.cell_at(i))
		for c: Vector2i in entry_cells:
			var i: int = grid.index_of(c)
			if i >= 0 and in_room[i] == 1 and is_entry[i] == 0:
				is_entry[i] = 1
		for i: int in n:
			if is_entry[i] == 1:
				entries.append(i)

	static func _zeros(n: int) -> PackedByteArray:
		var a: PackedByteArray = PackedByteArray()
		a.resize(n)
		a.fill(0)
		return a


## Amuebla `room_cells` (deben ser transitables y estar conectadas) del nivel
## `level_index`. `entry_cells`: casillas de la estancia junto a cada puerta
## (quedan libres). Devuelve el nº de objetos colocados (-1 si el tipo de
## estancia o el estilo no existen). Los ids salen de doc.allocate_id().
static func furnish(doc: MapDocument, level_index: int, room_cells: Array[Vector2i], entry_cells: Array[Vector2i],
		room_type_id: String, style_id: String, clutter: int, rng: Rng) -> int:
	var data: EstData = EstData.load_default()
	var catalog: ObjectCatalog = ObjectCatalog.load_default()
	var rt: EstData.RoomType = data.room_type(room_type_id)
	var style: EstData.Style = data.style(style_id)
	if rt == null or style == null or doc.level(level_index) == null:
		return -1
	var st: State = State.new(doc, level_index, room_cells, entry_cells)
	for k: int in rt.required.size():
		_place(st, catalog.entry(rt.required[k]), catalog, style, rng.fork("required", k))
	var target: int = (st.cells.size() * maxi(0, clutter) + CLUTTER_DIVISOR / 2) / CLUTTER_DIVISOR
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(rt.optional_ids.size())
	counts.fill(0)
	var placed_optional: int = 0
	var pick_rng: Rng = rng.fork("optional", 0)
	var attempt: int = 0
	while placed_optional < target:
		var weights: PackedInt32Array = PackedInt32Array()
		var total: int = 0
		for i: int in rt.optional_ids.size():
			var w: int = 0
			if counts[i] < rt.optional_max[i]:
				w = rt.optional_weights[i] * style.weight_factor_pct(rt.optional_ids[i]) / 100
			weights.append(maxi(0, w))
			total += maxi(0, w)
		if total <= 0:
			break
		var choice: int = pick_rng.pick_weighted(weights)
		var e: ObjectCatalog.Entry = catalog.entry(rt.optional_ids[choice])
		if _place(st, e, catalog, style, rng.fork("optional_try", attempt)):
			counts[choice] += 1
			placed_optional += 1
		else:
			# No cabe: no se vuelve a intentar en esta estancia.
			counts[choice] = rt.optional_max[choice]
		attempt += 1
	return st.placed


## Casillas (índices) de la huella del objeto anclado en `cell` con
## orientación `facing`, como MapLevel.object_cells() pero sin recortar;
## vacío si alguna cae fuera del mapa.
static func footprint(grid: GridGeometry, size: Vector2i, cell: Vector2i, facing: int) -> PackedInt32Array:
	var s: Vector2i = size
	if grid.edge_direction_count() == 4 and facing % 2 == 1:
		s = Vector2i(size.y, size.x)
	var out: PackedInt32Array = PackedInt32Array()
	for y: int in s.y:
		for x: int in s.x:
			var i: int = grid.index_of(cell + Vector2i(x, y))
			if i < 0:
				return PackedInt32Array()
			out.append(i)
	return out


static func _place(st: State, e: ObjectCatalog.Entry, catalog: ObjectCatalog, style: EstData.Style, rng: Rng) -> bool:
	if e == null:
		return false
	var cands: Array[Vector3i] = _candidates(st, e)
	for t: int in CANDIDATE_TRIES:
		if cands.is_empty():
			return false
		var k: int = rng.pick_index(cands.size())
		var cand: Vector3i = cands[k]
		cands.remove_at(k)
		var cell: Vector2i = Vector2i(cand.x, cand.y)
		var fp: PackedInt32Array = footprint(st.grid, e.size, cell, cand.z)
		if e.blocks_movement and not _keeps_clearance(st, fp, e.interaction != ""):
			continue
		var o: MapObject = catalog.instantiate(e, st.doc.allocate_id(), cell, cand.z, style.material_for(e.material_class))
		st.level.add_object(o)
		for i: int in fp:
			st.occupied[i] = 1
			if e.blocks_movement:
				st.blocked[i] = 1
		var prev: PackedInt32Array = st.cells_by_id.get(e.id, PackedInt32Array())
		prev.append_array(fp)
		st.cells_by_id[e.id] = prev
		if e.interaction != "":
			st.interactive.append(fp)
		st.placed += 1
		return true
	return false


## (x, y, orientación) que cumplen las reglas baratas (cabe, no pisa nada,
## etiquetas). Orden por filas y dirección.
static func _candidates(st: State, e: ObjectCatalog.Entry) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var grid: GridGeometry = st.grid
	var dirs: int = grid.edge_direction_count()
	var against_wall: bool = e.has_tag(ObjectCatalog.TAG_AGAINST_WALL)
	var center: bool = e.has_tag(ObjectCatalog.TAG_CENTER)
	var near_id: String = e.near_id()
	var near_cells: PackedInt32Array = PackedInt32Array()
	if not near_id.is_empty():
		if not st.cells_by_id.has(near_id):
			return out
		near_cells = st.cells_by_id[near_id]
	for c: Vector2i in st.cells:
		for f: int in dirs:
			var fp: PackedInt32Array = footprint(grid, e.size, c, f)
			if fp.is_empty() or not _fits(st, fp):
				continue
			if against_wall and not _back_to_wall(st, fp, grid.opposite(f)):
				continue
			if center and not _all_inside(st, fp):
				continue
			if not near_id.is_empty() and not _is_near(st, fp, near_cells):
				continue
			out.append(Vector3i(c.x, c.y, f))
	return out


static func _fits(st: State, fp: PackedInt32Array) -> bool:
	for i: int in fp:
		if st.in_room[i] == 0 or st.occupied[i] != 0 or st.is_entry[i] != 0:
			return false
	return true


static func _back_to_wall(st: State, fp: PackedInt32Array, back_dir: int) -> bool:
	for i: int in fp:
		var ni: int = st.grid.index_of(st.grid.neighbor(st.grid.cell_at(i), back_dir))
		if ni < 0 or st.in_room[ni] == 0:
			return true
	return false


static func _all_inside(st: State, fp: PackedInt32Array) -> bool:
	for i: int in fp:
		var c: Vector2i = st.grid.cell_at(i)
		for d: int in st.grid.edge_direction_count():
			var ni: int = st.grid.index_of(st.grid.neighbor(c, d))
			if ni < 0 or st.in_room[ni] == 0:
				return false
	return true


static func _is_near(st: State, fp: PackedInt32Array, near_cells: PackedInt32Array) -> bool:
	for i: int in fp:
		var c: Vector2i = st.grid.cell_at(i)
		for j: int in near_cells:
			if st.grid.distance(c, st.grid.cell_at(j)) <= 1:
				return true
	return false


## ¿Sigue habiendo pasillo libre si se bloquean las casillas `fp`? (regla 3).
static func _keeps_clearance(st: State, fp: PackedInt32Array, interactive: bool) -> bool:
	for i: int in fp:
		st.blocked[i] = 1
	var ok: bool = is_clear(st)
	if ok and interactive:
		ok = _reachable_object(st, fp, _flood(st))
	for i: int in fp:
		st.blocked[i] = 0
	return ok


## Todas las casillas libres conectadas, entradas incluidas, y todos los
## interactuables colocados alcanzables.
static func is_clear(st: State) -> bool:
	var reached: PackedByteArray = _flood(st)
	for i: int in st.cells.size():
		var ci: int = st.grid.index_of(st.cells[i])
		if st.blocked[ci] == 0 and reached[ci] == 0:
			return false
	for fp: PackedInt32Array in st.interactive:
		if not _reachable_object(st, fp, reached):
			return false
	return true


static func _reachable_object(st: State, fp: PackedInt32Array, reached: PackedByteArray) -> bool:
	for i: int in fp:
		if reached[i] != 0:
			return true
		var c: Vector2i = st.grid.cell_at(i)
		for d: int in st.grid.edge_direction_count():
			var ni: int = st.grid.index_of(st.grid.neighbor(c, d))
			if ni >= 0 and reached[ni] != 0 and MapEdge.is_traversable(st.level.get_edge(c, d)):
				return true
	return false


## Casillas libres alcanzables por aristas (sin muro) desde la primera entrada
## (o la primera casilla libre si no hay entradas).
static func _flood(st: State) -> PackedByteArray:
	var grid: GridGeometry = st.grid
	var reached: PackedByteArray = State._zeros(grid.cell_count())
	var start: int = -1
	if not st.entries.is_empty():
		start = st.entries[0]
	else:
		for c: Vector2i in st.cells:
			var i: int = grid.index_of(c)
			if st.blocked[i] == 0:
				start = i
				break
	if start < 0 or st.blocked[start] != 0:
		return reached
	var queue: PackedInt32Array = PackedInt32Array([start])
	reached[start] = 1
	var head: int = 0
	while head < queue.size():
		var ci: int = queue[head]
		head += 1
		var cell: Vector2i = grid.cell_at(ci)
		for d: int in grid.edge_direction_count():
			var ni: int = grid.index_of(grid.neighbor(cell, d))
			if ni < 0 or reached[ni] != 0 or st.in_room[ni] == 0 or st.blocked[ni] != 0:
				continue
			if not MapEdge.is_traversable(st.level.get_edge(cell, d)):
				continue
			reached[ni] = 1
			queue.append(ni)
	return reached
