class_name GridGeometry
extends RefCounted
## Geometría de rejilla abstracta (ADR 012 y ADR 017): la usan el modelo, los
## generadores, el coste de movimiento y las vistas, sin saber si la rejilla es
## cuadrada o hexagonal.
##
## Crear con GridFactory.create(kind, width, height). Implementaciones:
## SquareGrid ("square") y HexGrid ("hex_flat", "hex_pointy").
##
## COORDENADAS (lo que se guarda): Vector2i(x, y) = (columna, fila), enteras,
## dentro del rectángulo 0 <= x < width, 0 <= y < height. En hex son
## coordenadas "offset" (ver HexGrid); los cálculos internos usan axiales.
## Índice lineal de casilla: y * width + x (orden por filas, el de las capas).
##
## DIRECCIONES: cada rejilla numera sus vecinos 0..direction_count()-1 en un
## orden FIJO (no depende de la casilla). Las direcciones 0..edge_direction_count()-1
## son las que comparten arista con la casilla (en la cuadrada, las 4
## ortogonales; en hex, las 6). Ver la tabla de cada implementación.
##
## ARISTAS: una arista se identifica por (casilla dueña, lado) en forma
## canónica (canonical_edge) o por un entero (edge_id). La casilla dueña puede
## quedar fuera del mapa (x o y = -1, o = width/height) para las aristas del
## borde.
##
## DETERMINISMO: todo lo que no está marcado "SOLO VISTAS" es aritmética entera
## y devuelve listas en un orden fijo. Los métodos "SOLO VISTAS" usan float y
## no deben llamarse desde core/gen ni core/rules.

const KIND_SQUARE: String = "square"
const KIND_HEX_FLAT: String = "hex_flat"
const KIND_HEX_POINTY: String = "hex_pointy"
## Mismos ids (y orden) que el enumerado "grid" de los esquemas de parámetros.
const KINDS: PackedStringArray = ["square", "hex_flat", "hex_pointy"]

## Tipos de paso (los perfiles de sistema dan el coste de cada uno).
const STEP_ORTHOGONAL: int = 0
const STEP_DIAGONAL: int = 1
const STEP_HEX: int = 2
const STEP_KIND_COUNT: int = 3

## Huellas hexagonales admitidas (nº de hexágonos), ver footprint().
const HEX_FOOTPRINTS: PackedInt32Array = [1, 3, 7, 19]

## Tamaño máximo de un lado del mapa (cabe holgado en los ids de arista).
const MAX_SIDE: int = 4096

var kind: String = ""
var width: int = 0
var height: int = 0


func _setup(p_kind: String, p_width: int, p_height: int) -> void:
	kind = p_kind
	width = p_width
	height = p_height


# --- Interfaz (la implementan SquareGrid y HexGrid) -------------------------

## Número de vecinos de una casilla (8 en cuadrada, 6 en hex).
func direction_count() -> int:
	return 0


## Número de direcciones que comparten arista (4 en cuadrada, 6 en hex); son
## las direcciones 0..edge_direction_count()-1.
func edge_direction_count() -> int:
	return 0


## Casilla vecina en la dirección `dir` (puede caer fuera del mapa).
func neighbor(_cell: Vector2i, _dir: int) -> Vector2i:
	return Vector2i.ZERO


## Tipo de paso de la dirección: STEP_ORTHOGONAL, STEP_DIAGONAL o STEP_HEX.
func step_kind(_dir: int) -> int:
	return STEP_ORTHOGONAL


## Dirección opuesta.
func opposite(_dir: int) -> int:
	return 0


## En la cuadrada, las dos direcciones ortogonales que suman la diagonal `dir`
## (p. ej. NE -> [N, E]); vacío para direcciones no diagonales y en hex.
func diagonal_components(_dir: int) -> PackedInt32Array:
	return PackedInt32Array()


## Distancia en pasos (casillas) por el camino más corto en una rejilla vacía:
## Chebyshev en la cuadrada (la diagonal cuenta 1), hexagonal en hex. El coste
## en pies según el sistema está en MovementCost.measure_ft().
func distance(_a: Vector2i, _b: Vector2i) -> int:
	return 0


