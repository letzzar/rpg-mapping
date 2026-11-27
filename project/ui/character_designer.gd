class_name CharacterDesigner
extends ConfirmationDialog
## Diseñador de personajes (PROYECTO §10.2, ADR 034). Edita una copia de un
## CharacterSheet: modelo tipo, nombre, tamaño, velocidades y sentidos del
## perfil activo, iniciativa, retrato, complexión, una pieza por ranura y un
## color por material, con la ficha 2D y la figura 3D a la vista. Al aceptar
## emite `applied` con la hoja; quien lo abre decide qué hacer con ella (la
## pantalla principal la pone en la ficha con un comando que se deshace).
##
## Guardar y abrir *.rpgm-char.json: en escritorio con el diálogo del
## sistema; en web, guardar descarga el fichero.

signal applied(sheet: CharacterSheet)

const PREVIEW_PX: int = 220

## Formatea pies para mostrarlos (Units.format_distance con las unidades
## activas); la pone quien abre el diseñador.
var format_ft: Callable = func(ft: int) -> String: return str(ft) + " ft"

var _profile: SystemProfile = null
var _sheet: CharacterSheet = CharacterSheet.new()
var _cat: LookCatalog = null
var _updating: bool = false

var _preset_opt: OptionButton
var _name_edit: LineEdit
var _size_opt: OptionButton
var _speed_spins: Dictionary[String, SpinBox] = {}
var _speed_labels: Dictionary[String, Label] = {}
var _sense_spins: Dictionary[String, SpinBox] = {}
var _sense_labels: Dictionary[String, Label] = {}
var _init_chk: CheckBox
var _init_spin: SpinBox
var _body_opt: OptionButton
var _slots_grid: GridContainer
var _colors_grid: GridContainer
var _moves_grid: GridContainer
var _senses_grid: GridContainer
var _portrait_clear: Button
var _preview2d: Control
var _preview_tex: Texture2D = null
var _fig: MeshInstance3D
var _rig: Node3D = null
var _pivot: Node3D
var _open_dialog: FileDialog = null
var _save_dialog: FileDialog = null
var _portrait_dialog: FileDialog = null


func _init() -> void:
	title = tr("UI_CHAR_TITLE")
	ok_button_text = tr("UI_CHAR_APPLY")
	# El texto por defecto ("Cancel") sale en inglés en las exportaciones.
	cancel_button_text = tr("UI_CANCEL")
	exclusive = true
	_cat = LookCatalog.load_default()
	_build()
	confirmed.connect(func() -> void: applied.emit(_sheet.copy()))
	custom_action.connect(_on_custom_action)


## Abre el diseñador con una copia de `sheet` para el perfil `profile`.
func edit(sheet: CharacterSheet, profile: SystemProfile) -> void:
	_profile = profile
	_sheet = sheet.copy() if sheet != null else CharacterSheet.new()
	if _profile != null:
		_sheet.system = _profile.id
	_cat.sanitize(_sheet.look)
	_rebuild_rules_rows()
	_refresh_all()
	popup_centered(Vector2i(980, 640))


## Hoja tal y como está ahora (para los tests).
func current_sheet() -> CharacterSheet:
	return _sheet.copy()


# --- Construcción -------------------------------------------------------------

