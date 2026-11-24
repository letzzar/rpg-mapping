extends SceneTree
## Guion de prueba de F2 sobre la app real con ventana: inyecta eventos de
## ratón y teclado en la ventana raíz (pasan por toda la interfaz, como los
## del sistema operativo) y guarda una captura por paso. Imprime OK/FALLO.
##
##   godot --path project -s res://tests/render/play_f2.gd -- <carpeta>

const CODE: String = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"

var main: Control
var out_dir: String
var fails: int = 0
var step_n: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1400, 860)
	var scene: PackedScene = load("res://ui/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await _frames(2)
	await _scenario()
	print("RESULTADO fallos=", fails)
	quit()


# --- utilidades ---------------------------------------------------------------

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "FALLO ") + what)
	if not ok:
		fails += 1


func shot(name: String) -> void:
	await _frames(3)
	step_n += 1
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join("%02d_%s.png" % [step_n, name]))


func mouse_move(p: Vector2, mask: int = 0) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = mask
	root.push_input(ev)


func mouse_button(p: Vector2, button: MouseButton, pressed: bool, factor: float = 1.0) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = button
	ev.pressed = pressed
	ev.factor = factor
	root.push_input(ev)


func drag(a: Vector2, b: Vector2, button: MouseButton) -> void:
	var mask: int = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE)
	mouse_move(a)
	mouse_button(a, button, true)
	await _frames(1)
	for k: int in range(1, 6):
		var p: Vector2 = a.lerp(b, k / 5.0)
		var ev: InputEventMouseMotion = InputEventMouseMotion.new()
		ev.position = p
		ev.global_position = p
		ev.relative = (b - a) / 5.0
		ev.button_mask = mask
		root.push_input(ev)
		await _frames(1)
	mouse_button(b, button, false)
	await _frames(1)


