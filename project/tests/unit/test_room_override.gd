extends GutTest
## E4 (ADR 040): una estancia propia como interior de un edificio o de una
## estancia de edificio, y el guardado del recorrido entero (raíz, mapas
## visitados con sus cambios, sustituciones y en cuál se estaba).

const CODE_VILLAGE: String = "RPGM1-DND5-ALD-G1-0-H8DJRFAE-W"
const CODE_TAVERN: String = "RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T"
const DIR: String = "user://test_rooms_e4/"

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)
	var lib: RoomLibrary = RoomLibrary.new(DIR)
	for e: RoomLibrary.Entry in lib.entries():
		lib.remove(e.id)


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_not_null(res.doc, res.error)
	if res.doc.seed_code.is_empty():
		res.doc.seed_code = code
	return res.doc


## Estancia en blanco 6×5 con un cofre y nombre.
func _my_room() -> MapDocument:
	var doc: MapDocument = _gen(SeedCode.create("DND5", "EST", 3, {"width": 6, "height": 5}, 0).encode())
	var s: CommandStack = CommandStack.new(doc)
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	assert_true(s.execute(AddObjectCommand.new(0, cat.instantiate(cat.entry("chest"), doc.allocate_id(), Vector2i(2, 2), 0, ""))))
	assert_true(s.execute(SetRoomCommand.new(0, doc.level(0).rooms[0].id, "crypt", "Cripta secreta")))
	return doc


func _party_token(doc: MapDocument, s: CommandStack, cell: Vector2i) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = doc.allocate_id()
	t.name = "Ana"
	t.cell = cell
	t.side = MapToken.SIDE_PLAYER
	assert_true(s.execute(AddTokenCommand.new(t)))
	return t


func test_override_building_interior_and_back() -> void:
	var prof: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var nav: MapNavigator = MapNavigator.new()
	var root: MapNavigator.Frame = nav.open_root(_gen(CODE_VILLAGE))
	var child: MapChild = root.doc.level(0).children[0]
	_party_token(root.doc, root.stack, child.entrance)
	var room: MapDocument = _my_room()
	var cmd: SetChildOverrideCommand = SetChildOverrideCommand.new(child.id, room.seed_code, RoomContent.content_deltas(room))
	assert_true(root.stack.execute(cmd))
	assert_false(root.stack.execute(SetChildOverrideCommand.new(child.id, room.seed_code, RoomContent.content_deltas(room))), "igual: nada")
	var f: MapNavigator.Frame = nav.enter(child, 0, prof)
	assert_not_null(f, nav.error)
	assert_eq(RoomContent.short_id(f.doc), RoomContent.short_id(room), "dentro está mi estancia")
	assert_eq(f.doc.tokens.size(), 1, "el grupo entra")
	assert_eq(f.doc.tokens[0].cell, RoomContent.entrance_cell(f.doc), "por su puerta")
	var out: MapNavigator.Frame = nav.back(prof)
	assert_eq(out.doc.tokens[0].cell, child.entrance, "y sale delante del edificio")
	# Volver a la generada: el mapa guardado en `visited` ya no vale.
	assert_true(root.stack.execute(SetChildOverrideCommand.new(child.id, "")))
	f = nav.enter(child, 0, prof)
	assert_eq(f.doc.seed_code, child.seed_code, "otra vez el edificio generado")
	# El delta reaplica la sustitución entera.
	nav.back(prof)
	assert_true(root.stack.execute(SetChildOverrideCommand.new(child.id, room.seed_code, RoomContent.content_deltas(room))))
	var copy: MapDocument = _gen(CODE_VILLAGE)
	var rep: DeltaReplay.Result = DeltaReplay.replay(copy, root.doc.deltas)
	assert_eq(rep.error, "", rep.detail)
	assert_eq(copy.full_hash(), root.doc.full_hash())


