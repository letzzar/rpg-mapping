extends GutTest
## Tests de core/seed: Base32 Crockford, esquemas posicionales de PARAMS y
## código RPGM1 (ida y vuelta, longitud, errores, alias, control).

const SEED: int = -8629252141511181193
const HALF31: int = 1 << 30


func before_each() -> void:
	ParamSchemaRegistry.reset()
	var schemas: Array[ParamSchema] = [_typical4(), _ald(), _wide(), _single()]
	for s: ParamSchema in schemas:
		assert_eq(ParamSchemaRegistry.register(s), "", "%s G%d" % [s.scale, s.gen])


func after_all() -> void:
	ParamSchemaRegistry.reset()


# --- Esquemas de prueba -------------------------------------------------------

## 4 parámetros típicos (forma de MAZ). EST G9.
static func _typical4() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.int_field("rooms", 1, 64, 12),
		ParamSchema.enum_field("layout", PackedStringArray(["built", "cave", "mixed"]), "built", 8),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.int_field("corridor_pct", 0, 100, 30),
	]
	return ParamSchema.new("EST", 9, fields)


## Asentamiento con estilo cultural (ADR 015). ALD G3.
static func _ald() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("size", PackedStringArray(["hamlet", "village", "town", "city"]), "village"),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarven", "elven"]), "human", 8),
		ParamSchema.bool_field("walls", false),
		ParamSchema.int_field("prosperity", -2, 2, 0),
	]
	return ParamSchema.new("ALD", 3, fields)


## Más de 64 bits (6 × 31 + 1 + log2(3)) y valores negativos. EDI G7.
static func _wide() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = []
	for k: String in ["a", "b", "c", "d", "e", "f"]:
		fields.append(ParamSchema.int_field(k, -HALF31, HALF31 - 1, 0))
	fields.append(ParamSchema.bool_field("flag", false))
	fields.append(ParamSchema.enum_field("kind", PackedStringArray(["x", "y", "z"]), "x"))
	return ParamSchema.new("EDI", 7, fields)


## Un entero simple (para alias). REG G4.
static func _single() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [ParamSchema.int_field("n", 0, 1023, 0)]
	return ParamSchema.new("REG", 4, fields)


static func _signed(body: String) -> String:
	return "%s-%s" % [body, SeedCode.check_char(body)]


static func _random_params(s: ParamSchema, rng: Rng) -> Dictionary:
	var out: Dictionary = {}
	for f: ParamSchema.Field in s.fields:
		if rng.bounded(4) == 0:
			continue  # omitido: toma el valor por defecto
		if f.kind == ParamSchema.KIND_INT:
			out[f.key] = rng.range_int(f.min_value, f.max_value)
		elif f.kind == ParamSchema.KIND_BOOL:
			out[f.key] = rng.bounded(2) == 1
		else:
			out[f.key] = f.ids[rng.bounded(f.ids.size())]
	return out


# --- Base32 Crockford ---------------------------------------------------------

func test_base32_u64_roundtrip() -> void:
	var rng: Rng = Rng.new(1)
	var values: Array[int] = [0, 1, -1, 1 << 63, 0x7FFFFFFFFFFFFFFF, 123456789]
	for i: int in range(200):
		values.append((rng.next_u32() << 32) | rng.next_u32())
	for v: int in values:
		var text: String = Base32Crockford.encode_u64(v)
		assert_eq(text.length(), 13)
		var back: Base32Crockford.U64Result = Base32Crockford.decode_u64(text)
		assert_true(back.ok)
		assert_eq(back.value, v)


func test_base32_u64_known_values() -> void:
	assert_eq(Base32Crockford.encode_u64(0), "0000000000000")
	assert_eq(Base32Crockford.encode_u64(-1), "FZZZZZZZZZZZZ")
	assert_eq(Base32Crockford.encode_u64(32), "0000000000010")


func test_base32_u64_rejects_overflow_and_bad_chars() -> void:
	assert_false(Base32Crockford.decode_u64("GZZZZZZZZZZZZ").ok)
	assert_false(Base32Crockford.decode_u64("000000000000U").ok)
	assert_false(Base32Crockford.decode_u64("000").ok)


func test_base32_aliases() -> void:
	var a: Base32Crockford.U64Result = Base32Crockford.decode_u64("OOOOOOOOOOOil")
	assert_true(a.ok)
	assert_eq(a.value, 33)


