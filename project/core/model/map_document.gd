class_name MapDocument
extends RefCounted
## Modelo canónico de un mapa táctico (ADR 019): lo generan MAZ y EST (y, más
## adelante, EDI) y lo leen las tres vistas. PROYECTO §4.
##
## Contenido (lo que produce un generador; entra en content_hash()):
## - Procedencia: seed_code (RPGM1), scale y gen_version.
## - Rejilla: grid (GridGeometry: tipo, ancho, alto).
## - levels: uno o más MapLevel (terreno, aristas, salas, objetos, escaleras,
##   trampas).
## - El contador de ids (allocate_id): forma parte del estado reproducible.
## Sesión (NO la crea un generador; entra solo en full_hash()):
## - tokens (MapToken), niebla de guerra (por nivel) y deltas (MapDelta).
##
## Reglas de uso:
## - Las vistas solo LEEN. Los cambios van por MapCommand + CommandStack; el
##   comando, tras aplicar o deshacer, llama a notify_changed(nivel, capa).
## - Los generadores escriben directamente (no hay vistas conectadas).
## - Serialización canónica: to_dict() -> CanonicalJson (claves ordenadas,
##   solo enteros, listas en orden fijo). from_dict() la lee de vuelta.

## Se emite desde notify_changed(). `layer` es una de las LAYER_*;
## `level_index` es -1 si el cambio no es de un nivel concreto (p. ej. tokens).
signal changed(level_index: int, layer: String)

const SCHEMA_VERSION: int = 1

const LAYER_TERRAIN: String = "terrain"
const LAYER_EDGES: String = "edges"
const LAYER_ROOMS: String = "rooms"
const LAYER_OBJECTS: String = "objects"
const LAYER_FEATURES: String = "features"
const LAYER_TOKENS: String = "tokens"
const LAYER_FOG: String = "fog"
const LAYER_TURNS: String = "turns"
const LAYER_ALL: String = "all"

## Máximo de niveles por documento.
const MAX_LEVELS: int = 64

## Código RPGM1 del que sale ("" si el mapa se creó a mano).
var seed_code: String = ""
## Escala (SeedCode.SCALES) y versión del generador; "" y 0 si es manual.
var scale: String = ""
var gen_version: int = 0
var grid: GridGeometry
var levels: Array[MapLevel] = []
## Fichas (sesión), ordenadas por id.
var tokens: Array[MapToken] = []
## Ediciones manuales aplicadas sobre lo generado, en orden (sesión).
var deltas: Array[MapDelta] = []
## Turnos e iniciativa (sesión, ADR 035).
var turns: TurnTracker = TurnTracker.new()
## Hijos sustituidos por una estancia propia (E4, ADR 040): MapChild.id →
## {"seed_code": código base, "deltas": [MapDelta.to_dict()…]} (contenido de
## la estancia). Al entrar en ese hijo se abre la estancia en vez del mapa
## generado. Sesión; cambia con SetChildOverrideCommand.
var child_overrides: Dictionary[int, Dictionary] = {}
## Incrementa en cada notify_changed() (las vistas pueden compararlo).
var revision: int = 0
## Imagen de fondo del nivel 0 de un mapa importado (Universal VTT, ADR 030),
## del tamaño del mapa. No es contenido generado ni sesión: no se serializa
## ni entra en ningún hash. null en los mapas generados.
var background_image: Image = null

var _next_id: int = 1


## Documento vacío (todo Terrain.VOID) de rejilla `p_kind` (GridGeometry.KINDS),
## p_width×p_height casillas y `p_levels` niveles; null si algo no es válido.
static func create(p_kind: String, p_width: int, p_height: int, p_levels: int = 1) -> MapDocument:
	var g: GridGeometry = GridFactory.create(p_kind, p_width, p_height)
	if g == null or p_levels < 1 or p_levels > MAX_LEVELS:
		return null
	var doc: MapDocument = MapDocument.new()
	doc.grid = g
	for i: int in p_levels:
		doc.levels.append(MapLevel.new(g))
	return doc


func grid_kind() -> String:
	return grid.kind


func width() -> int:
	return grid.width


