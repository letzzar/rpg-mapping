class_name CharacterSheet
extends RefCounted
## Personaje (PROYECTO.md §10, ADR 034): lo que hace falta para moverlo y
## dibujarlo, no una hoja de personaje completa. Se guarda suelto como
## `*.rpgm-char.json` (data/schemas/character.schema.json) y dentro de la
## ficha que lo representa (MapToken.sheet), para que el mapa y la partida en
## red sean autosuficientes.
##
## Distancias en pies enteros, como los perfiles de sistema (regla de oro 4);
## se muestran con Units.format_distance().

const FORMAT: String = "rpgm-char"
const SCHEMA_VERSION: int = 1
const EXTENSION: String = ".rpgm-char.json"
## Lado del retrato guardado (se reduce al importarlo): basta para la ficha
## 2D y mantiene pequeños el fichero y los mensajes de red.
const PORTRAIT_PX: int = 128

var name: String = ""
## Id del perfil de sistema con el que se hizo ("" = cualquiera).
var system: String = ""
## Id de tamaño del perfil ("medium"…).
var size_id: String = "medium"
## Modo de movimiento ("walk", "fly"…) → pies por turno.
var speeds: Dictionary[String, int] = {}
## Sentido ("darkvision"…) → alcance en pies.
var senses: Dictionary[String, int] = {}
var has_initiative: bool = false
## Modificador de iniciativa (solo para ordenar turnos).
var initiative: int = 0
## PNG del retrato (cuadrado, PORTRAIT_PX); vacío = silueta.
var portrait_png: PackedByteArray = PackedByteArray()
var look: CharacterLook = CharacterLook.new()


## Velocidad del modo `mode`; si no la tiene, la caminando; si tampoco, la
## del perfil (0 si no hay perfil).
func speed_ft(mode: String, profile: SystemProfile) -> int:
	if speeds.has(mode):
		return speeds[mode]
	if speeds.has("walk"):
		return speeds["walk"]
	return profile.default_speed_ft if profile != null else 0


func copy() -> CharacterSheet:
	var c: CharacterSheet = CharacterSheet.new()
	c.name = name
	c.system = system
	c.size_id = size_id
	c.speeds = speeds.duplicate()
	c.senses = senses.duplicate()
	c.has_initiative = has_initiative
	c.initiative = initiative
	c.portrait_png = portrait_png.duplicate()
	c.look = look.copy()
	return c


## Igualdad de contenido (para no apilar comandos que no cambian nada).
func equals(o: CharacterSheet) -> bool:
	return o != null and CanonicalJson.stringify(to_dict()) == CanonicalJson.stringify(o.to_dict())


func to_dict() -> Dictionary:
	var d: Dictionary = {
		"format": FORMAT,
		"schema_version": SCHEMA_VERSION,
		"name": name,
		"system": system,
		"size_id": size_id,
		"speeds": _int_dict(speeds),
		"senses": _int_dict(senses),
		"look": look.to_dict(),
	}
	if has_initiative:
		d["initiative"] = initiative
	if not portrait_png.is_empty():
		d["portrait_png"] = Marshalls.raw_to_base64(portrait_png)
	return d


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", true)


## Solo lo que un jugador puede saber de una criatura ajena: nombre, tamaño,
## retrato y aspecto (sin velocidades, sentidos ni iniciativa).
func public_copy() -> CharacterSheet:
	var c: CharacterSheet = copy()
	c.speeds.clear()
	c.senses.clear()
	c.has_initiative = false
	c.initiative = 0
	return c


static func from_dict(r: JsonReader, d: Dictionary) -> CharacterSheet:
	var c: CharacterSheet = CharacterSheet.new()
	if r.get_str(d, "format") != FORMAT:
		r.fail("no es un personaje (%s)" % FORMAT)
		return c
	if r.get_int(d, "schema_version") != SCHEMA_VERSION:
		r.fail("schema_version de personaje distinto de %d" % SCHEMA_VERSION)
		return c
	c.name = r.get_str(d, "name")
	c.system = r.get_str(d, "system")
	c.size_id = r.get_str(d, "size_id")
	c.speeds = _read_int_dict(r, r.get_dict(d, "speeds"), "speeds")
	c.senses = _read_int_dict(r, r.get_dict(d, "senses"), "senses")
	if d.has("initiative"):
		c.has_initiative = true
		c.initiative = r.get_int(d, "initiative")
	if d.has("portrait_png"):
		c.portrait_png = Marshalls.base64_to_raw(r.get_str(d, "portrait_png"))
	c.look = CharacterLook.from_dict(r, r.get_dict(d, "look"))
	return c


## Resultado de from_json().
class LoadResult:
	extends RefCounted
	var sheet: CharacterSheet = null
	var error: String = ""


static func from_json(text: String) -> LoadResult:
	var res: LoadResult = LoadResult.new()
	var parsed: Variant = parse_json_quiet(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		res.error = "no es un objeto JSON"
		return res
	var d: Dictionary = parsed
	var r: JsonReader = JsonReader.new()
	var c: CharacterSheet = from_dict(r, d)
	if not r.ok():
		res.error = r.error
		return res
	res.sheet = c
	return res


## JSON.parse_string sin el error del motor en la consola cuando el texto no
## es JSON (es un fichero del usuario, no un fallo del programa). null si no
## se puede leer.
static func parse_json_quiet(text: String) -> Variant:
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


## Reduce y recorta al centro una imagen para usarla de retrato. Devuelve el
## PNG (vacío si la imagen no vale).
static func portrait_from_image(img: Image) -> PackedByteArray:
	if img == null or img.is_empty():
		return PackedByteArray()
	var im: Image = img.duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var side: int = mini(im.get_width(), im.get_height())
	im = im.get_region(Rect2i((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side))
	im.resize(PORTRAIT_PX, PORTRAIT_PX, Image.INTERPOLATE_LANCZOS)
	return im.save_png_to_buffer()


## Imagen del retrato (null si no tiene o no se puede leer).
func portrait_image() -> Image:
	if portrait_png.is_empty():
		return null
	var im: Image = Image.new()
	if im.load_png_from_buffer(portrait_png) != OK:
		return null
	return im


static func _int_dict(src: Dictionary[String, int]) -> Dictionary:
	var out: Dictionary = {}
	for k: String in src:
		out[k] = src[k]
	return out


static func _read_int_dict(r: JsonReader, src: Dictionary, what: String) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var keys: Array = src.keys()
	keys.sort()
	for k: Variant in keys:
		var ks: String = r.to_str(k, what)
		var v: int = r.to_int(src[k], what + "." + ks)
		if v < 0:
			r.fail("'%s.%s' no puede ser negativo" % [what, ks])
		out[ks] = v
	return out
