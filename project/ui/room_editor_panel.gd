class_name RoomEditorPanel
extends PanelContainer
## Panel del editor de estancias (PROYECTO §6.7, E2, ADR 037). Elige la
## herramienta de la vista 2D (terreno, aristas, objetos, borrar objetos),
## cambia tipo y nombre de las salas, avisa si hay suelo sin acceso desde la
## entrada y crea estancias en blanco (EST G3). Todo cambio es un comando
## con deshacer y un delta reaplicable (se guarda con "Guardar mapa").

## Herramienta elegida ("" = ninguna; formato de MapView2D.edit_tool).
signal tool_changed(tool: String)
## Cambió la orientación de los objetos a colocar (0-3).
signal facing_changed(facing: int)
## Pide crear una estancia en blanco de ese tamaño y rejilla.
signal new_room_requested(width: int, height: int, grid: String)

const TERRAIN_TOOLS: PackedStringArray = ["floor", "wall", "void", "rubble", "water_shallow", "water_deep", "pit"]
const EDGE_TOOLS: PackedStringArray = ["wall", "door", "secret_door", "arch", "window", "none"]
## Tipos de sala que se pueden elegir (con nombre en ROOM_KIND_*).
const ROOM_KINDS: PackedStringArray = [
	"room", "corridor", "cave", "entrance", "exit", "tavern", "bedroom", "storage", "temple",
	"library", "kitchen", "forge", "crypt", "hall", "living", "shop", "barracks", "armory",
	"cell", "guardroom",
]
const GRIDS: PackedStringArray = ["square", "hex_flat", "hex_pointy"]

## Abre una estancia recreada (de la biblioteca) como mapa nuevo.
signal room_opened(doc: MapDocument, id: String)
## Mensaje para la barra de estado.
signal status(text: String)

## Ejecuta un comando en el historial del mapa; devuelve si se aplicó.
var execute: Callable = func(_cmd: MapCommand) -> bool: return false
var level_index: int = 0
var library: RoomLibrary = RoomLibrary.new()

var _id_edit: LineEdit
var _share_edit: LineEdit
var _lib_list: ItemList
var _lib_ids: PackedStringArray = PackedStringArray()

