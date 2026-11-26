class_name ObjectModels
extends RefCounted
## Modelos 3D de los objetos del catálogo (data/models/objects.json, ADR
## 041): cada uno, una lista de primitivas como las de los personajes
## (LookCatalog.Shape). x y z en casillas desde el centro de la huella
## (mirando al norte: frente a -z), y en metros. Solo para las vistas: no
## cambia el contenido de ningún mapa ni las seeds doradas.
##
## Un objeto sin modelo se dibuja como antes (una caja de su altura).

const PATH: String = "res://data/models/objects.json"
const SCHEMA_VERSION: int = 1

## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
var palette: Dictionary[String, Color] = {}
var _models: Dictionary[String, Array] = {}

static var _default: ObjectModels = null


static func load_default() -> ObjectModels:
	if _default == null:
		_default = load_path(PATH)
	return _default


static func load_path(path: String) -> ObjectModels:
	var m: ObjectModels = ObjectModels.new()
	m._read(path)
	return m


func has(catalog_id: String) -> bool:
	return _models.has(catalog_id)


## Ids con modelo, ordenados.
func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_models.keys())
	out.sort()
	return out


func shapes(catalog_id: String) -> Array[LookCatalog.Shape]:
	var out: Array[LookCatalog.Shape] = []
	if _models.has(catalog_id):
		for s: LookCatalog.Shape in _models[catalog_id]:
			out.append(s)
	return out


func color_of(mat: String) -> Color:
	if mat.begins_with("#"):
		return Color.html(mat)
	return palette.get(mat, Color.MAGENTA)


func _read(path: String) -> void:
	var parsed: Variant = CharacterSheet.parse_json_quiet(FileAccess.get_file_as_string(path))
	var r: JsonReader = JsonReader.new()
	var root: Dictionary = r.to_dict(parsed, path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version distinto de %d" % SCHEMA_VERSION)
	var pal: Dictionary = r.get_dict(root, "palette")
	for k: Variant in pal:
		var hex: String = r.to_str(pal[k], "palette")
		if not Color.html_is_valid(hex):
			r.fail("color no válido '%s'" % hex)
			continue
		palette[r.to_str(k, "palette")] = Color.html(hex)
	# Las primitivas se leen con el lector de LookCatalog, con esta paleta
	# como materiales.
	var reader: LookCatalog = LookCatalog.new()
	reader.materials = palette
	var models: Dictionary = r.get_dict(root, "models")
	var keys: Array = models.keys()
	keys.sort()
	for k: Variant in keys:
		var id: String = r.to_str(k, "models")
		_models[id] = reader.read_shapes(r, r.to_array(models[k], id))
	if not r.ok():
		error = "%s: %s" % [path, r.error]
