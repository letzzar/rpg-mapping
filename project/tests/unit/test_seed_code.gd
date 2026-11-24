extends GutTest
## Tests de core/seed: Base32 Crockford, esquemas posicionales de PARAMS,
## SEED compacta, control GF(32) y código RPGM1 (ida y vuelta, longitud,
## errores, alias, detección exhaustiva de erratas).

## Semilla de 64 bits (13 caracteres) y semilla típica de la app (8).
const SEED: int = -8629252141511181193
const APP_SEED_TEXT: String = "3QV8M2KD"
const HALF31: int = 1 << 30
const CROCKFORD: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const ALNUM: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## Ejemplos de la documentación (PROYECTO.md §5.3), con el control calculado a
## mano: si cambian, cambia el formato.
const MAZ_EXAMPLE: String = "RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P"
const ALD_EXAMPLE: String = "RPGM1-PF2E-ALD-G3-0-1A-K"


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


## Añade el control correcto (o "0" si el cuerpo no es representable, para
## probar errores de estructura que se detectan antes del control).
static func _signed(body: String) -> String:
	var c: String = SeedCode.check_char(body)
	return "%s-%s" % [body, c if not c.is_empty() else "0"]


static func _app_seed() -> int:
	return Base32Crockford.decode_u64_compact(APP_SEED_TEXT).value


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


## Códigos variados para las pruebas exhaustivas de erratas.
func _sample_codes() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([MAZ_EXAMPLE, ALD_EXAMPLE])
	var rng: Rng = Rng.new(77)
	var cases: Array[Array] = [[_typical4(), "EST", 9], [_ald(), "ALD", 3], [_wide(), "EDI", 7], [_single(), "REG", 4]]
	for c: Array in cases:
		var s: ParamSchema = c[0]
		var esc: String = c[1]
		var gen: int = c[2]
		var seeds: Array[int] = [0, 42, _app_seed(), SEED]
		for seed_value: int in seeds:
			var text: String = SeedCode.create("DND5", esc, gen, _random_params(s, rng), seed_value).encode()
			assert_ne(text, "")
			out.append(text)
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


func test_base32_u64_compact() -> void:
	assert_eq(Base32Crockford.encode_u64_compact(0), "0")
	assert_eq(Base32Crockford.encode_u64_compact(42), "1A")
	assert_eq(Base32Crockford.encode_u64_compact(-1), "FZZZZZZZZZZZZ")
	assert_eq(Base32Crockford.encode_u64_compact(1 << 35), "10000000")
	assert_eq(Base32Crockford.encode_u64_compact((1 << 40) - 1), "ZZZZZZZZ")
	var rng: Rng = Rng.new(3)
	var values: Array[int] = [0, 1, 31, 32, -1, 1 << 63, 0x7FFFFFFFFFFFFFFF]
	for i: int in range(300):
		# Longitudes variadas: desplazar un u64 aleatorio entre 0 y 63 bits.
		var v: int = (rng.next_u32() << 32) | rng.next_u32()
		values.append(Bits64.lsr(v, rng.bounded(64)))
	for v: int in values:
		var text: String = Base32Crockford.encode_u64_compact(v)
		assert_true(text == "0" or not text.begins_with("0"), text)
		var back: Base32Crockford.U64Result = Base32Crockford.decode_u64_compact(text)
		assert_true(back.ok, text)
		assert_eq(back.value, v)
	var aliased: Base32Crockford.U64Result = Base32Crockford.decode_u64_compact("il")
	assert_true(aliased.ok)
	assert_eq(aliased.value, 33)


func test_base32_u64_compact_rejects() -> void:
	for bad: String in ["", "00", "01", "o1", "U", "1U", "GZZZZZZZZZZZZ", "1ZZZZZZZZZZZZZ"]:
		assert_false(Base32Crockford.decode_u64_compact(bad).ok, bad)


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


# --- Semillas de la app -------------------------------------------------------

func test_app_seed_from_bytes() -> void:
	assert_eq(SeedCode.seed40_from_bytes(PackedByteArray([1, 2, 3, 4, 5, 6])), 0x0102030405)
	assert_eq(SeedCode.seed40_from_bytes(PackedByteArray([255, 255, 255, 255, 255])), (1 << 40) - 1)
	assert_eq(SeedCode.seed40_from_bytes(PackedByteArray([1, 2, 3, 4])), -1)


