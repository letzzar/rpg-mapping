class_name LookCatalog
extends RefCounted
## Catálogo de aspectos de personaje (data/characters/look_catalog.json,
## PROYECTO §10.2, ADR 034): complexiones, piezas por ranura, colores por
## material y modelos tipo. Esquema: data/schemas/look_catalog.schema.json.
## Nombres visibles: claves i18n CHAR_BODY_*, CHAR_SLOT_*, CHAR_PART_*,
## CHAR_MAT_* y CHAR_PRESET_* (id en mayúsculas).
##
## Cada pieza es una lista de primitivas (caja, esfera, cilindro, cono) en
## coordenadas de una figura de altura 1, mirando a +Z. Así se añaden piezas
## sin tocar código; los modelos CC0 de §10.2 podrán sustituirlas más adelante.

const PATH: String = "res://data/characters/look_catalog.json"
const SCHEMA_VERSION: int = 1
const SHAPES: PackedStringArray = ["box", "sphere", "cylinder", "cone"]


## Una primitiva de una pieza.
class Shape:
	extends RefCounted
	var shape: String = "box"
	## Id de material del catálogo, o color fijo "#rrggbb".
	var mat: String = ""
	var pos: Vector3 = Vector3.ZERO
	## Medidas totales (ancho, alto, fondo).
	var size: Vector3 = Vector3.ONE
	## Giro en grados (X, Y, Z).
	var rot: Vector3 = Vector3.ZERO
	## Cilindro: radio de arriba / radio de abajo.
	var taper: float = 1.0


class Body:
	extends RefCounted
	var id: String = ""
	var family: String = ""
	## Escala horizontal (X y Z) de la figura.
	var width: float = 1.0
	var slots: PackedStringArray = PackedStringArray()
	var defaults: Dictionary[String, String] = {}


class Part:
	extends RefCounted
	var id: String = ""
	var slot: String = ""
	var family: String = ""
	var shapes: Array[Shape] = []


class Preset:
	extends RefCounted
	var id: String = ""
	var body: String = ""
	var size_id: String = "medium"
	var parts: Dictionary[String, String] = {}
	var colors: Dictionary[String, Color] = {}


## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
## Material → color por defecto, en el orden del fichero.
var materials: Dictionary[String, Color] = {}
var slots: PackedStringArray = PackedStringArray()
var bodies: Array[Body] = []
var presets: Array[Preset] = []
var _base: Dictionary[String, Array] = {}
var _parts: Dictionary[String, Part] = {}
var _part_order: Array[Part] = []

static var _default: LookCatalog = null


func is_valid() -> bool:
	return error.is_empty()


static func load_default() -> LookCatalog:
	if _default == null:
		_default = load_path(PATH)
	return _default


static func load_path(path: String) -> LookCatalog:
	var cat: LookCatalog = LookCatalog.new()
	cat._read(path)
	return cat


func body(id: String) -> Body:
	for b: Body in bodies:
		if b.id == id:
			return b
	return null


func part(id: String) -> Part:
	if not _parts.has(id):
		return null
	var p: Part = _parts[id]
	return p


func preset(id: String) -> Preset:
	for p: Preset in presets:
		if p.id == id:
			return p
	return null


## Primitivas fijas de una familia ("humanoid"…).
func base_shapes(family: String) -> Array[Shape]:
	var out: Array[Shape] = []
	if _base.has(family):
		for s: Shape in _base[family]:
			out.append(s)
	return out


## Piezas que puede llevar la complexión `body_id` en la ranura `slot`, en
## el orden del fichero.
func parts_for(body_id: String, slot: String) -> Array[Part]:
	var out: Array[Part] = []
	var b: Body = body(body_id)
	if b == null or not b.slots.has(slot):
		return out
	for p: Part in _part_order:
		if p.slot == slot and p.family == b.family:
			out.append(p)
	return out


## Color de `mat` en `look` (o el fijo "#rrggbb", o el del catálogo).
func color_of(look: CharacterLook, mat: String) -> Color:
	if mat.begins_with("#"):
		return Color.html(mat)
	if look != null and look.colors.has(mat):
		return look.colors[mat]
	return materials.get(mat, Color.MAGENTA)


## Aspecto inicial de una complexión (sus piezas por defecto).
func default_look(body_id: String) -> CharacterLook:
	var l: CharacterLook = CharacterLook.new()
	l.body = body_id
	var b: Body = body(body_id)
	if b != null:
		l.parts = b.defaults.duplicate()
	return l


## Aspecto de un modelo tipo.
func look_from_preset(p: Preset) -> CharacterLook:
	var l: CharacterLook = CharacterLook.new()
	l.body = p.body
	l.parts = p.parts.duplicate()
	l.colors = p.colors.duplicate()
	return l


## Deja el aspecto en algo que el catálogo sabe dibujar: complexión conocida,
## solo ranuras de esa complexión con piezas de su familia y materiales
## conocidos. Devuelve true si tuvo que cambiar algo.
func sanitize(look: CharacterLook) -> bool:
	var changed: bool = false
	var b: Body = body(look.body)
	if b == null:
		look.body = bodies[0].id if not bodies.is_empty() else ""
		look.parts = default_look(look.body).parts
		b = body(look.body)
		changed = true
	for slot: String in look.parts.keys():
		var p: Part = part(look.parts[slot])
		if b == null or not b.slots.has(slot) or p == null or p.slot != slot or p.family != b.family:
			look.parts.erase(slot)
			changed = true
	for m: String in look.colors.keys():
		if not materials.has(m):
			look.colors.erase(m)
			changed = true
	return changed


