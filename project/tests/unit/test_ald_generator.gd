extends GutTest
## Tests de ALD G1 (core/gen/ald) y de sus datos: con varias semillas, los 4
## tamaños, las tres rejillas, los tres estilos, muralla, río/costa,
## prosperidad y retícula comprueba que la red de calles es conexa, que la
## puerta de todo edificio se alcanza desde la plaza sin cruzar agua, que el
## código EDI de cada edificio regenera exactamente la huella, el tipo, la
## puerta principal, la trasera y las ventanas que describe el asentamiento
## (criterio de F3), que los edificios son independientes entre sí y el
## determinismo.
##
## Imprime estadísticas y tiempos (ALD_STATS), códigos de ejemplo y ASCII.
## NO graba seeds doradas: el esquema está pendiente de aprobar.

const SIZES: PackedStringArray = ["hamlet", "village", "town", "city"]
const STYLES: PackedStringArray = ["human", "dwarf", "elf"]
const STREET_KINDS: PackedStringArray = ["street", "plaza", "bridge", "gate"]


func after_each() -> void:
	GeneratorRegistry.reset()


func _code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	var sc: SeedCode = SeedCode.create(system, "ALD", 1, params, seed_value)
	assert_true(sc.is_valid(), "%s %s" % [sc.error, sc.error_field])
	return sc.encode()


func _build(code: String) -> AldGeneratorG1.Result:
	var sc: SeedCode = SeedCode.parse(code)
	assert_true(sc.is_valid(), code)
	return AldGeneratorG1.generate_settlement(AldGeneratorG1.params_from(sc), sc.system, Rng.new(sc.seed_value))


# --- Datos y registro -------------------------------------------------------------

func test_data_schema_and_registry() -> void:
	var data: AldData = AldData.load_default()
	assert_eq(data.error, "")
	var schema: ParamSchema = ParamSchemaRegistry.get_schema("ALD", 1)
	assert_not_null(schema)
	if schema == null:
		return
	assert_eq(schema.field_keys(), PackedStringArray(["size", "grid", "style", "wall", "water", "prosperity", "layout"]))
	# Tamaños y prosperidad: mismos ids y en el mismo orden que el esquema.
	assert_eq(data.size_ids, schema.fields[0].ids)
	assert_eq(data.prosperity_ids, schema.fields[5].ids)
	# Mismos estilos y rejillas que EDI (los hijos los heredan).
	var edi: ParamSchema = ParamSchemaRegistry.get_schema("EDI", 1)
	assert_eq(schema.fields[1].ids, edi.fields[1].ids)
	assert_eq(schema.fields[2].ids, edi.fields[2].ids)
	for s: String in STYLES:
		assert_not_null(data.style_settlement(s), s)
	# Los tipos de ALD son tipos de EDI (y del enumerado building_type).
	for t: String in data.type_ids:
		assert_true(edi.fields[0].ids.has(t), t)
	assert_true(GeneratorRegistry.has_generator("ALD", 1))
	var es: Translation = load("res://i18n/strings.es.translation")
	var keys: PackedStringArray = ["UI_SCALE_ALD", "UI_SETTLEMENT_INFO"]
	for k: String in MapRoom.OUTDOOR_KINDS:
		keys.append("ROOM_KIND_" + k.to_upper())
	for k2: String in [MapRoom.KIND_BUILDING, MapRoom.KIND_TOWN_WALL]:
		keys.append("ROOM_KIND_" + k2.to_upper())
	for sz: String in data.size_ids:
		keys.append("SETTLEMENT_" + sz.to_upper())
	for k3: String in keys:
		assert_ne(String(es.get_message(k3)), "", k3)