func test_base32_bytes_roundtrip() -> void:
	var rng: Rng = Rng.new(2)
	for n: int in range(0, 40):
		var data: PackedByteArray = PackedByteArray()
		for i: int in n:
			data.append(rng.bounded(256))
		var back: Base32Crockford.BytesResult = Base32Crockford.decode_bytes(Base32Crockford.encode_bytes(data))
		assert_true(back.ok)
		assert_eq(back.bytes, data)


func test_base32_bytes_rejects_nonzero_padding() -> void:
	# "f" = 0x66 -> "CR"; "CS" tiene bits de relleno distintos de cero.
	assert_eq(Base32Crockford.encode_bytes("f".to_utf8_buffer()), "CR")
	assert_false(Base32Crockford.decode_bytes("CS").ok)


# --- PARAMS posicional ----------------------------------------------------------

## Longitud típica con 4 parámetros, todos distintos de su defecto. Valor
## congelado: fija el orden (primer campo = dígito menos significativo).
## N = 8 + 64·(1 + 8·(1 + 4·15)) = 31304 = "YJ8".
func test_typical_length_4_params() -> void:
	var params: Dictionary = {"rooms": 20, "layout": "cave", "grid": "hex_flat", "corridor_pct": 45}
	var sc: SeedCode = SeedCode.create("DND5", "EST", 9, params, SEED)
	assert_true(sc.is_valid(), sc.error)
	var text: String = sc.encode()
	gut.p("Código típico con 4 parámetros (%d car.): %s" % [text.length(), text])
	assert_eq(text.split("-")[4], "YJ8")
	assert_eq(text.length(), 37)


func test_all_defaults_is_zero() -> void:
	var s: ParamSchema = _typical4()
	assert_eq(s.resolve({}).text, "0")
	assert_eq(s.resolve(s.default_values()).text, "0")
	var a: String = SeedCode.create("DND5", "EST", 9, {}, 7).encode()
	var b: String = SeedCode.create("DND5", "EST", 9, s.default_values(), 7).encode()
	assert_eq(a, b)
	assert_eq(a.split("-")[4], "0")


func test_param_order_irrelevant() -> void:
	var a: String = SeedCode.create("GEN", "EST", 9, {"corridor_pct": 45, "rooms": 20}, 7).encode()
	var b: String = SeedCode.create("GEN", "EST", 9, {"rooms": 20, "corridor_pct": 45}, 7).encode()
	assert_ne(a, "")
	assert_eq(a, b)


func test_trailing_defaults_are_omitted() -> void:
	var s: ParamSchema = _typical4()
	assert_eq(s.resolve({"rooms": 13}).text, "1")
	assert_eq(s.resolve({"rooms": 11}).text, "1Z")  # dígito 63 = (11 - 12) mod 64
	# Solo el último campo cambiado: ocupa todo el ancho de los anteriores.
	assert_eq(s.resolve({"corridor_pct": 31}).text, "200")  # 1·64·8·4 = 2048 = 2·32²


func test_ald_example_and_style() -> void:
	var text: String = SeedCode.create("PF2E", "ALD", 3, {}, 42).encode()
	assert_true(text.begins_with("RPGM1-PF2E-ALD-G3-0-000000000001A-"), text)
	var back: SeedCode = SeedCode.parse(text)
	assert_true(back.is_valid(), back.error)
	assert_eq(back.params, {"size": "village", "style": "human", "walls": false, "prosperity": 0})
	var dwarven: SeedCode = SeedCode.create("PF2E", "ALD", 3, {"style": "dwarven"}, 42)
	assert_eq(dwarven.encode().split("-")[4], "4")  # 0 + 4·1


func test_wide_schema_beyond_64_bits() -> void:
	var s: ParamSchema = _wide()
	# Solo el 6.º entero = 1  =>  N = (2^31)^5 = 2^155 = "1" + 31 ceros.
	assert_eq(s.resolve({"f": 1}).text, "1" + "0".repeat(31))
	# a = -1  =>  dígito 2^31 - 1  =>  "1ZZZZZZ".
	assert_eq(s.resolve({"a": -1}).text, "1ZZZZZZ")
	var all_max: Dictionary = {"a": -1, "b": -1, "c": -1, "d": -1, "e": -1, "f": -1, "flag": true, "kind": "z"}
	var r: ParamSchema.Resolved = s.resolve(all_max)
	assert_eq(r.error, "")
	var back: ParamSchema.Resolved = s.decode(r.text)
	assert_eq(back.error, "")
	assert_eq(back.values, all_max)


