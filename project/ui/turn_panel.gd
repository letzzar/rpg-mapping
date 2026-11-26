class_name TurnPanel
extends PanelContainer
## Panel de turnos e iniciativa (PROYECTO §10.3, ADR 035). Solo el orden y el
## movimiento gastado: no tira ataques ni lleva puntos de golpe.
##
## El DM añade fichas, escribe o tira la iniciativa, ordena, empieza, pasa
## turno y decide si se bloquea pasar de la velocidad; cada cambio es un
## SetTurnsCommand (con deshacer) que ejecuta `execute`. Los jugadores lo ven
## en solo lectura (`read_only`) con lo que les manda el servidor.

## Empieza el turno de una ficha (para seleccionarla y centrar la vista).
signal turn_started(token_id: int)

## Ejecuta un comando en el historial del mapa; devuelve si se aplicó.
var execute: Callable = func(_cmd: MapCommand) -> bool: return false
## Formatea pies con las unidades activas.
var format_ft: Callable = func(ft: int) -> String: return str(ft) + " ft"
## Tirada de iniciativa: d20 (se puede sustituir en las pruebas).
var roll_d20: Callable = func() -> int: return _rng.randi_range(1, 20)
var profile: SystemProfile = null
var level_index: int = 0
var read_only: bool = false:
	set = set_read_only

var _doc: MapDocument = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _title: Label
var _rows: VBoxContainer
var _dm_box: VBoxContainer
var _start_btn: Button
var _next_btn: Button
var _end_btn: Button
var _block_chk: CheckBox


