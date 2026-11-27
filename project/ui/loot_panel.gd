class_name LootPanel
extends PanelContainer
## Panel de botín (ADR 048): el contenido de un cofre, barril u otro
## contenedor, o el botín de una ficha (enemigo, PNJ). El DM añade, cambia y
## quita objetos, los pasa a otra ficha ("Dar a") y decide si los jugadores
## lo ven; cada cambio es un SetLootCommand (con deshacer) que ejecuta
## `execute`. Los jugadores lo ven en solo lectura, y solo lo enseñado.

## Interacciones del catálogo que guardan cosas (doble clic = su contenido).
const LOOTABLE: PackedStringArray = ["chest", "container", "search", "altar"]

## Ejecuta un comando en el historial del mapa; devuelve si se aplicó.
var execute: Callable = func(_cmd: MapCommand) -> bool: return false
var read_only: bool = false:
	set(v):
		read_only = v
		refresh()

var _doc: MapDocument = null
var _kind: String = ""
var _level: int = 0
var _id: int = -1
var _title: Label
var _hint: Label
var _rows: VBoxContainer
var _dm_box: VBoxContainer
var _name_edit: LineEdit
var _qty_spin: SpinBox
var _value_edit: LineEdit
var _reveal_chk: CheckBox
var _give_opt: OptionButton
var _give_all_btn: Button


