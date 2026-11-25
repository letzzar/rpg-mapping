class_name AldData
extends RefCounted
## Datos del generador ALD (PROYECTO §6.3, ADR 027): tamaños de asentamiento,
## tipos de edificio con sus habitantes y niveles de prosperidad
## (data/settlements/ald_settlement_types.json) y el bloque opcional
## "settlement" de los estilos (data/styles/<id>.json, ADR 015). Esquemas en
## data/schemas/. Son entrada del generador: cambiarlos cambia su salida y
## exige subir GEN.
##
## Se valida al cargar (AldData.error) lo que el esquema JSON no expresa: tipos
## existentes en EDI, ids únicos, intervalos ordenados, algún peso > 0 por
## tamaño y la plaza dentro del mapa.

const PATH: String = "res://data/settlements/ald_settlement_types.json"
const SCHEMA_VERSION: int = 1
## Ids del tamaño EDI en el orden de los pesos de prosperidad.
const EDI_SIZE_IDS: PackedStringArray = ["small", "medium", "large"]
const DEFAULT_TURN_PERMILLE: int = 180


class SizeSpec:
	extends RefCounted
	var id: String = ""
	var map: Vector2i = Vector2i.ZERO
	## [mín, máx] (x, y).
	var buildings: Vector2i = Vector2i.ZERO
	var main_width: int = 1
	var street_width: int = 1
	var lane_width: int = 1
	var crossroads_permille: int = 0
	var branch_every: Vector2i = Vector2i.ZERO
	var branch_length: Vector2i = Vector2i.ZERO
	var branch_levels: int = 1
	var grid_block: Vector2i = Vector2i.ZERO
	var plaza: Vector2i = Vector2i.ZERO
	var yard: int = 0
	var river_width: int = 3
	var extra_floor_permille: int = 0
	var required: PackedStringArray = PackedStringArray()
	## Pesos en el orden de AldData.type_ids.
	var type_weights: PackedInt32Array = PackedInt32Array()


class Prosperity:
	extends RefCounted
	var id: String = ""
	## % por tipo, en el orden de AldData.type_ids.
	var type_pct: PackedInt32Array = PackedInt32Array()
	## Pesos en el orden de EDI_SIZE_IDS.
	var edi_size_weights: PackedInt32Array = PackedInt32Array()
	var cellar_permille: int = 0
	var clutter: int = 5


class StyleSettlement:
	extends RefCounted
	## % por tipo, en el orden de AldData.type_ids.
	var type_pct: PackedInt32Array = PackedInt32Array()
	var turn_permille: int = DEFAULT_TURN_PERMILLE


## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
## Tipos de edificio en el orden de los datos.
var type_ids: PackedStringArray = PackedStringArray()
var residents: PackedInt32Array = PackedInt32Array()
var size_ids: PackedStringArray = PackedStringArray()
var prosperity_ids: PackedStringArray = PackedStringArray()
var _sizes: Dictionary[String, SizeSpec] = {}
var _prosperity: Dictionary[String, Prosperity] = {}
var _styles: Dictionary[String, StyleSettlement] = {}

static var _default: AldData = null


func is_valid() -> bool:
	return error.is_empty()


static func load_default() -> AldData:
	if _default == null:
		_default = AldData.new()
		_default._load(PATH, EstData.STYLES_DIR, EstData.load_default(), EdiData.load_default())
	return _default


func size_spec(id: String) -> SizeSpec:
	if not _sizes.has(id):
		return null
	var s: SizeSpec = _sizes[id]
	return s


func prosperity(id: String) -> Prosperity:
	if not _prosperity.has(id):
		return null
	var p: Prosperity = _prosperity[id]
	return p


func style_settlement(id: String) -> StyleSettlement:
	if not _styles.has(id):
		return null
	var s: StyleSettlement = _styles[id]
	return s


## Habitantes que aporta un edificio del tipo (0 si no existe).
func residents_of(type_id: String) -> int:
	var i: int = type_ids.find(type_id)
	return residents[i] if i >= 0 else 0


