class_name MovementCost
extends RefCounted
## Coste de movimiento y medición según un SystemProfile (PROYECTO §8 y §10.3,
## ADR 020), en las tres rejillas.
##
## Reglas como datos: el coste de cada paso sale del patrón del perfil para su
## TIPO (GridGeometry.STEP_ORTHOGONAL / STEP_DIAGONAL / STEP_HEX; ver
## SystemProfile.step_pattern()). Cada tipo lleva su propio contador, así que
## un patrón alterno (5/10) sigue alternando aunque haya pasos de otro tipo en
## medio. Aquí no se pregunta nunca por el sistema ni por el tipo de rejilla.
##
## Terreno difícil: se aplica al paso que ENTRA en la casilla difícil
## (coste * multiplier_pct / 100 + extra_ft_per_cell), salvo visual_only.
##
## Solo enteros: el resultado es idéntico en todas las plataformas y sirve al
## servidor del DM para validar movimientos (F4).

## Banderas de un paso (path_cost_ft). Sin STEP_DIAGONAL ni STEP_HEX = ortogonal.
const STEP_DIAGONAL: int = 1
const STEP_DIFFICULT: int = 2
const STEP_HEX: int = 4


## Resultado de find_route().
class Route:
	extends RefCounted
	## false si no hay camino (destino fuera, bloqueado o inalcanzable).
	var found: bool = false
	## Casillas desde el origen hasta el destino, ambos incluidos.
	var cells: Array[Vector2i] = []
	## Coste total en pies (-1 si no hay camino).
	var cost_ft: int = -1


## Bandera de paso para un tipo GridGeometry.STEP_* (+ terreno difícil).
static func step_flags(step_kind: int, difficult: bool) -> int:
	var f: int = 0
	if step_kind == GridGeometry.STEP_DIAGONAL:
		f = STEP_DIAGONAL
	elif step_kind == GridGeometry.STEP_HEX:
		f = STEP_HEX
	if difficult:
		f |= STEP_DIFFICULT
	return f


## Tipo GridGeometry.STEP_* codificado en las banderas de un paso.
static func step_kind_of(step: int) -> int:
	if step & STEP_HEX:
		return GridGeometry.STEP_HEX
	if step & STEP_DIAGONAL:
		return GridGeometry.STEP_DIAGONAL
	return GridGeometry.STEP_ORTHOGONAL


## Coste de entrar en una casilla con coste base `base_ft`, difícil o no.
static func difficult_cost(profile: SystemProfile, base_ft: int, difficult: bool) -> int:
	if difficult and not profile.difficult_visual_only:
		return base_ft * profile.difficult_multiplier_pct / 100 + profile.difficult_extra_ft
	return base_ft


## Coste total en pies de una lista de pasos (banderas STEP_*).
## `diagonal_variant` = "" usa movement.diagonal_ft; si no, una de
## movement.diagonal_variants (opción de mesa; si no existe, se usa la normal).
static func path_cost_ft(profile: SystemProfile, steps: PackedInt32Array, diagonal_variant: String = "") -> int:
	var patterns: Array[PackedInt32Array] = _patterns(profile, diagonal_variant)
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var total: int = 0
	for step: int in steps:
		var k: int = step_kind_of(step)
		var p: PackedInt32Array = patterns[k]
		var base: int = p[counts[k] % p.size()]
		counts[k] += 1
		total += difficult_cost(profile, base, (step & STEP_DIFFICULT) != 0)
	return total


## Medición en línea recta de `a` a `b` (regla de medir; sin terreno ni
## muros): pasos del camino más corto de la rejilla, cada tipo con su patrón.
static func measure_ft(profile: SystemProfile, grid: GridGeometry, a: Vector2i, b: Vector2i, diagonal_variant: String = "") -> int:
	var patterns: Array[PackedInt32Array] = _patterns(profile, diagonal_variant)
	var counts: PackedInt32Array = grid.step_counts(a, b)
	var total: int = 0
	for k: int in GridGeometry.STEP_KIND_COUNT:
		var p: PackedInt32Array = patterns[k]
		for j: int in counts[k]:
			total += p[j % p.size()]
	return total


## Pies -> casillas, redondeando hacia arriba (para bandas y velocidad).
static func ft_to_cells(profile: SystemProfile, ft: int) -> int:
	if ft <= 0:
		return 0
	return (ft + profile.cell_ft - 1) / profile.cell_ft


## Banda de alcance de una distancia en pies ("" si el perfil no usa bandas).
static func band_for_ft(profile: SystemProfile, ft: int) -> String:
	return profile.band_for_cells(ft_to_cells(profile, ft))


