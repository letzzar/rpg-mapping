extends GutTest
## Regiones REG G1 (hexcrawl independiente) y REG G2 (región de un mundo MUN
## G1), F6, PROYECTO §6.2: esquemas, determinismo, ríos, asentamientos y
## puntos de interés como hijos, caminos, caché del mundo, navegación
## mundo → región → asentamiento y tablas abiertas de encuentros.


static func _reg1(params: Dictionary, seed_value: int) -> String:
	return SeedCode.create("DND5", "REG", 1, params, seed_value).encode()


static func _mun(params: Dictionary, seed_value: int) -> String:
	return SeedCode.create("DND5", "MUN", 1, params, seed_value).encode()


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "", code)
	return res.doc


func _profile(system: String) -> SystemProfile:
	for pid: String in SystemProfile.available_ids():
		var p: SystemProfile = SystemProfile.load_id(pid)
		if p.is_valid() and p.seed_code == system:
			return p
	return null


func test_schemas() -> void:
	var g1: ParamSchema = ParamSchemaRegistry.get_schema("REG", 1)
	var g2: ParamSchema = ParamSchemaRegistry.get_schema("REG", 2)
	var mun: ParamSchema = ParamSchemaRegistry.get_schema("MUN", 1)
	assert_not_null(g1)
	assert_not_null(g2)
	if g1 == null or g2 == null or mun == null:
		return
	assert_eq(g1.field_keys(), PackedStringArray(["width", "height", "grid", "climate", "landscape", "settlements", "pois", "child_grid", "style"]))
	# G2 = los 9 campos de MUN G1, idénticos y en el mismo orden, + los suyos.
	assert_eq(g2.fields.size(), mun.fields.size() + 5)
	for i: int in mun.fields.size():
		var a: ParamSchema.Field = mun.fields[i]
		var b: ParamSchema.Field = g2.fields[i]
		assert_eq([a.kind, a.key, a.min_value, a.max_value, a.default_value, a.capacity, a.ids], [b.kind, b.key, b.min_value, b.max_value, b.default_value, b.capacity, b.ids], a.key)
	assert_eq(PackedStringArray(Array(g2.field_keys()).slice(mun.fields.size())), PackedStringArray(["rx", "ry", "grid", "villages", "pois"]))
	assert_eq(RegGeneratorG2.MUN_FIELDS, mun.field_keys())


func test_g1_deterministic_and_coherent() -> void:
	var variants: Array[Dictionary] = [
		{}, {"grid": "hex_pointy", "landscape": "islands", "climate": "warm"},
		{"landscape": "mountains", "climate": "cold", "width": 40}, {"landscape": "coast", "climate": "arid"},
		{"landscape": "plains", "climate": "wet", "settlements": 10, "pois": 10, "child_grid": "hex_flat", "style": "dwarf"},
	]
	for params: Dictionary in variants:
		var code: String = _reg1(params, 1000 + variants.find(params))
		var doc: MapDocument = _gen(code)
		if doc == null:
			continue
		assert_eq(doc.content_hash(), _gen(code).content_hash(), "determinista " + code)
		var want_grid: String = params.get("grid", "hex_flat")
		var want_w: int = params.get("width", 32)
		assert_eq(doc.grid_kind(), want_grid)
		assert_eq(doc.width(), want_w)
		_check_region(doc, code)


