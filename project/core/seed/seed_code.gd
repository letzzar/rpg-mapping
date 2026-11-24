class_name SeedCode
extends RefCounted
## Código de semilla compartible RPGM1 (PROYECTO.md §5.3).
##
##   RPGM1-<SIS>-<ESC>-G<n>-<PARAMS>-<SEED>-<CRC>
##   ej.: RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P   (MAZ G1 provisional: rooms=20,
##        layout=cave, grid=hex_flat, corridor_pct=45; semilla de 40 bits)
##   ej.: RPGM1-PF2E-ALD-G3-0-1A-K            (todo por defecto, semilla 42)
##
## Decisiones de formato (ADR 009):
## - SEED: uint64 en Base32 Crockford de longitud VARIABLE, forma canónica sin
##   ceros a la izquierda ("0" = semilla 0), de 1 a 13 caracteres. La app
##   genera semillas de 40 bits con el primer carácter distinto de 0, así que
##   siempre ocupan 8 (random_app_seed()); a mano se aceptan cortas (42 = "1A").
## - PARAMS: codificación POSICIONAL según el esquema del generador
##   (ParamSchema, registrado por escala y GEN en ParamSchemaRegistry): un
##   entero de base mixta en Base32 Crockford, "0" si todo vale su defecto.
##   Detalles y porqués en param_schema.gd.
## - SIS: 3-4 caracteres del alfabeto de Crockford (sin I, L, O ni U).
## - CRC: un carácter del alfabeto de Crockford calculado en GF(32); ver
##   check_value(). Detecta el 100 % de las sustituciones de un carácter y de
##   las transposiciones de dos adyacentes (también saltadas y gemelas).
##
## El código de sistema no se valida contra una lista: lo declara cada perfil
## de data/systems (reglas como datos). Las escalas sí son fijas. El esquema
## depende solo de (ESC, GEN), no del sistema.

const FORMAT_VERSION: String = "RPGM1"
const SCALES: PackedStringArray = ["MUN", "REG", "ALD", "EDI", "EST", "MAZ"]
const EMPTY_PARAMS: String = ParamSchema.EMPTY_TEXT
## Polinomio primitivo x^5 + x^2 + 1 que define GF(32).
const GF32_POLY: int = 0x25

## Semillas que genera la app: 40 bits con los 5 de arriba no nulos, para que
## ocupen siempre 8 caracteres (entropía ≈ 39,95 bits).
const APP_SEED_BITS: int = 40
const APP_SEED_MIN: int = 1 << 35
const APP_SEED_LEN: int = 8

## Claves de i18n de error (vacío = válido).
const ERR_FORMAT: String = "SEED_ERR_FORMAT"
const ERR_VERSION: String = "SEED_ERR_VERSION"
const ERR_SYSTEM: String = "SEED_ERR_SYSTEM"
const ERR_SCALE: String = "SEED_ERR_SCALE"
const ERR_GEN: String = "SEED_ERR_GEN"
## No hay esquema (y por tanto generador) para ese (ESC, GEN) en esta versión.
const ERR_SCHEMA: String = "SEED_ERR_SCHEMA"
## Texto PARAMS mal formado o que no cabe en el esquema.
const ERR_PARAMS: String = ParamSchema.ERR_PARAMS
const ERR_PARAM_UNKNOWN: String = ParamSchema.ERR_PARAM_UNKNOWN
const ERR_PARAM_TYPE: String = ParamSchema.ERR_PARAM_TYPE
const ERR_PARAM_RANGE: String = ParamSchema.ERR_PARAM_RANGE
const ERR_PARAM_ENUM: String = ParamSchema.ERR_PARAM_ENUM
const ERR_SEED: String = "SEED_ERR_SEED"
const ERR_CHECK: String = "SEED_ERR_CHECK"

var system: String = ""
var scale: String = ""
var gen_version: int = 0
## Si es válido: TODOS los campos del esquema en su orden (int, bool o el id
## String de un enumerado), con los omitidos ya resueltos a su defecto.
var params: Dictionary = {}
var seed_value: int = 0
## Clave de i18n del error si el código no es válido; "" si lo es.
var error: String = ""
## Parámetro que provocó el error (para el texto "{param}"); "" si no aplica.
var error_field: String = ""
## Esquema de (scale, gen_version); null si no se encontró.
var schema: ParamSchema = null


## `p_params` puede omitir campos (toman su valor por defecto). `p_seed` es un
## uint64 guardado en int64 (los negativos son semillas >= 2^63).
static func create(p_system: String, p_scale: String, p_gen: int, p_params: Dictionary, p_seed: int) -> SeedCode:
	var sc: SeedCode = SeedCode.new()
	sc.system = p_system
	sc.scale = p_scale
	sc.gen_version = p_gen
	sc.params = p_params.duplicate()
	sc.seed_value = p_seed
	sc.error = sc._validate_header()
	if not sc.is_valid():
		return sc
	sc.schema = ParamSchemaRegistry.get_schema(p_scale, p_gen)
	if sc.schema == null:
		sc.error = ERR_SCHEMA
		return sc
	var r: ParamSchema.Resolved = sc.schema.resolve(p_params)
	if not r.error.is_empty():
		sc.error = r.error
		sc.error_field = r.field
		return sc
	sc.params = r.values
	return sc


