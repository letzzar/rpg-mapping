extends GutTest
## Tests de core/model: MapDocument, MapLevel, aristas y serialización
## canónica (ADR 018, ADR 019).


func _doc(kind: String = GridGeometry.KIND_SQUARE, w: int = 6, h: int = 5, levels: int = 1) -> MapDocument:
	var d: MapDocument = MapDocument.create(kind, w, h, levels)
	assert_not_null(d)
	return d


## Documento con algo de todo (contenido y sesión).
func _full_doc(kind: String) -> MapDocument:
	var doc: MapDocument = _doc(kind, 6, 5, 2)
	doc.seed_code = "RPGM1-DND5-MAZ-G1-0-1A-8"
	doc.scale = "MAZ"
	doc.gen_version = 1
	var l0: MapLevel = doc.level(0)
	l0.fill_terrain(Terrain.FLOOR)
	l0.set_terrain(Vector2i(0, 0), Terrain.WALL)
	l0.set_terrain(Vector2i(3, 2), Terrain.RUBBLE)
	l0.set_edge(Vector2i(1, 1), 1, MapEdge.make(MapEdge.KIND_WALL))
	l0.set_edge(Vector2i(2, 3), 0, MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_LOCKED))
	l0.set_edge(Vector2i(0, 4), l0.grid.edge_direction_count() - 1, MapEdge.make(MapEdge.KIND_SECRET_DOOR))
	var room: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_ROOM, "Sala \"del trono\"\n")
	l0.add_room(room)
	for c: Vector2i in [Vector2i(1, 1), Vector2i(2, 1)]:
		l0.set_room_id(c, room.id)
	var table: MapObject = MapObject.new()
	table.id = doc.allocate_id()
	table.catalog_id = "table_long"
	table.cell = Vector2i(2, 2)
	table.size = Vector2i(2, 1)
	table.facing = 1
	table.cover = MapObject.COVER_HALF
	table.blocks_movement = true
	table.height_mm = 750
	l0.add_object(table)
	var stair: MapStair = MapStair.new()
	stair.id = doc.allocate_id()
	stair.cell = Vector2i(5, 4)
	stair.to_level = 1
	stair.to_cell = Vector2i(5, 4)
	l0.add_stair(stair)
	var trap: MapTrap = MapTrap.new()
	trap.id = doc.allocate_id()
	trap.cell = Vector2i(4, 1)
	trap.trap_id = "pit_hidden"
	l0.add_trap(trap)
	doc.level(1).set_terrain(Vector2i(5, 4), Terrain.FLOOR)
	var tok: MapToken = MapToken.new()
	tok.id = doc.allocate_id()
	tok.name = "Ñora"
	tok.cell = Vector2i(1, 2)
	tok.side = MapToken.SIDE_PLAYER
	doc.add_token(tok)
	l0.set_explored("party", Vector2i(1, 2), true)
	doc.deltas.append(MapDelta.make("set_terrain", {"level": 0, "cell": [3, 2], "from": 3, "to": 1}))
	return doc


func test_create_validates() -> void:
	assert_null(MapDocument.create("triangle", 4, 4))
	assert_null(MapDocument.create("square", 4, 4, 0))
	var d: MapDocument = _doc(GridGeometry.KIND_HEX_POINTY, 7, 3, 2)
	assert_eq(d.grid_kind(), GridGeometry.KIND_HEX_POINTY)
	assert_eq(d.width(), 7)
	assert_eq(d.height(), 3)
	assert_eq(d.level_count(), 2)
	assert_null(d.level(2))
	assert_eq(d.level(1).get_terrain(Vector2i(6, 2)), Terrain.VOID)


func test_terrain_set_returns_previous() -> void:
	var l: MapLevel = _doc().level(0)
	assert_eq(l.set_terrain(Vector2i(1, 1), Terrain.FLOOR), Terrain.VOID)
	assert_eq(l.set_terrain(Vector2i(1, 1), Terrain.WATER_DEEP), Terrain.FLOOR)
	assert_eq(l.get_terrain(Vector2i(1, 1)), Terrain.WATER_DEEP)
	assert_eq(l.set_terrain(Vector2i(-1, 1), Terrain.FLOOR), -1)
	assert_eq(l.set_terrain(Vector2i(1, 1), Terrain.COUNT), -1)
	assert_eq(l.get_terrain(Vector2i(99, 99)), Terrain.VOID)


