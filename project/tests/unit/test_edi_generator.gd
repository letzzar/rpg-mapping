extends GutTest
## Tests de EDI G1 (core/gen/edi) y de sus datos: con muchas semillas, los 7
## tipos, las tres rejillas y los tres estilos comprueba conectividad desde la
## entrada en todas las plantas, puertas (toda estancia tiene, no se juntan,
## nunca en escaleras), adyacencias obligatorias del tipo, escaleras
## coherentes entre plantas, ventanas solo en el muro exterior, mobiliario
## fuera de puertas y escaleras, y determinismo.
##
## Imprime las seeds doradas CANDIDATAS de EDI (solo códigos, sin hash: el
## esquema está pendiente de aprobar) entre EDI_GOLDEN_CANDIDATES_BEGIN/END,
## estadísticas (EDI_STATS) y ASCII de muestra.

const TYPES: PackedStringArray = ["tavern", "house", "smithy", "temple", "shop", "inn", "guardhouse"]
const STYLES: PackedStringArray = ["human", "dwarf", "elf"]

var _prev_locale: String = ""


## Los textos esperados están en español: se fija el idioma para no depender
## del del sistema (el CI de Linux arranca en inglés y fallaba siempre).
func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func after_each() -> void:
	GeneratorRegistry.reset()


func _code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	var sc: SeedCode = SeedCode.create(system, "EDI", 1, params, seed_value)
	assert_true(sc.is_valid(), "%s %s" % [sc.error, sc.error_field])
	return sc.encode()


func _build(code: String) -> EdiGeneratorG1.Result:
	var sc: SeedCode = SeedCode.parse(code)
	assert_true(sc.is_valid(), code)
	return EdiGeneratorG1.generate_building(EdiGeneratorG1.params_from(sc), Rng.new(sc.seed_value))


# --- Datos y registro -------------------------------------------------------------

func test_data_schema_and_registry() -> void:
	var data: EdiData = EdiData.load_default()
	assert_eq(data.error, "")
	var schema: ParamSchema = ParamSchemaRegistry.get_schema("EDI", 1)
	assert_not_null(schema)
	if schema == null:
		return
	assert_eq(schema.field_keys(), PackedStringArray(["building_type", "grid", "style", "floors", "cellar", "size", "clutter"]))
	var types: PackedStringArray = data.building_type_ids.duplicate()
	types.sort()
	var schema_types: PackedStringArray = schema.fields[0].ids.duplicate()
	schema_types.sort()
	assert_eq(types, schema_types)
	# Mismos estilos que EST (y MAZ).
	assert_eq(schema.fields[2].ids, ParamSchemaRegistry.get_schema("EST", 1).fields[3].ids)
	for s: String in STYLES:
		assert_not_null(data.style_building(s), s)
	assert_true(GeneratorRegistry.has_generator("EDI", 1))
	# Textos: tipos de edificio, todos los tipos de estancia EST, exterior y escala.
	var es: Translation = load("res://i18n/strings.es.translation")
	for t: String in data.building_type_ids:
		assert_ne(String(es.get_message("BUILDING_%s" % t.to_upper())), "", t)
	for rt: String in EstData.load_default().room_type_ids:
		assert_ne(String(es.get_message("ROOM_KIND_%s" % rt.to_upper())), "", rt)
	for k: String in ["ROOM_KIND_OUTSIDE", "UI_SCALE_EDI"]:
		assert_ne(String(es.get_message(k)), "", k)
	# Los tipos nuevos de EST van al final del enumerado, dentro de capacity.
	var est_ids: PackedStringArray = ParamSchemaRegistry.get_schema("EST", 1).fields[0].ids
	assert_eq(est_ids.slice(0, 8), PackedStringArray(["tavern", "bedroom", "storage", "temple", "library", "kitchen", "forge", "crypt"]))
	assert_true(est_ids.size() <= 32)