func _read(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var r: JsonReader = JsonReader.new()
	var root: Dictionary = r.to_dict(parsed, path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version distinto de %d" % SCHEMA_VERSION)
	var mats: Dictionary = r.get_dict(root, "materials")
	for k: Variant in mats:
		materials[r.to_str(k, "materials")] = _color(r, mats[k])
	for v: Variant in r.get_array(root, "slots"):
		slots.append(r.to_str(v, "slots"))
	var families: PackedStringArray = PackedStringArray()
	for d: Dictionary in r.get_dicts(root, "bodies"):
		var b: Body = Body.new()
		b.id = r.get_str(d, "id")
		b.family = r.get_str(d, "family")
		b.width = _num(r, d, "width")
		for v: Variant in r.get_array(d, "slots"):
			var s: String = r.to_str(v, "slots")
			if not slots.has(s):
				r.fail("%s: ranura desconocida '%s'" % [b.id, s])
			b.slots.append(s)
		var defs: Dictionary = r.get_dict(d, "defaults")
		for k: Variant in defs:
			b.defaults[r.to_str(k, "defaults")] = r.to_str(defs[k], "defaults")
		if b.id.is_empty() or body(b.id) != null:
			r.fail("complexión vacía o repetida: '%s'" % b.id)
		bodies.append(b)
		if not families.has(b.family):
			families.append(b.family)
	var base: Dictionary = r.get_dict(root, "base")
	for f: String in families:
		if not base.has(f):
			r.fail("falta base de la familia '%s'" % f)
			continue
		_base[f] = _shapes(r, r.to_array(base[f], "base." + f))
	for d: Dictionary in r.get_dicts(root, "parts"):
		var p: Part = Part.new()
		p.id = r.get_str(d, "id")
		p.slot = r.get_str(d, "slot")
		p.family = r.get_str(d, "family")
		p.shapes = _shapes(r, r.get_array(d, "shapes"))
		if p.id.is_empty() or _parts.has(p.id):
			r.fail("pieza vacía o repetida: '%s'" % p.id)
		elif not slots.has(p.slot):
			r.fail("%s: ranura desconocida" % p.id)
		elif not families.has(p.family):
			r.fail("%s: familia desconocida" % p.id)
		_parts[p.id] = p
		_part_order.append(p)
	for b: Body in bodies:
		for s: String in b.defaults:
			var p: Part = part(b.defaults[s])
			if p == null or p.slot != s or p.family != b.family:
				r.fail("%s: pieza por defecto no válida en '%s'" % [b.id, s])
	for d: Dictionary in r.get_dicts(root, "presets"):
		var pr: Preset = Preset.new()
		pr.id = r.get_str(d, "id")
		pr.body = r.get_str(d, "body")
		pr.size_id = r.get_str(d, "size_id")
		var pp: Dictionary = r.get_dict(d, "parts")
		for k: Variant in pp:
			pr.parts[r.to_str(k, "parts")] = r.to_str(pp[k], "parts")
		var pc: Dictionary = r.get_dict(d, "colors")
		for k: Variant in pc:
			pr.colors[r.to_str(k, "colors")] = _color(r, pc[k])
		presets.append(pr)
		if r.ok() and sanitize(look_from_preset(pr)):
			r.fail("modelo tipo '%s' con piezas o colores no válidos" % pr.id)
	if not r.ok():
		error = "%s: %s" % [path, r.error]


## Lee una lista de primitivas con los materiales de este catálogo (también
## lo usa ObjectModels con su propia paleta).
func read_shapes(r: JsonReader, arr: Array) -> Array[Shape]:
	return _shapes(r, arr)


func _shapes(r: JsonReader, arr: Array) -> Array[Shape]:
	var out: Array[Shape] = []
	for v: Variant in arr:
		var d: Dictionary = r.to_dict(v, "shapes")
		var s: Shape = Shape.new()
		s.shape = r.get_str(d, "shape")
		s.mat = r.get_str(d, "mat")
		s.pos = _vec3(r, d, "pos")
		s.size = _vec3(r, d, "size")
		if d.has("rot"):
			s.rot = _vec3(r, d, "rot")
		if d.has("taper"):
			s.taper = _num(r, d, "taper")
		if not SHAPES.has(s.shape):
			r.fail("forma desconocida '%s'" % s.shape)
		if s.mat.begins_with("#"):
			if not Color.html_is_valid(s.mat):
				r.fail("color no válido '%s'" % s.mat)
		elif not materials.has(s.mat):
			r.fail("material desconocido '%s'" % s.mat)
		out.append(s)
	return out


func _num(r: JsonReader, d: Dictionary, key: String) -> float:
	if not d.has(key) or (typeof(d[key]) != TYPE_FLOAT and typeof(d[key]) != TYPE_INT):
		r.fail("'%s' debe ser número" % key)
		return 0.0
	var f: float = d[key]
	return f


func _vec3(r: JsonReader, d: Dictionary, key: String) -> Vector3:
	var a: Array = r.get_array(d, key)
	if a.size() != 3:
		r.fail("'%s' debe tener 3 números" % key)
		return Vector3.ZERO
	var out: Vector3 = Vector3.ZERO
	for i: int in 3:
		if typeof(a[i]) != TYPE_FLOAT and typeof(a[i]) != TYPE_INT:
			r.fail("'%s' debe tener 3 números" % key)
			return Vector3.ZERO
		var f: float = a[i]
		out[i] = f
	return out


func _color(r: JsonReader, v: Variant) -> Color:
	var s: String = r.to_str(v, "color")
	if not Color.html_is_valid(s):
		r.fail("color no válido '%s'" % s)
		return Color.MAGENTA
	return Color.html(s)
