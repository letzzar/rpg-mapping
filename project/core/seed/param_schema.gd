class_name ParamSchema
extends RefCounted
## Esquema posicional de los parámetros de un generador (escala + GEN) para el
## campo PARAMS del código de semilla RPGM1 (PROYECTO.md §5.3, ADR 009).
##
## Cada generador declara una lista ORDENADA de campos: entero en [min, max],
## booleano o enumerado (lista cerrada de ids), cada uno con su valor por
## defecto. El esquema queda congelado con su GEN: cambiar el orden, un rango,
## un valor por defecto o un id existente cambia los códigos, así que obliga a
## subir GEN y conservar el esquema anterior (CLAUDE.md §2).
##
## Codificación (todo en enteros, sin floats ni diccionarios sin ordenar):
## 1. Cada valor pasa a un dígito 0..radix-1 RELATIVO a su valor por defecto:
##    dígito = (valor - defecto) mod radix. El valor por defecto siempre es 0.
##    radix: entero = max - min + 1; booleano = 2; enumerado = capacity.
## 2. Los dígitos forman un entero de base mixta con el PRIMER campo como
##    dígito menos significativo:  N = d0 + r0·(d1 + r1·(d2 + …)).
## 3. N se escribe en Base32 Crockford sin ceros a la izquierda ("0" si N = 0).
##
## Por qué se omiten los valores por defecto del final: con (1) y (2), los
## campos del final que valen su defecto son ceros a la izquierda de N y
## desaparecen solos, sin marcas de presencia ni longitudes (que costarían
## caracteres). Todo por defecto = "0". Consecuencias:
## - Conviene ordenar los campos de más a menos usados en la mesa.
## - Añadir un campo nuevo AL FINAL con defecto no cambia ningún código ya
##   emitido (sí cambia el generador, así que sigue requiriendo GEN nuevo si
##   altera la salida de códigos existentes).
## - Cada conjunto de valores tiene un único texto (se rechazan ceros a la
##   izquierda): el control y las seeds doradas no dependen de cómo se teclee.
##
## N puede pasar de 64 bits (p. ej. cinco enteros de 31 bits), así que se
## opera "por trozos": un natural en dígitos base 32 (los mismos del texto)
## que solo se multiplica y divide por radix <= 2^31. Coste O(F·L), con F
## campos y L caracteres del texto (L ≈ Σ log32(radix)); despreciable.
##
## Enumerados con `capacity` mayor que el nº de ids: reservan dígitos para
## añadir ids al final (p. ej. un estilo cultural nuevo, ADR 015) sin cambiar
## la radix ni, por tanto, los códigos existentes. Un dígito reservado que aún
## no tiene id se rechaza como enumerado desconocido (SEED_ERR_PARAM_ENUM).

const KIND_INT: int = 0
const KIND_BOOL: int = 1
const KIND_ENUM: int = 2

## Radix máxima de un campo: mantiene en int64 los productos del natural base 32.
const MAX_RADIX: int = 1 << 31
## Límite de |min| y |max| de un entero (evita desbordes en valor - defecto).
const MAX_ABS_VALUE: int = 1 << 62
## Caracteres máximos de PARAMS que se aceptan al analizar (texto pegado).
const MAX_TEXT_LEN: int = 64
const EMPTY_TEXT: String = "0"
const _IDENT_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_"

## Claves de i18n de error (las reexporta SeedCode).
const ERR_PARAMS: String = "SEED_ERR_PARAMS"
const ERR_PARAM_UNKNOWN: String = "SEED_ERR_PARAM_UNKNOWN"
const ERR_PARAM_TYPE: String = "SEED_ERR_PARAM_TYPE"
const ERR_PARAM_RANGE: String = "SEED_ERR_PARAM_RANGE"
const ERR_PARAM_ENUM: String = "SEED_ERR_PARAM_ENUM"


## Un campo del esquema. Créalo con int_field(), bool_field() o enum_field().
class Field:
	var kind: int = 0
	var key: String = ""
	## Solo enteros.
	var min_value: int = 0
	var max_value: int = 0
	## Representación interna del defecto: entero = el valor; booleano = 0/1;
	## enumerado = índice en `ids` (-1 si el id por defecto no existe).
	var default_value: int = 0
	## Solo enumerados.
	var ids: PackedStringArray = PackedStringArray()
	var capacity: int = 0


## Resultado de resolve() y decode().
class Resolved:
	## Clave i18n del error; "" si es válido.
	var error: String = ""
	## Clave del parámetro que provocó el error ("" si no aplica).
	var field: String = ""
	## Todos los campos del esquema, en su orden: int, bool o String (id).
	var values: Dictionary = {}
	## Texto PARAMS canónico.
	var text: String = ""

	func fail(p_error: String, p_field: String) -> Resolved:
		error = p_error
		field = p_field
		values = {}
		text = ""
		return self


