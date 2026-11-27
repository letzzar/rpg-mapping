class_name LootKinds
extends RefCounted
## Tipos de objeto del botín (data/loot/item_kinds.json, ADR 049): con qué
## icono se ve cada línea y qué palabras del nombre lo delatan ("Espada
## corta" → sword, "120 monedas de oro" → coins). Nombres visibles: claves
## i18n LOOT_KIND_<ID>. Los iconos los da LootIcons.

const PATH: String = "res://data/loot/item_kinds.json"
const SCHEMA_VERSION: int = 1


class Kind:
	extends RefCounted
	var id: String = ""
	## Objeto KayKit cuyo icono renderizado se usa; "" = dibujado por código.
	var model: String = ""
	## Palabras normalizadas (minúsculas, sin tildes), cada una en tokens.
	var words: Array[PackedStringArray] = []


var error: String = ""
var kinds: Array[Kind] = []

static var _default: LootKinds = null


static func load_default() -> LootKinds:
	if _default == null:
		_default = LootKinds.new()
		_default._read(PATH)
	return _default


func is_valid() -> bool:
	return error.is_empty()


func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Kind in kinds:
		out.append(k.id)
	return out


func kind(id: String) -> Kind:
	for k: Kind in kinds:
		if k.id == id:
			return k
	return null


## Tipo que delata el nombre `item_name` ("" si ninguno): el primero de la
## lista con una palabra que aparezca entera (también en plural: -s, -es).
func guess(item_name: String) -> String:
	var tokens: PackedStringArray = tokens_of(item_name)
	if tokens.is_empty():
		return ""
	for k: Kind in kinds:
		for w: PackedStringArray in k.words:
			if _contains(tokens, w):
				return k.id
	return ""


## Minúsculas, sin tildes y partido en palabras (letras y números).
static func tokens_of(text: String) -> PackedStringArray:
	var s: String = text.to_lower()
	const FROM: String = "áàäâéèëêíìïîóòöôúùüûñç"
	const TO: String = "aaaaeeeeiiiioooouuuunc"
	var out: String = ""
	for ch: String in s:
		var i: int = FROM.find(ch)
		if i >= 0:
			out += TO[i]
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		else:
			out += " "
	return out.split(" ", false)


static func _contains(tokens: PackedStringArray, word: PackedStringArray) -> bool:
	if word.is_empty() or word.size() > tokens.size():
		return false
	for start: int in tokens.size() - word.size() + 1:
		var ok: bool = true
		for j: int in word.size():
			var t: String = tokens[start + j]
			var w: String = word[j]
			if t != w and t != w + "s" and t != w + "es":
				ok = false
				break
		if ok:
			return true
	return false


func _read(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var r: JsonReader = JsonReader.new()
	var root: Dictionary = r.to_dict(parsed, path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version distinto de %d" % SCHEMA_VERSION)
	for d: Dictionary in r.get_dicts(root, "kinds"):
		var k: Kind = Kind.new()
		k.id = r.get_str(d, "id")
		if d.has("model"):
			k.model = r.get_str(d, "model")
		for v: Variant in r.get_array(d, "words"):
			var toks: PackedStringArray = tokens_of(r.to_str(v, "words"))
			if not toks.is_empty():
				k.words.append(toks)
		if k.id.is_empty() or kind(k.id) != null or k.id.length() > LootItem.MAX_KIND:
			r.fail("tipo vacío, repetido o largo: '%s'" % k.id)
		kinds.append(k)
	if not r.ok():
		error = "%s: %s" % [path, r.error]
