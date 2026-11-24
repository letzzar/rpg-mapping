class_name ParamSchemaRegistry
extends RefCounted
## Registro de esquemas de parámetros por (escala, GEN) que usa SeedCode.
##
## Cada generador registrará aquí el esquema de cada GEN que sepa ejecutar
## (también los de legacy/), para que los códigos antiguos se sigan leyendo.
## Mientras no existan generadores (F1), los tests registran esquemas de prueba
## con register() y restauran el estado con reset().
##
## Los esquemas incorporados se cargan de forma perezosa y en un orden fijo
## (determinista); el diccionario solo se consulta por clave, nunca se itera.

static var _schemas: Dictionary = {}
static var _loaded: bool = false


## Esquema de (escala, GEN), o null si esta versión de la app no lo conoce.
static func get_schema(scale: String, gen: int) -> ParamSchema:
	_ensure_builtins()
	var k: String = _key(scale, gen)
	if not _schemas.has(k):
		return null
	var s: ParamSchema = _schemas[k]
	return s


static func has_schema(scale: String, gen: int) -> bool:
	return get_schema(scale, gen) != null


## Registra un esquema. Devuelve "" si se registró o un mensaje técnico si el
## esquema no es válido o ya hay uno para ese (escala, GEN).
static func register(schema: ParamSchema) -> String:
	_ensure_builtins()
	return _add(schema)


static func unregister(scale: String, gen: int) -> void:
	_ensure_builtins()
	_schemas.erase(_key(scale, gen))


## Deja solo los esquemas incorporados (para after_each de los tests).
static func reset() -> void:
	_schemas.clear()
	_loaded = false
	_ensure_builtins()


static func _add(schema: ParamSchema) -> String:
	var problem: String = schema.validate()
	if not problem.is_empty():
		return problem
	if not SeedCode.SCALES.has(schema.scale):
		return "escala '%s' desconocida" % schema.scale
	var k: String = _key(schema.scale, schema.gen)
	if _schemas.has(k):
		return "ya hay un esquema para %s" % k
	_schemas[k] = schema
	return ""


static func _key(scale: String, gen: int) -> String:
	return "%s-G%d" % [scale, gen]


static func _ensure_builtins() -> void:
	if _loaded:
		return
	_loaded = true
	var problem: String = _add(maz_g1())
	assert(problem.is_empty(), "ParamSchemaRegistry: MAZ G1 no válido: " + problem)


## MAZ G1 — PROVISIONAL. Se puede cambiar libremente hasta que exista la
## primera seed dorada de MAZ (F1); a partir de ahí queda congelado.
## Orden de más a menos usado: los campos del final casi nunca se tocan y,
## al valer su defecto, no ocupan caracteres.
## - grid: rejilla táctica cuadrada o hexagonal (ADR 012). Va en el código
##   porque cambia la geometría de muros y salas, no solo la vista.
## - densidades de trampas y puertas secretas: por cada 10 salas.
## Sin estilo cultural: ADR 015 lo prevé para ALD, EDI y EST (allí será un
## enumerado con `capacity` holgada para añadir estilos sin cambiar códigos).
static func maz_g1() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.int_field("rooms", 1, 64, 12),
		ParamSchema.enum_field("layout", PackedStringArray(["built", "cave", "mixed"]), "built", 4),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.int_field("corridor_pct", 0, 100, 30),
		ParamSchema.int_field("exits", 1, 4, 1),
		ParamSchema.int_field("trap_density", 0, 10, 3),
		ParamSchema.int_field("secret_door_density", 0, 10, 2),
		ParamSchema.int_field("levels", 1, 8, 1),
		ParamSchema.bool_field("wfc_tiles", false),
	]
	return ParamSchema.new("MAZ", 1, fields)
