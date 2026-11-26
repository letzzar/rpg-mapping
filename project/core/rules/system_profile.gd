class_name SystemProfile
extends RefCounted
## Perfil de sistema de juego leído de data/systems/<id>.json (PROYECTO.md §8).
##
## Reglas como datos (ADR 006): la lógica consulta estos campos; nunca
## compara el id del sistema. Formato descrito en
## data/schemas/system_profile.schema.json.

const DIR: String = "res://data/systems/"
const SCHEMA_VERSION: int = 1
const CORNER_ANY_SIDE_FREE: String = "any_side_free"
const CORNER_BOTH_SIDES_FREE: String = "both_sides_free"

## Formas de plantilla de área (area_templates[].shape).
const SHAPE_CIRCLE: String = "circle"
const SHAPE_CONE: String = "cone"
const SHAPE_SQUARE: String = "square"
const SHAPE_LINE: String = "line"
const SHAPE_EMANATION: String = "emanation"
const SHAPES: PackedStringArray = ["circle", "cone", "square", "line", "emanation"]
## Origen de un círculo (area_templates[].origin).
const ORIGIN_CORNER: String = "corner"
const ORIGIN_CELL: String = "cell"


## Geometría de una plantilla de área del perfil (area_templates[]). Las
## casillas que cubre las calcula AreaTemplate.cells().
class AreaTemplateSpec:
	extends RefCounted
	var id: String = ""
	## Uno de SHAPE_*.
	var shape: String = ""
	## Tamaño inicial en la interfaz: radio, lado o longitud según la forma.
	var default_ft: int = 0
	## Solo circle: ORIGIN_CORNER (intersección) u ORIGIN_CELL (centro).
	var origin: String = ""
	## Solo cone: anchura a cada distancia, en % de esa distancia.
	var cone_width_pct: int = 0
	## Solo line: anchura total en pies.
	var line_width_ft: int = 0
	## Solo emanation: si la huella de la criatura forma parte del área.
	var includes_origin: bool = false

	## SOLO VISTAS (float). Semiabertura del cono en radianes; 0 si no es cono.
	func cone_half_angle_rad() -> float:
		if shape != SHAPE_CONE:
			return 0.0
		return atan(cone_width_pct / 200.0)

var id: String = ""
var seed_code: String = ""
var name_key: String = ""
var license: String = ""
var attribution: String = ""
var attribution_verified: bool = false

var cell_ft: int = 5
## "grid" (se mide en pies) o "bands" (se muestra la banda de alcance).
var measure: String = "grid"

var default_speed_ft: int = 0
## Coste en pies de las diagonales sucesivas; se repite cíclicamente.
var diagonal_ft: PackedInt32Array = PackedInt32Array()
var diagonal_variants: Dictionary[String, PackedInt32Array] = {}
## Coste en pies de los pasos sucesivos en rejilla hexagonal; cíclico, como
## diagonal_ft (ADR 020: el coste por tipo de paso es dato del perfil).
var hex_step_ft: PackedInt32Array = PackedInt32Array()
## Paso diagonal junto a una esquina en la cuadrada: "any_side_free" (basta
## con que uno de los dos rodeos ortogonales esté libre) o "both_sides_free"
## (no se puede cortar ninguna esquina).
var diagonal_corner_rule: String = CORNER_ANY_SIDE_FREE
var difficult_multiplier_pct: int = 100
var difficult_extra_ft: int = 0
var difficult_visual_only: bool = false
var movement_modes: PackedStringArray = PackedStringArray()

var sizes_occupy_cells: bool = true
## Ids de tamaño en el orden del fichero.
var size_ids: PackedStringArray = PackedStringArray()
## id de tamaño → lado ocupado en décimas de pie (2,5 ft = 25).
var size_space_ft_x10: Dictionary[String, int] = {}
## id de tamaño → hexágonos ocupados en rejilla hex (1, 3, 7 o 19).
var size_hex_cells: Dictionary[String, int] = {}