func _init() -> void:
	custom_minimum_size = Vector2(320, 0)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color("f7dc8e"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	box.add_child(_hint)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_dm_box = VBoxContainer.new()
	box.add_child(_dm_box)
	var add_row: HBoxContainer = HBoxContainer.new()
	_dm_box.add_child(add_row)
	_qty_spin = _qty(1)
	add_row.add_child(_qty_spin)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("UI_LOOT_NAME")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = LootItem.MAX_NAME
	_name_edit.text_submitted.connect(func(_t: String) -> void: add_item_from_fields())
	add_row.add_child(_name_edit)
	_value_edit = LineEdit.new()
	_value_edit.placeholder_text = tr("UI_LOOT_VALUE")
	_value_edit.custom_minimum_size = Vector2(70, 0)
	_value_edit.max_length = LootItem.MAX_TEXT
	_value_edit.text_submitted.connect(func(_t: String) -> void: add_item_from_fields())
	add_row.add_child(_value_edit)
	var add_btn: Button = Button.new()
	add_btn.text = tr("UI_LOOT_ADD")
	add_btn.pressed.connect(add_item_from_fields)
	add_row.add_child(add_btn)
	var give_row: HBoxContainer = HBoxContainer.new()
	_dm_box.add_child(give_row)
	var gl: Label = Label.new()
	gl.text = tr("UI_LOOT_GIVE_TO")
	give_row.add_child(gl)
	_give_opt = OptionButton.new()
	_give_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_give_opt.clip_text = true
	_give_opt.tooltip_text = tr("UI_LOOT_GIVE_TIP")
	give_row.add_child(_give_opt)
	_give_all_btn = Button.new()
	_give_all_btn.text = tr("UI_LOOT_GIVE_ALL")
	_give_all_btn.pressed.connect(give_all)
	give_row.add_child(_give_all_btn)
	_reveal_chk = CheckBox.new()
	_reveal_chk.text = tr("UI_LOOT_REVEALED")
	_reveal_chk.tooltip_text = tr("UI_LOOT_REVEALED_TIP")
	_reveal_chk.toggled.connect(func(on: bool) -> void: _commit(items(), on))
	_dm_box.add_child(_reveal_chk)
	refresh()


func set_document(doc: MapDocument) -> void:
	_doc = doc
	clear_target()


func clear_target() -> void:
	_kind = ""
	_id = -1
	refresh()


func show_object(level: int, object_id: int) -> void:
	_kind = SetLootCommand.KIND_OBJECT
	_level = level
	_id = object_id
	refresh()


func show_token(token_id: int) -> void:
	_kind = SetLootCommand.KIND_TOKEN
	_level = 0
	_id = token_id
	refresh()


func has_target() -> bool:
	return _target_object() != null or _target_token() != null


func target_kind() -> String:
	return _kind if has_target() else ""


func target_id() -> int:
	return _id


## ¿Se abre el panel con un doble clic en este objeto?
static func is_lootable(o: MapObject) -> bool:
	return LOOTABLE.has(o.interaction) or not o.contents.is_empty()


func _target_object() -> MapObject:
	if _doc == null or _kind != SetLootCommand.KIND_OBJECT or _doc.level(_level) == null:
		return null
	return _doc.level(_level).object(_id)


func _target_token() -> MapToken:
	if _doc == null or _kind != SetLootCommand.KIND_TOKEN:
		return null
	return _doc.token(_id)


## Lista actual del objetivo (copia).
func items() -> Array[LootItem]:
	var o: MapObject = _target_object()
	if o != null:
		return LootItem.list_copy(o.contents)
	var t: MapToken = _target_token()
	if t != null:
		return LootItem.list_copy(t.loot)
	return []


func revealed() -> bool:
	var o: MapObject = _target_object()
	if o != null:
		return o.contents_revealed
	var t: MapToken = _target_token()
	return t != null and t.loot_revealed


func _commit(new_items: Array[LootItem], show: bool) -> bool:
	if read_only or not has_target():
		return false
	var cmd: SetLootCommand = null
	if _kind == SetLootCommand.KIND_OBJECT:
		cmd = SetLootCommand.for_object(_level, _id, new_items, show)
	else:
		cmd = SetLootCommand.for_token(_id, new_items, show)
	var ok: bool = execute.call(cmd)
	refresh()
	return ok


## Añade lo escrito en la fila de abajo (si ya hay uno igual, suma cantidad).
func add_item_from_fields() -> bool:
	var it: LootItem = LootItem.make(_name_edit.text, int(_qty_spin.value), _value_edit.text)
	if it.name.is_empty():
		return false
	if _commit(merge_into(items(), it), revealed()):
		_name_edit.clear()
		_value_edit.clear()
		_qty_spin.value = 1
		return true
	return false


## `list` con `it` añadido: si hay uno con el mismo nombre y valor, se suman.
static func merge_into(list: Array[LootItem], it: LootItem) -> Array[LootItem]:
	var out: Array[LootItem] = LootItem.list_copy(list)
	for o: LootItem in out:
		if o.name == it.name and o.value == it.value:
			o.qty = mini(LootItem.MAX_QTY, o.qty + it.qty)
			return out
	if out.size() < LootItem.MAX_ITEMS:
		out.append(it.copy())
	return out


func remove_item(index: int) -> bool:
	var list: Array[LootItem] = items()
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	return _commit(list, revealed())


func set_item(index: int, it: LootItem) -> bool:
	var list: Array[LootItem] = items()
	if index < 0 or index >= list.size() or it.name.is_empty():
		refresh()
		return false
	list[index] = it
	return _commit(list, revealed())


## Ficha elegida en "Dar a" (-1 si no hay).
func give_target() -> int:
	if _give_opt.item_count == 0 or _give_opt.selected < 0:
		return -1
	var id: int = _give_opt.get_item_metadata(_give_opt.selected)
	return id


func select_give_target(token_id: int) -> void:
	for i: int in _give_opt.item_count:
		var id: int = _give_opt.get_item_metadata(i)
		if id == token_id:
			_give_opt.select(i)


## Pasa el objeto `index` (entero) a la ficha de "Dar a", en un solo paso
## que se deshace junto.
func give_item(index: int) -> bool:
	var list: Array[LootItem] = items()
	var to: MapToken = _doc.token(give_target()) if _doc != null else null
	if read_only or to == null or index < 0 or index >= list.size():
		return false
	var it: LootItem = list[index]
	list.remove_at(index)
	return _give(list, [it], to)


func give_all() -> bool:
	var to: MapToken = _doc.token(give_target()) if _doc != null else null
	var list: Array[LootItem] = items()
	if read_only or to == null or list.is_empty():
		return false
	var none: Array[LootItem] = []
	return _give(none, list, to)


func _give(remaining: Array[LootItem], moved: Array[LootItem], to: MapToken) -> bool:
	if _kind == SetLootCommand.KIND_TOKEN and to.id == _id:
		return false
	var dest: Array[LootItem] = LootItem.list_copy(to.loot)
	for it: LootItem in moved:
		dest = merge_into(dest, it)
	var from_cmd: SetLootCommand = null
	if _kind == SetLootCommand.KIND_OBJECT:
		from_cmd = SetLootCommand.for_object(_level, _id, remaining, revealed())
	else:
		from_cmd = SetLootCommand.for_token(_id, remaining, revealed())
	var parts: Array[MapCommand] = [from_cmd, SetLootCommand.for_token(to.id, dest, to.loot_revealed)]
	var ok: bool = execute.call(CompositeCommand.new(parts))
	refresh()
	return ok


# --- Dibujo del panel -----------------------------------------------------------

func refresh() -> void:
	if _rows == null:
		return
	for ch: Node in _rows.get_children():
		_rows.remove_child(ch)
		ch.queue_free()
	var o: MapObject = _target_object()
	var t: MapToken = _target_token()
	var target: bool = o != null or t != null
	_dm_box.visible = target and not read_only
	if not target:
		_title.text = tr("UI_LOOT")
		_hint.text = tr("UI_LOOT_NO_TARGET")
		return
	if o != null:
		var label: String = tr("OBJ_" + o.catalog_id.to_upper())
		if label.begins_with("OBJ_"):
			label = o.catalog_id
		_title.text = tr("UI_LOOT_TITLE_OBJECT").replace("{name}", label).replace("{x}", str(o.cell.x)).replace("{y}", str(o.cell.y))
	else:
		_title.text = tr("UI_LOOT_TITLE_TOKEN").replace("{name}", t.name if not t.name.is_empty() else "#%d" % t.id)
	var list: Array[LootItem] = items()
	var shown: bool = revealed()
	if read_only and not shown:
		_hint.text = tr("UI_LOOT_NOT_SHOWN")
		return
	_hint.text = tr("UI_LOOT_EMPTY") if list.is_empty() else tr("UI_LOOT_COUNT").replace("{n}", str(list.size()))
	_reveal_chk.set_pressed_no_signal(shown)
	_fill_give_targets()
	_give_all_btn.disabled = list.is_empty() or give_target() < 0
	for i: int in list.size():
		_rows.add_child(_row(i, list[i]))


func _row(index: int, it: LootItem) -> Control:
	if read_only:
		var l: Label = Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = _line_text(it)
		return l
	var row: HBoxContainer = HBoxContainer.new()
	var q: SpinBox = _qty(it.qty)
	q.value_changed.connect(func(v: float) -> void:
		set_item(index, LootItem.make(it.name, int(v), it.value, it.note)))
	row.add_child(q)
	var n: LineEdit = LineEdit.new()
	n.text = it.name
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.max_length = LootItem.MAX_NAME
	n.text_submitted.connect(func(s: String) -> void:
		set_item(index, LootItem.make(s, it.qty, it.value, it.note)))
	n.focus_exited.connect(func() -> void:
		if n.text.strip_edges() != it.name:
			set_item.call_deferred(index, LootItem.make(n.text, it.qty, it.value, it.note)))
	row.add_child(n)
	var v: LineEdit = LineEdit.new()
	v.text = it.value
	v.placeholder_text = tr("UI_LOOT_VALUE")
	v.custom_minimum_size = Vector2(70, 0)
	v.text_submitted.connect(func(s: String) -> void:
		set_item(index, LootItem.make(it.name, it.qty, s, it.note)))
	row.add_child(v)
	var give: Button = Button.new()
	give.text = "→"
	give.tooltip_text = tr("UI_LOOT_GIVE_TIP")
	give.disabled = give_target() < 0
	give.pressed.connect(func() -> void: give_item(index))
	row.add_child(give)
	var del: Button = Button.new()
	del.text = "✕"
	del.tooltip_text = tr("UI_LOOT_REMOVE_TIP")
	del.pressed.connect(func() -> void: remove_item(index))
	row.add_child(del)
	return row


static func _line_text(it: LootItem) -> String:
	var s: String = "%d × %s" % [it.qty, it.name]
	if not it.value.is_empty():
		s += " (%s)" % it.value
	if not it.note.is_empty():
		s += " — " + it.note
	return s


func _qty(v: int) -> SpinBox:
	var s: SpinBox = SpinBox.new()
	s.min_value = 1
	s.max_value = LootItem.MAX_QTY
	s.value = v
	s.custom_minimum_size = Vector2(70, 0)
	s.tooltip_text = tr("UI_LOOT_QTY")
	return s


## "Dar a": las fichas del mapa (primero las del grupo), menos la propia.
func _fill_give_targets() -> void:
	var keep: int = give_target()
	_give_opt.clear()
	if _doc == null:
		return
	var party: Array[MapToken] = []
	var others: Array[MapToken] = []
	for t: MapToken in _doc.tokens:
		if _kind == SetLootCommand.KIND_TOKEN and t.id == _id:
			continue
		if PartyVision.SIDES_IN_PARTY.has(t.side):
			party.append(t)
		else:
			others.append(t)
	party.append_array(others)
	for t: MapToken in party:
		_give_opt.add_item(t.name if not t.name.is_empty() else "#%d" % t.id)
		_give_opt.set_item_metadata(_give_opt.item_count - 1, t.id)
	if _give_opt.item_count > 0:
		_give_opt.select(0)
		select_give_target(keep)
