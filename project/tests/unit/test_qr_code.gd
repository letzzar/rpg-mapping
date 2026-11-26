extends GutTest
## Código QR del enlace de invitación (F4). Valores de referencia publicados
## (ejemplo "HELLO WORLD" 1-M de Thonky, tablas de formato y versión del
## estándar) y una lectura completa del símbolo: formato → máscara → zigzag →
## desintercalado → Reed-Solomon sin errores → texto original.


func test_reed_solomon_matches_the_published_example() -> void:
	var data: PackedByteArray = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
	var ecc: PackedByteArray = QrCode.rs_remainder(data, QrCode.rs_divisor(10))
	assert_eq(ecc, PackedByteArray([196, 35, 39, 119, 235, 215, 231, 226, 93, 23]))


func test_format_version_and_alignment_tables() -> void:
	assert_eq(QrCode.format_bits(QrCode.ECC_M, 0), 0b101010000010010)
	assert_eq(QrCode.format_bits(QrCode.ECC_L, 0), 0b111011111000100)
	assert_eq(QrCode.format_bits(QrCode.ECC_M, 5), 0b100000011001110)
	assert_eq(QrCode.format_bits(QrCode.ECC_M, 7), 0b100101010100000)
	assert_eq(QrCode.version_bits(7), 0x07C94)
	assert_eq(QrCode.version_bits(10), 0x0A4D3)
	assert_eq(QrCode.alignment_positions(2), PackedInt32Array([6, 18]))
	assert_eq(QrCode.alignment_positions(7), PackedInt32Array([6, 22, 38]))
	assert_eq(QrCode.alignment_positions(10), PackedInt32Array([6, 28, 50]))
	# Capacidad en bytes con corrección M (tabla del estándar).
	var cap_m: PackedInt32Array = [14, 26, 42, 62, 84, 106, 122, 152, 180, 213]
	for v: int in range(1, 11):
		assert_eq(QrCode.byte_capacity(v, QrCode.ECC_M), cap_m[v - 1], "versión %d" % v)
	assert_eq(QrCode.byte_capacity(1, QrCode.ECC_L), 17)


func test_version_grows_with_the_text() -> void:
	assert_eq(QrCode.encode_text("x".repeat(62)).version, 4)
	assert_eq(QrCode.encode_text("x".repeat(63)).version, 5)
	assert_null(QrCode.encode_text("x".repeat(214)))


## Lee el símbolo como lo haría un lector y recupera el texto.
func test_symbols_decode_back_to_the_link() -> void:
	var texts: Array[String] = [
		"https://192.168.1.34:47830/?sala=TN5YE0&t=HWPKS380P4",
		"a",
		"Ñandú · ¿sala?",
		"x".repeat(150),
	]
	for text: String in texts:
		for level: int in [QrCode.ECC_L, QrCode.ECC_M]:
			var qr: QrCode = QrCode.encode_text(text, level)
			assert_not_null(qr)
			assert_eq(_decode(qr), text, "%d bytes, nivel %d, versión %d" % [text.to_utf8_buffer().size(), level, qr.version])


func test_finders_timing_and_image() -> void:
	var qr: QrCode = QrCode.encode_text("https://10.0.0.2:47830/?sala=ABCDEF&t=0123456789")
	assert_eq(qr.size, qr.version * 4 + 17)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(qr.size - 7, 0), Vector2i(0, qr.size - 7)]:
		for d: int in 7:
			assert_true(qr.is_dark(c.x + d, c.y), "borde del buscador")
			assert_true(qr.is_dark(c.x, c.y + d), "borde del buscador")
		assert_false(qr.is_dark(c.x + 1, c.y + 1))
		assert_true(qr.is_dark(c.x + 3, c.y + 3), "centro del buscador")
	for i: int in range(8, qr.size - 8):
		assert_eq(qr.is_dark(i, 6), i % 2 == 0, "temporización")
	assert_true(qr.is_dark(8, qr.size - 8), "módulo oscuro fijo")
	var img: Image = qr.to_image(4, 4)
	assert_eq(img.get_width(), (qr.size + 8) * 4)
	assert_eq(img.get_pixel(1, 1), Color.WHITE)
	assert_eq(img.get_pixel(16, 16), Color.BLACK)


# --- Lector mínimo (sin corrección de errores: el símbolo es perfecto) ------

