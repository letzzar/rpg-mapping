extends GutTest
## Pruebas de interacción de la pantalla principal: se simulan eventos de
## ratón reales (push_input) sobre ui/main.tscn dentro de un SubViewport
## aislado, para detectar fallos que los tests de comandos no ven (p. ej. un
## Control que se traga los clics antes de que lleguen a la vista).

const CODE_SQUARE: String = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"

var _vp: SubViewport
var _main: Control
var _prev_locale: String = ""


## Los textos esperados están en español: se fija el idioma para no depender
## del del sistema (el CI de Linux arranca en inglés y fallaba siempre).
func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 800)
	_vp.gui_disable_input = false
	add_child_autofree(_vp)
	var scene: PackedScene = load("res://ui/main.tscn")
	_main = scene.instantiate()
	_vp.add_child(_main)
	await wait_process_frames(2)


func _view() -> MapView2D:
	var v: MapView2D = _main.get("_view")
	return v


func _doc() -> MapDocument:
	var d: MapDocument = _main.get("_doc")
	return d


func _generate(code: String) -> void:
	var edit: LineEdit = _main.get("_code_edit")
	edit.text = code
	_main.call("_generate_from_text")
	await wait_process_frames(2)


func _screen_of(cell: Vector2i) -> Vector2:
	var v: MapView2D = _view()
	return v.get_global_transform() * _doc().grid.cell_to_pixel(cell, v.cell_px)


func _push_button(pos: Vector2, button: MouseButton, pressed: bool, factor: float = 1.0) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = button
	ev.pressed = pressed
	ev.factor = factor
	if pressed and button == MOUSE_BUTTON_LEFT:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	_vp.push_input(ev, true)


func _push_motion(pos: Vector2, relative: Vector2, mask: int) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = relative
	ev.button_mask = mask
	_vp.push_input(ev, true)


## Primera casilla vecina alcanzable dentro de la velocidad.
func _reachable_neighbor(from: Vector2i) -> Vector2i:
	var d: MapDocument = _doc()
	var v: MapView2D = _view()
	for dir: int in d.grid.direction_count():
		var n: Vector2i = d.grid.neighbor(from, dir)
		if not d.grid.in_bounds(n):
			continue
		var r: MovementCost.Route = MovementCost.find_route(v.profile, d.level(0), from, n, "")
		if r.found and r.cells.size() == 2:
			return n
	return Vector2i(-1, -1)


func test_drag_token_with_mouse_moves_it() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	var d: MapDocument = _doc()
	assert_eq(d.tokens.size(), 1)
	var t: MapToken = d.tokens[0]
	var start: Vector2i = t.cell
	var target: Vector2i = _reachable_neighbor(start)
	assert_true(target.x >= 0, "hay casilla vecina alcanzable")
	var a: Vector2 = _screen_of(start)
	var b: Vector2 = _screen_of(target)
	_push_motion(a, Vector2.ZERO, 0)
	_push_button(a, MOUSE_BUTTON_LEFT, true)
	_push_motion(b, b - a, MOUSE_BUTTON_MASK_LEFT)
	_push_button(b, MOUSE_BUTTON_LEFT, false)
	await wait_process_frames(1)
	assert_eq(d.token(t.id).cell, target, "la ficha se mueve al arrastrarla")


func test_new_token_goes_next_to_entrance() -> void:
	await _generate(CODE_SQUARE)
	var d: MapDocument = _doc()
	var lvl: MapLevel = d.level(0)
	var entrance: Array[Vector2i] = []
	for r: MapRoom in lvl.rooms:
		if r.kind == MapRoom.KIND_ENTRANCE:
			entrance.append_array(lvl.room_cells(r.id))
	assert_gt(entrance.size(), 0, "MAZ marca la entrada")
	_main.call("_add_token")
	assert_true(entrance.has(d.tokens[0].cell), "la primera ficha aparece en la entrada")
	_main.call("_add_token")
	assert_ne(d.tokens[1].cell, d.tokens[0].cell, "la segunda, en otra casilla")
	var status: Label = _main.get("_status")
	assert_string_contains(status.text, "P2")


func test_ruler_with_right_drag() -> void:
	await _generate(CODE_SQUARE)
	var d: MapDocument = _doc()
	var v: MapView2D = _view()
	# Seis casillas en línea recta dentro del mapa (aunque haya roca: la regla
	# mide distancia, no ruta).
	var a_cell: Vector2i = Vector2i(10, 10)
	var b_cell: Vector2i = Vector2i(16, 10)
	var a: Vector2 = _screen_of(a_cell)
	var b: Vector2 = _screen_of(b_cell)
	_push_motion(a, Vector2.ZERO, 0)
	_push_button(a, MOUSE_BUTTON_RIGHT, true)
	_push_motion(b, b - a, MOUSE_BUTTON_MASK_RIGHT)
	await wait_process_frames(1)
	var t1: String = v.call("_ruler_text")
	assert_eq(t1, "9 m", "6 casillas = 30 ft = 9 m (convención)")
	v.unit_mode = Units.Mode.EXACT
	var t2: String = v.call("_ruler_text")
	assert_eq(t2, "9,14 m")
	v.unit_system = Units.System.IMPERIAL
	v.unit_mode = Units.Mode.CONVENTION
	var t3: String = v.call("_ruler_text")
	assert_eq(t3, "30 ft")
	_push_button(b, MOUSE_BUTTON_RIGHT, false)
	assert_true(d != null)


