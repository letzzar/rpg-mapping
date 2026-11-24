class_name Base32Crockford
extends RefCounted
## Base32 de Crockford (https://www.crockford.com/base32.html).
##
## Por qué: sin I, L, O ni U, insensible a mayúsculas y tolerante a erratas
## típicas al dictar o copiar un código (O→0, I/L→1).

const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## Caracteres de un uint64 codificado (65 bits ≥ 64; el primero vale 0..15).
const U64_LEN: int = 13


## Resultado de decode_u64().
class U64Result:
	var ok: bool = false
	var value: int = 0

	func _init(p_ok: bool = false, p_value: int = 0) -> void:
		ok = p_ok
		value = p_value


## Resultado de decode_bytes().
class BytesResult:
	var ok: bool = false
	var bytes: PackedByteArray = PackedByteArray()

	func _init(p_ok: bool = false, p_bytes: PackedByteArray = PackedByteArray()) -> void:
		ok = p_ok
		bytes = p_bytes


## Valor 0..31 de un carácter, o -1 si no es válido. Aplica los alias de
## Crockford (O→0, I/L→1) y acepta minúsculas.
static func char_value(c: String) -> int:
	var u: String = c.to_upper()
	if u == "O":
		return 0
	if u == "I" or u == "L":
		return 1
	return ALPHABET.find(u)


## uint64 → 13 caracteres, con ceros a la izquierda (longitud fija).
static func encode_u64(value: int) -> String:
	var out: String = ""
	for i: int in range(U64_LEN - 1, -1, -1):
		out += ALPHABET[Bits64.lsr(value, i * 5) & 31]
	return out


## 13 caracteres → uint64 (como int64).
static func decode_u64(text: String) -> U64Result:
	if text.length() != U64_LEN:
		return U64Result.new()
	var v: int = 0
	for i: int in U64_LEN:
		var d: int = char_value(text[i])
		if d < 0 or (i == 0 and d > 15):
			return U64Result.new()
		v = (v << 5) | d
	return U64Result.new(true, v)


## Bytes → Base32 (MSB primero, último grupo rellenado con ceros, sin '=').
static func encode_bytes(data: PackedByteArray) -> String:
	var out: String = ""
	var buffer: int = 0
	var bits: int = 0
	for b: int in data:
		buffer = (buffer << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHABET[(buffer >> bits) & 31]
		buffer &= (1 << bits) - 1
	if bits > 0:
		out += ALPHABET[(buffer << (5 - bits)) & 31]
	return out


## Base32 → bytes. Rechaza
## caracteres inválidos, longitudes imposibles y bits de relleno distintos de 0
## (así cada secuencia de bytes tiene una única representación).
static func decode_bytes(text: String) -> BytesResult:
	var out: PackedByteArray = PackedByteArray()
	var buffer: int = 0
	var bits: int = 0
	for c: String in text:
		var d: int = char_value(c)
		if d < 0:
			return BytesResult.new()
		buffer = (buffer << 5) | d
		bits += 5
		if bits >= 8:
			bits -= 8
			out.append((buffer >> bits) & 0xFF)
			buffer &= (1 << bits) - 1
	if bits >= 5 or buffer != 0:
		return BytesResult.new()
	return BytesResult.new(true, out)
