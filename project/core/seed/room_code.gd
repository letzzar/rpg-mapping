class_name RoomCode
extends RefCounted
## Los dos identificadores de una estancia hecha a mano (editor E3, PROYECTO
## §5.5 y §6.7). Una estancia = código RPGM1 de su base (normalmente EST G3)
## + deltas de contenido (MapDelta).
##
## 1) Id corto, NO autosuficiente (se busca en la biblioteca local, el fichero
##    de campaña o, en red, en el DM):
##      RPGU1-<cuerpo>-<control>          ej.: RPGU1-NWJB9PTDPWF0-D
##    cuerpo = los 60 primeros bits (big-endian) del SHA-256 del contenido que
##    calcula quien llama, en 12 caracteres Base32 Crockford (longitud fija).
##    Por qué 60 bits: probabilidad de que dos estancias distintas compartan
##    id ≈ n²/2^61 (cumpleaños): 10 000 estancias → 4·10⁻¹¹; 1 000 000 →
##    4·10⁻⁷. Con 50 bits serían 4·10⁻⁸ y 4·10⁻⁴. 60 = 12 caracteres exactos
##    (sin bits de relleno); el id entero ocupa 20. No es una defensa contra
##    colisiones FABRICADAS (≈ 2^30 intentos): la biblioteca debe guardar la
##    huella completa y, si dos entradas comparten id, avisar.
##
## 2) Código para compartir, autosuficiente:
##      RPGS1-<carga>-<control>
##    carga = Base32 Crockford del flujo DEFLATE crudo (sin cabecera zlib ni
##    Adler-32: el control ya detecta erratas y el JSON se valida) de un JSON
##    canónico compacto (formato v1, el "1" de RPGS1):
##      [<código RPGM1 canónico>, <delta>, <delta>, …]
##    con cada delta como lista posicional cuyo primer elemento es el índice
##    de la op en OPS:
##      0 set_terrain   [0, level, terrain, x0, y0, x1, y1, …]  (casillas aplanadas)
##      1 set_edge      [1, level, edge, value]
##      2 add_object    [2, level, id, catalog_id, x, y, w, h, facing, cover,
##                       flags, light_bright, light_dim, interaction, height_mm, material]
##                       flags = difficult_terrain | blocks_movement<<1 | blocks_sight<<2
##      3 remove_object [3, level, id]
##      4 set_room      [4, level, room, kind, label]
##    Cambiar cualquier cosa de esta lista (orden, campos, índices) exige
##    RPGS2; los lectores conservan la v1.
##    Al escribir no se insertan guiones en la carga (más corto para el QR); al
##    leer se ignoran guiones y espacios internos de la carga.
##
## Control (ambos): un carácter Crockford calculado en GF(32) con
## SeedCode.check_value() (mismo polinomio y garantías que RPGM1: todas las
## sustituciones de un carácter y transposiciones adyacentes) sobre
## [dominio, 0, valores de los caracteres del cuerpo]; dominio 1 = RPGU1,
## 2 = RPGS1 (la U no está en el alfabeto, así que el prefijo entra como un
## símbolo, igual que la escala en RPGM1). Así un cuerpo con su control no
## vale bajo el otro prefijo.

const SHORT_PREFIX: String = "RPGU1"
const SHARE_PREFIX: String = "RPGS1"
const SEED_PREFIX: String = "RPGM1"

const KIND_SEED: String = "seed"
const KIND_SHORT: String = "short"
const KIND_SHARE: String = "share"

## Bits del SHA-256 que forman el id corto y su longitud en caracteres.
const SHORT_BITS: int = 60
const SHORT_LEN: int = 12
const DOMAIN_SHORT: int = 1
const DOMAIN_SHARE: int = 2

## Límites contra texto ajeno: caracteres del código (≈ 40 KB comprimidos) y
## bytes del JSON descomprimido (bombas de descompresión).
const MAX_SHARE_CHARS: int = 65536
const MAX_PAYLOAD_BYTES: int = 2 * 1024 * 1024
## Enteros exactos en JSON (double): |v| <= 2^53.
const MAX_JSON_INT: int = 1 << 53

## Operaciones de contenido por índice (formato v1; solo se añade al final).
const OPS: PackedStringArray = ["set_terrain", "set_edge", "add_object", "remove_object", "set_room"]

const ERR_FORMAT: String = "ROOM_ERR_FORMAT"
const ERR_CHECK: String = "ROOM_ERR_CHECK"
const ERR_TOO_BIG: String = "ROOM_ERR_TOO_BIG"
const ERR_VERSION: String = "ROOM_ERR_VERSION"


