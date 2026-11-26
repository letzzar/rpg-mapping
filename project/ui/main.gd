extends Control
## Pantalla principal: generar un mapa desde un código de semilla, verlo en
## 2D, 3D cenital o 1ª persona (F2), mover fichas, medir, explorar con
## niebla de guerra y exportar a PNG. Partida en red (F4, ADR 031): el DM la
## abre con el panel "Partida en red"; en el navegador, una URL con ?sala=…&t=…
## abre el modo jugador (solo ve lo que el servidor le envía y propone
## movimientos).
##
## La interfaz se construye por código para mantener la escena mínima. Todos
## los textos salen de i18n/strings.csv.

const SCALES: Array[String] = ["MAZ", "EST", "EDI", "ALD"]
const GEN: int = 1
const UNIT_OPTIONS: Array[String] = ["UI_UNITS_METRIC", "UI_UNITS_METRIC_EXACT", "UI_UNITS_IMPERIAL"]
const GRID_OPTIONS: Array[String] = ["square", "hex_flat", "hex_pointy"]
const VIEW_OPTIONS: Array[String] = ["UI_VIEW_2D", "UI_VIEW_3D", "UI_VIEW_FP"]
const VIEW_2D: int = 0
const VIEW_3D: int = 1
const VIEW_FP: int = 2
## Luz que lleva cada ficha del grupo con "Antorcha": la del objeto del
## catálogo (reglas como datos; no se fija en código).
const CARRIED_LIGHT_OBJECT: String = "torch_sconce"

var _view: MapView2D
var _view3d: MapView3D
var _view3d_box: SubViewportContainer
var _view_opt: OptionButton
var _audience_opt: OptionButton
var _ambient_chk: CheckBox
var _torch_chk: CheckBox
var _vision_dirty: bool = false
var _carried_bright: int = 0
var _carried_dim: int = 0
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
var _uvtt_save_dialog: FileDialog
var _uvtt_open_dialog: FileDialog

