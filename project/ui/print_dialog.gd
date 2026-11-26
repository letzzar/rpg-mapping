class_name PrintDialog
extends ConfirmationDialog
## Opciones de la impresión a escala real (ADR 042): papel, medida de la
## casilla, versión del DM (con secretos) o de los jugadores, y fichas. Dice
## antes cuántas hojas saldrán. Al aceptar emite `print_requested`.

signal print_requested(options: PrintPager.Options)

var document: MapDocument = null

var _paper: OptionButton
var _scale: OptionButton
var _dm: CheckBox
var _tokens: CheckBox
var _summary: Label


func _init() -> void:
	title = tr("UI_PRINT_TITLE")
	ok_button_text = tr("UI_PRINT_OK")
	cancel_button_text = tr("UI_CANCEL")
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_paper = OptionButton.new()
	_paper.add_item(tr("UI_PRINT_A4"))
	_paper.add_item(tr("UI_PRINT_LETTER"))
	_paper.item_selected.connect(func(_i: int) -> void: refresh())
	_row(grid, "UI_PRINT_PAPER", _paper)
	_scale = OptionButton.new()
	_scale.add_item(tr("UI_PRINT_INCH"))
	_scale.add_item(tr("UI_PRINT_25MM"))
	_scale.item_selected.connect(func(_i: int) -> void: refresh())
	_row(grid, "UI_PRINT_SCALE", _scale)
	_dm = CheckBox.new()
	_dm.text = tr("UI_PRINT_DM")
	box.add_child(_dm)
	_tokens = CheckBox.new()
	_tokens.text = tr("UI_PRINT_TOKENS")
	box.add_child(_tokens)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(380, 0)
	box.add_child(_summary)
	confirmed.connect(func() -> void: print_requested.emit(options()))


func _row(g: GridContainer, key: String, ctl: Control) -> void:
	var l: Label = Label.new()
	l.text = tr(key)
	g.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctl)


func open_for(doc: MapDocument) -> void:
	document = doc
	refresh()
	popup_centered(Vector2i(460, 260))


func options() -> PrintPager.Options:
	var o: PrintPager.Options = PrintPager.Options.new()
	o.paper = "letter" if _paper.selected == 1 else "a4"
	o.cell_mm = PrintPager.CELL_MM_OPTIONS[maxi(0, _scale.selected)]
	o.dm_view = _dm.button_pressed
	o.show_tokens = _tokens.button_pressed
	return o


## Cuántas hojas y en qué disposición.
func refresh() -> void:
	if document == null:
		_summary.text = ""
		return
	var l: PrintPager.Layout = PrintPager.layout(document, options())
	_summary.text = tr("UI_PRINT_SUMMARY").replace("{n}", str(l.page_count())) \
		.replace("{cols}", str(l.columns)).replace("{rows}", str(l.rows)) \
		.replace("{orientation}", tr("UI_PRINT_LANDSCAPE" if l.landscape else "UI_PRINT_PORTRAIT"))