func test_edges_are_shared_between_neighbors() -> void:
	for kind: String in GridGeometry.KINDS:
		var l: MapLevel = _doc(kind).level(0)
		var c: Vector2i = Vector2i(2, 2)
		for d: int in l.grid.edge_direction_count():
			var n: Vector2i = l.grid.neighbor(c, d)
			var wall: int = MapEdge.make(MapEdge.KIND_WALL)
			assert_eq(l.set_edge(c, d, wall), MapEdge.NONE)
			assert_eq(l.get_edge(n, l.grid.opposite(d)), wall, "%s dir %d" % [kind, d])
			assert_eq(l.set_edge(n, l.grid.opposite(d), MapEdge.NONE), wall)
			assert_eq(l.edge_count(), 0)
	var sq: MapLevel = _doc().level(0)
	assert_eq(sq.set_edge(Vector2i(1, 1), 0, 0x200), -1, "valor no válido")
	assert_eq(sq.set_edge(Vector2i(1, 1), 0, MapEdge.make(MapEdge.KIND_WALL, MapEdge.FLAG_OPEN)), -1, "banderas en un muro")
	# Ids ordenados aunque se inserten desordenados.
	sq.set_edge(Vector2i(4, 4), 1, MapEdge.make(MapEdge.KIND_WALL))
	sq.set_edge(Vector2i(0, 0), 0, MapEdge.make(MapEdge.KIND_WALL))
	sq.set_edge(Vector2i(2, 1), 1, MapEdge.make(MapEdge.KIND_ARCH))
	var ids: PackedInt64Array = sq.edge_ids()
	assert_eq(ids.size(), 3)
	assert_true(ids[0] < ids[1] and ids[1] < ids[2])


func test_edge_blocking_rules() -> void:
	var wall: int = MapEdge.make(MapEdge.KIND_WALL)
	var door: int = MapEdge.make(MapEdge.KIND_DOOR)
	var locked: int = MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_LOCKED)
	var open_door: int = MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_OPEN)
	var secret: int = MapEdge.make(MapEdge.KIND_SECRET_DOOR)
	var found: int = MapEdge.with_flag(secret, MapEdge.FLAG_DISCOVERED, true)
	var arch: int = MapEdge.make(MapEdge.KIND_ARCH)
	assert_true(MapEdge.blocks_movement(wall) and MapEdge.blocks_sight(wall))
	# Cualquier puerta cerrada bloquea la ruta automática (ADR 020).
	assert_true(MapEdge.blocks_movement(door))
	assert_true(MapEdge.blocks_sight(door))
	assert_true(MapEdge.blocks_movement(locked))
	assert_false(MapEdge.blocks_movement(open_door) or MapEdge.blocks_sight(open_door))
	assert_true(MapEdge.blocks_movement(secret) and MapEdge.blocks_sight(secret))
	assert_true(MapEdge.blocks_movement(found))
	assert_true(MapEdge.blocks_sight(found))
	var found_open: int = MapEdge.with_flag(found, MapEdge.FLAG_OPEN, true)
	assert_false(MapEdge.blocks_movement(found_open) or MapEdge.blocks_sight(found_open))
	# Pero todas son franqueables para la conectividad; el muro no.
	for v: int in [door, locked, secret, found, arch, MapEdge.NONE]:
		assert_true(MapEdge.is_traversable(v))
	assert_false(MapEdge.is_traversable(wall))
	assert_false(MapEdge.blocks_movement(arch) or MapEdge.blocks_sight(arch))
	assert_false(MapEdge.blocks_movement(MapEdge.NONE))
	assert_true(MapEdge.is_valid(found))
	assert_false(MapEdge.is_valid(MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_DISCOVERED)))
	# Ventana (F3): tipo 5, bloquea el paso y la conectividad pero no la vista.
	var window: int = MapEdge.make(MapEdge.KIND_WINDOW)
	assert_eq(window, 5)
	assert_true(MapEdge.is_valid(window))
	assert_true(MapEdge.blocks_movement(window))
	assert_false(MapEdge.blocks_sight(window))
	assert_false(MapEdge.is_traversable(window))
	assert_false(MapEdge.is_valid(MapEdge.make(MapEdge.KIND_WINDOW, MapEdge.FLAG_OPEN)), "banderas en una ventana")
	assert_false(MapEdge.is_valid(6))


