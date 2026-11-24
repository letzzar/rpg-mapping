class_name MapLevel
extends RefCounted
## Un nivel (planta) de un MapDocument. Todos los niveles comparten rejilla y
## tamaño (simplifica apilar plantas en 3D y las escaleras).
##
## Capas por casilla (índice = GridGeometry.index_of(), orden por filas):
## - terrain: un byte por casilla (Terrain.*).
## - room_ids: id de la sala/zona de cada casilla (0 = ninguna).
## Aristas (ADR 018): muros finos, puertas y vanos en un mapa disperso
## edge_id -> valor MapEdge; las aristas libres no se guardan.
## Listas ordenadas por id: rooms, objects, stairs, traps.
## Niebla de guerra (sesión): casillas exploradas por "observador".
##
## Los métodos set_* devuelven el valor anterior para que los comandos puedan
## deshacer. Ninguno emite señales: tras modificar, el comando llama a
## MapDocument.notify_changed(). Las vistas NO deben llamar a los set_*.

var grid: GridGeometry
var terrain: PackedByteArray = PackedByteArray()
var room_ids: PackedInt32Array = PackedInt32Array()
var rooms: Array[MapRoom] = []
var objects: Array[MapObject] = []
var stairs: Array[MapStair] = []
var traps: Array[MapTrap] = []

var _edges: Dictionary[int, int] = {}
## Observador ("party", id de jugador…) -> 1 byte por casilla (1 = explorada).
var _fog: Dictionary[String, PackedByteArray] = {}


func _init(p_grid: GridGeometry) -> void:
	grid = p_grid
	terrain.resize(grid.cell_count())
	terrain.fill(Terrain.VOID)
	room_ids.resize(grid.cell_count())
	room_ids.fill(0)


# --- Terreno ----------------------------------------------------------------

## Terreno de la casilla; Terrain.VOID si está fuera del mapa.
func get_terrain(cell: Vector2i) -> int:
	var i: int = grid.index_of(cell)
	return terrain[i] if i >= 0 else Terrain.VOID


## Cambia el terreno y devuelve el anterior (-1 si la casilla está fuera o el
## tipo no es válido; entonces no cambia nada).
func set_terrain(cell: Vector2i, t: int) -> int:
	var i: int = grid.index_of(cell)
	if i < 0 or not Terrain.is_valid(t):
		return -1
	var old: int = terrain[i]
	terrain[i] = t
	return old


func fill_terrain(t: int) -> void:
	if Terrain.is_valid(t):
		terrain.fill(t)


# --- Aristas ----------------------------------------------------------------

## Valor MapEdge de la arista entre `cell` y su vecina en `dir`
## (dir < grid.edge_direction_count()).
func get_edge(cell: Vector2i, dir: int) -> int:
	return get_edge_by_id(grid.edge_id(cell, dir))


## Pone la arista y devuelve el valor anterior (-1 si el valor no es válido o
## la arista no toca el mapa; entonces no cambia nada). MapEdge.NONE la borra.
func set_edge(cell: Vector2i, dir: int, value: int) -> int:
	return set_edge_by_id(grid.edge_id(cell, dir), value)


func get_edge_by_id(id: int) -> int:
	return _edges.get(id, MapEdge.NONE)


func set_edge_by_id(id: int, value: int) -> int:
	if not MapEdge.is_valid(value) or not grid.edge_touches_map(id):
		return -1
	var old: int = get_edge_by_id(id)
	if value == MapEdge.NONE:
		_edges.erase(id)
	else:
		_edges[id] = value
	return old


## Ids de las aristas no libres, ordenados (determinista).
func edge_ids() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for k: int in _edges.keys():
		out.append(k)
	out.sort()
	return out


func edge_count() -> int:
	return _edges.size()


# --- Salas ------------------------------------------------------------------

func get_room_id(cell: Vector2i) -> int:
	var i: int = grid.index_of(cell)
	return room_ids[i] if i >= 0 else 0


## Asigna la casilla a una sala (0 = ninguna) y devuelve el id anterior (-1 si
## la casilla está fuera).
func set_room_id(cell: Vector2i, room_id: int) -> int:
	var i: int = grid.index_of(cell)
	if i < 0:
		return -1
	var old: int = room_ids[i]
	room_ids[i] = room_id
	return old


func room(id: int) -> MapRoom:
	var k: int = _find_room(id)
	return rooms[k] if k >= 0 else null


## Añade la sala manteniendo el orden por id. false si el id ya existe.
func add_room(r: MapRoom) -> bool:
	if _find_room(r.id) >= 0:
		return false
	var k: int = 0
	while k < rooms.size() and rooms[k].id < r.id:
		k += 1
	rooms.insert(k, r)
	return true


## Quita la sala (no toca room_ids) y la devuelve; null si no existe.
func remove_room(id: int) -> MapRoom:
	var k: int = _find_room(id)
	if k < 0:
		return null
	var r: MapRoom = rooms[k]
	rooms.remove_at(k)
	return r