func _load(path: String, styles_dir: String, est: EstData, edi: EdiData) -> void:
	var r: JsonReader = JsonReader.new()
	if not est.is_valid():
		r.fail("datos EST: " + est.error)
	if not edi.is_valid():
		r.fail("datos EDI: " + edi.error)
	var root: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(path)), path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version de asentamientos")
	for d: Dictionary in r.get_dicts(root, "building_types"):
		var tid: String = r.get_str(d, "id")
		if edi.building_type(tid) == null:
			r.fail("tipo de edificio '%s' no existe en EDI" % tid)
		if type_ids.has(tid):
			r.fail("tipo de edificio repetido '%s'" % tid)
		type_ids.append(tid)
		var res: int = r.get_int(d, "residents")
		if res < 0:
			r.fail("%s: residents < 0" % tid)
		residents.append(res)
	if type_ids.is_empty():
		r.fail("sin tipos de edificio")
	for d: Dictionary in r.get_dicts(root, "sizes"):
		if not r.ok():
			break
		var s: SizeSpec = _read_size(r, d)
		if s.id.is_empty() or _sizes.has(s.id):
			r.fail("tamaño vacío o repetido")
		_sizes[s.id] = s
		size_ids.append(s.id)
	for d: Dictionary in r.get_dicts(root, "prosperity"):
		if not r.ok():
			break
		var p: Prosperity = Prosperity.new()
		p.id = r.get_str(d, "id")
		if p.id.is_empty() or _prosperity.has(p.id):
			r.fail("prosperidad vacía o repetida")
		p.type_pct = _pct_by_type(r, r.get_dict(d, "type_weight_pct"), p.id)
		var sw: Dictionary = r.get_dict(d, "edi_size_weights")
		var total: int = 0
		for sid: String in EDI_SIZE_IDS:
			var w: int = r.get_int(sw, sid)
			if w < 0:
				r.fail("%s: peso de tamaño < 0" % p.id)
			total += w
			p.edi_size_weights.append(w)
		if total <= 0:
			r.fail("%s: todos los pesos de tamaño son 0" % p.id)
		p.cellar_permille = r.get_int(d, "cellar_permille")
		p.clutter = r.get_int(d, "clutter")
		if p.cellar_permille < 0 or p.cellar_permille > 1000 or p.clutter < 0 or p.clutter > 10:
			r.fail("%s: cellar_permille o clutter fuera de rango" % p.id)
		_prosperity[p.id] = p
		prosperity_ids.append(p.id)
	# Bloque "settlement" de cada estilo (mismos ficheros que lee EstData).
	for sid: String in est.style_ids:
		if not r.ok():
			break
		var sd: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(styles_dir + sid + ".json")), sid)
		var ss: StyleSettlement = StyleSettlement.new()
		var empty: Dictionary = {}
		ss.type_pct = _pct_by_type(r, empty, sid)
		if sd.has("settlement"):
			var b: Dictionary = r.get_dict(sd, "settlement")
			if b.has("type_weight_pct"):
				ss.type_pct = _pct_by_type(r, r.get_dict(b, "type_weight_pct"), sid)
			if b.has("turn_permille"):
				ss.turn_permille = r.get_int(b, "turn_permille")
			if ss.turn_permille < 0 or ss.turn_permille > 1000:
				r.fail("%s: turn_permille fuera de rango" % sid)
		_styles[sid] = ss
	if not r.ok():
		error = r.error


func _read_size(r: JsonReader, d: Dictionary) -> SizeSpec:
	var s: SizeSpec = SizeSpec.new()
	s.id = r.get_str(d, "id")
	s.map = r.get_vec2i(d, "map")
	s.buildings = r.get_vec2i(d, "buildings")
	s.main_width = r.get_int(d, "main_width")
	s.street_width = r.get_int(d, "street_width")
	s.lane_width = r.get_int(d, "lane_width")
	s.crossroads_permille = r.get_int(d, "crossroads_permille")
	s.branch_every = r.get_vec2i(d, "branch_every")
	s.branch_length = r.get_vec2i(d, "branch_length")
	s.branch_levels = r.get_int(d, "branch_levels")
	s.grid_block = r.get_vec2i(d, "grid_block")
	s.plaza = r.get_vec2i(d, "plaza")
	s.yard = r.get_int(d, "yard")
	s.river_width = r.get_int(d, "river_width")
	s.extra_floor_permille = r.get_int(d, "extra_floor_permille")
	for v: Variant in r.get_array(d, "required"):
		var t: String = r.to_str(v, "required")
		if not type_ids.has(t):
			r.fail("%s: tipo obligatorio desconocido '%s'" % [s.id, t])
		s.required.append(t)
	var tw: Dictionary = r.get_dict(d, "type_weights")
	var total: int = 0
	for tid: String in type_ids:
		var w: int = 0
		if tw.has(tid):
			w = r.to_int(tw[tid], tid)
		if w < 0:
			r.fail("%s: peso < 0" % s.id)
		total += w
		s.type_weights.append(w)
	var tw_keys: Array = tw.keys()
	tw_keys.sort()
	for k: Variant in tw_keys:
		var key: String = r.to_str(k, "type_weights")
		if not type_ids.has(key):
			r.fail("%s: tipo desconocido en type_weights '%s'" % [s.id, key])
	if total <= 0:
		r.fail("%s: todos los pesos son 0" % s.id)
	var ranges: Array[Vector2i] = [s.buildings, s.branch_every, s.branch_length]
	for rg: Vector2i in ranges:
		if rg.x < 0 or rg.y < rg.x:
			r.fail("%s: intervalo [mín, máx] no válido" % s.id)
	if s.branch_every.x < 2 or s.branch_length.x < 1:
		r.fail("%s: branch_every >= 2 y branch_length >= 1" % s.id)
	if s.map.x < 32 or s.map.y < 32 or s.map.x > 512 or s.map.y > 512:
		r.fail("%s: mapa fuera de 32-512" % s.id)
	if s.plaza.x < 1 or s.plaza.y < 1 or s.plaza.x * 3 > s.map.x or s.plaza.y * 3 > s.map.y:
		r.fail("%s: la plaza no cabe" % s.id)
	for w2: int in [s.main_width, s.street_width, s.lane_width]:
		if w2 < 1 or w2 > 6:
			r.fail("%s: ancho de calle fuera de 1-6" % s.id)
	if s.grid_block.x < 8 or s.grid_block.y < 8:
		r.fail("%s: grid_block < 8" % s.id)
	return s


## Diccionario tipo -> % en un array en el orden de type_ids (100 si falta).
func _pct_by_type(r: JsonReader, d: Dictionary, what: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for tid: String in type_ids:
		var v: int = 100
		if d.has(tid):
			v = r.to_int(d[tid], tid)
		if v < 0:
			r.fail("%s: %% < 0" % what)
		out.append(v)
	var keys: Array = d.keys()
	keys.sort()
	for k: Variant in keys:
		var key: String = r.to_str(k, what)
		if not type_ids.has(key):
			r.fail("%s: tipo desconocido '%s'" % [what, key])
	return out