## Ids de banda ordenados de menor a mayor alcance.
var band_ids: PackedStringArray = PackedStringArray()
## Casillas máximas de cada banda; -1 = sin límite (hasta el borde del mapa).
var band_max_cells: PackedInt32Array = PackedInt32Array()

var senses: PackedStringArray = PackedStringArray()
## Ids de las plantillas de área en el orden del fichero (el de la interfaz).
var area_templates: PackedStringArray = PackedStringArray()
## id de plantilla → su geometría (ver AreaTemplateSpec y AreaTemplate).
var area_template_specs: Dictionary[String, AreaTemplateSpec] = {}

## Mensaje técnico (para el log) si la carga falló; "" si es válido.
var error: String = ""


func is_valid() -> bool:
	return error.is_empty()


## Carga data/systems/<profile_id>.json. Siempre devuelve un perfil; mirar
## is_valid().
static func load_id(profile_id: String) -> SystemProfile:
	return load_path(DIR + profile_id + ".json")


static func load_path(path: String) -> SystemProfile:
	var p: SystemProfile = SystemProfile.new()
	if not FileAccess.file_exists(path):
		p.error = "no existe %s" % path
		return p
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		p.error = "%s no es un objeto JSON" % path
		return p
	var root: Dictionary = parsed
	p._read(root)
	if not p.is_valid():
		p.error = "%s: %s" % [path, p.error]
	return p


## Ids de todos los perfiles disponibles, ordenados (determinista).
static func available_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## Perfil cuyo seed_code (campo SIS del código RPGM1) es `code`; null si no
## hay ninguno. Recorre los perfiles en orden de id (determinista).
static func find_by_seed_code(code: String) -> SystemProfile:
	for pid: String in available_ids():
		var p: SystemProfile = load_id(pid)
		if p.is_valid() and p.seed_code == code:
			return p
	return null


## Patrón de coste (pies, cíclico) de un tipo de paso GridGeometry.STEP_*.
## Ortogonal = [cell_ft]; diagonal = diagonal_ft o la variante de mesa
## `diagonal_variant` (si existe); hex = hex_step_ft.
func step_pattern(step_kind: int, diagonal_variant: String = "") -> PackedInt32Array:
	match step_kind:
		GridGeometry.STEP_DIAGONAL:
			if not diagonal_variant.is_empty() and diagonal_variants.has(diagonal_variant):
				return diagonal_variants[diagonal_variant]
			return diagonal_ft
		GridGeometry.STEP_HEX:
			return hex_step_ft
	return PackedInt32Array([cell_ft])


## Casillas de lado que ocupa una criatura del tamaño `size_id`: el espacio
## del perfil redondeado hacia arriba a casillas, mínimo 1 (Diminuto comparte
## casilla). 1 si el perfil no hace ocupar casillas o el tamaño no existe.
func size_cells(size_id: String) -> int:
	if not sizes_occupy_cells or not size_space_ft_x10.has(size_id):
		return 1
	var cell_x10: int = cell_ft * 10
	return maxi(1, (size_space_ft_x10[size_id] + cell_x10 - 1) / cell_x10)


## Hexágonos que ocupa una criatura del tamaño `size_id` en rejilla hex
## (sizes[].hex_cells). 1 si el perfil no hace ocupar casillas o el tamaño no
## existe.
func size_hex_cells_of(size_id: String) -> int:
	if not sizes_occupy_cells or not size_hex_cells.has(size_id):
		return 1
	return size_hex_cells[size_id]


## Geometría de la plantilla de área `template_id`; null si el perfil no la
## tiene.
func area_template(template_id: String) -> AreaTemplateSpec:
	if not area_template_specs.has(template_id):
		return null
	return area_template_specs[template_id]


## Tamaño inicial (pies) de la plantilla `template_id`; 0 si no existe.
func area_template_default_ft(template_id: String) -> int:
	var spec: AreaTemplateSpec = area_template(template_id)
	return spec.default_ft if spec != null else 0