## Comprobaciones comunes de un documento de región.
func _check_region(doc: MapDocument, code: String) -> void:
	var lvl: MapLevel = doc.level(0)
	var g: GridGeometry = doc.grid
	var n: int = g.cell_count()
	assert_eq([lvl.biome.size(), lvl.elevation.size(), lvl.features.size()], [n, n, n], code)
	var bad: int = 0
	for i: int in n:
		var f: int = lvl.features[i]
		var water: bool = Biome.is_water(lvl.biome[i])
		if water and (f & (GeoLayers.RIVER_MASK | GeoLayers.ROAD)) != 0:
			bad += 1
		var d: int = GeoLayers.flow_dir(f)
		if GeoLayers.river_class(f) > 0 and d >= 0:
			var nb: Vector2i = g.neighbor(g.cell_at(i), d)
			if g.in_bounds(nb):
				var j: int = g.index_of(nb)
				if not Biome.is_water(lvl.biome[j]) and GeoLayers.river_class(lvl.features[j]) == 0:
					bad += 1
	assert_eq(bad, 0, "ríos y caminos coherentes " + code)
	var settlements: Array[MapChild] = []
	for ch: MapChild in lvl.children:
		var i: int = g.index_of(ch.rect.position)
		assert_true(i >= 0, code)
		assert_false(Biome.is_water(lvl.biome[i]), "hijo en tierra " + code)
		if ch.kind.begins_with("poi_"):
			assert_true(RegCommon.POI_IDS.has(ch.kind.substr(4)), ch.kind)
			if not ch.seed_code.is_empty():
				var sc: SeedCode = SeedCode.parse(ch.seed_code)
				assert_true(sc.is_valid() and sc.scale == "MAZ", ch.seed_code)
		else:
			var sc2: SeedCode = SeedCode.parse(ch.seed_code)
			assert_true(sc2.is_valid() and sc2.scale == "ALD", ch.seed_code)
			assert_ne(ch.label, "")
			settlements.append(ch)
	# Caminos: los asentamientos de la región quedan unidos por hexágonos de
	# camino (o vecinos de uno) en su mayoría.
	if settlements.size() >= 2:
		var seen: PackedByteArray = PackedByteArray()
		seen.resize(n)
		var queue: Array[Vector2i] = [settlements[0].rect.position]
		seen[g.index_of(queue[0])] = 1
		var head: int = 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for d: int in 6:
				var nb: Vector2i = g.neighbor(c, d)
				var j: int = g.index_of(nb)
				if j < 0 or seen[j] == 1:
					continue
				if GeoLayers.has_road(lvl.features[j]) or lvl.child_at(nb) != null:
					seen[j] = 1
					queue.append(nb)
		# Masa de tierra transitable del primero (sin agua ni hielo).
		var land: PackedByteArray = PackedByteArray()
		land.resize(n)
		var q2: Array[Vector2i] = [settlements[0].rect.position]
		land[g.index_of(q2[0])] = 1
		var h2: int = 0
		while h2 < q2.size():
			var c2: Vector2i = q2[h2]
			h2 += 1
			for d: int in 6:
				var nb2: Vector2i = g.neighbor(c2, d)
				var j2: int = g.index_of(nb2)
				if j2 < 0 or land[j2] == 1:
					continue
				var b2: int = lvl.biome[j2]
				if (not Biome.is_water(b2) and b2 != Biome.ICE) or lvl.child_at(nb2) != null:
					land[j2] = 1
					q2.append(nb2)
		var same: int = 0
		var linked: int = 0
		for ch: MapChild in settlements:
			var si: int = g.index_of(ch.rect.position)
			if land[si] == 1:
				same += 1
				if seen[si] == 1:
					linked += 1
		assert_eq(linked, same, "asentamientos de la misma tierra unidos por caminos " + code)


func test_g1_pois_with_maps_open() -> void:
	var doc: MapDocument = _gen(_reg1({"pois": 10}, 77))
	var opened: int = 0
	for ch: MapChild in doc.level(0).children:
		if ch.kind.begins_with("poi_") and not ch.seed_code.is_empty() and opened < 2:
			var maz: MapDocument = _gen(ch.seed_code)
			assert_not_null(maz)
			opened += 1
	assert_gt(opened, 0)


func test_g2_matches_world_and_ignores_cache() -> void:
	var world_code: String = _mun({"size": "tiny"}, 777)
	var world: MapDocument = _gen(world_code)
	var cities: Array[MapChild] = []
	for ch: MapChild in world.level(0).children:
		if ch.kind == "city":
			cities.append(ch)
	assert_gt(cities.size(), 0)
	var rc: MapChild = RegGeneratorG2.region_child(world, cities[0].rect.position)
	assert_not_null(rc)
	if rc == null:
		return
	assert_lt(rc.id, 0, "id negativo")
	assert_true(rc.rect.has_point(cities[0].rect.position))
	var region: MapDocument = _gen(rc.seed_code)
	if region == null:
		return
	assert_eq(region.grid_kind(), "hex_flat")
	assert_eq([region.width(), region.height()], [37, 24])
	assert_true(region.grid.in_bounds(rc.to_child_cell(rc.entrance)))
	var h: String = region.content_hash()
	MunGeneratorG1.clear_cache()
	assert_eq(_gen(rc.seed_code).content_hash(), h, "no depende de la caché")
	# La ciudad del mundo está en la región con el mismo código y nombre.
	var found: bool = false
	for ch: MapChild in region.level(0).children:
		if ch.seed_code == cities[0].seed_code:
			found = ch.label == cities[0].label
	assert_true(found, "ciudad del mundo en su región")
	_check_region(region, rc.seed_code)
	# El código MUN se recupera de los campos 0-8.
	assert_eq(RegGeneratorG2.world_code(SeedCode.parse(rc.seed_code)).encode(), world_code)
	var pointy: MapChild = RegGeneratorG2.region_child(world, cities[0].rect.position, "hex_pointy")
	var rp: MapDocument = _gen(pointy.seed_code)
	assert_eq([rp.width(), rp.height()], [32, 28])