func test_code_round_trip_and_registry_generates() -> void:
	var code: String = _code({"size": "town", "grid": "hex_pointy", "style": "elf", "wall": true, "water": "coast",
		"prosperity": "rich", "layout": "grid"}, 0xABCDE12345)
	var sc: SeedCode = SeedCode.parse(code)
	assert_true(sc.is_valid(), code)
	assert_eq(sc.encode(), code)
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "")
	if res.doc != null:
		assert_eq(res.doc.scale, "ALD")
		assert_eq(res.doc.seed_code, code)
		assert_eq(res.doc.grid_kind(), "hex_pointy")
	# Todo por defecto: aldea, cuadrada, humana, sin muralla ni agua.
	var def: MapDocument = GeneratorRegistry.generate(_code({}, 1)).doc
	if def != null:
		var data: AldData = AldData.load_default()
		assert_eq(Vector2i(def.width(), def.height()), data.size_spec("village").map)
		assert_eq(def.level_count(), 1)


# --- Comprobación de un asentamiento -----------------------------------------------

## Problemas de un asentamiento generado (vacío = correcto).
func _problems(res: AldGeneratorG1.Result) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var doc: MapDocument = res.doc
	var lvl: MapLevel = doc.level(0)
	var g: GridGeometry = doc.grid
	var plaza: Vector2i = res.plaza_cell
	if _kind_at(lvl, plaza) != MapRoom.KIND_PLAZA:
		out.append("el centro no es la plaza")
		return out
	# 1. Calles: una sola red (vecinos de la rejilla, sin aristas que lo impidan).
	var streets: PackedByteArray = _flood(doc, plaza, STREET_KINDS, false)
	for i: int in g.cell_count():
		if STREET_KINDS.has(_kind_at(lvl, g.cell_at(i))) and streets[i] == 0:
			out.append("calle suelta en %s" % g.cell_at(i))
			break
	# 2. A pie y sin mojarse: toda parcela y toda entrada desde la plaza.
	var dry: PackedByteArray = _flood(doc, plaza, PackedStringArray(), true)
	for i2: int in g.cell_count():
		if _kind_at(lvl, g.cell_at(i2)) == MapRoom.KIND_YARD and dry[i2] == 0:
			out.append("parcela inaccesible en %s" % g.cell_at(i2))
			break
	# 3. Connectivity del documento (el criterio común de los generadores).
	var missing: int = Connectivity.unreachable_count(doc, 0, plaza)
	if missing != 0:
		out.append("%d casillas inaccesibles desde la plaza" % missing)
	# 4. Cada edificio: huella = zona, entrada fuera y unida por una puerta.
	if lvl.children.size() != res.placed_count():
		out.append("hijos %d != colocados %d" % [lvl.children.size(), res.placed_count()])
	for c: MapChild in lvl.children:
		var cells: Array[Vector2i] = lvl.room_cells(c.room_id)
		if cells.size() != c.rect.get_area():
			out.append("%s: zona de %d casillas, huella de %d" % [c.seed_code, cells.size(), c.rect.get_area()])
		for fc: Vector2i in cells:
			if not c.rect.has_point(fc) or lvl.get_terrain(fc) != Terrain.FLOOR:
				out.append("%s: casilla de huella mala %s" % [c.seed_code, fc])
				break
		if c.rect.has_point(c.entrance) or _kind_at(lvl, c.entrance) != MapRoom.KIND_YARD:
			out.append("%s: entrada %s fuera de su parcela" % [c.seed_code, c.entrance])
		if dry[g.index_of(c.entrance)] == 0:
			out.append("%s: entrada inaccesible" % c.seed_code)
		var door: bool = false
		for d: int in g.edge_direction_count():
			if c.rect.has_point(g.neighbor(c.entrance, d)) and MapEdge.kind_of(lvl.get_edge(c.entrance, d)) == MapEdge.KIND_DOOR:
				door = true
		if not door:
			out.append("%s: sin puerta junto a la entrada" % c.seed_code)
		var sc: SeedCode = SeedCode.parse(c.seed_code)
		if not sc.is_valid() or sc.scale != "EDI":
			out.append("%s: código EDI no válido" % c.seed_code)
			continue
		var bt: String = sc.params["building_type"]
		var gk: String = sc.params["grid"]
		if bt != c.kind or gk != doc.grid_kind():
			out.append("%s: tipo o rejilla distintos" % c.seed_code)
		var cellar: bool = sc.params["cellar"]
		if c.child_level != (1 if cellar else 0):
			out.append("%s: nivel hijo %d" % [c.seed_code, c.child_level])
	return out


