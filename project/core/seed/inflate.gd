class_name Inflate
extends RefCounted
## Descompresor DEFLATE (RFC 1951, flujo "crudo", sin cabecera zlib) escrito
## en GDScript para leer los códigos para compartir RPGS1 (RoomCode).
##
## Por qué uno propio en vez de PackedByteArray.decompress_dynamic():
## - Límite de salida exacto contra bombas de descompresión, y distinguir
##   "demasiado grande" (ROOM_ERR_TOO_BIG) de "datos corruptos".
## - Sin mensajes de error del motor: el motor imprime ERR_FAIL con datos
##   inválidos o al pasar el límite, y el texto lo pega el usuario (puede ser
##   cualquier cosa). GUT trata esos errores como fallos.
## - Mismo comportamiento en escritorio y web, sin depender del zlib del motor
##   para LEER (para comprimir sí se usa el del motor; ver RoomCode).
## Sigue el esquema de "puff" (zlib/contrib/puff, de Mark Adler): decodificación
## canónica de Huffman por longitudes, sin tablas. Coste O(bits de entrada +
## bytes de salida); las copias largas se hacen por trozos con append_array.

const STATUS_OK: int = 0
const STATUS_ERROR: int = 1
const STATUS_TOO_BIG: int = 2

const _MAX_BITS: int = 15
const _LBASE: PackedInt32Array = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
const _LEXT: PackedInt32Array = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
const _DBASE: PackedInt32Array = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
const _DEXT: PackedInt32Array = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
## Orden de las longitudes del código de longitudes (bloques dinámicos).
const _CL_ORDER: PackedInt32Array = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


## Resultado de inflate_raw().
class Result:
	extends RefCounted
	var status: int = STATUS_ERROR
	var bytes: PackedByteArray = PackedByteArray()


## Código de Huffman canónico: nº de códigos por longitud y símbolos
## ordenados por (longitud, símbolo).
class Huffman:
	extends RefCounted
	var counts: PackedInt32Array = PackedInt32Array()
	var symbols: PackedInt32Array = PackedInt32Array()
	## Huecos sin usar (0 = completo; > 0 = incompleto).
	var left: int = 0


var _in: PackedByteArray = PackedByteArray()
var _bitpos: int = 0
var _out: PackedByteArray = PackedByteArray()
var _max: int = 0
var _failed: bool = false
var _too_big: bool = false


## Descomprime un flujo DEFLATE crudo. `max_output` = bytes máximos de salida
## (si se pasan, STATUS_TOO_BIG sin seguir). Rechaza bytes sobrantes tras el
## último bloque.
static func inflate_raw(data: PackedByteArray, max_output: int) -> Result:
	var st: Inflate = Inflate.new()
	st._in = data
	st._max = max_output
	var res: Result = Result.new()
	st._run()
	if st._too_big:
		res.status = STATUS_TOO_BIG
	elif st._failed:
		res.status = STATUS_ERROR
	else:
		res.status = STATUS_OK
		res.bytes = st._out
	return res


func _run() -> void:
	var last: int = 0
	while last == 0 and not _failed:
		last = _bits(1)
		var kind: int = _bits(2)
		if _failed:
			return
		match kind:
			0:
				_stored()
			1:
				_codes(_fixed_lit(), _fixed_dist())
			2:
				_dynamic()
			_:
				_failed = true
	if _failed:
		return
	# Nada después del último bloque (salvo el relleno del último byte).
	if (_bitpos + 7) >> 3 != _in.size():
		_failed = true


func _bits(n: int) -> int:
	var v: int = 0
	for i: int in n:
		var bi: int = _bitpos >> 3
		if bi >= _in.size():
			_failed = true
			return 0
		v |= ((_in[bi] >> (_bitpos & 7)) & 1) << i
		_bitpos += 1
	return v


func _stored() -> void:
	_bitpos = (_bitpos + 7) & ~7
	var p: int = _bitpos >> 3
	if p + 4 > _in.size():
		_failed = true
		return
	var n: int = _in[p] | (_in[p + 1] << 8)
	var nn: int = _in[p + 2] | (_in[p + 3] << 8)
	if n != (~nn & 0xFFFF) or p + 4 + n > _in.size():
		_failed = true
		return
	if _out.size() + n > _max:
		_too_big = true
		_failed = true
		return
	_out.append_array(_in.slice(p + 4, p + 4 + n))
	_bitpos = (p + 4 + n) << 3


func _decode(h: Huffman) -> int:
	var code: int = 0
	var first: int = 0
	var index: int = 0
	for bl: int in range(1, _MAX_BITS + 1):
		code |= _bits(1)
		if _failed:
			return -1
		var count: int = h.counts[bl]
		if code - count < first:
			return h.symbols[index + (code - first)]
		index += count
		first += count
		first <<= 1
		code <<= 1
	return -1