var _doc: MapDocument = null
var _stack: CommandStack = null
## Ruta aldea → edificio (F3); el mapa mostrado es `_nav.current()`.
var _nav: MapNavigator = MapNavigator.new()
var _back_btn: Button
var _profiles: Array[SystemProfile] = []
var _token_counter: int = 0
## Controles que solo tiene el DM (se ocultan en modo jugador).
var _dm_only: Array[Control] = []
## Partida en red: panel del DM (escritorio) y cliente (modo jugador).
var _net_panel: NetHostPanel = null
var _net_btn: Button = null
var _client: NetClient = null
var _proposals: ProposalStack = null
## Última ficha seleccionada en las vistas (para dársela a un jugador).
var _selected_token: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_profiles()
	_build_ui()
	_status.text = tr("UI_HELP")
	var params: Dictionary = _join_params()
	if not params.is_empty():
		var room: String = params["room"]
		var token: String = params["token"]
		_start_client(room, token)


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
	var gen_btn: Button = _button("UI_GENERATE", _generate_from_text)
	bar.add_child(gen_btn)
	_dm_only.append_array([_code_edit, gen_btn])
	_scale_opt = OptionButton.new()
	for sc_id: String in SCALES:
		_scale_opt.add_item(tr("UI_SCALE_" + sc_id))
	bar.add_child(_scale_opt)
	var rnd_btn: Button = _button("UI_RANDOM", _generate_random)
	bar.add_child(rnd_btn)
	_dm_only.append_array([_scale_opt, rnd_btn])
	_back_btn = _button("UI_NAV_BACK", _go_back)
	_back_btn.visible = false
	bar.add_child(_back_btn)

	_system_opt = OptionButton.new()
	for p: SystemProfile in _profiles:
		_system_opt.add_item(tr(p.name_key))
	_system_opt.item_selected.connect(func(_i: int) -> void: _apply_profile())
	bar.add_child(_system_opt)

	_grid_opt = OptionButton.new()
	for g: String in GRID_OPTIONS:
		_grid_opt.add_item(tr("UI_GRID_" + g.to_upper()))
	bar.add_child(_grid_opt)
	_dm_only.append_array([_system_opt, _grid_opt])

	_units_opt = OptionButton.new()
	for k: String in UNIT_OPTIONS:
		_units_opt.add_item(tr(k))
	_units_opt.item_selected.connect(func(_i: int) -> void: _apply_units())
	bar.add_child(_units_opt)

	_level_opt = OptionButton.new()
	_level_opt.item_selected.connect(_on_level_selected)
	bar.add_child(_level_opt)

	var add_btn: Button = _button("UI_ADD_TOKEN", _add_token)
	bar.add_child(add_btn)
	_undo_btn = _button("UI_UNDO", _undo)
	_redo_btn = _button("UI_REDO", _redo)
	bar.add_child(_undo_btn)
	bar.add_child(_redo_btn)
	bar.add_child(_button("UI_FIT", _fit))
	bar.add_child(_button("UI_EXPORT_PNG", _export_png))
	var uvtt_btn: Button = _button("UI_EXPORT_UVTT", _export_uvtt)
	bar.add_child(uvtt_btn)
	_dm_only.append_array([add_btn, _undo_btn, _redo_btn, uvtt_btn])
	# En web no hay diálogo para abrir ficheros locales (de momento solo se
	# exporta, con descarga).
	if not OS.has_feature("web"):
		bar.add_child(_button("UI_IMPORT_UVTT", _import_uvtt))
		# Partida en red: el servidor solo puede abrirlo la app de escritorio.
		_net_btn = _button("UI_NET_HOST", _toggle_net_panel)
		_net_btn.toggle_mode = true
		bar.add_child(_net_btn)

	_view_opt = OptionButton.new()
	for k: String in VIEW_OPTIONS:
		_view_opt.add_item(tr(k))
	_view_opt.item_selected.connect(func(_i: int) -> void: _apply_view())
	bar.add_child(_view_opt)
	_audience_opt = OptionButton.new()
	_audience_opt.add_item(tr("UI_AUDIENCE_DM"))
	_audience_opt.add_item(tr("UI_AUDIENCE_PLAYERS"))
	_audience_opt.item_selected.connect(func(_i: int) -> void: _refresh_vision())
	bar.add_child(_audience_opt)
	_ambient_chk = CheckBox.new()
	_ambient_chk.text = tr("UI_AMBIENT_LIT")
	_ambient_chk.toggled.connect(func(_b: bool) -> void: _refresh_vision())
	bar.add_child(_ambient_chk)
	_torch_chk = CheckBox.new()
	_torch_chk.text = tr("UI_CARRY_TORCH")
	_torch_chk.button_pressed = true
	_torch_chk.toggled.connect(func(_b: bool) -> void: _refresh_vision())
	bar.add_child(_torch_chk)
	_dm_only.append_array([_audience_opt, _ambient_chk, _torch_chk])
	_load_carried_light()

	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	_map_area = Control.new()
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_area.clip_contents = true
	# El área del mapa recoge el ratón y se lo pasa a la vista: con PASS el
	# evento subía hasta este Control raíz (STOP) y la vista no lo recibía.
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	middle.add_child(_map_area)
	if not OS.has_feature("web"):
		_net_panel = NetHostPanel.new()
		_net_panel.visible = false
		middle.add_child(_net_panel)
		_net_panel.move_approved.connect(_on_net_move_approved)
		_net_panel.door_approved.connect(_on_net_door_approved)
		_net_panel.pinged.connect(func(li: int, cell: Vector2i, who: String) -> void: _view.show_ping(li, cell, who))
		_net_panel.assign_requested.connect(_assign_token_to_player)
		_net_panel.status.connect(func(text: String) -> void: _status.text = text)

	_view = MapView2D.new()
	_view.status_changed.connect(func(t: String) -> void: _status.text = t)
	_view.set_process_unhandled_input(false)
	_map_area.add_child(_view)
	_map_area.gui_input.connect(_view.process_input)
	_view.user_command_done.connect(_on_user_command)
	_view.token_selected.connect(func(id: int) -> void:
		_view3d.selected_token = id
		_selected_token = id)
	_view.cell_activated.connect(_on_cell_activated)

	# Vista 3D en su propio SubViewport (mundo 3D propio). El contenedor
	# recoge ratón y teclado y se los pasa a la vista, como en 2D.
	_view3d_box = SubViewportContainer.new()
	_view3d_box.stretch = true
	_view3d_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view3d_box.mouse_filter = Control.MOUSE_FILTER_STOP
	# Sin foco: un SubViewportContainer con el foco se queda también los
	# clics dirigidos a la barra superior (no se podía volver a 2D ni cambiar
	# opciones tras tocar la vista 3D). Las teclas se las pasa main.
	_view3d_box.focus_mode = Control.FOCUS_NONE
	_view3d_box.visible = false
	_map_area.add_child(_view3d_box)
	var sv: SubViewport = SubViewport.new()
	sv.own_world_3d = true
	sv.handle_input_locally = false
	_view3d_box.add_child(sv)
	_view3d = MapView3D.new()
	_view3d.active = false
	sv.add_child(_view3d)
	_view3d_box.gui_input.connect(_on_view3d_input)
	_view3d.status_changed.connect(func(t: String) -> void: _status.text = t)
	_view3d.user_command_done.connect(_on_user_command)
	_view3d.cell_activated.connect(_on_cell_activated)
	_view3d.token_selected.connect(func(id: int) -> void:
		_selected_token = id
		_status.text = tr("UI_TOKEN_SELECTED").replace("{name}", _doc.token(id).name))

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

	_uvtt_save_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "UI_EXPORT_UVTT", OS.SYSTEM_DIR_DOCUMENTS)
	_uvtt_save_dialog.file_selected.connect(_save_uvtt_to)
	_uvtt_open_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "UI_IMPORT_UVTT", OS.SYSTEM_DIR_DOCUMENTS)
	_uvtt_open_dialog.file_selected.connect(_load_uvtt_from)

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
	_token_counter = 0
	if res.doc.seed_code.is_empty():
		res.doc.seed_code = _code_edit.text
	_show_frame(_nav.open_root(res.doc), -1)
	_status.text = _map_summary(res.doc)


