class_name AreaTemplate
extends RefCounted
## Casillas que cubre una plantilla de área (PROYECTO §8 y §10.3). La geometría
## de cada plantilla es dato del perfil (SystemProfile.AreaTemplateSpec,
## area_templates[] en data/systems/*.json); aquí no se pregunta nunca por el
## sistema.
##
## REGLAS COMUNES
## - Distancias: con las reglas de movimiento del perfil (como
##   MovementCost.measure_ft: diagonales de diagonal_ft o de la variante de
##   mesa, pasos hex de hex_step_ft). Así la plantilla coincide con la regla de
##   medir: si la regla marca 20 ft hasta una casilla, una esfera de 20 ft la
##   cubre. En 5e (diagonal 5 ft) los círculos salen cuadrados; en PF2e
##   (5/10) salen octógonos, como en sus diagramas.
## - Casilla dentro: el tamaño medido hasta la casilla es <= size_ft; en conos
##   y líneas, además, el CENTRO de la casilla está dentro del ángulo o de la
##   franja (bordes incluidos: un empate cuenta como dentro, simétrico).
## - Sin float: ángulos y anchuras se comparan en la red entera de
##   GridGeometry.center_lattice() (productos escalar y vectorial al cuadrado,
##   sin raíces), así que el resultado es idéntico en escritorio y web.
##
## FORMAS
## - circle (esfera, cilindro, explosión): con origin = "corner", centro en la
##   esquina superior izquierda de `origin` (intersección de la cuadrícula); la
##   distancia a una casilla es la del camino que sale de la esquina y entra en
##   ella (la primera diagonal ya cuenta). Con "cell", centro en la casilla.
## - cone: eje del centro de `origin` al centro de `toward`; vértice donde el
##   eje sale de la casilla de origen (mitad del borde si apunta en
##   ortogonal, esquina si apunta en diagonal: el cono "sale" del espacio de
##   la criatura); anchura a cada distancia del vértice = cone_width_pct % de
##   esa distancia (100 = la anchura iguala la distancia, 200 = cuarto de
##   círculo de 90°); longitud medida con el movimiento desde la casilla de
##   origen (en diagonal coincide con medir desde la esquina). Sin la
##   casilla de origen.
## - line: desde el centro de `origin` hacia `toward`, franja de anchura
##   line_width_ft centrada en el eje; longitud medida con el movimiento. Sin
##   la casilla de origen.
## - square (cubo): bloque de ceil(size/cell_ft) casillas de lado con `origin`
##   arriba a la izquierda (como GridGeometry.footprint).
## - emanation: casillas a <= size_ft de alguna casilla de la huella
##   (`origin_cells`; vacío = solo `origin`); la huella entra según
##   includes_origin.
## En conos y líneas se excluyen también las casillas de `origin_cells` (la
## criatura que lanza no está en su propio cono).
##
## HEX (aproximación): no hay intersecciones de 4 casillas, así que los
## círculos se centran siempre en una casilla (radio r en pasos hex =
## hexágono de 3r² + 3r + 1 casillas). El "cubo" es el hexágono de radio
## lado/2 centrado en `origin` (área parecida: lado 2 -> 7 hex frente a 4
## casillas, lado 6 -> 37 frente a 36). Conos y líneas usan la geometría
## euclídea exacta de los centros.
##
## Coste: O(R²) casillas examinadas, R = alcance en casillas (O(R²·|huella|)
## en emanaciones).

## Alcance máximo en casillas (1280 ft con casillas de 5 ft); más allá no se
## cubre nada. Con _DIR_LIMIT acota los factores de conos y líneas por debajo
## de 2^46 (ver _mul_gt).
const MAX_REACH_CELLS: int = 256
## Componente máxima de la dirección de conos y líneas en la red entera; si
## `toward` está más lejos (más de 256 casillas), la dirección se reescala con
## redondeo entero (error < 0,1°).
const _DIR_LIMIT: int = 512


