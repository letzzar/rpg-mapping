class_name EstData
extends RefCounted
## Datos del generador EST: tipos de estancia (data/rooms/est_room_types.json)
## y estilos (data/styles/<id>.json, ADR 015). Esquemas en data/schemas/.
## Son entrada del generador: cambiarlos cambia su salida y exige subir GEN.

const ROOM_TYPES_PATH: String = "res://data/rooms/est_room_types.json"
const STYLES_DIR: String = "res://data/styles/"
const SCHEMA_VERSION: int = 1
const SIZE_IDS: PackedStringArray = ["small", "medium", "large"]


class RoomType:
	extends RefCounted
	var id: String = ""
	## "small", "medium" o "large".
	var auto_size: String = "medium"
	## Objetos que se intentan colocar siempre, en orden.
	var required: PackedStringArray = PackedStringArray()
	## Opcionales: id, peso y máximo (mismos índices).
	var optional_ids: PackedStringArray = PackedStringArray()
	var optional_weights: PackedInt32Array = PackedInt32Array()
	var optional_max: PackedInt32Array = PackedInt32Array()


class Style:
	extends RefCounted
	var id: String = ""
	var name_key: String = ""
	## Clase de material -> material.
	var materials: Dictionary[String, String] = {}
	## id de objeto -> % del peso (100 si no aparece).
	var weight_pct: Dictionary[String, int] = {}

	func material_for(material_class: String) -> String:
		if materials.has(material_class):
			var m: String = materials[material_class]
			return m
		return ""

	func weight_factor_pct(object_id: String) -> int:
		if weight_pct.has(object_id):
			var w: int = weight_pct[object_id]
			return w
		return 100


## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
var room_type_ids: PackedStringArray = PackedStringArray()
var style_ids: PackedStringArray = PackedStringArray()
var _room_types: Dictionary[String, RoomType] = {}
var _styles: Dictionary[String, Style] = {}

static var _default: EstData = null


func is_valid() -> bool:
	return error.is_empty()


static func load_default() -> EstData:
	if _default == null:
		_default = EstData.new()
		_default._load(ROOM_TYPES_PATH, STYLES_DIR, ObjectCatalog.load_default())
	return _default


func room_type(id: String) -> RoomType:
	if not _room_types.has(id):
		return null
	var t: RoomType = _room_types[id]
	return t


func style(id: String) -> Style:
	if not _styles.has(id):
		return null
	var s: Style = _styles[id]
	return s


func _load(rooms_path: String, styles_dir: String, catalog: ObjectCatalog) -> void:
	var r: JsonReader = JsonReader.new()
	if not catalog.is_valid():
		r.fail("catálogo: " + catalog.error)
	var root: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(rooms_path)), rooms_path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version de tipos de estancia")
	for d: Dictionary in r.get_dicts(root, "room_types"):
		var t: RoomType = RoomType.new()
		t.id = r.get_str(d, "id")
		t.auto_size = r.get_str(d, "auto_size")
		if not SIZE_IDS.has(t.auto_size):
			r.fail("%s: auto_size desconocido" % t.id)
		for v: Variant in r.get_array(d, "required"):
			t.required.append(r.to_str(v, "required"))
		for od: Dictionary in r.get_dicts(d, "optional"):
			t.optional_ids.append(r.get_str(od, "object"))
			t.optional_weights.append(r.get_int(od, "weight"))
			t.optional_max.append(r.get_int(od, "max"))
		for oid: String in t.required + t.optional_ids:
			if not catalog.has(oid):
				r.fail("%s: objeto desconocido '%s'" % [t.id, oid])
		if t.id.is_empty() or _room_types.has(t.id):
			r.fail("tipo de estancia vacío o repetido")
		if not r.ok():
			break
		_room_types[t.id] = t
		room_type_ids.append(t.id)
	var files: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(styles_dir):
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	for f: String in files:
		var sd: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(styles_dir + f)), f)
		if not r.ok():
			break
		if r.get_int(sd, "schema_version") != SCHEMA_VERSION:
			r.fail("%s: schema_version" % f)
		var s: Style = Style.new()
		s.id = r.get_str(sd, "id")
		s.name_key = r.get_str(sd, "name_key")
		if s.id != f.get_basename():
			r.fail("%s: el id debe coincidir con el nombre del fichero" % f)
		var mats: Dictionary = r.get_dict(sd, "materials")
		for mc: String in ObjectCatalog.MATERIAL_CLASSES:
			s.materials[mc] = r.get_str(mats, mc)
		var weights: Dictionary = r.get_dict(sd, "furniture_weight_pct")
		var keys: Array = weights.keys()
		keys.sort()
		for k: Variant in keys:
			var key: String = r.to_str(k, "furniture_weight_pct")
			s.weight_pct[key] = r.to_int(weights[key], key)
			if not catalog.has(key):
				r.fail("%s: objeto desconocido '%s'" % [f, key])
		if not r.ok():
			break
		_styles[s.id] = s
		style_ids.append(s.id)
	if not r.ok():
		error = r.error