## Texto de la barra al abrir un mapa: en un asentamiento, tamaño, edificios
## y población derivada (ADR 027) y cómo entrar en los edificios.
func _map_summary(doc: MapDocument) -> String:
	var parsed: SeedCode = SeedCode.parse(doc.seed_code)
	if parsed.is_valid() and parsed.scale == AldGeneratorG1.SCALE:
		var size_id: String = parsed.params.get("size", "")
		return tr("UI_SETTLEMENT_INFO").replace("{size}", tr("SETTLEMENT_" + size_id.to_upper())) \
			.replace("{buildings}", str(doc.level(0).children.size())) \
			.replace("{population}", str(AldGeneratorG1.population_of(doc))).replace("{code}", doc.seed_code) \
			+ " · " + tr("UI_NAV_HINT")
	if parsed.is_valid() and parsed.scale == EstGeneratorG2.EDI_SCALE and parsed.gen_version == EstGeneratorG2.EDI_GEN:
		return tr("UI_GENERATED").replace("{code}", doc.seed_code) + " · " + tr("UI_NAV_HINT_ROOM")
	return tr("UI_GENERATED").replace("{code}", doc.seed_code)


## Nombre visible de un mapa de la ruta: el edificio por el que se entró o,
## en la raíz, el tamaño del asentamiento o la escala.
func _frame_name(f: MapNavigator.Frame) -> String:
	if f.child != null:
		# Estancia de edificio (paso "misma casilla") o edificio de una aldea.
		return tr(("ROOM_KIND_" if f.keep_positions else "BUILDING_") + f.child.kind.to_upper())
	var parsed: SeedCode = SeedCode.parse(f.doc.seed_code)
	if parsed.is_valid() and parsed.scale == AldGeneratorG1.SCALE:
		var size_id: String = parsed.params.get("size", "")
		return tr("SETTLEMENT_" + size_id.to_upper())
	if parsed.is_valid() and parsed.scale == EstGeneratorG2.EDI_SCALE:
		var type_id: String = parsed.params.get("building_type", "")
		return tr("BUILDING_" + type_id.to_upper())
	return tr("UI_SCALE_" + parsed.scale) if parsed.is_valid() else ""


## Muestra un mapa de la ruta: su documento, su historial de deshacer y el
## nivel `level` (-1 = el de la entrada). Pone el código y los selectores de
## escala, sistema y rejilla como los del mapa.
func _show_frame(f: MapNavigator.Frame, level: int) -> void:
	_set_document(f.doc, f.stack, level)
	var parsed: SeedCode = SeedCode.parse(f.doc.seed_code)
	for i: int in _profiles.size():
		if _profiles[i].seed_code == parsed.system:
			_system_opt.select(i)
	var scale_idx: int = SCALES.find(parsed.scale)
	if scale_idx >= 0:
		_scale_opt.select(scale_idx)
	var grid_idx: int = GRID_OPTIONS.find(f.doc.grid_kind())
	if grid_idx >= 0:
		_grid_opt.select(grid_idx)
	_code_edit.text = f.doc.seed_code
	_apply_profile()
	var up: MapNavigator.Frame = _nav.parent()
	_back_btn.visible = up != null
	if up != null:
		_back_btn.text = tr("UI_NAV_BACK").replace("{name}", _frame_name(up))
	if _view_opt.selected != VIEW_2D:
		_apply_view()


