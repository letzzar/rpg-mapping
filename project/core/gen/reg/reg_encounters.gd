class_name RegEncounters
extends RefCounted
## Tablas ABIERTAS de encuentros por bioma de una región (PROYECTO §6.2):
## data/regions/encounters.json. Solo etiquetas genéricas (i18n "ENC_" + tag
## en mayúsculas), sin contenido de reglas con licencia; el DM puede editar
## el fichero. NO forman parte de la generación: ningún mapa ni seed dorada
## depende de ellas. Si un bioma no tiene tabla, se usa "default".

const PATH: String = "res://data/regions/encounters.json"

class Entry:
	extends RefCounted
	var tag: String = ""
	var weight: int = 1

static var _default: RegEncounters = null

var _tables: Dictionary[String, Array] = {}
var _fallback: Array[Entry] = []
var error: String = ""


static func load_default() -> RegEncounters:
	if _default == null:
		_default = RegEncounters.new()
		_default._load(PATH)
	return _default


func is_valid() -> bool:
	return error.is_empty()


## Tabla del bioma `biome` (Biome.*), en el orden del fichero.
func table_for(biome: int) -> Array[Entry]:
	var out: Array[Entry] = []
	var id: String = Biome.IDS[biome] if Biome.is_valid(biome) else ""
	var src: Array = _tables.get(id, _fallback)
	for e: Variant in src:
		var en: Entry = e
		out.append(en)
	return out


## Etiqueta al azar de la tabla del bioma (pesos), con el Rng que pase la
## sesión (no la generación). "" si la tabla está vacía.
func roll(biome: int, rng: Rng) -> String:
	var table: Array[Entry] = table_for(biome)
	if table.is_empty():
		return ""
	var weights: PackedInt32Array = PackedInt32Array()
	for e: Entry in table:
		weights.append(e.weight)
	return table[rng.pick_weighted(weights)].tag


func _load(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		error = "encounters.json no es un objeto JSON"
		return
	var d: Dictionary = parsed
	_fallback = _read_list(d.get("default", []))
	var biomes: Variant = d.get("biomes", {})
	if typeof(biomes) != TYPE_DICTIONARY:
		error = "'biomes' debe ser un objeto"
		return
	var bd: Dictionary = biomes
	for k: Variant in bd:
		var key: String = str(k)
		if not Biome.IDS.has(key):
			error = "bioma desconocido: " + key
			return
		_tables[key] = _read_list(bd[k])


func _read_list(v: Variant) -> Array[Entry]:
	var out: Array[Entry] = []
	if typeof(v) != TYPE_ARRAY:
		error = "una tabla debe ser una lista"
		return out
	var arr: Array = v
	for item: Variant in arr:
		if typeof(item) != TYPE_DICTIONARY:
			error = "entrada de tabla no válida"
			return out
		var it: Dictionary = item
		var e: Entry = Entry.new()
		e.tag = str(it.get("tag", ""))
		var wv: Variant = it.get("weight", 1)
		e.weight = 0
		if typeof(wv) == TYPE_INT:
			var wi: int = wv
			e.weight = wi
		elif typeof(wv) == TYPE_FLOAT:
			var wf: float = wv
			e.weight = int(wf)
		if e.tag.is_empty() or e.weight <= 0:
			error = "entrada sin 'tag' o con peso <= 0"
			return out
		out.append(e)
	return out