func _kind_at(lvl: MapLevel, c: Vector2i) -> String:
	var r: MapRoom = lvl.room(lvl.get_room_id(c))
	return r.kind if r != null else ""


## Inundación por vecinos de la rejilla y aristas franqueables. Con `kinds`
## no vacío, solo por casillas de esas zonas; con `dry`, solo por suelo fuera
## de las huellas (a pie, sin agua ni muralla).
func _flood(doc: MapDocument, start: Vector2i, kinds: PackedStringArray, dry: bool) -> PackedByteArray:
	var lvl: MapLevel = doc.level(0)
	var g: GridGeometry = doc.grid
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(g.cell_count())
	seen.fill(0)
	var queue: Array[Vector2i] = [start]
	seen[g.index_of(start)] = 1
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: int in g.edge_direction_count():
			var nb: Vector2i = g.neighbor(c, d)
			var ni: int = g.index_of(nb)
			if ni < 0 or seen[ni] != 0 or not MapEdge.is_traversable(lvl.get_edge(c, d)):
				continue
			var k: String = _kind_at(lvl, nb)
			if not kinds.is_empty() and not kinds.has(k):
				continue
			if dry and (lvl.get_terrain(nb) != Terrain.FLOOR or k == MapRoom.KIND_BUILDING):
				continue
			seen[ni] = 1
			queue.append(nb)
	return seen


func _check(params: Dictionary, seed_value: int, system: String = "DND5") -> AldGeneratorG1.Result:
	var code: String = _code(params, seed_value, system)
	var res: AldGeneratorG1.Result = _build(code)
	assert_not_null(res, code)
	if res == null:
		return null
	assert_eq(_problems(res), PackedStringArray(), code)
	res.doc.seed_code = code
	res.doc.scale = "ALD"
	res.doc.gen_version = 1
	var again: MapDocument = GeneratorRegistry.generate(code).doc
	assert_eq(again.content_hash(), res.doc.content_hash(), "determinismo: " + code)
	return res


# --- Propiedades --------------------------------------------------------------------

func test_sizes_grids_styles() -> void:
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		for size: String in SIZES:
			i += 1
			var res: AldGeneratorG1.Result = _check({"size": size, "grid": kind, "style": STYLES[i % 3]}, 7000 + i)
			if res == null:
				continue
			_assert_placement(res, "%s %s" % [kind, size])


## Se colocan casi todos los edificios intentados (los que no caben junto a
## una calle se descartan) y siempre los obligatorios del tamaño, que van
## primero junto a la plaza.
func _assert_placement(res: AldGeneratorG1.Result, tag: String) -> void:
	var placed: int = res.placed_count()
	var wanted: int = res.buildings.size()
	assert_true(placed * 100 >= wanted * 80, "%s: %d de %d edificios" % [tag, placed, wanted])
	var ss: AldData.SizeSpec = null
	var sc: SeedCode = SeedCode.parse(res.doc.seed_code) if not res.doc.seed_code.is_empty() else null
	if sc != null and sc.is_valid():
		var size_id: String = sc.params["size"]
		ss = AldData.load_default().size_spec(size_id)
	for b: AldGeneratorG1.Building in res.buildings:
		if ss != null and b.order < ss.required.size():
			assert_true(b.placed, "%s: obligatorio %s sin sitio" % [tag, b.edi.building_type])