func height() -> int:
	return grid.height


func level_count() -> int:
	return levels.size()


## Nivel `index`; null si no existe.
func level(index: int) -> MapLevel:
	if index < 0 or index >= levels.size():
		return null
	return levels[index]


## Añade un nivel vacío al final y lo devuelve (null si se llegó a MAX_LEVELS).
func add_level() -> MapLevel:
	if levels.size() >= MAX_LEVELS:
		return null
	var l: MapLevel = MapLevel.new(grid)
	levels.append(l)
	return l


## Asegura que allocate_id() no devuelva ya `id` ni ninguno menor (al
## reaplicar deltas que traen sus ids, DeltaReplay).
func reserve_ids_through(id: int) -> void:
	_next_id = maxi(_next_id, id + 1)


## Contador de ids (el siguiente que dará allocate_id()).
func next_id() -> int:
	return _next_id


## Fija el contador al guardado (MapFile): al reaplicar deltas solo se
## conocen los ids que siguen en uso, no los gastados en fichas borradas.
## Nunca lo baja por debajo de lo ya reservado.
func restore_next_id(value: int) -> void:
	_next_id = maxi(_next_id, value)


## Id nuevo, único en todo el documento (salas, objetos, escaleras, trampas y
## tokens comparten contador). Determinista: depende solo del orden de las
## llamadas.
func allocate_id() -> int:
	var id: int = _next_id
	_next_id += 1
	return id


## Siguiente id que daría allocate_id() (para guardar/deshacer).
func peek_next_id() -> int:
	return _next_id


## Solo para deshacer la creación de algo o al cargar.
func set_next_id(value: int) -> void:
	_next_id = maxi(1, value)


## Avisa a las vistas de un cambio (lo llaman los comandos).
func notify_changed(level_index: int, layer: String) -> void:
	revision += 1
	changed.emit(level_index, layer)


# --- Tokens -----------------------------------------------------------------

func token(id: int) -> MapToken:
	for t: MapToken in tokens:
		if t.id == id:
			return t
	return null


## Añade manteniendo el orden por id. false si el id ya existe.
func add_token(t: MapToken) -> bool:
	if token(t.id) != null:
		return false
	var k: int = 0
	while k < tokens.size() and tokens[k].id < t.id:
		k += 1
	tokens.insert(k, t)
	return true


func remove_token(id: int) -> MapToken:
	for k: int in tokens.size():
		if tokens[k].id == id:
			var t: MapToken = tokens[k]
			tokens.remove_at(k)
			return t
	return null


## Tokens cuya huella incluye la casilla (`profile` da el tamaño).
func tokens_at(level_index: int, cell: Vector2i, profile: SystemProfile) -> Array[MapToken]:
	var out: Array[MapToken] = []
	for t: MapToken in tokens:
		if t.level == level_index and token_cells(t, profile).has(cell):
			out.append(t)
	return out


## Casillas que ocupa el token según su tamaño en el perfil (sin recortar).
func token_cells(t: MapToken, profile: SystemProfile) -> Array[Vector2i]:
	return grid.footprint(t.cell, profile.size_cells(t.size_id), profile.size_hex_cells_of(t.size_id))


# --- Serialización ----------------------------------------------------------

## Diccionario canónico. Con `include_session` = false, solo el contenido
## generado (lo que cubre content_hash() y las seeds doradas).
func to_dict(include_session: bool = true) -> Dictionary:
	var level_list: Array = []
	for l: MapLevel in levels:
		level_list.append(l.content_to_dict())
	var d: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"source": {"seed_code": seed_code, "scale": scale, "gen": gen_version},
		"grid": {"kind": grid.kind, "width": grid.width, "height": grid.height},
		"next_id": _next_id,
		"levels": level_list,
	}
	if include_session:
		var token_list: Array = []
		for t: MapToken in tokens:
			token_list.append(t.to_dict())
		var fog_list: Array = []
		for l: MapLevel in levels:
			fog_list.append(l.fog_to_dict())
		var delta_list: Array = []
		for dl: MapDelta in deltas:
			delta_list.append(dl.to_dict())
		var session: Dictionary = {"tokens": token_list, "fog": fog_list, "deltas": delta_list}
		# Solo si hay algo: los mapas sin turnos guardan lo mismo que antes.
		if not turns.equals(TurnTracker.new()):
			session["turns"] = turns.to_dict()
		if not child_overrides.is_empty():
			var ov: Dictionary = {}
			for k: int in child_overrides:
				ov[str(k)] = child_overrides[k].duplicate(true)
			session["child_overrides"] = ov
		d["session"] = session
	return d


