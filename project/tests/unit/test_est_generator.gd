extends GutTest
## Tests de EST G1 (core/gen/est) y de sus datos (catálogo, tipos de estancia,
## estilos): con muchas semillas y en las tres rejillas comprueba
## determinismo, puertas y conectividad, pasillo libre, interactuables
## alcanzables, objetos dentro de la estancia y sin solaparse, y etiquetas
## against_wall / center / near:<id>.
##
## Imprime las seeds doradas PROPUESTAS de EST entre
## EST_GOLDEN_PROPOSALS_BEGIN y EST_GOLDEN_PROPOSALS_END (esquema pendiente de
## aprobar; no se graban).

const ROOM_TYPES: PackedStringArray = ["tavern", "bedroom", "storage", "temple", "library", "kitchen", "forge", "crypt"]


func after_each() -> void:
	GeneratorRegistry.reset()


func _code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	var sc: SeedCode = SeedCode.create(system, "EST", 1, params, seed_value)
	assert_true(sc.is_valid(), "%s %s" % [sc.error, sc.error_field])
	return sc.encode()


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "", code)
	return res.doc


# --- Datos ------------------------------------------------------------------------

func test_catalog_and_data_are_valid() -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	assert_eq(cat.error, "")
	assert_true(cat.ids.size() >= 25, "objetos: %d" % cat.ids.size())
	# Se consulta la traducción compilada (el CSV fuente no viaja en las exportaciones).
	var es: Translation = load("res://i18n/strings.es.translation")
	for id: String in cat.ids:
		assert_ne(String(es.get_message("OBJ_%s" % id.to_upper())), "", id)
	var data: EstData = EstData.load_default()
	assert_eq(data.error, "")
	var schema: ParamSchema = ParamSchemaRegistry.get_schema("EST", 1)
	assert_not_null(schema)
	if schema == null:
		return
	# Los enumerados del esquema y los datos deben coincidir.
	var types: PackedStringArray = data.room_type_ids.duplicate()
	types.sort()
	var schema_types: PackedStringArray = schema.fields[0].ids.duplicate()
	schema_types.sort()
	assert_eq(types, schema_types)
	var styles: PackedStringArray = data.style_ids.duplicate()
	styles.sort()
	var schema_styles: PackedStringArray = schema.fields[3].ids.duplicate()
	schema_styles.sort()
	assert_eq(styles, schema_styles)
	for t: String in ROOM_TYPES:
		assert_ne(String(es.get_message("ROOM_KIND_%s" % t.to_upper())), "", t)
	for s: String in data.style_ids:
		assert_ne(String(es.get_message(data.style(s).name_key)), "", s)
	assert_true(GeneratorRegistry.has_generator("EST", 1))


func test_catalog_entry_properties() -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var chest: ObjectCatalog.Entry = cat.entry("chest")
	assert_not_null(chest)
	if chest == null:
		return
	assert_eq(chest.interaction, "chest")
	assert_eq(chest.near_id(), "bed")
	assert_eq(chest.cover, MapObject.COVER_HALF)
	var brazier: ObjectCatalog.Entry = cat.entry("brazier")
	assert_eq(brazier.light_bright_cells, 3)
	assert_true(brazier.has_tag(ObjectCatalog.TAG_CENTER))
	var o: MapObject = cat.instantiate(chest, 9, Vector2i(2, 3), 1, "oak")
	assert_eq(o.catalog_id, "chest")
	assert_eq(o.material, "oak")
	assert_true(o.blocks_movement)
	assert_null(cat.entry("no_existe"))


# --- Comprobación de una estancia ----------------------------------------------------