func test_random_app_seed_is_40_bits_and_8_chars() -> void:
	for i: int in range(200):
		var v: int = SeedCode.random_app_seed()
		assert_true(v >= SeedCode.APP_SEED_MIN and v < (1 << SeedCode.APP_SEED_BITS), str(v))
		assert_eq(Base32Crockford.encode_u64_compact(v).length(), SeedCode.APP_SEED_LEN)


# --- Control GF(32): propiedades, verificadas de forma exhaustiva ---------------

func test_gf32_is_a_field() -> void:
	# Sin divisores de cero: base de la detección de sustituciones y transposiciones.
	for a: int in range(1, 32):
		assert_eq(SeedCode.gf32_mul(a, 1), a)
		assert_eq(SeedCode.gf32_mul_x(a), SeedCode.gf32_mul(a, 2))
		for b: int in range(1, 32):
			assert_true(SeedCode.gf32_mul(a, b) != 0, "%d·%d" % [a, b])
	# x tiene orden 31 (primitivo): pesos consecutivos y a distancia 2 distintos.
	var p: int = 1
	for k: int in range(1, 32):
		p = SeedCode.gf32_mul_x(p)
		if k < 31:
			assert_ne(p, 1, "x^%d" % k)
	assert_eq(p, 1, "x^31")


func test_check_value_detects_all_substitutions() -> void:
	var rng: Rng = Rng.new(11)
	var base: PackedInt32Array = PackedInt32Array()
	for i: int in range(40):
		base.append(rng.bounded(32))
	var c0: int = SeedCode.check_value(base)
	for i: int in base.size():
		for alt: int in range(32):
			if alt == base[i]:
				continue
			var m: PackedInt32Array = base.duplicate()
			m[i] = alt
			assert_true(SeedCode.check_value(m) != c0, "sustitución no detectada en %d" % i)


## Todas las parejas (a, b) con a != b en todas las posiciones adyacentes de una
## secuencia de 33 símbolos (cubre el periodo 31 de los pesos).
func test_check_value_detects_all_adjacent_transpositions() -> void:
	var seq: PackedInt32Array = PackedInt32Array()
	seq.resize(33)
	seq.fill(0)
	var missed: int = 0
	for i: int in range(seq.size() - 1):
		for a: int in range(32):
			for b: int in range(a + 1, 32):
				seq[i] = a
				seq[i + 1] = b
				var ab: int = SeedCode.check_value(seq)
				seq[i] = b
				seq[i + 1] = a
				if SeedCode.check_value(seq) == ab:
					missed += 1
		seq[i] = 0
		seq[i + 1] = 0
	assert_eq(missed, 0)


# --- PARAMS posicional ----------------------------------------------------------

## Longitud típica con 4 parámetros, todos distintos de su defecto, y semilla
## de la app (8 car.). Valor congelado: fija el orden (primer campo = dígito
## menos significativo). N = 8 + 64·(1 + 8·(1 + 4·15)) = 31304 = "YJ8".
func test_typical_length_4_params() -> void:
	var params: Dictionary = {"rooms": 20, "layout": "cave", "grid": "hex_flat", "corridor_pct": 45}
	var sc: SeedCode = SeedCode.create("DND5", "EST", 9, params, _app_seed())
	assert_true(sc.is_valid(), sc.error)
	var text: String = sc.encode()
	gut.p("Código típico con 4 parámetros (%d car.): %s" % [text.length(), text])
	assert_eq(text.split("-")[4], "YJ8")
	assert_eq(text.split("-")[5], APP_SEED_TEXT)
	assert_eq(text.length(), 32)


func test_documented_examples() -> void:
	var maz: SeedCode = SeedCode.create("DND5", "MAZ", 1, {"rooms": 20, "layout": "cave", "grid": "hex_flat", "corridor_pct": 45}, _app_seed())
	assert_eq(maz.encode(), MAZ_EXAMPLE)
	assert_eq(SeedCode.create("PF2E", "ALD", 3, {}, 42).encode(), ALD_EXAMPLE)
	var back: SeedCode = SeedCode.parse(ALD_EXAMPLE)
	assert_true(back.is_valid(), back.error)
	assert_eq(back.seed_value, 42)
	assert_eq(back.params, {"size": "village", "style": "human", "walls": false, "prosperity": 0})


