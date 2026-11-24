class_name HexGrid
extends GridGeometry
## Rejilla hexagonal en dos orientaciones (ADR 012, ADR 017).
##
## Coordenadas guardadas: "offset" (x, y) = (columna, fila), enteras y dentro
## del rectángulo width×height, como en la cuadrada:
## - hex_flat (lados planos arriba y abajo): "odd-q", las columnas impares
##   bajan media casilla.
## - hex_pointy (vértices arriba y abajo): "odd-r", las filas impares se
##   desplazan media casilla a la derecha.
## Internamente se trabaja en axiales (q, r) y cúbicas (q, -q-r, r): distancia,
## vecinos y líneas son más simples y no dependen de la paridad.
##
## Direcciones (orden fijo, horario empezando por arriba; la opuesta de d es
## (d + 3) % 6). Todas comparten arista y todos los pasos son STEP_HEX.
##   hex_flat:   0 N  1 NE  2 SE  3 S  4 SW  5 NW
##   hex_pointy: 0 NE 1 E   2 SE  3 SW 4 W   5 NW

const _AXIAL_FLAT: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]
const _AXIAL_POINTY: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1),
	Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
]
## Factor de escala y empujón de la línea entera (ver _line_ordered).
const _LINE_SCALE: int = 8

var pointy: bool = false


func _init(p_pointy: bool, p_width: int, p_height: int) -> void:
	pointy = p_pointy
	_setup(KIND_HEX_POINTY if p_pointy else KIND_HEX_FLAT, p_width, p_height)


## Offset -> axial Vector2i(q, r).
func to_axial(cell: Vector2i) -> Vector2i:
	if pointy:
		return Vector2i(cell.x - (cell.y - (cell.y & 1)) / 2, cell.y)
	return Vector2i(cell.x, cell.y - (cell.x - (cell.x & 1)) / 2)


## Axial (q, r) -> offset.
func from_axial(ax: Vector2i) -> Vector2i:
	if pointy:
		return Vector2i(ax.x + (ax.y - (ax.y & 1)) / 2, ax.y)
	return Vector2i(ax.x, ax.y + (ax.x - (ax.x & 1)) / 2)


func direction_count() -> int:
	return 6


func edge_direction_count() -> int:
	return 6


func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	var d: Vector2i = _AXIAL_POINTY[dir] if pointy else _AXIAL_FLAT[dir]
	return from_axial(to_axial(cell) + d)


func step_kind(_dir: int) -> int:
	return STEP_HEX


func opposite(dir: int) -> int:
	return (dir + 3) % 6


func distance(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = to_axial(b) - to_axial(a)
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


func step_counts(a: Vector2i, b: Vector2i) -> PackedInt32Array:
	return PackedInt32Array([0, 0, distance(a, b)])


## PROVISIONAL (validar con Víctor): 1-2 casillas de lado -> 1 hex; 3-4 -> el
## hex y su anillo (7); en general, radio (size - 1) / 2 alrededor de `anchor`.
func footprint(anchor: Vector2i, size_cells: int) -> Array[Vector2i]:
	return cells_in_radius(anchor, maxi(0, (maxi(1, size_cells) - 1) / 2), false)


## Interpolación en cúbicas con aritmética entera (equivalente a la de Red Blob
## Games con lerp + redondeo cúbico): N = distancia; para i = 0..N el punto
## a + (b - a)·i/N se escala por 8N y se le suma el empujón (1, 2, -3), que
## suma 0 y es menor que la mitad de la separación entre muestras (4 de 8N).
## Así ningún punto cae justo en una arista o vértice (no hay empates de
## redondeo) y el resultado no depende de la plataforma.
func _line_ordered(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var n: int = distance(a, b)
	if n == 0:
		return out
	var aa: Vector2i = to_axial(a)
	var bb: Vector2i = to_axial(b)
	# Cúbicas: x = q, z = r, y = -q - r.
	var ax: int = aa.x
	var az: int = aa.y
	var ay: int = -ax - az
	var bx: int = bb.x
	var bz: int = bb.y
	var by: int = -bx - bz
	var den: int = _LINE_SCALE * n
	for i: int in range(1, n + 1):
		var px: int = _LINE_SCALE * (ax * n + (bx - ax) * i) + 1
		var py: int = _LINE_SCALE * (ay * n + (by - ay) * i) + 2
		var pz: int = _LINE_SCALE * (az * n + (bz - az) * i) - 3
		var rx: int = round_div(px, den)
		var ry: int = round_div(py, den)
		var rz: int = round_div(pz, den)
		var ex: int = absi(rx * den - px)
		var ey: int = absi(ry * den - py)
		var ez: int = absi(rz * den - pz)
		if ex > ey and ex > ez:
			rx = -ry - rz
		elif ey > ez:
			ry = -rx - rz
		else:
			rz = -rx - ry
		out.append(from_axial(Vector2i(rx, rz)))
	return out


# --- SOLO VISTAS ------------------------------------------------------------
# R = radio circunscrito = cell_px / √3 (cell_px = ancho de lado plano a lado
# plano = distancia entre centros vecinos).

func cell_to_pixel(cell: Vector2i, cell_px: float) -> Vector2:
	var r: float = _circumradius(cell_px)
	var ax: Vector2i = to_axial(cell)
	if pointy:
		return Vector2(cell_px * 0.5 + cell_px * (ax.x + ax.y * 0.5), r + 1.5 * r * ax.y)
	return Vector2(r + 1.5 * r * ax.x, cell_px * 0.5 + cell_px * (ax.y + ax.x * 0.5))


func pixel_to_cell(p: Vector2, cell_px: float) -> Vector2i:
	var r: float = _circumradius(cell_px)
	var qf: float
	var rf: float
	if pointy:
		var lx: float = p.x - cell_px * 0.5
		var ly: float = p.y - r
		qf = (sqrt(3.0) / 3.0 * lx - ly / 3.0) / r
		rf = (2.0 / 3.0 * ly) / r
	else:
		var lx2: float = p.x - r
		var ly2: float = p.y - cell_px * 0.5
		qf = (2.0 / 3.0 * lx2) / r
		rf = (-lx2 / 3.0 + sqrt(3.0) / 3.0 * ly2) / r
	# Redondeo cúbico en float (solo vistas).
	var sf: float = -qf - rf
	var rq: float = roundf(qf)
	var rr: float = roundf(rf)
	var rs: float = roundf(sf)
	var dq: float = absf(rq - qf)
	var dr: float = absf(rr - rf)
	var ds: float = absf(rs - sf)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return from_axial(Vector2i(int(rq), int(rr)))


func map_pixel_size(cell_px: float) -> Vector2:
	if width <= 0 or height <= 0:
		return Vector2.ZERO
	var r: float = _circumradius(cell_px)
	if pointy:
		var extra_x: float = cell_px * 0.5 if height > 1 else 0.0
		return Vector2(cell_px * width + extra_x, 1.5 * r * (height - 1) + 2.0 * r)
	var extra_y: float = cell_px * 0.5 if width > 1 else 0.0
	return Vector2(1.5 * r * (width - 1) + 2.0 * r, cell_px * height + extra_y)


func _side_count() -> int:
	return 6


func _first_corner_deg() -> float:
	return 30.0 if pointy else 0.0


func _circumradius(cell_px: float) -> float:
	return cell_px / sqrt(3.0)