func is_valid() -> bool:
	return error.is_empty()


## Texto del código. Devuelve "" si los campos no son válidos.
func encode() -> String:
	if not is_valid() or schema == null:
		return ""
	var r: ParamSchema.Resolved = schema.resolve(params)
	if not r.error.is_empty():
		return ""
	var body: String = _body(r.text)
	return "%s-%s" % [body, check_char(body)]


## Analiza un código pegado por el usuario (tolera espacios, minúsculas y los
## alias de Crockford O→0, I/L→1 en PARAMS, SEED y CRC). Siempre devuelve un
## SeedCode; mirar is_valid().
##
## Orden de comprobación: estructura -> control -> contenido.
## - Estructura: lo necesario para calcular el control (7 partes, versión,
##   sistema con alfabeto válido, escala de la lista, "G" + dígitos, caracteres
##   Base32 válidos). Ninguna escala está a una sustitución de otra, así que
##   una errata en ESC siempre da SEED_ERR_SCALE.
## - Control antes que contenido: si no cuadra, lo probable es una errata, y
##   "revisa si hay una errata" orienta mejor que "valor fuera de rango". Si
##   cuadra y el contenido falla, el código es auténtico pero de otra versión
##   (p. ej. SEED_ERR_SCHEMA) o no canónico (ceros a la izquierda).
static func parse(text: String) -> SeedCode:
	var sc: SeedCode = SeedCode.new()
	var parts: PackedStringArray = text.strip_edges().replace(" ", "").to_upper().split("-")
	if parts.size() != 7:
		sc.error = ERR_FORMAT
		return sc
	for part: String in parts:
		if part.is_empty():
			sc.error = ERR_FORMAT
			return sc
	if parts[0] != FORMAT_VERSION:
		sc.error = ERR_VERSION
		return sc
	# Los alias solo se aplican a los campos Base32; SIS y ESC son literales.
	parts[4] = _unalias(parts[4])
	parts[5] = _unalias(parts[5])
	parts[6] = _unalias(parts[6])
	sc.system = parts[1]
	if not is_system_code(sc.system):
		sc.error = ERR_SYSTEM
		return sc
	sc.scale = parts[2]
	if not SCALES.has(sc.scale):
		sc.error = ERR_SCALE
		return sc
	var gen_text: String = parts[3]
	var digits: String = gen_text.substr(1)
	# Sin signo ni ceros a la izquierda: un único texto por GEN.
	var gen_ok: bool = gen_text.begins_with("G") and _is_digits(digits)
	gen_ok = gen_ok and not digits.is_empty() and digits.length() <= 9
	gen_ok = gen_ok and (digits.length() == 1 or digits[0] != "0")
	if not gen_ok:
		sc.error = ERR_GEN
		return sc
	if not _is_crockford(parts[4]):
		sc.error = ERR_PARAMS
		return sc
	if not _is_crockford(parts[5]):
		sc.error = ERR_SEED
		return sc
	if parts[6].length() != 1:
		sc.error = ERR_FORMAT
		return sc
	if not _is_crockford(parts[6]) or check_char("-".join(parts.slice(0, 6))) != parts[6]:
		sc.error = ERR_CHECK
		return sc
	sc.gen_version = digits.to_int()
	sc.error = sc._validate_header()
	if not sc.is_valid():
		return sc
	sc.schema = ParamSchemaRegistry.get_schema(sc.scale, sc.gen_version)
	if sc.schema == null:
		sc.error = ERR_SCHEMA
		return sc
	var r: ParamSchema.Resolved = sc.schema.decode(parts[4])
	if not r.error.is_empty():
		sc.error = r.error
		sc.error_field = r.field
		return sc
	sc.params = r.values
	var s: Base32Crockford.U64Result = Base32Crockford.decode_u64_compact(parts[5])
	if not s.ok:
		sc.error = ERR_SEED
		return sc
	sc.seed_value = s.value
	return sc


## Carácter de control de un cuerpo canónico `RPGM1-SIS-ESC-Gn-PARAMS-SEED`
## (sin alias, en mayúsculas). Devuelve "" si el cuerpo no se puede
## convertir en símbolos (no son 6 partes, escala desconocida o carácter
## fuera del alfabeto de Crockford).
static func check_char(body: String) -> String:
	var symbols: PackedInt32Array = body_symbols(body)
	if symbols.is_empty():
		return ""
	return Base32Crockford.ALPHABET[check_value(symbols)]


