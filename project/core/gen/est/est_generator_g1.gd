class_name EstGeneratorG1
extends RefCounted
## Generador de estancias EST, versión G1 (PROYECTO §6.5, ADR 023).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en EstFurnisherG1 o en los
## datos data/objects, data/rooms, data/styles) EXIGE GEN NUEVO: copiar a
## core/gen/est/legacy/, registrar G2 y añadir seeds doradas nuevas.
##
## Jerarquía de semillas (§5.2, criterio de F3): toda la estancia sale de UN
## Rng. Aislada, es Rng.new(semilla del código); como hija de un edificio será
## Rng.new(SplitMix64.hash64(semilla_edificio, "EST", id_estable)) y EDI
## llamará a generate_room() (o a EstFurnisherG1.furnish() para amueblar un
## recinto suyo). Hijos:
##   fork("shape", 0)    forma (esquina recortada de la L)
##   fork("doors", 0)    puertas
##   fork("furnish", 0)  mobiliario (EstFurnisherG1)
##
## Mapa: la estancia (interior w×h) rodeada por un anillo de muro macizo
## (Terrain.WALL); mapa de (w+2)×(h+2). Cada puerta es una arista entre una
## casilla de la estancia ("entrada") y una casilla del anillo que pasa a
## suelo ("rellano": zona entrance la primera, exit las demás); las demás
## aristas entre el rellano y la estancia llevan muro fino (en hex un rellano
## toca dos casillas de la estancia).

const SCALE: String = "EST"
const GEN: int = 1

## Interior (ancho × alto) de cada tamaño, por índice de EstData.SIZE_IDS.
const SIZE_DIMS: Array[Vector2i] = [Vector2i(6, 5), Vector2i(9, 7), Vector2i(13, 10)]
const SHAPES: PackedStringArray = ["rect", "l_shape"]


## Parámetros resueltos (campos del esquema EST G1).
class Params:
	extends RefCounted
	var room_type: String = "tavern"
	var grid_kind: String = "square"
	## "auto", "small", "medium" o "large".
	var size_id: String = "auto"
	var style: String = "human"
	var shape: String = "rect"
	var doors: int = 1
	var clutter: int = 5


## Punto de entrada registrado en GeneratorRegistry.
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	return generate_room(params_from(code), rng)


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var room_type: String = code.params["room_type"]
	var grid_kind: String = code.params["grid"]
	var size_id: String = code.params["size"]
	var style: String = code.params["style"]
	var shape: String = code.params["shape"]
	var doors: int = code.params["doors"]
	var clutter: int = code.params["clutter"]
	p.room_type = room_type
	p.grid_kind = grid_kind
	p.size_id = size_id
	p.style = style
	p.shape = shape
	p.doors = doors
	p.clutter = clutter
	return p


## Interior de la estancia; "auto" usa el tamaño típico del tipo.
static func interior_size(p: Params) -> Vector2i:
	var sid: String = p.size_id
	if sid == "auto":
		var rt: EstData.RoomType = EstData.load_default().room_type(p.room_type)
		sid = rt.auto_size if rt != null else "medium"
	var i: int = maxi(0, EstData.SIZE_IDS.find(sid))
	return SIZE_DIMS[i]


## Estancia completa a partir de sus parámetros y su Rng (pura).
static func generate_room(p: Params, rng: Rng) -> MapDocument:
	var dims: Vector2i = interior_size(p)
	var doc: MapDocument = MapDocument.create(p.grid_kind, dims.x + 2, dims.y + 2)
	if doc == null:
		return null
	var level: MapLevel = doc.level(0)
	level.fill_terrain(Terrain.WALL)
	var room_cells: Array[Vector2i] = _shape_cells(dims, p.shape, rng.fork("shape", 0))
	var zone: MapRoom = MapRoom.make(doc.allocate_id(), p.room_type)
	level.add_room(zone)
	for c: Vector2i in room_cells:
		level.set_terrain(c, Terrain.FLOOR)
		level.set_room_id(c, zone.id)
	var entries: Array[Vector2i] = _add_doors(doc, level, room_cells, p.doors, rng.fork("doors", 0))
	EstFurnisherG1.furnish(doc, 0, room_cells, entries, p.room_type, p.style, p.clutter, rng.fork("furnish", 0))
	return doc


