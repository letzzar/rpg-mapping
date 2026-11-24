extends Control
## Pantalla principal de F1: generar un mapa desde un código de semilla,
## verlo en 2D, mover fichas, medir y exportar a PNG.
##
## La interfaz se construye por código para mantener la escena mínima. Todos
## los textos salen de i18n/strings.csv.

const SCALES: Array[String] = ["MAZ", "EST"]
const GEN: int = 1
const UNIT_OPTIONS: Array[String] = ["UI_UNITS_METRIC", "UI_UNITS_METRIC_EXACT", "UI_UNITS_IMPERIAL"]
const GRID_OPTIONS: Array[String] = ["square", "hex_flat", "hex_pointy"]

var _view: MapView2D
var _map_area: Control
var _code_edit: LineEdit
var _scale_opt: OptionButton
var _system_opt: OptionButton
var _grid_opt: OptionButton
var _units_opt: OptionButton
var _level_opt: OptionButton
var _undo_btn: Button
var _redo_btn: Button
var _status: Label
var _save_dialog: FileDialog

var _doc: MapDocument = null
var _stack: CommandStack = null
var _profiles: Array[SystemProfile] = []
var _token_counter: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_profiles()
	_build_ui()
	_status.text = tr("UI_HELP")


func _load_profiles() -> void:
	for pid: String in SystemProfile.available_ids():
		var p: SystemProfile = SystemProfile.load_id(pid)
		if p.is_valid():
			_profiles.append(p)


# --- Construcción de la interfaz ----------------------------------------------

func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("2b1d14")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bar: HFlowContainer = HFlowContainer.new()
	root.add_child(bar)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = tr("UI_SEED_PLACEHOLDER")
	_code_edit.custom_minimum_size = Vector2(340, 0)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _generate_from_text())
	bar.add_child(_code_edit)
	bar.add_child(_button("UI_GENERATE", _generate_from_text))
	_scale_opt = OptionButton.new()
	for sc_id: String in SCALES:
		_scale_opt.add_item(tr("UI_SCALE_" + sc_id))
	bar.add_child(_scale_opt)
	bar.add_child(_button("UI_RANDOM", _generate_random))

	_system_opt = OptionButton.new()
	for p: SystemProfile in _profiles:
		_system_opt.add_item(tr(p.name_key))
	_system_opt.item_selected.connect(func(_i: int) -> void: _apply_profile())
	bar.add_child(_system_opt)

	_grid_opt = OptionButton.new()
	for g: String in GRID_OPTIONS:
		_grid_opt.add_item(tr("UI_GRID_" + g.to_upper()))
	bar.add_child(_grid_opt)

	_units_opt = OptionButton.new()
	for k: String in UNIT_OPTIONS:
		_units_opt.add_item(tr(k))
	_units_opt.item_selected.connect(func(_i: int) -> void: _apply_units())
	bar.add_child(_units_opt)

	_level_opt = OptionButton.new()
	_level_opt.item_selected.connect(_on_level_selected)
	bar.add_child(_level_opt)

	bar.add_child(_button("UI_ADD_TOKEN", _add_token))
	_undo_btn = _button("UI_UNDO", _undo)
	_redo_btn = _button("UI_REDO", _redo)
	bar.add_child(_undo_btn)
	bar.add_child(_redo_btn)
	bar.add_child(_button("UI_FIT", _fit))
	bar.add_child(_button("UI_EXPORT_PNG", _export_png))

	_map_area = Control.new()
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_area.clip_contents = true
	# El área del mapa recoge el ratón y se lo pasa a la vista: con PASS el
	# evento subía hasta este Control raíz (STOP) y la vista no lo recibía.
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_map_area)

	_view = MapView2D.new()
	_view.status_changed.connect(func(t: String) -> void: _status.text = t)
	_view.set_process_unhandled_input(false)
	_map_area.add_child(_view)
	_map_area.gui_input.connect(_view.process_input)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.png ; PNG"])
	# Diálogo del sistema: sale en el idioma del usuario (el de Godot sale en
	# inglés en las exportaciones) y empieza en Imágenes, no en la carpeta
	# del ejecutable.
	_save_dialog.use_native_dialog = true
	_save_dialog.title = tr("UI_EXPORT_PNG")
	_save_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	_save_dialog.file_selected.connect(_save_png_to)
	add_child(_save_dialog)

	_apply_profile()
	_apply_units()
	_refresh_buttons()


