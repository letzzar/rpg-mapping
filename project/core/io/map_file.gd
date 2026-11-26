class_name MapFile
extends RefCounted
## Mapa guardado (`*.rpgm-map.json`, ADR 004 y 036): código de semilla +
## ediciones. Al abrirlo se regenera el mapa desde el código y se reaplican
## los deltas (DeltaReplay); fichas, niebla y turnos salen de los propios
## deltas. Esquema: data/schemas/map_file.schema.json.
##
## Un mapa sin código (importado de Universal VTT) no se puede regenerar: se
## guarda el documento entero (`document`, MapDocument.to_dict); la imagen de
## fondo no se guarda.
##
## Comprobación: `content_hash` es el del mapa generado (sin sesión). Si al
## abrir no coincide, el generador de ese código ha cambiado sin subir su
## GEN (es un error del programa, no del fichero) y no se abre, para no
## aplicar ediciones sobre otro mapa.

const FORMAT: String = "rpgm-map"
const SCHEMA_VERSION: int = 1
const EXTENSION: String = ".rpgm-map.json"


class LoadResult:
	extends RefCounted
	var doc: MapDocument = null
	## Clave i18n del error ("" si se abrió).
	var error: String = ""
	## Detalle técnico (para el registro).
	var detail: String = ""


static func to_dict(doc: MapDocument) -> Dictionary:
	var deltas: Array = []
	for dl: MapDelta in doc.deltas:
		deltas.append(dl.to_dict())
	var d: Dictionary = {
		"format": FORMAT,
		"schema_version": SCHEMA_VERSION,
		"seed_code": doc.seed_code,
		"next_id": doc.next_id(),
		"deltas": deltas,
	}
	if doc.seed_code.is_empty():
		d["document"] = doc.to_dict(true)
	else:
		d["content_hash"] = base_hash(doc)
	return d


static func to_json(doc: MapDocument) -> String:
	return CanonicalJson.stringify(to_dict(doc))


## Hash del mapa tal y como sale del generador: el de ahora sin las fichas
## (que cambian el contador de ids) no sirve, así que se regenera.
static func base_hash(doc: MapDocument) -> String:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(doc.seed_code)
	return res.doc.content_hash() if res.doc != null else ""


static func from_json(text: String) -> LoadResult:
	var parsed: Variant = CharacterSheet.parse_json_quiet(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var bad: LoadResult = LoadResult.new()
		bad.error = "MAP_ERR_FILE"
		return bad
	var d: Dictionary = parsed
	return from_dict(d)


static func from_dict(d: Dictionary) -> LoadResult:
	var res: LoadResult = LoadResult.new()
	var r: JsonReader = JsonReader.new()
	if r.get_str(d, "format") != FORMAT:
		res.error = "MAP_ERR_FILE"
		return res
	if r.get_int(d, "schema_version") != SCHEMA_VERSION:
		res.error = "MAP_ERR_VERSION"
		return res
	var code: String = r.get_str(d, "seed_code")
	var next_id: int = r.get_int(d, "next_id")
	var deltas: Array[MapDelta] = []
	for dd: Dictionary in r.get_dicts(d, "deltas"):
		deltas.append(MapDelta.from_dict(r, dd))
	if not r.ok():
		res.error = "MAP_ERR_FILE"
		res.detail = r.error
		return res
	if code.is_empty():
		# Sin código: el documento entero, tal cual.
		var lr: MapDocument.LoadResult = MapDocument.from_dict(r.get_dict(d, "document"))
		if lr.doc == null:
			res.error = "MAP_ERR_FILE"
			res.detail = lr.error if not lr.error.is_empty() else r.error
			return res
		res.doc = lr.doc
		return res
	var gen: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	if gen.doc == null:
		res.error = gen.error
		return res
	var doc: MapDocument = gen.doc
	if doc.seed_code.is_empty():
		doc.seed_code = code
	if d.has("content_hash") and r.get_str(d, "content_hash") != doc.content_hash():
		res.error = "MAP_ERR_GENERATOR"
		res.detail = "el generador de %s ya no da el mismo mapa" % code
		return res
	var rep: DeltaReplay.Result = DeltaReplay.replay(doc, deltas)
	if not rep.error.is_empty():
		res.error = rep.error
		res.detail = rep.detail
		return res
	doc.restore_next_id(next_id)
	res.doc = doc
	return res