## Casillas de la sala en orden por filas.
func room_cells(id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in room_ids.size():
		if room_ids[i] == id:
			out.append(grid.cell_at(i))
	return out


# --- Objetos ----------------------------------------------------------------

func object(id: int) -> MapObject:
	var k: int = _find_object(id)
	return objects[k] if k >= 0 else null


func add_object(o: MapObject) -> bool:
	if _find_object(o.id) >= 0:
		return false
	var k: int = 0
	while k < objects.size() and objects[k].id < o.id:
		k += 1
	objects.insert(k, o)
	return true


func remove_object(id: int) -> MapObject:
	var k: int = _find_object(id)
	if k < 0:
		return null
	var o: MapObject = objects[k]
	objects.remove_at(k)
	return o


## Casillas de la huella del objeto (rectángulo size, con ancho y alto
## intercambiados si mira a una dirección impar en la cuadrada). Recortadas
## al mapa, en orden por filas.
func object_cells(o: MapObject) -> Array[Vector2i]:
	var s: Vector2i = o.size
	if grid.edge_direction_count() == 4 and o.facing % 2 == 1:
		s = Vector2i(o.size.y, o.size.x)
	var out: Array[Vector2i] = []
	for y: int in maxi(1, s.y):
		for x: int in maxi(1, s.x):
			var c: Vector2i = o.cell + Vector2i(x, y)
			if grid.in_bounds(c):
				out.append(c)
	return out


## Objetos que ocupan la casilla, por id.
func objects_at(cell: Vector2i) -> Array[MapObject]:
	var out: Array[MapObject] = []
	for o: MapObject in objects:
		if object_cells(o).has(cell):
			out.append(o)
	return out


# --- Escaleras y trampas ----------------------------------------------------

func stair(id: int) -> MapStair:
	for s: MapStair in stairs:
		if s.id == id:
			return s
	return null


func add_stair(s: MapStair) -> bool:
	if stair(s.id) != null:
		return false
	var k: int = 0
	while k < stairs.size() and stairs[k].id < s.id:
		k += 1
	stairs.insert(k, s)
	return true


func remove_stair(id: int) -> MapStair:
	for k: int in stairs.size():
		if stairs[k].id == id:
			var s: MapStair = stairs[k]
			stairs.remove_at(k)
			return s
	return null


func stairs_at(cell: Vector2i) -> Array[MapStair]:
	var out: Array[MapStair] = []
	for s: MapStair in stairs:
		if s.cell == cell:
			out.append(s)
	return out


func trap(id: int) -> MapTrap:
	for t: MapTrap in traps:
		if t.id == id:
			return t
	return null


func add_trap(t: MapTrap) -> bool:
	if trap(t.id) != null:
		return false
	var k: int = 0
	while k < traps.size() and traps[k].id < t.id:
		k += 1
	traps.insert(k, t)
	return true


func remove_trap(id: int) -> MapTrap:
	for k: int in traps.size():
		if traps[k].id == id:
			var t: MapTrap = traps[k]
			traps.remove_at(k)
			return t
	return null


func traps_at(cell: Vector2i) -> Array[MapTrap]:
	var out: Array[MapTrap] = []
	for t: MapTrap in traps:
		if t.cell == cell:
			out.append(t)
	return out


# --- Movimiento y visión (sin reglas del sistema) ---------------------------

const MOVE_PASSABLE: int = 1
const MOVE_DIFFICULT: int = 2

## Máscara por casilla (índice lineal) para el coste de movimiento:
## MOVE_PASSABLE si se puede entrar andando (terreno transitable y ningún
## objeto que bloquee), MOVE_DIFFICULT si es terreno difícil (por el terreno o
## por un objeto). Coste O(casillas + huellas de objetos).
func movement_mask() -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(terrain.size())
	for i: int in terrain.size():
		var t: int = terrain[i]
		var m: int = 0
		if Terrain.is_passable(t):
			m |= MOVE_PASSABLE
		if Terrain.is_difficult(t):
			m |= MOVE_DIFFICULT
		mask[i] = m
	for o: MapObject in objects:
		if not o.blocks_movement and not o.difficult_terrain:
			continue
		for c: Vector2i in object_cells(o):
			var i: int = grid.index_of(c)
			if o.blocks_movement:
				mask[i] = mask[i] & ~MOVE_PASSABLE
			if o.difficult_terrain:
				mask[i] = mask[i] | MOVE_DIFFICULT
	return mask


## true si la arista entre `cell` y su vecina en `dir` impide pasar.
func edge_blocks_movement(cell: Vector2i, dir: int) -> bool:
	return MapEdge.blocks_movement(get_edge(cell, dir))


func edge_blocks_sight(cell: Vector2i, dir: int) -> bool:
	return MapEdge.blocks_sight(get_edge(cell, dir))


## true si el terreno o algún objeto de la casilla tapa la visión.
func cell_blocks_sight(cell: Vector2i) -> bool:
	if Terrain.blocks_sight(get_terrain(cell)):
		return true
	for o: MapObject in objects_at(cell):
		if o.blocks_sight:
			return true
	return false


# --- Niebla de guerra (sesión; lugar previsto, se completa en F2/F4) --------

## Observadores con niebla, ordenados.
func fog_viewers() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: String in _fog.keys():
		out.append(k)
	out.sort()
	return out


## Casillas exploradas por `viewer` (1 byte por casilla; copia).
func explored(viewer: String) -> PackedByteArray:
	if _fog.has(viewer):
		return _fog[viewer].duplicate()
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(grid.cell_count())
	empty.fill(0)
	return empty


func is_explored(viewer: String, cell: Vector2i) -> bool:
	var i: int = grid.index_of(cell)
	return i >= 0 and _fog.has(viewer) and _fog[viewer][i] != 0


## Marca/desmarca y devuelve el estado anterior.
func set_explored(viewer: String, cell: Vector2i, value: bool) -> bool:
	var i: int = grid.index_of(cell)
	if i < 0:
		return false
	if not _fog.has(viewer):
		_fog[viewer] = explored(viewer)
	var fog: PackedByteArray = _fog[viewer]
	var old: bool = fog[i] != 0
	fog[i] = 1 if value else 0
	_fog[viewer] = fog
	return old


func clear_fog(viewer: String) -> void:
	_fog.erase(viewer)


# --- Serialización ----------------------------------------------------------

func content_to_dict() -> Dictionary:
	var edges: Array = []
	for id: int in edge_ids():
		var e: Vector3i = grid.edge_from_id(id)
		edges.append([e.x, e.y, e.z, get_edge_by_id(id)])
	var room_list: Array = []
	for r: MapRoom in rooms:
		room_list.append(r.to_dict())
	var obj_list: Array = []
	for o: MapObject in objects:
		obj_list.append(o.to_dict())
	var stair_list: Array = []
	for s: MapStair in stairs:
		stair_list.append(s.to_dict())
	var trap_list: Array = []
	for t: MapTrap in traps:
		trap_list.append(t.to_dict())
	return {
		"terrain": terrain,
		"room_ids": room_ids,
		"edges": edges,
		"rooms": room_list,
		"objects": obj_list,
		"stairs": stair_list,
		"traps": trap_list,
	}


func fog_to_dict() -> Dictionary:
	var out: Dictionary = {}
	for v: String in fog_viewers():
		out[v] = _fog[v]
	return out


## Rellena el nivel desde content_to_dict() (y fog_to_dict()). Los errores se
## acumulan en `r`.
func load_dicts(r: JsonReader, content: Dictionary, fog: Dictionary) -> void:
	var n: int = grid.cell_count()
	var t_list: PackedInt32Array = r.get_ints(content, "terrain")
	var rid_list: PackedInt32Array = r.get_ints(content, "room_ids")
	if t_list.size() != n or rid_list.size() != n:
		r.fail("capas de tamaño distinto de width*height")
		return
	for i: int in n:
		if not Terrain.is_valid(t_list[i]):
			r.fail("terreno desconocido: %d" % t_list[i])
			return
		terrain[i] = t_list[i]
		room_ids[i] = rid_list[i]
	for item: Variant in r.get_array(content, "edges"):
		var e: Array = r.to_array(item, "edges")
		if e.size() != 4:
			r.fail("arista debe ser [x, y, lado, valor]")
			return
		var cell: Vector2i = Vector2i(r.to_int(e[0], "edges"), r.to_int(e[1], "edges"))
		var side: int = r.to_int(e[2], "edges")
		if side < 0 or side >= grid.edge_direction_count() / 2:
			r.fail("lado de arista no canónico")
			return
		if set_edge(cell, side, r.to_int(e[3], "edges")) < 0:
			r.fail("arista no válida")
			return
	for d: Dictionary in r.get_dicts(content, "rooms"):
		if not add_room(MapRoom.from_dict(r, d)):
			r.fail("id de sala repetido")
	for d: Dictionary in r.get_dicts(content, "objects"):
		if not add_object(MapObject.from_dict(r, d)):
			r.fail("id de objeto repetido")
	for d: Dictionary in r.get_dicts(content, "stairs"):
		if not add_stair(MapStair.from_dict(r, d)):
			r.fail("id de escalera repetido")
	for d: Dictionary in r.get_dicts(content, "traps"):
		if not add_trap(MapTrap.from_dict(r, d)):
			r.fail("id de trampa repetido")
	var viewers: Array = fog.keys()
	viewers.sort()
	for v: Variant in viewers:
		var key: String = r.to_str(v, "fog")
		var bytes: PackedInt32Array = r.get_ints(fog, key)
		if bytes.size() != n:
			r.fail("niebla de tamaño distinto de width*height")
			return
		var fb: PackedByteArray = PackedByteArray()
		fb.resize(n)
		for i: int in n:
			fb[i] = 1 if bytes[i] != 0 else 0
		_fog[key] = fb


func _find_room(id: int) -> int:
	for k: int in rooms.size():
		if rooms[k].id == id:
			return k
	return -1


func _find_object(id: int) -> int:
	for k: int in objects.size():
		if objects[k].id == id:
			return k
	return -1
