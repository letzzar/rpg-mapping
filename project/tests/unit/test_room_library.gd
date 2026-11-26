extends GutTest
## Id corto, código para compartir y biblioteca de estancias (E3, ADR 038),
## desde el contenido de la estancia hasta la caja del código de la pantalla
## principal. El formato de los códigos lo prueba test_room_code.gd.

const DIR: String = "user://test_rooms/"

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func after_each() -> void:
	var lib: RoomLibrary = RoomLibrary.new(DIR)
	for e: RoomLibrary.Entry in lib.entries():
		lib.remove(e.id)


func _blank(w: int = 6, h: int = 5) -> MapDocument:
	var sc: SeedCode = SeedCode.create("DND5", "EST", 3, {"width": w, "height": h}, 0)
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(sc.encode())
	assert_not_null(res.doc, res.error)
	if res.doc.seed_code.is_empty():
		res.doc.seed_code = sc.encode()
	return res.doc


func _place(doc: MapDocument, s: CommandStack, catalog_id: String, cell: Vector2i) -> void:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	assert_true(s.execute(AddObjectCommand.new(0, cat.instantiate(cat.entry(catalog_id), doc.allocate_id(), cell, 0, ""))))


func test_id_depends_only_on_resulting_content() -> void:
	var a: MapDocument = _blank()
	var sa: CommandStack = CommandStack.new(a)
	var empty_id: String = RoomContent.short_id(a)
	_place(a, sa, "chest", Vector2i(2, 2))
	var id_a: String = RoomContent.short_id(a)
	assert_ne(id_a, empty_id)
	# Otro camino al mismo resultado: poner y quitar un barril, fichas y
	# niebla por medio.
	var b: MapDocument = _blank()
	var sb: CommandStack = CommandStack.new(b)
	var barrel: MapObject = ObjectCatalog.load_default().instantiate(ObjectCatalog.load_default().entry("barrel"), b.allocate_id(), Vector2i(3, 3), 0, "")
	assert_true(sb.execute(AddObjectCommand.new(0, barrel)))
	var t: MapToken = MapToken.new()
	t.id = b.allocate_id()
	t.cell = Vector2i(1, 1)
	assert_true(sb.execute(AddTokenCommand.new(t)))
	assert_true(sb.execute(RemoveObjectCommand.new(0, barrel.id)))
	# El cofre con el mismo id que en `a` (el id del objeto es contenido).
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var chest: MapObject = cat.instantiate(cat.entry("chest"), a.level(0).objects_at(Vector2i(2, 2))[0].id, Vector2i(2, 2), 0, "")
	b.reserve_ids_through(chest.id)
	assert_true(sb.execute(AddObjectCommand.new(0, chest)))
	assert_eq(RoomContent.short_id(b), id_a, "mismo contenido, mismo id")
	assert_eq(RoomContent.content_deltas(b).size(), 3, "sin fichas ni niebla")
	# Otro sistema, otro id.
	var pf: SeedCode = SeedCode.create("PF2E", "EST", 3, {"width": 6, "height": 5}, 0)
	var pdoc: MapDocument = GeneratorRegistry.generate(pf.encode()).doc
	pdoc.seed_code = pf.encode()
	assert_ne(RoomContent.short_id(pdoc), empty_id)


func test_share_code_recreates_the_room() -> void:
	var doc: MapDocument = _blank(9, 7)
	var s: CommandStack = CommandStack.new(doc)
	_place(doc, s, "table_long", Vector2i(2, 2))
	assert_true(s.execute(SetTerrainCommand.new(0, [Vector2i(6, 2), Vector2i(7, 2)] as Array[Vector2i], Terrain.WATER_SHALLOW)))
	assert_true(s.execute(SetRoomCommand.new(0, doc.level(0).rooms[0].id, "crypt", "Cripta")))
	var code: String = RoomContent.share_code(doc)
	assert_true(code.begins_with("RPGS1-"))
	var p: Dictionary = RoomCode.parse_share_code(code)
	var perr: String = p["error"]
	assert_eq(perr, "")
	var deltas: Array[MapDelta] = p["deltas"]
	var base: String = p["seed_code"]
	var res: MapFile.LoadResult = RoomContent.rebuild(base, deltas)
	assert_eq(res.error, "", res.detail)
	assert_eq(RoomContent.short_id(res.doc), RoomContent.short_id(doc))
	assert_eq(res.doc.level(0).rooms[0].label, "Cripta")