func test_code_round_trip_and_registry_generates() -> void:
	var code: String = _code({"building_type": "inn", "grid": "hex_flat", "style": "elf", "floors": 3, "cellar": true, "size": "small", "clutter": 2}, 0xABCDE12345)
	var sc: SeedCode = SeedCode.parse(code)
	assert_true(sc.is_valid(), code)
	assert_eq(sc.encode(), code)
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "")
	if res.doc != null:
		assert_eq(res.doc.scale, "EDI")
		assert_eq(res.doc.level_count(), 4)
		assert_eq(res.doc.seed_code, code)
	# Todo por defecto: taberna, cuadrada, humana, 2 plantas, sin sótano.
	var def: MapDocument = GeneratorRegistry.generate(_code({}, 1)).doc
	if def != null:
		assert_eq(def.level_count(), 2)
		assert_eq(def.grid_kind(), "square")


# --- Comprobación de un edificio -------------------------------------------------

## Problemas de un edificio generado (vacío = correcto).
func _problems(res: EdiGeneratorG1.Result) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var doc: MapDocument = res.doc
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	# Entrada en la planta baja.
	var ground: MapLevel = doc.level(res.ground_level)
	var entrance: Vector2i = Vector2i(-1, -1)
	for r: MapRoom in ground.rooms:
		if r.kind == MapRoom.KIND_ENTRANCE:
			var ec: Array[Vector2i] = ground.room_cells(r.id)
			if ec.size() != 1:
				out.append("entrada con %d casillas" % ec.size())
			else:
				entrance = ec[0]
	if entrance.x < 0:
		out.append("sin entrada")
		return out
	var missing: int = Connectivity.unreachable_count(doc, res.ground_level, entrance)
	if missing != 0:
		out.append("%d casillas inaccesibles desde la entrada" % missing)
	# Escaleras: pares coherentes entre plantas consecutivas, misma casilla.
	var stair_total: int = 0
	for li: int in doc.level_count():
		var lvl: MapLevel = doc.level(li)
		for s: MapStair in lvl.stairs:
			stair_total += 1
			if absi(s.to_level - li) != 1 or s.to_level < 0 or s.to_level >= doc.level_count():
				out.append("escalera de %d a %d" % [li, s.to_level])
				continue
			if s.to_cell != s.cell:
				out.append("escalera con casillas distintas")
			var back: bool = false
			for s2: MapStair in doc.level(s.to_level).stairs_at(s.to_cell):
				if s2.to_level == li:
					back = true
			if not back:
				out.append("escalera sin vuelta en %d %s" % [li, s.cell])
			var rid: int = lvl.get_room_id(s.cell)
			if not Terrain.is_passable(lvl.get_terrain(s.cell)) or rid == 0 or lvl.room(rid).kind == MapRoom.KIND_OUTSIDE:
				out.append("escalera fuera de una estancia en %d %s" % [li, s.cell])
			if not lvl.objects_at(s.cell).is_empty():
				out.append("objeto sobre la escalera en %d %s" % [li, s.cell])
	if stair_total != 2 * (doc.level_count() - 1):
		out.append("escaleras: %d para %d plantas" % [stair_total, doc.level_count()])
	for f: EdiGeneratorG1.Floor in res.floors:
		out.append_array(_floor_problems(doc, f, cat))
	return out


