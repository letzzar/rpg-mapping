extends GutTest
## Editor de estancias (E2, ADR 037): comandos con deshacer y deltas
## reaplicables, herramientas de la vista 2D con el ratón, panel y estancia
## en blanco (EST G3).

const CODE: String = "RPGM1-DND5-EST-G1-0-H8DJRFAE-M"

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func _generate(code: String = CODE) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_not_null(res.doc, res.error)
	if res.doc.seed_code.is_empty():
		res.doc.seed_code = code
	return res.doc


func _floor(doc: MapDocument) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lvl: MapLevel = doc.level(0)
	var mask: PackedByteArray = lvl.movement_mask()
	for i: int in mask.size():
		var c: Vector2i = doc.grid.cell_at(i)
		if (mask[i] & MapLevel.MOVE_PASSABLE) != 0 and lvl.objects_at(c).is_empty():
			out.append(c)
	return out


func _view(doc: MapDocument, s: CommandStack) -> MapView2D:
	var view: MapView2D = MapView2D.new()
	view.document = doc
	view.profile = SystemProfile.load_id("dnd5e_2024")
	view.command_stack = s
	add_child_autofree(view)
	return view


func _mouse(view: MapView2D, at: Vector2, pressed: int) -> void:
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = at
	view.process_input(mm, false)
	if pressed < 0:
		return
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed == 1
	ev.position = at
	view.process_input(ev, false)


func test_commands_undo_and_replay() -> void:
	var doc: MapDocument = _generate()
	# El contenido del nivel (terreno, aristas, salas, objetos y su orden). El
	# contador de ids no vuelve atrás al deshacer, a propósito: un id gastado
	# no se reutiliza.
	var base: String = CanonicalJson.stringify(doc.level(0).content_to_dict())
	var s: CommandStack = CommandStack.new(doc)
	var cells: Array[Vector2i] = _floor(doc)
	assert_true(s.execute(SetTerrainCommand.new(0, [cells[0], cells[1], cells[1]], Terrain.RUBBLE)))
	assert_false(s.execute(SetTerrainCommand.new(0, [cells[0]], Terrain.RUBBLE)), "sin cambios: nada")
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var o: MapObject = cat.instantiate(cat.entry("chest"), doc.allocate_id(), cells[2], 1, "")
	assert_true(s.execute(AddObjectCommand.new(0, o)))
	var generated: MapObject = doc.level(0).objects[0]
	assert_true(s.execute(RemoveObjectCommand.new(0, generated.id)))
	var room: MapRoom = doc.level(0).rooms[0]
	assert_true(s.execute(SetRoomCommand.new(0, room.id, "crypt", "Cripta del rey")))
	var lvl: MapLevel = doc.level(0)
	var e1: int = doc.grid.edge_id(cells[3], 0)
	var e2: int = doc.grid.edge_id(cells[3], 1)
	assert_true(s.execute(CompositeCommand.new([SetEdgeCommand.new(0, e1, MapEdge.make(MapEdge.KIND_WINDOW)),
		SetEdgeCommand.new(0, e2, MapEdge.make(MapEdge.KIND_WALL))] as Array[MapCommand])))
	assert_eq(MapEdge.kind_of(lvl.get_edge_by_id(e1)), MapEdge.KIND_WINDOW)
	# Guardar y abrir: idéntico.
	var res: MapFile.LoadResult = MapFile.from_json(MapFile.to_json(doc))
	assert_eq(res.error, "", res.detail)
	assert_eq(res.doc.full_hash(), doc.full_hash())
	assert_eq(res.doc.level(0).room(room.id).label, "Cripta del rey")
	assert_null(res.doc.level(0).object(generated.id), "el objeto borrado sigue borrado")
	# Deshacerlo todo vuelve al mapa generado.
	while s.can_undo():
		s.undo()
	assert_eq(CanonicalJson.stringify(doc.level(0).content_to_dict()), base, "nada queda tras deshacer")
	assert_eq(doc.deltas.size(), 0)


