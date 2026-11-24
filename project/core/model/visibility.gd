class_name Visibility
extends RefCounted
## Línea de visión, iluminación y casillas visibles (PROYECTO §7, ADR 024).
##
## Se calcula en el MODELO, no en las vistas: las tres vistas (2D, 3D y
## 1ª persona) pintan el mismo resultado, y en F4 el servidor del DM filtrará
## con él lo que recibe cada jugador. Todo es aritmética entera sobre la
## rejilla (GridGeometry.line(), simétrica), así que es determinista y da lo
## mismo en escritorio y en web.
##
## Reglas:
## - Una casilla tapa la visión si su terreno u objeto la tapa
##   (MapLevel.cell_blocks_sight). La casilla destino se ve aunque tape (así se
##   ve la cara del muro o la columna); las intermedias no pueden tapar.
## - Entre dos casillas consecutivas de la línea: si comparten arista, una
##   arista que tapa (muro fino, puerta cerrada, secreta) corta la visión. En
##   la cuadrada, un paso diagonal pasa por un vértice: se ve si al menos uno
##   de los dos rodeos ortogonales está libre (misma regla de esquina
##   "any_side_free" que el movimiento por defecto).
## - Luz: cada fuente ilumina en brillante hasta `bright` casillas y en tenue
##   hasta `dim`, siempre con línea de visión desde la casilla de la fuente.
## - Un observador ve una casilla si hay línea de visión, está a `range`
##   casillas como mucho y está iluminada (o el ambiente está iluminado, o la
##   casilla cae dentro de su visión en la oscuridad).

const DARK: int = 0
const DIM: int = 1
const BRIGHT: int = 2

## Alcance máximo por defecto de la vista (casillas). Limita el coste: la
## línea de visión es O(alcance³) por observador.
const DEFAULT_RANGE: int = 24


## Fuente de luz: casilla y radios en casillas.
class LightSource:
	extends RefCounted
	var cell: Vector2i = Vector2i.ZERO
	var bright: int = 0
	var dim: int = 0

	static func make(p_cell: Vector2i, p_bright: int, p_dim: int) -> LightSource:
		var l: LightSource = LightSource.new()
		l.cell = p_cell
		l.bright = p_bright
		l.dim = maxi(p_dim, p_bright)
		return l


## Observador: casillas que ocupa (se ve desde cualquiera), alcance y visión
## en la oscuridad (casillas; 0 = no tiene).
class Viewer:
	extends RefCounted
	var cells: Array[Vector2i] = []
	var range_cells: int = DEFAULT_RANGE
	var darkvision_cells: int = 0


## true si hay línea de visión entre `a` y `b` en el nivel (simétrica).
static func has_los(level: MapLevel, a: Vector2i, b: Vector2i) -> bool:
	return _los(level, sight_mask(level), a, b)


## 1 por casilla que tapa la visión (terreno u objeto). Se calcula una vez por
## consulta grande: MapLevel.cell_blocks_sight recorre todos los objetos.
static func sight_mask(level: MapLevel) -> PackedByteArray:
	var g: GridGeometry = level.grid
	var m: PackedByteArray = PackedByteArray()
	m.resize(g.cell_count())
	for i: int in g.cell_count():
		m[i] = 1 if Terrain.blocks_sight(level.terrain[i]) else 0
	for o: MapObject in level.objects:
		if o.blocks_sight:
			for c: Vector2i in level.object_cells(o):
				var i: int = g.index_of(c)
				if i >= 0:
					m[i] = 1
	return m


static func _blocks(g: GridGeometry, mask: PackedByteArray, c: Vector2i) -> bool:
	var i: int = g.index_of(c)
	return i < 0 or mask[i] != 0


static func _los(level: MapLevel, mask: PackedByteArray, a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	var g: GridGeometry = level.grid
	var path: Array[Vector2i] = g.line(a, b)
	for i: int in range(1, path.size()):
		var p: Vector2i = path[i - 1]
		var q: Vector2i = path[i]
		if not _step_clear(level, mask, p, q):
			return false
		# Las casillas intermedias no pueden tapar; los extremos sí se ven.
		if i < path.size() - 1 and _blocks(g, mask, q):
			return false
	return true


## Paso entre dos casillas vecinas sin atravesar aristas que tapen.
static func _step_clear(level: MapLevel, mask: PackedByteArray, p: Vector2i, q: Vector2i) -> bool:
	var g: GridGeometry = level.grid
	var dir: int = g.direction_between(p, q)
	if dir < 0:
		return false
	if dir < g.edge_direction_count():
		return not level.edge_blocks_sight(p, dir)
	# Diagonal de la cuadrada: pasa por un vértice. Basta un rodeo libre.
	var comps: PackedInt32Array = g.diagonal_components(dir)
	for k: int in 2:
		var first: int = comps[k]
		var second: int = comps[1 - k]
		var mid: Vector2i = g.neighbor(p, first)
		if level.edge_blocks_sight(p, first):
			continue
		if _blocks(g, mask, mid):
			continue
		if level.edge_blocks_sight(mid, second):
			continue
		return true
	return false


## Fuentes de luz de los objetos del nivel, en orden de id.
static func object_lights(level: MapLevel) -> Array[LightSource]:
	var out: Array[LightSource] = []
	for o: MapObject in level.objects:
		if o.light_bright_cells > 0 or o.light_dim_cells > 0:
			out.append(LightSource.make(o.cell, o.light_bright_cells, o.light_dim_cells))
	return out


## Nivel de luz por casilla (DARK/DIM/BRIGHT, índice lineal). Con
## `ambient_lit` todo el mapa está en BRIGHT.
static func light_map(level: MapLevel, lights: Array[LightSource], ambient_lit: bool) -> PackedByteArray:
	var g: GridGeometry = level.grid
	var out: PackedByteArray = PackedByteArray()
	out.resize(g.cell_count())
	out.fill(BRIGHT if ambient_lit else DARK)
	if ambient_lit:
		return out
	var mask: PackedByteArray = sight_mask(level)
	for l: LightSource in lights:
		for c: Vector2i in g.cells_in_radius(l.cell, l.dim):
			var i: int = g.index_of(c)
			if out[i] == BRIGHT:
				continue
			var lvl: int = BRIGHT if g.distance(l.cell, c) <= l.bright else DIM
			if lvl <= out[i]:
				continue
			if _los(level, mask, l.cell, c):
				out[i] = lvl
	return out


## Casillas visibles para un conjunto de observadores: 0 = no visible; si no,
## el nivel de luz con que se ve (DIM o BRIGHT; la visión en la oscuridad ve
## la oscuridad como DIM). Índice lineal.
static func visible_map(level: MapLevel, viewers: Array[Viewer], light: PackedByteArray) -> PackedByteArray:
	var g: GridGeometry = level.grid
	var out: PackedByteArray = PackedByteArray()
	out.resize(g.cell_count())
	out.fill(0)
	var mask: PackedByteArray = sight_mask(level)
	for v: Viewer in viewers:
		for origin: Vector2i in v.cells:
			if not g.in_bounds(origin):
				continue
			for c: Vector2i in g.cells_in_radius(origin, v.range_cells):
				var i: int = g.index_of(c)
				var lit: int = light[i]
				if lit == DARK and g.distance(origin, c) <= v.darkvision_cells:
					lit = DIM
				if lit == DARK or lit <= out[i]:
					continue
				if _los(level, mask, origin, c):
					out[i] = lit
	return out