func _floor_problems(doc: MapDocument, f: EdiGeneratorG1.Floor, cat: ObjectCatalog) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var grid: GridGeometry = doc.grid
	var lvl: MapLevel = doc.level(f.level_index)
	var tag: String = "nivel %d (%s)" % [f.level_index, f.floor_class]
	var stair_cells: Array[Vector2i] = []
	for s: MapStair in lvl.stairs:
		stair_cells.append(s.cell)
	# Puertas: casillas sin repetir, nunca en escaleras; cada estancia con una.
	var door_count: Dictionary[int, int] = {}
	var cell_uses: PackedInt32Array = PackedInt32Array()
	cell_uses.resize(grid.cell_count())
	cell_uses.fill(0)
	var doors_between: Array[Vector2i] = []
	for id: int in lvl.edge_ids():
		var v: int = lvl.get_edge_by_id(id)
		var k: int = MapEdge.kind_of(v)
		var cells: Array[Vector2i] = grid.edge_cells(id)
		if k == MapEdge.KIND_WINDOW:
			if f.floor_class == EdiData.FLOOR_CELLAR:
				out.append("%s: ventana en el sótano" % tag)
			var inside: int = 0
			for c: Vector2i in cells:
				if grid.in_bounds(c) and f.footprint.has_point(c) and Terrain.is_passable(lvl.get_terrain(c)):
					inside += 1
			if inside != 1:
				out.append("%s: ventana que no está en el muro exterior" % tag)
			continue
		if k != MapEdge.KIND_DOOR:
			continue
		var rooms: Vector2i = Vector2i(lvl.get_room_id(cells[0]), lvl.get_room_id(cells[1]))
		doors_between.append(rooms)
		for c: Vector2i in cells:
			var ci: int = grid.index_of(c)
			cell_uses[ci] += 1
			if cell_uses[ci] > 1:
				out.append("%s: dos puertas comparten %s" % [tag, c])
			if stair_cells.has(c):
				out.append("%s: puerta en la escalera %s" % [tag, c])
			var rid: int = lvl.get_room_id(c)
			var prev: int = door_count.get(rid, 0)
			door_count[rid] = prev + 1
	# Estancias: huella entera en estancias, cada una con puerta y su tipo.
	for sl: EdiGeneratorG1.Slot in f.slots:
		if not sl.placed():
			continue
		if lvl.room(sl.room_id) == null or lvl.room(sl.room_id).kind != sl.kind:
			out.append("%s: estancia %s sin zona" % [tag, sl.key])
			continue
		var has_stair: bool = false
		for sc: Vector2i in stair_cells:
			has_stair = has_stair or lvl.get_room_id(sc) == sl.room_id
		# Sin puerta solo si es la única estancia de la planta y llega la escalera.
		if not door_count.has(sl.room_id) and not (has_stair and _placed_count(f) == 1):
			out.append("%s: estancia %s sin puerta" % [tag, sl.key])
		if sl.rect.size.x < EdiGeneratorG1.MIN_SIDE or sl.rect.size.y < EdiGeneratorG1.MIN_SIDE:
			if not sl.hub:
				out.append("%s: estancia %s de %s" % [tag, sl.key, sl.rect.size])
	for c: Vector2i in EdiGeneratorG1.rect_cells(f.footprint):
		var rid2: int = lvl.get_room_id(c)
		if lvl.get_terrain(c) != Terrain.FLOOR or rid2 == 0 or lvl.room(rid2).kind == MapRoom.KIND_OUTSIDE:
			out.append("%s: hueco en la huella %s" % [tag, c])
			break
	if f.floor_class != EdiData.FLOOR_GROUND:
		for i: int in grid.cell_count():
			if not f.footprint.has_point(grid.cell_at(i)) and lvl.terrain[i] != Terrain.VOID:
				out.append("%s: suelo fuera de la huella" % tag)
				break
	# Adyacencias obligatorias: puerta directa o, con hub de reserva, ambas al hub.
	var hub: int = f.hub_index()
	for pair: Vector2i in f.pairs:
		var a: EdiGeneratorG1.Slot = f.slots[pair.x]
		var b: EdiGeneratorG1.Slot = f.slots[pair.y]
		if not a.placed() or not b.placed():
			continue
		if _door_between(doors_between, a.room_id, b.room_id):
			continue
		if f.fallback_hub and hub >= 0 and _door_between(doors_between, a.room_id, f.slots[hub].room_id) \
				and _door_between(doors_between, b.room_id, f.slots[hub].room_id):
			continue
		out.append("%s: adyacencia %s-%s sin cumplir" % [tag, a.key, b.key])
	# Muros: entre dos estancias distintas de la huella siempre hay arista.
	for c2: Vector2i in EdiGeneratorG1.rect_cells(f.footprint):
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(c2, d)
			if lvl.get_room_id(n) != lvl.get_room_id(c2) and lvl.get_edge(c2, d) == MapEdge.NONE:
				out.append("%s: falta muro en %s dir %d" % [tag, c2, d])
	# Objetos: dentro de su estancia, sin tapar puertas ni escaleras.
	for o: MapObject in lvl.objects:
		if cat.entry(o.catalog_id) == null:
			out.append("objeto fuera del catálogo")
		var cells2: Array[Vector2i] = lvl.object_cells(o)
		var rid3: int = lvl.get_room_id(o.cell)
		for c3: Vector2i in cells2:
			if lvl.get_room_id(c3) != rid3:
				out.append("%s: %s cruza un muro" % [tag, o.catalog_id])
			if cell_uses[grid.index_of(c3)] != 0:
				out.append("%s: %s tapa una puerta" % [tag, o.catalog_id])
	return out