func _set_document(doc: MapDocument, stack: CommandStack, level: int) -> void:
	_doc = doc
	_stack = stack
	if not _stack.changed.is_connected(_refresh_buttons):
		_stack.changed.connect(_refresh_buttons)
	_view.command_stack = _stack
	_view.document = doc
	_view3d.command_stack = _stack
	_view3d.profile = _current_profile()
	_view3d.document = doc
	# Con nombre (no lambda) para no conectarlo dos veces al volver a un mapa.
	if not doc.changed.is_connected(_on_doc_changed):
		doc.changed.connect(_on_doc_changed)
	_level_opt.clear()
	for i: int in doc.level_count():
		_level_opt.add_item(tr("UI_LEVEL").replace("{n}", str(i + 1)))
	# Se abre en el nivel de la entrada: en un edificio con sótano (EDI) el
	# nivel 0 es el sótano y la puerta está en la planta baja.
	var start: int = level if level >= 0 and level < doc.level_count() else _entrance_level(doc)
	_level_opt.select(start)
	_view.level_index = start
	_view3d.level_index = start
	# La 1ª persona sigue a una ficha del grupo de este mapa (los ids cambian
	# al pasar de un mapa a otro).
	for t: MapToken in doc.tokens:
		if t.level == start and PartyVision.SIDES_IN_PARTY.has(t.side):
			_view3d.selected_token = t.id
			break
	_fit.call_deferred()
	_refresh_buttons()
	_refresh_vision()
	_share_document()


func _on_doc_changed(_level: int, layer: String) -> void:
	if layer != MapDocument.LAYER_FOG:
		_queue_vision()
	if _net_panel != null:
		_net_panel.mark_dirty()
		if layer == MapDocument.LAYER_TOKENS:
			_net_panel.refresh()


# --- Navegación aldea → edificio (F3) -----------------------------------------

## Doble clic en una casilla: si es la huella de un edificio, entra en él con
## las fichas del grupo de este nivel.
func _on_cell_activated(cell: Vector2i) -> void:
	if _doc == null:
		return
	if _client != null:
		# Modo jugador: doble clic = señalar la casilla a todos.
		_client.send_ping(_view.level_index, cell)
		return
	var child: MapChild = _doc.level(_view.level_index).child_at(cell)
	# Estancia de un edificio (EST G2, ADR 029): se calcula al vuelo, el
	# documento EDI no guarda hijos. Es el mismo sitio a la misma escala, así
	# que las fichas que ya están en ella pasan a su misma casilla.
	var room: bool = false
	if child == null:
		var ref: EstGeneratorG2.RoomRef = _room_ref_at(_view.level_index, cell)
		if ref != null:
			child = ref.to_map_child()
			room = true
	if child == null:
		return
	var f: MapNavigator.Frame = _nav.enter(child, _view.level_index, _current_profile(), room)
	if f == null:
		_status.text = tr(_nav.error)
		return
	_show_frame(f, f.level_index)
	_explore_after_navigation()
	var key: String = "UI_NAV_ENTERED_ROOM" if room else "UI_NAV_ENTERED"
	_status.text = tr(key).replace("{name}", _frame_name(f)).replace("{code}", f.doc.seed_code)


## Estancia del edificio mostrado (si es EDI G1) que contiene la casilla.
func _room_ref_at(level: int, cell: Vector2i) -> EstGeneratorG2.RoomRef:
	var sc: SeedCode = SeedCode.parse(_doc.seed_code)
	if not sc.is_valid() or sc.scale != EstGeneratorG2.EDI_SCALE or sc.gen_version != EstGeneratorG2.EDI_GEN:
		return null
	return EstGeneratorG2.room_at(_doc.seed_code, level, cell)


## Vuelve al mapa padre sacando al grupo por la puerta.
func _go_back() -> void:
	var here: MapNavigator.Frame = _nav.current()
	var kept: bool = here != null and here.keep_positions
	var f: MapNavigator.Frame = _nav.back(_current_profile())
	if f == null:
		_status.text = tr(_nav.error)
		return
	_show_frame(f, f.level_index)
	_explore_after_navigation()
	var key: String = "UI_NAV_RETURNED_ROOM" if kept else "UI_NAV_RETURNED"
	_status.text = tr(key).replace("{name}", _frame_name(f))