## Casillas del mapa a <= `ft` pies de `center` medidos con measure_ft()
## (emanaciones, radios de luz), en orden por filas. O(r²).
static func cells_within_ft(profile: SystemProfile, grid: GridGeometry, center: Vector2i, ft: int, diagonal_variant: String = "") -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if ft < 0:
		return out
	var cheapest: int = profile.cell_ft
	for p: PackedInt32Array in _patterns(profile, diagonal_variant):
		for c: int in p:
			cheapest = mini(cheapest, c)
	for c: Vector2i in grid.cells_in_radius(center, ft / maxi(1, cheapest)):
		if measure_ft(profile, grid, center, c, diagonal_variant) <= ft:
			out.append(c)
	return out


## ¿Se puede dar el paso de `from` en la dirección `dir`? `mask` es
## level.movement_mask(). Reglas (ADR 020):
## - El destino debe estar en el mapa y ser transitable.
## - Paso con arista (ortogonal o hex): la arista no debe bloquear
##   (MapEdge.blocks_movement: muro, cualquier puerta cerrada, secreta sin
##   descubrir). El foso (Terrain.PIT) no es transitable.
## - Diagonal (cuadrada): cada rodeo ortogonal (from -> casilla intermedia ->
##   destino) está libre si la intermedia es transitable y ninguna de sus dos
##   aristas bloquea; se exige uno o los dos según
##   profile.diagonal_corner_rule.
static func can_step(profile: SystemProfile, level: MapLevel, mask: PackedByteArray, from: Vector2i, dir: int) -> bool:
	var grid: GridGeometry = level.grid
	var ti: int = grid.index_of(grid.neighbor(from, dir))
	if ti < 0 or (mask[ti] & MapLevel.MOVE_PASSABLE) == 0:
		return false
	var parts: PackedInt32Array = grid.diagonal_components(dir)
	if parts.is_empty():
		return not level.edge_blocks_movement(from, dir)
	var free_sides: int = 0
	for k: int in 2:
		var first: int = parts[k]
		var second: int = parts[1 - k]
		var mid: Vector2i = grid.neighbor(from, first)
		var mi: int = grid.index_of(mid)
		if mi < 0 or (mask[mi] & MapLevel.MOVE_PASSABLE) == 0:
			continue
		if level.edge_blocks_movement(from, first) or level.edge_blocks_movement(mid, second):
			continue
		free_sides += 1
	if profile.diagonal_corner_rule == SystemProfile.CORNER_BOTH_SIDES_FREE:
		return free_sides == 2
	return free_sides >= 1


## Coste en pies de una ruta casilla a casilla sobre un nivel (terreno
## difícil por casilla de destino, muros y puertas). -1 si dos casillas
## consecutivas no son vecinas o algún paso no se puede dar.
static func route_cost_ft(profile: SystemProfile, level: MapLevel, path: Array[Vector2i], diagonal_variant: String = "") -> int:
	var grid: GridGeometry = level.grid
	var mask: PackedByteArray = level.movement_mask()
	var steps: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, path.size()):
		var d: int = grid.direction_between(path[i - 1], path[i])
		if d < 0 or not can_step(profile, level, mask, path[i - 1], d):
			return -1
		var difficult: bool = (mask[grid.index_of(path[i])] & MapLevel.MOVE_DIFFICULT) != 0
		steps.append(step_flags(grid.step_kind(d), difficult))
	return path_cost_ft(profile, steps, diagonal_variant)


## Ruta más barata de `from` a `to` (Dijkstra). El estado incluye la fase de
## cada patrón de coste, así que es exacta también con diagonales alternas.
## Determinista: empates resueltos por índice de estado y vecinos en el orden
## fijo de la rejilla. O(S log S), S = casillas × fases (≤ 2 en los perfiles
## actuales). No tiene en cuenta otros tokens.
static func find_route(profile: SystemProfile, level: MapLevel, from: Vector2i, to: Vector2i, diagonal_variant: String = "") -> Route:
	var route: Route = Route.new()
	var grid: GridGeometry = level.grid
	var target: int = grid.index_of(to)
	if target < 0:
		return route
	var s: SearchState = _search(profile, level, from, target, diagonal_variant, -1)
	if s.goal_state < 0:
		return route
	var cells: Array[Vector2i] = []
	var st: int = s.goal_state
	while st >= 0:
		cells.append(grid.cell_at(st / s.phases))
		st = s.prev[st]
	cells.reverse()
	route.found = true
	route.cells = cells
	route.cost_ft = s.dist[s.goal_state]
	return route