func test_roundtrip_random() -> void:
	var rng: Rng = Rng.new(20261124)
	var cases: Array[Array] = [[_typical4(), "EST", 9], [_ald(), "ALD", 3], [_wide(), "EDI", 7], [_single(), "REG", 4]]
	for c: Array in cases:
		var s: ParamSchema = c[0]
		var esc: String = c[1]
		var gen: int = c[2]
		for i: int in range(150):
			var params: Dictionary = _random_params(s, rng)
			var expected: Dictionary = s.default_values()
			expected.merge(params, true)
			var seed_value: int = (rng.next_u32() << 32) | rng.next_u32()
			var sc: SeedCode = SeedCode.create("DND5", esc, gen, params, seed_value)
			assert_true(sc.is_valid(), sc.error)
			var text: String = sc.encode()
			var back: SeedCode = SeedCode.parse(text)
			assert_true(back.is_valid(), "%s -> %s" % [text, back.error])
			assert_eq(back.params, expected, text)
			assert_eq(back.seed_value, seed_value)
			assert_eq(back.encode(), text)


func test_values_in_schema_order() -> void:
	var s: ParamSchema = _ald()
	var r: ParamSchema.Resolved = s.resolve({"prosperity": 2, "size": "city"})
	assert_eq(PackedStringArray(r.values.keys()), s.field_keys())
	assert_eq(PackedStringArray(s.decode(r.text).values.keys()), s.field_keys())


func test_enum_capacity_keeps_old_codes() -> void:
	# Añadir un id dentro de la capacidad no cambia la radix ni los códigos.
	var old_fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarven"]), "human", 4),
		ParamSchema.int_field("n", 0, 9, 0),
	]
	var new_fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarven", "elven"]), "human", 4),
		ParamSchema.int_field("n", 0, 9, 0),
	]
	var a: ParamSchema = ParamSchema.new("EST", 1, old_fields)
	var b: ParamSchema = ParamSchema.new("EST", 1, new_fields)
	assert_eq(a.resolve({"style": "dwarven", "n": 7}).text, b.resolve({"style": "dwarven", "n": 7}).text)
	# El hueco aún sin id se rechaza en el esquema antiguo.
	assert_eq(a.decode(b.resolve({"style": "elven"}).text).error, SeedCode.ERR_PARAM_ENUM)


func test_appended_default_field_keeps_old_codes() -> void:
	var old_fields: Array[ParamSchema.Field] = [ParamSchema.int_field("n", 0, 9, 0)]
	var new_fields: Array[ParamSchema.Field] = [ParamSchema.int_field("n", 0, 9, 0), ParamSchema.bool_field("x", false)]
	var a: ParamSchema = ParamSchema.new("EST", 1, old_fields)
	var b: ParamSchema = ParamSchema.new("EST", 1, new_fields)
	var text: String = a.resolve({"n": 7}).text
	assert_eq(b.resolve({"n": 7}).text, text)
	assert_eq(b.decode(text).values, {"n": 7, "x": false})


func test_maz_provisional_schema() -> void:
	assert_eq(ParamSchemaRegistry.maz_g1().validate(), "")
	assert_true(ParamSchemaRegistry.has_schema("MAZ", 1))
	var sc: SeedCode = SeedCode.create("DND5", "MAZ", 1, {"rooms": 20, "layout": "cave", "grid": "hex_flat", "corridor_pct": 45}, SEED)
	assert_true(sc.is_valid(), sc.error)
	var text: String = sc.encode()
	gut.p("Ejemplo MAZ G1 (provisional): " + text)
	# 8 + 64·(1 + 4·(1 + 4·15)) = 15688 = "FA8"
	assert_eq(text.split("-")[4], "FA8")
	assert_eq(text.length(), 37)
	assert_eq(SeedCode.parse(text).params, sc.params)


# --- Errores de valores -------------------------------------------------------

func test_rejects_out_of_range() -> void:
	for v: int in [0, 65, -1, 1 << 40]:
		var sc: SeedCode = SeedCode.create("DND5", "EST", 9, {"rooms": v}, 1)
		assert_eq(sc.error, SeedCode.ERR_PARAM_RANGE, str(v))
		assert_eq(sc.error_field, "rooms")
		assert_eq(sc.encode(), "")
	assert_eq(SeedCode.create("DND5", "ALD", 3, {"prosperity": -3}, 1).error, SeedCode.ERR_PARAM_RANGE)
	assert_true(SeedCode.create("DND5", "ALD", 3, {"prosperity": -2}, 1).is_valid())


