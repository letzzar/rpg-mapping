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
	## Recorrido abierto (from_json): la raíz es `doc`; con "route", los
	## mapas visitados y en cuál se estaba (ADR 040).
	var nav: MapNavigator = null
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
	var res: LoadResult = from_dict(d)
	if res.doc == null:
		return res
	res.nav = MapNavigator.new()
	var root: MapNavigator.Frame = res.nav.open_root(res.doc)
	# Sin recorrido: se abre en el nivel de la entrada, como al generar.
	root.level_index = -1
	if d.has("route"):
		var r: JsonReader = JsonReader.new()
		var route: Dictionary = r.get_dict(d, "route")
		root.level_index = r.get_int(route, "level")
		var err: LoadResult = _load_children(r, root, r.get_dicts(route, "children"))
		if err != null:
			return err
		var cur: MapNavigator.Frame = root
		for v: Variant in r.get_array(route, "path"):
			var cid: int = r.to_int(v, "path")
			if not cur.visited.has(cid):
				r.fail("path: hijo %d no visitado" % cid)
				break
			cur = cur.visited[cid]
			res.nav.frames.append(cur)
		if not r.ok():
			var bad2: LoadResult = LoadResult.new()
			bad2.error = "MAP_ERR_FILE"
			bad2.detail = r.error
			return bad2
	return res


# --- Recorrido (ADR 040) ------------------------------------------------------

## El recorrido entero: la raíz como to_dict() más "route" con los mapas
## visitados (cada uno con sus deltas y su sustitución), en cuál se está y
## qué nivel se miraba. Así las estancias y los edificios editados viajan en
## el mismo fichero.
static func route_to_dict(nav: MapNavigator) -> Dictionary:
	var root: MapNavigator.Frame = nav.frames[0]
	var d: Dictionary = to_dict(root.doc)
	var path: Array = []
	for i: int in range(1, nav.frames.size()):
		path.append(nav.frames[i].child.id)
	d["route"] = {"level": root.level_index, "children": _children_dicts(root), "path": path}
	return d


static func route_to_json(nav: MapNavigator) -> String:
	return CanonicalJson.stringify(route_to_dict(nav))


static func _children_dicts(f: MapNavigator.Frame) -> Array:
	var out: Array = []
	var ids: Array = f.visited.keys()
	ids.sort()
	for cid: int in ids:
		var sub: MapNavigator.Frame = f.visited[cid]
		out.append({
			"id": cid,
			"child": sub.child.to_dict(),
			"keep_positions": sub.keep_positions,
			"parent_level": sub.parent_level,
			"level": sub.level_index,
			"override_key": sub.override_key,
			"map": to_dict(sub.doc),
			"children": _children_dicts(sub),
		})
	return out


## Reconstruye los hijos visitados de `parent`; null si todo fue bien, o el
## error del primero que falló.
static func _load_children(r: JsonReader, parent: MapNavigator.Frame, list: Array[Dictionary]) -> LoadResult:
	for cd: Dictionary in list:
		var lr: LoadResult = from_dict(r.get_dict(cd, "map"))
		if lr.doc == null:
			return lr
		var f: MapNavigator.Frame = MapNavigator.Frame.new()
		f.doc = lr.doc
		f.stack = CommandStack.new(lr.doc)
		f.child = MapChild.from_dict(r, r.get_dict(cd, "child"))
		f.keep_positions = r.get_bool(cd, "keep_positions")
		f.parent_level = r.get_int(cd, "parent_level")
		f.level_index = r.get_int(cd, "level")
		f.override_key = r.get_str(cd, "override_key")
		var cid: int = r.get_int(cd, "id")
		if not r.ok():
			var bad: LoadResult = LoadResult.new()
			bad.error = "MAP_ERR_FILE"
			bad.detail = r.error
			return bad
		parent.visited[cid] = f
		var err: LoadResult = _load_children(r, f, r.get_dicts(cd, "children"))
		if err != null:
			return err
	return null


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
