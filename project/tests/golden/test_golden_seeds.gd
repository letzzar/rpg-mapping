extends GutTest
## Seeds doradas (PROYECTO §5.4, ADR 021): código RPGM1 -> SHA-256 del
## contenido canónico del MapDocument (MapDocument.content_hash()).
##
## Fichero: res://tests/golden/golden_seeds.txt (formato en su cabecera).
## - Normal: cada línea con hash debe coincidir; una línea sin hash falla.
## - Grabación (variable de entorno RPGM_GOLDEN_RECORD=1): rellena SOLO las
##   líneas sin hash y reescribe el fichero; las que ya tienen hash no se
##   tocan nunca y se comprueban igual (CLAUDE.md §2).
## Cada código se genera dos veces: si los hashes difieren, el generador no es
## determinista dentro de la misma ejecución.
##
## La segunda parte del fichero prueba esta infraestructura con un generador
## falso registrado en un esquema de prueba (EST G98/G99).

const PATH: String = "res://tests/golden/golden_seeds.txt"
const RECORD_ENV: String = "RPGM_GOLDEN_RECORD"
const HEX: String = "0123456789abcdef"


class Entry:
	extends RefCounted
	var code: String = ""
	## "" = pendiente de grabar.
	var sha: String = ""
	var line: int = 0


class Parsed:
	extends RefCounted
	var entries: Array[Entry] = []
	var errors: PackedStringArray = PackedStringArray()


class Recorded:
	extends RefCounted
	var text: String = ""
	var recorded: int = 0
	var errors: PackedStringArray = PackedStringArray()


# --- Infraestructura --------------------------------------------------------

static func parse_text(text: String) -> Parsed:
	var out: Parsed = Parsed.new()
	var seen: Dictionary[String, int] = {}
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size():
		var raw: String = lines[i].strip_edges()
		if raw.is_empty() or raw.begins_with("#"):
			continue
		var tokens: PackedStringArray = raw.replace("\t", " ").split(" ", false)
		if tokens.size() > 2:
			out.errors.append("línea %d: se esperaba '<código> [<sha256>]'" % (i + 1))
			continue
		var e: Entry = Entry.new()
		e.code = tokens[0]
		e.sha = tokens[1] if tokens.size() == 2 else ""
		e.line = i + 1
		var sc: SeedCode = SeedCode.parse(e.code)
		if not sc.is_valid():
			out.errors.append("línea %d: código no válido (%s)" % [e.line, sc.error])
			continue
		if sc.encode() != e.code:
			out.errors.append("línea %d: código no canónico, debe ser %s" % [e.line, sc.encode()])
			continue
		if not e.sha.is_empty() and not is_sha256(e.sha):
			out.errors.append("línea %d: el hash debe tener 64 dígitos hex en minúsculas" % e.line)
			continue
		if seen.has(e.code):
			out.errors.append("línea %d: código repetido (ya en la línea %d)" % [e.line, seen[e.code]])
			continue
		seen[e.code] = e.line
		out.entries.append(e)
	return out


static func is_sha256(s: String) -> bool:
	if s.length() != 64:
		return false
	for c: String in s:
		if HEX.find(c) < 0:
			return false
	return true


## Hash de un código con `generate` (Callable(code: String) -> MapDocument);
## "" si no se pudo generar.
static func hash_of(code: String, generate: Callable) -> String:
	var doc: MapDocument = generate.call(code)
	return doc.content_hash() if doc != null else ""


## Rellena las líneas sin hash. Las demás quedan byte a byte iguales.
static func record_text(text: String, generate: Callable) -> Recorded:
	var rec: Recorded = Recorded.new()
	var parsed: Parsed = parse_text(text)
	rec.errors = parsed.errors
	var lines: PackedStringArray = text.split("\n")
	for e: Entry in parsed.entries:
		if not e.sha.is_empty():
			continue
		var h: String = hash_of(e.code, generate)
		if h.is_empty():
			rec.errors.append("línea %d: no se pudo generar %s" % [e.line, e.code])
			continue
		lines[e.line - 1] = "%s %s" % [e.code, h]
		rec.recorded += 1
	rec.text = "\n".join(lines)
	return rec


## Fallos de la comprobación (vacío = todo bien).
static func check_entries(parsed: Parsed, generate: Callable) -> PackedStringArray:
	var failures: PackedStringArray = parsed.errors.duplicate()
	for e: Entry in parsed.entries:
		var h: String = hash_of(e.code, generate)
		if h.is_empty():
			failures.append("línea %d: no se pudo generar %s" % [e.line, e.code])
			continue
		if hash_of(e.code, generate) != h:
			failures.append("línea %d: %s no es determinista (dos hashes distintos)" % [e.line, e.code])
			continue
		if e.sha.is_empty():
			failures.append("línea %d: %s sin hash; grabar con %s=1" % [e.line, e.code, RECORD_ENV])
		elif e.sha != h:
			failures.append("línea %d: %s cambió (%s -> %s); un cambio de salida exige subir GEN" % [e.line, e.code, e.sha, h])
	return failures


static func registry_generate(code: String) -> MapDocument:
	return GeneratorRegistry.generate(code).doc


# --- Seeds doradas del proyecto ---------------------------------------------

