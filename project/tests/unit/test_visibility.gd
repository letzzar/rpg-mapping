extends GutTest
## Línea de visión, luz, casillas visibles y exploración (ADR 024).


func _room(kind: String = "square", w: int = 9, h: int = 7) -> MapDocument:
	var d: MapDocument = MapDocument.create(kind, w, h)
	d.level(0).fill_terrain(Terrain.FLOOR)
	return d


func test_open_floor_has_los_everywhere() -> void:
	for kind: String in GridGeometry.KINDS:
		var d: MapDocument = _room(kind)
		var lvl: MapLevel = d.level(0)
		assert_true(Visibility.has_los(lvl, Vector2i(0, 0), Vector2i(8, 6)), kind)
		assert_true(Visibility.has_los(lvl, Vector2i(8, 0), Vector2i(0, 6)), kind)


func test_wall_cell_blocks_but_is_itself_visible() -> void:
	for kind: String in GridGeometry.KINDS:
		var d: MapDocument = _room(kind)
		var lvl: MapLevel = d.level(0)
		lvl.set_terrain(Vector2i(4, 3), Terrain.WALL)
		assert_false(Visibility.has_los(lvl, Vector2i(2, 3), Vector2i(6, 3)), kind)
		assert_true(Visibility.has_los(lvl, Vector2i(2, 3), Vector2i(4, 3)), "%s: se ve la cara del muro" % kind)


func test_edges_doors_and_symmetry() -> void:
	for kind: String in GridGeometry.KINDS:
		var d: MapDocument = _room(kind)
		var lvl: MapLevel = d.level(0)
		var a: Vector2i = Vector2i(3, 3)
		var east: int = -1
		for dir: int in d.grid.edge_direction_count():
			if d.grid.neighbor(a, dir).x == 4 and d.grid.neighbor(a, dir).y == 3:
				east = dir
		assert_true(east >= 0, kind)
		var b: Vector2i = Vector2i(4, 3)
		var id: int = d.grid.edge_id(a, east)
		lvl.set_edge_by_id(id, MapEdge.make(MapEdge.KIND_WALL))
		assert_false(Visibility.has_los(lvl, a, b), "%s: muro fino" % kind)
		lvl.set_edge_by_id(id, MapEdge.make(MapEdge.KIND_DOOR))
		assert_false(Visibility.has_los(lvl, a, b), "%s: puerta cerrada" % kind)
		lvl.set_edge_by_id(id, MapEdge.with_flag(MapEdge.make(MapEdge.KIND_DOOR), MapEdge.FLAG_OPEN, true))
		assert_true(Visibility.has_los(lvl, a, b), "%s: puerta abierta" % kind)
		assert_true(Visibility.has_los(lvl, b, a), "%s: simétrica" % kind)


func test_square_diagonal_corner_rule() -> void:
	var d: MapDocument = _room()
	var lvl: MapLevel = d.level(0)
	# (2,2) -> (3,1): rodeos por (2,1) y (3,2).
	lvl.set_terrain(Vector2i(2, 1), Terrain.WALL)
	assert_true(Visibility.has_los(lvl, Vector2i(2, 2), Vector2i(3, 1)), "un rodeo libre basta")
	lvl.set_terrain(Vector2i(3, 2), Terrain.WALL)
	assert_false(Visibility.has_los(lvl, Vector2i(2, 2), Vector2i(3, 1)), "esquina cerrada")


func test_los_is_symmetric_on_generated_maps() -> void:
	for code: String in ["RPGM1-DND5-MAZ-G1-0-HWX23H6N-W", "RPGM1-PF2E-MAZ-G1-80-PK2XDSZR-5",
			"RPGM1-DND5-MAZ-G1-WKA0G0-W7HE7S75-0"]:
		var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
		assert_not_null(res.doc, code)
		if res.doc == null:
			continue
		var lvl: MapLevel = res.doc.level(0)
		var g: GridGeometry = res.doc.grid
		var rng: Rng = Rng.new(7, 1)
		for k: int in 300:
			var a: Vector2i = Vector2i(rng.bounded(g.width), rng.bounded(g.height))
			var b: Vector2i = Vector2i(rng.bounded(g.width), rng.bounded(g.height))
			assert_eq(Visibility.has_los(lvl, a, b), Visibility.has_los(lvl, b, a), "%s %s %s" % [code, a, b])


