class_name ObjectCatalog
extends RefCounted
## Catálogo de objetos colocables (data/objects/*.json, PROYECTO §6.5, ADR 023).
## Esquema: data/schemas/object_catalog.schema.json. Nombre visible: clave
## i18n "OBJ_" + id.to_upper().
##
## Se leen todos los *.json de DIR en orden alfabético; un id repetido es un
## error. Los generadores lo usan como datos: cambiar un objeto que coloquen
## cambia su salida y exige subir su GEN.

const DIR: String = "res://data/objects/"
const SCHEMA_VERSION: int = 1
const COVER_IDS: PackedStringArray = ["none", "half", "three_quarters", "total"]
const MATERIAL_CLASSES: PackedStringArray = ["furniture", "stone", "metal", "fabric", "none"]
## Etiquetas de colocación (las de §6.5 con nombre en inglés):
## contra_pared = against_wall, centro = center, junto_a:<id> = near:<id>.
const TAG_AGAINST_WALL: String = "against_wall"
const TAG_CENTER: String = "center"
const TAG_NEAR_PREFIX: String = "near:"


## Un objeto del catálogo.
class Entry:
	extends RefCounted
	var id: String = ""
	## [ancho, fondo] en casillas, mirando al norte (facing 0).
	var size: Vector2i = Vector2i.ONE
	var placement: PackedStringArray = PackedStringArray()
	var material_class: String = "none"
	var cover: int = MapObject.COVER_NONE
	var difficult_terrain: bool = false
	var blocks_movement: bool = false
	var blocks_sight: bool = false
	var light_bright_cells: int = 0
	var light_dim_cells: int = 0
	var interaction: String = ""
	var height_mm: int = 0

	func has_tag(tag: String) -> bool:
		return placement.has(tag)

	## Id de la etiqueta near:<id>, o "" si no tiene.
	func near_id() -> String:
		for t: String in placement:
			if t.begins_with("near:"):
				return t.substr(5)
		return ""


## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
## Ids ordenados.
var ids: PackedStringArray = PackedStringArray()
var _entries: Dictionary[String, Entry] = {}

static var _default: ObjectCatalog = null


func is_valid() -> bool:
	return error.is_empty()


## Catálogo de res://data/objects (se carga una vez y se reutiliza).
static func load_default() -> ObjectCatalog:
	if _default == null:
		_default = load_dir(DIR)
	return _default


static func load_dir(dir: String) -> ObjectCatalog:
	var cat: ObjectCatalog = ObjectCatalog.new()
	var files: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	if files.is_empty():
		cat.error = "no hay ficheros en %s" % dir
	for f: String in files:
		cat._read_file(dir + f)
	cat.ids.sort()
	return cat


func has(id: String) -> bool:
	return _entries.has(id)


## Entrada `id`; null si no existe.
func entry(id: String) -> Entry:
	if not _entries.has(id):
		return null
	var e: Entry = _entries[id]
	return e


## MapObject con las propiedades de juego copiadas de la entrada (ADR 019).
func instantiate(e: Entry, object_id: int, cell: Vector2i, facing: int, material: String) -> MapObject:
	var o: MapObject = MapObject.new()
	o.id = object_id
	o.catalog_id = e.id
	o.cell = cell
	o.size = e.size
	o.facing = facing
	o.cover = e.cover
	o.difficult_terrain = e.difficult_terrain
	o.blocks_movement = e.blocks_movement
	o.blocks_sight = e.blocks_sight
	o.light_bright_cells = e.light_bright_cells
	o.light_dim_cells = e.light_dim_cells
	o.interaction = e.interaction
	o.height_mm = e.height_mm
	o.material = material
	return o


func _read_file(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var r: JsonReader = JsonReader.new()
	var root: Dictionary = r.to_dict(parsed, path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version distinto de %d" % SCHEMA_VERSION)
	for d: Dictionary in r.get_dicts(root, "objects"):
		if not r.ok():
			break
		var e: Entry = Entry.new()
		e.id = r.get_str(d, "id")
		e.size = r.get_vec2i(d, "size")
		for v: Variant in r.get_array(d, "placement"):
			e.placement.append(r.to_str(v, "placement"))
		e.material_class = r.get_str(d, "material_class")
		e.cover = COVER_IDS.find(r.get_str(d, "cover"))
		e.difficult_terrain = r.get_bool(d, "difficult_terrain")
		e.blocks_movement = r.get_bool(d, "blocks_movement")
		e.blocks_sight = r.get_bool(d, "blocks_sight")
		e.light_bright_cells = r.get_int(d, "light_bright_cells")
		e.light_dim_cells = r.get_int(d, "light_dim_cells")
		e.interaction = r.get_str(d, "interaction")
		e.height_mm = r.get_int(d, "height_mm")
		if e.id.is_empty() or _entries.has(e.id):
			r.fail("id vacío o repetido: '%s'" % e.id)
		elif e.cover < 0:
			r.fail("%s: cover desconocido" % e.id)
		elif not MATERIAL_CLASSES.has(e.material_class):
			r.fail("%s: material_class desconocida" % e.id)
		elif e.size.x < 1 or e.size.y < 1:
			r.fail("%s: size debe ser >= 1" % e.id)
		for t: String in e.placement:
			if t != TAG_AGAINST_WALL and t != TAG_CENTER and not t.begins_with(TAG_NEAR_PREFIX):
				r.fail("%s: etiqueta desconocida '%s'" % [e.id, t])
		if r.ok():
			_entries[e.id] = e
			ids.append(e.id)
	if not r.ok() and error.is_empty():
		error = "%s: %s" % [path, r.error]