func test_golden_seeds_file() -> void:
	assert_true(FileAccess.file_exists(PATH), "falta " + PATH)
	var text: String = FileAccess.get_file_as_string(PATH)
	var gen: Callable = registry_generate
	if OS.get_environment(RECORD_ENV) == "1":
		var rec: Recorded = record_text(text, gen)
		assert_eq(rec.errors, PackedStringArray(), "errores al grabar")
		if rec.recorded > 0 and rec.errors.is_empty():
			var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
			f.store_string(rec.text)
			f.close()
			print("Seeds doradas grabadas: %d" % rec.recorded)
			text = rec.text
	var parsed: Parsed = parse_text(text)
	assert_eq(check_entries(parsed, gen), PackedStringArray())
	if parsed.entries.is_empty():
		pass_test("todavía no hay seeds doradas (F1, etapa 1)")


# --- Pruebas de la infraestructura (generador falso) -------------------------

const TEST_SCALE: String = "EST"
const TEST_GEN: int = 99
const TEST_GEN_NO_GENERATOR: int = 98


func before_each() -> void:
	for g: int in [TEST_GEN, TEST_GEN_NO_GENERATOR]:
		var fields: Array[ParamSchema.Field] = [ParamSchema.int_field("width", 2, 16, 6)]
		assert_eq(ParamSchemaRegistry.register(ParamSchema.new(TEST_SCALE, g, fields)), "")
	assert_eq(GeneratorRegistry.register(TEST_SCALE, TEST_GEN, fake_generator), "")


func after_each() -> void:
	ParamSchemaRegistry.reset()
	GeneratorRegistry.reset()


## Generador de prueba: suelo o muro al azar en un rectángulo width×3.
static func fake_generator(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var w: int = code.params["width"]
	var doc: MapDocument = MapDocument.create(GridGeometry.KIND_SQUARE, w, 3)
	var level: MapLevel = doc.level(0)
	for i: int in level.grid.cell_count():
		var t: int = Terrain.FLOOR if rng.chance_permille(600) else Terrain.WALL
		level.set_terrain(level.grid.cell_at(i), t)
	var room: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_ROOM)
	level.add_room(room)
	level.set_room_id(Vector2i.ZERO, room.id)
	return doc


func _code(seed_value: int, gen: int = TEST_GEN) -> String:
	return SeedCode.create("DND5", TEST_SCALE, gen, {"width": 8}, seed_value).encode()


func test_registry_generates_and_stamps_provenance() -> void:
	var code: String = _code(42)
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "")
	assert_not_null(res.doc)
	assert_eq(res.doc.seed_code, code)
	assert_eq(res.doc.scale, TEST_SCALE)
	assert_eq(res.doc.gen_version, TEST_GEN)
	assert_eq(res.doc.width(), 8)
	# Determinista y sensible a la semilla.
	assert_eq(hash_of(code, registry_generate), res.doc.content_hash())
	assert_ne(hash_of(_code(43), registry_generate), res.doc.content_hash())


func test_registry_errors() -> void:
	assert_eq(GeneratorRegistry.generate("RPGM1-DND5-MAZ").error, SeedCode.ERR_FORMAT)
	var no_gen: GeneratorRegistry.Result = GeneratorRegistry.generate(_code(1, TEST_GEN_NO_GENERATOR))
	assert_null(no_gen.doc)
	assert_string_contains(no_gen.error, "no hay generador")
	assert_ne(GeneratorRegistry.register(TEST_SCALE, TEST_GEN, fake_generator), "", "no se puede registrar dos veces")


func test_record_fills_only_missing_lines() -> void:
	var c1: String = _code(1)
	var c2: String = _code(2)
	var wrong: String = "0".repeat(64)
	var text: String = "# cabecera\n%s\n\n%s %s\n" % [c1, c2, wrong]
	var rec: Recorded = record_text(text, registry_generate)
	assert_eq(rec.errors, PackedStringArray())
	assert_eq(rec.recorded, 1)
	var h1: String = hash_of(c1, registry_generate)
	assert_eq(rec.text, "# cabecera\n%s %s\n\n%s %s\n" % [c1, h1, c2, wrong])
	# La línea con hash (aunque sea erróneo) no se ha tocado y falla.
	var failures: PackedStringArray = check_entries(parse_text(rec.text), registry_generate)
	assert_eq(failures.size(), 1)
	if failures.size() == 1:
		assert_string_contains(failures[0], "subir GEN")
	# Grabar otra vez no cambia nada.
	var again: Recorded = record_text(rec.text, registry_generate)
	assert_eq(again.recorded, 0)
	assert_eq(again.text, rec.text)


func test_pending_line_fails_without_record() -> void:
	var failures: PackedStringArray = check_entries(parse_text(_code(5) + "\n"), registry_generate)
	assert_eq(failures.size(), 1)
	if failures.size() == 1:
		assert_string_contains(failures[0], RECORD_ENV)


func test_parse_rejects_bad_lines() -> void:
	var c: String = _code(7)
	var h: String = hash_of(c, registry_generate)
	assert_true(is_sha256(h))
	assert_eq(parse_text("%s %s" % [c, h]).errors, PackedStringArray())
	assert_eq(parse_text(c.to_lower()).errors.size(), 1, "no canónico")
	assert_eq(parse_text("%s\n%s" % [c, c]).errors.size(), 1, "repetido")
	assert_eq(parse_text("%s %s" % [c, h.to_upper()]).errors.size(), 1, "hash en mayúsculas")
	assert_eq(parse_text("%s %s x" % [c, h]).errors.size(), 1, "demasiados campos")
	assert_eq(parse_text("RPGM1-DND5-MAZ-G1-0-1A-X").errors.size(), 1, "control erróneo")
	assert_eq(parse_text("# solo comentarios\n\n").entries.size(), 0)