func test_wall_water_prosperity_layout() -> void:
	var i: int = 0
	for water: String in ["none", "river", "coast"]:
		for wall: bool in [false, true]:
			for layout: String in ["organic", "grid"]:
				i += 1
				var params: Dictionary = {"size": SIZES[i % 4], "grid": GridGeometry.KINDS[i % 3], "style": STYLES[(i / 3) % 3],
					"wall": wall, "water": water, "layout": layout, "prosperity": ["poor", "average", "rich"][i % 3]}
				var res: AldGeneratorG1.Result = _check(params, 500 + i, "PF2E" if i % 2 == 0 else "DND5")
				if res == null:
					continue
				_assert_placement(res, str(params))
				var zones: Dictionary[String, int] = _zone_counts(res.doc)
				var n_wall: int = zones.get("town_wall", 0)
				var n_gate: int = zones.get("gate", 0)
				var n_bridge: int = zones.get("bridge", 0)
				assert_eq(n_wall > 0, wall, "muralla: %s" % params)
				assert_eq(n_gate > 0, wall, "puertas: %s" % params)
				assert_eq(n_bridge > 0, water == "river", "puente: %s" % params)
				var wet: int = _terrain_count(res.doc, Terrain.WATER_DEEP) + _terrain_count(res.doc, Terrain.WATER_SHALLOW)
				assert_eq(wet > 0, water != "none", "agua: %s" % params)


func _zone_counts(doc: MapDocument) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var lvl: MapLevel = doc.level(0)
	for i: int in doc.grid.cell_count():
		var k: String = _kind_at(lvl, doc.grid.cell_at(i))
		var prev: int = out.get(k, 0)
		out[k] = prev + 1
	return out


func _terrain_count(doc: MapDocument, t: int) -> int:
	var n: int = 0
	for v: int in doc.level(0).terrain:
		if v == t:
			n += 1
	return n


## La muralla cierra el asentamiento: sin las puertas, desde la plaza no se
## llega al borde del mapa (sin agua, que la deja abierta).
func test_wall_closes_except_gates() -> void:
	for kind: String in GridGeometry.KINDS:
		var res: AldGeneratorG1.Result = _check({"size": "town", "grid": kind, "wall": true}, 31)
		if res == null:
			continue
		var doc: MapDocument = res.doc
		var lvl: MapLevel = doc.level(0)
		var inside: PackedByteArray = _flood(doc, res.plaza_cell, PackedStringArray(["street", "plaza", "bridge", "yard", "garden", "building"]), false)
		for x: int in doc.width():
			for y: int in [0, doc.height() - 1]:
				assert_eq(inside[doc.grid.index_of(Vector2i(x, y))], 0, "%s: se sale sin cruzar una puerta" % kind)
		var gates: int = _zone_counts(doc).get("gate", 0)
		assert_true(gates >= 2, "%s: %d casillas de puerta" % [kind, gates])
		assert_eq(lvl.get_terrain(res.plaza_cell), Terrain.FLOOR)


## Criterio de F3: el código EDI de cada edificio regenera exactamente lo que
## describe el asentamiento (tipo, huella, puerta principal, trasera,
## ventanas y muros del contorno), en las tres rejillas.
func test_child_code_regenerates_same_building() -> void:
	var checked: int = 0
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		i += 1
		var res: AldGeneratorG1.Result = _check({"size": "village", "grid": kind, "style": STYLES[i % 3],
			"prosperity": "rich", "water": "river"}, 0xA1D0 + i)
		if res == null:
			continue
		var lvl: MapLevel = res.doc.level(0)
		for c: MapChild in lvl.children:
			var gen: GeneratorRegistry.Result = GeneratorRegistry.generate(c.seed_code)
			assert_eq(gen.error, "", c.seed_code)
			if gen.doc == null:
				continue
			assert_eq(_child_mismatches(res.doc, c, gen.doc), PackedStringArray(), c.seed_code)
			checked += 1
	assert_true(checked >= 30, "edificios comprobados: %d" % checked)


