class_name SeedCode
extends RefCounted
## Código de semilla compartible RPGM1 (PROYECTO.md §5.3).
##
##   RPGM1-<SIS>-<ESC>-G<n>-<PARAMS>-<SEED>-<CRC>
##   ej.: RPGM1-DND5-MAZ-G1-FA8-0000000000016-<CRC>   (MAZ G1 provisional:
##        rooms=20, layout=cave, grid=hex_flat, corridor_pct=45; semilla 38)
##
## Decisiones de formato (ADR 009):
## - SEED: 13 caracteres Base32 Crockford de longitud fija (64 bits necesitan
##   13; el ejemplo de 12 de la especificación solo cubría 60 bits).
## - PARAMS: codificación POSICIONAL según el esquema del generador
##   (ParamSchema, registrado por escala y GEN en ParamSchemaRegistry): un
##   entero de base mixta en Base32 Crockford, "0" si todo vale su defecto.
##   Con 4 parámetros típicos ocupa 3 caracteres (el texto canónico anterior,
##   ~70). Detalles y porqués en param_schema.gd.
## - CRC: ISO/IEC 7064 MOD 37,36 sobre el cuerpo sin guiones; el carácter de
##   control está en 0-9A-Z. Detecta toda sustitución de un carácter y toda
##   transposición de dos adyacentes.
##
## El código de sistema (SIS) no se valida contra una lista: lo declara cada
## perfil de data/systems (reglas como datos). Las escalas sí son fijas. El
## esquema depende solo de (ESC, GEN), no del sistema.

const FORMAT_VERSION: String = "RPGM1"
const SCALES: PackedStringArray = ["MUN", "REG", "ALD", "EDI", "EST", "MAZ"]
const EMPTY_PARAMS: String = ParamSchema.EMPTY_TEXT
const _ALNUM: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

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


## `p_params` puede omitir campos (toman su valor por defecto).
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
## alias de Crockford en PARAMS y SEED). Siempre devuelve un SeedCode; mirar
## is_valid().
##
## Orden de comprobación: estructura -> control -> contenido. El control va
## antes que el contenido porque, si no cuadra, lo más probable es una errata
## y "revisa si hay una errata" orienta mejor que, p. ej., "valor fuera de
## rango". Si cuadra y aun así falla el contenido, el código es auténtico pero
## de otra versión (p. ej. SEED_ERR_SCHEMA: generador desconocido).
static func parse(text: String) -> SeedCode:
	var sc: SeedCode = SeedCode.new()
	var parts: PackedStringArray = text.strip_edges().replace(" ", "").to_upper().split("-")
	if parts.size() != 7:
		sc.error = ERR_FORMAT
		return sc
	if parts[0] != FORMAT_VERSION:
		sc.error = ERR_VERSION
		return sc
	# Los alias de Crockford solo existen en los campos Base32.
	parts[4] = _unalias(parts[4])
	parts[5] = _unalias(parts[5])
	for i: int in parts.size():
		if parts[i].is_empty() or not _is_alnum(parts[i]):
			sc.error = ERR_FORMAT
			return sc
	if parts[6].length() != 1:
		sc.error = ERR_FORMAT
		return sc
	var body: String = "-".join(parts.slice(0, 6))
	if check_char(body) != parts[6]:
		sc.error = ERR_CHECK
		return sc
	sc.system = parts[1]
	sc.scale = parts[2]
	var gen_text: String = parts[3]
	var digits: String = gen_text.substr(1)
	# Sin signo ni ceros a la izquierda: un único texto por GEN.
	var gen_ok: bool = gen_text.begins_with("G") and _is_digits(digits)
	gen_ok = gen_ok and not digits.is_empty() and digits.length() <= 9
	gen_ok = gen_ok and (digits.length() == 1 or digits[0] != "0")
	if not gen_ok:
		sc.error = ERR_GEN
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
	var s: Base32Crockford.U64Result = Base32Crockford.decode_u64(parts[5])
	if not s.ok:
		sc.error = ERR_SEED
		return sc
	sc.seed_value = s.value
	return sc


## Carácter de control ISO/IEC 7064 MOD 37,36 (híbrido) sobre `body`,
## ignorando los guiones.
static func check_char(body: String) -> String:
	const M: int = 36
	var p: int = M
	for c: String in body:
		if c == "-":
			continue
		var a: int = _ALNUM.find(c)
		assert(a >= 0, "SeedCode.check_char: carácter no alfanumérico")
		var s: int = (p + a) % M
		if s == 0:
			s = M
		p = (s * 2) % (M + 1)
	return _ALNUM[(M + 1 - p) % M]


## true si `s` es un código de sistema aceptable (3-4 caracteres 0-9A-Z).
static func is_system_code(s: String) -> bool:
	return s.length() >= 3 and s.length() <= 4 and _is_alnum(s)


func _body(params_text: String) -> String:
	return "-".join(PackedStringArray([
		FORMAT_VERSION,
		system,
		scale,
		"G%d" % gen_version,
		params_text,
		Base32Crockford.encode_u64(seed_value),
	]))


func _validate_header() -> String:
	if not is_system_code(system):
		return ERR_SYSTEM
	if not SCALES.has(scale):
		return ERR_SCALE
	if gen_version < 1:
		return ERR_GEN
	return ""


static func _is_alnum(s: String) -> bool:
	for c: String in s:
		if _ALNUM.find(c) < 0:
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
