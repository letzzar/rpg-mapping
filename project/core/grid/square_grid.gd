class_name SquareGrid
extends GridGeometry
## Rejilla cuadrada. Coordenadas (x, y) = (columna, fila); y crece hacia abajo.
##
## Direcciones (orden fijo; las 4 ortogonales primero, así que los 4 primeros
## vecinos son la vecindad de von Neumann):
##   0 N (0,-1)   1 E (1,0)   2 S (0,1)   3 W (-1,0)
##   4 NE (1,-1)  5 SE (1,1)  6 SW (-1,1) 7 NW (-1,-1)
## Solo las ortogonales comparten arista; las diagonales tocan por un vértice.

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
## Componentes ortogonales de cada diagonal (NE, SE, SW, NW).
const _DIAG_PARTS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(2, 1), Vector2i(2, 3), Vector2i(0, 3)]


func _init(p_width: int, p_height: int) -> void:
	_setup(KIND_SQUARE, p_width, p_height)


func direction_count() -> int:
	return 8


func edge_direction_count() -> int:
	return 4


func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	return cell + DIRS[dir]


func step_kind(dir: int) -> int:
	return STEP_ORTHOGONAL if dir < 4 else STEP_DIAGONAL


func opposite(dir: int) -> int:
	if dir < 4:
		return (dir + 2) % 4
	return 4 + (dir - 2) % 4


func diagonal_components(dir: int) -> PackedInt32Array:
	if dir < 4:
		return PackedInt32Array()
	var p: Vector2i = _DIAG_PARTS[dir - 4]
	return PackedInt32Array([p.x, p.y])


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(b.x - a.x), absi(b.y - a.y))


func step_counts(a: Vector2i, b: Vector2i) -> PackedInt32Array:
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var diag: int = mini(dx, dy)
	return PackedInt32Array([maxi(dx, dy) - diag, diag, 0])


func footprint(anchor: Vector2i, size_cells: int) -> Array[Vector2i]:
	var n: int = maxi(1, size_cells)
	var out: Array[Vector2i] = []
	for y: int in n:
		for x: int in n:
			out.append(anchor + Vector2i(x, y))
	return out


## Muestreo del segmento entre centros: N = max(|dx|, |dy|) pasos y, en cada
## uno, el eje menor redondeado (mitades hacia +inf). El eje mayor avanza 1
## por paso, así que las casillas consecutivas son siempre vecinas.
func _line_ordered(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	var n: int = maxi(absi(dx), absi(dy))
	var out: Array[Vector2i] = [a]
	for i: int in range(1, n + 1):
		out.append(Vector2i(a.x + round_div(dx * i, n), a.y + round_div(dy * i, n)))
	return out


# --- SOLO VISTAS ------------------------------------------------------------

func cell_to_pixel(cell: Vector2i, cell_px: float) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px


func pixel_to_cell(p: Vector2, cell_px: float) -> Vector2i:
	return Vector2i(floori(p.x / cell_px), floori(p.y / cell_px))


func map_pixel_size(cell_px: float) -> Vector2:
	return Vector2(width, height) * cell_px


func _side_count() -> int:
	return 4


func _first_corner_deg() -> float:
	return 45.0


func _circumradius(cell_px: float) -> float:
	return cell_px * sqrt(2.0) / 2.0
