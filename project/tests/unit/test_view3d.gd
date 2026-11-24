extends GutTest
## Vista 3D cenital y 1ª persona (F2): construcción, criterio de cambio de
## vista < 500 ms, interacción y niebla coherente con la vista 2D.

const CODE_SQUARE: String = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
const CODES: Array[String] = [
	"RPGM1-DND5-MAZ-G1-0-HWX23H6N-W",
	"RPGM1-PF2E-MAZ-G1-80-PK2XDSZR-5",
	"RPGM1-DND5-MAZ-G1-WKA0G0-W7HE7S75-0",
	"RPGM1-DND5-EST-G1-0-H8DJRFAE-M",
	"RPGM1-DND5-EST-G1-223-QN75YR3H-Y",
]

var _vp: SubViewport
var _main: Control


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 800)
	add_child_autofree(_vp)
	var scene: PackedScene = load("res://ui/main.tscn")
	_main = scene.instantiate()
	_vp.add_child(_main)
	await wait_process_frames(2)


func _generate(code: String) -> void:
	var edit: LineEdit = _main.get("_code_edit")
	edit.text = code
	_main.call("_generate_from_text")
	await wait_process_frames(2)


func _doc() -> MapDocument:
	var d: MapDocument = _main.get("_doc")
	return d


func _v3() -> MapView3D:
	var v: MapView3D = _main.get("_view3d")
	return v


func _select_view(i: int) -> int:
	var opt: OptionButton = _main.get("_view_opt")
	opt.select(i)
	var ms: int = _main.call("_apply_view")
	return ms


func _count_tris(root: Node3D, child: String) -> int:
	var mi: MeshInstance3D = root.get_node_or_null(child) as MeshInstance3D
	if mi == null:
		return 0
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	return verts.size() / 3


func test_builder_makes_geometry_for_all_kinds() -> void:
	for code: String in CODES:
		var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
		assert_not_null(res.doc, code)
		if res.doc == null:
			continue
		var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
		var root: Node3D = MapMeshBuilder.build_level(res.doc, 0, opts)
		assert_gt(_count_tris(root, "Floor"), 0, code)
		assert_gt(_count_tris(root, "Walls"), 0, code)
		root.free()


func test_builder_fog_hides_unexplored() -> void:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(CODE_SQUARE)
	var d: MapDocument = res.doc
	var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
	opts.fog = true
	opts.visible = PackedByteArray()
	opts.visible.resize(d.grid.cell_count())
	opts.explored = opts.visible.duplicate()
	var root: Node3D = MapMeshBuilder.build_level(d, 0, opts)
	assert_eq(_count_tris(root, "Floor"), 0, "sin explorar no se construye nada")
	root.free()
	# Una casilla de suelo explorada: solo su abanico.
	for i: int in d.grid.cell_count():
		if Terrain.is_passable(d.level(0).terrain[i]):
			opts.explored[i] = 1
			break
	root = MapMeshBuilder.build_level(d, 0, opts)
	assert_eq(_count_tris(root, "Floor"), 8, "un cuadrado = 4 triángulos (+4 de la junta)")
	root.free()


func test_view_switch_under_500ms() -> void:
	for code: String in CODES:
		await _generate(code)
		for v: int in [1, 2, 0, 1]:
			var ms: int = _select_view(v)
			assert_lt(ms, 500, "%s vista %d: %d ms" % [code, v, ms])
		_select_view(0)


func test_3d_click_door_and_drag_token() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	_select_view(1)
	await wait_process_frames(2)
	var v: MapView3D = _v3()
	var d: MapDocument = _doc()
	# Vista desde arriba del todo para que el rayo sea limpio.
	v.set("_tilt", 0.0)
	v.call("_update_camera")
	var t: MapToken = d.tokens[0]
	var target: Vector2i = Vector2i(-1, -1)
	for dir: int in d.grid.direction_count():
		var n: Vector2i = d.grid.neighbor(t.cell, dir)
		var r: MovementCost.Route = MovementCost.find_route(v.profile, d.level(0), t.cell, n, "")
		if d.grid.in_bounds(n) and r.found and r.cells.size() == 2:
			target = n
			break
	assert_true(target.x >= 0)
	assert_eq(v.cell_at_screen(v.screen_of_cell(t.cell)), t.cell, "rayo al suelo ida y vuelta")
	_press(v, v.screen_of_cell(t.cell), true)
	_press(v, v.screen_of_cell(target), false)
	assert_eq(d.token(t.id).cell, target, "arrastrar en 3D mueve la ficha")
	var lvl: MapLevel = d.level(0)
	var door: int = -1
	for id: int in lvl.edge_ids():
		if MapEdge.kind_of(lvl.get_edge_by_id(id)) == MapEdge.KIND_DOOR:
			door = id
			break
	var ce: Vector3i = d.grid.edge_from_id(door)
	var seg: PackedVector2Array = d.grid.edge_segment(Vector2i(ce.x, ce.y), ce.z, v.cell_m)
	var mid: Vector2 = v.camera().unproject_position(MapMeshBuilder.v3((seg[0] + seg[1]) * 0.5, 0.0))
	var was: bool = MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN)
	_press(v, mid, true)
	_press(v, mid, false)
	assert_ne(MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN), was, "clic en puerta en 3D")


func _press(v: MapView3D, pos: Vector2, pressed: bool) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	v.process_input(ev)