func test_all_defaults_is_zero() -> void:
	var s: ParamSchema = _typical4()
	assert_eq(s.resolve({}).text, "0")
	assert_eq(s.resolve(s.default_values()).text, "0")
	var a: String = SeedCode.create("DND5", "EST", 9, {}, 7).encode()
	var b: String = SeedCode.create("DND5", "EST", 9, s.default_values(), 7).encode()
	assert_eq(a, b)
	assert_eq(a.split("-")[4], "0")
	assert_eq(a.split("-")[5], "7")


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


func test_ald_style() -> void:
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
			# Semillas de todas las longitudes (1 a 13 caracteres).
			var seed_value: int = Bits64.lsr((rng.next_u32() << 32) | rng.next_u32(), rng.bounded(64))
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
	var back: SeedCode = SeedCode.parse(MAZ_EXAMPLE)
	assert_true(back.is_valid(), back.error)
	var rooms: int = back.params["rooms"]
	var grid: String = back.params["grid"]
	assert_eq(rooms, 20)
	assert_eq(grid, "hex_flat")
	assert_eq(back.seed_value, _app_seed())
	assert_eq(back.encode(), MAZ_EXAMPLE)


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
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G99-0-0")).error, SeedCode.ERR_SCHEMA)
	ParamSchemaRegistry.unregister("EST", 9)
	assert_eq(SeedCode.create("DND5", "EST", 9, {}, 1).error, SeedCode.ERR_SCHEMA)


func test_parse_rejects_bad_params_text() -> void:
	# Capacidad de _typical4: 64·8·4·101 = 206848 valores (0 .. "69ZZ").
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-6A00-0")).error, SeedCode.ERR_PARAMS)
	# 206847: layout cae en un hueco reservado de la capacidad 8.
	var hole: SeedCode = SeedCode.parse(_signed("RPGM1-DND5-EST-G9-69ZZ-0"))
	assert_eq(hole.error, SeedCode.ERR_PARAM_ENUM)
	assert_eq(hole.error_field, "layout")
	# Ceros a la izquierda: no canónico.
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-01-0")).error, SeedCode.ERR_PARAMS)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-00-0")).error, SeedCode.ERR_PARAMS)
	# U no es Base32 de Crockford.
	assert_eq(SeedCode.parse("RPGM1-DND5-EST-G9-U-0-0").error, SeedCode.ERR_PARAMS)
	assert_true(SeedCode.parse(_signed("RPGM1-DND5-EST-G9-0-0")).is_valid())


func test_parse_rejects_bad_seed_text() -> void:
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-01A")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-0000000000000")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-G000000000000")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-10000000000000")).error, SeedCode.ERR_SEED)
	assert_eq(SeedCode.parse("RPGM1-DND5-MAZ-G1-0-1U-0").error, SeedCode.ERR_SEED)
	var max_seed: SeedCode = SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-FZZZZZZZZZZZZ"))
	assert_true(max_seed.is_valid(), max_seed.error)
	assert_eq(max_seed.seed_value, -1)


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


# --- Código completo: alias, erratas y errores de estructura -----------------

func test_aliases_in_params_seed_and_check() -> void:
	var text: String = SeedCode.create("GEN", "REG", 4, {"n": 33}, 33).encode()
	var parts: PackedStringArray = text.split("-")
	assert_eq(parts[4], "11")
	assert_eq(parts[5], "11")
	parts[4] = "iL"
	parts[5] = "Li"
	parts[6] = parts[6].replace("0", "o").replace("1", "l")
	var messy: String = "  " + " - ".join(parts).to_lower() + "\n"
	var back: SeedCode = SeedCode.parse(messy)
	assert_true(back.is_valid(), back.error)
	assert_eq(back.params, {"n": 33})
	assert_eq(back.seed_value, 33)
	assert_eq(back.encode(), text)


func test_check_char_is_crockford() -> void:
	for text: String in _sample_codes():
		var c: String = text.substr(text.length() - 1)
		assert_true(CROCKFORD.contains(c), text)


## Cualquier carácter del cuerpo o del control cambiado por cualquier otro de
## 0-9A-Z invalida el código (salvo alias de Crockford, que no cambian nada).
func test_detects_any_single_substitution() -> void:
	var detected: int = 0
	var tried: int = 0
	for text: String in _sample_codes():
		for i: int in text.length():
			if text[i] == "-":
				continue
			for c: String in ALNUM:
				if c == text[i]:
					continue
				var mutated: String = text.substr(0, i) + c + text.substr(i + 1)
				var back: SeedCode = SeedCode.parse(mutated)
				if back.is_valid() and back.encode() == text:
					continue  # alias (p. ej. 0 -> O en SEED)
				tried += 1
				if not back.is_valid():
					detected += 1
				else:
					gut.p("no detectada: " + mutated)
	gut.p("sustituciones probadas: %d" % tried)
	assert_true(tried > 1000)
	assert_eq(detected, tried, "sustituciones detectadas %d/%d" % [detected, tried])