func test_view_tools_with_mouse() -> void:
	var doc: MapDocument = _generate()
	var s: CommandStack = CommandStack.new(doc)
	var view: MapView2D = _view(doc, s)
	var g: GridGeometry = doc.grid
	var cells: Array[Vector2i] = _floor(doc)
	# Pincelada de agua por tres casillas: un solo paso de deshacer.
	view.edit_tool = "terrain:water_shallow"
	_mouse(view, g.cell_to_pixel(cells[0], view.cell_px), 1)
	_mouse(view, g.cell_to_pixel(cells[1], view.cell_px), -1)
	_mouse(view, g.cell_to_pixel(cells[2], view.cell_px), -1)
	_mouse(view, g.cell_to_pixel(cells[2], view.cell_px), 0)
	for i: int in 3:
		assert_eq(doc.level(0).get_terrain(cells[i]), Terrain.WATER_SHALLOW)
	assert_eq(s.undo_label_key(), "CMD_SET_TERRAIN")
	s.undo()
	assert_eq(doc.level(0).get_terrain(cells[1]), Terrain.FLOOR, "deshace la pincelada entera")
	# Arista: el punto medio del borde de una casilla.
	view.edit_tool = "edge:door"
	var seg: PackedVector2Array = g.edge_segment(cells[4], 0, view.cell_px)
	var mid: Vector2 = (seg[0] + seg[1]) * 0.5
	_mouse(view, mid, 1)
	_mouse(view, mid, 0)
	assert_eq(MapEdge.kind_of(doc.level(0).get_edge(cells[4], 0)), MapEdge.KIND_DOOR)
	# Objeto girado y borrado; el arrastre de fichas no actúa con herramienta.
	view.edit_tool = "object:barrel"
	view.edit_facing = 2
	var n_before: int = doc.level(0).objects.size()
	_mouse(view, g.cell_to_pixel(cells[5], view.cell_px), 1)
	_mouse(view, g.cell_to_pixel(cells[5], view.cell_px), 0)
	assert_eq(doc.level(0).objects.size(), n_before + 1)
	var placed: MapObject = doc.level(0).objects_at(cells[5])[0]
	assert_eq(placed.catalog_id, "barrel")
	assert_eq(placed.facing, 2)
	view.edit_tool = "erase_object"
	_mouse(view, g.cell_to_pixel(cells[5], view.cell_px), 1)
	_mouse(view, g.cell_to_pixel(cells[5], view.cell_px), 0)
	assert_eq(doc.level(0).objects.size(), n_before)
	# Sobre una casilla de roca no cabe.
	var rock: Vector2i = Vector2i(-1, -1)
	for i: int in g.cell_count():
		if doc.level(0).terrain[i] == Terrain.WALL or doc.level(0).terrain[i] == Terrain.VOID:
			rock = g.cell_at(i)
			break
	assert_false(view.place_object("barrel", rock, 0))


func test_panel_tools_rooms_and_check() -> void:
	var doc: MapDocument = _generate()
	var s: CommandStack = CommandStack.new(doc)
	var panel: RoomEditorPanel = RoomEditorPanel.new()
	panel.execute = func(cmd: MapCommand) -> bool: return s.execute(cmd)
	add_child_autofree(panel)
	panel.set_document(doc)
	watch_signals(panel)
	panel.select_tool("terrain:rubble")
	assert_signal_emitted_with_parameters(panel, "tool_changed", ["terrain:rubble"])
	panel.select_tool("object:chest")
	assert_eq(panel.current_tool(), "object:chest")
	panel.select_tool("")
	assert_eq(panel.current_tool(), "")
	panel.rotate()
	assert_signal_emitted_with_parameters(panel, "facing_changed", [1])
	assert_eq(panel.check_text(), tr("UI_EDIT_CHECK_OK"))
	# Tapiar casillas de suelo con roca deja otras sin acceso.
	var room: MapRoom = doc.level(0).rooms[0]
	panel.select_room(room.id, "library", "Biblioteca vieja")
	assert_true(panel.apply_room())
	assert_eq(doc.level(0).room(room.id).kind, "library")
	var start: Vector2i = panel.start_cell()
	var ring: Array[Vector2i] = []
	for c: Vector2i in _floor(doc):
		if c != start and (c - start).length_squared() <= 2:
			ring.append(c)
	for dir: int in doc.grid.direction_count():
		var n: Vector2i = doc.grid.neighbor(start, dir)
		if doc.grid.in_bounds(n) and not ring.has(n):
			ring.append(n)
	assert_true(s.execute(SetTerrainCommand.new(0, ring, Terrain.WALL)))
	panel.refresh()
	assert_true(panel.check_text().begins_with(tr("UI_EDIT_CHECK_MISSING").get_slice("{", 0)), panel.check_text())


func test_blank_room_is_editable_and_saved() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	for grid: String in ["square", "hex_flat", "hex_pointy"]:
		var ok: bool = main.call("new_blank_room", 6, 5, grid)
		assert_true(ok, grid)
		var doc: MapDocument = main.get("_doc")
		assert_eq(doc.grid.kind, grid)
		var sc: SeedCode = SeedCode.parse(doc.seed_code)
		assert_eq(sc.scale, "EST")
		var panel: RoomEditorPanel = main.get("_editor_panel")
		panel.set_document(doc)
		assert_eq(panel.check_text(), tr("UI_EDIT_CHECK_OK"), grid)
	# Editar con el botón y guardar: se recrea con el código EST G3.
	var btn: Button = main.get("_edit_btn")
	btn.button_pressed = true
	btn.pressed.emit()
	var view: MapView2D = main.get("_view")
	var doc2: MapDocument = main.get("_doc")
	var c: Vector2i = _floor(doc2)[0]
	assert_true(view.place_object("chest", c, 0))
	var res: MapFile.LoadResult = MapFile.from_json(MapFile.to_json(doc2))
	assert_eq(res.error, "", res.detail)
	assert_eq(res.doc.full_hash(), doc2.full_hash())
	btn.button_pressed = false
	btn.pressed.emit()
	assert_eq(view.edit_tool, "")