## Natural de precisión arbitraria en dígitos base 32, poco significativo
## primero y sin ceros sobrantes (vacío = 0).
class Nat:
	var limbs: Array[int] = []

	## self = self * m + a, con 1 <= m <= MAX_RADIX y 0 <= a < m.
	func mul_add(m: int, a: int) -> void:
		var carry: int = a
		for i: int in limbs.size():
			var t: int = limbs[i] * m + carry
			limbs[i] = t & 31
			carry = t >> 5
		while carry > 0:
			limbs.append(carry & 31)
			carry >>= 5

	## self = self div m; devuelve self mod m (1 <= m <= MAX_RADIX).
	func divmod(m: int) -> int:
		var rem: int = 0
		for i: int in range(limbs.size() - 1, -1, -1):
			var cur: int = (rem << 5) | limbs[i]
			limbs[i] = cur / m
			rem = cur % m
		while not limbs.is_empty() and limbs[limbs.size() - 1] == 0:
			limbs.pop_back()
		return rem

	func is_zero() -> bool:
		return limbs.is_empty()


var scale: String = ""
var gen: int = 0
var fields: Array[Field] = []


func _init(p_scale: String = "", p_gen: int = 0, p_fields: Array[Field] = []) -> void:
	scale = p_scale
	gen = p_gen
	fields.assign(p_fields)


static func int_field(p_key: String, p_min: int, p_max: int, p_default: int) -> Field:
	var f: Field = Field.new()
	f.kind = KIND_INT
	f.key = p_key
	f.min_value = p_min
	f.max_value = p_max
	f.default_value = p_default
	return f


static func bool_field(p_key: String, p_default: bool) -> Field:
	var f: Field = Field.new()
	f.kind = KIND_BOOL
	f.key = p_key
	f.default_value = 1 if p_default else 0
	return f


## `p_capacity` = 0 equivale a ids.size() (sin hueco reservado).
static func enum_field(p_key: String, p_ids: PackedStringArray, p_default: String, p_capacity: int = 0) -> Field:
	var f: Field = Field.new()
	f.kind = KIND_ENUM
	f.key = p_key
	f.ids = p_ids.duplicate()
	f.default_value = p_ids.find(p_default)
	f.capacity = p_capacity if p_capacity > 0 else p_ids.size()
	return f


static func radix_of(f: Field) -> int:
	match f.kind:
		KIND_INT:
			return f.max_value - f.min_value + 1
		KIND_BOOL:
			return 2
	return f.capacity


## Índice del campo `key`, o -1.
func find(key: String) -> int:
	for i: int in fields.size():
		if fields[i].key == key:
			return i
	return -1


func field_keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: Field in fields:
		out.append(f.key)
	return out


## Valores por defecto de todos los campos, en el orden del esquema.
func default_values() -> Dictionary:
	var out: Dictionary = {}
	for f: Field in fields:
		out[f.key] = _value_from_digit(f, 0)
	return out


## Mensaje técnico (para el log/tests, no para el usuario) si el esquema está
## mal declarado; "" si es válido.
func validate() -> String:
	if scale.length() != 3:
		return "escala '%s' no válida" % scale
	if gen < 1:
		return "GEN debe ser >= 1"
	var seen: Dictionary = {}
	for f: Field in fields:
		if f.key.is_empty() or not _is_ident(f.key):
			return "clave '%s' no válida ([a-z0-9_])" % f.key
		if seen.has(f.key):
			return "clave '%s' repetida" % f.key
		seen[f.key] = true
		match f.kind:
			KIND_INT:
				if absi(f.min_value) > MAX_ABS_VALUE or absi(f.max_value) > MAX_ABS_VALUE:
					return "%s: límites fuera de ±2^62" % f.key
				if f.min_value > f.max_value:
					return "%s: min > max" % f.key
				if f.max_value - f.min_value >= MAX_RADIX:
					return "%s: rango de más de 2^31 valores" % f.key
				if f.default_value < f.min_value or f.default_value > f.max_value:
					return "%s: defecto fuera de rango" % f.key
			KIND_BOOL:
				if f.default_value != 0 and f.default_value != 1:
					return "%s: defecto booleano no válido" % f.key
			KIND_ENUM:
				if f.ids.is_empty():
					return "%s: enumerado sin ids" % f.key
				var ids_seen: Dictionary = {}
				for id: String in f.ids:
					if id.is_empty() or not _is_ident(id):
						return "%s: id '%s' no válido" % [f.key, id]
					if ids_seen.has(id):
						return "%s: id '%s' repetido" % [f.key, id]
					ids_seen[id] = true
				if f.default_value < 0:
					return "%s: el defecto no está entre los ids" % f.key
				if f.capacity < f.ids.size() or f.capacity > MAX_RADIX:
					return "%s: capacity fuera de [nº de ids, 2^31]" % f.key
			_:
				return "%s: tipo de campo desconocido" % f.key
	# El código más largo posible (todos los dígitos al máximo) debe poder
	# analizarse; si no, el esquema tiene demasiados campos.
	var max_digits: PackedInt64Array = PackedInt64Array()
	for f: Field in fields:
		max_digits.append(radix_of(f) - 1)
	if _digits_to_text(max_digits).length() > MAX_TEXT_LEN:
		return "el esquema necesita más de %d caracteres" % MAX_TEXT_LEN
	return ""