func test_rooms_objects_and_ids() -> void:
	var doc: MapDocument = _doc()
	var l: MapLevel = doc.level(0)
	assert_eq(doc.allocate_id(), 1)
	assert_eq(doc.allocate_id(), 2)
	assert_eq(doc.peek_next_id(), 3)
	assert_true(l.add_room(MapRoom.make(7, MapRoom.KIND_CAVE)))
	assert_true(l.add_room(MapRoom.make(3, MapRoom.KIND_CORRIDOR)))
	assert_false(l.add_room(MapRoom.make(3, MapRoom.KIND_ROOM)), "id repetido")
	assert_eq(l.rooms[0].id, 3)
	assert_eq(l.room(7).kind, MapRoom.KIND_CAVE)
	l.set_room_id(Vector2i(1, 0), 7)
	l.set_room_id(Vector2i(0, 1), 7)
	var cells: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	assert_eq(l.room_cells(7), cells)
	assert_eq(l.remove_room(3).id, 3)
	assert_null(l.remove_room(3))
	var o: MapObject = MapObject.new()
	o.id = 5
	o.cell = Vector2i(1, 1)
	o.size = Vector2i(3, 1)
	assert_true(l.add_object(o))
	assert_eq(l.object_cells(o).size(), 3)
	assert_eq(l.objects_at(Vector2i(3, 1)).size(), 1)
	# Girado 90º en la cuadrada: 1×3 en vertical.
	o.facing = 1
	var rotated: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	assert_eq(l.object_cells(o), rotated)
	assert_eq(l.objects_at(Vector2i(3, 1)).size(), 0)
	assert_eq(l.remove_object(5), o)
	assert_eq(l.objects.size(), 0)


func test_movement_mask() -> void:
	var l: MapLevel = _doc().level(0)
	l.fill_terrain(Terrain.FLOOR)
	l.set_terrain(Vector2i(0, 0), Terrain.WALL)
	l.set_terrain(Vector2i(1, 0), Terrain.RUBBLE)
	var crate: MapObject = MapObject.new()
	crate.id = 1
	crate.cell = Vector2i(2, 0)
	crate.blocks_movement = true
	l.add_object(crate)
	var bush: MapObject = MapObject.new()
	bush.id = 2
	bush.cell = Vector2i(3, 0)
	bush.difficult_terrain = true
	l.add_object(bush)
	var m: PackedByteArray = l.movement_mask()
	assert_eq(m[0], 0)
	assert_eq(m[1], MapLevel.MOVE_PASSABLE | MapLevel.MOVE_DIFFICULT)
	assert_eq(m[2], 0)
	assert_eq(m[3], MapLevel.MOVE_PASSABLE | MapLevel.MOVE_DIFFICULT)
	assert_eq(m[4], MapLevel.MOVE_PASSABLE)


func test_tokens_and_footprint() -> void:
	var doc: MapDocument = _doc()
	var p: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var ogre: MapToken = MapToken.new()
	ogre.id = doc.allocate_id()
	ogre.cell = Vector2i(1, 1)
	ogre.size_id = "large"
	assert_true(doc.add_token(ogre))
	assert_false(doc.add_token(ogre))
	assert_eq(doc.token_cells(ogre, p).size(), 4)
	var expected: Array[MapToken] = [ogre]
	assert_eq(doc.tokens_at(0, Vector2i(2, 2), p), expected)
	assert_eq(doc.tokens_at(1, Vector2i(2, 2), p).size(), 0)
	assert_eq(doc.remove_token(ogre.id), ogre)


func test_fog_placeholder() -> void:
	var l: MapLevel = _doc().level(0)
	assert_false(l.is_explored("party", Vector2i(1, 1)))
	assert_false(l.set_explored("party", Vector2i(1, 1), true))
	assert_true(l.is_explored("party", Vector2i(1, 1)))
	assert_eq(l.fog_viewers(), PackedStringArray(["party"]))
	l.clear_fog("party")
	assert_eq(l.fog_viewers().size(), 0)


func test_notify_changed_emits() -> void:
	var doc: MapDocument = _doc()
	watch_signals(doc)
	doc.notify_changed(0, MapDocument.LAYER_TERRAIN)
	assert_signal_emitted_with_parameters(doc, "changed", [0, MapDocument.LAYER_TERRAIN])
	assert_eq(doc.revision, 1)


# --- Serialización canónica -------------------------------------------------