## Nº de pasos de cada tipo de un camino recto más corto de `a` a `b`, indexado
## por STEP_*: [ortogonales, diagonales, hex]. Base de la medición.
func step_counts(_a: Vector2i, _b: Vector2i) -> PackedInt32Array:
	return PackedInt32Array([0, 0, 0])


## Casillas ocupadas por una criatura anclada en `anchor`, en orden por filas.
## Cada rejilla usa el dato que le corresponde del perfil (reglas como datos):
## - cuadrada: bloque side_cells×side_cells con `anchor` arriba a la izquierda
##   (SystemProfile.size_cells());
## - hex: `hex_cells` hexágonos (SystemProfile.size_hex_cells_of()): 1; 3 =
##   triángulo `anchor` + vecinos en las direcciones 2 y 3 (orientación fija);
##   7 = radio 1; 19 = radio 2 alrededor de `anchor`.
## No recorta al mapa.
func footprint(anchor: Vector2i, _side_cells: int, _hex_cells: int = 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = [anchor]
	return out


## Centro de la casilla en una red entera auxiliar para geometría exacta sin
## float (plantillas de área): dos casillas vecinas por un lado distan 2
## unidades y el cuadrado de la distancia euclídea de un vector (X, Y) es
## w.x·X² + w.y·Y², con w = lattice_weights(). En la cuadrada w = (1, 1); en
## hex, uno de los pesos es 3 (el √3 del hexágono queda al cuadrado).
func center_lattice(_cell: Vector2i) -> Vector2i:
	return Vector2i.ZERO


## Pesos de la métrica de center_lattice().
func lattice_weights() -> Vector2i:
	return Vector2i(1, 1)


## Línea entre `a` y `b` (incluidas), casilla a casilla, para la línea de
## visión. Consecutivas siempre vecinas. SIMÉTRICA: line(b, a) es line(a, b)
## al revés (se calcula siempre desde el extremo menor por filas). No recorta.
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if b.y < a.y or (b.y == a.y and b.x < a.x):
		var rev: Array[Vector2i] = _line_ordered(b, a)
		rev.reverse()
		return rev
	return _line_ordered(a, b)


func _line_ordered(a: Vector2i, _b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	return out


# --- Comunes ----------------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func cell_count() -> int:
	return width * height


## Índice lineal (orden por filas) de una casilla del mapa; -1 si está fuera.
func index_of(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	return cell.y * width + cell.x


func cell_at(index: int) -> Vector2i:
	return Vector2i(index % width, index / width)


## Vecinos en el orden fijo de las direcciones. Con `include_outside` = false
## (por defecto) se omiten los que caen fuera del mapa.
func neighbors(cell: Vector2i, include_outside: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: int in direction_count():
		var n: Vector2i = neighbor(cell, d)
		if include_outside or in_bounds(n):
			out.append(n)
	return out


## Dirección de `a` a `b` si son vecinas; -1 si no.
func direction_between(a: Vector2i, b: Vector2i) -> int:
	for d: int in direction_count():
		if neighbor(a, d) == b:
			return d
	return -1


## Casillas a distancia <= `radius` de `center`, en orden por filas (y, luego
## x). Con `clip` (por defecto) solo las del mapa. Coste O(radius²).
func cells_in_radius(center: Vector2i, radius: int, clip: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius < 0:
		return out
	# En las tres rejillas cada paso cambia x e y como mucho en 1, así que el
	# cuadrado [-r, r]² contiene el círculo.
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var c: Vector2i = Vector2i(x, y)
			if clip and not in_bounds(c):
				continue
			if distance(center, c) <= radius:
				out.append(c)
	return out


## Arista en forma canónica: Vector3i(x, y, lado) con la casilla dueña (x, y) y
## lado < edge_direction_count()/2. Cada arista tiene una sola forma canónica:
## la de la casilla para la que esa arista está en su primera mitad de
## direcciones. `dir` debe compartir arista (< edge_direction_count()).
func canonical_edge(cell: Vector2i, dir: int) -> Vector3i:
	assert(dir >= 0 and dir < edge_direction_count(), "GridGeometry: la dirección no comparte arista")
	if dir < edge_direction_count() / 2:
		return Vector3i(cell.x, cell.y, dir)
	var n: Vector2i = neighbor(cell, dir)
	return Vector3i(n.x, n.y, opposite(dir))


## Id entero de la arista (estable para un ancho dado; ordenar por id = ordenar
## por fila, columna y lado de la casilla dueña).
func edge_id(cell: Vector2i, dir: int) -> int:
	var e: Vector3i = canonical_edge(cell, dir)
	return ((e.y + 1) * (width + 2) + (e.x + 1)) * 4 + e.z


## Inverso de edge_id(): Vector3i(x, y, lado) canónico.
func edge_from_id(id: int) -> Vector3i:
	var rest: int = id / 4
	return Vector3i(rest % (width + 2) - 1, rest / (width + 2) - 1, id % 4)


## Las dos casillas que separa la arista (la dueña primero).
func edge_cells(id: int) -> Array[Vector2i]:
	var e: Vector3i = edge_from_id(id)
	var own: Vector2i = Vector2i(e.x, e.y)
	var out: Array[Vector2i] = [own, neighbor(own, e.z)]
	return out


## true si la arista toca al menos una casilla del mapa.
func edge_touches_map(id: int) -> bool:
	if id < 0:
		return false
	var cells: Array[Vector2i] = edge_cells(id)
	return in_bounds(cells[0]) or in_bounds(cells[1])


## División entera redondeando hacia -infinito (b > 0).
static func floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if a % b != 0 and a < 0:
		q -= 1
	return q


## n/d redondeado al entero más cercano, mitades hacia +infinito (d > 0).
static func round_div(n: int, d: int) -> int:
	return floor_div(2 * n + d, 2 * d)


# --- SOLO VISTAS (float; prohibido en core/gen y core/rules) ----------------
# `cell_px` es la distancia en píxeles entre los centros de dos casillas
# vecinas por un lado (en hex, el ancho de lado plano a lado plano). Así
# "1 casilla = 1 pulgada" funciona igual en las tres rejillas. El origen (0, 0)
# es la esquina superior izquierda del rectángulo que envuelve el mapa.

## SOLO VISTAS. Centro de la casilla en píxeles.
func cell_to_pixel(_cell: Vector2i, _cell_px: float) -> Vector2:
	return Vector2.ZERO


## SOLO VISTAS. Casilla que contiene el punto (puede estar fuera del mapa).
func pixel_to_cell(_p: Vector2, _cell_px: float) -> Vector2i:
	return Vector2i.ZERO


## SOLO VISTAS. Tamaño en píxeles del rectángulo que envuelve el mapa.
func map_pixel_size(_cell_px: float) -> Vector2:
	return Vector2.ZERO


## SOLO VISTAS. Esquinas de la casilla (sentido horario en pantalla).
func cell_polygon(cell: Vector2i, cell_px: float) -> PackedVector2Array:
	var c: Vector2 = cell_to_pixel(cell, cell_px)
	var r: float = _circumradius(cell_px)
	var sides: int = _side_count()
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in sides:
		var ang: float = deg_to_rad(_first_corner_deg() + 360.0 * i / sides)
		out.append(c + Vector2(cos(ang), sin(ang)) * r)
	return out


## SOLO VISTAS. Extremos del segmento de la arista entre `cell` y su vecina en
## `dir` (dir < edge_direction_count()). Para dibujar muros y puertas.
func edge_segment(cell: Vector2i, dir: int, cell_px: float) -> PackedVector2Array:
	var c: Vector2 = cell_to_pixel(cell, cell_px)
	var n: Vector2 = cell_to_pixel(neighbor(cell, dir), cell_px)
	var theta: float = (n - c).angle()
	var half: float = PI / _side_count()
	var r: float = _circumradius(cell_px)
	return PackedVector2Array([
		c + Vector2(cos(theta - half), sin(theta - half)) * r,
		c + Vector2(cos(theta + half), sin(theta + half)) * r,
	])


func _side_count() -> int:
	return 4


func _first_corner_deg() -> float:
	return 45.0


func _circumradius(_cell_px: float) -> float:
	return 0.0