func _child_mismatches(parent: MapDocument, c: MapChild, edi: MapDocument) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var g: GridGeometry = parent.grid
	var plvl: MapLevel = parent.level(0)
	var elvl: MapLevel = edi.level(c.child_level)
	if edi.scale != "EDI" or edi.grid_kind() != parent.grid_kind():
		out.append("escala o rejilla")
	if Vector2i(edi.width(), edi.height()) != c.rect.size + Vector2i(2, 2):
		out.append("tamaño %dx%d para huella %s" % [edi.width(), edi.height(), c.rect.size])
		return out
	if c.rect.position != c.offset + Vector2i(1, 1):
		out.append("offset")
	# Huella: todo suelo de estancias en EDI.
	for y: int in range(c.rect.position.y, c.rect.end.y):
		for x: int in range(c.rect.position.x, c.rect.end.x):
			var ec: Vector2i = c.to_child_cell(Vector2i(x, y))
			var rr: MapRoom = elvl.room(elvl.get_room_id(ec))
			if elvl.get_terrain(ec) != Terrain.FLOOR or rr == null or rr.kind == MapRoom.KIND_OUTSIDE:
				out.append("hueco en la huella EDI %s" % ec)
	# Contorno: muros, puertas y ventanas idénticos.
	for y2: int in range(c.rect.position.y, c.rect.end.y):
		for x2: int in range(c.rect.position.x, c.rect.end.x):
			var pc: Vector2i = Vector2i(x2, y2)
			for d: int in g.edge_direction_count():
				if c.rect.has_point(g.neighbor(pc, d)):
					continue
				var pv: int = plvl.get_edge(pc, d)
				var ev: int = elvl.get_edge(c.to_child_cell(pc), d)
				if pv != ev:
					out.append("arista %s/%d: aldea %d, EDI %d" % [pc, d, pv, ev])
	# Puerta principal: la zona "entrance" de EDI es la entrada de la aldea.
	var found: bool = false
	for r: MapRoom in elvl.rooms:
		if r.kind == MapRoom.KIND_ENTRANCE:
			var cells: Array[Vector2i] = elvl.room_cells(r.id)
			found = cells.size() == 1 and cells[0] + c.offset == c.entrance
	if not found:
		out.append("entrada distinta")
	return out


## Los parámetros y la semilla de cada edificio salen solo de (parámetros
## del asentamiento, semilla, orden): building_spec aislado da el mismo código
## y cambiar la muralla, el agua o la retícula (que mueven las parcelas) no
## cambia el código de ningún edificio. Así, regenerar o editar un edificio
## no altera a los demás.
func test_buildings_independent() -> void:
	var seed_value: int = 0x5EED5
	var base_params: Dictionary = {"size": "town", "grid": "hex_flat", "style": "dwarf", "prosperity": "poor"}
	var a: AldGeneratorG1.Result = _check(base_params, seed_value)
	var moved_params: Dictionary = base_params.duplicate()
	moved_params["wall"] = true
	moved_params["water"] = "river"
	moved_params["layout"] = "grid"
	var b: AldGeneratorG1.Result = _check(moved_params, seed_value)
	if a == null or b == null:
		return
	var p: AldGeneratorG1.Params = AldGeneratorG1.params_from(SeedCode.parse(_code(base_params, seed_value)))
	var same: int = 0
	for ba: AldGeneratorG1.Building in a.buildings:
		var solo: AldGeneratorG1.Building = AldGeneratorG1.building_spec(p, "DND5", seed_value, ba.order)
		assert_eq(solo.code, ba.code, "orden %d" % ba.order)
		assert_eq(ba.child_seed, SplitMix64.hash64(seed_value, "EDI", ba.order) & AldGeneratorG1.CHILD_SEED_MASK)
		for bb: AldGeneratorG1.Building in b.buildings:
			if bb.order == ba.order:
				assert_eq(bb.code, ba.code, "orden %d con otra muralla/agua/retícula" % ba.order)
				same += 1
	assert_true(same >= 20)
	# Las posiciones sí cambian (otra parcelación), los códigos no.
	assert_ne(a.doc.content_hash(), b.doc.content_hash())