func test_canonical_json_format() -> void:
	var v: Dictionary = {"b": 1, "a": [true, null, -3], "c": "x\"y\\z\n", "ñ": PackedByteArray([0, 255])}
	assert_eq(CanonicalJson.stringify(v), '{"a":[true,null,-3],"b":1,"c":"x\\"y\\\\z\\u000a","ñ":[0,255]}')
	assert_eq(CanonicalJson.stringify({}), "{}")
	# SHA-256 de "{}" (vector conocido).
	assert_eq(CanonicalJson.sha256({}), "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
	assert_false(CanonicalJson.is_supported({"x": 1.5}), "float prohibido")
	assert_false(CanonicalJson.is_supported([Vector2i(1, 2)]))
	assert_false(CanonicalJson.is_supported({1: 2}), "claves no texto")
	assert_eq(CanonicalJson.stringify({"x": 1.5}), "")


## Formato exacto de un documento pequeño: congela el esquema del JSON
## canónico (si cambia, cambian todas las seeds doradas).
func test_document_canonical_text_is_frozen() -> void:
	var doc: MapDocument = _doc(GridGeometry.KIND_SQUARE, 2, 1)
	var l: MapLevel = doc.level(0)
	l.set_terrain(Vector2i(0, 0), Terrain.FLOOR)
	l.set_terrain(Vector2i(1, 0), Terrain.WALL)
	l.set_edge(Vector2i(0, 0), 1, MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_LOCKED))
	var room: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_ROOM, "Sala A")
	l.add_room(room)
	l.set_room_id(Vector2i(0, 0), room.id)
	var content: String = '{"grid":{"height":1,"kind":"square","width":2},' \
		+ '"levels":[{"edges":[[0,0,1,34]],"objects":[],"room_ids":[1,0],' \
		+ '"rooms":[{"id":1,"kind":"room","label":"Sala A"}],"stairs":[],"terrain":[1,2],"traps":[]}],' \
		+ '"next_id":2,"schema_version":1,"source":{"gen":0,"scale":"","seed_code":""}}'
	assert_eq(doc.to_canonical_json(false), content)
	var full: String = content.replace('"schema_version":1,', '"schema_version":1,"session":{"deltas":[],"fog":[{}],"tokens":[]},')
	assert_eq(doc.to_canonical_json(true), full)
	assert_eq(doc.content_hash(), content.sha256_text())


func test_roundtrip_all_grids() -> void:
	for kind: String in GridGeometry.KINDS:
		var doc: MapDocument = _full_doc(kind)
		var text: String = doc.to_canonical_json()
		assert_false(text.is_empty(), kind)
		var res: MapDocument.LoadResult = MapDocument.from_json(text)
		assert_eq(res.error, "", kind)
		if res.doc == null:
			continue
		assert_eq(res.doc.to_canonical_json(), text, kind)
		assert_eq(res.doc.full_hash(), doc.full_hash())
		assert_eq(res.doc.content_hash(), doc.content_hash())
		assert_eq(res.doc.level(0).room(1).label, "Sala \"del trono\"\n")
		assert_eq(res.doc.token(5).name, "Ñora")
		# Los números del JSON llegan como float y se normalizan a int.
		var delta_cell: Array = res.doc.deltas[0].data["cell"]
		assert_eq(delta_cell, [3, 2])
		var first: int = delta_cell[0]
		assert_eq(first, 3)


func test_session_does_not_change_content_hash() -> void:
	var doc: MapDocument = _full_doc(GridGeometry.KIND_SQUARE)
	var content: String = doc.content_hash()
	var full: String = doc.full_hash()
	doc.token(5).cell = Vector2i(4, 4)
	doc.level(0).set_explored("party", Vector2i(4, 4), true)
	assert_eq(doc.content_hash(), content)
	assert_ne(doc.full_hash(), full)
	doc.level(0).set_terrain(Vector2i(4, 4), Terrain.PIT)
	assert_ne(doc.content_hash(), content)


func test_same_steps_same_hash() -> void:
	assert_eq(_full_doc(GridGeometry.KIND_HEX_FLAT).content_hash(), _full_doc(GridGeometry.KIND_HEX_FLAT).content_hash())
	assert_ne(_full_doc(GridGeometry.KIND_HEX_FLAT).content_hash(), _full_doc(GridGeometry.KIND_HEX_POINTY).content_hash())


func test_from_json_rejects_bad_input() -> void:
	assert_ne(MapDocument.from_json("[]").error, "")
	assert_ne(MapDocument.from_json("{}").error, "")
	var text: String = _full_doc(GridGeometry.KIND_SQUARE).to_canonical_json()
	assert_ne(MapDocument.from_json(text.replace('"kind":"square"', '"kind":"triangle"')).error, "")
	assert_ne(MapDocument.from_json(text.replace('"terrain":[2,', '"terrain":[2.5,')).error, "")
	assert_ne(MapDocument.from_json(text.replace('"terrain":[2,', '"terrain":[99,')).error, "")
