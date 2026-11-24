class_name GeneratorRegistry
extends RefCounted
## Punto único de entrada "código de semilla -> MapDocument" (lo usan la app y
## las seeds doradas). Cada generador registra aquí cada GEN que sabe
## ejecutar, también los de legacy/, igual que en ParamSchemaRegistry.
##
## Firma de un generador (función estática pura, CLAUDE.md §6):
##   func(code: SeedCode, profile: SystemProfile, rng: Rng) -> MapDocument
## `rng` es Rng.new(code.seed_value); los hijos se derivan con rng.fork().
## El registro sella la procedencia (seed_code, scale, gen_version) en el
## documento devuelto, así que el generador no tiene que hacerlo.
##
## F1 etapa 1: todavía no hay generadores incorporados (MAZ y EST llegan en las
## etapas 2 y 3). Los tests registran generadores de prueba y llaman a reset().

## Resultado de generate().
class Result:
	extends RefCounted
	var doc: MapDocument = null
	## Clave i18n SEED_ERR_* si el código no es válido, o mensaje técnico si
	## no hay perfil o generador; "" si se generó.
	var error: String = ""


static var _generators: Dictionary = {}
static var _loaded: bool = false


static func register(scale: String, gen: int, fn: Callable) -> String:
	_ensure_builtins()
	return _add(scale, gen, fn)


static func unregister(scale: String, gen: int) -> void:
	_ensure_builtins()
	_generators.erase(_key(scale, gen))


static func has_generator(scale: String, gen: int) -> bool:
	_ensure_builtins()
	return _generators.has(_key(scale, gen))


## Deja solo los generadores incorporados (after_each de los tests).
static func reset() -> void:
	_generators.clear()
	_loaded = false
	_ensure_builtins()


## Analiza el código, busca el perfil por su SIS y el generador por (ESC, GEN)
## y genera. Nunca lanza: mirar Result.error.
static func generate(code_text: String) -> Result:
	var res: Result = Result.new()
	var sc: SeedCode = SeedCode.parse(code_text)
	if not sc.is_valid():
		res.error = sc.error
		return res
	var profile: SystemProfile = SystemProfile.find_by_seed_code(sc.system)
	if profile == null:
		res.error = "no hay perfil de sistema con código %s" % sc.system
		return res
	_ensure_builtins()
	var k: String = _key(sc.scale, sc.gen_version)
	if not _generators.has(k):
		res.error = "no hay generador para %s" % k
		return res
	var fn: Callable = _generators[k]
	var doc: MapDocument = fn.call(sc, profile, Rng.new(sc.seed_value))
	if doc == null:
		res.error = "el generador %s no devolvió documento" % k
		return res
	doc.seed_code = sc.encode()
	doc.scale = sc.scale
	doc.gen_version = sc.gen_version
	res.doc = doc
	return res


static func _add(scale: String, gen: int, fn: Callable) -> String:
	if not SeedCode.SCALES.has(scale) or gen < 1:
		return "escala o GEN no válidos"
	if not fn.is_valid():
		return "función no válida"
	var k: String = _key(scale, gen)
	if _generators.has(k):
		return "ya hay un generador para %s" % k
	_generators[k] = fn
	return ""


static func _key(scale: String, gen: int) -> String:
	return "%s-G%d" % [scale, gen]


## Generadores incorporados, en orden fijo. Vacío hasta la etapa 2 de F1.
static func _ensure_builtins() -> void:
	if _loaded:
		return
	_loaded = true