func test_library_save_open_list_remove() -> void:
	var lib: RoomLibrary = RoomLibrary.new(DIR)
	var doc: MapDocument = _blank()
	var s: CommandStack = CommandStack.new(doc)
	_place(doc, s, "chest", Vector2i(1, 1))
	assert_true(s.execute(SetRoomCommand.new(0, doc.level(0).rooms[0].id, "storage", "Despensa")))
	var t: MapToken = MapToken.new()
	t.id = doc.allocate_id()
	t.cell = Vector2i(3, 3)
	assert_true(s.execute(AddTokenCommand.new(t)))
	var id: String = lib.save(doc)
	assert_eq(id, RoomContent.short_id(doc))
	assert_true(lib.has(id))
	var res: MapFile.LoadResult = lib.load_room(id)
	assert_eq(res.error, "", res.detail)
	assert_eq(res.doc.tokens.size(), 0, "en la biblioteca solo va el contenido")
	assert_eq(RoomContent.short_id(res.doc), id)
	var list: Array[RoomLibrary.Entry] = lib.entries()
	assert_eq(list.size(), 1)
	assert_eq(list[0].name, "Despensa")
	assert_eq(lib.save(doc), id, "guardarla otra vez no la duplica")
	assert_eq(lib.entries().size(), 1)
	assert_true(lib.remove(id))
	assert_eq(lib.load_room(id).error, "ROOM_ERR_NOT_IN_LIBRARY")
	var plain: MapDocument = MapDocument.create("square", 4, 4)
	assert_eq(lib.save(plain), "")
	assert_eq(lib.last_error, "ROOM_ERR_NO_CODE")


func test_code_box_opens_ids_and_share_codes() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var panel: RoomEditorPanel = main.get("_editor_panel")
	panel.library = RoomLibrary.new(DIR)
	var made: bool = main.call("new_blank_room", 7, 6, "hex_pointy")
	assert_true(made)
	var view: MapView2D = main.get("_view")
	assert_true(view.place_object("barrel", Vector2i(2, 2), 0))
	var id: String = panel.save_to_library()
	assert_false(id.is_empty())
	var share_edit: LineEdit = panel.get("_share_edit")
	var share: String = share_edit.text
	assert_true(share.begins_with("RPGS1-"))
	var cur: MapDocument = main.get("_doc")
	var edited: String = RoomContent.short_id(cur)
	var edit: LineEdit = main.get("_code_edit")
	for code: String in [id, id.to_lower(), share]:
		edit.text = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
		main.call("_generate_from_text")
		edit.text = code
		main.call("_generate_from_text")
		var doc: MapDocument = main.get("_doc")
		assert_eq(doc.grid.kind, "hex_pointy", code)
		assert_eq(RoomContent.short_id(doc), edited, code)
	# Errores: errata en el id y estancia que no está en la biblioteca.
	var typo: String = id.substr(0, 7) + ("0" if id[7] != "0" else "1") + id.substr(8)
	edit.text = typo
	main.call("_generate_from_text")
	var status: Label = main.get("_status")
	assert_ne(status.text, tr("UI_ROOM_OPENED").replace("{id}", id))
	panel.library.remove(id)
	edit.text = id
	main.call("_generate_from_text")
	assert_eq(status.text, tr("ROOM_ERR_NOT_IN_LIBRARY"))
	# Abrir desde la lista de la biblioteca.
	panel.library = RoomLibrary.new(DIR)
	assert_false(panel.open_library_room(id))