func _placed_count(f: EdiGeneratorG1.Floor) -> int:
	var n: int = 0
	for sl: EdiGeneratorG1.Slot in f.slots:
		if sl.placed():
			n += 1
	return n


func _door_between(doors: Array[Vector2i], a: int, b: int) -> bool:
	return doors.has(Vector2i(a, b)) or doors.has(Vector2i(b, a))


func _check(params: Dictionary, seed_value: int, system: String = "DND5") -> EdiGeneratorG1.Result:
	var code: String = _code(params, seed_value, system)
	var res: EdiGeneratorG1.Result = _build(code)
	assert_not_null(res, code)
	if res == null:
		return null
	assert_eq(_problems(res), PackedStringArray(), code)
	# El registro sella la procedencia: se sella igual para comparar.
	res.doc.seed_code = code
	res.doc.scale = "EDI"
	res.doc.gen_version = 1
	var again: MapDocument = GeneratorRegistry.generate(code).doc
	assert_eq(again.content_hash(), res.doc.content_hash(), "determinismo: " + code)
	return res


# --- Propiedades --------------------------------------------------------------------

func test_all_types_all_grids_many_seeds() -> void:
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		for t: String in TYPES:
			for s: int in [1, 2, 3]:
				i += 1
				var params: Dictionary = {"building_type": t, "grid": kind, "style": STYLES[i % 3]}
				if s == 3:
					params["cellar"] = true
				var res: EdiGeneratorG1.Result = _check(params, 1000 * i + s)
				if res != null:
					assert_true(res.doc.level(res.ground_level).objects.size() >= 1, "%s %s sin objetos" % [kind, t])


func test_floors_cellar_sizes_and_clutter() -> void:
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		for size: String in ["small", "medium", "large"]:
			i += 1
			var t: String = TYPES[i % TYPES.size()]
			var res: EdiGeneratorG1.Result = _check({"building_type": t, "grid": kind, "size": size, "floors": 1 + i % 4,
				"cellar": i % 2 == 0, "clutter": (i * 3) % 11, "style": STYLES[i % 3]}, 77 + i, "PF2E")
			if res != null:
				assert_eq(res.doc.level_count(), 1 + i % 4 + (1 if i % 2 == 0 else 0))
				assert_eq(res.ground_level, 1 if i % 2 == 0 else 0)


func test_style_changes_footprint_and_windows() -> void:
	var human: EdiGeneratorG1.Result = _check({"building_type": "house", "style": "human"}, 5)
	var dwarf: EdiGeneratorG1.Result = _check({"building_type": "house", "style": "dwarf"}, 5)
	if human == null or dwarf == null:
		return
	assert_true(dwarf.doc.width() > human.doc.width(), "la huella enana es mayor (115 %)")
	var hw: int = 0
	var dw: int = 0
	for s: int in 10:
		hw += _count_edges(_build(_code({"building_type": "temple", "style": "elf"}, 40 + s)).doc, MapEdge.KIND_WINDOW)
		dw += _count_edges(_build(_code({"building_type": "temple", "style": "dwarf"}, 40 + s)).doc, MapEdge.KIND_WINDOW)
	assert_true(hw > dw, "ventanas élficas %d > enanas %d" % [hw, dw])