## Banda de alcance para una distancia en casillas ("" si el perfil no usa
## bandas o la distancia es negativa).
func band_for_cells(cells: int) -> String:
	if cells < 0:
		return ""
	for i: int in band_ids.size():
		if band_max_cells[i] < 0 or cells <= band_max_cells[i]:
			return band_ids[i]
	return ""


func _read(d: Dictionary) -> void:
	if _int(d, "schema_version") != SCHEMA_VERSION:
		_fail("schema_version distinto de %d" % SCHEMA_VERSION)
		return
	id = _str(d, "id")
	seed_code = _str(d, "seed_code")
	name_key = _str(d, "name_key")
	var content: Dictionary = _dict(d, "content")
	license = _str(content, "license")
	attribution = _str(content, "attribution")
	attribution_verified = _bool(content, "attribution_verified")

	var grid: Dictionary = _dict(d, "grid")
	cell_ft = _int(grid, "cell_ft")
	measure = _str(grid, "measure")
	if measure != "grid" and measure != "bands":
		_fail("grid.measure debe ser 'grid' o 'bands'")
	if cell_ft <= 0:
		_fail("grid.cell_ft debe ser > 0")

	var mv: Dictionary = _dict(d, "movement")
	default_speed_ft = _int(mv, "default_speed_ft")
	diagonal_ft = _int_array(mv, "diagonal_ft")
	if diagonal_ft.is_empty():
		_fail("movement.diagonal_ft vacío")
	var variants: Dictionary = _dict(mv, "diagonal_variants")
	var vkeys: Array = variants.keys()
	vkeys.sort()
	for k: Variant in vkeys:
		diagonal_variants[str(k)] = _int_array(variants, str(k))
	hex_step_ft = _int_array(mv, "hex_step_ft")
	if hex_step_ft.is_empty():
		_fail("movement.hex_step_ft vacío")
	for pattern: PackedInt32Array in [diagonal_ft, hex_step_ft]:
		for c: int in pattern:
			if c < 1:
				_fail("los costes de paso deben ser >= 1")
	diagonal_corner_rule = _str(mv, "diagonal_corner_rule")
	if diagonal_corner_rule != CORNER_ANY_SIDE_FREE and diagonal_corner_rule != CORNER_BOTH_SIDES_FREE:
		_fail("movement.diagonal_corner_rule debe ser '%s' o '%s'" % [CORNER_ANY_SIDE_FREE, CORNER_BOTH_SIDES_FREE])
	var dt: Dictionary = _dict(mv, "difficult_terrain")
	difficult_multiplier_pct = _int(dt, "multiplier_pct")
	difficult_extra_ft = _int(dt, "extra_ft_per_cell")
	difficult_visual_only = _bool(dt, "visual_only")
	movement_modes = _str_array(mv, "modes")

	sizes_occupy_cells = _bool(d, "sizes_occupy_cells")
	for s: Dictionary in _dict_array(d, "sizes"):
		var sid: String = _str(s, "id")
		size_ids.append(sid)
		size_space_ft_x10[sid] = _int(s, "space_ft_x10")
		var hc: int = _int(s, "hex_cells")
		if not GridGeometry.HEX_FOOTPRINTS.has(hc):
			_fail("sizes.hex_cells debe ser 1, 3, 7 o 19")
		size_hex_cells[sid] = hc

	var last_max: int = 0
	for b: Dictionary in _dict_array(d, "range_bands"):
		var m: int = _int(b, "max_cells")
		if last_max < 0 or (m >= 0 and m <= last_max):
			_fail("range_bands debe ir en orden creciente y terminar como mucho en una banda ilimitada")
		band_ids.append(_str(b, "id"))
		band_max_cells.append(m)
		last_max = m

	senses = _str_array(d, "senses")
	for t: Dictionary in _dict_array(d, "area_templates"):
		_read_area_template(t)
	if id.is_empty() or seed_code.is_empty() or name_key.is_empty():
		_fail("faltan id, seed_code o name_key")


