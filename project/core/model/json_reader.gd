class_name JsonReader
extends RefCounted
## Lectura tipada de valores JSON ya analizados (JSON.parse_string), con el
## primer error acumulado en `error`. JSON.parse_string entrega los números
## como float: aquí se aceptan solo si son enteros exactos.
##
## Uso: var r := JsonReader.new(); var w: int = r.get_int(d, "width");
## al final, comprobar r.ok().

## Primer error (técnico, para el log); "" si todo fue bien.
var error: String = ""


func ok() -> bool:
	return error.is_empty()


func fail(msg: String) -> void:
	if error.is_empty():
		error = msg


## Variant -> int (acepta float entero exacto).
func to_int(v: Variant, what: String) -> int:
	if typeof(v) == TYPE_INT:
		var i: int = v
		return i
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
	fail("'%s' debe ser entero" % what)
	return 0


func to_str(v: Variant, what: String) -> String:
	if typeof(v) != TYPE_STRING:
		fail("'%s' debe ser texto" % what)
		return ""
	var s: String = v
	return s


func to_bool(v: Variant, what: String) -> bool:
	if typeof(v) != TYPE_BOOL:
		fail("'%s' debe ser booleano" % what)
		return false
	var b: bool = v
	return b


func to_dict(v: Variant, what: String) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		fail("'%s' debe ser objeto" % what)
		return {}
	var d: Dictionary = v
	return d


func to_array(v: Variant, what: String) -> Array:
	if typeof(v) != TYPE_ARRAY:
		fail("'%s' debe ser lista" % what)
		return []
	var a: Array = v
	return a


func get_int(d: Dictionary, key: String) -> int:
	if not d.has(key):
		fail("falta '%s'" % key)
		return 0
	return to_int(d[key], key)


func get_str(d: Dictionary, key: String) -> String:
	if not d.has(key):
		fail("falta '%s'" % key)
		return ""
	return to_str(d[key], key)


func get_bool(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		fail("falta '%s'" % key)
		return false
	return to_bool(d[key], key)


func get_dict(d: Dictionary, key: String) -> Dictionary:
	if not d.has(key):
		fail("falta '%s'" % key)
		return {}
	return to_dict(d[key], key)


func get_array(d: Dictionary, key: String) -> Array:
	if not d.has(key):
		fail("falta '%s'" % key)
		return []
	return to_array(d[key], key)


## Lista de enteros.
func get_ints(d: Dictionary, key: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var arr: Array = get_array(d, key)
	out.resize(arr.size())
	for k: int in arr.size():
		out[k] = to_int(arr[k], key)
	return out


## Lista de dos enteros [x, y] -> Vector2i.
func get_vec2i(d: Dictionary, key: String) -> Vector2i:
	var p: PackedInt32Array = get_ints(d, key)
	if p.size() != 2:
		fail("'%s' debe ser [x, y]" % key)
		return Vector2i.ZERO
	return Vector2i(p[0], p[1])


## Lista de objetos.
func get_dicts(d: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Variant in get_array(d, key):
		out.append(to_dict(v, key))
	return out
