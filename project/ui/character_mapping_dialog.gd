class_name CharacterMappingDialog
extends ConfirmationDialog
## Mapeo de campos para importar personajes de un JSON ajeno (PROYECTO §10.1,
## ADR 034): para cada campo nuestro (nombre, tamaño, velocidades, sentidos…)
## se elige la ruta del JSON de donde sale, entre las que tiene su primer
## objeto. Propone las que reconoce por el nombre. Al aceptar emite `mapped`.

signal mapped(mapping: Dictionary[String, String])

var _opts: Dictionary[String, OptionButton] = {}
var _paths: PackedStringArray = PackedStringArray()
var _profile: SystemProfile = null


func _init() -> void:
	title = tr("UI_CHAR_MAPPING_TITLE")
	ok_button_text = tr("UI_CHAR_IMPORT")
	cancel_button_text = tr("UI_CANCEL")
	confirmed.connect(func() -> void: mapped.emit(mapping()))


## Prepara las filas para el JSON `text` y abre el diálogo.
func open_for(text: String, profile: SystemProfile) -> void:
	setup(text, profile)
	popup_centered(Vector2i(620, 560))


func setup(text: String, profile: SystemProfile) -> void:
	for c: Node in get_children(false):
		if c is ScrollContainer or c is VBoxContainer:
			remove_child(c)
			c.queue_free()
	_opts.clear()
	_profile = profile
	_paths = CharacterImport.leaf_paths(text)
	var suggested: Dictionary[String, String] = CharacterImport.suggest_mapping(_paths, profile)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	var help: Label = Label.new()
	help.text = tr("UI_CHAR_MAPPING_HELP")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(560, 0)
	box.add_child(help)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	box.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	for f: String in CharacterImport.mappable_fields(profile):
		var lbl: Label = Label.new()
		lbl.text = tr(field_label_key(f))
		lbl.custom_minimum_size = Vector2(200, 0)
		grid.add_child(lbl)
		var opt: OptionButton = OptionButton.new()
		opt.add_item(tr("UI_CHAR_MAPPING_SKIP"))
		for p: String in _paths:
			opt.add_item(p)
			if suggested.get(f, "") == p:
				opt.select(opt.item_count - 1)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(opt)
		_opts[f] = opt


## Clave i18n del nombre de un campo.
func field_label_key(f: String) -> String:
	match f:
		"name":
			return "UI_CHAR_NAME"
		"size":
			return "UI_CHAR_SIZE"
		"side":
			return "UI_CHAR_SIDE"
		"initiative":
			return "UI_CHAR_INITIATIVE"
		"preset":
			return "UI_CHAR_PRESET"
	if f == "walk" or (_profile != null and _profile.movement_modes.has(f)):
		return "MOVE_" + f.to_upper()
	return "SENSE_" + f.to_upper()


## Mapeo elegido (solo los campos con ruta).
func mapping() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for f: String in _opts:
		var i: int = _opts[f].selected
		if i > 0:
			out[f] = _paths[i - 1]
	return out