func _build() -> void:
	var root: HBoxContainer = HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	add_child(root)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 520)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var form: VBoxContainer = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	var top: GridContainer = _grid(form, "")
	_preset_opt = OptionButton.new()
	_preset_opt.add_item(tr("UI_CHAR_PRESET_NONE"))
	for p: LookCatalog.Preset in _cat.presets:
		_preset_opt.add_item(tr("CHAR_PRESET_" + p.id.to_upper()))
	_preset_opt.item_selected.connect(_on_preset)
	_row(top, "UI_CHAR_PRESET", _preset_opt)
	_name_edit = LineEdit.new()
	_name_edit.text_changed.connect(func(t: String) -> void:
		_sheet.name = t.strip_edges())
	_row(top, "UI_CHAR_NAME", _name_edit)
	_size_opt = OptionButton.new()
	_size_opt.item_selected.connect(func(i: int) -> void:
		if not _updating and _profile != null:
			_sheet.size_id = _profile.size_ids[i]
			_refresh_previews())
	_row(top, "UI_CHAR_SIZE", _size_opt)
	_init_chk = CheckBox.new()
	_init_chk.text = tr("UI_CHAR_HAS_INITIATIVE")
	_init_spin = SpinBox.new()
	_init_spin.min_value = -20
	_init_spin.max_value = 40
	var init_box: HBoxContainer = HBoxContainer.new()
	init_box.add_child(_init_chk)
	init_box.add_child(_init_spin)
	_init_chk.toggled.connect(func(on: bool) -> void:
		_sheet.has_initiative = on
		_init_spin.editable = on)
	_init_spin.value_changed.connect(func(v: float) -> void:
		_sheet.initiative = int(v))
	_row(top, "UI_CHAR_INITIATIVE", init_box)
	var portrait_box: HBoxContainer = HBoxContainer.new()
	if not OS.has_feature("web"):
		var load_btn: Button = Button.new()
		load_btn.text = tr("UI_CHAR_PORTRAIT_LOAD")
		load_btn.pressed.connect(_pick_portrait)
		portrait_box.add_child(load_btn)
	_portrait_clear = Button.new()
	_portrait_clear.text = tr("UI_CHAR_PORTRAIT_CLEAR")
	_portrait_clear.pressed.connect(func() -> void:
		_sheet.portrait_png = PackedByteArray()
		_refresh_previews())
	portrait_box.add_child(_portrait_clear)
	_row(top, "UI_CHAR_PORTRAIT", portrait_box)

	_moves_grid = _grid(form, "UI_CHAR_SPEEDS")
	_senses_grid = _grid(form, "UI_CHAR_SENSES")

	var look: GridContainer = _grid(form, "UI_CHAR_LOOK")
	_body_opt = OptionButton.new()
	for b: LookCatalog.Body in _cat.bodies:
		_body_opt.add_item(tr("CHAR_BODY_" + b.id.to_upper()))
	_body_opt.item_selected.connect(func(i: int) -> void:
		if _updating:
			return
		var b: LookCatalog.Body = _cat.bodies[i]
		var colors: Dictionary[String, Color] = _sheet.look.colors
		_sheet.look = _cat.default_look(b.id)
		_sheet.look.colors = colors
		_refresh_look())
	_row(look, "UI_CHAR_BODY", _body_opt)
	_slots_grid = GridContainer.new()
	_slots_grid.columns = 2
	form.add_child(_slots_grid)
	_colors_grid = _grid(form, "UI_CHAR_COLORS")
	_colors_grid.columns = 4
	for m: String in _cat.materials:
		var lbl: Label = Label.new()
		lbl.text = tr("CHAR_MAT_" + m.to_upper())
		_colors_grid.add_child(lbl)
		var pick: ColorPickerButton = ColorPickerButton.new()
		pick.name = m
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(64, 28)
		pick.color_changed.connect(func(c: Color) -> void:
			_sheet.look.colors[m] = c
			_refresh_previews())
		_colors_grid.add_child(pick)

	var side: VBoxContainer = VBoxContainer.new()
	root.add_child(side)
	_preview2d = Control.new()
	_preview2d.custom_minimum_size = Vector2(PREVIEW_PX, 140)
	_preview2d.draw.connect(_draw_preview2d)
	side.add_child(_preview2d)
	var box: SubViewportContainer = SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(PREVIEW_PX, 300)
	side.add_child(box)
	var sv: SubViewport = SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	box.add_child(sv)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b1d14")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.7, 0.62)
	e.ambient_light_energy = 0.7
	env.environment = e
	sv.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sv.add_child(sun)
	var cam: Camera3D = Camera3D.new()
	var eye: Vector3 = Vector3(0, 0.75, 2.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.55, 0) - eye), eye)
	cam.fov = 40.0
	sv.add_child(cam)
	_pivot = Node3D.new()
	sv.add_child(_pivot)
	_fig = MeshInstance3D.new()
	_pivot.add_child(_fig)
	var hint: Label = Label.new()
	hint.text = tr("UI_CHAR_PREVIEW_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(PREVIEW_PX, 0)
	side.add_child(hint)

	add_button(tr("UI_CHAR_SAVE"), false, "save")
	if not OS.has_feature("web"):
		add_button(tr("UI_CHAR_OPEN"), false, "open")


func _grid(parent: Control, title_key: String) -> GridContainer:
	if not title_key.is_empty():
		var h: Label = Label.new()
		h.text = tr(title_key)
		h.add_theme_color_override("font_color", Color("f7dc8e"))
		parent.add_child(HSeparator.new())
		parent.add_child(h)
	var g: GridContainer = GridContainer.new()
	g.columns = 2
	parent.add_child(g)
	return g


func _row(g: GridContainer, key: String, ctl: Control) -> void:
	var lbl: Label = Label.new()
	lbl.text = tr(key)
	lbl.custom_minimum_size = Vector2(170, 0)
	g.add_child(lbl)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctl)


