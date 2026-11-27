extends GutTest
## Botín y contenido (ADR 048): cofres y otros contenedores con su lista de
## objetos, botín de enemigos y PNJ, con deshacer, guardado, filtro de red y
## panel.


func before_all() -> void:
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale("es")


func _setup() -> Array:
	var d: MapDocument = MapDocument.create("square", 8, 6)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(d)
	var o: MapObject = MapObject.new()
	o.id = d.allocate_id()
	o.catalog_id = "chest"
	o.cell = Vector2i(2, 2)
	o.interaction = "chest"
	o.blocks_movement = true
	assert_true(s.execute(AddObjectCommand.new(0, o)))
	var hero: MapToken = MapToken.new()
	hero.id = d.allocate_id()
	hero.name = "Ana"
	hero.cell = Vector2i(1, 1)
	hero.side = MapToken.SIDE_PLAYER
	assert_true(s.execute(AddTokenCommand.new(hero)))
	var orc: MapToken = MapToken.new()
	orc.id = d.allocate_id()
	orc.name = "Orco"
	orc.cell = Vector2i(5, 3)
	orc.side = MapToken.SIDE_ENEMY
	assert_true(s.execute(AddTokenCommand.new(orc)))
	return [d, s, o.id, hero.id, orc.id]


func _items(pairs: Array) -> Array[LootItem]:
	var out: Array[LootItem] = []
	for p: Array in pairs:
		var q: int = p[1]
		out.append(LootItem.make(str(p[0]), q, str(p[2]) if p.size() > 2 else ""))
	return out


func test_empty_contents_do_not_change_saved_maps() -> void:
	var o: MapObject = MapObject.new()
	var od: Dictionary = o.to_dict()
	assert_false(od.has("contents"), "sin contenido no se guarda: los hashes de siempre")
	assert_false(od.has("contents_revealed"))
	var t: MapToken = MapToken.new()
	var td: Dictionary = t.to_dict()
	assert_false(td.has("loot"))
	# Con contenido, ida y vuelta.
	o.contents = _items([["Monedas de oro", 120, "120 po"], ["Poción de curación", 2]])
	o.contents_revealed = true
	var r: JsonReader = JsonReader.new()
	var back: MapObject = MapObject.from_dict(r, o.to_dict())
	assert_true(r.ok(), r.error)
	assert_true(LootItem.list_equals(back.contents, o.contents))
	assert_true(back.contents_revealed)
	t.loot = _items([["Daga", 1, "2 po"]])
	var tb: MapToken = MapToken.from_dict(r, t.to_dict())
	assert_true(LootItem.list_equals(tb.loot, t.loot))
	assert_false(tb.loot_revealed)
	# Un objeto sin nombre no vale.
	var bad: JsonReader = JsonReader.new()
	LootItem.from_dict(bad, {"name": " ", "qty": 1})
	assert_false(bad.ok())


func test_set_loot_undo_and_replay() -> void:
	var st: Array = _setup()
	var d: MapDocument = st[0]
	var s: CommandStack = st[1]
	var chest: int = st[2]
	var orc: int = st[4]
	var before: String = d.content_hash()
	assert_true(s.execute(SetLootCommand.for_object(0, chest, _items([["Rubí", 1, "50 po"]]), false)))
	assert_true(s.execute(SetLootCommand.for_token(orc, _items([["Hacha", 1], ["Monedas de plata", 30]]), true)))
	assert_eq(d.level(0).object(chest).contents.size(), 1)
	assert_eq(d.token(orc).loot.size(), 2)
	assert_true(d.token(orc).loot_revealed)
	assert_false(s.execute(SetLootCommand.for_token(orc, _items([["Hacha", 1], ["Monedas de plata", 30]]), true)), "sin cambios no se apila")
	# Se recrea igual desde sus deltas (guardar y abrir el mapa).
	var copy: MapDocument = MapDocument.create("square", 8, 6)
	copy.level(0).fill_terrain(Terrain.FLOOR)
	var res: DeltaReplay.Result = DeltaReplay.replay(copy, d.deltas)
	assert_eq(res.error, "", res.detail)
	assert_eq(copy.content_hash(), d.content_hash())
	s.undo()
	s.undo()
	assert_true(d.level(0).object(chest).contents.is_empty())
	assert_true(d.token(orc).loot.is_empty())
	assert_eq(d.content_hash(), before, "deshacer lo deja como estaba")


