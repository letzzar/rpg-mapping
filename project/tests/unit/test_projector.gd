extends GutTest
## Modo proyectado (ADR 039): revelar zonas (a mano, con pincel y al abrir
## puertas), ocultar con deshacer y delta reaplicable, la ventana del
## proyector a escala y fija, y la pantalla principal con el proyector.

const EAST: int = 1
const CFG: String = "user://test_projector.cfg"

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


## Dos salas de 5×4 (x 1-5 y 7-11, y 1-4) separadas por un muro grueso en
## x = 6, con una puerta cerrada en (5, 2) → (6, 2)... la puerta va en la
## arista entre (5, 2) y (6, 2), y (6, 2) es suelo (el hueco del muro).
func _two_rooms() -> MapDocument:
	var d: MapDocument = MapDocument.create("square", 13, 6)
	var lvl: MapLevel = d.level(0)
	lvl.fill_terrain(Terrain.WALL)
	var a: MapRoom = MapRoom.make(d.allocate_id(), MapRoom.KIND_ROOM)
	var b: MapRoom = MapRoom.make(d.allocate_id(), MapRoom.KIND_ROOM)
	lvl.add_room(a)
	lvl.add_room(b)
	for y: int in range(1, 5):
		for x: int in range(1, 6):
			lvl.set_terrain(Vector2i(x, y), Terrain.FLOOR)
			lvl.set_room_id(Vector2i(x, y), a.id)
		for x: int in range(7, 12):
			lvl.set_terrain(Vector2i(x, y), Terrain.FLOOR)
			lvl.set_room_id(Vector2i(x, y), b.id)
	# Pasillo de una casilla sin sala en (6, 2), con puerta al oeste.
	lvl.set_terrain(Vector2i(6, 2), Terrain.FLOOR)
	lvl.set_edge(Vector2i(5, 2), EAST, MapEdge.make(MapEdge.KIND_DOOR))
	return d


func test_regions_and_doors() -> void:
	var d: MapDocument = _two_rooms()
	var lvl: MapLevel = d.level(0)
	var room_a: Array[Vector2i] = FogReveal.region_cells(d, 0, Vector2i(2, 2))
	var floor_a: int = 0
	for c: Vector2i in room_a:
		if lvl.get_terrain(c) == Terrain.FLOOR:
			floor_a += 1
			assert_eq(lvl.get_room_id(c), lvl.get_room_id(Vector2i(2, 2)))
	assert_eq(floor_a, 20, "la sala entera")
	assert_true(room_a.has(Vector2i(0, 0)), "con sus muros")
	# Sin sala: lo que se alcanza sin cruzar la puerta cerrada.
	var corridor: Array[Vector2i] = FogReveal.region_cells(d, 0, Vector2i(6, 2))
	assert_true(corridor.has(Vector2i(7, 2)), "sigue a la sala de al lado (sin puerta)")
	assert_false(corridor.has(Vector2i(5, 2)), "no cruza la puerta cerrada")
	assert_true(FogReveal.region_cells(d, 0, Vector2i(0, 0)).is_empty(), "roca")
	var door: int = d.grid.edge_id(Vector2i(5, 2), EAST)
	var both: Array[Vector2i] = FogReveal.door_cells(d, 0, door)
	assert_true(both.has(Vector2i(1, 1)) and both.has(Vector2i(6, 2)))


func test_conceal_undo_and_replay() -> void:
	var d: MapDocument = _two_rooms()
	var s: CommandStack = CommandStack.new(d)
	var cells: Array[Vector2i] = FogReveal.region_cells(d, 0, Vector2i(2, 2))
	assert_true(s.execute(ExploreCommand.new(0, PartyVision.VIEWER_PARTY, cells)))
	assert_true(s.execute(ConcealCommand.new(0, PartyVision.VIEWER_PARTY, [Vector2i(1, 1), Vector2i(9, 3)] as Array[Vector2i])))
	var lvl: MapLevel = d.level(0)
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(1, 1)))
	assert_true(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(2, 2)))
	var hidden: Array = d.deltas[d.deltas.size() - 1].data["cells"]
	assert_eq(hidden.size(), 1, "solo lo que cambia")
	var replay: MapDocument = _two_rooms()
	var rep: DeltaReplay.Result = DeltaReplay.replay(replay, d.deltas)
	assert_eq(rep.error, "", rep.detail)
	assert_eq(replay.full_hash(), d.full_hash())
	s.undo()
	assert_true(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(1, 1)))


func test_view_reveal_tools_with_mouse() -> void:
	var d: MapDocument = _two_rooms()
	var s: CommandStack = CommandStack.new(d)
	var view: MapView2D = MapView2D.new()
	view.document = d
	view.profile = SystemProfile.load_id("dnd5e_2024")
	view.command_stack = s
	add_child_autofree(view)
	var at: Callable = func(c: Vector2i) -> Vector2: return d.grid.cell_to_pixel(c, view.cell_px)
	var click: Callable = func(p: Vector2, down: bool) -> void:
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = p
		view.process_input(mm, false)
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		view.process_input(ev, false)
	var lvl: MapLevel = d.level(0)
	view.edit_tool = "reveal_room"
	click.call(at.call(Vector2i(9, 3)), true)
	click.call(at.call(Vector2i(9, 3)), false)
	assert_true(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(11, 4)))
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(2, 2)))
	view.edit_tool = "conceal"
	click.call(at.call(Vector2i(11, 4)), true)
	click.call(at.call(Vector2i(10, 4)), false)
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(11, 4)))
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(10, 4)))
	view.edit_tool = "reveal"
	click.call(at.call(Vector2i(2, 2)), true)
	click.call(at.call(Vector2i(3, 2)), false)
	assert_true(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(3, 2)))
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, Vector2i(4, 2)))
	# Sin herramienta, el clic en la puerta la abre y avisa.
	view.edit_tool = ""
	watch_signals(view)
	var seg: PackedVector2Array = d.grid.edge_segment(Vector2i(5, 2), EAST, view.cell_px)
	click.call((seg[0] + seg[1]) * 0.5, true)
	click.call((seg[0] + seg[1]) * 0.5, false)
	assert_signal_emitted_with_parameters(view, "door_toggled", [d.grid.edge_id(Vector2i(5, 2), EAST), true])