## Casillas de la estancia en orden por filas: rectángulo interior (desde
## (1, 1)) o "L" (se recorta un rectángulo de w/2 × h/2 en una esquina al azar).
static func _shape_cells(dims: Vector2i, shape: String, rng: Rng) -> Array[Vector2i]:
	var cut_min: Vector2i = Vector2i(1, 1)
	var cut_max: Vector2i = Vector2i(0, 0)
	if shape == "l_shape":
		var corner: int = rng.pick_index(4)
		var cut: Vector2i = Vector2i(dims.x / 2, dims.y / 2)
		var x0: int = 1 if corner == 0 or corner == 3 else dims.x + 1 - cut.x
		var y0: int = 1 if corner == 0 or corner == 1 else dims.y + 1 - cut.y
		cut_min = Vector2i(x0, y0)
		cut_max = Vector2i(x0 + cut.x - 1, y0 + cut.y - 1)
	var out: Array[Vector2i] = []
	for y: int in range(1, dims.y + 1):
		for x: int in range(1, dims.x + 1):
			var in_cut: bool = x >= cut_min.x and x <= cut_max.x and y >= cut_min.y and y <= cut_max.y
			if not in_cut:
				out.append(Vector2i(x, y))
	return out


## Pone hasta `count` puertas (al menos una) y devuelve las casillas de
## entrada. Candidatas: (casilla de la estancia, dirección) cuya vecina es
## muro; ninguna entrada a distancia <= 1 de otra ni rellano a distancia <= 1
## de otro.
static func _add_doors(doc: MapDocument, level: MapLevel, room_cells: Array[Vector2i], count: int, rng: Rng) -> Array[Vector2i]:
	var grid: GridGeometry = level.grid
	var entries: Array[Vector2i] = []
	var landings: Array[Vector2i] = []
	for k: int in maxi(1, count):
		var cands: Array[Vector3i] = []
		for c: Vector2i in room_cells:
			if _near_any(grid, c, entries):
				continue
			for d: int in grid.edge_direction_count():
				var n: Vector2i = grid.neighbor(c, d)
				if not grid.in_bounds(n) or level.get_terrain(n) != Terrain.WALL:
					continue
				if _near_any(grid, n, landings):
					continue
				cands.append(Vector3i(c.x, c.y, d))
		if cands.is_empty():
			break
		var pick: Vector3i = cands[rng.pick_index(cands.size())]
		var entry: Vector2i = Vector2i(pick.x, pick.y)
		var landing: Vector2i = grid.neighbor(entry, pick.z)
		var zone: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_ENTRANCE if k == 0 else MapRoom.KIND_EXIT)
		level.add_room(zone)
		level.set_terrain(landing, Terrain.FLOOR)
		level.set_room_id(landing, zone.id)
		level.set_edge(entry, pick.z, MapEdge.make(MapEdge.KIND_DOOR))
		var back: int = grid.opposite(pick.z)
		for e: int in grid.edge_direction_count():
			if e == back:
				continue
			var m: Vector2i = grid.neighbor(landing, e)
			if grid.in_bounds(m) and room_cells.has(m):
				level.set_edge(landing, e, MapEdge.make(MapEdge.KIND_WALL))
		entries.append(entry)
		landings.append(landing)
	return entries


static func _near_any(grid: GridGeometry, c: Vector2i, others: Array[Vector2i]) -> bool:
	for o: Vector2i in others:
		if grid.distance(c, o) <= 1:
			return true
	return false