## Problemas de una estancia generada (vacío = correcta).
func _problems(doc: MapDocument, room_type: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	if doc.level_count() != 1:
		out.append("niveles: %d" % doc.level_count())
		return out
	var level: MapLevel = doc.level(0)
	var grid: GridGeometry = doc.grid
	var room_id: int = 0
	var entrance: Vector2i = Vector2i(-1, -1)
	var landings: int = 0
	for r: MapRoom in level.rooms:
		if r.kind == room_type:
			if room_id != 0:
				out.append("dos zonas de estancia")
			room_id = r.id
		elif r.kind == MapRoom.KIND_ENTRANCE or r.kind == MapRoom.KIND_EXIT:
			landings += 1
			var lc: Array[Vector2i] = level.room_cells(r.id)
			if lc.size() != 1:
				out.append("rellano %d con %d casillas" % [r.id, lc.size()])
			elif r.kind == MapRoom.KIND_ENTRANCE:
				entrance = lc[0]
		else:
			out.append("zona inesperada: " + r.kind)
	if room_id == 0 or entrance.x < 0:
		out.append("falta la estancia o la entrada")
		return out
	var in_room: PackedByteArray = PackedByteArray()
	in_room.resize(grid.cell_count())
	in_room.fill(0)
	for i: int in grid.cell_count():
		if level.room_ids[i] == room_id:
			in_room[i] = 1
	# Puertas: una por rellano; su casilla interior es una entrada.
	var entries: Array[Vector2i] = []
	for id: int in level.edge_ids():
		if MapEdge.kind_of(level.get_edge_by_id(id)) != MapEdge.KIND_DOOR:
			continue
		for c: Vector2i in grid.edge_cells(id):
			if grid.in_bounds(c) and in_room[grid.index_of(c)] == 1:
				entries.append(c)
	if entries.size() != landings or entries.is_empty():
		out.append("puertas %d, rellanos %d" % [entries.size(), landings])
	if Connectivity.unreachable_count(doc, 0, entrance) != 0:
		out.append("casillas inaccesibles desde la entrada")
	# Objetos.
	var occupied: PackedByteArray = PackedByteArray()
	occupied.resize(grid.cell_count())
	occupied.fill(0)
	var blocked: PackedByteArray = occupied.duplicate()
	for o: MapObject in level.objects:
		var e: ObjectCatalog.Entry = cat.entry(o.catalog_id)
		if e == null:
			out.append("objeto fuera del catálogo: " + o.catalog_id)
			continue
		if o.cover != e.cover or o.blocks_movement != e.blocks_movement or o.interaction != e.interaction:
			out.append("%s: propiedades distintas del catálogo" % o.catalog_id)
		var cells: Array[Vector2i] = level.object_cells(o)
		if cells.size() != o.size.x * o.size.y:
			out.append("%s: fuera del mapa" % o.catalog_id)
		for c: Vector2i in cells:
			var i: int = grid.index_of(c)
			if in_room[i] == 0 or level.terrain[i] != Terrain.FLOOR:
				out.append("%s en %s: fuera de la estancia o sobre muro" % [o.catalog_id, c])
			if occupied[i] != 0:
				out.append("%s en %s: solapa otro objeto" % [o.catalog_id, c])
			if entries.has(c):
				out.append("%s en %s: tapa una puerta" % [o.catalog_id, c])
			occupied[i] = 1
			if o.blocks_movement:
				blocked[i] = 1
		out.append_array(_tag_problems(level, o, e, cells, in_room))
	# Pasillo libre: casillas libres conectadas desde la primera entrada.
	var reached: PackedByteArray = _flood_free(level, in_room, blocked, entries[0] if not entries.is_empty() else entrance)
	for i: int in grid.cell_count():
		if in_room[i] == 1 and blocked[i] == 0 and reached[i] == 0:
			out.append("casilla libre aislada en %s" % grid.cell_at(i))
	for o2: MapObject in level.objects:
		if o2.interaction.is_empty():
			continue
		var ok: bool = false
		for c: Vector2i in level.object_cells(o2):
			if reached[grid.index_of(c)] != 0:
				ok = true
			for n: Vector2i in grid.neighbors(c):
				if reached[grid.index_of(n)] != 0:
					ok = true
		if not ok:
			out.append("interactuable inalcanzable: %s" % o2.catalog_id)
	return out


func _tag_problems(level: MapLevel, o: MapObject, e: ObjectCatalog.Entry, cells: Array[Vector2i], in_room: PackedByteArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var grid: GridGeometry = level.grid
	if e.has_tag(ObjectCatalog.TAG_AGAINST_WALL):
		var back: int = grid.opposite(o.facing)
		var ok: bool = false
		for c: Vector2i in cells:
			var ni: int = grid.index_of(grid.neighbor(c, back))
			if ni < 0 or in_room[ni] == 0:
				ok = true
		if not ok:
			out.append("%s no está contra la pared" % o.catalog_id)
	if e.has_tag(ObjectCatalog.TAG_CENTER):
		for c: Vector2i in cells:
			for n: Vector2i in grid.neighbors(c, true):
				if grid.direction_between(c, n) >= grid.edge_direction_count():
					continue
				var ni: int = grid.index_of(n)
				if ni < 0 or in_room[ni] == 0:
					out.append("%s no está en el centro" % o.catalog_id)
	var near: String = e.near_id()
	if not near.is_empty():
		var ok2: bool = false
		for other: MapObject in level.objects:
			if other.catalog_id != near:
				continue
			for c: Vector2i in cells:
				for oc: Vector2i in level.object_cells(other):
					if grid.distance(c, oc) <= 1:
						ok2 = true
		if not ok2:
			out.append("%s no está junto a %s" % [o.catalog_id, near])
	return out


func _flood_free(level: MapLevel, in_room: PackedByteArray, blocked: PackedByteArray, start: Vector2i) -> PackedByteArray:
	var grid: GridGeometry = level.grid
	var reached: PackedByteArray = PackedByteArray()
	reached.resize(grid.cell_count())
	reached.fill(0)
	var si: int = grid.index_of(start)
	if si < 0 or blocked[si] != 0:
		return reached
	reached[si] = 1
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(c, d)
			var ni: int = grid.index_of(n)
			if ni < 0 or reached[ni] != 0 or in_room[ni] == 0 or blocked[ni] != 0:
				continue
			if not MapEdge.is_traversable(level.get_edge(c, d)):
				continue
			reached[ni] = 1
			queue.append(n)
	return reached


func _check(params: Dictionary, seed_value: int, system: String = "DND5") -> MapDocument:
	var code: String = _code(params, seed_value, system)
	var doc: MapDocument = _gen(code)
	if doc == null:
		return null
	var sc: SeedCode = SeedCode.parse(code)
	var room_type: String = sc.params["room_type"]
	assert_eq(_problems(doc, room_type), PackedStringArray(), code)
	var again: MapDocument = _gen(code)
	assert_eq(again.content_hash(), doc.content_hash(), "determinismo: " + code)
	return doc


# --- Propiedades ----------------------------------------------------------------------

func test_all_room_types_all_grids() -> void:
	for kind: String in GridGeometry.KINDS:
		for t: String in ROOM_TYPES:
			for s: int in [1, 2]:
				var doc: MapDocument = _check({"room_type": t, "grid": kind}, s)
				if doc != null:
					assert_eq(doc.scale, "EST")
					assert_true(doc.level(0).objects.size() >= 1, "%s %s sin objetos" % [kind, t])


func test_shapes_doors_styles_and_clutter() -> void:
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		for style: String in ["human", "dwarf", "elf"]:
			i += 1
			_check({"grid": kind, "style": style, "shape": "l_shape", "doors": 4, "room_type": ROOM_TYPES[i % ROOM_TYPES.size()]}, 100 + i)
			_check({"grid": kind, "style": style, "size": "small", "clutter": 10, "room_type": ROOM_TYPES[(i + 3) % ROOM_TYPES.size()]}, 200 + i)


func test_required_objects_and_clutter_zero() -> void:
	var doc: MapDocument = _check({"room_type": "forge", "clutter": 0}, 11)
	if doc == null:
		return
	var ids: PackedStringArray = PackedStringArray()
	for o: MapObject in doc.level(0).objects:
		ids.append(o.catalog_id)
	assert_eq(ids, PackedStringArray(["forge_furnace", "anvil", "quench_trough"]))
	var many: MapDocument = _check({"room_type": "storage", "clutter": 10, "size": "large"}, 11)
	if many != null:
		assert_true(many.level(0).objects.size() > 5)


func test_style_sets_material() -> void:
	var dwarf: MapDocument = _check({"room_type": "bedroom", "style": "dwarf"}, 3)
	if dwarf == null:
		return
	for o: MapObject in dwarf.level(0).objects:
		if o.catalog_id == "bed":
			assert_eq(o.material, "granite")


func test_seed_changes_output() -> void:
	var a: MapDocument = _gen(_code({}, 1))
	var b: MapDocument = _gen(_code({}, 2))
	if a != null and b != null:
		assert_ne(a.content_hash(), b.content_hash())


## Criterio de F3 preparado: la estancia como hija de un edificio, con
## hash64(semilla_padre, "EST", id), da lo mismo que generada aislada con esa
## semilla.
func test_child_seed_and_isolated_match() -> void:
	var parent: int = 0x5EED
	var child_seed: int = SplitMix64.hash64(parent, "EST", 7)
	var code: String = _code({"room_type": "library"}, child_seed)
	var isolated: MapDocument = _gen(code)
	var p: EstGeneratorG1.Params = EstGeneratorG1.params_from(SeedCode.parse(code))
	var as_child: MapDocument = EstGeneratorG1.generate_room(p, Rng.new(SplitMix64.hash64(parent, "EST", 7)))
	if isolated == null or as_child == null:
		return
	assert_eq(CanonicalJson.stringify(as_child.level(0).content_to_dict()), CanonicalJson.stringify(isolated.level(0).content_to_dict()))


## API de amueblado para EDI: un recinto dado de un nivel cualquiera.
func test_furnish_api_on_given_area() -> void:
	for kind: String in GridGeometry.KINDS:
		var hashes: PackedStringArray = PackedStringArray()
		for run: int in 2:
			var doc: MapDocument = MapDocument.create(kind, 12, 10)
			var level: MapLevel = doc.level(0)
			var area: Array[Vector2i] = []
			for y: int in range(2, 8):
				for x: int in range(2, 10):
					area.append(Vector2i(x, y))
					level.set_terrain(Vector2i(x, y), Terrain.FLOOR)
			var entry: Array[Vector2i] = [Vector2i(2, 4)]
			var n: int = EstFurnisherG1.furnish(doc, 0, area, entry, "kitchen", "elf", 5, Rng.new(77))
			assert_true(n >= 2, "%s: %d objetos" % [kind, n])
			for o: MapObject in level.objects:
				for c: Vector2i in level.object_cells(o):
					assert_true(area.has(c), "%s fuera del recinto" % o.catalog_id)
					assert_ne(c, Vector2i(2, 4), "tapa la entrada")
			hashes.append(doc.content_hash())
		assert_eq(hashes[0], hashes[1])
	var none: Array[Vector2i] = []
	assert_eq(EstFurnisherG1.furnish(MapDocument.create("square", 4, 4), 0, none, none, "no_existe", "human", 5, Rng.new(1)), -1)


# --- Seeds doradas propuestas (pendientes de aprobar el esquema) -------------------

## [sistema, parámetros, semilla]: los 8 tipos, las tres rejillas, los tres
## estilos, las dos formas, varias puertas, tamaños y densidades.
static func proposals() -> Array:
	return [
		["DND5", {}, 0x8A1B2C3D4E],
		["DND5", {"room_type": "bedroom"}, 0x9B2C3D4E5F],
		["PF2E", {"room_type": "storage", "grid": "hex_flat"}, 0xAC3D4E5F60],
		["DND5", {"room_type": "temple", "grid": "hex_pointy", "style": "elf"}, 0xBD4E5F6071],
		["DND5", {"room_type": "library", "shape": "l_shape", "doors": 2}, 0xCE5F607182],
		["PF2E", {"room_type": "kitchen", "grid": "hex_flat", "size": "large", "clutter": 8}, 0xDF60718293],
		["DND5", {"room_type": "forge", "style": "dwarf", "doors": 3}, 0xE0718293A4],
		["PF2E", {"room_type": "crypt", "grid": "hex_pointy", "shape": "l_shape", "clutter": 2}, 0xF18293A4B5],
		["DND5", {"grid": "hex_flat", "style": "dwarf", "size": "medium", "doors": 4}, 7],
	]


func test_proposed_golden_seeds() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for item: Variant in proposals():
		var entry: Array = item
		var system: String = entry[0]
		var params: Dictionary = entry[1]
		var seed_value: int = entry[2]
		var doc: MapDocument = _check(params, seed_value, system)
		if doc != null:
			lines.append("%s %s" % [doc.seed_code, doc.content_hash()])
	assert_eq(lines.size(), proposals().size())
	print("EST_GOLDEN_PROPOSALS_BEGIN\n%s\nEST_GOLDEN_PROPOSALS_END" % "\n".join(lines))


## ASCII para revisión: '#' muro, '.' suelo, '+' rellano, letra = objeto
## (inicial del id; mayúscula si bloquea el paso).
static func ascii(doc: MapDocument) -> String:
	var level: MapLevel = doc.level(0)
	var grid: GridGeometry = doc.grid
	var rows: PackedStringArray = PackedStringArray()
	for y: int in grid.height:
		var row: String = " " if grid.kind == GridGeometry.KIND_HEX_POINTY and y % 2 == 1 else ""
		for x: int in grid.width:
			var c: Vector2i = Vector2i(x, y)
			var ch: String = "#"
			if Terrain.is_passable(level.get_terrain(c)):
				ch = "."
				var rid: int = level.get_room_id(c)
				if rid != 0 and level.room(rid).kind in [MapRoom.KIND_ENTRANCE, MapRoom.KIND_EXIT]:
					ch = "+"
			var objs: Array[MapObject] = level.objects_at(c)
			if not objs.is_empty():
				ch = objs[0].catalog_id.substr(0, 1)
				if objs[0].blocks_movement:
					ch = ch.to_upper()
			row += ch + (" " if grid.kind == GridGeometry.KIND_HEX_POINTY else "")
		rows.append(row)
	return "\n".join(rows)


func test_print_ascii_samples() -> void:
	for kind: String in GridGeometry.KINDS:
		var code: String = _code({"grid": kind, "room_type": "tavern"}, 1)
		var doc: MapDocument = _gen(code)
		if doc != null:
			print("%s\n%s\n" % [code, ascii(doc)])
	pass_test("ASCII impreso")