func _count_edges(doc: MapDocument, kind: int) -> int:
	var n: int = 0
	for lvl: MapLevel in doc.levels:
		for id: int in lvl.edge_ids():
			if MapEdge.kind_of(lvl.get_edge_by_id(id)) == kind:
				n += 1
	return n


func test_taberna_tiene_cadena_sala_cocina_almacen() -> void:
	for s: int in 20:
		var res: EdiGeneratorG1.Result = _check({"building_type": "tavern"}, 300 + s)
		if res == null:
			return
		var g: EdiGeneratorG1.Floor = res.floors[res.ground_level]
		for key: String in ["common", "kitchen", "store"]:
			assert_true(g.slot_index(key) >= 0, "falta %s" % key)
		assert_eq(g.pairs.size(), 2)
		# Habitaciones arriba, alrededor del recibidor.
		var up: EdiGeneratorG1.Floor = res.floors[res.ground_level + 1]
		assert_true(up.hub_index() >= 0)
		assert_true(up.slot_index("bed_1") >= 0)


func test_seed_changes_output_and_child_seeds() -> void:
	var a: MapDocument = GeneratorRegistry.generate(_code({}, 1)).doc
	var b: MapDocument = GeneratorRegistry.generate(_code({}, 2)).doc
	if a != null and b != null:
		assert_ne(a.content_hash(), b.content_hash())
	assert_eq(EdiGeneratorG1.room_seed(9, 1, 2), SplitMix64.hash64(9, "EST", 258))


## Jerarquía de semillas (§5.2): el mobiliario de cada estancia sale solo de
## su semilla hija; amueblar el mismo recinto aparte con room_seed() da los
## mismos objetos.
func test_room_furniture_depends_only_on_child_seed() -> void:
	var code: String = _code({"building_type": "inn", "grid": "hex_pointy", "cellar": true}, 0x51DE)
	var sc: SeedCode = SeedCode.parse(code)
	var res: EdiGeneratorG1.Result = _build(code)
	if res == null:
		return
	var checked: int = 0
	for f: EdiGeneratorG1.Floor in res.floors:
		for i: int in f.slots.size():
			var sl: EdiGeneratorG1.Slot = f.slots[i]
			if not sl.placed():
				continue
			var lvl: MapLevel = res.doc.level(f.level_index)
			var expected: PackedStringArray = PackedStringArray()
			for o: MapObject in lvl.objects:
				if lvl.get_room_id(o.cell) == sl.room_id:
					expected.append("%s@%s/%d/%s" % [o.catalog_id, o.cell, o.facing, o.material])
			var solo: MapDocument = MapDocument.create(res.doc.grid_kind(), res.doc.width(), res.doc.height())
			var cells: Array[Vector2i] = EdiGeneratorG1.rect_cells(sl.rect)
			for c: Vector2i in cells:
				solo.level(0).set_terrain(c, Terrain.FLOOR)
			var rng: Rng = Rng.new(EdiGeneratorG1.room_seed(sc.seed_value, f.level_index, sl.order)).fork("furnish", 0)
			EstFurnisherG1.furnish(solo, 0, cells, EdiGeneratorG1.room_entries(res.doc.grid, f, i), sl.kind, "human", 5, rng)
			var got: PackedStringArray = PackedStringArray()
			for o2: MapObject in solo.level(0).objects:
				got.append("%s@%s/%d/%s" % [o2.catalog_id, o2.cell, o2.facing, o2.material])
			assert_eq(got, expected, "%d/%s" % [f.level_index, sl.key])
			checked += 1
	assert_true(checked >= 8, "estancias comprobadas: %d" % checked)


