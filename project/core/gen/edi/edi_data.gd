class_name EdiData
extends RefCounted
## Datos del generador EDI (PROYECTO §6.4, ADR 026): tipos de edificio
## (data/buildings/edi_building_types.json) y el bloque opcional "building" de
## los estilos (data/styles/<id>.json, ADR 015). Esquemas en data/schemas/.
## Son entrada del generador: cambiarlos cambia su salida y exige subir GEN.
##
## Se valida al cargar (EdiData.error) lo que el esquema JSON no expresa:
## tipos de estancia existentes en EST, claves únicas, una estancia no hub
## como mínimo en cada planta, adyacencias dentro de la misma planta y las
## estancias especiales (entrada, puerta trasera, escaleras) en la planta baja.

const BUILDING_TYPES_PATH: String = "res://data/buildings/edi_building_types.json"
const SCHEMA_VERSION: int = 1
const SIZE_IDS: PackedStringArray = ["small", "medium", "large"]
const FLOOR_CELLAR: String = "cellar"
const FLOOR_GROUND: String = "ground"
const FLOOR_UPPER: String = "upper"
const FLOOR_CLASSES: PackedStringArray = ["cellar", "ground", "upper"]
## Lado mínimo de la huella en los datos (2 × lado mínimo de estancia).
const MIN_FOOTPRINT_SIDE: int = 6
const MAX_FOOTPRINT_SIDE: int = 64


## Estancia de un tipo de edificio.
class RoomSpec:
	extends RefCounted
	var key: String = ""
	## Tipo de estancia EST (amueblado y nombre visible).
	var kind: String = ""
	## FLOOR_CELLAR, FLOOR_GROUND o FLOOR_UPPER.
	var floor_class: String = ""
	## Peso del área (0 en el hub).
	var area: int = 0
	var hub: bool = false
	var windows: bool = true


class BuildingType:
	extends RefCounted
	var id: String = ""
	var auto_size: String = "medium"
	var floors: int = 1
	## Huella [ancho, alto] por índice de SIZE_IDS.
	var footprints: Array[Vector2i] = []
	var upper_shrink_permille: int = 0
	var window_permille: int = 0
	var back_door_permille: int = 0
	var entrance: String = ""
	var back_door: String = ""
	var stairs_up: String = ""
	var stairs_down: String = ""
	## En orden de prioridad.
	var rooms: Array[RoomSpec] = []
	## Pares de claves.
	var adjacency: Array[PackedStringArray] = []

	## Estancias de una planta, en orden.
	func rooms_on(floor_class: String) -> Array[RoomSpec]:
		var out: Array[RoomSpec] = []
		for r: RoomSpec in rooms:
			if r.floor_class == floor_class:
				out.append(r)
		return out

	func room(key: String) -> RoomSpec:
		for r: RoomSpec in rooms:
			if r.key == key:
				return r
		return null

	func footprint(size_id: String) -> Vector2i:
		var i: int = SIZE_IDS.find(size_id)
		return footprints[i] if i >= 0 and i < footprints.size() else Vector2i.ZERO


## Bloque "building" de un estilo.
class StyleBuilding:
	extends RefCounted
	var footprint_pct: int = 100
	var window_pct: int = 100


## Mensaje técnico si la carga falló; "" si es válido.
var error: String = ""
var building_type_ids: PackedStringArray = PackedStringArray()
var _types: Dictionary[String, BuildingType] = {}
var _styles: Dictionary[String, StyleBuilding] = {}

static var _default: EdiData = null


func is_valid() -> bool:
	return error.is_empty()


static func load_default() -> EdiData:
	if _default == null:
		_default = EdiData.new()
		_default._load(BUILDING_TYPES_PATH, EstData.STYLES_DIR, EstData.load_default())
	return _default


func building_type(id: String) -> BuildingType:
	if not _types.has(id):
		return null
	var t: BuildingType = _types[id]
	return t


## Bloque "building" del estilo; null si el estilo no existe.
func style_building(id: String) -> StyleBuilding:
	if not _styles.has(id):
		return null
	var s: StyleBuilding = _styles[id]
	return s