func test_route_save_reopens_where_you_were() -> void:
	var prof: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var nav: MapNavigator = MapNavigator.new()
	var root: MapNavigator.Frame = nav.open_root(_gen(CODE_VILLAGE))
	var a: MapChild = root.doc.level(0).children[0]
	var b: MapChild = root.doc.level(0).children[1]
	_party_token(root.doc, root.stack, a.entrance)
	# Edificio A: generado y editado (puerta abierta). Edificio B: estancia propia.
	var fa: MapNavigator.Frame = nav.enter(a, 0, prof)
	var lvl: MapLevel = fa.doc.level(fa.level_index)
	for id: int in lvl.edge_ids():
		if MapEdge.kind_of(lvl.get_edge_by_id(id)) == MapEdge.KIND_DOOR:
			assert_true(fa.stack.execute(SetEdgeCommand.toggle_flag(fa.doc, fa.level_index, id, MapEdge.FLAG_OPEN)))
			break
	nav.back(prof)
	var room: MapDocument = _my_room()
	assert_true(root.stack.execute(SetChildOverrideCommand.new(b.id, room.seed_code, RoomContent.content_deltas(room))))
	var fb: MapNavigator.Frame = nav.enter(b, 0, prof)
	assert_eq(nav.depth(), 2)
	var text: String = MapFile.route_to_json(nav)
	var res: MapFile.LoadResult = MapFile.from_json(text)
	assert_eq(res.error, "", res.detail)
	assert_eq(res.nav.depth(), 2, "se abre dentro de B, como se dejó")
	assert_eq(res.nav.current().doc.full_hash(), fb.doc.full_hash())
	assert_eq(res.nav.frames[0].doc.full_hash(), root.doc.full_hash())
	var ra: MapNavigator.Frame = res.nav.frames[0].visited[a.id]
	assert_eq(ra.doc.full_hash(), fa.doc.full_hash(), "A con su puerta abierta")
	assert_eq(MapFile.route_to_json(res.nav), text, "guardar lo abierto da el mismo fichero")
	# Volver de B a la aldea funciona tras abrir.
	var back: MapNavigator.Frame = res.nav.back(prof)
	assert_eq(back.doc.full_hash() != "", true)
	assert_eq(res.nav.depth(), 1)


func test_main_use_room_here_and_save() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var panel: RoomEditorPanel = main.get("_editor_panel")
	panel.library = RoomLibrary.new(DIR)
	var id: String = panel.library.save(_my_room())
	assert_false(id.is_empty())
	var edit: LineEdit = main.get("_code_edit")
	edit.text = CODE_TAVERN
	main.call("_generate_from_text")
	var used: bool = main.call("use_room_here", id)
	assert_false(used, "en la raíz no hay padre")
	# Entrar en una estancia de la taberna (EST G2) y sustituirla.
	var nav: MapNavigator = main.get("_nav")
	var ref: EstGeneratorG2.RoomRef = EstGeneratorG2.rooms_of(CODE_TAVERN)[0]
	var view: MapView2D = main.get("_view")
	view.level_index = ref.level
	main.call("_on_cell_activated", ref.rect.position + Vector2i(1, 1))
	assert_eq(nav.depth(), 2, "dentro de la estancia generada")
	used = main.call("use_room_here", id)
	assert_true(used)
	var doc: MapDocument = main.get("_doc")
	assert_eq(RoomContent.short_id(doc), id, "ahora es mi estancia")
	assert_eq(doc.level(0).rooms[0].label, "Cripta secreta")
	# Guardar y abrir: vuelve dentro de mi estancia.
	var path: String = ProjectSettings.globalize_path("user://test_route" + MapFile.EXTENSION)
	var saved: bool = main.call("save_map_to", path)
	assert_true(saved)
	edit.text = CODE_VILLAGE
	main.call("_generate_from_text")
	var opened: bool = main.call("open_map_from", path)
	assert_true(opened)
	DirAccess.remove_absolute(path)
	var reopened: MapDocument = main.get("_doc")
	assert_eq(RoomContent.short_id(reopened), id)
	# Volver a la generada.
	used = main.call("use_room_here", "")
	assert_true(used)
	var gen: MapDocument = main.get("_doc")
	assert_eq(SeedCode.parse(gen.seed_code).scale, "EST")
	assert_eq(SeedCode.parse(gen.seed_code).gen_version, 2, "otra vez EST G2")