## Una estrella (una estancia pequeña que debe tocar a otras cuatro) casi
## nunca sale del BSP: se usa el hub de reserva y las adyacencias se cumplen
## directamente o a través de él; todas las estancias quedan unidas.
func test_fallback_hub_when_adjacency_impossible() -> void:
	var bt: EdiData.BuildingType = EdiData.BuildingType.new()
	bt.id = "star"
	bt.entrance = "a"
	bt.back_door = ""
	for k: int in 5:
		var s: EdiData.RoomSpec = EdiData.RoomSpec.new()
		s.key = "abcde"[k]
		s.kind = "storage"
		s.floor_class = EdiData.FLOOR_GROUND
		s.area = 4 if k == 0 else 25
		bt.rooms.append(s)
		if k > 0:
			bt.adjacency.append(PackedStringArray(["a", s.key]))
	var sb: EdiData.StyleBuilding = EdiData.StyleBuilding.new()
	var fallbacks: int = 0
	for kind: String in GridGeometry.KINDS:
		for seed_value: int in 10:
			var doc: MapDocument = MapDocument.create(kind, 16, 12)
			var none: Array[Vector2i] = []
			var f: EdiGeneratorG1.Floor = EdiGeneratorG1._build_floor(doc.grid, bt, sb, 0, EdiData.FLOOR_GROUND, Rect2i(1, 1, 14, 10), none, Rng.new(seed_value))
			if f.fallback_hub:
				fallbacks += 1
				assert_true(f.hub_index() >= 0)
			var reached: PackedByteArray = EdiGeneratorG1._reached_slots(doc.grid, f)
			for i: int in f.slots.size():
				if f.slots[i].placed():
					assert_eq(reached[i], 1, "%s %d: estancia %s sin unir" % [kind, seed_value, f.slots[i].key])
			EdiGeneratorG1._commit_floor(doc, f)
			var res: EdiGeneratorG1.Result = EdiGeneratorG1.Result.new()
			res.doc = doc
			res.floors.append(f)
			var problems: PackedStringArray = _floor_problems(doc, f, ObjectCatalog.load_default())
			assert_eq(problems, PackedStringArray(), "%s %d" % [kind, seed_value])
			assert_eq(Connectivity.unreachable_count(doc, 0, f.entrance_cell), 0)
	print("EDI_FALLBACK estrella: %d de 30 plantas con hub de reserva" % fallbacks)
	assert_true(fallbacks > 0, "la estrella debe forzar el hub de reserva")


func test_unknown_values_return_null() -> void:
	var p: EdiGeneratorG1.Params = EdiGeneratorG1.Params.new()
	p.building_type = "castle"
	assert_null(EdiGeneratorG1.generate_building(p, Rng.new(1)))


# --- Ventanas en el modelo y en las vistas -------------------------------------------

func test_window_blocks_movement_not_sight() -> void:
	var profile: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	for kind: String in GridGeometry.KINDS:
		var doc: MapDocument = MapDocument.create(kind, 5, 3)
		var lvl: MapLevel = doc.level(0)
		lvl.fill_terrain(Terrain.FLOOR)
		# Una columna de ventanas entre x=1 y x=2 (todas las aristas hacia el E).
		for y: int in 3:
			var c: Vector2i = Vector2i(1, y)
			for d: int in doc.grid.edge_direction_count():
				if doc.grid.neighbor(c, d).x == 2:
					lvl.set_edge(c, d, MapEdge.make(MapEdge.KIND_WINDOW))
		assert_true(Visibility.has_los(lvl, Vector2i(0, 1), Vector2i(4, 1)), kind + ": se ve a través")
		var route: MovementCost.Route = MovementCost.find_route(profile, lvl, Vector2i(0, 1), Vector2i(4, 1))
		assert_false(route.found, kind + ": no se cruza")
		assert_eq(Connectivity.unreachable_count(doc, 0, Vector2i(0, 1)), 9, kind + ": conectividad")


func test_views_draw_buildings_with_windows() -> void:
	var res: EdiGeneratorG1.Result = _build(_code({"building_type": "temple", "style": "elf", "floors": 2}, 12))
	if res == null:
		return
	assert_true(_count_edges(res.doc, MapEdge.KIND_WINDOW) > 0)
	for li: int in res.doc.level_count():
		var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
		var root: Node3D = MapMeshBuilder.build_level(res.doc, li, opts)
		assert_not_null(root.get_node_or_null("Walls"), "nivel %d sin muros" % li)
		root.free()
	var view: MapView2D = MapView2D.new()
	add_child_autofree(view)
	view.document = res.doc
	view.queue_redraw()
	await wait_process_frames(1)
	pass_test("vista 2D dibujada")