func test_drop_without_route_reports_it() -> void:
	await _generate(CODE_SQUARE)
	_main.call("_add_token")
	var d: MapDocument = _doc()
	var t: MapToken = d.tokens[0]
	var start: Vector2i = t.cell
	# Una casilla de roca cualquiera.
	var rock: Vector2i = Vector2i(-1, -1)
	for i: int in d.grid.cell_count():
		var c: Vector2i = d.grid.cell_at(i)
		if not Terrain.is_passable(d.level(0).get_terrain(c)):
			rock = c
			break
	var a: Vector2 = _screen_of(start)
	var b: Vector2 = _screen_of(rock)
	_push_motion(a, Vector2.ZERO, 0)
	_push_button(a, MOUSE_BUTTON_LEFT, true)
	_push_motion(b, b - a, MOUSE_BUTTON_MASK_LEFT)
	_push_button(b, MOUSE_BUTTON_LEFT, false)
	await wait_process_frames(1)
	assert_eq(d.token(t.id).cell, start)
	var status: Label = _main.get("_status")
	assert_eq(status.text, tr("UI_NO_ROUTE_STATUS"))


func test_wheel_zoom_uses_event_factor() -> void:
	await _generate(CODE_SQUARE)
	var v: MapView2D = _view()
	var old: float = v.scale.x
	var p: Vector2 = Vector2(640, 400)
	_push_motion(p, Vector2.ZERO, 0)
	# Windows agrupa varios pasos de rueda en un evento con factor > 1.
	_push_button(p, MOUSE_BUTTON_WHEEL_UP, true, 3.0)
	await wait_process_frames(1)
	assert_almost_eq(v.scale.x, minf(old * pow(MapView2D.ZOOM_STEP, 3.0), MapView2D.ZOOM_MAX), 0.001)


## Una coma sin comillas en strings.csv parte el texto en columnas y deja
## mensajes truncados ("Métrico (5 ft = 1"). Se comprueba en la traducción
## compilada (OptimizedTranslation no permite listar claves) que los
## paréntesis cuadran en los textos de la barra superior.
func test_translations_not_split_by_commas() -> void:
	var keys: Array[String] = ["UI_UNITS_METRIC", "UI_UNITS_METRIC_EXACT", "UI_UNITS_IMPERIAL",
		"UI_SEED_PLACEHOLDER", "UI_HELP", "UI_GENERATED", "UI_MOVED", "UI_OVER_SPEED"]
	for loc: String in ["es", "en"]:
		var tr_res: Translation = load("res://i18n/strings.%s.translation" % loc)
		for key: String in keys:
			var msg: String = String(tr_res.get_message(key))
			assert_ne(msg, "", "%s %s" % [loc, key])
			assert_eq(msg.count("("), msg.count(")"), "%s %s: %s" % [loc, key, msg])
	var es: Translation = load("res://i18n/strings.es.translation")
	assert_eq(String(es.get_message("UI_UNITS_METRIC")), "Métrico (5 ft = 1,5 m)")


func test_click_door_toggles_it() -> void:
	await _generate(CODE_SQUARE)
	var d: MapDocument = _doc()
	var v: MapView2D = _view()
	var lvl: MapLevel = d.level(0)
	var doors: Array[int] = []
	for id: int in lvl.edge_ids():
		if MapEdge.is_door(lvl.get_edge_by_id(id)):
			doors.append(id)
	assert_gt(doors.size(), 0, "el mapa tiene puertas")
	# Todas las puertas (incluidas las secretas en vista DM) deben responder
	# a un clic en el centro de su arista, se pulse desde el lado que sea.
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]
	for door: int in doors:
		var ce: Vector3i = d.grid.edge_from_id(door)
		var seg: PackedVector2Array = d.grid.edge_segment(Vector2i(ce.x, ce.y), ce.z, v.cell_px)
		for off: Vector2 in offsets:
			var mid: Vector2 = v.get_global_transform() * ((seg[0] + seg[1]) * 0.5) + off
			var was_open: bool = MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN)
			_push_motion(mid, Vector2.ZERO, 0)
			_push_button(mid, MOUSE_BUTTON_LEFT, true)
			_push_button(mid, MOUSE_BUTTON_LEFT, false)
			await wait_process_frames(1)
			assert_ne(MapEdge.has_flag(lvl.get_edge_by_id(door), MapEdge.FLAG_OPEN), was_open,
				"la puerta %d (%s) cambia con un clic desplazado %s" % [door, str(ce), str(off)])
