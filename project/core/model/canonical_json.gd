class_name CanonicalJson
extends RefCounted
## Serialización JSON canónica (ADR 019): el mismo valor da siempre el mismo
## texto, en cualquier plataforma y versión del motor. Es la base del hash de
## MapDocument y, por tanto, de las seeds doradas.
##
## Reglas:
## - Tipos admitidos: null, bool, int, String, Array, Dictionary con claves
##   String, PackedByteArray, PackedInt32Array, PackedInt64Array y
##   PackedStringArray. Cualquier otro (float, Vector2i, Object…) es un error:
##   el modelo debe convertirlo antes a enteros o listas.
## - Diccionarios con las claves ordenadas por punto de código Unicode.
## - Sin espacios. Enteros en decimal. Textos con escape solo de `"`, `\` y
##   los caracteres de control (< 0x20, como \u00XX); el resto, tal cual (UTF-8).
##
## Por qué no JSON.stringify(sort_keys): su formato de números y escapes es
## del motor y podría cambiar entre versiones; aquí está fijado y probado.


## Texto canónico de `value`. Si contiene un tipo no admitido devuelve ""
## (nunca un JSON válido, así que no puede pasar por un hash correcto); usar
## is_supported() para comprobarlo antes.
static func stringify(value: Variant) -> String:
	var parts: Array[String] = []
	if not _write(value, parts):
		return ""
	return "".join(PackedStringArray(parts))


## true si `value` solo contiene tipos admitidos.
static func is_supported(value: Variant) -> bool:
	var parts: Array[String] = []
	return _write(value, parts)


## SHA-256 (hex en minúsculas) del texto canónico de `value`.
static func sha256(value: Variant) -> String:
	return stringify(value).sha256_text()


static func _write(v: Variant, out: Array[String]) -> bool:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			var b: bool = v
			out.append("true" if b else "false")
		TYPE_INT:
			var i: int = v
			out.append(str(i))
		TYPE_STRING:
			var s: String = v
			out.append(quote(s))
		TYPE_ARRAY:
			var arr: Array = v
			out.append("[")
			for k: int in arr.size():
				if k > 0:
					out.append(",")
				if not _write(arr[k], out):
					return false
			out.append("]")
		TYPE_PACKED_BYTE_ARRAY:
			var pb: PackedByteArray = v
			_write_ints(Array(pb), out)
		TYPE_PACKED_INT32_ARRAY:
			var p32: PackedInt32Array = v
			_write_ints(Array(p32), out)
		TYPE_PACKED_INT64_ARRAY:
			var p64: PackedInt64Array = v
			_write_ints(Array(p64), out)
		TYPE_PACKED_STRING_ARRAY:
			var ps: PackedStringArray = v
			out.append("[")
			for k: int in ps.size():
				if k > 0:
					out.append(",")
				out.append(quote(ps[k]))
			out.append("]")
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: PackedStringArray = PackedStringArray()
			for key: Variant in d.keys():
				if typeof(key) != TYPE_STRING:
					return false
				var ks: String = key
				keys.append(ks)
			keys.sort()
			out.append("{")
			for k: int in keys.size():
				if k > 0:
					out.append(",")
				out.append(quote(keys[k]))
				out.append(":")
				if not _write(d[keys[k]], out):
					return false
			out.append("}")
		_:
			return false
	return true


static func _write_ints(values: Array, out: Array[String]) -> void:
	var texts: PackedStringArray = PackedStringArray()
	texts.resize(values.size())
	for k: int in values.size():
		var n: int = values[k]
		texts[k] = str(n)
	out.append("[" + ",".join(texts) + "]")


## Texto JSON entre comillas con el escape canónico.
static func quote(s: String) -> String:
	var needs: bool = false
	for k: int in s.length():
		var c: int = s.unicode_at(k)
		if c < 0x20 or c == 0x22 or c == 0x5C:
			needs = true
			break
	if not needs:
		return "\"" + s + "\""
	var parts: PackedStringArray = PackedStringArray()
	for k: int in s.length():
		var c: int = s.unicode_at(k)
		if c == 0x22:
			parts.append("\\\"")
		elif c == 0x5C:
			parts.append("\\\\")
		elif c < 0x20:
			parts.append("\\u%04x" % c)
		else:
			parts.append(s[k])
	return "\"" + "".join(parts) + "\""