func _init() -> void:
	_rng.randomize()
	custom_minimum_size = Vector2(300, 0)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color("f7dc8e"))
	box.add_child(_title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_dm_box = VBoxContainer.new()
	box.add_child(_dm_box)
	var r1: HFlowContainer = HFlowContainer.new()
	_dm_box.add_child(r1)
	r1.add_child(_btn("UI_TURNS_ADD_LEVEL", "UI_TURNS_ADD_LEVEL_TIP", add_level_tokens))
	r1.add_child(_btn("UI_TURNS_ROLL", "UI_TURNS_ROLL_TIP", roll_missing))
	r1.add_child(_btn("UI_TURNS_SORT", "", sort_by_initiative))
	var r2: HFlowContainer = HFlowContainer.new()
	_dm_box.add_child(r2)
	_start_btn = _btn("UI_TURNS_START", "", start)
	_next_btn = _btn("UI_TURNS_NEXT", "", next_turn)
	_end_btn = _btn("UI_TURNS_END", "", end_combat)
	r2.add_child(_start_btn)
	r2.add_child(_next_btn)
	r2.add_child(_end_btn)
	_block_chk = CheckBox.new()
	_block_chk.text = tr("UI_TURNS_BLOCK")
	_block_chk.tooltip_text = tr("UI_TURNS_BLOCK_TIP")
	_block_chk.toggled.connect(func(on: bool) -> void:
		if _doc == null or _doc.turns.block_over_speed == on:
			return
		var t: TurnTracker = _doc.turns.copy()
		t.block_over_speed = on
		_apply(t, "CMD_TURNS_BLOCK"))
	_dm_box.add_child(_block_chk)


func _btn(key: String, tip_key: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = tr(key)
	if not tip_key.is_empty():
		b.tooltip_text = tr(tip_key)
	b.pressed.connect(cb)
	return b


func set_read_only(v: bool) -> void:
	read_only = v
	if _dm_box != null:
		_dm_box.visible = not v
	refresh()


func set_document(doc: MapDocument) -> void:
	_doc = doc
	refresh()


# --- Acciones del DM (públicas para las pruebas) ------------------------------

## Añade al orden las fichas del nivel que aún no están (ocultas incluidas:
## a los jugadores no les llegan).
func add_level_tokens() -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	for tk: MapToken in _doc.tokens:
		if tk.level == level_index and not t.order.has(tk.id):
			t.order.append(tk.id)
	_apply(t, "CMD_TURNS_ADD")


## Tira iniciativa (d20 + modificador del personaje) a las fichas del orden
## que no tienen resultado, y ordena.
func roll_missing() -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	for id: int in t.order:
		if t.initiative.has(id):
			continue
		var tk: MapToken = _doc.token(id)
		var mod: int = tk.sheet.initiative if tk != null and tk.sheet != null and tk.sheet.has_initiative else 0
		var d20: int = roll_d20.call()
		t.initiative[id] = d20 + mod
	_keep_current_after_sort(t)
	_apply(t, "CMD_TURNS_ROLL")


func sort_by_initiative() -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	_keep_current_after_sort(t)
	_apply(t, "CMD_TURNS_SORT")


func set_initiative(token_id: int, value: int) -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	t.initiative[token_id] = value
	_apply(t, "CMD_TURNS_INITIATIVE")


func remove_token(token_id: int) -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	var i: int = t.order.find(token_id)
	if i < 0:
		return
	var cur: int = t.current_token_id()
	t.order.remove_at(i)
	t.initiative.erase(token_id)
	if t.order.is_empty():
		t.active = false
		t.current = 0
	elif cur == token_id:
		# Le toca a la siguiente; su movimiento empieza de cero.
		t.current = i % t.order.size()
		t.moved_ft = 0
	else:
		t.current = maxi(0, t.order.find(cur))
	_apply(t, "CMD_TURNS_REMOVE")


## Empieza el combate: ronda 1, turno de la primera del orden.
func start() -> void:
	if _doc == null or _doc.turns.order.is_empty():
		return
	var t: TurnTracker = _doc.turns.copy()
	t.sort_order(_doc)
	t.active = true
	t.round = 1
	t.current = 0
	t.moved_ft = 0
	if _apply(t, "CMD_TURNS_START"):
		turn_started.emit(t.current_token_id())


func next_turn() -> void:
	if _doc == null or not _doc.turns.active:
		return
	var t: TurnTracker = _doc.turns.copy()
	t.advance(_doc)
	if _apply(t, "CMD_TURNS_NEXT"):
		turn_started.emit(t.current_token_id())


## Termina el combate (conserva el orden y la iniciativa por si se reanuda).
func end_combat() -> void:
	if _doc == null:
		return
	var t: TurnTracker = _doc.turns.copy()
	t.active = false
	t.moved_ft = 0
	_apply(t, "CMD_TURNS_END")


func _keep_current_after_sort(t: TurnTracker) -> void:
	var cur: int = t.current_token_id()
	t.sort_order(_doc)
	if cur >= 0:
		t.current = maxi(0, t.order.find(cur))


func _apply(t: TurnTracker, label: String) -> bool:
	if read_only:
		return false
	var ok: bool = execute.call(SetTurnsCommand.new(t, label))
	refresh()
	return ok


# --- Vista --------------------------------------------------------------------

## Texto del turno actual ("" si no hay combate).
func status_text() -> String:
	if _doc == null or not _doc.turns.active:
		return ""
	var tk: MapToken = _doc.token(_doc.turns.current_token_id())
	if tk == null:
		return ""
	return tr("UI_TURNS_NOW").replace("{name}", tk.name).replace("{round}", str(_doc.turns.round))


func refresh() -> void:
	if _rows == null:
		return
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if _doc == null:
		_title.text = tr("UI_TURNS_TITLE")
		return
	var tt: TurnTracker = _doc.turns
	_title.text = tr("UI_TURNS_ROUND").replace("{round}", str(tt.round)) if tt.active else tr("UI_TURNS_TITLE")
	_block_chk.set_pressed_no_signal(tt.block_over_speed)
	_start_btn.disabled = tt.order.is_empty()
	_start_btn.text = tr("UI_TURNS_RESTART" if tt.active else "UI_TURNS_START")
	_next_btn.disabled = not tt.active
	_end_btn.disabled = not tt.active
	if tt.order.is_empty():
		var empty: Label = Label.new()
		empty.text = tr("UI_TURNS_EMPTY_PLAYER" if read_only else "UI_TURNS_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(260, 0)
		_rows.add_child(empty)
		return
	var cur: int = tt.current_token_id()
	for id: int in tt.order:
		var tk: MapToken = _doc.token(id)
		if tk == null:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		_rows.add_child(row)
		var mark: Label = Label.new()
		mark.text = "▶" if id == cur else " "
		mark.custom_minimum_size = Vector2(16, 0)
		row.add_child(mark)
		if read_only:
			var iv: Label = Label.new()
			iv.text = str(tt.initiative[id]) if tt.initiative.has(id) else "–"
			iv.custom_minimum_size = Vector2(36, 0)
			row.add_child(iv)
		else:
			var spin: SpinBox = SpinBox.new()
			spin.min_value = -20
			spin.max_value = 60
			spin.value = tt.initiative.get(id, 0)
			spin.custom_minimum_size = Vector2(80, 0)
			spin.tooltip_text = tr("UI_TURNS_INITIATIVE_TIP")
			spin.value_changed.connect(func(v: float) -> void: set_initiative(id, int(v)))
			row.add_child(spin)
		var name_lbl: Label = Label.new()
		name_lbl.text = tk.name + ("  " + tr("UI_TURNS_HIDDEN") if tk.hidden else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		if id == cur:
			name_lbl.add_theme_color_override("font_color", Color("f7dc8e"))
		row.add_child(name_lbl)
		var speed: int = tk.speed_ft(profile)
		if id == cur and speed > 0:
			var used: Label = Label.new()
			used.text = tr("UI_TURNS_LEFT").replace("{left}", str(format_ft.call(maxi(0, speed - tt.moved_ft))))
			row.add_child(used)
		if not read_only:
			var rm: Button = Button.new()
			rm.text = "✕"
			rm.tooltip_text = tr("UI_TURNS_REMOVE")
			rm.pressed.connect(func() -> void: remove_token(id))
			row.add_child(rm)