## La pantalla principal ofrece la escala EDI, genera aleatorias y abre un
## edificio con sótano en la planta baja (la de la entrada), no en el sótano.
func test_main_screen_edi() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var scale_opt: OptionButton = main.get("_scale_opt")
	var scales: Array[String] = main.get("SCALES")
	var edi: int = scales.find("EDI")
	assert_true(edi >= 0)
	assert_eq(scale_opt.get_item_text(edi), "Edificio")
	scale_opt.select(edi)
	main.call("_generate_random")
	await wait_process_frames(1)
	var doc: MapDocument = main.get("_doc")
	assert_not_null(doc)
	if doc != null:
		assert_eq(doc.scale, "EDI")
	var edit: LineEdit = main.get("_code_edit")
	edit.text = _code({"building_type": "temple", "cellar": true}, 99)
	main.call("_generate_from_text")
	await wait_process_frames(1)
	var level_opt: OptionButton = main.get("_level_opt")
	assert_eq(level_opt.item_count, 2)
	assert_eq(level_opt.selected, 1, "abre en la planta baja")
	var view: MapView2D = main.get("_view")
	assert_eq(view.level_index, 1)
	main.call("_add_token")
	doc = main.get("_doc")
	if doc != null and not doc.tokens.is_empty():
		assert_eq(doc.tokens[0].level, 1)


# --- Estadísticas, candidatas a seeds doradas y ASCII ---------------------------------

func test_stats() -> void:
	var buildings: int = 0
	var fallback: int = 0
	var floors: int = 0
	var dropped: int = 0
	var rooms: int = 0
	var t0: int = Time.get_ticks_msec()
	for kind: String in GridGeometry.KINDS:
		for t: String in TYPES:
			for s: int in 4:
				var res: EdiGeneratorG1.Result = _build(_code({"building_type": t, "grid": kind, "size": ["small", "medium", "large", "auto"][s]}, 9000 + s))
				if res == null:
					continue
				buildings += 1
				for f: EdiGeneratorG1.Floor in res.floors:
					floors += 1
					if f.fallback_hub:
						fallback += 1
					for sl: EdiGeneratorG1.Slot in f.slots:
						if sl.placed():
							rooms += 1
						else:
							dropped += 1
	var ms: int = Time.get_ticks_msec() - t0
	print("EDI_STATS edificios=%d plantas=%d estancias=%d descartadas=%d plantas_con_hub_de_reserva=%d ms_total=%d ms_por_edificio=%d" % [
		buildings, floors, rooms, dropped, fallback, ms, ms / maxi(1, buildings)])
	assert_eq(buildings, 84)


## [sistema, parámetros, semilla]: los 7 tipos, las tres rejillas, los tres
## estilos, 1-3 plantas, sótano y tamaños.
static func candidates() -> Array:
	return [
		["DND5", {}, 0x8A1B2C3D4E],
		["DND5", {"building_type": "house", "cellar": true}, 0x9B2C3D4E5F],
		["PF2E", {"building_type": "smithy", "grid": "hex_flat", "style": "dwarf"}, 0xAC3D4E5F60],
		["DND5", {"building_type": "temple", "grid": "hex_pointy", "style": "elf", "cellar": true}, 0xBD4E5F6071],
		["DND5", {"building_type": "shop", "floors": 3, "size": "medium"}, 0xCE5F607182],
		["PF2E", {"building_type": "inn", "grid": "hex_flat", "clutter": 8}, 0xDF60718293],
		["DND5", {"building_type": "guardhouse", "style": "dwarf", "cellar": true}, 0xE0718293A4],
		["PF2E", {"building_type": "tavern", "grid": "hex_pointy", "size": "large", "floors": 1, "cellar": true}, 0xF18293A4B5],
	]