# --- Id corto -----------------------------------------------------------------

## Id corto a partir de la huella SHA-256 (32 bytes) del contenido. "" si la
## huella no tiene 32 bytes.
static func short_id(fingerprint: PackedByteArray) -> String:
	if fingerprint.size() != 32:
		return ""
	var v: int = 0
	for i: int in 8:
		v = (v << 8) | fingerprint[i]
	v = Bits64.lsr(v, 64 - SHORT_BITS)
	var body: String = ""
	for i: int in SHORT_LEN:
		body += Base32Crockford.ALPHABET[(v >> (5 * (SHORT_LEN - 1 - i))) & 31]
	return "%s-%s-%s" % [SHORT_PREFIX, body, check_char(DOMAIN_SHORT, body)]


## {"id": id canónico o "", "error": clave i18n o ""}. Tolera minúsculas,
## espacios y los alias O→0, I/L→1 en el cuerpo y el control.
static func parse_short_id(text: String) -> Dictionary:
	var parts: PackedStringArray = _clean(text).split("-")
	if parts.size() != 3 or parts[0] != SHORT_PREFIX:
		return {"id": "", "error": _prefix_error(parts[0], SHORT_PREFIX)}
	var body: String = _unalias(parts[1])
	var c: String = _unalias(parts[2])
	if body.length() != SHORT_LEN or not _is_crockford(body) or c.length() != 1:
		return {"id": "", "error": ERR_FORMAT}
	if check_char(DOMAIN_SHORT, body) != c:
		return {"id": "", "error": ERR_CHECK}
	return {"id": "%s-%s-%s" % [SHORT_PREFIX, body, c], "error": ""}


# --- Código para compartir ----------------------------------------------------