func test_rejects_unknown_enum_and_key() -> void:
	var e: SeedCode = SeedCode.create("DND5", "EST", 9, {"layout": "maze"}, 1)
	assert_eq(e.error, SeedCode.ERR_PARAM_ENUM)
	assert_eq(e.error_field, "layout")
	var k: SeedCode = SeedCode.create("DND5", "EST", 9, {"zeta": 1, "alpha": 1, "rooms": 3}, 1)
	assert_eq(k.error, SeedCode.ERR_PARAM_UNKNOWN)
	assert_eq(k.error_field, "alpha")  # el primero en orden alfabético
	assert_eq(SeedCode.create("DND5", "EST", 9, {1: 2}, 1).error, SeedCode.ERR_PARAM_UNKNOWN)


func test_rejects_wrong_types() -> void:
	var bad: Array[Dictionary] = [
		{"rooms": 12.0},
		{"rooms": true},
		{"rooms": "12"},
		{"layout": 1},
		{"layout": true},
	]
	for p: Dictionary in bad:
		var sc: SeedCode = SeedCode.create("DND5", "EST", 9, p, 1)
		assert_eq(sc.error, SeedCode.ERR_PARAM_TYPE, str(p))
		assert_eq(sc.encode(), "")
	assert_eq(SeedCode.create("DND5", "ALD", 3, {"walls": 1}, 1).error, SeedCode.ERR_PARAM_TYPE)
	assert_eq(SeedCode.create("DND5", "ALD", 3, {"walls": "true"}, 1).error, SeedCode.ERR_PARAM_TYPE)
	assert_true(SeedCode.create("DND5", "EST", 9, {&"layout": &"cave"}, 1).is_valid())


func test_unknown_schema() -> void:
	assert_eq(SeedCode.create("DND5", "MAZ", 99, {}, 1).error, SeedCode.ERR_SCHEMA)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G99-0-0000000000000")).error, SeedCode.ERR_SCHEMA)
	ParamSchemaRegistry.unregister("EST", 9)
	assert_eq(SeedCode.create("DND5", "EST", 9, {}, 1).error, SeedCode.ERR_SCHEMA)