## Explora lo que ve el grupo al llegar. No se puede deshacer: el paso de un
## mapa a otro tampoco (MapNavigator vacía la historia).
func _explore_after_navigation() -> void:
	_on_user_command()
	_stack.clear()


## Primer nivel con una zona "entrance" (0 si no hay ninguna).
func _entrance_level(doc: MapDocument) -> int:
	for li: int in doc.level_count():
		for r: MapRoom in doc.level(li).rooms:
			if r.kind == MapRoom.KIND_ENTRANCE:
				return li
	return 0


func _apply_profile() -> void:
	_share_document()
	_view.profile = _current_profile()
	_view.queue_redraw()
	if _view3d != null:
		_view3d.profile = _current_profile()
		_view3d.mark_dirty()


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
	if _view3d != null:
		_view3d.unit_system = _view.unit_system
		_view3d.unit_mode = _view.unit_mode


func _on_level_selected(i: int) -> void:
	_view.level_index = i
	_view.queue_redraw()
	_view3d.level_index = i
	if _view_opt.selected == VIEW_FP:
		_view3d.set_mode(MapView3D.Mode.FIRST_PERSON)
	_refresh_vision()


func _fit() -> void:
	if _client != null and _doc != null:
		# Modo jugador: el mapa entero es casi todo desconocido; se encuadra
		# lo explorado en el nivel mostrado.
		var known: Rect2i = _explored_bounds(_view.level_index)
		if known.size.x > 0:
			_view.fit_region(known, Rect2(Vector2.ZERO, _map_area.size))
			return
	_view.fit_to(Rect2(Vector2.ZERO, _map_area.size))
	if _view3d != null and _view_opt.selected == VIEW_3D:
		_view3d.fit()


# --- Vistas y niebla (F2) -----------------------------------------------------

## Cambia entre 2D, 3D cenital y 1ª persona. Devuelve los ms que tardó en
## tener la vista lista (criterio de F2: < 500 ms).
func _apply_view() -> int:
	var t0: int = Time.get_ticks_msec()
	var sel: int = _view_opt.selected
	_view.visible = sel == VIEW_2D
	_view3d_box.visible = sel != VIEW_2D
	_view3d.active = sel != VIEW_2D
	if sel != VIEW_2D:
		_view3d.level_index = _view.level_index
		_view3d.set_mode(MapView3D.Mode.FIRST_PERSON if sel == VIEW_FP else MapView3D.Mode.TOP)
		_view3d.rebuild()
		_release_text_focus()
		if sel == VIEW_FP and _doc != null and _doc.token(_view3d.selected_token) == null:
			_status.text = tr("UI_FP_NEEDS_TOKEN")
		elif sel == VIEW_FP:
			_status.text = tr("UI_FP_HELP")
		else:
			_status.text = tr("UI_3D_HELP")
	else:
		_status.text = tr("UI_HELP")
	return Time.get_ticks_msec() - t0


func _on_view3d_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		_release_text_focus()
	_view3d.process_input(event)
	_view3d_box.accept_event()


## Quita el foco de la caja del código (u otro control) para que W/A/S/D y
## Q/E lleguen a la vista 3D en vez de escribirse.
func _release_text_focus() -> void:
	var f: Control = get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()


func _players_view() -> bool:
	return _audience_opt.selected == 1


func _load_carried_light() -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var e: ObjectCatalog.Entry = cat.entry(CARRIED_LIGHT_OBJECT) if cat.error.is_empty() else null
	if e != null:
		_carried_bright = e.light_bright_cells
		_carried_dim = e.light_dim_cells


func _vision_options() -> PartyVision.Options:
	var o: PartyVision.Options = PartyVision.Options.new()
	o.ambient_lit = _ambient_chk.button_pressed
	if _torch_chk.button_pressed:
		o.carried_bright = _carried_bright
		o.carried_dim = _carried_dim
	return o


func _queue_vision() -> void:
	if _vision_dirty:
		return
	_vision_dirty = true
	_refresh_vision.call_deferred()