var _doc: MapDocument = null
var _group: ButtonGroup = ButtonGroup.new()
var _tool_buttons: Dictionary[String, Button] = {}
var _object_opt: OptionButton
var _object_ids: PackedStringArray = PackedStringArray()
var _facing: int = 0
var _facing_btn: Button
var _room_opt: OptionButton
var _room_ids: PackedInt32Array = PackedInt32Array()
var _kind_opt: OptionButton
var _label_edit: LineEdit
var _check: Label
var _new_w: SpinBox
var _new_h: SpinBox
var _new_grid: OptionButton


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	_group.allow_unpress = true
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_heading(box, "UI_EDIT_TITLE")
	_check = Label.new()
	_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check.custom_minimum_size = Vector2(270, 0)
	box.add_child(_check)

	_heading(box, "UI_EDIT_TERRAIN")
	var tf: HFlowContainer = HFlowContainer.new()
	box.add_child(tf)
	for t: String in TERRAIN_TOOLS:
		tf.add_child(_tool_button("terrain:" + t, tr("TERRAIN_" + t.to_upper())))

	_heading(box, "UI_EDIT_EDGES")
	var ef: HFlowContainer = HFlowContainer.new()
	box.add_child(ef)
	for k: String in EDGE_TOOLS:
		ef.add_child(_tool_button("edge:" + k, tr("UI_EDIT_EDGE_" + k.to_upper())))

	_heading(box, "UI_EDIT_OBJECTS")
	_object_opt = OptionButton.new()
	_fill_objects()
	_object_opt.item_selected.connect(func(_i: int) -> void:
		var b: Button = _tool_buttons["object"]
		b.button_pressed = true
		_emit_tool())
	box.add_child(_object_opt)
	var of: HFlowContainer = HFlowContainer.new()
	box.add_child(of)
	of.add_child(_tool_button("object", tr("UI_EDIT_PLACE")))
	_facing_btn = Button.new()
	_facing_btn.tooltip_text = tr("UI_EDIT_ROTATE_TIP")
	_facing_btn.pressed.connect(rotate)
	of.add_child(_facing_btn)
	of.add_child(_tool_button("erase_object", tr("UI_EDIT_ERASE_OBJECT")))
	_update_facing()

	_heading(box, "UI_EDIT_ROOM")
	_room_opt = OptionButton.new()
	_room_opt.item_selected.connect(func(_i: int) -> void: _show_room())
	box.add_child(_room_opt)
	_kind_opt = OptionButton.new()
	for k: String in ROOM_KINDS:
		_kind_opt.add_item(tr("ROOM_KIND_" + k.to_upper()))
	box.add_child(_kind_opt)
	_label_edit = LineEdit.new()
	_label_edit.placeholder_text = tr("UI_EDIT_ROOM_NAME")
	box.add_child(_label_edit)
	var apply_btn: Button = Button.new()
	apply_btn.text = tr("UI_EDIT_ROOM_APPLY")
	apply_btn.pressed.connect(apply_room)
	box.add_child(apply_btn)

	_heading(box, "UI_ROOM_SHARE")
	var save_btn: Button = Button.new()
	save_btn.text = tr("UI_ROOM_SAVE_LIBRARY")
	save_btn.tooltip_text = tr("UI_ROOM_SAVE_LIBRARY_TIP")
	save_btn.pressed.connect(save_to_library)
	box.add_child(save_btn)
	# Sin QR: decidido por Víctor (el QR es solo para que entren los
	# jugadores; las estancias viajan en los ficheros de guardado).
	_id_edit = _code_row(box, "UI_ROOM_SHORT_ID", "UI_ROOM_SHORT_ID_TIP")
	_share_edit = _code_row(box, "UI_ROOM_SHARE_CODE", "UI_ROOM_SHARE_CODE_TIP")
	var lib_lbl: Label = Label.new()
	lib_lbl.text = tr("UI_ROOM_LIBRARY")
	box.add_child(lib_lbl)
	_lib_list = ItemList.new()
	_lib_list.custom_minimum_size = Vector2(270, 120)
	_lib_list.item_activated.connect(func(i: int) -> void: open_library_room(_lib_ids[i]))
	box.add_child(_lib_list)
	var lr: HFlowContainer = HFlowContainer.new()
	box.add_child(lr)
	var open_btn: Button = Button.new()
	open_btn.text = tr("UI_ROOM_OPEN")
	open_btn.pressed.connect(func() -> void:
		var sel: PackedInt32Array = _lib_list.get_selected_items()
		if not sel.is_empty():
			open_library_room(_lib_ids[sel[0]]))
	lr.add_child(open_btn)
	var del_btn: Button = Button.new()
	del_btn.text = tr("UI_ROOM_REMOVE")
	del_btn.pressed.connect(func() -> void:
		var sel: PackedInt32Array = _lib_list.get_selected_items()
		if not sel.is_empty():
			library.remove(_lib_ids[sel[0]])
			refresh_library())
	lr.add_child(del_btn)

	_heading(box, "UI_EDIT_NEW")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_new_w = _spin(grid, "UI_EDIT_WIDTH", 9)
	_new_h = _spin(grid, "UI_EDIT_HEIGHT", 7)
	var gl: Label = Label.new()
	gl.text = tr("UI_EDIT_GRID")
	grid.add_child(gl)
	_new_grid = OptionButton.new()
	for g: String in GRIDS:
		_new_grid.add_item(tr("UI_GRID_" + g.to_upper()))
	grid.add_child(_new_grid)
	var new_btn: Button = Button.new()
	new_btn.text = tr("UI_EDIT_NEW_BUTTON")
	new_btn.tooltip_text = tr("UI_EDIT_NEW_TIP")
	new_btn.pressed.connect(func() -> void:
		new_room_requested.emit(int(_new_w.value), int(_new_h.value), GRIDS[maxi(0, _new_grid.selected)]))
	box.add_child(new_btn)