func _button(key: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = tr(key)
	b.pressed.connect(cb)
	return b


# --- Acciones -----------------------------------------------------------------

func _current_profile() -> SystemProfile:
	var i: int = _system_opt.selected
	return _profiles[i] if i >= 0 and i < _profiles.size() else null


func _generate_random() -> void:
	var p: SystemProfile = _current_profile()
	if p == null:
		return
	var params: Dictionary = {"grid": GRID_OPTIONS[maxi(0, _grid_opt.selected)]}
	var sc: SeedCode = SeedCode.create(p.seed_code, SCALES[maxi(0, _scale_opt.selected)], GEN, params, SeedCode.random_app_seed())
	if not sc.is_valid():
		_status.text = tr(sc.error).replace("{param}", sc.error_field)
		return
	_code_edit.text = sc.encode()
	_generate_from_text()


func _generate_from_text() -> void:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(_code_edit.text)
	if res.doc == null:
		_status.text = tr(res.error)
		return
	_set_document(res.doc)
	var parsed: SeedCode = SeedCode.parse(_code_edit.text)
	for i: int in _profiles.size():
		if _profiles[i].seed_code == parsed.system:
			_system_opt.select(i)
	var scale_idx: int = SCALES.find(parsed.scale)
	if scale_idx >= 0:
		_scale_opt.select(scale_idx)
	var grid_idx: int = GRID_OPTIONS.find(res.doc.grid_kind())
	if grid_idx >= 0:
		_grid_opt.select(grid_idx)
	_code_edit.text = res.doc.seed_code if not res.doc.seed_code.is_empty() else _code_edit.text
	_apply_profile()
	_status.text = tr("UI_GENERATED").replace("{code}", _code_edit.text)


func _set_document(doc: MapDocument) -> void:
	_doc = doc
	_token_counter = 0
	_stack = CommandStack.new(doc)
	_stack.changed.connect(_refresh_buttons)
	_view.command_stack = _stack
	_view.document = doc
	_level_opt.clear()
	for i: int in doc.level_count():
		_level_opt.add_item(tr("UI_LEVEL").replace("{n}", str(i + 1)))
	_fit.call_deferred()
	_refresh_buttons()


func _apply_profile() -> void:
	_view.profile = _current_profile()
	_view.queue_redraw()


func _apply_units() -> void:
	match _units_opt.selected:
		1:
			_view.unit_system = Units.System.METRIC
			_view.unit_mode = Units.Mode.EXACT
		2:
			_view.unit_system = Units.System.IMPERIAL
			_view.unit_mode = Units.Mode.CONVENTION
		_:
			_view.unit_system = Units.System.METRIC
			_view.unit_mode = Units.Mode.CONVENTION
	_view.queue_redraw()


func _on_level_selected(i: int) -> void:
	_view.level_index = i
	_view.queue_redraw()


func _fit() -> void:
	_view.fit_to(Rect2(Vector2.ZERO, _map_area.size))


## Coloca una ficha de jugador en la casilla transitable y libre más cercana
## a la entrada (zona "entrance", si no "exit", si no una escalera); sin
## ninguna de ellas, en la primera casilla libre. Antes siempre usaba la
## primera casilla del mapa (esquina superior izquierda), lejos de la puerta.
func _add_token() -> void:
	if _doc == null:
		return
	var lvl: MapLevel = _doc.level(_view.level_index)
	var mask: PackedByteArray = lvl.movement_mask()
	var g: GridGeometry = _doc.grid
	var p: SystemProfile = _current_profile()
	for c: Vector2i in _cells_by_entrance_distance(lvl, mask):
		if p != null and not _doc.tokens_at(_view.level_index, c, p).is_empty():
			continue
		_token_counter += 1
		var t: MapToken = MapToken.new()
		t.id = _doc.allocate_id()
		t.name = "P" + str(_token_counter)
		t.level = _view.level_index
		t.cell = c
		t.side = MapToken.SIDE_PLAYER
		_stack.execute(AddTokenCommand.new(t))
		_status.text = tr("UI_TOKEN_ADDED").replace("{name}", t.name)
		return


## Casillas transitables ordenadas por distancia (en pasos, sin cruzar
## muros) a la entrada del nivel; al final, las no alcanzables en orden.
func _cells_by_entrance_distance(lvl: MapLevel, mask: PackedByteArray) -> Array[Vector2i]:
	var g: GridGeometry = _doc.grid
	var seeds: Array[Vector2i] = []
	for kind: String in [MapRoom.KIND_ENTRANCE, MapRoom.KIND_EXIT]:
		for r: MapRoom in lvl.rooms:
			if r.kind == kind:
				seeds.append_array(lvl.room_cells(r.id))
		if not seeds.is_empty():
			break
	if seeds.is_empty():
		for s: MapStair in lvl.stairs:
			seeds.append(s.cell)
	var out: Array[Vector2i] = []
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(g.cell_count())
	var queue: Array[Vector2i] = []
	for c: Vector2i in seeds:
		var i: int = g.index_of(c)
		if seen[i] == 0 and (mask[i] & MapLevel.MOVE_PASSABLE) != 0:
			seen[i] = 1
			queue.append(c)
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		out.append(c)
		for dir: int in g.direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if not g.in_bounds(n):
				continue
			var ni: int = g.index_of(n)
			if seen[ni] != 0 or (mask[ni] & MapLevel.MOVE_PASSABLE) == 0:
				continue
			if dir < g.edge_direction_count() and MapEdge.kind_of(lvl.get_edge(c, dir)) == MapEdge.KIND_WALL:
				continue
			seen[ni] = 1
			queue.append(n)
	for i: int in g.cell_count():
		if seen[i] == 0 and (mask[i] & MapLevel.MOVE_PASSABLE) != 0:
			out.append(g.cell_at(i))
	return out


func _undo() -> void:
	if _stack != null:
		_stack.undo()


func _redo() -> void:
	if _stack != null:
		_stack.redo()


func _refresh_buttons() -> void:
	_undo_btn.disabled = _stack == null or not _stack.can_undo()
	_redo_btn.disabled = _stack == null or not _stack.can_redo()
	_undo_btn.tooltip_text = tr(_stack.undo_label_key()) if _stack != null and _stack.can_undo() else ""
	_redo_btn.tooltip_text = tr(_stack.redo_label_key()) if _stack != null and _stack.can_redo() else ""


func _export_png() -> void:
	if _doc == null:
		return
	var file_name: String = (_doc.seed_code if not _doc.seed_code.is_empty() else "mapa") + ".png"
	if OS.has_feature("web"):
		var img: Image = await PngExporter.render(self, _doc, _view.level_index, _current_profile())
		if img == null:
			_status.text = tr("UI_EXPORT_FAILED")
			return
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), file_name, "image/png")
		_status.text = tr("UI_EXPORTED").replace("{path}", file_name)
		return
	_save_dialog.current_file = file_name
	_save_dialog.popup_centered_ratio(0.6)


func _save_png_to(path: String) -> void:
	var err: Error = await PngExporter.save(self, _doc, _view.level_index, _current_profile(), path)
	_status.text = tr("UI_EXPORTED").replace("{path}", path) if err == OK else tr("UI_EXPORT_FAILED")


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or not k.ctrl_pressed:
		return
	if k.keycode == KEY_Z and not k.shift_pressed:
		_undo()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed):
		_redo()
		get_viewport().set_input_as_handled()
