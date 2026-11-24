extends GutTest
## Tests de los comandos de la vista (mover ficha, puertas, añadir ficha) y
## comprobación de que la vista 2D y la pantalla principal compilan y se
## construyen sin errores.


func _doc(kind: String = "square") -> MapDocument:
	var d: MapDocument = MapDocument.create(kind, 6, 4)
	d.level(0).fill_terrain(Terrain.FLOOR)
	return d


func _token(d: MapDocument, cell: Vector2i) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.cell = cell
	t.side = MapToken.SIDE_PLAYER
	return t


func test_add_and_move_token_with_undo() -> void:
	var d: MapDocument = _doc()
	var s: CommandStack = CommandStack.new(d)
	var t: MapToken = _token(d, Vector2i(0, 0))
	assert_true(s.execute(AddTokenCommand.new(t)))
	assert_eq(d.tokens.size(), 1)
	assert_true(s.execute(MoveTokenCommand.new(t.id, Vector2i(3, 2), 0)))
	assert_eq(d.token(t.id).cell, Vector2i(3, 2))
	assert_eq(d.deltas.size(), 2)
	s.undo()
	assert_eq(d.token(t.id).cell, Vector2i(0, 0))
	assert_eq(d.deltas.size(), 1)
	s.undo()
	assert_eq(d.tokens.size(), 0)
	assert_eq(d.deltas.size(), 0)
	s.redo()
	s.redo()
	assert_eq(d.token(t.id).cell, Vector2i(3, 2))


func test_move_rejects_out_of_bounds_and_noop() -> void:
	var d: MapDocument = _doc()
	var s: CommandStack = CommandStack.new(d)
	var t: MapToken = _token(d, Vector2i(1, 1))
	s.execute(AddTokenCommand.new(t))
	assert_false(s.execute(MoveTokenCommand.new(t.id, Vector2i(99, 0), 0)))
	assert_false(s.execute(MoveTokenCommand.new(t.id, Vector2i(1, 1), 0)))
	assert_false(s.execute(MoveTokenCommand.new(t.id, Vector2i(2, 1), 5)))
	assert_eq(d.token(t.id).cell, Vector2i(1, 1))


func test_toggle_door_open_and_undo() -> void:
	for kind: String in GridGeometry.KINDS:
		var d: MapDocument = _doc(kind)
		var lvl: MapLevel = d.level(0)
		var edge: int = d.grid.edge_id(Vector2i(2, 1), 0)
		lvl.set_edge_by_id(edge, MapEdge.make(MapEdge.KIND_DOOR))
		var s: CommandStack = CommandStack.new(d)
		assert_true(s.execute(SetEdgeCommand.toggle_flag(d, 0, edge, MapEdge.FLAG_OPEN)), kind)
		assert_true(MapEdge.has_flag(lvl.get_edge_by_id(edge), MapEdge.FLAG_OPEN), kind)
		s.undo()
		assert_false(MapEdge.has_flag(lvl.get_edge_by_id(edge), MapEdge.FLAG_OPEN), kind)
		assert_eq(d.deltas.size(), 0, kind)


func test_document_signal_reaches_view() -> void:
	var d: MapDocument = _doc()
	var view: MapView2D = MapView2D.new()
	view.document = d
	view.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(view)
	var s: CommandStack = CommandStack.new(d)
	view.command_stack = s
	watch_signals(d)
	s.execute(AddTokenCommand.new(_token(d, Vector2i(0, 0))))
	assert_signal_emitted(d, "changed")
	view.fit_to(Rect2(0, 0, 800, 600))
	assert_gt(view.scale.x, 0.0)


func test_main_screen_builds() -> void:
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_true(main.is_inside_tree())