## Fila con un código de solo lectura y botón de copiar.
func _code_row(box: VBoxContainer, key: String, tip_key: String) -> LineEdit:
	var lbl: Label = Label.new()
	lbl.text = tr(key)
	lbl.tooltip_text = tr(tip_key)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(lbl)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var e: LineEdit = LineEdit.new()
	e.editable = false
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.tooltip_text = tr(tip_key)
	row.add_child(e)
	var copy: Button = Button.new()
	copy.text = tr("UI_ROOM_COPY")
	copy.pressed.connect(func() -> void:
		if not e.text.is_empty():
			DisplayServer.clipboard_set(e.text)
			status.emit(tr("UI_ROOM_COPIED")))
	row.add_child(copy)
	return e


## Guarda la estancia mostrada en la biblioteca y pone sus dos códigos.
## Devuelve el id corto ("" si no se pudo).
func save_to_library() -> String:
	if _doc == null:
		return ""
	var id: String = library.save(_doc)
	if id.is_empty():
		status.emit(tr(library.last_error))
		return ""
	_id_edit.text = id
	_share_edit.text = RoomContent.share_code(_doc)
	refresh_library()
	status.emit(tr("UI_ROOM_SAVED").replace("{id}", id))
	return id


## Abre una estancia de la biblioteca (emite room_opened). true si se pudo.
func open_library_room(id: String) -> bool:
	var res: MapFile.LoadResult = library.load_room(id)
	if res.doc == null:
		status.emit(tr(res.error))
		return false
	room_opened.emit(res.doc, id)
	return true


func refresh_library() -> void:
	if _lib_list == null:
		return
	_lib_list.clear()
	_lib_ids.clear()
	for e: RoomLibrary.Entry in library.entries():
		var shown: String = e.name if not e.name.is_empty() else tr("ROOM_KIND_" + e.kind.to_upper())
		_lib_list.add_item("%s  ·  %s" % [shown, e.id])
		_lib_ids.append(e.id)


func _heading(box: VBoxContainer, key: String) -> void:
	box.add_child(HSeparator.new())
	var h: Label = Label.new()
	h.text = tr(key)
	h.add_theme_color_override("font_color", Color("f7dc8e"))
	box.add_child(h)


func _spin(grid: GridContainer, key: String, value: int) -> SpinBox:
	var l: Label = Label.new()
	l.text = tr(key)
	grid.add_child(l)
	var s: SpinBox = SpinBox.new()
	s.min_value = 3
	s.max_value = 48
	s.value = value
	grid.add_child(s)
	return s


