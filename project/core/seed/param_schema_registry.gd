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
	problem = _add(est_g1())
	assert(problem.is_empty(), "ParamSchemaRegistry: EST G1 no válido: " + problem)
	problem = _add(edi_g1())
	assert(problem.is_empty(), "ParamSchemaRegistry: EDI G1 no válido: " + problem)
	problem = _add(ald_g1())
	assert(problem.is_empty(), "ParamSchemaRegistry: ALD G1 no válido: " + problem)
	problem = _add(est_g2())
	assert(problem.is_empty(), "ParamSchemaRegistry: EST G2 no válido: " + problem)


## MAZ G1 — PROPUESTA DEFINITIVA, PENDIENTE DE APROBAR (F1, etapa 2). Se
## congela al grabar la primera seed dorada de MAZ; a partir de ahí, solo se
## pueden añadir campos AL FINAL con su defecto o ids dentro de `capacity`.
## Orden de más a menos usado: los campos del final casi nunca se tocan y,
## al valer su defecto, no ocupan caracteres. Los cuatro primeros no cambian
## respecto al esquema provisional de F0 (el ejemplo FA8 sigue valiendo).
## Significado (detalle en MazGeneratorG1 y PROYECTO §6.6):
## - rooms: salas por nivel (máximo; si no caben, las que quepan).
## - grid: rejilla táctica (ADR 012). Va en el código porque cambia la
##   geometría de muros y salas, no solo la vista.
## - corridor_pct: pasillos extra (bucles) sobre el árbol mínimo que une las
##   salas, en % de (salas - 1).
## - size: tamaño del mapa; "auto" lo deduce de rooms.
## - exits: salidas al exterior en el nivel 0 (la primera es la entrada).
## - densidades de trampas y puertas secretas: por cada 10 salas del nivel.
## - style: estilo cultural (ADR 015), capacity 16 para añadir estilos.
## wfc_tiles se quita: cuando exista, se añadirá AL FINAL (booleano, defecto
## false) sin cambiar ningún código emitido.
static func maz_g1() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.int_field("rooms", 1, 64, 12),
		ParamSchema.enum_field("layout", PackedStringArray(["built", "cave", "mixed"]), "built", 4),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.int_field("corridor_pct", 0, 100, 30),
		ParamSchema.enum_field("size", PackedStringArray(["auto", "small", "medium", "large", "huge"]), "auto", 8),
		ParamSchema.int_field("exits", 1, 4, 1),
		ParamSchema.int_field("levels", 1, 8, 1),
		ParamSchema.int_field("trap_density", 0, 10, 3),
		ParamSchema.int_field("secret_door_density", 0, 10, 2),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarf", "elf"]), "human", 16),
	]
	return ParamSchema.new("MAZ", 1, fields)


## EST G1 — PROPUESTA, PENDIENTE DE APROBAR (F1, etapa 3). Se congela al
## grabar la primera seed dorada de EST. Detalle en EstGeneratorG1 y §6.5.
## - room_type: tipo de estancia (data/rooms/est_room_types.json; los ids
##   deben coincidir); capacity 32 para añadir tipos sin cambiar códigos.
## - size: interior small 6×5, medium 9×7, large 13×10; auto = el del tipo.
## - style: ADR 015, materiales y pesos del mobiliario (data/styles).
## - shape: rectángulo o L (esquina recortada de w/2 × h/2).
## - doors: puertas (las que quepan sin juntarse; al menos una).
## - clutter: objetos opcionales ≈ casillas × clutter / 40.
## F3 (EDI G1) añade AL FINAL de room_type, dentro de capacity, los tipos que
## necesitan los edificios (hall … guardroom): ningún código emitido cambia.
static func est_g1() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("room_type", PackedStringArray(["tavern", "bedroom", "storage", "temple", "library", "kitchen", "forge", "crypt",
			"hall", "living", "shop", "barracks", "armory", "cell", "guardroom"]), "tavern", 32),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.enum_field("size", PackedStringArray(["auto", "small", "medium", "large"]), "auto", 8),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarf", "elf"]), "human", 16),
		ParamSchema.enum_field("shape", PackedStringArray(["rect", "l_shape"]), "rect", 4),
		ParamSchema.int_field("doors", 1, 4, 1),
		ParamSchema.int_field("clutter", 0, 10, 5),
	]
	return ParamSchema.new("EST", 1, fields)