func click(p: Vector2) -> void:
	mouse_move(p)
	await _frames(1)
	mouse_button(p, MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	mouse_button(p, MOUSE_BUTTON_LEFT, false)
	await _frames(2)


func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		root.push_input(ev)
	await _frames(1)


func button_center(text_key: String) -> Vector2:
	var label: String = TranslationServer.translate(text_key)
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b: Button = n as Button
		if b != null and b.text == label and b.is_visible_in_tree():
			return b.get_global_rect().get_center()
		stack.append_array(n.get_children())
	return Vector2(-1, -1)


func select_option(field: String, idx: int) -> void:
	# Abre el desplegable con un clic real y elige con el teclado.
	var opt: OptionButton = main.get(field)
	var c: Vector2 = opt.get_global_rect().get_center()
	await click(c)
	await _frames(2)
	var popup: PopupMenu = opt.get_popup()
	check(popup.visible, "%s: se abre el desplegable" % field)
	popup.hide()
	opt.select(idx)
	opt.item_selected.emit(idx)
	await _frames(2)


func box_pos(local: Vector2) -> Vector2:
	var box: SubViewportContainer = main.get("_view3d_box")
	return box.get_global_rect().position + local


func doc() -> MapDocument:
	var d: MapDocument = main.get("_doc")
	return d


func v3() -> MapView3D:
	var v: MapView3D = main.get("_view3d")
	return v


func status() -> String:
	var l: Label = main.get("_status")
	return l.text


# --- guion --------------------------------------------------------------------

func _scenario() -> void:
	var edit: LineEdit = main.get("_code_edit")
	await click(edit.get_global_rect().get_center())
	edit.text = CODE
	await key(KEY_ENTER)
	await _frames(3)
	check(doc() != null, "genera el mapa con Intro")
	await click(button_center("UI_ADD_TOKEN"))
	await click(button_center("UI_ADD_TOKEN"))
	check(doc().tokens.size() == 2, "añade dos fichas")
	await shot("2d")

	# 1. Vista 3D cenital.
	var t0: int = Time.get_ticks_msec()
	await select_option("_view_opt", 1)
	var ms: int = Time.get_ticks_msec() - t0
	check(v3().active and v3().mode == MapView3D.Mode.TOP, "cambia a Vista 3D")
	check(v3().last_build_ms < 500, "construcción 3D < 500 ms (%d ms; con clic y fotogramas %d ms)" % [v3().last_build_ms, ms])
	await shot("3d")
	var cam0: Vector3 = v3().camera().position
	await drag(box_pos(Vector2(700, 400)), box_pos(Vector2(820, 360)), MOUSE_BUTTON_RIGHT)
	check(v3().camera().position.distance_to(cam0) > 0.5, "botón derecho gira/inclina la cámara")
	await shot("3d_girada")
	var tgt: Vector3 = v3().get("_target")
	var d0: float = v3().camera().position.distance_to(tgt)
	mouse_move(box_pos(Vector2(700, 400)))
	mouse_button(box_pos(Vector2(700, 400)), MOUSE_BUTTON_WHEEL_UP, true, 3.0)
	mouse_button(box_pos(Vector2(700, 400)), MOUSE_BUTTON_WHEEL_UP, false, 3.0)
	await _frames(1)
	var d1: float = v3().camera().position.distance_to(tgt)
	check(d1 < d0 * 0.8, "la rueda acerca (%.1f → %.1f m)" % [d0, d1])
	var tg0: Vector3 = v3().get("_target")
	await drag(box_pos(Vector2(700, 400)), box_pos(Vector2(600, 450)), MOUSE_BUTTON_MIDDLE)
	var tg1: Vector3 = v3().get("_target")
	check(tg0.distance_to(tg1) > 0.3, "botón central desplaza")
	var yaw0: float = v3().get("_yaw")
	await key(KEY_Q)
	var yaw1: float = v3().get("_yaw")
	check(not is_equal_approx(yaw0, yaw1), "Q gira (con el foco en la vista 3D)")
	await key(KEY_O)
	check(v3().camera().projection == Camera3D.PROJECTION_ORTHOGONAL, "O pasa a ortográfica")
	await shot("3d_ortografica")
	await key(KEY_O)
	await click(button_center("UI_FIT"))
	# Vista cenital pura para apuntar bien.
	v3().set("_tilt", 0.0)
	v3().call("_update_camera")
	await _frames(1)

	# Arrastrar una ficha en 3D.
	var t: MapToken = doc().tokens[0]
	var target: Vector2i = _free_neighbor(t.cell)
	var vp_off: Vector2 = box_pos(Vector2.ZERO)
	await drag(vp_off + v3().screen_of_cell(t.cell), vp_off + v3().screen_of_cell(target), MOUSE_BUTTON_LEFT)
	check(doc().token(t.id).cell == target, "arrastrar una ficha en 3D la mueve (%s)" % status())
	await shot("3d_ficha_movida")

	# Puerta en 3D.
	var lvl: MapLevel = doc().level(0)
	var door: int = _first_door(lvl)
	var ce: Vector3i = doc().grid.edge_from_id(door)
	var seg: PackedVector2Array = doc().grid.edge_segment(Vector2i(ce.x, ce.y), ce.z, v3().cell_m)
	var mid: Vector2 = v3().camera().unproject_position(MapMeshBuilder.v3((seg[0] + seg[1]) * 0.5, 0.0))
	await click(vp_off + mid)
	check(MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN), "clic abre una puerta en 3D")
	await shot("3d_puerta_abierta")
	await key(KEY_Z, true)
	check(not MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN), "Ctrl+Z en 3D cierra la puerta")

	# 2. 1ª persona.
	await select_option("_view_opt", 2)
	check(v3().mode == MapView3D.Mode.FIRST_PERSON, "cambia a 1ª persona")
	await shot("fp_inicio")
	var moved: bool = false
	var sel: MapToken = doc().token(v3().selected_token)
	check(sel != null, "1ª persona tiene ficha seleccionada")
	for k: int in 4:
		var before: Vector2i = sel.cell
		await key(KEY_W)
		if sel.cell != before:
			moved = true
			break
		await key(KEY_D)
	check(moved, "W avanza en 1ª persona (%s)" % status())
	await shot("fp_avanza")
	var yaw_before: float = v3().camera().rotation.y
	await key(KEY_A)
	check(not is_equal_approx(yaw_before, v3().camera().rotation.y), "A gira")
	await shot("fp_gira")
	var rot0: Vector3 = v3().camera().rotation
	await drag(box_pos(Vector2(700, 400)), box_pos(Vector2(760, 380)), MOUSE_BUTTON_RIGHT)
	check(v3().camera().rotation.distance_to(rot0) > 0.05, "botón derecho mira alrededor")
	for k: int in 6:
		await key(KEY_W)
	await shot("fp_pasos")
	# Llevar la ficha junto a una puerta cerrada y abrirla desde 1ª persona.
	var lvl2: MapLevel = doc().level(0)
	var door2: int = _first_door(lvl2)
	var door_cells: Array[Vector2i] = doc().grid.edge_cells(door2)
	var stand: Vector2i = door_cells[0] if Terrain.is_passable(lvl2.get_terrain(door_cells[0])) else door_cells[1]
	var stk0: CommandStack = main.get("_stack")
	stk0.execute(MoveTokenCommand.new(sel.id, stand, 0))
	await _frames(2)
	if true:
		var at_door: Vector2i = sel.cell
		var stk: CommandStack = main.get("_stack")
		var opened: bool = false
		for k: int in doc().grid.edge_direction_count():
			await key(KEY_SPACE)
			if stk.undo_label_key() == "CMD_SET_EDGE":
				opened = true
				break
			await key(KEY_D)
		check(opened, "girando se encara la puerta y Espacio la abre")
		await shot("fp_puerta_abierta")
		for k: int in 3:
			await key(KEY_W)
		check(sel.cell != at_door, "Espacio abre la puerta de delante y se puede seguir (%s)" % status())
		await shot("fp_tras_puerta")

	# 3. Vista de jugadores, antorchas y ambiente.
	await select_option("_audience_opt", 1)
	check(v3().fog, "Ve: jugadores activa la niebla en 3D")
	await shot("fp_jugadores")
	await select_option("_view_opt", 1)
	await click(button_center("UI_FIT"))
	await shot("3d_jugadores")
	var explored_before: int = _count(doc().level(0).explored(PartyVision.VIEWER_PARTY))
	var torch: CheckBox = main.get("_torch_chk")
	await click(torch.get_global_rect().get_center())
	check(not torch.button_pressed, "desmarca Antorchas")
	var vis_dark: int = _count(v3().fog_visible)
	await shot("3d_jugadores_sin_antorcha")
	await click(torch.get_global_rect().get_center())
	var vis_lit: int = _count(v3().fog_visible)
	check(vis_dark < vis_lit, "sin antorchas se ve menos (%d < %d casillas)" % [vis_dark, vis_lit])
	var amb: CheckBox = main.get("_ambient_chk")
	await click(torch.get_global_rect().get_center())
	await click(amb.get_global_rect().get_center())
	var vis_amb: int = _count(v3().fog_visible)
	check(vis_amb > vis_dark, "sin antorchas pero con ambiente iluminado se ve la sala (%d > %d)" % [vis_amb, vis_dark])
	await shot("3d_jugadores_ambiente")
	await click(amb.get_global_rect().get_center())
	await click(torch.get_global_rect().get_center())

	# 4. Deshacer vuelve a tapar lo explorado por el último paso.
	await select_option("_view_opt", 0)
	var stack: CommandStack = main.get("_stack")
	var explored_now: int = _count(doc().level(0).explored(PartyVision.VIEWER_PARTY))
	var undo_steps: int = 0
	while stack.can_undo() and undo_steps < 12:
		await click(button_center("UI_UNDO"))
		undo_steps += 1
	var explored_after: int = _count(doc().level(0).explored(PartyVision.VIEWER_PARTY))
	check(explored_after < explored_now, "deshacer tapa lo explorado (%d → %d casillas, %d pasos)" % [explored_now, explored_after, undo_steps])
	await shot("2d_jugadores_tras_deshacer")
	check(explored_before > 0, "se había explorado algo")
	await select_option("_audience_opt", 0)
	await shot("2d_dm_final")


func _free_neighbor(c: Vector2i) -> Vector2i:
	var d: MapDocument = doc()
	for dir: int in d.grid.direction_count():
		var n: Vector2i = d.grid.neighbor(c, dir)
		if not d.grid.in_bounds(n) or not d.tokens_at(0, n, v3().profile).is_empty():
			continue
		var r: MovementCost.Route = MovementCost.find_route(v3().profile, d.level(0), c, n, "")
		if r.found and r.cells.size() == 2:
			return n
	return c


func _first_door(lvl: MapLevel) -> int:
	for id: int in lvl.edge_ids():
		if MapEdge.kind_of(lvl.get_edge_by_id(id)) == MapEdge.KIND_DOOR and not MapEdge.has_flag(lvl.get_edge_by_id(id), MapEdge.FLAG_LOCKED):
			return id
	return -1


func _count(a: PackedByteArray) -> int:
	var n: int = 0
	for b: int in a:
		if b != 0:
			n += 1
	return n