func _key(v: MapView3D, code: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	v.process_input(ev)


func test_first_person_walks_turns_and_explores() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	var d: MapDocument = _doc()
	var t: MapToken = d.tokens[0]
	_select_view(2)
	await wait_process_frames(1)
	var v: MapView3D = _v3()
	assert_eq(v.mode, MapView3D.Mode.FIRST_PERSON)
	assert_eq(v.selected_token, t.id, "sin selección, toma la primera ficha del grupo")
	var eye: float = v.camera().position.y
	assert_almost_eq(eye, 1.6, 0.01, "ojos de criatura mediana")
	# Girar hasta poder avanzar (hay al menos una salida).
	var moved: bool = false
	for k: int in d.grid.edge_direction_count():
		var before: Vector2i = d.token(t.id).cell
		_key(v, KEY_W)
		if d.token(t.id).cell != before:
			moved = true
			break
		_key(v, KEY_D)
	assert_true(moved, "avanza en 1ª persona")
	var stack: CommandStack = _main.get("_stack")
	assert_eq(stack.undo_label_key(), "CMD_MOVE_TOKEN", "el paso y su exploración son un solo deshacer")
	var cam: Vector3 = v.camera().position
	var p: Vector2 = d.grid.cell_to_pixel(d.token(t.id).cell, v.cell_m)
	assert_almost_eq(cam.x, p.x, 0.01, "la cámara sigue a la ficha")
	assert_almost_eq(cam.z, p.y, 0.01)


func test_fog_is_the_same_in_2d_and_3d() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	var aud: OptionButton = _main.get("_audience_opt")
	aud.select(1)
	_main.call("_refresh_vision")
	_select_view(1)
	await wait_process_frames(2)
	var v2: MapView2D = _main.get("_view")
	var v3: MapView3D = _v3()
	assert_true(v2.fog and v3.fog, "niebla activa en las dos vistas")
	assert_eq(v2.fog_visible, v3.fog_visible)
	assert_eq(v2.fog_explored, v3.fog_explored)
	var explored: int = 0
	for b: int in v2.fog_explored:
		explored += 1 if b != 0 else 0
	assert_gt(explored, 0, "la ficha ya ha explorado su entorno")
	assert_lt(explored, _doc().grid.cell_count() / 4, "pero no todo el mapa")
	assert_false(v2.dm_view, "la vista de jugadores no enseña secretos")


func _push_click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		_vp.push_input(ev, true)
		await wait_process_frames(1)


## Regresión: con el contenedor 3D enfocado, los clics a la barra superior
## no llegaban (no se podía volver a 2D). Y las teclas deben llegar a la
## 1ª persona sin que la vista tenga el foco.
func test_toolbar_still_works_after_using_3d_and_keys_reach_fp() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	_select_view(1)
	await wait_process_frames(2)
	var box: SubViewportContainer = _main.get("_view3d_box")
	var torch: CheckBox = _main.get("_torch_chk")
	var was: bool = torch.button_pressed
	await _push_click(box.get_global_rect().get_center())
	await _push_click(torch.get_global_rect().get_center())
	assert_ne(torch.button_pressed, was, "la barra responde tras hacer clic en la vista 3D")
	_select_view(2)
	await wait_process_frames(1)
	var d: MapDocument = _doc()
	var t: MapToken = d.token(_v3().selected_token)
	var moved: bool = false
	for k: int in 6:
		var before: Vector2i = t.cell
		for pressed: bool in [true, false]:
			var ev: InputEventKey = InputEventKey.new()
			ev.keycode = KEY_W
			ev.physical_keycode = KEY_W
			ev.pressed = pressed
			_vp.push_input(ev, true)
		await wait_process_frames(1)
		if t.cell != before:
			moved = true
			break
		for pressed2: bool in [true, false]:
			var ev2: InputEventKey = InputEventKey.new()
			ev2.keycode = KEY_D
			ev2.physical_keycode = KEY_D
			ev2.pressed = pressed2
			_vp.push_input(ev2, true)
		await wait_process_frames(1)
	assert_true(moved, "W llega a la 1ª persona sin foco en la vista")


func test_first_person_opens_door_ahead() -> void:
	var d: MapDocument = MapDocument.create("square", 6, 3)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var east: int = d.grid.direction_between(Vector2i(2, 1), Vector2i(3, 1))
	var door: int = d.grid.edge_id(Vector2i(2, 1), east)
	d.level(0).set_edge_by_id(door, MapEdge.make(MapEdge.KIND_DOOR))
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.cell = Vector2i(2, 1)
	t.side = MapToken.SIDE_PLAYER
	d.add_token(t)
	var v: MapView3D = MapView3D.new()
	v.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(v)
	v.command_stack = CommandStack.new(d)
	v.document = d
	v.selected_token = t.id
	v.set_mode(MapView3D.Mode.FIRST_PERSON)
	v.set("_fp_facing", east)
	var yaw_east: float = v.call("_facing_yaw", east)
	v.set("_fp_yaw", yaw_east)
	assert_false(v.step_first_person(1), "la puerta cerrada para el paso")
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	v.process_input(ev)
	assert_true(MapEdge.has_flag(d.level(0).get_edge_by_id(door), MapEdge.FLAG_OPEN), "Espacio abre la puerta de delante")
	assert_true(v.step_first_person(1))
	assert_eq(t.cell, Vector2i(3, 1), "y ya se puede pasar")