## Símbolos 0..31 sobre los que se calcula el control:
## - cada carácter, por su valor en el alfabeto de Crockford;
## - la escala, como UN símbolo: su índice en SCALES (MUN y ALD contienen U
##   y L, que no están en el alfabeto);
## - entre dos campos, un separador de valor 0. Así, correr un guion una
##   posición equivale a transponer un carácter con un 0 (se detecta) o deja
##   un cero a la izquierda/campo vacío (se rechaza): con PARAMS y SEED de
##   longitud variable, "FA8-1A" y "FA-81A" no comparten control.
## Devuelve un array vacío si el cuerpo no es representable.
static func body_symbols(body: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var fields: PackedStringArray = body.split("-")
	if fields.size() != 6:
		return PackedInt32Array()
	for k: int in fields.size():
		if k > 0:
			out.append(0)
		if k == 2:
			var idx: int = SCALES.find(fields[k])
			if idx < 0:
				return PackedInt32Array()
			out.append(idx)
			continue
		for c: String in fields[k]:
			var v: int = Base32Crockford.ALPHABET.find(c)
			if v < 0:
				return PackedInt32Array()
			out.append(v)
	return out


## Control lineal sobre GF(32) = GF(2)[x]/(x^5 + x^2 + 1):
##   c = Σ s_i · x^(n-i)   (Horner: c = (…((s_0)·x + s_1)·x + …)·x)
## Por qué detecta el 100 %:
## - Sustitución en i: el control cambia en x^(n-i)·(a ⊕ a'), producto de dos
##   elementos no nulos de un cuerpo, nunca 0.
## - Transposición de i e i+1: cambia en (x^(n-i) ⊕ x^(n-i-1))·(a ⊕ b), no nulo
##   porque x ≠ 1 y a ≠ b. Lo mismo para la del último símbolo con el propio
##   control (peso x^0 = 1) y para las saltadas (x^2 ≠ 1, orden de x = 31).
## Por qué no ISO 7064 sobre 32 símbolos: los sistemas puros necesitan módulo
## primo (31 deja 2 símbolos con el mismo valor; 37 necesita 37 símbolos de
## control) y el híbrido MOD 33,32 necesita M+1 primo (33 = 3·11, y 2 tiene
## orden 10 módulo 33). GF(32) da las mismas garantías con 32 símbolos justos
## y solo usa desplazamientos y XOR.
static func check_value(symbols: PackedInt32Array) -> int:
	var s: int = 0
	for v: int in symbols:
		s = gf32_mul_x(s ^ v)
	return s


## Multiplica por x en GF(32) (0 <= a <= 31).
static func gf32_mul_x(a: int) -> int:
	var t: int = a << 1
	if (t & 32) != 0:
		t ^= GF32_POLY
	return t


## Producto general en GF(32) (para los tests de las propiedades).
static func gf32_mul(a: int, b: int) -> int:
	var r: int = 0
	var x: int = a
	var y: int = b
	while y > 0:
		if (y & 1) != 0:
			r ^= x
		x = gf32_mul_x(x)
		y >>= 1
	return r


## true si `s` es un código de sistema aceptable: 3-4 caracteres del alfabeto
## de Crockford en mayúsculas (sin I, L, O ni U, para que el control lo cubra).
static func is_system_code(s: String) -> bool:
	return s.length() >= 3 and s.length() <= 4 and _is_crockford(s)


## Semilla nueva para la APP (botón "nueva semilla"): 40 bits de entropía del
## sistema (Crypto), con el primer carácter no nulo => siempre 8 caracteres.
## NUNCA usar en core/gen: los generadores reciben la semilla, no la crean.
static func random_app_seed() -> int:
	var crypto: Crypto = Crypto.new()
	var v: int = 0
	# Rechazo (probabilidad 1/32 por intento) en vez de módulo: sin sesgo.
	while v < APP_SEED_MIN:
		v = seed40_from_bytes(crypto.generate_random_bytes(5))
	return v


## Primeros 5 bytes (big-endian) como entero de 40 bits; -1 si hay menos.
static func seed40_from_bytes(bytes: PackedByteArray) -> int:
	if bytes.size() < 5:
		return -1
	var v: int = 0
	for i: int in 5:
		v = (v << 8) | bytes[i]
	return v


func _body(params_text: String) -> String:
	return "-".join(PackedStringArray([
		FORMAT_VERSION,
		system,
		scale,
		"G%d" % gen_version,
		params_text,
		Base32Crockford.encode_u64_compact(seed_value),
	]))


func _validate_header() -> String:
	if not is_system_code(system):
		return ERR_SYSTEM
	if not SCALES.has(scale):
		return ERR_SCALE
	if gen_version < 1:
		return ERR_GEN
	return ""


## Todos los caracteres en el alfabeto de Crockford (mayúsculas, sin alias).
static func _is_crockford(s: String) -> bool:
	for c: String in s:
		if Base32Crockford.ALPHABET.find(c) < 0:
			return false
	return true


static func _is_digits(s: String) -> bool:
	for c: String in s:
		if "0123456789".find(c) < 0:
			return false
	return true


## O -> 0, I/L -> 1 (texto ya en mayúsculas).
static func _unalias(s: String) -> String:
	return s.replace("O", "0").replace("I", "1").replace("L", "1")