## Mundo → región → asentamiento → y vuelta, con el grupo.
func test_navigation_world_region_settlement() -> void:
	var prof: SystemProfile = _profile("DND5")
	var world: MapDocument = _gen(_mun({"size": "tiny"}, 4242))
	var city: MapChild = null
	for ch: MapChild in world.level(0).children:
		if ch.kind == "city":
			city = ch
			break
	assert_not_null(city)
	if city == null:
		return
	var t: MapToken = MapToken.new()
	t.id = world.allocate_id()
	t.name = "A"
	t.cell = city.rect.position
	t.side = MapToken.SIDE_PLAYER
	world.add_token(t)
	var nav: MapNavigator = MapNavigator.new()
	nav.open_root(world)
	var rc: MapChild = RegGeneratorG2.region_child(world, city.rect.position)
	var fr: MapNavigator.Frame = nav.enter(rc, 0, prof)
	assert_not_null(fr, nav.error)
	if fr == null:
		return
	assert_eq(fr.doc.scale, "REG")
	assert_eq(fr.doc.tokens.size(), 1)
	assert_eq(world.tokens.size(), 0)
	var here: MapChild = null
	for ch: MapChild in fr.doc.level(0).children:
		if ch.seed_code == city.seed_code:
			here = ch
	assert_not_null(here)
	if here == null:
		return
	var fa: MapNavigator.Frame = nav.enter(here, 0, prof)
	assert_not_null(fa, nav.error)
	if fa == null:
		return
	assert_eq(fa.doc.scale, "ALD")
	assert_eq(fa.doc.tokens.size(), 1)
	nav.back(prof)
	nav.back(prof)
	assert_eq(world.tokens.size(), 1)
	assert_eq(world.tokens[0].cell, city.rect.position)


## Un punto de interés con mazmorra: el grupo entra por la zona "entrance".
func test_navigation_into_dungeon_poi() -> void:
	var prof: SystemProfile = _profile("DND5")
	var region: MapDocument = _gen(_reg1({"pois": 10}, 9))
	var poi: MapChild = null
	for ch: MapChild in region.level(0).children:
		if ch.kind.begins_with("poi_") and not ch.seed_code.is_empty():
			poi = ch
			break
	assert_not_null(poi)
	if poi == null:
		return
	var t: MapToken = MapToken.new()
	t.id = region.allocate_id()
	t.name = "A"
	t.cell = poi.rect.position
	t.side = MapToken.SIDE_PLAYER
	region.add_token(t)
	var nav: MapNavigator = MapNavigator.new()
	nav.open_root(region)
	var fr: MapNavigator.Frame = nav.enter(poi, 0, prof)
	assert_not_null(fr, nav.error)
	if fr == null:
		return
	assert_eq(fr.doc.tokens.size(), 1, "el grupo entra en la mazmorra")
	if fr.doc.tokens.size() == 1:
		assert_true(Terrain.is_passable(fr.doc.level(0).get_terrain(fr.doc.tokens[0].cell)))


func test_encounter_tables() -> void:
	var enc: RegEncounters = RegEncounters.load_default()
	assert_true(enc.is_valid(), enc.error)
	for b: int in Biome.COUNT:
		assert_false(enc.table_for(b).is_empty(), Biome.IDS[b])
	var r1: Rng = Rng.new(5)
	var r2: Rng = Rng.new(5)
	for _k: int in 20:
		assert_eq(enc.roll(Biome.DESERT, r1), enc.roll(Biome.DESERT, r2))


func test_g1_timing() -> void:
	var t0: int = Time.get_ticks_msec()
	_gen(_reg1({"width": 64, "height": 64, "settlements": 10, "pois": 10}, 3))
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("REG G1 64×64: %d ms" % ms)
	assert_lt(ms, 3000)