func to_canonical_json(include_session: bool = true) -> String:
	return CanonicalJson.stringify(to_dict(include_session))


## SHA-256 (hex minúsculas) del contenido generado, sin sesión. Es el valor
## de las seeds doradas (tests/golden/golden_seeds.txt).
func content_hash() -> String:
	return to_canonical_json(false).sha256_text()


## SHA-256 de todo, sesión incluida (sincronización en red, cachés).
func full_hash() -> String:
	return to_canonical_json(true).sha256_text()


## Resultado de from_dict()/from_json().
class LoadResult:
	extends RefCounted
	var doc: MapDocument = null
	## Mensaje técnico (log) si falló; "" si se cargó.
	var error: String = ""


static func from_json(text: String) -> LoadResult:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var res: LoadResult = LoadResult.new()
		res.error = "no es un objeto JSON"
		return res
	var d: Dictionary = parsed
	return from_dict(d)


## Lee un diccionario de to_dict() (con o sin "session").
static func from_dict(d: Dictionary) -> LoadResult:
	var res: LoadResult = LoadResult.new()
	var r: JsonReader = JsonReader.new()
	if r.get_int(d, "schema_version") != SCHEMA_VERSION:
		res.error = "schema_version distinto de %d" % SCHEMA_VERSION
		return res
	var g: Dictionary = r.get_dict(d, "grid")
	var level_dicts: Array[Dictionary] = r.get_dicts(d, "levels")
	var doc: MapDocument = create(r.get_str(g, "kind"), r.get_int(g, "width"), r.get_int(g, "height"), maxi(1, level_dicts.size()))
	if not r.ok() or doc == null or level_dicts.is_empty():
		res.error = r.error if not r.ok() else "rejilla o niveles no válidos"
		return res
	var src: Dictionary = r.get_dict(d, "source")
	doc.seed_code = r.get_str(src, "seed_code")
	doc.scale = r.get_str(src, "scale")
	doc.gen_version = r.get_int(src, "gen")
	doc._next_id = r.get_int(d, "next_id")
	var fog_dicts: Array[Dictionary] = []
	if d.has("session"):
		var s: Dictionary = r.get_dict(d, "session")
		for td: Dictionary in r.get_dicts(s, "tokens"):
			if not doc.add_token(MapToken.from_dict(r, td)):
				r.fail("id de token repetido")
		fog_dicts = r.get_dicts(s, "fog")
		if fog_dicts.size() != level_dicts.size():
			r.fail("session.fog debe tener una entrada por nivel")
		for dd: Dictionary in r.get_dicts(s, "deltas"):
			doc.deltas.append(MapDelta.from_dict(r, dd))
		if s.has("turns"):
			doc.turns = TurnTracker.from_dict(r, r.get_dict(s, "turns"))
		if s.has("child_overrides"):
			var ov: Dictionary = r.get_dict(s, "child_overrides")
			for k: Variant in ov:
				var ks: String = r.to_str(k, "child_overrides")
				if not ks.is_valid_int():
					r.fail("child_overrides: clave no numérica")
					continue
				var entry: Dictionary = r.to_dict(ov[k], "child_overrides")
				var normalized: Variant = MapDelta.normalize(r, entry)
				var nd: Dictionary = r.to_dict(normalized, "child_overrides")
				doc.child_overrides[ks.to_int()] = nd
	for i: int in level_dicts.size():
		var fog: Dictionary = fog_dicts[i] if i < fog_dicts.size() else {}
		doc.levels[i].load_dicts(r, level_dicts[i], fog)
	if not r.ok():
		res.error = r.error
		return res
	res.doc = doc
	return res