func _codes(lit: Huffman, dist: Huffman) -> void:
	while not _failed:
		var sym: int = _decode(lit)
		if sym < 0:
			_failed = true
			return
		if sym < 256:
			if _out.size() >= _max:
				_too_big = true
				_failed = true
				return
			_out.append(sym)
		elif sym == 256:
			return
		else:
			sym -= 257
			if sym >= _LBASE.size():
				_failed = true
				return
			var length: int = _LBASE[sym] + _bits(_LEXT[sym])
			var ds: int = _decode(dist)
			if ds < 0 or ds >= _DBASE.size():
				_failed = true
				return
			var distance: int = _DBASE[ds] + _bits(_DEXT[ds])
			if _failed or distance > _out.size():
				_failed = true
				return
			if _out.size() + length > _max:
				_too_big = true
				_failed = true
				return
			# Copia LZ77; si se solapa (distance < length), por trozos que
			# crecen: cada vuelta copia todo lo disponible desde `start`.
			var start: int = _out.size() - distance
			var remaining: int = length
			while remaining > 0:
				var chunk: int = mini(remaining, _out.size() - start)
				_out.append_array(_out.slice(start, start + chunk))
				remaining -= chunk


func _dynamic() -> void:
	var nlen: int = _bits(5) + 257
	var ndist: int = _bits(5) + 1
	var ncode: int = _bits(4) + 4
	if _failed or nlen > 286 or ndist > 30:
		_failed = true
		return
	var cl: PackedInt32Array = PackedInt32Array()
	cl.resize(19)
	cl.fill(0)
	for i: int in ncode:
		cl[_CL_ORDER[i]] = _bits(3)
	if _failed:
		return
	var clcode: Huffman = _build(cl)
	# El código de longitudes tiene que ser completo.
	if clcode == null or clcode.left != 0:
		_failed = true
		return
	var total: int = nlen + ndist
	var lens: PackedInt32Array = PackedInt32Array()
	lens.resize(total)
	lens.fill(0)
	var index: int = 0
	while index < total:
		var sym: int = _decode(clcode)
		if sym < 0:
			_failed = true
			return
		if sym < 16:
			lens[index] = sym
			index += 1
			continue
		var value: int = 0
		var rep: int = 0
		if sym == 16:
			if index == 0:
				_failed = true
				return
			value = lens[index - 1]
			rep = 3 + _bits(2)
		elif sym == 17:
			rep = 3 + _bits(3)
		else:
			rep = 11 + _bits(7)
		if _failed or index + rep > total:
			_failed = true
			return
		for _k: int in rep:
			lens[index] = value
			index += 1
	if lens[256] == 0:
		_failed = true
		return
	var lit: Huffman = _build(lens.slice(0, nlen))
	var dist: Huffman = _build(lens.slice(nlen))
	if not _usable(lit, nlen) or not _usable(dist, ndist):
		_failed = true
		return
	_codes(lit, dist)


## Como en puff: un código incompleto solo vale si tiene un único símbolo.
static func _usable(h: Huffman, n: int) -> bool:
	if h == null:
		return false
	return h.left == 0 or n == h.counts[0] + h.counts[1]


## Código canónico a partir de las longitudes; null si está sobresuscrito.
static func _build(lengths: PackedInt32Array) -> Huffman:
	var h: Huffman = Huffman.new()
	h.counts.resize(_MAX_BITS + 1)
	h.counts.fill(0)
	for l: int in lengths:
		h.counts[l] += 1
	var left: int = 1
	for bl: int in range(1, _MAX_BITS + 1):
		left <<= 1
		left -= h.counts[bl]
		if left < 0:
			return null
	h.left = left if h.counts[0] != lengths.size() else 0
	var offs: PackedInt32Array = PackedInt32Array()
	offs.resize(_MAX_BITS + 1)
	offs.fill(0)
	for bl: int in range(1, _MAX_BITS):
		offs[bl + 1] = offs[bl] + h.counts[bl]
	h.symbols.resize(lengths.size())
	h.symbols.fill(0)
	for sym: int in lengths.size():
		var l: int = lengths[sym]
		if l != 0:
			h.symbols[offs[l]] = sym
			offs[l] += 1
	return h


static var _fixed_lit_code: Huffman = null
static var _fixed_dist_code: Huffman = null


static func _fixed_lit() -> Huffman:
	if _fixed_lit_code == null:
		var l: PackedInt32Array = PackedInt32Array()
		l.resize(288)
		for s: int in 288:
			l[s] = 8 if s < 144 else (9 if s < 256 else (7 if s < 280 else 8))
		_fixed_lit_code = _build(l)
	return _fixed_lit_code


static func _fixed_dist() -> Huffman:
	if _fixed_dist_code == null:
		var l: PackedInt32Array = PackedInt32Array()
		l.resize(30)
		l.fill(5)
		_fixed_dist_code = _build(l)
	return _fixed_dist_code