## Casillas cubiertas por la plantilla `template_id` del perfil, dentro del
## mapa, en orden de índice (por filas) y sin repetir. `origin`: casilla de
## origen (o cuya esquina superior izquierda es el centro, en círculos
## "corner"); `toward`: casilla a la que apuntan conos y líneas (si es
## `origin`, no hay dirección y sale vacío); `size_ft`: radio, lado o
## longitud; `origin_cells`: huella de la criatura (emanaciones). Plantilla
## desconocida o size_ft <= 0 -> vacío.
static func cells(profile: SystemProfile, grid: GridGeometry, template_id: String, origin: Vector2i, toward: Vector2i, size_ft: int, origin_cells: Array[Vector2i] = [], diagonal_variant: String = "") -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var spec: SystemProfile.AreaTemplateSpec = profile.area_template(template_id)
	if spec == null or size_ft <= 0 or grid.cell_count() <= 0:
		return out
	var patterns: Array[PackedInt32Array] = _patterns(profile, diagonal_variant)
	var reach: int = _reach_cells(patterns, size_ft)
	var sources: Array[Vector2i] = []
	sources.append_array(origin_cells)
	if sources.is_empty():
		sources.append(origin)
	match spec.shape:
		SystemProfile.SHAPE_CIRCLE:
			if spec.origin == SystemProfile.ORIGIN_CORNER and grid.kind == GridGeometry.KIND_SQUARE:
				return _corner_circle(grid, patterns, origin, size_ft, reach)
			var center: Array[Vector2i] = [origin]
			return _within(grid, patterns, center, size_ft, reach, true)
		SystemProfile.SHAPE_EMANATION:
			return _within(grid, patterns, sources, size_ft, reach, spec.includes_origin)
		SystemProfile.SHAPE_SQUARE:
			return _square(profile, grid, origin, size_ft)
		SystemProfile.SHAPE_CONE, SystemProfile.SHAPE_LINE:
			return _directional(profile, grid, patterns, spec, origin, toward, size_ft, reach, sources)
	return out


# --- Interno ----------------------------------------------------------------

static func _patterns(profile: SystemProfile, diagonal_variant: String) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for k: int in GridGeometry.STEP_KIND_COUNT:
		out.append(profile.step_pattern(k, diagonal_variant))
	return out


## Coste en pies de `counts[k]` pasos de cada tipo (como MovementCost.measure_ft).
static func _cost(patterns: Array[PackedInt32Array], counts: PackedInt32Array) -> int:
	var total: int = 0
	for k: int in GridGeometry.STEP_KIND_COUNT:
		var p: PackedInt32Array = patterns[k]
		for j: int in counts[k]:
			total += p[j % p.size()]
	return total


## Pasos máximos que caben en size_ft (todo paso cuesta al menos el más
## barato de los patrones), acotado a MAX_REACH_CELLS.
static func _reach_cells(patterns: Array[PackedInt32Array], size_ft: int) -> int:
	var cheapest: int = 1 << 30
	for p: PackedInt32Array in patterns:
		for c: int in p:
			cheapest = mini(cheapest, c)
	return mini(size_ft / maxi(1, cheapest), MAX_REACH_CELLS)


## Rectángulo [x0, x1] × [y0, y1] recortado al mapa.
static func _box(grid: GridGeometry, x0: int, y0: int, x1: int, y1: int) -> Rect2i:
	var a: Vector2i = Vector2i(maxi(0, x0), maxi(0, y0))
	var b: Vector2i = Vector2i(mini(grid.width - 1, x1), mini(grid.height - 1, y1))
	return Rect2i(a, b - a + Vector2i.ONE)


