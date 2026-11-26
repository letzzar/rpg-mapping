class_name FogReveal
extends RefCounted
## Zonas que el DM revela de golpe en el modo proyectado (ADR 039): la sala
## de una casilla o, si no tiene sala (o es una zona exterior enorme), lo que
## se alcanza desde ella sin cruzar muros ni puertas cerradas, con tope.

## Tope de casillas de una zona sin sala (un pasillo largo cabe; un
## asentamiento entero no).
const FLOOD_MAX: int = 400


## Casillas de la zona de `cell` en el nivel, en orden de índice. Vacío si
## la casilla no es transitable o está fuera.
static func region_cells(doc: MapDocument, level_index: int, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lvl: MapLevel = doc.level(level_index)
	var g: GridGeometry = doc.grid
	if lvl == null or not g.in_bounds(cell) or not Terrain.is_passable(lvl.get_terrain(cell)):
		return out
	var rid: int = lvl.get_room_id(cell)
	var r: MapRoom = lvl.room(rid) if rid != 0 else null
	if r != null and not MapRoom.OUTDOOR_KINDS.has(r.kind):
		out = lvl.room_cells(rid)
		# Con sus muros a la vista: las casillas macizas vecinas también.
		return _with_walls(doc, level_index, out)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(g.cell_count())
	var queue: Array[Vector2i] = [cell]
	seen[g.index_of(cell)] = 1
	var head: int = 0
	while head < queue.size() and queue.size() < FLOOD_MAX:
		var c: Vector2i = queue[head]
		head += 1
		# Solo por aristas: en la cuadrada, las diagonales colaban la zona
		# por la esquina de un muro.
		for dir: int in g.edge_direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if not g.in_bounds(n):
				continue
			var ni: int = g.index_of(n)
			if seen[ni] != 0 or not Terrain.is_passable(lvl.get_terrain(n)):
				continue
			if lvl.edge_blocks_movement(c, dir):
				continue
			seen[ni] = 1
			queue.append(n)
	queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return g.index_of(a) < g.index_of(b))
	return _with_walls(doc, level_index, queue)


## Las dos zonas a los lados de una arista (al abrir una puerta).
static func door_cells(doc: MapDocument, level_index: int, edge_id: int) -> Array[Vector2i]:
	var e: Vector3i = doc.grid.edge_from_id(edge_id)
	var a: Vector2i = Vector2i(e.x, e.y)
	var b: Vector2i = doc.grid.neighbor(a, e.z)
	var out: Array[Vector2i] = region_cells(doc, level_index, a)
	for c: Vector2i in region_cells(doc, level_index, b):
		if not out.has(c):
			out.append(c)
	return out


## Añade las casillas no transitables pegadas a la zona (muros gruesos y
## roca del borde), para que se vea su contorno.
static func _with_walls(doc: MapDocument, level_index: int, cells: Array[Vector2i]) -> Array[Vector2i]:
	var lvl: MapLevel = doc.level(level_index)
	var g: GridGeometry = doc.grid
	var mark: PackedByteArray = PackedByteArray()
	mark.resize(g.cell_count())
	for c: Vector2i in cells:
		mark[g.index_of(c)] = 1
	for c: Vector2i in cells:
		for dir: int in g.direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if g.in_bounds(n) and not Terrain.is_passable(lvl.get_terrain(n)):
				mark[g.index_of(n)] = 1
	var out: Array[Vector2i] = []
	for i: int in mark.size():
		if mark[i] != 0:
			out.append(g.cell_at(i))
	return out