## EDI G1 — PROPUESTA, PENDIENTE DE APROBAR (F3, etapa 1). Se congela al
## grabar la primera seed dorada de EDI. Detalle en EdiGeneratorG1 y §6.4.
## Orden de más a menos usado (los del final casi siempre valen su defecto y
## no ocupan caracteres):
## - building_type: tipo de edificio (data/buildings/edi_building_types.json;
##   los ids deben coincidir); capacity 32 para añadir tipos.
## - grid: rejilla (ADR 012).
## - style: ADR 015 (mismos ids que EST y MAZ).
## - floors: plantas sobre el suelo; 0 = las del tipo (taberna 2, casa 1…).
## - cellar: sótano bajo la planta baja.
## - size: huella del edificio; auto = la del tipo.
## - clutter: como en EST (se pasa a cada estancia).
static func edi_g1() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("building_type", PackedStringArray(["tavern", "house", "smithy", "temple", "shop", "inn", "guardhouse"]), "tavern", 32),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarf", "elf"]), "human", 16),
		ParamSchema.int_field("floors", 0, 4, 0),
		ParamSchema.bool_field("cellar", false),
		ParamSchema.enum_field("size", PackedStringArray(["auto", "small", "medium", "large"]), "auto", 8),
		ParamSchema.int_field("clutter", 0, 10, 5),
	]
	return ParamSchema.new("EDI", 1, fields)


## ALD G1 — PROPUESTA, PENDIENTE DE APROBAR (F3). Se congela al grabar la
## primera seed dorada de ALD. Detalle en AldGeneratorG1, PROYECTO §6.3 y
## ADR 027. Orden de más a menos usado:
## - size: caserío, aldea, pueblo, ciudad (data/settlements: mapa, nº de
##   edificios, calles, plaza…); capacity 8. La población se deriva de los
##   edificios (no es un parámetro en G1).
## - grid: rejilla (ADR 012); la de los edificios hijos.
## - style: ADR 015 (mismos ids que EST, EDI y MAZ); el de los edificios hijos.
## - wall: muralla con puertas donde la cruzan las calles principales.
## - water: ninguna, río (con puente) o costa; capacity 8.
## - prosperity: pobre, media, rica (pesos de tipos, tamaño EDI, sótanos y
##   clutter de los hijos); capacity 8.
## - layout: calles orgánicas o retícula (ciudad planificada); capacity 4.
static func ald_g1() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("size", PackedStringArray(["hamlet", "village", "town", "city"]), "village", 8),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarf", "elf"]), "human", 16),
		ParamSchema.bool_field("wall", false),
		ParamSchema.enum_field("water", PackedStringArray(["none", "river", "coast"]), "none", 8),
		ParamSchema.enum_field("prosperity", PackedStringArray(["poor", "average", "rich"]), "average", 8),
		ParamSchema.enum_field("layout", PackedStringArray(["organic", "grid"]), "organic", 4),
	]
	return ParamSchema.new("ALD", 1, fields)


## EST G2 — PROPUESTA, PENDIENTE DE APROBAR (F3, ADR 029): código de ESTANCIA
## DE UN EDIFICIO. No sustituye a EST G1 (estancia aislada, que sigue igual):
## es otro generador de la misma escala. SEED = la semilla del edificio.
## - Campos 0-6: los de EDI G1, en el mismo orden, con los mismos rangos, ids,
##   capacity y defectos (copiados aquí, no leídos de edi_g1(): si EDI G1
##   añadiera un campo al final, este esquema no debe cambiar en medio; el
##   test test_est_g2 comprueba que coinciden). Con ellos y SEED, el código
##   EDI G1 del edificio es el mismo PARAMS sin los dos últimos campos.
## - level: índice del nivel en el documento EDI (0 = sótano si lo hay; si no,
##   planta baja). Rango 0-7 (EDI G1 tiene como mucho 5 niveles).
## - room: orden de la estancia en la lista de su planta (el de room_seed:
##   id = level × 256 + room). Rango 0-63.
## Un nivel o estancia que el edificio no tiene da SEED_ERR_ROOM_LEVEL o
## SEED_ERR_ROOM al generar (el esquema no conoce el edificio).
static func est_g2() -> ParamSchema:
	var fields: Array[ParamSchema.Field] = [
		ParamSchema.enum_field("building_type", PackedStringArray(["tavern", "house", "smithy", "temple", "shop", "inn", "guardhouse"]), "tavern", 32),
		ParamSchema.enum_field("grid", PackedStringArray(["square", "hex_flat", "hex_pointy"]), "square", 4),
		ParamSchema.enum_field("style", PackedStringArray(["human", "dwarf", "elf"]), "human", 16),
		ParamSchema.int_field("floors", 0, 4, 0),
		ParamSchema.bool_field("cellar", false),
		ParamSchema.enum_field("size", PackedStringArray(["auto", "small", "medium", "large"]), "auto", 8),
		ParamSchema.int_field("clutter", 0, 10, 5),
		ParamSchema.int_field("level", 0, 7, 0),
		ParamSchema.int_field("room", 0, 63, 0),
	]
	return ParamSchema.new("EST", 2, fields)