## Filas que dependen del perfil: tamaños, modos de movimiento y sentidos.
func _rebuild_rules_rows() -> void:
	_size_opt.clear()
	for g: GridContainer in [_moves_grid, _senses_grid]:
		for c: Node in g.get_children():
			g.remove_child(c)
			c.queue_free()
	_speed_spins.clear()
	_speed_labels.clear()
	_sense_spins.clear()
	_sense_labels.clear()
	if _profile == null:
		return
	for s: String in _profile.size_ids:
		_size_opt.add_item(tr("SIZE_" + s.to_upper()))
	var modes: PackedStringArray = _profile.movement_modes.duplicate()
	if not modes.has("walk"):
		modes.insert(0, "walk")
	for m: String in modes:
		_add_distance_row(_moves_grid, "MOVE_" + m.to_upper(), m, true)
	for s: String in _profile.senses:
		_add_distance_row(_senses_grid, "SENSE_" + s.to_upper(), s, false)


func _add_distance_row(g: GridContainer, key: String, id: String, is_speed: bool) -> void:
	var box: HBoxContainer = HBoxContainer.new()
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 1000
	spin.step = 5
	spin.suffix = "ft"
	spin.custom_minimum_size = Vector2(110, 0)
	var shown: Label = Label.new()
	shown.custom_minimum_size = Vector2(90, 0)
	box.add_child(spin)
	box.add_child(shown)
	_row(g, key, box)
	if is_speed:
		_speed_spins[id] = spin
		_speed_labels[id] = shown
	else:
		_sense_spins[id] = spin
		_sense_labels[id] = shown
	spin.value_changed.connect(func(v: float) -> void:
		if _updating:
			return
		var ft: int = int(v)
		var dict: Dictionary[String, int] = _sheet.speeds if is_speed else _sheet.senses
		if ft > 0:
			dict[id] = ft
		else:
			dict.erase(id)
		shown.text = "= " + str(format_ft.call(ft)) if ft > 0 else "")


# --- Refresco -----------------------------------------------------------------

func _refresh_all() -> void:
	_updating = true
	_preset_opt.select(0)
	_name_edit.text = _sheet.name
	if _profile != null:
		var si: int = _profile.size_ids.find(_sheet.size_id)
		if si < 0:
			si = _profile.size_ids.find("medium")
			_sheet.size_id = _profile.size_ids[maxi(0, si)]
		_size_opt.select(maxi(0, si))
	for m: String in _speed_spins:
		var v: int = _sheet.speeds.get(m, 0)
		_speed_spins[m].value = v
		_speed_labels[m].text = "= " + str(format_ft.call(v)) if v > 0 else ""
	for s: String in _sense_spins:
		var v: int = _sheet.senses.get(s, 0)
		_sense_spins[s].value = v
		_sense_labels[s].text = "= " + str(format_ft.call(v)) if v > 0 else ""
	_init_chk.button_pressed = _sheet.has_initiative
	_init_spin.value = _sheet.initiative
	_init_spin.editable = _sheet.has_initiative
	_updating = false
	_refresh_look()


