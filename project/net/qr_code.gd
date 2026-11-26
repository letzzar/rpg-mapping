class_name QrCode
extends RefCounted
## Código QR (ISO/IEC 18004) para el enlace de invitación de la partida en
## red (F4): el jugador lo escanea con el móvil en vez de teclear la URL.
##
## Solo lo necesario para eso: modo byte (UTF-8), versiones 1 a 10 (hasta 213
## bytes con corrección M; un enlace ocupa unos 55) y niveles de corrección L
## y M. Sigue el algoritmo de referencia del estándar (y de qrcodegen de
## Nayuki): codificar, Reed-Solomon por bloques, intercalar, colocar en
## zigzag y elegir la máscara de menor penalización. Sin dependencias: Godot
## no trae generador de QR y no queremos GDExtension (rompe la web).

const ECC_L: int = 0
const ECC_M: int = 1
const MAX_VERSION: int = 10

# Por nivel y versión: índice nivel * 11 + versión (1..10; el 0 sin usar).
const _ECC_PER_BLOCK: PackedInt32Array = [
	-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18,
	-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26,
]
const _NUM_BLOCKS: PackedInt32Array = [
	-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4,
	-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5,
]
## Bits de nivel en la información de formato (L = 01, M = 00).
const _FORMAT_BITS: PackedInt32Array = [1, 0]

var version: int = 0
var ecc: int = ECC_M
var mask: int = -1
var size: int = 0
## Módulos fila a fila (1 = oscuro).
var modules: PackedByteArray = PackedByteArray()
var _is_function: PackedByteArray = PackedByteArray()


## QR del texto (UTF-8) con la versión más pequeña en la que cabe; null si
## no cabe en la versión 10.
static func encode_text(text: String, p_ecc: int = ECC_M) -> QrCode:
	return encode_bytes(text.to_utf8_buffer(), p_ecc)


static func encode_bytes(data: PackedByteArray, p_ecc: int = ECC_M) -> QrCode:
	for v: int in range(1, MAX_VERSION + 1):
		if data.size() <= byte_capacity(v, p_ecc):
			var qr: QrCode = QrCode.new()
			qr._build(v, p_ecc, data)
			return qr
	return null


## Bytes que caben en modo byte con esa versión y nivel.
static func byte_capacity(v: int, p_ecc: int) -> int:
	var count_bits: int = 8 if v <= 9 else 16
	return (data_codewords(v, p_ecc) * 8 - 4 - count_bits) / 8


static func data_codewords(v: int, p_ecc: int) -> int:
	return raw_data_modules(v) / 8 - _ECC_PER_BLOCK[p_ecc * 11 + v] * _NUM_BLOCKS[p_ecc * 11 + v]


## Módulos disponibles para datos y corrección (sin los de función).
static func raw_data_modules(v: int) -> int:
	var result: int = (16 * v + 128) * v + 64
	if v >= 2:
		var num_align: int = v / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if v >= 7:
			result -= 36
	return result