## Cada forma exige sus campos y rechaza los de las demás (como el esquema),
## para que un error de datos no pase desapercibido.
func _read_area_template(t: Dictionary) -> void:
	var spec: AreaTemplateSpec = AreaTemplateSpec.new()
	spec.id = _str(t, "id")
	spec.shape = _str(t, "shape")
	spec.default_ft = _int(t, "default_ft")
	if not SHAPES.has(spec.shape):
		_fail("area_templates.shape debe ser uno de %s" % ", ".join(SHAPES))
	if spec.default_ft < 1:
		_fail("area_templates.default_ft debe ser >= 1")
	if area_template_specs.has(spec.id):
		_fail("area_templates: id repetido '%s'" % spec.id)
	var own: Dictionary[String, String] = {
		"origin": SHAPE_CIRCLE,
		"cone_width_pct": SHAPE_CONE,
		"line_width_ft": SHAPE_LINE,
		"includes_origin": SHAPE_EMANATION,
	}
	for key: String in own.keys():
		if t.has(key) and own[key] != spec.shape:
			_fail("area_templates.%s solo vale para la forma '%s'" % [key, own[key]])
	match spec.shape:
		SHAPE_CIRCLE:
			spec.origin = _str(t, "origin")
			if spec.origin != ORIGIN_CORNER and spec.origin != ORIGIN_CELL:
				_fail("area_templates.origin debe ser '%s' o '%s'" % [ORIGIN_CORNER, ORIGIN_CELL])
		SHAPE_CONE:
			spec.cone_width_pct = _int(t, "cone_width_pct")
			if spec.cone_width_pct < 1 or spec.cone_width_pct > 1000:
				_fail("area_templates.cone_width_pct debe estar entre 1 y 1000")
		SHAPE_LINE:
			spec.line_width_ft = _int(t, "line_width_ft")
			if spec.line_width_ft < 1:
				_fail("area_templates.line_width_ft debe ser >= 1")
		SHAPE_EMANATION:
			spec.includes_origin = _bool(t, "includes_origin")
	area_templates.append(spec.id)
	area_template_specs[spec.id] = spec


func _fail(msg: String) -> void:
	if error.is_empty():
		error = msg


# --- Lectura tipada de JSON (los números llegan como float) -----------------

func _has(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		_fail("falta '%s'" % key)
		return false
	return true


func _int(d: Dictionary, key: String) -> int:
	if not _has(d, key):
		return 0
	var v: Variant = d[key]
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
	_fail("'%s' debe ser entero" % key)
	return 0


func _str(d: Dictionary, key: String) -> String:
	if not _has(d, key):
		return ""
	if typeof(d[key]) != TYPE_STRING:
		_fail("'%s' debe ser texto" % key)
		return ""
	return str(d[key])


func _bool(d: Dictionary, key: String) -> bool:
	if not _has(d, key):
		return false
	if typeof(d[key]) != TYPE_BOOL:
		_fail("'%s' debe ser booleano" % key)
		return false
	return d[key]


func _dict(d: Dictionary, key: String) -> Dictionary:
	if not _has(d, key):
		return {}
	if typeof(d[key]) != TYPE_DICTIONARY:
		_fail("'%s' debe ser objeto" % key)
		return {}
	return d[key]


func _array(d: Dictionary, key: String) -> Array:
	if not _has(d, key):
		return []
	if typeof(d[key]) != TYPE_ARRAY:
		_fail("'%s' debe ser lista" % key)
		return []
	return d[key]


func _int_array(d: Dictionary, key: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var arr: Array = _array(d, key)
	for i: int in arr.size():
		out.append(_int({"v": arr[i]}, "v"))
	return out


func _str_array(d: Dictionary, key: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for v: Variant in _array(d, key):
		if typeof(v) != TYPE_STRING:
			_fail("'%s' debe contener textos" % key)
			continue
		out.append(str(v))
	return out


func _dict_array(d: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Variant in _array(d, key):
		if typeof(v) != TYPE_DICTIONARY:
			_fail("'%s' debe contener objetos" % key)
			continue
		out.append(v)
	return out