func _load(path: String, styles_dir: String, est: EstData) -> void:
	var r: JsonReader = JsonReader.new()
	if not est.is_valid():
		r.fail("datos EST: " + est.error)
	var root: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(path)), path)
	if r.ok() and r.get_int(root, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version de tipos de edificio")
	for d: Dictionary in r.get_dicts(root, "building_types"):
		if not r.ok():
			break
		var t: BuildingType = _read_type(r, d, est)
		if t.id.is_empty() or _types.has(t.id):
			r.fail("tipo de edificio vacío o repetido")
		if not r.ok():
			break
		_types[t.id] = t
		building_type_ids.append(t.id)
	# Bloque "building" de cada estilo (mismos ficheros que lee EstData).
	for sid: String in est.style_ids:
		if not r.ok():
			break
		var sd: Dictionary = r.to_dict(JSON.parse_string(FileAccess.get_file_as_string(styles_dir + sid + ".json")), sid)
		var sb: StyleBuilding = StyleBuilding.new()
		if sd.has("building"):
			var b: Dictionary = r.get_dict(sd, "building")
			if b.has("footprint_pct"):
				sb.footprint_pct = r.get_int(b, "footprint_pct")
			if b.has("window_pct"):
				sb.window_pct = r.get_int(b, "window_pct")
			if sb.footprint_pct < 50 or sb.footprint_pct > 200 or sb.window_pct < 0 or sb.window_pct > 400:
				r.fail("%s: building fuera de rango" % sid)
		_styles[sid] = sb
	if not r.ok():
		error = r.error


func _read_type(r: JsonReader, d: Dictionary, est: EstData) -> BuildingType:
	var t: BuildingType = BuildingType.new()
	t.id = r.get_str(d, "id")
	t.auto_size = r.get_str(d, "auto_size")
	if not SIZE_IDS.has(t.auto_size):
		r.fail("%s: auto_size desconocido" % t.id)
	t.floors = r.get_int(d, "floors")
	if t.floors < 1 or t.floors > 4:
		r.fail("%s: floors fuera de 1-4" % t.id)
	var fps: Dictionary = r.get_dict(d, "footprints")
	for sid: String in SIZE_IDS:
		var dims: Vector2i = r.get_vec2i(fps, sid)
		if dims.x < MIN_FOOTPRINT_SIDE or dims.y < MIN_FOOTPRINT_SIDE or dims.x > MAX_FOOTPRINT_SIDE or dims.y > MAX_FOOTPRINT_SIDE:
			r.fail("%s: huella %s fuera de rango" % [t.id, sid])
		t.footprints.append(dims)
	t.upper_shrink_permille = r.get_int(d, "upper_shrink_permille")
	t.window_permille = r.get_int(d, "window_permille")
	t.back_door_permille = r.get_int(d, "back_door_permille")
	for pm: int in [t.upper_shrink_permille, t.window_permille, t.back_door_permille]:
		if pm < 0 or pm > 1000:
			r.fail("%s: ‰ fuera de 0-1000" % t.id)
	t.entrance = r.get_str(d, "entrance")
	t.back_door = r.get_str(d, "back_door")
	t.stairs_up = r.get_str(d, "stairs_up")
	t.stairs_down = r.get_str(d, "stairs_down")
	for rd: Dictionary in r.get_dicts(d, "rooms"):
		var s: RoomSpec = RoomSpec.new()
		s.key = r.get_str(rd, "key")
		s.kind = r.get_str(rd, "kind")
		s.floor_class = r.get_str(rd, "floor")
		if rd.has("hub"):
			s.hub = r.get_bool(rd, "hub")
		if rd.has("windows"):
			s.windows = r.get_bool(rd, "windows")
		if not s.hub:
			s.area = r.get_int(rd, "area")
			if s.area < 1:
				r.fail("%s/%s: area < 1" % [t.id, s.key])
		if not FLOOR_CLASSES.has(s.floor_class):
			r.fail("%s/%s: planta desconocida" % [t.id, s.key])
		if est.room_type(s.kind) == null:
			r.fail("%s/%s: tipo de estancia desconocido '%s'" % [t.id, s.key, s.kind])
		if s.key.is_empty() or t.room(s.key) != null:
			r.fail("%s: clave de estancia vacía o repetida '%s'" % [t.id, s.key])
		t.rooms.append(s)
	for fc: String in FLOOR_CLASSES:
		var hubs: int = 0
		var others: int = 0
		for s2: RoomSpec in t.rooms_on(fc):
			if s2.hub:
				hubs += 1
			else:
				others += 1
		if hubs > 1 or others < 1:
			r.fail("%s: la planta %s necesita >= 1 estancia y <= 1 hub" % [t.id, fc])
	for v: Variant in r.get_array(d, "adjacency"):
		var pair: Array = r.to_array(v, "adjacency")
		if pair.size() != 2:
			r.fail("%s: adyacencia debe ser un par" % t.id)
			continue
		var a: RoomSpec = t.room(r.to_str(pair[0], "adjacency"))
		var b: RoomSpec = t.room(r.to_str(pair[1], "adjacency"))
		if a == null or b == null or a == b or a.floor_class != b.floor_class:
			r.fail("%s: adyacencia no válida" % t.id)
			continue
		t.adjacency.append(PackedStringArray([a.key, b.key]))
	var special: PackedStringArray = PackedStringArray([t.entrance, t.stairs_up, t.stairs_down])
	if not t.back_door.is_empty():
		special.append(t.back_door)
	for key: String in special:
		var s3: RoomSpec = t.room(key)
		if s3 == null or s3.floor_class != FLOOR_GROUND or s3.hub:
			r.fail("%s: '%s' debe ser una estancia de la planta baja (no hub)" % [t.id, key])
	return t
