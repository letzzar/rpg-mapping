class_name EstGeneratorG3
extends RefCounted
## Estancia en blanco, EST G3 (PROYECTO §6.5 y §6.7, editor de estancias E2).
##
## Base de las estancias hechas a mano: el DM crea una estancia vacía de un
## tamaño y una rejilla y la edita; cada edición es un delta sobre este código
## (§6.7). Una estancia hecha a mano = código EST G3 + deltas (lo que usará E3
## para el id corto y el código para compartir).
##
## NO sustituye a EST G1 (estancia aislada amueblada) ni a EST G2 (estancia de
## un edificio): es otro generador de la misma escala (clave EST-G3).
##
## Código: RPGM1-<SIS>-EST-G3-<PARAMS>-<SEED>-<CRC> (ParamSchemaRegistry.est_g3:
## width, height, grid, room_type). LA SEMILLA NO SE USA: el generador no tiene
## azar y la salida solo depende de PARAMS. El código canónico que emite la app
## lleva la semilla 0: RPGM1-<SIS>-EST-G3-<PARAMS>-0-<CRC> (canonical_code()).
## Un código con otra semilla es válido y da el mismo mapa, pero no es el
## canónico (para E3, dos códigos con el mismo contenido deben ser el mismo).
##
## Mapa (coherente con EST G1, para que se vea igual en 2D y 3D):
## - (width+2)×(height+2): interior width×height de suelo, zona `room_type`
##   (por defecto "room", el tipo de sala de MAZ), desde (1, 1);
## - anillo exterior de muro macizo (Terrain.WALL);
## - UNA puerta en el centro de la pared de abajo: arista KIND_DOOR entre la
##   casilla de entrada E = (1 + (width−1)/2, height) y el rellano
##   R = (E.x, height+1), que pasa a suelo con zona KIND_ENTRANCE (como la
##   primera puerta de EST G1). Las demás aristas entre R y la estancia (en hex
##   R toca dos o tres casillas de la estancia) llevan muro fino, también como
##   en G1. La entrada es la raíz de la conectividad y donde salen las fichas.
##   (x, y+1) es vecina de (x, y) en las tres rejillas (cuadrada, odd-q y
##   odd-r), así que la puerta existe siempre.
## - Sin objetos, escaleras ni hijos. Ids: estancia 1, entrada 2.
##
## Coste: O(width × height) (rellenar terreno y zona); sin Rng.
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA EXIGE GEN NUEVO (EST G4) y conservar
## este en core/gen/est/legacy/: las estancias guardadas son este código +
## deltas, y los deltas se reaplican sobre esta salida exacta.

const SCALE: String = "EST"
const GEN: int = 3
## Semilla del código canónico (la salida no depende de ella).
const CANONICAL_SEED: int = 0


## Parámetros resueltos (campos del esquema EST G3).
class Params:
	extends RefCounted
	var width: int = 9
	var height: int = 7
	var grid_kind: String = "square"
	var room_type: String = MapRoom.KIND_ROOM


## Punto de entrada registrado en GeneratorRegistry. `_rng` no se usa.
static func generate(code: SeedCode, _profile: SystemProfile, _rng: Rng) -> MapDocument:
	return generate_blank(params_from(code))


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var width: int = code.params["width"]
	var height: int = code.params["height"]
	var grid_kind: String = code.params["grid"]
	var room_type: String = code.params["room_type"]
	p.width = width
	p.height = height
	p.grid_kind = grid_kind
	p.room_type = room_type
	return p


## Código canónico (semilla 0) de una estancia en blanco; "" si algún valor
## no cabe en el esquema. `room_type` = "" deja el defecto.
static func canonical_code(system: String, width: int, height: int, grid_kind: String, room_type: String = "") -> String:
	var params: Dictionary = {"width": width, "height": height, "grid": grid_kind}
	if not room_type.is_empty():
		params["room_type"] = room_type
	var sc: SeedCode = SeedCode.create(system, SCALE, GEN, params, CANONICAL_SEED)
	if not sc.is_valid():
		return ""
	return sc.encode()


## Casilla de la estancia junto a la puerta (la entrada) y rellano.
static func entry_cell(width: int, height: int) -> Vector2i:
	return Vector2i(1 + (width - 1) / 2, height)


static func landing_cell(width: int, height: int) -> Vector2i:
	return Vector2i(1 + (width - 1) / 2, height + 1)


## Estancia en blanco (pura, sin azar).
static func generate_blank(p: Params) -> MapDocument:
	var doc: MapDocument = MapDocument.create(p.grid_kind, p.width + 2, p.height + 2)
	if doc == null:
		return null
	var level: MapLevel = doc.level(0)
	var grid: GridGeometry = level.grid
	level.fill_terrain(Terrain.WALL)
	var zone: MapRoom = MapRoom.make(doc.allocate_id(), p.room_type)
	level.add_room(zone)
	for y: int in range(1, p.height + 1):
		for x: int in range(1, p.width + 1):
			var c: Vector2i = Vector2i(x, y)
			level.set_terrain(c, Terrain.FLOOR)
			level.set_room_id(c, zone.id)
	var entry: Vector2i = entry_cell(p.width, p.height)
	var landing: Vector2i = landing_cell(p.width, p.height)
	var dir: int = grid.direction_between(entry, landing)
	if dir < 0 or dir >= grid.edge_direction_count():
		return null
	var entrance: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_ENTRANCE)
	level.add_room(entrance)
	level.set_terrain(landing, Terrain.FLOOR)
	level.set_room_id(landing, entrance.id)
	level.set_edge(entry, dir, MapEdge.make(MapEdge.KIND_DOOR))
	# Muro fino entre el rellano y el resto de casillas de la estancia que toca
	# (en orden fijo de direcciones), como en EstGeneratorG1._add_doors.
	var back: int = grid.opposite(dir)
	for e: int in grid.edge_direction_count():
		if e == back:
			continue
		var m: Vector2i = grid.neighbor(landing, e)
		if grid.in_bounds(m) and level.get_room_id(m) == zone.id:
			level.set_edge(landing, e, MapEdge.make(MapEdge.KIND_WALL))
	return doc