func test_golden_candidates() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for item: Variant in candidates():
		var entry: Array = item
		var system: String = entry[0]
		var params: Dictionary = entry[1]
		var seed_value: int = entry[2]
		var res: EdiGeneratorG1.Result = _check(params, seed_value, system)
		if res != null:
			lines.append("# " + _code(params, seed_value, system))
	assert_eq(lines.size(), candidates().size())
	print("EDI_GOLDEN_CANDIDATES_BEGIN\n%s\nEDI_GOLDEN_CANDIDATES_END" % "\n".join(lines))


## ASCII de un nivel de rejilla cuadrada con aristas: '|' '-' muro, 'D'
## puerta, 'W' ventana, '+' esquina; en las casillas: ' ' vacío, ',' exterior,
## 'e' entrada/salida, '.' suelo, '>' '<' escalera arriba/abajo y la inicial
## del objeto (mayúscula si bloquea el paso).
static func ascii_square(doc: MapDocument, li: int) -> String:
	var lvl: MapLevel = doc.level(li)
	var g: GridGeometry = doc.grid
	var rows: PackedStringArray = PackedStringArray()
	for y: int in g.height:
		var top: String = ""
		var mid: String = ""
		for x: int in g.width:
			var c: Vector2i = Vector2i(x, y)
			top += "+" + _edge_char(lvl.get_edge(c, 0), "-")
			mid += _edge_char(lvl.get_edge(c, 3), "|") + _cell_char(lvl, li, c)
		rows.append(top + "+")
		rows.append(mid + _edge_char(lvl.get_edge(Vector2i(g.width - 1, y), 1), "|"))
	var last: String = ""
	for x: int in g.width:
		last += "+" + _edge_char(lvl.get_edge(Vector2i(x, g.height - 1), 2), "-")
	rows.append(last + "+")
	return "\n".join(rows)


static func _edge_char(v: int, wall: String) -> String:
	match MapEdge.kind_of(v):
		MapEdge.KIND_WALL:
			return wall
		MapEdge.KIND_DOOR:
			return "D"
		MapEdge.KIND_WINDOW:
			return "W"
	return " "


static func _cell_char(lvl: MapLevel, li: int, c: Vector2i) -> String:
	var t: int = lvl.get_terrain(c)
	if not Terrain.is_passable(t):
		return " "
	for s: MapStair in lvl.stairs_at(c):
		return ">" if s.to_level > li else "<"
	var objs: Array[MapObject] = lvl.objects_at(c)
	if not objs.is_empty():
		var ch: String = objs[0].catalog_id.substr(0, 1)
		return ch.to_upper() if objs[0].blocks_movement else ch
	var rid: int = lvl.get_room_id(c)
	var r: MapRoom = lvl.room(rid)
	if r != null and r.kind == MapRoom.KIND_OUTSIDE:
		return ","
	if r != null and (r.kind == MapRoom.KIND_ENTRANCE or r.kind == MapRoom.KIND_EXIT):
		return "e"
	return "."


func test_print_ascii_samples() -> void:
	for t: String in TYPES:
		var code: String = _code({"building_type": t, "cellar": t == "guardhouse" or t == "temple"}, 7)
		var res: EdiGeneratorG1.Result = _build(code)
		if res == null:
			continue
		var text: String = code
		for li: int in res.doc.level_count():
			text += "\n-- nivel %d (%s)%s\n%s" % [li, res.floors[li].floor_class, " [hub de reserva]" if res.floors[li].fallback_hub else "", ascii_square(res.doc, li)]
		print(text + "\n")
	# Hex: ASCII por casillas de test_est_generator.gd (planta baja).
	var est_script: GDScript = load("res://tests/unit/test_est_generator.gd")
	for kind: String in ["hex_flat", "hex_pointy"]:
		var code2: String = _code({"building_type": "tavern", "grid": kind}, 7)
		var doc: MapDocument = GeneratorRegistry.generate(code2).doc
		if doc != null:
			var text2: String = est_script.call("ascii", doc)
			print("%s\n%s\n" % [code2, text2])
	pass_test("ASCII impreso")