## En hex, la traslación del edificio respeta la paridad offset de la rejilla.
func test_translation_step_and_parity() -> void:
	assert_eq(AldGeneratorG1.translation_step(GridFactory.create("square", 8, 8)), Vector2i(1, 1))
	assert_eq(AldGeneratorG1.translation_step(GridFactory.create("hex_flat", 8, 8)), Vector2i(2, 1))
	assert_eq(AldGeneratorG1.translation_step(GridFactory.create("hex_pointy", 8, 8)), Vector2i(1, 2))
	for kind: String in ["hex_flat", "hex_pointy"]:
		var res: AldGeneratorG1.Result = _build(_code({"grid": kind}, 99))
		if res == null:
			continue
		var step: Vector2i = AldGeneratorG1.translation_step(res.doc.grid)
		for c: MapChild in res.doc.level(0).children:
			assert_eq(posmod(c.offset.x, step.x), 0, kind)
			assert_eq(posmod(c.offset.y, step.y), 0, kind)


func test_seed_changes_output_and_population() -> void:
	var a: AldGeneratorG1.Result = _build(_code({}, 1))
	var b: AldGeneratorG1.Result = _build(_code({}, 2))
	if a == null or b == null:
		return
	assert_ne(a.doc.content_hash(), b.doc.content_hash())
	assert_eq(AldGeneratorG1.population_of(a.doc), a.population)
	assert_true(a.population > 0)
	# Una aldea tiene siempre su taberna, su templo y su herrería (obligatorios).
	var kinds: PackedStringArray = PackedStringArray()
	for c: MapChild in a.doc.level(0).children:
		kinds.append(c.kind)
	for t: String in ["tavern", "temple", "smithy"]:
		assert_true(kinds.has(t), t)


func test_unknown_values_return_null() -> void:
	var p: AldGeneratorG1.Params = AldGeneratorG1.Params.new()
	p.size_id = "metropolis"
	assert_null(AldGeneratorG1.generate_settlement(p, "DND5", Rng.new(1)))


## Los hijos viajan en el JSON canónico y vuelven iguales.
func test_children_serialize() -> void:
	var res: AldGeneratorG1.Result = _build(_code({"size": "hamlet"}, 3))
	if res == null:
		return
	var text: String = res.doc.to_canonical_json()
	assert_true(text.contains("\"children\""))
	var back: MapDocument.LoadResult = MapDocument.from_json(text)
	assert_eq(back.error, "")
	if back.doc == null:
		return
	assert_eq(back.doc.to_canonical_json(), text)
	var c0: MapChild = res.doc.level(0).children[0]
	assert_eq(back.doc.level(0).child_at(c0.rect.position).seed_code, c0.seed_code)
	# Un documento sin hijos no escribe la clave (los hashes de MAZ/EST/EDI no cambian).
	var plain: MapDocument = MapDocument.create("square", 4, 4)
	assert_false(plain.to_canonical_json().contains("children"))


# --- Vistas y pantalla principal ---------------------------------------------------

func test_views_draw_settlement() -> void:
	var res: AldGeneratorG1.Result = _build(_code({"size": "town", "wall": true, "water": "river"}, 12))
	if res == null:
		return
	var t0: int = Time.get_ticks_msec()
	var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
	var root: Node3D = MapMeshBuilder.build_level(res.doc, 0, opts)
	var ms3d: int = Time.get_ticks_msec() - t0
	assert_not_null(root.get_node_or_null("Walls"))
	root.free()
	var view: MapView2D = MapView2D.new()
	add_child_autofree(view)
	view.document = res.doc
	view.queue_redraw()
	await wait_process_frames(1)
	print("ALD_VIEW pueblo %dx%d: 3D construido en %d ms" % [res.doc.width(), res.doc.height(), ms3d])
	# Zonas al aire libre con color propio; la huella no.
	assert_true(MapMeshBuilder.zone_color(MapRoom.KIND_STREET).a > 0.0)
	assert_eq(MapMeshBuilder.zone_color(MapRoom.KIND_BUILDING).a, 0.0)