## Valida y completa con los valores por defecto los parámetros dados por el
## usuario (los que falten toman su defecto) y calcula el texto PARAMS.
## Tipado estricto: entero = int (no float), booleano = bool, enumerado =
## String/StringName con un id de la lista.
func resolve(params: Dictionary) -> Resolved:
	var r: Resolved = Resolved.new()
	var by_key: Dictionary = {}
	var unknown: PackedStringArray = PackedStringArray()
	for k: Variant in params.keys():
		if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
			return r.fail(ERR_PARAM_UNKNOWN, "")
		var key: String = str(k)
		by_key[key] = params[k]
		if find(key) < 0:
			unknown.append(key)
	if not unknown.is_empty():
		# Ordenado para que el error notificado no dependa del orden del diccionario.
		unknown.sort()
		return r.fail(ERR_PARAM_UNKNOWN, unknown[0])
	var digits: PackedInt64Array = PackedInt64Array()
	for f: Field in fields:
		var digit: int = 0
		if by_key.has(f.key):
			var v: Variant = by_key[f.key]
			match f.kind:
				KIND_INT:
					if typeof(v) != TYPE_INT:
						return r.fail(ERR_PARAM_TYPE, f.key)
					var iv: int = v
					if iv < f.min_value or iv > f.max_value:
						return r.fail(ERR_PARAM_RANGE, f.key)
					digit = posmod(iv - f.default_value, radix_of(f))
				KIND_BOOL:
					if typeof(v) != TYPE_BOOL:
						return r.fail(ERR_PARAM_TYPE, f.key)
					var bv: bool = v
					digit = 0 if (1 if bv else 0) == f.default_value else 1
				KIND_ENUM:
					if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
						return r.fail(ERR_PARAM_TYPE, f.key)
					var idx: int = f.ids.find(str(v))
					if idx < 0:
						return r.fail(ERR_PARAM_ENUM, f.key)
					digit = posmod(idx - f.default_value, f.capacity)
		digits.append(digit)
		r.values[f.key] = _value_from_digit(f, digit)
	r.text = _digits_to_text(digits)
	return r


## Analiza un texto PARAMS (ya en mayúsculas o no; admite alias de Crockford).
## Rechaza caracteres no válidos, ceros a la izquierda y valores que no caben
## en el esquema (SEED_ERR_PARAMS) y huecos de enumerado sin id (SEED_ERR_PARAM_ENUM).
func decode(text: String) -> Resolved:
	var r: Resolved = Resolved.new()
	if text.is_empty() or text.length() > MAX_TEXT_LEN:
		return r.fail(ERR_PARAMS, "")
	var n: Nat = Nat.new()
	for i: int in range(text.length() - 1, -1, -1):
		var d: int = Base32Crockford.char_value(text[i])
		if d < 0:
			return r.fail(ERR_PARAMS, "")
		n.limbs.append(d)
	if text.length() > 1 and n.limbs[n.limbs.size() - 1] == 0:
		return r.fail(ERR_PARAMS, "")
	while not n.limbs.is_empty() and n.limbs[n.limbs.size() - 1] == 0:
		n.limbs.pop_back()
	var digits: PackedInt64Array = PackedInt64Array()
	for f: Field in fields:
		digits.append(n.divmod(radix_of(f)))
	if not n.is_zero():
		return r.fail(ERR_PARAMS, "")
	for i: int in fields.size():
		var f: Field = fields[i]
		if f.kind == KIND_ENUM and posmod(digits[i] + f.default_value, f.capacity) >= f.ids.size():
			return r.fail(ERR_PARAM_ENUM, f.key)
		r.values[f.key] = _value_from_digit(f, digits[i])
	r.text = _digits_to_text(digits)
	return r


static func _value_from_digit(f: Field, digit: int) -> Variant:
	match f.kind:
		KIND_INT:
			return f.min_value + posmod(digit + f.default_value - f.min_value, radix_of(f))
		KIND_BOOL:
			return (digit == 1) != (f.default_value == 1)
	return f.ids[posmod(digit + f.default_value, f.capacity)]


## Horner desde el último campo: el primero queda como dígito menos significativo.
func _digits_to_text(digits: PackedInt64Array) -> String:
	var n: Nat = Nat.new()
	for i: int in range(fields.size() - 1, -1, -1):
		n.mul_add(radix_of(fields[i]), digits[i])
	if n.is_zero():
		return EMPTY_TEXT
	var out: String = ""
	for i: int in range(n.limbs.size() - 1, -1, -1):
		out += Base32Crockford.ALPHABET[n.limbs[i]]
	return out


static func _is_ident(s: String) -> bool:
	for c: String in s:
		if _IDENT_CHARS.find(c) < 0:
			return false
	return true