func test_projector_window_scale_and_turns() -> void:
	var d: MapDocument = _two_rooms()
	var w: ProjectorWindow = ProjectorWindow.new()
	w.config_path = CFG
	add_child_autofree(w)
	w.size = Vector2i(800, 600)
	w.set_document(d, 0)
	w.px_per_cell = 100.0
	w.center_on(Vector2i(6, 2))
	var center_px: Vector2 = w.view.get_transform() * d.grid.cell_to_pixel(Vector2i(6, 2), w.view.cell_px)
	assert_almost_eq(center_px, Vector2(400, 300), Vector2(0.01, 0.01), "la casilla en el centro")
	var next_px: Vector2 = w.view.get_transform() * d.grid.cell_to_pixel(Vector2i(7, 2), w.view.cell_px)
	assert_almost_eq(next_px.x - center_px.x, 100.0, 0.01, "100 px por casilla")
	w.quarter_turns = 1
	center_px = w.view.get_transform() * d.grid.cell_to_pixel(Vector2i(6, 2), w.view.cell_px)
	assert_almost_eq(center_px, Vector2(400, 300), Vector2(0.01, 0.01), "girar no mueve el centro")
	next_px = w.view.get_transform() * d.grid.cell_to_pixel(Vector2i(7, 2), w.view.cell_px)
	assert_almost_eq(next_px, Vector2(400, 400), Vector2(0.01, 0.01), "90°: el este baja")
	var area: PackedVector2Array = w.area_polygon()
	assert_eq(area.size(), 4)
	assert_true(Geometry2D.is_point_in_polygon(d.grid.cell_to_pixel(Vector2i(6, 2), w.view.cell_px), area))
	w.shift(Vector2(1, 0))
	assert_almost_eq(w.center_cell, Vector2(7.5, 2.5), Vector2(0.001, 0.001))
	w.calibrating = true
	await wait_process_frames(1)
	# Guardar y leer la calibración.
	w.save_settings(1, true)
	var w2: ProjectorWindow = ProjectorWindow.new()
	w2.config_path = CFG
	add_child_autofree(w2)
	var saved: Dictionary = w2.load_settings()
	assert_almost_eq(w2.px_per_cell, 100.0, 0.001)
	assert_eq(w2.quarter_turns, 1)
	var screen: int = saved["screen"]
	assert_eq(screen, 1)


func test_main_with_projector() -> void:
	if OS.has_feature("web"):
		pending("el proyector es otra ventana: solo en escritorio")
		return
	# Sin calibración guardada (la de la prueba anterior mostraba fichas).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var proj: ProjectorWindow = main.get("_projector")
	proj.config_path = CFG
	var edit: LineEdit = main.get("_code_edit")
	edit.text = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
	main.call("_generate_from_text")
	await wait_process_frames(1)
	var panel: ProjectorPanel = main.get("_proj_panel")
	panel.set_open(true)
	await wait_process_frames(1)
	assert_true(panel.is_open())
	var doc: MapDocument = main.get("_doc")
	assert_eq(proj.view.document, doc)
	assert_false(proj.view.show_tokens or proj.view.dm_view, "sin fichas ni secretos")
	var view: MapView2D = main.get("_view")
	assert_eq(view.projector_area.size(), 4, "la zona proyectada se ve en la pantalla del DM")
	# Abrir una puerta revela lo de los dos lados, en el mismo paso.
	var lvl: MapLevel = doc.level(0)
	var door: int = -1
	for id: int in lvl.edge_ids():
		if MapEdge.kind_of(lvl.get_edge_by_id(id)) == MapEdge.KIND_DOOR and not MapEdge.has_flag(lvl.get_edge_by_id(id), MapEdge.FLAG_OPEN):
			door = id
			break
	var e: Vector3i = doc.grid.edge_from_id(door)
	var cell: Vector2i = Vector2i(e.x, e.y)
	assert_false(lvl.is_explored(PartyVision.VIEWER_PARTY, cell))
	view.door_toggled.emit(door, true)
	main.call("_on_user_command")
	assert_true(lvl.is_explored(PartyVision.VIEWER_PARTY, cell), "revelado al abrir la puerta")
	await wait_process_frames(2)
	assert_ne(proj.view.fog_explored[doc.grid.index_of(cell)], 0, "y le llega al proyector")
	# Ficha del grupo: descubre por visión, como siempre.
	main.call("_add_party_marker")
	assert_eq(PartyVision.party_tokens(doc, view.level_index).size(), 1)
	panel.select_tool("reveal_room")
	assert_eq(view.edit_tool, "reveal_room")
	panel.select_tool("")
	assert_eq(view.edit_tool, "")
	panel.set_open(false)
	assert_false(panel.is_open())
	assert_eq(view.projector_area.size(), 0)