func test_players_only_get_what_the_dm_shows() -> void:
	var st: Array = _setup()
	var d: MapDocument = st[0]
	var s: CommandStack = st[1]
	var chest: int = st[2]
	var orc: int = st[4]
	s.execute(SetLootCommand.for_object(0, chest, _items([["Llave de hierro", 1]]), false))
	s.execute(SetLootCommand.for_token(orc, _items([["Mapa del tesoro", 1]]), false))
	var explored: PackedByteArray = PackedByteArray()
	explored.resize(d.grid.cell_count())
	explored.fill(1)
	var lv: Dictionary = PlayerView.filter_level(d.level(0), explored)
	var objs: Array = lv["objects"]
	var od: Dictionary = objs[0]
	assert_false(od.has("contents"), "sin enseñar, no se manda")
	s.execute(SetLootCommand.for_object(0, chest, _items([["Llave de hierro", 1]]), true))
	lv = PlayerView.filter_level(d.level(0), explored)
	objs = lv["objects"]
	od = objs[0]
	assert_true(od.has("contents"), "enseñado, sí")
	var opts: PartyVision.Options = PartyVision.Options.new()
	opts.ambient_lit = true
	var snap: PlayerView.Snapshot = PlayerView.build(d, SystemProfile.load_id("dnd5e_2024"), opts)
	for td: Dictionary in snap.tokens:
		var tid: int = td["id"]
		if tid == orc:
			assert_false(td.has("loot"), "el botín del orco no se ve")


func test_panel_adds_merges_gives_and_reveals() -> void:
	var st: Array = _setup()
	var d: MapDocument = st[0]
	var s: CommandStack = st[1]
	var chest: int = st[2]
	var hero: int = st[3]
	var p: LootPanel = LootPanel.new()
	p.execute = func(cmd: MapCommand) -> bool: return s.execute(cmd)
	add_child_autofree(p)
	p.set_document(d)
	assert_false(p.has_target())
	p.show_object(0, chest)
	assert_true(p.has_target())
	assert_true(LootPanel.is_lootable(d.level(0).object(chest)))
	p._name_edit.text = "Monedas de oro"
	p._qty_spin.value = 50
	p._value_edit.text = "1 po"
	assert_true(p.add_item_from_fields())
	p._name_edit.text = "Monedas de oro"
	p._qty_spin.value = 25
	p._value_edit.text = "1 po"
	assert_true(p.add_item_from_fields())
	var c: Array[LootItem] = d.level(0).object(chest).contents
	assert_eq(c.size(), 1, "mismo objeto y valor: se suma")
	assert_eq(c[0].qty, 75)
	p._name_edit.text = "Espada corta"
	p._qty_spin.value = 1
	p._value_edit.text = ""
	assert_true(p.add_item_from_fields())
	# Dar la espada a Ana: se quita del cofre y se le suma a ella, en un paso.
	p.select_give_target(hero)
	assert_eq(p.give_target(), hero)
	assert_true(p.give_item(1))
	assert_eq(d.level(0).object(chest).contents.size(), 1)
	assert_eq(d.token(hero).loot.size(), 1)
	assert_eq(d.token(hero).loot[0].name, "Espada corta")
	s.undo()
	assert_eq(d.level(0).object(chest).contents.size(), 2, "deshacer devuelve la espada al cofre")
	assert_true(d.token(hero).loot.is_empty())
	assert_true(p.give_all())
	assert_true(d.level(0).object(chest).contents.is_empty())
	assert_eq(d.token(hero).loot.size(), 2)
	# El botín de una ficha y enseñarlo.
	p.show_token(hero)
	assert_eq(p.items().size(), 2)
	p._reveal_chk.button_pressed = true
	assert_true(d.token(hero).loot_revealed)
	assert_true(p.remove_item(0))
	assert_eq(d.token(hero).loot.size(), 1)
	# Los jugadores: solo lectura.
	p.read_only = true
	assert_false(p._dm_box.visible)
	assert_false(p.remove_item(0))


func test_new_chests_in_catalog_and_double_click_opens_panel() -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var models: ObjectModels = ObjectModels.load_default()
	for id: String in ["chest", "chest_large", "coffer", "treasure_chest", "treasure_pile"]:
		var e: ObjectCatalog.Entry = cat.entry(id)
		assert_not_null(e, id)
		assert_true(models.has(id), "con modelo 3D: " + id)
		assert_ne(tr("OBJ_" + id.to_upper()), "OBJ_" + id.to_upper(), "con nombre: " + id)
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = "RPGM1-DND5-EST-G1-223-QN75YR3H-Y"
	main.call("_generate_from_text")
	await wait_process_frames(2)
	var view: MapView2D = main.get("_view")
	var stack: CommandStack = main.get("_stack")
	var d: MapDocument = view.document
	var cell: Vector2i = Vector2i(-1, -1)
	for i: int in d.grid.cell_count():
		var c: Vector2i = d.grid.cell_at(i)
		if d.level(0).get_terrain(c) == Terrain.FLOOR and d.level(0).objects_at(c).is_empty():
			cell = c
			break
	assert_true(view.place_object("coffer", cell, 0))
	assert_not_null(stack)
	var opened: bool = main.call("open_loot_at", 0, cell)
	assert_true(opened)
	var panel: LootPanel = main.get("_loot_panel")
	assert_true(panel.visible)
	assert_eq(panel.target_kind(), SetLootCommand.KIND_OBJECT)
