class_name MapDelta
extends RefCounted
## Una edición manual serializable (PROYECTO §4.3 y §6.7: mapa = semilla +
## deltas). Los comandos de core/model/commands crean deltas al aplicarse; al
## cargar un mapa se regenera desde el código de semilla y se reaplican en
## orden.
##
## `op` identifica la operación (lo define cada comando, p. ej.
## "set_terrain"); `data` solo puede contener valores que admita
## CanonicalJson (enteros, textos, booleanos, listas y diccionarios con claves
## de texto): nada de float ni Vector2i.

var op: String = ""
var data: Dictionary = {}


static func make(p_op: String, p_data: Dictionary) -> MapDelta:
	var d: MapDelta = MapDelta.new()
	d.op = p_op
	d.data = p_data.duplicate(true)
	return d


func is_valid() -> bool:
	return not op.is_empty() and CanonicalJson.is_supported(data)


func copy() -> MapDelta:
	return MapDelta.make(op, data)


func to_dict() -> Dictionary:
	return {"op": op, "data": data.duplicate(true)}


## Los números de `data` llegan del JSON como float: se normalizan a int (si
## alguno no es entero, el lector falla).
static func from_dict(r: JsonReader, d: Dictionary) -> MapDelta:
	var normalized: Variant = _normalize(r, r.get_dict(d, "data"))
	var nd: Dictionary = r.to_dict(normalized, "data")
	return MapDelta.make(r.get_str(d, "op"), nd)


## Números de un valor leído de JSON (float) a int; para otros datos de
## sesión con la misma forma que `data` (ADR 040).
static func normalize(r: JsonReader, v: Variant) -> Variant:
	return _normalize(r, v)


static func _normalize(r: JsonReader, v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return r.to_int(v, "data")
		TYPE_ARRAY:
			var arr: Array = v
			var out: Array = []
			for item: Variant in arr:
				out.append(_normalize(r, item))
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = v
			var outd: Dictionary = {}
			for k: Variant in dict.keys():
				outd[k] = _normalize(r, dict[k])
			return outd
	return v
