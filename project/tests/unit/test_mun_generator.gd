extends GutTest
## Mundo MUN G1 (F6, PROYECTO §6.1): esquema, determinismo, coherencia de
## capas, ríos, reinos, asentamientos (hijos ALD), caminos, serialización y
## el criterio de F6 (2048×1024 en < 10 s).

static func _code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	return SeedCode.create(system, "MUN", 1, params, seed_value).encode()


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "", code)
	return res.doc


func _result(params: Dictionary, seed_value: int) -> MunGeneratorG1.Result:
	var sc: SeedCode = SeedCode.parse(_code(params, seed_value))
	return MunGeneratorG1.generate_world(MunGeneratorG1.params_from(sc), "DND5", Rng.new(sc.seed_value))


func test_schema() -> void:
	var s: ParamSchema = ParamSchemaRegistry.get_schema("MUN", 1)
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.field_keys(), PackedStringArray(["size", "land_pct", "kingdoms", "climate", "plates", "rivers", "settlements", "child_grid", "style"]))
	assert_eq(_code({}, 42), "RPGM1-DND5-MUN-G1-0-1A-" + SeedCode.check_char("RPGM1-DND5-MUN-G1-0-1A"))
	var full: Dictionary = {"size": "small", "land_pct": 50, "kingdoms": 3, "climate": "arid", "plates": 20, "rivers": 9, "settlements": 2, "child_grid": "hex_pointy", "style": "elf"}
	var sc: SeedCode = SeedCode.parse(_code(full, 1234567))
	assert_true(sc.is_valid())
	for k: String in full:
		assert_eq(str(sc.params[k]), str(full[k]), k)


func test_deterministic_and_seed_sensitive() -> void:
	var a: String = _code({"size": "tiny"}, 11)
	var h1: String = _gen(a).content_hash()
	MunGeneratorG1.clear_cache()
	assert_eq(_gen(a).content_hash(), h1)
	assert_ne(_gen(_code({"size": "tiny"}, 12)).content_hash(), h1)
	assert_ne(_gen(_code({"size": "tiny", "land_pct": 50}, 11)).content_hash(), h1)


func test_layers_are_coherent() -> void:
	for params: Dictionary in [{"size": "tiny"}, {"size": "small", "climate": "wet", "land_pct": 55}, {"size": "tiny", "climate": "cold", "rivers": 10}]:
		var res: MunGeneratorG1.Result = _result(params, 99)
		var doc: MapDocument = res.doc
		var lvl: MapLevel = doc.level(0)
		var n: int = doc.width() * doc.height()
		assert_eq(doc.grid_kind(), "square")
		assert_eq([lvl.biome.size(), lvl.elevation.size(), lvl.features.size()], [n, n, n])
		var land: int = 0
		var bad: int = 0
		for i: int in n:
			var b: int = lvl.biome[i]
			var e: int = lvl.elevation[i]
			var t: int = lvl.terrain[i]
			var water: bool = Biome.is_water(b)
			if water != (t == Terrain.WATER_DEEP or t == Terrain.WATER_SHALLOW):
				bad += 1
			if Biome.is_sea(b) and e >= GeoLayers.SEA_LEVEL:
				bad += 1
			if not water and e < GeoLayers.SEA_LEVEL:
				bad += 1
			if not water:
				land += 1
			if water and lvl.features[i] != 0:
				bad += 1
			if water and lvl.room_ids[i] != 0:
				bad += 1
		assert_eq(bad, 0, "capas incoherentes %s" % str(params))
		# % de tierra (lagos aparte) cerca del pedido.
		var want: int = params.get("land_pct", 35)
		var got: int = land * 100 / n
		assert_almost_eq(got, want, 4, "tierra %s" % str(params))


## Toda cadena de río baja hasta el mar, un lago o el borde, sin ciclos.
func test_rivers_flow_to_water() -> void:
	var res: MunGeneratorG1.Result = _result({"size": "small"}, 7)
	var lvl: MapLevel = res.doc.level(0)
	var w: int = res.doc.width()
	var h: int = res.doc.height()
	assert_gt(res.river_cells, 100, "hay ríos")
	assert_gt(res.lake_cells, 0, "hay lagos")
	var broken: int = 0
	var checked: int = 0
	for i: int in w * h:
		var f: int = lvl.features[i]
		if GeoLayers.river_class(f) == 0:
			continue
		checked += 1
		var c: Vector2i = Vector2i(i % w, i / w)
		var steps: int = 0
		while steps < w * 4:
			var d: int = GeoLayers.flow_dir(lvl.features[c.y * w + c.x])
			if d < 0:
				break
			var nx: Vector2i = c + SquareGrid.DIRS[d]
			nx.x = posmod(nx.x, w)
			if nx.y < 0 or nx.y >= h:
				break
			var j: int = nx.y * w + nx.x
			if Biome.is_water(lvl.biome[j]):
				break
			if GeoLayers.river_class(lvl.features[j]) == 0:
				broken += 1
				break
			c = nx
			steps += 1
		if steps >= w * 4:
			broken += 1
		if checked >= 400:
			break
	assert_eq(broken, 0, "ríos que no llegan al agua")