## La pantalla principal ofrece la escala ALD y genera aleatorias.
func test_main_screen_ald() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var scale_opt: OptionButton = main.get("_scale_opt")
	var scales: Array[String] = main.get("SCALES")
	var ald: int = scales.find("ALD")
	assert_true(ald >= 0)
	assert_eq(scale_opt.get_item_text(ald), "Asentamiento")
	scale_opt.select(ald)
	main.call("_generate_random")
	await wait_process_frames(1)
	var doc: MapDocument = main.get("_doc")
	assert_not_null(doc)
	if doc == null:
		return
	assert_eq(doc.scale, "ALD")
	var status: Label = main.get("_status")
	assert_true(status.text.contains("Aldea"), status.text)
	main.call("_add_token")
	doc = main.get("_doc")
	if not doc.tokens.is_empty():
		var lvl: MapLevel = doc.level(0)
		var r: MapRoom = lvl.room(lvl.get_room_id(doc.tokens[0].cell))
		assert_true(r != null and r.kind == MapRoom.KIND_PLAZA, "la ficha nueva sale en la plaza")


# --- Estadísticas, tiempos, ejemplos y ASCII ----------------------------------------

func test_stats_and_timing() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var worst: int = 0
	var all_placed: int = 0
	var all_wanted: int = 0
	var min_pct: int = 100
	for size: String in SIZES:
		for kind: String in GridGeometry.KINDS:
			var ms_total: int = 0
			var placed: int = 0
			var wanted: int = 0
			var pop: int = 0
			var streets: int = 0
			var runs: int = 3
			for s: int in runs:
				var code: String = _code({"size": size, "grid": kind, "wall": s == 1, "water": ["none", "river", "coast"][s]}, 4200 + s)
				var t0: int = Time.get_ticks_msec()
				var res: AldGeneratorG1.Result = _build(code)
				var ms: int = Time.get_ticks_msec() - t0
				if res == null:
					continue
				ms_total += ms
				worst = maxi(worst, ms)
				placed += res.placed_count()
				wanted += res.buildings.size()
				min_pct = mini(min_pct, res.placed_count() * 100 / maxi(1, res.buildings.size()))
				pop += res.population
				streets += res.street_cells
			all_placed += placed
			all_wanted += wanted
			lines.append("ALD_STATS %s %s: %d/%d edificios, %d hab., %d casillas de calle, %d ms/asentamiento" % [
				size, kind, placed / runs, wanted / runs, pop / runs, streets / runs, ms_total / runs])
	print("\n".join(lines))
	print("ALD_STATS peor caso: %d ms; colocados %d de %d (%d %%), el peor asentamiento %d %%" % [
		worst, all_placed, all_wanted, all_placed * 100 / maxi(1, all_wanted), min_pct])
	# Objetivo: < 2 s en gama media. Margen x2 en el test para no fallar en CI lento.
	assert_true(worst < 4000, "peor caso %d ms" % worst)


