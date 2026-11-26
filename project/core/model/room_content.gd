class_name RoomContent
extends RefCounted
## Contenido de una estancia hecha a mano (E3, ADR 038): el código de su
## base + las ediciones que cambian el mapa (terreno, aristas, objetos,
## salas). Fichas, niebla y turnos son de la partida, no de la estancia, y
## no entran ni en su id ni en su código para compartir.

## Operaciones de delta que son contenido: las del código para compartir
## (su orden es parte del formato RPGS1, así que hay una sola lista).
const CONTENT_OPS: PackedStringArray = RoomCode.OPS


## Deltas de contenido del documento, en orden.
static func content_deltas(doc: MapDocument) -> Array[MapDelta]:
	var out: Array[MapDelta] = []
	for dl: MapDelta in doc.deltas:
		if CONTENT_OPS.has(dl.op):
			out.append(dl.copy())
	return out


## SHA-256 del contenido RESULTANTE (sistema, rejilla y niveles; sin el
## contador de ids ni la sesión): dos estancias iguales dan la misma huella
## aunque se hayan editado por caminos distintos. Es lo que identifica el id
## corto (RoomCode.short_id).
static func fingerprint(doc: MapDocument) -> PackedByteArray:
	var sc: SeedCode = SeedCode.parse(doc.seed_code)
	var levels: Array = []
	for i: int in doc.level_count():
		levels.append(doc.level(i).content_to_dict())
	var d: Dictionary = {
		"system": sc.system if sc.is_valid() else "",
		"grid": {"kind": doc.grid.kind, "width": doc.grid.width, "height": doc.grid.height},
		"levels": levels,
	}
	return CanonicalJson.stringify(d).sha256_buffer()


## Id corto de la estancia mostrada.
static func short_id(doc: MapDocument) -> String:
	return RoomCode.short_id(fingerprint(doc))


## Código para compartir: código de la base + deltas de contenido.
static func share_code(doc: MapDocument) -> String:
	return RoomCode.share_code(doc.seed_code, content_deltas(doc))


## Recrea una estancia: genera la base y reaplica los deltas de contenido
## (los que no lo son se ignoran). Error con claves i18n como MapFile.
static func rebuild(seed_code: String, deltas: Array[MapDelta]) -> MapFile.LoadResult:
	var res: MapFile.LoadResult = MapFile.LoadResult.new()
	var gen: GeneratorRegistry.Result = GeneratorRegistry.generate(seed_code)
	if gen.doc == null:
		res.error = gen.error
		return res
	var doc: MapDocument = gen.doc
	if doc.seed_code.is_empty():
		doc.seed_code = seed_code
	var only: Array[MapDelta] = []
	for dl: MapDelta in deltas:
		if CONTENT_OPS.has(dl.op):
			only.append(dl)
	var rep: DeltaReplay.Result = DeltaReplay.replay(doc, only)
	if not rep.error.is_empty():
		res.error = rep.error
		res.detail = rep.detail
		return res
	res.doc = doc
	return res


## La misma estancia solo con su contenido (sin fichas, niebla ni turnos):
## lo que se guarda en la biblioteca.
static func content_only(doc: MapDocument) -> MapFile.LoadResult:
	if doc.seed_code.is_empty():
		var res: MapFile.LoadResult = MapFile.LoadResult.new()
		res.error = "ROOM_ERR_NO_CODE"
		return res
	return rebuild(doc.seed_code, content_deltas(doc))
