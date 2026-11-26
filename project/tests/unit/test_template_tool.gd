extends GutTest
## Herramienta de plantillas de área en la vista 2D y en la pantalla
## principal (F5, ADR 035). La geometría de cada plantilla la prueba
## test_area_template.gd; aquí, que la vista la usa con el ratón, cuenta las
## fichas de dentro y no mueve nada.

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func _press(view: MapView2D, doc: MapDocument, cell: Vector2i, pressed: bool) -> void:
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = doc.grid.cell_to_pixel(cell, view.cell_px)
	view.process_input(mm, false)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = mm.position
	view.process_input(ev, false)


func test_view_draws_template_and_counts_tokens() -> void:
	var p: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var d: MapDocument = MapDocument.create("square", 20, 20)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(d)
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(19, 19)]:
		var t: MapToken = MapToken.new()
		t.id = d.allocate_id()
		t.name = "T%d" % t.id
		t.cell = cell
		t.side = MapToken.SIDE_ENEMY
		assert_true(s.execute(AddTokenCommand.new(t)))
	var view: MapView2D = MapView2D.new()
	view.document = d
	view.profile = p
	view.command_stack = s
	add_child_autofree(view)
	watch_signals(view)
	view.template_ft = 10
	view.template_id = "sphere"
	_press(view, d, Vector2i(10, 10), true)
	_press(view, d, Vector2i(10, 10), false)
	var cells: Array[Vector2i] = view.template_cells()
	assert_gt(cells.size(), 4)
	assert_true(cells.has(Vector2i(11, 10)))
	assert_false(cells.has(Vector2i(19, 19)))
	assert_eq(d.token(1).cell, Vector2i(10, 10), "con la herramienta, arrastrar no mueve fichas")
	var status: String = get_signal_parameters(view, "status_changed")[0]
	assert_true(status.contains("2 fichas"), status)
	# Cono arrastrado hacia el este: crece al soltar más lejos y apunta allí.
	view.template_id = "cone"
	view.template_ft = 15
	_press(view, d, Vector2i(5, 5), true)
	_press(view, d, Vector2i(9, 5), false)
	var cone: Array[Vector2i] = view.template_cells()
	assert_gt(cone.size(), 2)
	for c: Vector2i in cone:
		assert_true(c.x >= 5, "el cono apunta al este: %s" % c)
	# Apagar la herramienta borra la plantilla y el arrastre vuelve a mover.
	view.template_id = ""
	assert_true(view.template_cells().is_empty())
	assert_eq(s.undo_label_key(), "CMD_ADD_TOKEN", "la plantilla no entra en el historial")


func test_main_template_controls_follow_system() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var opt: OptionButton = main.get("_tpl_opt")
	var sys: OptionButton = main.get("_system_opt")
	var profiles: Array[SystemProfile] = main.get("_profiles")
	for i: int in profiles.size():
		sys.select(i)
		sys.item_selected.emit(i)
		assert_eq(opt.item_count, profiles[i].area_templates.size(), profiles[i].id)
	var btn: Button = main.get("_tpl_btn")
	btn.button_pressed = true
	btn.pressed.emit()
	var view: MapView2D = main.get("_view")
	assert_false(view.template_id.is_empty(), "al pulsar se activa")
	btn.button_pressed = false
	btn.pressed.emit()
	assert_true(view.template_id.is_empty())