func test_parse_rejects_bad_params_text() -> void:
	# Capacidad de _typical4: 64·8·4·101 = 206848 valores (0 .. "69ZZ").
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-6A00-0000000000000")).error, SeedCode.ERR_PARAMS)
	# 206847: layout cae en un hueco reservado de la capacidad 8.
	var hole: SeedCode = SeedCode.parse(_signed("RPGM1-DND5-EST-G9-69ZZ-0000000000000"))
	assert_eq(hole.error, SeedCode.ERR_PARAM_ENUM)
	assert_eq(hole.error_field, "layout")
	# Ceros a la izquierda: no canónico.
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-01-0000000000000")).error, SeedCode.ERR_PARAMS)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-00-0000000000000")).error, SeedCode.ERR_PARAMS)
	# U no es Base32 de Crockford.
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-U-0000000000000")).error, SeedCode.ERR_PARAMS)
	assert_true(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-0-0000000000000")).is_valid())


# --- Esquemas mal declarados --------------------------------------------------

func test_invalid_schemas_are_rejected() -> void:
	var bad_fields: Array[ParamSchema.Field] = [
		ParamSchema.int_field("a", 5, 1, 3),
		ParamSchema.int_field("a", 0, 5, 9),
		ParamSchema.int_field("a", 0, 1 << 31, 0),
		ParamSchema.int_field("Bad", 0, 1, 0),
		ParamSchema.int_field("", 0, 1, 0),
		ParamSchema.enum_field("e", PackedStringArray(["a", "b"]), "c"),
		ParamSchema.enum_field("e", PackedStringArray(["a", "b", "c"]), "a", 2),
		ParamSchema.enum_field("e", PackedStringArray(["a", "a"]), "a"),
		ParamSchema.enum_field("e", PackedStringArray([]), ""),
	]
	for f: ParamSchema.Field in bad_fields:
		var one: Array[ParamSchema.Field] = [f]
		assert_ne(ParamSchemaRegistry.register(ParamSchema.new("EST", 50, one)), "", f.key)
	assert_false(ParamSchemaRegistry.has_schema("EST", 50))
	var ok: Array[ParamSchema.Field] = [ParamSchema.int_field("a", 0, (1 << 31) - 1, 0)]
	assert_eq(ParamSchema.new("EST", 50, ok).validate(), "")
	var dup: Array[ParamSchema.Field] = [ParamSchema.int_field("a", 0, 1, 0), ParamSchema.bool_field("a", false)]
	assert_ne(ParamSchema.new("EST", 50, dup).validate(), "")
	assert_ne(ParamSchemaRegistry.register(ParamSchema.new("XYZ", 1, ok)), "")
	assert_ne(ParamSchemaRegistry.register(ParamSchema.new("EST", 0, ok)), "")
	assert_ne(ParamSchemaRegistry.register(_typical4()), "", "duplicado")
	var huge: Array[ParamSchema.Field] = []
	for i: int in range(13):
		huge.append(ParamSchema.int_field("f%d" % i, 0, (1 << 31) - 1, 0))
	assert_ne(ParamSchema.new("EST", 50, huge).validate(), "", "más de 64 caracteres")


# --- Código completo: alias, control y errores de estructura -----------------

func test_aliases_in_params_and_seed() -> void:
	var text: String = SeedCode.create("GEN", "REG", 4, {"n": 33}, 0).encode()
	var parts: PackedStringArray = text.split("-")
	assert_eq(parts[4], "11")
	parts[4] = "iL"
	parts[5] = parts[5].replace("0", "o")
	var messy: String = "  " + " - ".join(parts).to_lower() + "\n"
	var back: SeedCode = SeedCode.parse(messy)
	assert_true(back.is_valid(), back.error)
	assert_eq(back.params, {"n": 33})
	assert_eq(back.encode(), text)


func test_detects_any_single_substitution() -> void:
	var text: String = SeedCode.create("DND5", "EST", 9, {"rooms": 9, "grid": "hex_pointy"}, 987654321).encode()
	var detected: int = 0
	var tried: int = 0
	for i: int in text.length():
		if text[i] == "-":
			continue
		for c: String in "0123456789ABCDEFGHJKMNPQRSTVWXYZ":
			if c == text[i]:
				continue
			var mutated: String = text.substr(0, i) + c + text.substr(i + 1)
			tried += 1
			if not SeedCode.parse(mutated).is_valid():
				detected += 1
	assert_eq(detected, tried, "sustituciones detectadas %d/%d" % [detected, tried])


func test_typo_reports_check_error() -> void:
	var text: String = SeedCode.create("DND5", "EST", 9, {"rooms": 20}, 5).encode()
	var parts: PackedStringArray = text.split("-")
	assert_eq(parts[4], "8")
	# "U" no es Base32 (sería SEED_ERR_PARAMS), pero lo primero es el control.
	parts[4] = "U"
	assert_eq(SeedCode.parse("-".join(parts)).error, SeedCode.ERR_CHECK)


func test_detects_adjacent_transposition() -> void:
	var text: String = SeedCode.create("DND5", "EST", 9, {"rooms": 40, "corridor_pct": 77}, 0x0123456789ABCDEF).encode()
	for i: int in range(text.length() - 1):
		if text[i] == text[i + 1] or text[i] == "-" or text[i + 1] == "-":
			continue
		var swapped: String = text.substr(0, i) + text[i + 1] + text[i] + text.substr(i + 2)
		assert_false(SeedCode.parse(swapped).is_valid(), "no detectada: " + swapped)


func test_structure_errors() -> void:
	assert_eq(SeedCode.parse("hola").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse("RPGM2-DND5-MAZ-G1-0-0000000000000-0").error, SeedCode.ERR_VERSION)
	assert_eq(SeedCode.parse("RPGM1-DN_5-MAZ-G1-0-0000000000000-0").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse("RPGM1-DND5-MAZ-G1--0000000000000-0").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-0000000000000") + "0").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-XXX-G1-0-0000000000000")).error, SeedCode.ERR_SCALE)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G0-0-0000000000000")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-X1-0-0000000000000")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G01-0-0000000000000")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G-0-0000000000000")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-D-MAZ-G1-0-0000000000000")).error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-00000000000")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-G000000000000")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.create("D", "MAZ", 1, {}, 0).error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.create("DND5", "MAZ", 0, {}, 0).error, SeedCode.ERR_GEN)