static func _corner_circle(grid: GridGeometry, patterns: Array[PackedInt32Array], vertex: Vector2i, size_ft: int, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var box: Rect2i = _box(grid, vertex.x - reach, vertex.y - reach, vertex.x + reach - 1, vertex.y + reach - 1)
	for y: int in range(box.position.y, box.end.y):
		var j: int = y - vertex.y if y >= vertex.y else vertex.y - 1 - y
		for x: int in range(box.position.x, box.end.x):
			var i: int = x - vertex.x if x >= vertex.x else vertex.x - 1 - x
			var diag: int = mini(i, j) + 1
			var counts: PackedInt32Array = PackedInt32Array([absi(i - j), diag, 0])
			if _cost(patterns, counts) <= size_ft:
				out.append(Vector2i(x, y))
	return out


static func _within(grid: GridGeometry, patterns: Array[PackedInt32Array], sources: Array[Vector2i], size_ft: int, reach: int, include_sources: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo: Vector2i = sources[0]
	var hi: Vector2i = sources[0]
	var is_source: Dictionary[Vector2i, bool] = {}
	for s: Vector2i in sources:
		lo = Vector2i(mini(lo.x, s.x), mini(lo.y, s.y))
		hi = Vector2i(maxi(hi.x, s.x), maxi(hi.y, s.y))
		is_source[s] = true
	# Cada paso (también en hex, en offset) cambia x e y como mucho en 1.
	var box: Rect2i = _box(grid, lo.x - reach, lo.y - reach, hi.x + reach, hi.y + reach)
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var c: Vector2i = Vector2i(x, y)
			if is_source.has(c):
				if include_sources:
					out.append(c)
				continue
			for s: Vector2i in sources:
				if grid.distance(s, c) <= reach and _cost(patterns, grid.step_counts(s, c)) <= size_ft:
					out.append(c)
					break
	return out


static func _square(profile: SystemProfile, grid: GridGeometry, origin: Vector2i, size_ft: int) -> Array[Vector2i]:
	var side: int = mini(MovementCost.ft_to_cells(profile, size_ft), 2 * MAX_REACH_CELLS)
	if grid.kind != GridGeometry.KIND_SQUARE:
		return grid.cells_in_radius(origin, side / 2)
	var out: Array[Vector2i] = []
	var box: Rect2i = _box(grid, origin.x, origin.y, origin.x + side - 1, origin.y + side - 1)
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			out.append(Vector2i(x, y))
	return out


static func _directional(profile: SystemProfile, grid: GridGeometry, patterns: Array[PackedInt32Array], spec: SystemProfile.AreaTemplateSpec, origin: Vector2i, toward: Vector2i, size_ft: int, reach: int, excluded: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if toward == origin:
		return out
	var w: Vector2i = grid.lattice_weights()
	var k: int = w.x * w.y
	var a: Vector2i = grid.center_lattice(origin)
	var dir: Vector2i = _reduce(grid.center_lattice(toward) - a)
	var dir_len2: int = w.x * dir.x * dir.x + w.y * dir.y * dir.y
	var is_cone: bool = spec.shape == SystemProfile.SHAPE_CONE
	# Vértice del cono: donde el eje sale de la casilla de origen (borde en
	# ortogonal, esquina en diagonal). La casilla es la región de puntos P con
	# P·N <= |N|²/2 = 2 para cada vecino por arista N, así que el vértice es
	# a + dir·2/m con m = max(dir·N). Se trabaja escalado por m (enteros).
	var m: int = 1
	if is_cone:
		m = 0
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.center_lattice(grid.neighbor(origin, d)) - a
			m = maxi(m, w.x * dir.x * n.x + w.y * dir.y * n.y)
	var shift: Vector2i = 2 * dir if is_cone else Vector2i.ZERO
	var skip: Dictionary[Vector2i, bool] = {origin: true}
	for e: Vector2i in excluded:
		skip[e] = true
	var box: Rect2i = _box(grid, origin.x - reach, origin.y - reach, origin.x + reach, origin.y + reach)
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var c: Vector2i = Vector2i(x, y)
			if skip.has(c):
				continue
			var rel: Vector2i = grid.center_lattice(c) - a
			# Vector del vértice al centro de la casilla, escalado por m.
			var vx: int = m * rel.x - shift.x
			var vy: int = m * rel.y - shift.y
			var dot: int = w.x * vx * dir.x + w.y * vy * dir.y
			if dot <= 0:
				continue
			if grid.distance(origin, c) > reach or _cost(patterns, grid.step_counts(origin, c)) > size_ft:
				continue
			# |v × dir| en la métrica de la red = √(w.x·w.y)·|vx·dir.y − vy·dir.x|.
			var cross: int = absi(vx * dir.y - vy * dir.x)
			if is_cone:
				# Semiancho/distancia <= pct/200  <=>  200·√k·|cross| <= pct·dot.
				var lhs: int = 200 * cross
				if _mul_gt(k * lhs, lhs, spec.cone_width_pct * dot, spec.cone_width_pct * dot):
					continue
			else:
				# Distancia al eje = √k·|cross|/|dir| medias casillas = ·cell_ft/2
				# pies; dentro si <= line_width_ft/2.
				var lhs2: int = cross * profile.cell_ft
				if _mul_gt(k * lhs2, lhs2, spec.line_width_ft * spec.line_width_ft, dir_len2):
					continue
			out.append(c)
	return out


## a·b > c·d sin desbordar, para enteros >= 0 menores que 2^46 (productos de
## hasta 2^92, en tres miembros de 31 bits).
static func _mul_gt(a: int, b: int, c: int, d: int) -> bool:
	var p: PackedInt64Array = _mul_wide(a, b)
	var q: PackedInt64Array = _mul_wide(c, d)
	for i: int in [2, 1, 0]:
		if p[i] != q[i]:
			return p[i] > q[i]
	return false


static func _mul_wide(a: int, b: int) -> PackedInt64Array:
	const MASK: int = (1 << 31) - 1
	var ah: int = a >> 31
	var al: int = a & MASK
	var bh: int = b >> 31
	var bl: int = b & MASK
	var lo: int = al * bl
	var mid: int = ah * bl + al * bh + (lo >> 31)
	return PackedInt64Array([lo & MASK, mid & MASK, ah * bh + (mid >> 31)])

## Dirección dividida por su mcd y, si aún es grande, reescalada a
## componentes <= _DIR_LIMIT (acota los productos de _directional).
static func _reduce(d: Vector2i) -> Vector2i:
	var g: int = _gcd(absi(d.x), absi(d.y))
	if g > 1:
		d = Vector2i(d.x / g, d.y / g)
	var m: int = maxi(absi(d.x), absi(d.y))
	if m > _DIR_LIMIT:
		d = Vector2i(GridGeometry.round_div(d.x * _DIR_LIMIT, m), GridGeometry.round_div(d.y * _DIR_LIMIT, m))
	return d


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = a % b
		a = b
		b = t
	return a