## Recalcula lo que ve el grupo y se lo pasa a las vistas. La niebla solo se
## pinta en la vista de jugadores; el DM lo ve todo.
func _refresh_vision() -> void:
	_vision_dirty = false
	if _doc == null:
		return
	var lvl_i: int = _view.level_index
	if _client != null:
		# Modo jugador: lo visible lo calcula el servidor (niebla filtrada en
		# el servidor, ADR 031) y la niebla viene en la copia del mapa.
		var seen: PackedByteArray = _client.visible_of(lvl_i)
		if seen.is_empty():
			seen.resize(_doc.grid.cell_count())
			seen.fill(0)
		var known: PackedByteArray = _doc.level(lvl_i).explored(PartyVision.VIEWER_PARTY)
		_view.dm_view = false
		_view.set_fog(true, seen, known)
		_view3d.dm_view = false
		_view3d.set_fog(true, seen, known)
		return
	if _net_panel != null:
		_net_panel.set_vision_options(_vision_options())
	var players: bool = _players_view()
	var r: PartyVision.Result = PartyVision.compute(_doc, lvl_i, _current_profile(), _vision_options())
	var explored: PackedByteArray = _doc.level(lvl_i).explored(PartyVision.VIEWER_PARTY)
	_view.dm_view = not players
	_view.set_fog(players, r.visible, explored)
	_view3d.dm_view = not players
	_view3d.set_fog(players, r.visible, explored)


## Tras mover una ficha, abrir una puerta o añadir una ficha: explora lo que
## ve ahora el grupo, unido al mismo paso de deshacer.
func _on_user_command() -> void:
	if _doc == null or _stack == null or _client != null:
		return
	var lvl_i: int = _view.level_index
	var r: PartyVision.Result = PartyVision.compute(_doc, lvl_i, _current_profile(), _vision_options())
	_stack.execute_attached(ExploreCommand.from_visible(_doc, lvl_i, PartyVision.VIEWER_PARTY, r.visible))
	_refresh_vision()


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
		_on_user_command()
		_status.text = tr("UI_TOKEN_ADDED").replace("{name}", t.name)
		return


## Casillas transitables ordenadas por distancia (en pasos, sin cruzar
## muros) a la entrada del nivel; al final, las no alcanzables en orden.
func _cells_by_entrance_distance(lvl: MapLevel, mask: PackedByteArray) -> Array[Vector2i]:
	var g: GridGeometry = _doc.grid
	var seeds: Array[Vector2i] = []
	# En un asentamiento (sin entrada) la ficha sale en la plaza.
	for kind: String in [MapRoom.KIND_ENTRANCE, MapRoom.KIND_EXIT, MapRoom.KIND_PLAZA]:
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
			if dir < g.edge_direction_count() and not MapEdge.is_traversable(lvl.get_edge(c, dir)):
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


## Diálogo nativo de ficheros Universal VTT.
func _file_dialog(mode: FileDialog.FileMode, title_key: String, start_dir: OS.SystemDir) -> FileDialog:
	var dlg: FileDialog = FileDialog.new()
	dlg.file_mode = mode
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.uvtt, *.dd2vtt ; Universal VTT"])
	dlg.use_native_dialog = true
	dlg.title = tr(title_key)
	dlg.current_dir = OS.get_system_dir(start_dir)
	add_child(dlg)
	return dlg


# --- Universal VTT (F3, ADR 030) ------------------------------------------------

## Píxeles por casilla de la imagen exportada: 100 como el PNG, menos en mapas
## grandes para no pasar de 8192 px (límite seguro de textura; una ciudad de
## 212 casillas a 100 px daba 21 200 px).
func _uvtt_px_per_cell() -> int:
	var size: Vector2 = _doc.grid.map_pixel_size(1.0)
	return clampi(floori(8192.0 / maxf(size.x, size.y)), 16, PngExporter.DEFAULT_PX_PER_CELL)


## Texto UVTT del nivel mostrado: imagen sin rejilla ni fichas (la otra mesa
## pone las suyas) y lo que ven los jugadores (secretas sin descubrir = muro).
func _uvtt_text() -> String:
	var ppc: int = _uvtt_px_per_cell()
	var img: Image = await PngExporter.render(self, _doc, _view.level_index, _current_profile(), ppc, false, false, false)
	var png: PackedByteArray = img.save_png_to_buffer() if img != null and not img.is_empty() else PackedByteArray()
	return UvttCodec.to_json(UvttCodec.export_level(_doc, _view.level_index, png, ppc, false))


func _export_uvtt() -> void:
	if _doc == null:
		return
	var file_name: String = (_doc.seed_code if not _doc.seed_code.is_empty() else "mapa") + ".uvtt"
	if OS.has_feature("web"):
		var text: String = await _uvtt_text()
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/json")
		_status.text = tr("UI_EXPORTED").replace("{path}", file_name)
		return
	_uvtt_save_dialog.current_file = file_name
	_uvtt_save_dialog.popup_centered_ratio(0.6)