func _decode(qr: QrCode) -> String:
	# Formato: primera copia, comparada con las 32 posibles.
	var bits: int = 0
	var positions: Array[Vector2i] = []
	for i: int in range(0, 6):
		positions.append(Vector2i(8, i))
	positions.append_array([Vector2i(8, 7), Vector2i(8, 8), Vector2i(7, 8)])
	for i: int in range(9, 15):
		positions.append(Vector2i(14 - i, 8))
	for i: int in 15:
		if qr.is_dark(positions[i].x, positions[i].y):
			bits |= 1 << i
	var level: int = -1
	var m: int = -1
	for lv: int in [QrCode.ECC_L, QrCode.ECC_M]:
		for mm: int in 8:
			if QrCode.format_bits(lv, mm) == bits:
				level = lv
				m = mm
	assert_eq(level, qr.ecc, "nivel leído del formato")
	assert_eq(m, qr.mask, "máscara leída del formato")
	# Segunda copia igual que la primera.
	var bits2: int = 0
	for i: int in range(0, 8):
		if qr.is_dark(qr.size - 1 - i, 8):
			bits2 |= 1 << i
	for i: int in range(8, 15):
		if qr.is_dark(8, qr.size - 15 + i):
			bits2 |= 1 << i
	assert_eq(bits2, bits, "las dos copias del formato")
	# Zigzag y máscara.
	var raw: PackedByteArray = PackedByteArray()
	var order: Array[Vector2i] = qr.data_module_order()
	assert_eq(order.size(), QrCode.raw_data_modules(qr.version))
	var acc: int = 0
	var n: int = 0
	for c: Vector2i in order:
		var bit: int = 1 if qr.is_dark(c.x, c.y) else 0
		if QrCode.mask_applies(m, c.x, c.y):
			bit ^= 1
		acc = (acc << 1) | bit
		n += 1
		if n == 8:
			raw.append(acc)
			acc = 0
			n = 0
	# Desintercalado (mismos tamaños de bloque que el estándar).
	var v: int = qr.version
	var num_blocks: int = 0
	var block_ecc: int = 0
	var total: int = QrCode.raw_data_modules(v) / 8
	for nb: int in range(1, 9):
		for be: int in range(7, 31):
			if total - nb * be == QrCode.data_codewords(v, level) and _blocks_ok(v, level, nb, be):
				num_blocks = nb
				block_ecc = be
	assert_gt(num_blocks, 0)
	var num_short: int = num_blocks - total % num_blocks
	var short_len: int = total / num_blocks
	var blocks: Array[PackedByteArray] = []
	for j: int in num_blocks:
		blocks.append(PackedByteArray())
	var k: int = 0
	for i: int in short_len + 1:
		for j: int in num_blocks:
			if i == short_len - block_ecc and j < num_short:
				continue
			blocks[j].append(raw[k])
			k += 1
	var data: PackedByteArray = PackedByteArray()
	var divisor: PackedByteArray = QrCode.rs_divisor(block_ecc)
	for blk: PackedByteArray in blocks:
		var dat: PackedByteArray = blk.slice(0, blk.size() - block_ecc)
		assert_eq(QrCode.rs_remainder(dat, divisor), blk.slice(blk.size() - block_ecc), "Reed-Solomon del bloque")
		data.append_array(dat)
	# Modo byte, longitud y bytes.
	var pos: int = 0
	var mode: int = _bits(data, pos, 4)
	pos += 4
	assert_eq(mode, 0b0100, "modo byte")
	var count_bits: int = 8 if v <= 9 else 16
	var length: int = _bits(data, pos, count_bits)
	pos += count_bits
	var out: PackedByteArray = PackedByteArray()
	for i: int in length:
		out.append(_bits(data, pos, 8))
		pos += 8
	return out.get_string_from_utf8()


## El reparto de bloques que se prueba tiene que ser el de la tabla: misma
## cantidad de datos y misma corrección total.
func _blocks_ok(v: int, level: int, nb: int, be: int) -> bool:
	var raw_total: int = QrCode.raw_data_modules(v) / 8
	return raw_total - QrCode.data_codewords(v, level) == nb * be and _expected_blocks(v, level) == nb


func _expected_blocks(v: int, level: int) -> int:
	var m: PackedInt32Array = [1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
	var l: PackedInt32Array = [1, 1, 1, 1, 1, 2, 2, 2, 2, 4]
	return m[v - 1] if level == QrCode.ECC_M else l[v - 1]


func _bits(data: PackedByteArray, start: int, count: int) -> int:
	var out: int = 0
	for i: int in count:
		var p: int = start + i
		out = (out << 1) | ((data[p >> 3] >> (7 - (p & 7))) & 1)
	return out