func _refresh_look() -> void:
	_updating = true
	var bi: int = 0
	for i: int in _cat.bodies.size():
		if _cat.bodies[i].id == _sheet.look.body:
			bi = i
	_body_opt.select(bi)
	for c: Node in _slots_grid.get_children():
		_slots_grid.remove_child(c)
		c.queue_free()
	var b: LookCatalog.Body = _cat.bodies[bi]
	for slot: String in _cat.slots:
		if not b.slots.has(slot):
			continue
		var parts: Array[LookCatalog.Part] = _cat.parts_for(b.id, slot)
		var opt: OptionButton = OptionButton.new()
		opt.name = slot
		opt.add_item(tr("UI_CHAR_PART_NONE"))
		for p: LookCatalog.Part in parts:
			opt.add_item(tr("CHAR_PART_" + p.id.to_upper()))
			if _sheet.look.parts.get(slot, "") == p.id:
				opt.select(opt.item_count - 1)
		opt.item_selected.connect(func(i: int) -> void:
			if i == 0:
				_sheet.look.parts.erase(slot)
			else:
				_sheet.look.parts[slot] = parts[i - 1].id
			_refresh_previews())
		_row(_slots_grid, "CHAR_SLOT_" + slot.to_upper(), opt)
	for c: Node in _colors_grid.get_children():
		var pick: ColorPickerButton = c as ColorPickerButton
		if pick != null:
			pick.color = _cat.color_of(_sheet.look, String(pick.name))
	_updating = false
	_refresh_previews()


func _refresh_previews() -> void:
	var img: Image = _sheet.portrait_image()
	_preview_tex = ImageTexture.create_from_image(img) if img != null else null
	_portrait_clear.disabled = _sheet.portrait_png.is_empty()
	_preview2d.queue_redraw()
	# Modelo con esqueleto (ADR 045): se ve el modelo animado en reposo.
	if _rig != null:
		_rig.queue_free()
		_rig = null
	var body: LookCatalog.Body = _cat.body(_sheet.look.body)
	if body != null and not body.model.is_empty():
		_rig = RiggedFigure.create(body.model)
		if _rig != null:
			var k: float = 1.0 / maxf(RiggedFigure.height_of(body.model), 0.01)
			_rig.scale = Vector3(k, k, k)
			_pivot.add_child(_rig)
	var mesh: ArrayMesh = CharacterModelBuilder.mesh_for(_sheet.look, _cat)
	_fig.mesh = mesh
	_fig.visible = _rig == null
	# Tamaño relativo: una figura grande se ve mayor que una mediana.
	var eye: float = MapView3D.EYE_HEIGHT_M.get(_sheet.size_id, 1.6)
	var h: float = clampf(eye / 1.6, 0.45, 1.0)
	_pivot.scale = Vector3(h, h, h)


func _process(delta: float) -> void:
	if visible and _pivot != null:
		_pivot.rotate_y(delta * 0.6)


func _draw_preview2d() -> void:
	# Grande con el color de los jugadores; pequeñas, con el de los demás
	# bandos (así se ve cómo queda en el mapa sea del bando que sea).
	var r: float = minf(_preview2d.size.x * 0.3, _preview2d.size.y * 0.45)
	TokenPainter.draw(_preview2d, _sheet, Vector2(r * 1.1, _preview2d.size.y * 0.5), r,
		MapView2D.SIDE_COLORS[MapToken.SIDE_PLAYER], _preview_tex)
	var others: PackedStringArray = [MapToken.SIDE_ALLY, MapToken.SIDE_NEUTRAL, MapToken.SIDE_ENEMY]
	var step: float = _preview2d.size.y / others.size()
	var rr: float = minf(r * 0.36, step * 0.42)
	for i: int in others.size():
		var at: Vector2 = Vector2(_preview2d.size.x - rr * 1.3, step * (i + 0.5))
		TokenPainter.draw(_preview2d, _sheet, at, rr, MapView2D.SIDE_COLORS[others[i]], _preview_tex)