func _save_uvtt_to(path: String) -> void:
	var text: String = await _uvtt_text()
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = tr("UI_EXPORT_FAILED")
		return
	f.store_string(text)
	f.close()
	_status.text = tr("UI_EXPORTED").replace("{path}", path)


func _import_uvtt() -> void:
	_uvtt_open_dialog.popup_centered_ratio(0.6)


func _load_uvtt_from(path: String) -> void:
	if not FileAccess.file_exists(path):
		_status.text = tr("UVTT_ERR_JSON")
		return
	open_uvtt_text(FileAccess.get_file_as_string(path), path.get_file())


## Abre un mapa importado como raíz de una ruta nueva (también lo usan los
## tests). Devuelve false si el fichero no era válido.
func open_uvtt_text(text: String, file_name: String) -> bool:
	var res: UvttCodec.ImportResult = UvttCodec.import_text(text)
	if res.doc == null:
		_status.text = tr(res.error)
		return false
	_token_counter = 0
	_show_frame(_nav.open_root(res.doc), 0)
	var msg: String = tr("UI_UVTT_IMPORTED").replace("{file}", file_name) \
		.replace("{w}", str(res.doc.grid.width)).replace("{h}", str(res.doc.grid.height)) \
		.replace("{walls}", str(res.walls)).replace("{doors}", str(res.doors)).replace("{lights}", str(res.lights))
	if res.approximated_length >= 0.5:
		msg += " · " + tr("UI_UVTT_DROPPED").replace("{n}", str(roundi(res.approximated_length)))
	_status.text = msg
	return true


func _save_png_to(path: String) -> void:
	var err: Error = await PngExporter.save(self, _doc, _view.level_index, _current_profile(), path)
	_status.text = tr("UI_EXPORTED").replace("{path}", path) if err == OK else tr("UI_EXPORT_FAILED")


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed:
		return
	if not k.ctrl_pressed:
		# Teclas de cámara y de 1ª persona, solo con la vista 3D activa.
		if _view3d != null and _view3d.active:
			_view3d.process_input(k)
			get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_Z and not k.shift_pressed:
		_undo()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed):
		_redo()
		get_viewport().set_input_as_handled()


# --- Partida en red (F4, ADR 031) ---------------------------------------------

func _toggle_net_panel() -> void:
	_net_panel.visible = _net_btn.button_pressed
	_fit.call_deferred()


## El panel del DM comparte el mapa mostrado (y su sistema) con los jugadores.
func _share_document() -> void:
	if _net_panel == null or _doc == null:
		return
	var f: MapNavigator.Frame = _nav.current()
	_net_panel.set_document(_doc, _current_profile(), _frame_name(f) if f != null and f.doc == _doc else "")


## Movimiento de un jugador ya validado por la sesión: se ejecuta en el
## historial del DM (puede deshacerlo) y explora como cualquier otro.
func _on_net_move_approved(cmd: MoveTokenCommand) -> void:
	if _stack == null or _doc == null or _doc.token(cmd.token_id) == null:
		return
	if _stack.execute(cmd):
		_on_user_command()


## Puerta abierta o cerrada por un jugador (validada por la sesión): igual
## que un movimiento, va al historial del DM y recalcula lo que se ve.
func _on_net_door_approved(cmd: SetEdgeCommand) -> void:
	if _stack == null or _doc == null or _doc.level(cmd.level_index) == null:
		return
	if _stack.execute(cmd):
		_on_user_command()


func _assign_token_to_player(player_ref: String, player_name: String) -> void:
	var t: MapToken = _doc.token(_selected_token) if _doc != null else null
	if t == null:
		_status.text = tr("UI_NET_SELECT_TOKEN")
		return
	_stack.execute(SetTokenCharacterCommand.new(t.id, player_ref))
	_status.text = tr("UI_NET_ASSIGNED").replace("{token}", t.name).replace("{name}", player_name)


## Parámetros de invitación de la URL de la página (?sala=…&t=…) en web; {}
## si no los hay (app normal).
func _join_params() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var search: Variant = JavaScriptBridge.eval("window.location.search")
	if typeof(search) != TYPE_STRING:
		return {}
	var query: String = search
	var room: String = ""
	var token: String = ""
	for part: String in query.trim_prefix("?").split("&"):
		var kv: PackedStringArray = part.split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "sala":
			room = kv[1].uri_decode()
		elif kv[0] == "t":
			token = kv[1].uri_decode()
	if room.is_empty() or token.is_empty():
		return {}
	return {"room": room, "token": token}