func _tool_button(tool: String, text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = _group
	b.toggled.connect(func(_on: bool) -> void: _emit_tool())
	_tool_buttons[tool] = b
	return b


func _fill_objects() -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var named: Array[Array] = []
	for id: String in cat.ids:
		named.append([tr("OBJ_" + id.to_upper()), id])
	named.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	for pair: Array in named:
		_object_opt.add_item(str(pair[0]))
		_object_ids.append(str(pair[1]))


## Herramienta activa ("" si ninguna).
func current_tool() -> String:
	var pressed: BaseButton = _group.get_pressed_button()
	if pressed == null:
		return ""
	for t: String in _tool_buttons:
		if _tool_buttons[t] == pressed:
			if t == "object":
				var i: int = _object_opt.selected
				return "object:" + _object_ids[i] if i >= 0 and i < _object_ids.size() else ""
			return t
	return ""


## Elige una herramienta por su texto (para las pruebas); "" la apaga.
func select_tool(tool: String) -> void:
	if tool.is_empty():
		var p: BaseButton = _group.get_pressed_button()
		if p != null:
			p.button_pressed = false
		return
	if tool.begins_with("object:"):
		var i: int = _object_ids.find(tool.substr(7))
		if i >= 0:
			_object_opt.select(i)
		tool = "object"
	if _tool_buttons.has(tool):
		_tool_buttons[tool].button_pressed = true
	_emit_tool()


func _emit_tool() -> void:
	tool_changed.emit(current_tool())


func rotate() -> void:
	_facing = (_facing + 1) % 4
	_update_facing()
	facing_changed.emit(_facing)


func _update_facing() -> void:
	_facing_btn.text = tr("UI_EDIT_ROTATE").replace("{dir}", tr("UI_EDIT_FACING_%d" % _facing))


func set_document(doc: MapDocument) -> void:
	_doc = doc
	refresh()
	refresh_library()


## Rehace la lista de salas y la comprobación de acceso.
func refresh() -> void:
	if _room_opt == null:
		return
	# Tras cualquier cambio los códigos ya no son los de la estancia: se
	# vuelven a pedir con "Guardar en mi biblioteca".
	_id_edit.text = ""
	_share_edit.text = ""
	var keep: int = _room_ids[_room_opt.selected] if _room_opt.selected >= 0 and _room_opt.selected < _room_ids.size() else -1
	_room_opt.clear()
	_room_ids.clear()
	if _doc == null or _doc.level(level_index) == null:
		_check.text = ""
		return
	var lvl: MapLevel = _doc.level(level_index)
	for r: MapRoom in lvl.rooms:
		var room_name: String = r.label if not r.label.is_empty() else tr("ROOM_KIND_" + r.kind.to_upper())
		_room_opt.add_item("%s (#%d)" % [room_name, r.id])
		_room_ids.append(r.id)
	var sel: int = maxi(0, _room_ids.find(keep))
	if _room_opt.item_count > 0:
		_room_opt.select(sel)
	_show_room()
	_check.text = check_text()


func _show_room() -> void:
	var r: MapRoom = _selected_room()
	_kind_opt.disabled = r == null
	_label_edit.editable = r != null
	if r == null:
		return
	# Un tipo que no está en la lista (calle, edificio…) se deja como está si
	# no se elige otro.
	_kind_opt.select(ROOM_KINDS.find(r.kind))
	_label_edit.text = r.label


func _selected_room() -> MapRoom:
	if _doc == null or _room_opt.selected < 0 or _room_opt.selected >= _room_ids.size():
		return null
	return _doc.level(level_index).room(_room_ids[_room_opt.selected])


## Aplica tipo y nombre a la sala elegida.
func apply_room() -> bool:
	var r: MapRoom = _selected_room()
	if r == null:
		return false
	var ki: int = _kind_opt.selected
	var kind: String = ROOM_KINDS[ki] if ki >= 0 and ki < ROOM_KINDS.size() else r.kind
	return execute.call(SetRoomCommand.new(level_index, r.id, kind, _label_edit.text.strip_edges()))


## Elige la sala `room_id` en la lista (para las pruebas).
func select_room(room_id: int, kind: String, label: String) -> void:
	var i: int = _room_ids.find(room_id)
	if i < 0:
		return
	_room_opt.select(i)
	_show_room()
	_kind_opt.select(ROOM_KINDS.find(kind))
	_label_edit.text = label


## Casilla de la entrada del nivel (o la primera transitable); (-1, -1) si
## no hay suelo.
func start_cell() -> Vector2i:
	var lvl: MapLevel = _doc.level(level_index)
	var mask: PackedByteArray = lvl.movement_mask()
	for r: MapRoom in lvl.rooms:
		if r.kind == MapRoom.KIND_ENTRANCE:
			for c: Vector2i in lvl.room_cells(r.id):
				if (mask[_doc.grid.index_of(c)] & MapLevel.MOVE_PASSABLE) != 0:
					return c
	for i: int in mask.size():
		if (mask[i] & MapLevel.MOVE_PASSABLE) != 0:
			return _doc.grid.cell_at(i)
	return Vector2i(-1, -1)


## "Todo el suelo se alcanza desde la entrada" o cuántas casillas no.
func check_text() -> String:
	var start: Vector2i = start_cell()
	if start.x < 0:
		return tr("UI_EDIT_CHECK_EMPTY")
	var missing: int = Connectivity.unreachable_count(_doc, level_index, start)
	if missing == 0:
		return tr("UI_EDIT_CHECK_OK")
	return tr("UI_EDIT_CHECK_MISSING").replace("{n}", str(missing))