## Coste mínimo en pies desde `from` a cada casilla del nivel (índice lineal),
## -1 si no se alcanza o pasa de `max_ft` (max_ft < 0 = sin límite). Para
## sombrear el alcance de un token en su turno.
static func cost_field(profile: SystemProfile, level: MapLevel, from: Vector2i, diagonal_variant: String = "", max_ft: int = -1) -> PackedInt32Array:
	var grid: GridGeometry = level.grid
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(grid.cell_count())
	out.fill(-1)
	var s: SearchState = _search(profile, level, from, -1, diagonal_variant, max_ft)
	for st: int in s.dist.size():
		var c: int = s.dist[st]
		if c < 0:
			continue
		var ci: int = st / s.phases
		if out[ci] < 0 or c < out[ci]:
			out[ci] = c
	return out


# --- Interno ----------------------------------------------------------------

static func _patterns(profile: SystemProfile, diagonal_variant: String) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for k: int in GridGeometry.STEP_KIND_COUNT:
		out.append(profile.step_pattern(k, diagonal_variant))
	return out


class SearchState:
	extends RefCounted
	var phases: int = 1
	var dist: PackedInt64Array = PackedInt64Array()
	var prev: PackedInt64Array = PackedInt64Array()
	var goal_state: int = -1


## Montículo binario de enteros (mínimo arriba).
class MinHeap:
	extends RefCounted
	var data: PackedInt64Array = PackedInt64Array()

	func is_empty() -> bool:
		return data.is_empty()

	func push(v: int) -> void:
		data.append(v)
		var i: int = data.size() - 1
		while i > 0:
			var p: int = (i - 1) / 2
			if data[p] <= data[i]:
				break
			var tmp: int = data[p]
			data[p] = data[i]
			data[i] = tmp
			i = p

	func pop() -> int:
		var top: int = data[0]
		var last: int = data[data.size() - 1]
		data.resize(data.size() - 1)
		var n: int = data.size()
		if n == 0:
			return top
		data[0] = last
		var i: int = 0
		while true:
			var l: int = 2 * i + 1
			var r: int = l + 1
			var m: int = i
			if l < n and data[l] < data[m]:
				m = l
			if r < n and data[r] < data[m]:
				m = r
			if m == i:
				break
			var tmp: int = data[m]
			data[m] = data[i]
			data[i] = tmp
			i = m
		return top


## Dijkstra sobre estados (casilla, fase). La fase guarda, en base mixta, en
## qué punto de su patrón va cada tipo de paso: fase = Σ dígito_k · radix_k.
## Clave del montículo: coste << 32 | estado (coste < 2^31, estado < 2^32).
static func _search(profile: SystemProfile, level: MapLevel, from: Vector2i, target: int, diagonal_variant: String, max_ft: int) -> SearchState:
	var grid: GridGeometry = level.grid
	var patterns: Array[PackedInt32Array] = _patterns(profile, diagonal_variant)
	var radix: PackedInt32Array = PackedInt32Array()
	var phases: int = 1
	for p: PackedInt32Array in patterns:
		radix.append(phases)
		phases *= p.size()
	var s: SearchState = SearchState.new()
	s.phases = phases
	var n_states: int = grid.cell_count() * phases
	s.dist.resize(n_states)
	s.dist.fill(-1)
	s.prev.resize(n_states)
	s.prev.fill(-1)
	var start: int = grid.index_of(from)
	if start < 0:
		return s
	var mask: PackedByteArray = level.movement_mask()
	var heap: MinHeap = MinHeap.new()
	s.dist[start * phases] = 0
	heap.push(start * phases)
	while not heap.is_empty():
		var key: int = heap.pop()
		var cost: int = key >> 32
		var st: int = key & 0xFFFFFFFF
		if cost != s.dist[st]:
			continue
		var ci: int = st / phases
		if ci == target:
			s.goal_state = st
			break
		var phase: int = st % phases
		var cell: Vector2i = grid.cell_at(ci)
		for d: int in grid.direction_count():
			if not can_step(profile, level, mask, cell, d):
				continue
			var ni: int = grid.index_of(grid.neighbor(cell, d))
			var k: int = grid.step_kind(d)
			var p: PackedInt32Array = patterns[k]
			var digit: int = (phase / radix[k]) % p.size()
			var next_phase: int = phase + ((digit + 1) % p.size() - digit) * radix[k]
			var difficult: bool = (mask[ni] & MapLevel.MOVE_DIFFICULT) != 0
			var nc: int = cost + difficult_cost(profile, p[digit], difficult)
			if max_ft >= 0 and nc > max_ft:
				continue
			var ns: int = ni * phases + next_phase
			if s.dist[ns] < 0 or nc < s.dist[ns]:
				s.dist[ns] = nc
				s.prev[ns] = st
				heap.push((nc << 32) | ns)
	return s