## Modo jugador: se conecta al WSS del mismo origen que la página.
func _start_client(room: String, token: String) -> void:
	for c: Control in _dm_only:
		c.visible = false
	_audience_opt.select(1)
	_proposals = ProposalStack.new()
	_proposals.accept = _propose
	_client = NetClient.new()
	_client.map_reset.connect(_on_client_map)
	_client.vision_changed.connect(func(_i: int) -> void: _queue_vision())
	_client.pinged.connect(func(li: int, cell: Vector2i, who: String) -> void: _view.show_ping(li, cell, who))
	_client.notice.connect(func(key: String) -> void: _status.text = tr(key))
	_client.denied.connect(func(key: String) -> void: _status.text = tr(key))
	_client.closed.connect(func() -> void: _status.text = tr("NET_CLOSED"))
	_client.welcomed.connect(func(_n: String) -> void: _status.text = _client_welcome())
	var host: Variant = JavaScriptBridge.eval("window.location.host")
	var url: String = "wss://%s/ws" % str(host)
	if _client.connect_to(url, room, token) != OK:
		_status.text = tr("NET_CLOSED")
		return
	_status.text = tr("NET_CONNECTING")


func _client_welcome() -> String:
	return tr("NET_WELCOME").replace("{name}", _client.player_name).replace("{title}", _client.title)


func _process(_delta: float) -> void:
	if _client != null:
		_client.poll()


## Mapa nuevo del servidor: se muestra en el nivel de la ficha propia.
func _on_client_map() -> void:
	for i: int in _profiles.size():
		if _profiles[i].seed_code == _client.system_code:
			_system_opt.select(i)
	_view.profile = _current_profile()
	_view3d.profile = _current_profile()
	_set_document(_client.document, _proposals, 0)
	_status.text = _client_welcome()
	# Las fichas llegan después del mapa: al llegar, se va al nivel de la propia.
	if not _client.document.changed.is_connected(_follow_own_token):
		_client.document.changed.connect(_follow_own_token)


## La primera vez que llegan las fichas (después de los niveles), muestra el
## nivel de la propia y encuadra lo explorado.
func _follow_own_token(_level: int, layer: String) -> void:
	if layer != MapDocument.LAYER_TOKENS or _client == null:
		return
	_client.document.changed.disconnect(_follow_own_token)
	for t: MapToken in _client.document.tokens:
		if _client.owns(t) and t.level != _view.level_index:
			_level_opt.select(t.level)
			_on_level_selected(t.level)
			break
	_fit.call_deferred()


## Rectángulo de casillas exploradas del nivel (vacío si no hay ninguna).
func _explored_bounds(level: int) -> Rect2i:
	var lvl: MapLevel = _doc.level(level)
	if lvl == null:
		return Rect2i()
	var known: PackedByteArray = lvl.explored(PartyVision.VIEWER_PARTY)
	var lo: Vector2i = Vector2i(1 << 30, 1 << 30)
	var hi: Vector2i = Vector2i(-1, -1)
	for i: int in known.size():
		if known[i] != 0:
			var c: Vector2i = _doc.grid.cell_at(i)
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Lo que una vista "ejecuta" en modo jugador se envía como propuesta: mover
## fichas propias y abrir o cerrar puertas (el DM las valida; las escaleras y
## lo demás lo hace el DM).
func _propose(cmd: MapCommand) -> bool:
	if _client == null:
		return false
	var door: SetEdgeCommand = cmd as SetEdgeCommand
	if door != null:
		var old: int = _client.document.level(door.level_index).get_edge_by_id(door.edge_id)
		if not MapEdge.is_door(old) or MapEdge.with_flag(old, MapEdge.FLAG_OPEN, false) != MapEdge.with_flag(door.new_value, MapEdge.FLAG_OPEN, false):
			return false
		_client.propose_door(door.level_index, door.edge_id, MapEdge.has_flag(door.new_value, MapEdge.FLAG_OPEN))
		return true
	var mv: MoveTokenCommand = cmd as MoveTokenCommand
	if mv == null:
		return false
	if not _client.owns(_client.document.token(mv.token_id)):
		_status.text = tr("NET_MOVE_NOT_YOURS")
		return false
	_client.propose_move(mv.token_id, mv.to_level, mv.to_cell)
	return true