# --- Acciones -----------------------------------------------------------------

func _on_preset(i: int) -> void:
	if _updating or i <= 0:
		return
	var p: LookCatalog.Preset = _cat.presets[i - 1]
	_sheet.look = _cat.look_from_preset(p)
	if _profile != null and _profile.size_ids.has(p.size_id):
		_sheet.size_id = p.size_id
	_refresh_all()
	_updating = true
	_preset_opt.select(i)
	_updating = false


func _on_custom_action(action: StringName) -> void:
	if action == &"save":
		_save()
	elif action == &"open":
		_file(FileDialog.FILE_MODE_OPEN_FILE).popup_centered_ratio(0.6)


func _file_name() -> String:
	var base: String = _sheet.name if not _sheet.name.is_empty() else "personaje"
	return base.validate_filename() + CharacterSheet.EXTENSION


func _save() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(_sheet.to_json().to_utf8_buffer(), _file_name(), "application/json")
		return
	var dlg: FileDialog = _file(FileDialog.FILE_MODE_SAVE_FILE)
	dlg.current_file = _file_name()
	dlg.popup_centered_ratio(0.6)


## Diálogo de abrir o guardar *.rpgm-char.json (se crea una vez).
func _file(mode: FileDialog.FileMode) -> FileDialog:
	var existing: FileDialog = _open_dialog if mode == FileDialog.FILE_MODE_OPEN_FILE else _save_dialog
	if existing != null:
		return existing
	var dlg: FileDialog = FileDialog.new()
	dlg.file_mode = mode
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.rpgm-char.json ; " + tr("UI_CHAR_FILE_KIND")])
	dlg.use_native_dialog = true
	dlg.title = tr("UI_CHAR_OPEN" if mode == FileDialog.FILE_MODE_OPEN_FILE else "UI_CHAR_SAVE")
	dlg.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(dlg)
	if mode == FileDialog.FILE_MODE_OPEN_FILE:
		dlg.file_selected.connect(load_file)
		_open_dialog = dlg
	else:
		dlg.file_selected.connect(save_file)
		_save_dialog = dlg
	return dlg


## Guarda la hoja en `path`. true si se pudo.
func save_file(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_alert("UI_CHAR_SAVE_FAILED")
		return false
	f.store_string(_sheet.to_json())
	f.close()
	return true


## Carga una hoja de `path` en el diseñador. true si se pudo.
func load_file(path: String) -> bool:
	var res: CharacterSheet.LoadResult = CharacterSheet.from_json(FileAccess.get_file_as_string(path))
	if res.sheet == null:
		push_warning("%s: %s" % [path, res.error])
		_alert("UI_CHAR_OPEN_FAILED")
		return false
	_sheet = res.sheet
	if _profile != null:
		_sheet.system = _profile.id
	_cat.sanitize(_sheet.look)
	_refresh_all()
	return true


func _pick_portrait() -> void:
	if _portrait_dialog == null:
		_portrait_dialog = FileDialog.new()
		_portrait_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_portrait_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_portrait_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("UI_CHAR_IMAGES")])
		_portrait_dialog.use_native_dialog = true
		_portrait_dialog.title = tr("UI_CHAR_PORTRAIT_LOAD")
		_portrait_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		_portrait_dialog.file_selected.connect(load_portrait)
		add_child(_portrait_dialog)
	_portrait_dialog.popup_centered_ratio(0.6)


## Pone de retrato la imagen de `path` (recortada y reducida). true si valía.
func load_portrait(path: String) -> bool:
	var img: Image = Image.load_from_file(path)
	var png: PackedByteArray = CharacterSheet.portrait_from_image(img)
	if png.is_empty():
		_alert("UI_CHAR_PORTRAIT_FAILED")
		return false
	_sheet.portrait_png = png
	_refresh_previews()
	return true


func _alert(key: String) -> void:
	var a: AcceptDialog = AcceptDialog.new()
	a.dialog_text = tr(key)
	add_child(a)
	a.confirmed.connect(a.queue_free)
	a.popup_centered()