## Código autosuficiente de `seed_code` + `deltas` (solo ops de OPS; usar
## content_deltas() para quitar fichas, niebla y turnos). Mismo contenido →
## mismo código. Devuelve "" si el código de semilla no es válido, si algún
## delta no es de contenido o no se puede representar SIN PÉRDIDA (se
## comprueba leyendo el resultado), o si pasa de los límites.
##
## Determinismo: el JSON es canónico y lo comprime el zlib del motor (el mismo
## en escritorio y web, nivel de compression/formats/zlib/compression_level).
## Si un motor futuro comprimiera distinto, los códigos viejos se seguirían
## leyendo (el lector es propio, Inflate), solo cambiaría el texto nuevo.
static func share_code(seed_code: String, deltas: Array[MapDelta]) -> String:
	var sc: SeedCode = SeedCode.parse(seed_code)
	if not sc.is_valid():
		return ""
	var canon: String = sc.encode()
	var arr: Array = [canon]
	for dl: MapDelta in deltas:
		if dl == null or not dl.is_valid():
			return ""
		var item: Array = _pack(dl)
		if item.is_empty():
			return ""
		arr.append(item)
	var json: String = CanonicalJson.stringify(arr)
	if json.is_empty():
		return ""
	var raw: PackedByteArray = json.to_utf8_buffer()
	if raw.size() > MAX_PAYLOAD_BYTES:
		return ""
	var deflated: PackedByteArray = _strip_zlib(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	if deflated.is_empty():
		return ""
	var payload: String = Base32Crockford.encode_bytes(deflated)
	var code: String = "%s-%s-%s" % [SHARE_PREFIX, payload, check_char(DOMAIN_SHARE, payload)]
	if code.length() > MAX_SHARE_CHARS:
		return ""
	# Garantía de ida y vuelta exacta.
	var back: Dictionary = parse_share_code(code)
	var back_deltas: Array[MapDelta] = back["deltas"]
	if back["error"] != "" or back["seed_code"] != canon or not _same_deltas(back_deltas, deltas):
		return ""
	return code


## {"seed_code": String, "deltas": Array[MapDelta], "error": clave i18n o ""}.
## Orden: estructura → control → tamaño → descompresión → JSON → ops → código
## de semilla (con SeedCode.parse; su error, SEED_ERR_*, se devuelve tal cual).
static func parse_share_code(text: String) -> Dictionary:
	var t: String = _clean(text)
	if t.length() > MAX_SHARE_CHARS:
		return _share_result(ERR_TOO_BIG)
	if not t.begins_with(SHARE_PREFIX + "-"):
		return _share_result(_prefix_error(t.get_slice("-", 0), SHARE_PREFIX))
	var rest: String = t.substr(SHARE_PREFIX.length() + 1)
	var sep: int = rest.rfind("-")
	if sep < 0:
		return _share_result(ERR_FORMAT)
	var payload: String = _unalias(rest.substr(0, sep).replace("-", ""))
	var c: String = _unalias(rest.substr(sep + 1))
	if payload.is_empty() or not _is_crockford(payload) or c.length() != 1:
		return _share_result(ERR_FORMAT)
	if check_char(DOMAIN_SHARE, payload) != c:
		return _share_result(ERR_CHECK)
	var b: Base32Crockford.BytesResult = Base32Crockford.decode_bytes(payload)
	if not b.ok:
		return _share_result(ERR_FORMAT)
	var inf: Inflate.Result = Inflate.inflate_raw(b.bytes, MAX_PAYLOAD_BYTES)
	if inf.status == Inflate.STATUS_TOO_BIG:
		return _share_result(ERR_TOO_BIG)
	if inf.status != Inflate.STATUS_OK or not _is_utf8(inf.bytes):
		return _share_result(ERR_FORMAT)
	var j: JSON = JSON.new()
	if j.parse(inf.bytes.get_string_from_utf8()) != OK or typeof(j.data) != TYPE_ARRAY:
		return _share_result(ERR_FORMAT)
	var arr: Array = j.data
	if arr.is_empty() or typeof(arr[0]) != TYPE_STRING:
		return _share_result(ERR_FORMAT)
	var deltas: Array[MapDelta] = []
	for k: int in range(1, arr.size()):
		var dl: MapDelta = _unpack(arr[k])
		if dl == null:
			return _share_result(ERR_FORMAT)
		deltas.append(dl)
	var seed_text: String = arr[0]
	var sc: SeedCode = SeedCode.parse(seed_text)
	if not sc.is_valid():
		return _share_result(sc.error)
	return {"seed_code": sc.encode(), "deltas": deltas, "error": ""}


## Solo los deltas de contenido (ops de OPS), en su orden; quita fichas,
## niebla y turnos, que son de la partida y no de la estancia.
static func content_deltas(deltas: Array[MapDelta]) -> Array[MapDelta]:
	var out: Array[MapDelta] = []
	for dl: MapDelta in deltas:
		if dl != null and OPS.has(dl.op):
			out.append(dl)
	return out


# --- Tipo de texto -------------------------------------------------------------

## Tipo del texto de la caja del código: KIND_SEED (RPGM1), KIND_SHORT
## (RPGU1), KIND_SHARE (RPGS1) o "" (no se reconoce; no lo valida).
static func kind_of(text: String) -> String:
	var t: String = _clean(text)
	if t.begins_with(SEED_PREFIX + "-"):
		return KIND_SEED
	if t.begins_with(SHORT_PREFIX + "-"):
		return KIND_SHORT
	if t.begins_with(SHARE_PREFIX + "-"):
		return KIND_SHARE
	return ""


# --- Control ------------------------------------------------------------------

## Carácter de control de un cuerpo (texto Crockford canónico, sin alias) en
## el dominio dado (DOMAIN_SHORT o DOMAIN_SHARE). "" si no es representable.
static func check_char(domain: int, body: String) -> String:
	var symbols: PackedInt32Array = PackedInt32Array([domain, 0])
	for ch: String in body:
		var v: int = Base32Crockford.ALPHABET.find(ch)
		if v < 0:
			return ""
		symbols.append(v)
	return Base32Crockford.ALPHABET[SeedCode.check_value(symbols)]


# --- Formato compacto (v1) ------------------------------------------------------

## Lista compacta de un delta; [] si su op no es de contenido o le falta o
## sobra algo (lo segundo lo detecta la comprobación de ida y vuelta).
static func _pack(dl: MapDelta) -> Array:
	var p: _Packer = _Packer.new(dl.data)
	var idx: int = OPS.find(dl.op)
	var out: Array = [idx]
	match idx:
		0:
			out.append_array([p.int_of("level"), p.int_of("terrain")])
			var cells: Variant = dl.data.get("cells")
			if typeof(cells) != TYPE_ARRAY:
				return []
			var cell_list: Array = cells
			for pair: Variant in cell_list:
				if typeof(pair) != TYPE_ARRAY:
					return []
				var xy: Array = pair
				if xy.size() != 2:
					return []
				out.append_array([p.int_value(xy[0]), p.int_value(xy[1])])
		1:
			out.append_array([p.int_of("level"), p.int_of("edge"), p.int_of("value")])
		2:
			out.append_array([p.int_of("level"), p.int_of("id")])
			var obj: Variant = dl.data.get("object")
			if typeof(obj) != TYPE_DICTIONARY:
				return []
			var obj_dict: Dictionary = obj
			var o: _Packer = _Packer.new(obj_dict)
			var cell: Array = o.pair_of("cell")
			var size: Array = o.pair_of("size")
			var flags: int = (1 if o.bool_of("difficult_terrain") else 0) | (2 if o.bool_of("blocks_movement") else 0) \
				| (4 if o.bool_of("blocks_sight") else 0)
			out.append_array([o.str_of("catalog_id"), cell[0], cell[1], size[0], size[1], o.int_of("facing"),
				o.int_of("cover"), flags, o.int_of("light_bright_cells"), o.int_of("light_dim_cells"),
				o.str_of("interaction"), o.int_of("height_mm"), o.str_of("material")])
			if not o.ok or o.int_of("id") != p.int_of("id"):
				return []
		3:
			out.append_array([p.int_of("level"), p.int_of("id")])
		4:
			out.append_array([p.int_of("level"), p.int_of("room"), p.str_of("kind"), p.str_of("label")])
		_:
			return []
	return out if p.ok else []


## Delta a partir de su lista compacta (valores de JSON.parse: números en
## float); null si no es válida.
static func _unpack(v: Variant) -> MapDelta:
	if typeof(v) != TYPE_ARRAY:
		return null
	var a: Array = v
	var u: _Unpacker = _Unpacker.new(a)
	if a.is_empty():
		return null
	var idx: int = u.int_at(0)
	if not u.ok or idx < 0 or idx >= OPS.size():
		return null
	var data: Dictionary = {}
	match idx:
		0:
			if a.size() < 3 or (a.size() - 3) % 2 != 0:
				return null
			var cells: Array = []
			for k: int in range(3, a.size(), 2):
				cells.append([u.int_at(k), u.int_at(k + 1)])
			data = {"level": u.int_at(1), "terrain": u.int_at(2), "cells": cells}
		1:
			if a.size() != 4:
				return null
			data = {"level": u.int_at(1), "edge": u.int_at(2), "value": u.int_at(3)}
		2:
			if a.size() != 16:
				return null
			var o: MapObject = MapObject.new()
			o.id = u.int_at(2)
			o.catalog_id = u.str_at(3)
			o.cell = Vector2i(u.int_at(4), u.int_at(5))
			o.size = Vector2i(u.int_at(6), u.int_at(7))
			o.facing = u.int_at(8)
			o.cover = u.int_at(9)
			var flags: int = u.int_at(10)
			if flags < 0 or flags > 7:
				return null
			o.difficult_terrain = (flags & 1) != 0
			o.blocks_movement = (flags & 2) != 0
			o.blocks_sight = (flags & 4) != 0
			o.light_bright_cells = u.int_at(11)
			o.light_dim_cells = u.int_at(12)
			o.interaction = u.str_at(13)
			o.height_mm = u.int_at(14)
			o.material = u.str_at(15)
			data = {"level": u.int_at(1), "id": o.id, "object": o.to_dict()}
		3:
			if a.size() != 3:
				return null
			data = {"level": u.int_at(1), "id": u.int_at(2)}
		4:
			if a.size() != 5:
				return null
			data = {"level": u.int_at(1), "room": u.int_at(2), "kind": u.str_at(3), "label": u.str_at(4)}
	if not u.ok:
		return null
	return MapDelta.make(OPS[idx], data)


static func _same_deltas(a: Array[MapDelta], b: Array[MapDelta]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		var ta: String = CanonicalJson.stringify(a[i].to_dict())
		if ta.is_empty() or ta != CanonicalJson.stringify(b[i].to_dict()):
			return false
	return true


## Lee campos con tipo exacto de un diccionario de delta; `ok` = false al
## primer fallo (los valores devueltos entonces no importan).
class _Packer:
	extends RefCounted
	var ok: bool = true
	var _d: Dictionary = {}

	func _init(d: Dictionary) -> void:
		_d = d

	func int_value(v: Variant) -> int:
		if typeof(v) != TYPE_INT:
			ok = false
			return 0
		var i: int = v
		if i > RoomCode.MAX_JSON_INT or i < -RoomCode.MAX_JSON_INT:
			ok = false
			return 0
		return i

	func int_of(key: String) -> int:
		return int_value(_d.get(key))

	func str_of(key: String) -> String:
		var v: Variant = _d.get(key)
		if typeof(v) != TYPE_STRING:
			ok = false
			return ""
		var s: String = v
		return s

	func bool_of(key: String) -> bool:
		var v: Variant = _d.get(key)
		if typeof(v) != TYPE_BOOL:
			ok = false
			return false
		var b: bool = v
		return b

	func pair_of(key: String) -> Array:
		var v: Variant = _d.get(key)
		if typeof(v) != TYPE_ARRAY:
			ok = false
			return [0, 0]
		var a: Array = v
		if a.size() != 2:
			ok = false
			return [0, 0]
		return [int_value(a[0]), int_value(a[1])]


## Lee elementos de una lista de JSON.parse (enteros llegan como float).
class _Unpacker:
	extends RefCounted
	var ok: bool = true
	var _a: Array = []

	func _init(a: Array) -> void:
		_a = a

	func int_at(k: int) -> int:
		if k >= _a.size():
			ok = false
			return 0
		var v: Variant = _a[k]
		if typeof(v) == TYPE_INT:
			var i: int = v
			return i
		if typeof(v) != TYPE_FLOAT:
			ok = false
			return 0
		var f: float = v
		if f != floorf(f) or absf(f) > float(RoomCode.MAX_JSON_INT):
			ok = false
			return 0
		return int(f)

	func str_at(k: int) -> String:
		if k >= _a.size() or typeof(_a[k]) != TYPE_STRING:
			ok = false
			return ""
		var s: String = _a[k]
		return s


# --- Utilidades -----------------------------------------------------------------

static func _share_result(err: String) -> Dictionary:
	var none: Array[MapDelta] = []
	return {"seed_code": "", "deltas": none, "error": err}


## Mayúsculas y sin espacios, tabuladores ni saltos de línea (un QR o un
## correo pueden partir el código en líneas).
static func _clean(text: String) -> String:
	return text.strip_edges().to_upper().replace(" ", "").replace("\t", "").replace("\n", "").replace("\r", "")


## ROOM_ERR_VERSION si el prefijo es de la misma familia que `current` (p. ej.
## RPGS + dígitos) pero de otra versión; si no, ROOM_ERR_FORMAT.
static func _prefix_error(prefix: String, current: String) -> String:
	var family: String = current.left(current.length() - 1)
	var digits: String = prefix.substr(family.length())
	if prefix != current and prefix.begins_with(family) and not digits.is_empty() and digits.is_valid_int() and not digits.begins_with("-") and not digits.begins_with("+"):
		return ERR_VERSION
	return ERR_FORMAT


## Flujo zlib (cabecera de 2 bytes + DEFLATE + Adler-32) → DEFLATE crudo.
## [] si no tiene la forma esperada.
static func _strip_zlib(z: PackedByteArray) -> PackedByteArray:
	if z.size() < 7:
		return PackedByteArray()
	var cmf: int = z[0]
	var flg: int = z[1]
	if (cmf & 0x0F) != 8 or ((cmf << 8) | flg) % 31 != 0 or (flg & 0x20) != 0:
		return PackedByteArray()
	return z.slice(2, z.size() - 4)


static func _is_crockford(s: String) -> bool:
	for ch: String in s:
		if Base32Crockford.ALPHABET.find(ch) < 0:
			return false
	return true


## O -> 0, I/L -> 1 (texto ya en mayúsculas).
static func _unalias(s: String) -> String:
	return s.replace("O", "0").replace("I", "1").replace("L", "1")


## UTF-8 estricto (sin sobrelargos, sustitutos ni > U+10FFFF), para no pasar
## al motor bytes que le hagan imprimir errores.
static func _is_utf8(b: PackedByteArray) -> bool:
	var i: int = 0
	var n: int = b.size()
	while i < n:
		var c: int = b[i]
		var extra: int = 0
		var lo: int = 0x80
		var hi: int = 0xBF
		if c < 0x80:
			i += 1
			continue
		elif c >= 0xC2 and c <= 0xDF:
			extra = 1
		elif c == 0xE0:
			extra = 2
			lo = 0xA0
		elif c == 0xED:
			extra = 2
			hi = 0x9F
		elif c >= 0xE1 and c <= 0xEF:
			extra = 2
		elif c == 0xF0:
			extra = 3
			lo = 0x90
		elif c >= 0xF1 and c <= 0xF3:
			extra = 3
		elif c == 0xF4:
			extra = 3
			hi = 0x8F
		else:
			return false
		if i + extra >= n:
			return false
		for k: int in range(1, extra + 1):
			var cc: int = b[i + k]
			var low: int = lo if k == 1 else 0x80
			var high: int = hi if k == 1 else 0xBF
			if cc < low or cc > high:
				return false
		i += extra + 1
	return true