static func alignment_positions(v: int) -> PackedInt32Array:
	if v == 1:
		return PackedInt32Array()
	var num_align: int = v / 7 + 2
	var step: int = (v * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	var s: int = v * 4 + 17
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(num_align)
	out[0] = 6
	for i: int in range(num_align - 1):
		out[num_align - 1 - i] = s - 7 - i * step
	return out


## Los 15 bits de formato (nivel + máscara, BCH y la máscara 0x5412).
static func format_bits(p_ecc: int, p_mask: int) -> int:
	var data: int = (_FORMAT_BITS[p_ecc] << 3) | p_mask
	var rem: int = data
	for i: int in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	return ((data << 10) | rem) ^ 0x5412


## Los 18 bits de versión (versiones 7 y mayores).
static func version_bits(v: int) -> int:
	var rem: int = v
	for i: int in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	return (v << 12) | rem


func is_dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and modules[y * size + x] != 0


## Imagen en blanco y negro con margen de `quiet` módulos y `scale` píxeles
## por módulo (para mostrarla con filtro "nearest").
func to_image(scale: int = 8, quiet: int = 4) -> Image:
	var px: int = (size + quiet * 2) * scale
	var img: Image = Image.create_empty(px, px, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y: int in size:
		for x: int in size:
			if is_dark(x, y):
				img.fill_rect(Rect2i((x + quiet) * scale, (y + quiet) * scale, scale, scale), Color.BLACK)
	return img


# --- Construcción -------------------------------------------------------------

func _build(v: int, p_ecc: int, data: PackedByteArray) -> void:
	version = v
	ecc = p_ecc
	size = v * 4 + 17
	modules.resize(size * size)
	modules.fill(0)
	_is_function.resize(size * size)
	_is_function.fill(0)
	_draw_function_patterns()
	_draw_codewords(add_ecc_and_interleave(v, p_ecc, _data_codewords(v, p_ecc, data)))
	var best: int = 0
	var best_penalty: int = 1 << 30
	for m: int in 8:
		_apply_mask(m)
		_draw_format(m)
		var p: int = penalty()
		if p < best_penalty:
			best = m
			best_penalty = p
		_apply_mask(m)
	mask = best
	_apply_mask(best)
	_draw_format(best)


## Segmento en modo byte + terminador + relleno hasta la capacidad.
static func _data_codewords(v: int, p_ecc: int, data: PackedByteArray) -> PackedByteArray:
	var bits: PackedByteArray = PackedByteArray()
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, data.size(), 8 if v <= 9 else 16)
	for b: int in data:
		_append_bits(bits, b, 8)
	var capacity: int = data_codewords(v, p_ecc) * 8
	_append_bits(bits, 0, mini(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var out: PackedByteArray = PackedByteArray()
	for i: int in range(0, bits.size(), 8):
		var byte: int = 0
		for j: int in 8:
			byte = (byte << 1) | bits[i + j]
		out.append(byte)
	var pad: int = 0xEC
	while out.size() < capacity / 8:
		out.append(pad)
		pad ^= 0xEC ^ 0x11
	return out


static func _append_bits(bits: PackedByteArray, value: int, count: int) -> void:
	for i: int in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


## Divide en bloques, añade a cada uno su corrección Reed-Solomon e intercala
## (público para las pruebas).
static func add_ecc_and_interleave(v: int, p_ecc: int, data: PackedByteArray) -> PackedByteArray:
	var num_blocks: int = _NUM_BLOCKS[p_ecc * 11 + v]
	var block_ecc: int = _ECC_PER_BLOCK[p_ecc * 11 + v]
	var raw_codewords: int = raw_data_modules(v) / 8
	var num_short: int = num_blocks - raw_codewords % num_blocks
	var short_len: int = raw_codewords / num_blocks
	var divisor: PackedByteArray = rs_divisor(block_ecc)
	var blocks: Array[PackedByteArray] = []
	var k: int = 0
	for i: int in num_blocks:
		var n: int = short_len - block_ecc + (0 if i < num_short else 1)
		var dat: PackedByteArray = data.slice(k, k + n)
		k += n
		var block: PackedByteArray = dat.duplicate()
		if i < num_short:
			block.append(0)
		block.append_array(rs_remainder(dat, divisor))
		blocks.append(block)
	var out: PackedByteArray = PackedByteArray()
	for i: int in blocks[0].size():
		for j: int in blocks.size():
			if i != short_len - block_ecc or j >= num_short:
				out.append(blocks[j][i])
	return out


## Producto en GF(256) con el polinomio 0x11D.
static func gf_mul(x: int, y: int) -> int:
	var z: int = 0
	for i: int in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z


static func rs_divisor(degree: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root: int = 1
	for i: int in degree:
		for j: int in degree:
			result[j] = gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = gf_mul(root, 0x02)
	return result


static func rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(divisor.size())
	result.fill(0)
	for b: int in data:
		var factor: int = b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i: int in divisor.size():
			result[i] ^= gf_mul(divisor[i], factor)
	return result


func _set_function(x: int, y: int, dark: bool) -> void:
	modules[y * size + x] = 1 if dark else 0
	_is_function[y * size + x] = 1


func is_function(x: int, y: int) -> bool:
	return _is_function[y * size + x] != 0


func _draw_function_patterns() -> void:
	for i: int in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	for c: Vector2i in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var dist: int = maxi(absi(dx), absi(dy))
				var xx: int = c.x + dx
				var yy: int = c.y + dy
				if xx >= 0 and yy >= 0 and xx < size and yy < size:
					_set_function(xx, yy, dist != 2 and dist != 4)
	var pos: PackedInt32Array = alignment_positions(version)
	var n: int = pos.size()
	for i: int in n:
		for j: int in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					_set_function(pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	# Reserva las zonas de formato (se escriben de verdad al elegir máscara).
	_draw_format(0)
	if version >= 7:
		var bits: int = version_bits(version)
		for i: int in 18:
			var dark: bool = (bits >> i) & 1 != 0
			var a: int = size - 11 + i % 3
			var b: int = i / 3
			_set_function(a, b, dark)
			_set_function(b, a, dark)


func _draw_format(m: int) -> void:
	var bits: int = format_bits(ecc, m)
	for i: int in range(0, 6):
		_set_function(8, i, (bits >> i) & 1 != 0)
	_set_function(8, 7, (bits >> 6) & 1 != 0)
	_set_function(8, 8, (bits >> 7) & 1 != 0)
	_set_function(7, 8, (bits >> 8) & 1 != 0)
	for i: int in range(9, 15):
		_set_function(14 - i, 8, (bits >> i) & 1 != 0)
	for i: int in range(0, 8):
		_set_function(size - 1 - i, 8, (bits >> i) & 1 != 0)
	for i: int in range(8, 15):
		_set_function(8, size - 15 + i, (bits >> i) & 1 != 0)
	_set_function(8, size - 8, true)


## Orden de colocación de los bits de datos (zigzag de dos columnas, de
## derecha a izquierda, saltando la columna de temporización).
func data_module_order() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert: int in size:
			for j: int in 2:
				var x: int = right - j
				var upward: bool = (right + 1) & 2 == 0
				var y: int = size - 1 - vert if upward else vert
				if not is_function(x, y):
					out.append(Vector2i(x, y))
		right -= 2
	return out


func _draw_codewords(data: PackedByteArray) -> void:
	var order: Array[Vector2i] = data_module_order()
	for i: int in mini(order.size(), data.size() * 8):
		var c: Vector2i = order[i]
		modules[c.y * size + c.x] = (data[i >> 3] >> (7 - (i & 7))) & 1


static func mask_applies(m: int, x: int, y: int) -> bool:
	match m:
		0: return (x + y) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (x + y) % 3 == 0
		4: return (x / 3 + y / 2) % 2 == 0
		5: return x * y % 2 + x * y % 3 == 0
		6: return (x * y % 2 + x * y % 3) % 2 == 0
		_: return ((x + y) % 2 + x * y % 3) % 2 == 0


func _apply_mask(m: int) -> void:
	for y: int in size:
		for x: int in size:
			if not is_function(x, y) and mask_applies(m, x, y):
				modules[y * size + x] ^= 1


## Penalización del estándar (rachas, bloques 2×2, falsos buscadores y
## proporción de oscuros): se elige la máscara que la minimiza.
func penalty() -> int:
	var result: int = 0
	for horizontal: bool in [true, false]:
		for a: int in size:
			var run: int = 0
			var prev: int = -1
			var line: PackedByteArray = PackedByteArray()
			line.resize(size)
			for b: int in size:
				var v: int = modules[a * size + b] if horizontal else modules[b * size + a]
				line[b] = v
				if v == prev:
					run += 1
				else:
					if run >= 5:
						result += run - 2
					run = 1
					prev = v
			if run >= 5:
				result += run - 2
			# 1:1:3:1:1 con cuatro claros a un lado (fuera del símbolo cuenta
			# como claro).
			for b: int in range(-4, size):
				if _finder_like(line, b):
					result += 40
	for y: int in size - 1:
		for x: int in size - 1:
			var c: int = modules[y * size + x]
			if c == modules[y * size + x + 1] and c == modules[(y + 1) * size + x] and c == modules[(y + 1) * size + x + 1]:
				result += 3
	var dark: int = 0
	for v: int in modules:
		dark += v
	var total: int = size * size
	var k: int = (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += maxi(k, 0) * 10
	return result


const _FINDER_A: PackedByteArray = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
const _FINDER_B: PackedByteArray = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]


static func _finder_like(line: PackedByteArray, start: int) -> bool:
	if start + 11 > line.size() + 4:
		return false
	var a: bool = true
	var b: bool = true
	for i: int in 11:
		var idx: int = start + i
		var v: int = line[idx] if idx >= 0 and idx < line.size() else 0
		if v != _FINDER_A[i]:
			a = false
		if v != _FINDER_B[i]:
			b = false
	return a or b