func test_detects_adjacent_transposition() -> void:
	for text: String in _sample_codes():
		for i: int in range(text.length() - 1):
			if text[i] == text[i + 1] or text[i] == "-" or text[i + 1] == "-":
				continue
			var swapped: String = text.substr(0, i) + text[i + 1] + text[i] + text.substr(i + 2)
			assert_false(SeedCode.parse(swapped).is_valid(), "no detectada: " + swapped)


## Con PARAMS y SEED de longitud variable, correr un guion una posición no
## debe dar otro código válido.
func test_detects_shifted_dash() -> void:
	for text: String in _sample_codes():
		for i: int in text.length():
			if text[i] != "-":
				continue
			var left: String = text.substr(0, i - 1) + "-" + text[i - 1] + text.substr(i + 1)
			var right: String = text.substr(0, i) + text[i + 1] + "-" + text.substr(i + 2)
			assert_false(SeedCode.parse(left).is_valid(), "no detectada: " + left)
			assert_false(SeedCode.parse(right).is_valid(), "no detectada: " + right)


func test_typo_reports_check_error() -> void:
	var text: String = SeedCode.create("DND5", "EST", 9, {"rooms": 20}, 5).encode()
	var parts: PackedStringArray = text.split("-")
	assert_eq(parts[4], "8")
	parts[4] = "9"
	assert_eq(SeedCode.parse("-".join(parts)).error, SeedCode.ERR_CHECK)
	parts = text.split("-")
	parts[5] = "6"
	assert_eq(SeedCode.parse("-".join(parts)).error, SeedCode.ERR_CHECK)
	parts = text.split("-")
	parts[6] = "U"
	assert_eq(SeedCode.parse("-".join(parts)).error, SeedCode.ERR_CHECK)


## Ninguna escala está a una sustitución o transposición de otra: una errata en
## ESC siempre da SEED_ERR_SCALE (el control trata la escala como un símbolo).
func test_scales_are_far_apart() -> void:
	for a: String in SeedCode.SCALES:
		for b: String in SeedCode.SCALES:
			if a == b:
				continue
			var diff: int = 0
			for i: int in 3:
				if a[i] != b[i]:
					diff += 1
			assert_true(diff >= 2, "%s/%s" % [a, b])
			assert_ne(a[1] + a[0] + a[2], b)
			assert_ne(a[0] + a[2] + a[1], b)


func test_system_code_alphabet() -> void:
	assert_true(SeedCode.is_system_code("DND5"))
	assert_true(SeedCode.is_system_code("GEN"))
	for bad: String in ["D", "DN", "DND55", "DIL5", "OSR", "UNO", "dnd5", "DN_5"]:
		assert_false(SeedCode.is_system_code(bad), bad)


func test_structure_errors() -> void:
	assert_eq(SeedCode.parse("hola").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse("RPGM2-DND5-MAZ-G1-0-0-0").error, SeedCode.ERR_VERSION)
	assert_eq(SeedCode.parse("RPGM1-DN_5-MAZ-G1-0-0-0").error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.parse("RPGM1-DIL5-MAZ-G1-0-0-0").error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.parse("RPGM1-DND5-MAZ-G1--0-0").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G1-0-0") + "0").error, SeedCode.ERR_FORMAT)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-XXX-G1-0-0")).error, SeedCode.ERR_SCALE)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G0-0-0")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-X1-0-0")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G01-0-0")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-DND5-MAZ-G-0-0")).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.parse(_signed("RPGM1-D-MAZ-G1-0-0")).error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.create("D", "MAZ", 1, {}, 0).error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.create("OSR", "MAZ", 1, {}, 0).error, SeedCode.ERR_SYSTEM)
	assert_eq(SeedCode.create("DND5", "MAZ", 0, {}, 0).error, SeedCode.ERR_GEN)
	assert_eq(SeedCode.check_char("RPGM1-DND5-XXX-G1-0-0"), "")
	assert_eq(SeedCode.check_char("RPGM1-DND5-MAZ-G1-0"), "")