func test_print_examples() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for item: Array in [
		[{}, 0x8A1B2C3D4E, "DND5"],
		[{"size": "town", "wall": true, "water": "river"}, 0x9B2C3D4E5F, "DND5"],
		[{"size": "city", "grid": "hex_flat", "style": "dwarf", "wall": true, "prosperity": "rich", "layout": "grid"}, 0xAC3D4E5F60, "PF2E"],
		[{"size": "hamlet", "style": "elf", "water": "coast", "prosperity": "poor"}, 0xBD4E5F6071, "DND5"],
		# Candidatas añadidas para las seeds doradas: hex punta, costa amurallada,
		# retícula en caserío y pueblo, y la combinación de aldea más cargada.
		[{"grid": "hex_pointy", "style": "elf", "water": "river", "prosperity": "rich"}, 0xCE5F607182, "PF2E"],
		[{"size": "town", "style": "dwarf", "wall": true, "water": "coast", "prosperity": "poor"}, 0xDF60718293, "DND5"],
		[{"size": "hamlet", "grid": "hex_flat", "layout": "grid"}, 0xE0718293A4, "DND5"],
		[{"size": "town", "grid": "hex_pointy", "wall": true, "prosperity": "rich", "layout": "grid"}, 0xF18293A4B5, "PF2E"],
	]:
		var params: Dictionary = item[0]
		var seed_value: int = item[1]
		var system: String = item[2]
		var res: AldGeneratorG1.Result = _check(params, seed_value, system)
		if res == null:
			continue
		var code: String = _code(params, seed_value, system)
		var c0: MapChild = res.doc.level(0).children[0]
		lines.append("%s  (%d edificios, %d hab.; p. ej. %s %s)" % [code, res.placed_count(), res.population, c0.kind, c0.seed_code])
	print("ALD_EXAMPLES_BEGIN\n%s\nALD_EXAMPLES_END" % "\n".join(lines))


## ASCII de un asentamiento: ' ' campo, ',' huerto, '#' calle, '=' plaza,
## 'H' puente, 'O' puerta de la muralla, 'X' muralla, '~' agua poco profunda,
## 'W' agua profunda, '.' parcela, '@' entrada de un edificio y, en la huella,
## la inicial del tipo (c casa, T taberna, I posada, S herrería, P tienda,
## E templo, G cuartel).
static func ascii(doc: MapDocument) -> String:
	var lvl: MapLevel = doc.level(0)
	var g: GridGeometry = doc.grid
	var zone_chars: Dictionary[String, String] = {"field": " ", "garden": ",", "street": "#", "plaza": "=", "bridge": "H", "gate": "O", "town_wall": "X", "yard": "."}
	var type_chars: Dictionary[String, String] = {"house": "c", "tavern": "T", "inn": "I", "smithy": "S", "shop": "P", "temple": "E", "guardhouse": "G"}
	var entrances: Dictionary[int, bool] = {}
	for ch: MapChild in lvl.children:
		entrances[g.index_of(ch.entrance)] = true
	var rows: PackedStringArray = PackedStringArray()
	for y: int in g.height:
		var row: String = ""
		for x: int in g.width:
			var c: Vector2i = Vector2i(x, y)
			var t: int = lvl.get_terrain(c)
			if t == Terrain.WATER_DEEP:
				row += "W"
				continue
			if t == Terrain.WATER_SHALLOW:
				row += "~"
				continue
			if entrances.has(g.index_of(c)):
				row += "@"
				continue
			var child: MapChild = lvl.child_at(c)
			if child != null:
				row += type_chars.get(child.kind, "?")
				continue
			var r: MapRoom = lvl.room(lvl.get_room_id(c))
			row += zone_chars.get(r.kind if r != null else "", "?")
		rows.append(row)
	return "\n".join(rows)


func test_print_ascii_samples() -> void:
	for item: Array in [
		[{"size": "hamlet"}, 11],
		[{"size": "village", "water": "river"}, 12],
		[{"size": "town", "wall": true, "water": "coast"}, 13],
		[{"size": "town", "layout": "grid", "wall": true}, 14],
		[{"size": "city"}, 7015],
	]:
		var params: Dictionary = item[0]
		var seed_value: int = item[1]
		var code: String = _code(params, seed_value)
		var res: AldGeneratorG1.Result = _build(code)
		if res != null:
			print("%s\n%s\n" % [code, ascii(res.doc)])
	pass_test("ASCII impreso")