func test_kingdoms_and_settlements() -> void:
	var res: MunGeneratorG1.Result = _result({"size": "small", "kingdoms": 8}, 31)
	var doc: MapDocument = res.doc
	var lvl: MapLevel = doc.level(0)
	assert_eq(res.kingdoms, 8)
	var kingdom_rooms: Dictionary[int, int] = {}
	for r: MapRoom in lvl.rooms:
		assert_eq(r.kind, "kingdom")
		assert_ne(r.label, "")
		kingdom_rooms[r.id] = 0
	for i: int in lvl.room_ids.size():
		var k: int = lvl.room_ids[i]
		if k != 0:
			assert_true(kingdom_rooms.has(k))
			kingdom_rooms[k] += 1
	for k: int in kingdom_rooms:
		assert_gt(kingdom_rooms[k], 50, "reino con territorio")
	assert_gt(lvl.children.size(), 40)
	var cities: int = 0
	for ch: MapChild in lvl.children:
		var sc: SeedCode = SeedCode.parse(ch.seed_code)
		assert_true(sc.is_valid() and sc.scale == "ALD" and sc.gen_version == 1, ch.seed_code)
		assert_eq(sc.encode(), ch.seed_code, "canónico")
		assert_true(["hamlet", "village", "town", "city"].has(ch.kind))
		var size_id: String = sc.params["size"]
		assert_eq(size_id, ch.kind)
		assert_ne(ch.label, "")
		var i: int = doc.grid.index_of(ch.rect.position)
		assert_false(Biome.is_water(lvl.biome[i]), "en tierra")
		assert_eq(ch.room_id, lvl.room_ids[i])
		if ch.kind == "city":
			cities += 1
	assert_gte(cities, 8, "una capital por reino")


## El hijo ALD se regenera desde su código y la casilla de llegada cae dentro.
func test_settlement_child_enters_ald() -> void:
	var doc: MapDocument = _result({"size": "tiny"}, 5).doc
	var kinds: Dictionary[String, bool] = {}
	for ch: MapChild in doc.level(0).children:
		if kinds.has(ch.kind):
			continue
		kinds[ch.kind] = true
		var ald: MapDocument = _gen(ch.seed_code)
		var target: Vector2i = ch.to_child_cell(ch.entrance)
		assert_eq(target, Vector2i(ald.width() / 2, ald.height() / 2), ch.seed_code)
		assert_true(ald.grid.in_bounds(target))


func test_roads_reach_settlements() -> void:
	var res: MunGeneratorG1.Result = _result({"size": "small"}, 21)
	var lvl: MapLevel = res.doc.level(0)
	var w: int = res.doc.width()
	assert_gt(res.roads_built, res.roads_failed * 4, "casi todos los caminos")
	var near: int = 0
	for ch: MapChild in lvl.children:
		var found: bool = false
		for oy: int in range(-3, 4):
			for ox: int in range(-3, 4):
				var c: Vector2i = ch.rect.position + Vector2i(ox, oy)
				if res.doc.grid.in_bounds(c) and GeoLayers.has_road(lvl.features[c.y * w + c.x]):
					found = true
		if found:
			near += 1
	assert_gt(near * 100 / maxi(1, lvl.children.size()), 80, "asentamientos con camino")


func test_serialization_round_trip() -> void:
	var doc: MapDocument = _gen(_code({"size": "tiny"}, 3))
	var lr: MapDocument.LoadResult = MapDocument.from_json(doc.to_canonical_json())
	assert_eq(lr.error, "")
	if lr.doc != null:
		assert_eq(lr.doc.content_hash(), doc.content_hash())
		assert_eq(lr.doc.level(0).children[0].label, doc.level(0).children[0].label)
	# Un mapa táctico no lleva capas geográficas (su hash no cambia).
	var maz: MapDocument = _gen("RPGM1-DND5-MAZ-G1-0-1A-" + SeedCode.check_char("RPGM1-DND5-MAZ-G1-0-1A"))
	var d: Dictionary = maz.level(0).content_to_dict()
	assert_false(d.has("biome") or d.has("elevation") or d.has("features"))


func test_units_scale() -> void:
	assert_eq(Units.scale_cell_mm("MUN", 2048, 5), 20_000_000)
	assert_eq(Units.scale_cell_mm("MUN", 256, 5), 160_000_000)
	assert_eq(Units.scale_cell_mm("REG", 37, 5), 10_000_000)
	assert_eq(Units.scale_cell_mm("REG", 37, 5, Units.Mode.EXACT), 6 * 1_609_344)
	assert_eq(Units.scale_cell_mm("ALD", 100, 5), 1500)
	assert_eq(MunGeneratorG1.cell_mm(2048), 20_000_000)
	assert_eq(RegCommon.cell_mm(), 10_000_000)


## Criterio de F6: mundo 2048×1024 en menos de 10 s (escritorio).
func test_large_world_under_10_s() -> void:
	var code: String = _code({}, 0xC0FFEE)
	var t0: int = Time.get_ticks_msec()
	var doc: MapDocument = _gen(code)
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("MUN large 2048×1024: %d ms" % ms)
	assert_not_null(doc)
	if doc == null:
		return
	assert_eq([doc.width(), doc.height()], [2048, 1024])
	assert_lt(ms, 10000, "F6: < 10 s")
	assert_gt(doc.level(0).children.size(), 80)
