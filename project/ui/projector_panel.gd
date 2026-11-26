class_name ProjectorPanel
extends PanelContainer
## Panel del DM para el modo proyectado (ADR 039): abrir la ventana del
## proyector en otra pantalla, calibrar la escala con una regla, girar,
## desplazar o centrar la imagen, mostrar o no las fichas, y descubrir el
## mapa a mano (revelar una zona con un clic o con un pincel, ocultar) o al
## abrir puertas. La otra forma de descubrir es la de siempre: una ficha del
## grupo que el DM mueve (no sale en el proyector; las miniaturas son de
## verdad).

## Herramienta de revelar elegida ("" = ninguna; formato MapView2D.edit_tool).
signal tool_changed(tool: String)
## Pide centrar el proyector (en la ficha seleccionada o en el grupo).
signal center_requested
## Pide añadir la ficha del grupo (para descubrir por visión).
signal party_marker_requested
## Algo cambió en el proyector (para redibujar su área en la vista del DM).
signal layout_changed
signal status(text: String)

var projector: ProjectorWindow = null
## Revelar las dos zonas de una puerta al abrirla.
var reveal_on_door: bool = true

var _open_btn: Button
var _screen_opt: OptionButton
var _px_spin: SpinBox
var _calib_btn: Button
var _turn_opt: OptionButton
var _tokens_chk: CheckBox
var _door_chk: CheckBox
var _group: ButtonGroup = ButtonGroup.new()
var _tools: Dictionary[String, Button] = {}
var _updating: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	_group.allow_unpress = true
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_heading(box, "UI_PROJ_TITLE")
	var help: Label = Label.new()
	help.text = tr("UI_PROJ_HELP")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(270, 0)
	box.add_child(help)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_screen_opt = OptionButton.new()
	_fill_screens()
	_screen_opt.item_selected.connect(func(_i: int) -> void: _place_window())
	_row(grid, "UI_PROJ_SCREEN", _screen_opt)
	_open_btn = Button.new()
	_open_btn.text = tr("UI_PROJ_OPEN")
	_open_btn.toggle_mode = true
	_open_btn.toggled.connect(set_open)
	box.add_child(_open_btn)

	_heading(box, "UI_PROJ_SCALE")
	var g2: GridContainer = GridContainer.new()
	g2.columns = 2
	box.add_child(g2)
	_px_spin = SpinBox.new()
	_px_spin.min_value = 8
	_px_spin.max_value = 600
	_px_spin.step = 0.5
	_px_spin.value = ProjectorWindow.DEFAULT_PX_PER_CELL
	_px_spin.value_changed.connect(func(v: float) -> void:
		if not _updating and projector != null:
			projector.px_per_cell = v
			_save()
			layout_changed.emit())
	_row(g2, "UI_PROJ_PX", _px_spin)
	_turn_opt = OptionButton.new()
	for k: int in 4:
		_turn_opt.add_item(tr("UI_PROJ_TURN_%d" % k))
	_turn_opt.item_selected.connect(func(i: int) -> void:
		if projector != null:
			projector.quarter_turns = i
			_save()
			layout_changed.emit())
	_row(g2, "UI_PROJ_TURN", _turn_opt)
	_calib_btn = Button.new()
	_calib_btn.text = tr("UI_PROJ_CALIBRATE")
	_calib_btn.tooltip_text = tr("UI_PROJ_CALIBRATE_TIP")
	_calib_btn.toggle_mode = true
	_calib_btn.toggled.connect(func(on: bool) -> void:
		if projector != null:
			projector.calibrating = on)
	box.add_child(_calib_btn)

	_heading(box, "UI_PROJ_MOVE")
	var mv: GridContainer = GridContainer.new()
	mv.columns = 3
	box.add_child(mv)
	for spec: Array in [["", Vector2.ZERO], ["↑", Vector2(0, -1)], ["", Vector2.ZERO],
			["←", Vector2(-1, 0)], ["◎", Vector2.ZERO], ["→", Vector2(1, 0)],
			["", Vector2.ZERO], ["↓", Vector2(0, 1)], ["", Vector2.ZERO]]:
		var label: String = spec[0]
		var dir: Vector2 = spec[1]
		if label.is_empty():
			mv.add_child(Control.new())
			continue
		var b: Button = Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(44, 32)
		if label == "◎":
			b.tooltip_text = tr("UI_PROJ_CENTER_TIP")
			b.pressed.connect(func() -> void: center_requested.emit())
		else:
			b.tooltip_text = tr("UI_PROJ_SHIFT_TIP")
			b.pressed.connect(func() -> void: shift(dir))
		mv.add_child(b)
	var warn: Label = Label.new()
	warn.text = tr("UI_PROJ_MOVE_WARN")
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(270, 0)
	box.add_child(warn)
	_tokens_chk = CheckBox.new()
	_tokens_chk.text = tr("UI_PROJ_SHOW_TOKENS")
	_tokens_chk.tooltip_text = tr("UI_PROJ_SHOW_TOKENS_TIP")
	_tokens_chk.toggled.connect(func(on: bool) -> void:
		if projector != null:
			projector.view.show_tokens = on
			projector.view.queue_redraw()
			_save())
	box.add_child(_tokens_chk)

	_heading(box, "UI_PROJ_REVEAL")
	_door_chk = CheckBox.new()
	_door_chk.text = tr("UI_PROJ_REVEAL_DOORS")
	_door_chk.button_pressed = true
	_door_chk.toggled.connect(func(on: bool) -> void: reveal_on_door = on)
	box.add_child(_door_chk)
	var tf: HFlowContainer = HFlowContainer.new()
	box.add_child(tf)
	for t: String in ["reveal_room", "reveal", "conceal"]:
		var b: Button = Button.new()
		b.text = tr("UI_PROJ_TOOL_" + t.to_upper())
		b.tooltip_text = tr("UI_PROJ_TOOL_" + t.to_upper() + "_TIP")
		b.toggle_mode = true
		b.button_group = _group
		b.toggled.connect(func(_on: bool) -> void: tool_changed.emit(current_tool()))
		_tools[t] = b
		tf.add_child(b)
	var party_btn: Button = Button.new()
	party_btn.text = tr("UI_PROJ_PARTY_MARKER")
	party_btn.tooltip_text = tr("UI_PROJ_PARTY_MARKER_TIP")
	party_btn.pressed.connect(func() -> void: party_marker_requested.emit())
	box.add_child(party_btn)