func test_light_map_radii_and_shadow() -> void:
	var d: MapDocument = _room("square", 15, 3)
	var lvl: MapLevel = d.level(0)
	var lights: Array[Visibility.LightSource] = [Visibility.LightSource.make(Vector2i(2, 1), 2, 4)]
	var lm: PackedByteArray = Visibility.light_map(lvl, lights, false)
	var g: GridGeometry = d.grid
	assert_eq(lm[g.index_of(Vector2i(4, 1))], Visibility.BRIGHT)
	assert_eq(lm[g.index_of(Vector2i(6, 1))], Visibility.DIM)
	assert_eq(lm[g.index_of(Vector2i(7, 1))], Visibility.DARK)
	lvl.set_terrain(Vector2i(3, 0), Terrain.WALL)
	lvl.set_terrain(Vector2i(3, 1), Terrain.WALL)
	lvl.set_terrain(Vector2i(3, 2), Terrain.WALL)
	lm = Visibility.light_map(lvl, lights, false)
	assert_eq(lm[g.index_of(Vector2i(4, 1))], Visibility.DARK, "el muro hace sombra")
	var lit: PackedByteArray = Visibility.light_map(lvl, lights, true)
	assert_eq(lit[g.index_of(Vector2i(10, 1))], Visibility.BRIGHT, "ambiente iluminado")


func test_visible_needs_light_or_darkvision() -> void:
	var d: MapDocument = _room("square", 15, 3)
	var lvl: MapLevel = d.level(0)
	var g: GridGeometry = d.grid
	var v: Visibility.Viewer = Visibility.Viewer.new()
	v.cells = [Vector2i(0, 1)]
	var viewers: Array[Visibility.Viewer] = [v]
	var dark: PackedByteArray = Visibility.light_map(lvl, [], false)
	var vis: PackedByteArray = Visibility.visible_map(lvl, viewers, dark)
	assert_eq(vis[g.index_of(Vector2i(3, 1))], 0, "a oscuras no se ve")
	v.darkvision_cells = 4
	vis = Visibility.visible_map(lvl, viewers, dark)
	assert_eq(vis[g.index_of(Vector2i(3, 1))], Visibility.DIM, "visión en la oscuridad")
	assert_eq(vis[g.index_of(Vector2i(6, 1))], 0)
	var lights: Array[Visibility.LightSource] = [Visibility.LightSource.make(Vector2i(12, 1), 1, 2)]
	vis = Visibility.visible_map(lvl, viewers, Visibility.light_map(lvl, lights, false))
	assert_eq(vis[g.index_of(Vector2i(12, 1))], Visibility.BRIGHT, "se ve una luz lejana")


func test_party_vision_and_explore_undo_with_move() -> void:
	var d: MapDocument = _room("square", 15, 3)
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.side = MapToken.SIDE_PLAYER
	t.cell = Vector2i(0, 1)
	var s: CommandStack = CommandStack.new(d)
	s.execute(AddTokenCommand.new(t))
	var hash_before: String = d.content_hash()
	var opts: PartyVision.Options = PartyVision.Options.new()
	opts.carried_bright = 2
	opts.carried_dim = 4
	var profile: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var r: PartyVision.Result = PartyVision.compute(d, 0, profile, opts)
	assert_eq(r.viewer_count, 1)
	assert_true(s.execute_attached(ExploreCommand.from_visible(d, 0, PartyVision.VIEWER_PARTY, r.visible)))
	assert_true(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(4, 1)))
	assert_false(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(8, 1)))
	# Mover y explorar como un solo paso.
	assert_true(s.execute(MoveTokenCommand.new(t.id, Vector2i(6, 1), 0)))
	r = PartyVision.compute(d, 0, profile, opts)
	assert_true(s.execute_attached(ExploreCommand.from_visible(d, 0, PartyVision.VIEWER_PARTY, r.visible)))
	assert_true(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(10, 1)))
	assert_eq(d.content_hash(), hash_before, "la niebla es sesión: no cambia el hash de contenido")
	assert_eq(s.undo_label_key(), "CMD_MOVE_TOKEN")
	s.undo()
	assert_eq(d.token(t.id).cell, Vector2i(0, 1))
	assert_false(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(10, 1)), "deshacer tapa lo descubierto")
	assert_true(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(4, 1)))
	s.redo()
	assert_eq(d.token(t.id).cell, Vector2i(6, 1))
	assert_true(d.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(10, 1)))
