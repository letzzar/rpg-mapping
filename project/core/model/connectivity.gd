class_name Connectivity
extends RefCounted
## Alcance "se puede llegar" en un MapDocument, a través de todos sus niveles:
## pasos por arista (sin diagonales, criterio conservador) a casillas de
## terreno transitable cuya arista no sea un muro (MapEdge.is_traversable:
## las puertas cuentan aunque estén cerradas, con llave o sin descubrir), y
## saltos por escaleras (MapStair). Es el criterio de "todas las salas
## accesibles desde la entrada" de los generadores (PROYECTO §6.6).
##
## No es la ruta de un token (eso es MovementCost.find_route, donde las
## puertas cerradas bloquean). Coste O(niveles × casillas).


## Una máscara por nivel (1 byte por casilla, 1 = alcanzable) desde `start`
## en el nivel `level_index`. Todo a 0 si el inicio no es transitable.
static func reachable(doc: MapDocument, level_index: int, start: Vector2i) -> Array[PackedByteArray]:
	var grid: GridGeometry = doc.grid
	var n: int = grid.cell_count()
	var levels: int = doc.levels.size()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(levels * n)
	seen.fill(0)
	var si: int = grid.index_of(start)
	var ok: bool = si >= 0 and level_index >= 0 and level_index < levels
	if ok and Terrain.is_passable(doc.levels[level_index].terrain[si]):
		_flood(doc, level_index * n + si, seen)
	var out: Array[PackedByteArray] = []
	for li: int in levels:
		out.append(seen.slice(li * n, (li + 1) * n))
	return out


## Nº de casillas transitables que NO se alcanzan desde `start` (0 = todo el
## documento conectado).
static func unreachable_count(doc: MapDocument, level_index: int, start: Vector2i) -> int:
	var masks: Array[PackedByteArray] = reachable(doc, level_index, start)
	var missing: int = 0
	for li: int in doc.levels.size():
		var terrain: PackedByteArray = doc.levels[li].terrain
		var mask: PackedByteArray = masks[li]
		for i: int in terrain.size():
			if Terrain.is_passable(terrain[i]) and mask[i] == 0:
				missing += 1
	return missing


static func _flood(doc: MapDocument, start_state: int, seen: PackedByteArray) -> void:
	var grid: GridGeometry = doc.grid
	var n: int = grid.cell_count()
	var levels: int = doc.levels.size()
	# Saltos por escalera: estado (nivel*n + casilla) -> estados de destino.
	var jumps: Dictionary[int, PackedInt64Array] = {}
	for li: int in levels:
		for s: MapStair in doc.levels[li].stairs:
			var fi: int = grid.index_of(s.cell)
			var ti: int = grid.index_of(s.to_cell)
			if fi < 0 or ti < 0 or s.to_level < 0 or s.to_level >= levels:
				continue
			var key: int = li * n + fi
			var targets: PackedInt64Array = jumps.get(key, PackedInt64Array())
			targets.append(s.to_level * n + ti)
			jumps[key] = targets
	var queue: PackedInt64Array = PackedInt64Array([start_state])
	seen[start_state] = 1
	var head: int = 0
	while head < queue.size():
		var st: int = queue[head]
		head += 1
		var li: int = st / n
		var level: MapLevel = doc.levels[li]
		var cell: Vector2i = grid.cell_at(st % n)
		for d: int in grid.edge_direction_count():
			var ni: int = grid.index_of(grid.neighbor(cell, d))
			if ni < 0:
				continue
			var ns: int = li * n + ni
			if seen[ns] != 0 or not Terrain.is_passable(level.terrain[ni]):
				continue
			if not MapEdge.is_traversable(level.get_edge(cell, d)):
				continue
			seen[ns] = 1
			queue.append(ns)
		if jumps.has(st):
			for ns2: int in jumps[st]:
				var tl: MapLevel = doc.levels[ns2 / n]
				if seen[ns2] == 0 and Terrain.is_passable(tl.terrain[ns2 % n]):
					seen[ns2] = 1
					queue.append(ns2)