func _heading(box: VBoxContainer, key: String) -> void:
	box.add_child(HSeparator.new())
	var h: Label = Label.new()
	h.text = tr(key)
	h.add_theme_color_override("font_color", Color("f7dc8e"))
	box.add_child(h)


func _row(g: GridContainer, key: String, ctl: Control) -> void:
	var l: Label = Label.new()
	l.text = tr(key)
	g.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctl)


func _fill_screens() -> void:
	_screen_opt.clear()
	for i: int in DisplayServer.get_screen_count():
		var s: Vector2i = DisplayServer.screen_get_size(i)
		_screen_opt.add_item(tr("UI_PROJ_SCREEN_N").replace("{n}", str(i + 1)).replace("{w}", str(s.x)).replace("{h}", str(s.y)))
	# Por defecto, la última pantalla (el proyector suele ser la segunda).
	if _screen_opt.item_count > 0:
		_screen_opt.select(_screen_opt.item_count - 1)


## Herramienta activa ("" si ninguna).
func current_tool() -> String:
	for t: String in _tools:
		if _tools[t].button_pressed:
			return t
	return ""


func select_tool(t: String) -> void:
	if t.is_empty():
		var p: BaseButton = _group.get_pressed_button()
		if p != null:
			p.button_pressed = false
	elif _tools.has(t):
		_tools[t].button_pressed = true


## Abre o cierra la ventana del proyector.
func set_open(on: bool) -> void:
	_open_btn.set_pressed_no_signal(on)
	_open_btn.text = tr("UI_PROJ_CLOSE" if on else "UI_PROJ_OPEN")
	if projector == null:
		return
	if on:
		var saved: Dictionary = projector.load_settings()
		_updating = true
		_px_spin.value = projector.px_per_cell
		_turn_opt.select(projector.quarter_turns)
		var show: bool = saved.get("show_tokens", false)
		_tokens_chk.set_pressed_no_signal(show)
		projector.view.show_tokens = show
		var scr: int = saved.get("screen", -1)
		if scr >= 0 and scr < _screen_opt.item_count:
			_screen_opt.select(scr)
		_updating = false
		projector.show()
		_place_window()
		center_requested.emit()
		status.emit(tr("UI_PROJ_OPENED"))
	else:
		projector.calibrating = false
		_calib_btn.set_pressed_no_signal(false)
		projector.hide()
	layout_changed.emit()


func is_open() -> bool:
	return projector != null and projector.visible


## Lleva la ventana a pantalla completa en la pantalla elegida.
func _place_window() -> void:
	if not is_open():
		return
	if DisplayServer.get_name() != "headless":
		projector.current_screen = maxi(0, _screen_opt.selected)
		projector.mode = Window.MODE_FULLSCREEN
	projector.apply_layout()
	_save()
	layout_changed.emit()


func shift(cells: Vector2) -> void:
	if projector == null:
		return
	# Las flechas llevan la zona proyectada hacia ese lado del mapa tal como
	# lo ve el DM en su pantalla (el rectángulo del proyector en su vista).
	projector.shift(cells)
	layout_changed.emit()


func _save() -> void:
	if projector != null and not _updating:
		projector.save_settings(maxi(0, _screen_opt.selected), _tokens_chk.button_pressed)
