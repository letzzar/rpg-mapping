extends GutTest
## Navegación jerárquica aldea → edificio (F3): MapNavigator, RemoveTokenCommand
## y la entrada con doble clic en la pantalla principal.

const CODE_VILLAGE: String = "RPGM1-DND5-ALD-G1-0-H8DJRFAE-W"
const CODE_TOWN_HEX: String = "RPGM1-PF2E-ALD-G1-28HA-NGYMWQV0-1"


func _profile(system: String) -> SystemProfile:
	for pid: String in SystemProfile.available_ids():
		var p: SystemProfile = SystemProfile.load_id(pid)
		if p.is_valid() and p.seed_code == system:
			return p
	return null


func _settlement(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_not_null(res.doc, code)
	return res.doc


func _token(doc: MapDocument, level: int, cell: Vector2i, side: String, token_name: String) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = doc.allocate_id()
	t.name = token_name
	t.level = level
	t.cell = cell
	t.side = side
	assert_true(doc.add_token(t), token_name)
	return t


func _party(doc: MapDocument) -> Array[MapToken]:
	var out: Array[MapToken] = []
	for t: MapToken in doc.tokens:
		if PartyVision.SIDES_IN_PARTY.has(t.side):
			out.append(t)
	return out


# --- RemoveTokenCommand ---------------------------------------------------------

func test_remove_token_command_undo_redo() -> void:
	var doc: MapDocument = _settlement(CODE_VILLAGE)
	var ch: MapChild = doc.level(0).children[0]
	var a: MapToken = _token(doc, 0, ch.entrance, MapToken.SIDE_PLAYER, "A")
	var stack: CommandStack = CommandStack.new(doc)
	assert_true(stack.execute(RemoveTokenCommand.new(a.id)))
	assert_null(doc.token(a.id))
	assert_false(stack.execute(RemoveTokenCommand.new(a.id)), "ya no existe")
	stack.undo()
	assert_not_null(doc.token(a.id))
	assert_eq(doc.token(a.id).cell, ch.entrance)
	stack.redo()
	assert_null(doc.token(a.id))


# --- MapNavigator ---------------------------------------------------------------

## Entrar en cada edificio de dos asentamientos (cuadrada y hex): el grupo
## aparece en el hijo en la casilla de la entrada (zona "entrance" de EDI,
## transitable), el padre se queda sin él y los demás bandos se quedan fuera.
func test_enter_moves_party_through_the_door() -> void:
	for code: String in [CODE_VILLAGE, CODE_TOWN_HEX]:
		var system: String = SeedCode.parse(code).system
		var prof: SystemProfile = _profile(system)
		var doc: MapDocument = _settlement(code)
		# Uno de cada tipo: generar los 75 hijos costaba ~10 s.
		var seen_kinds: Dictionary[String, bool] = {}
		for ch: MapChild in doc.level(0).children:
			if seen_kinds.has(ch.kind):
				continue
			seen_kinds[ch.kind] = true
			var nav: MapNavigator = MapNavigator.new()
			var root: MapNavigator.Frame = nav.open_root(doc)
			var p1: MapToken = _token(doc, 0, ch.entrance, MapToken.SIDE_PLAYER, "P1")
			var cells: Array[Vector2i] = MapNavigator.free_cells_near(doc, 0, ch.entrance, prof)
			var p2: MapToken = _token(doc, 0, cells[0], MapToken.SIDE_ALLY, "P2")
			var foe: MapToken = _token(doc, 0, cells[1], MapToken.SIDE_ENEMY, "E")
			var f: MapNavigator.Frame = nav.enter(ch, 0, prof)
			assert_not_null(f, ch.seed_code)
			if f == null:
				return
			assert_eq(nav.depth(), 2)
			assert_eq(f.doc.seed_code, ch.seed_code)
			assert_eq(f.level_index, ch.child_level)
			var inside: Array[MapToken] = _party(f.doc)
			assert_eq(inside.size(), 2, ch.seed_code)
			var door: Vector2i = ch.to_child_cell(ch.entrance)
			assert_eq(inside[0].cell, door, "P1 en la puerta: " + ch.seed_code)
			assert_ne(inside[1].cell, door, "P2 al lado, no encima")
			var lvl: MapLevel = f.doc.level(ch.child_level)
			var room_id: int = lvl.get_room_id(door)
			var kind: String = ""
			for r: MapRoom in lvl.rooms:
				if r.id == room_id:
					kind = r.kind
			assert_eq(kind, MapRoom.KIND_ENTRANCE, "la puerta del hijo: " + ch.seed_code)
			var mask: PackedByteArray = lvl.movement_mask()
			assert_true((mask[f.doc.grid.index_of(door)] & MapLevel.MOVE_PASSABLE) != 0, ch.seed_code)
			assert_null(doc.token(p1.id))
			assert_null(doc.token(p2.id))
			assert_not_null(doc.token(foe.id), "el enemigo se queda fuera")
			assert_false(root.stack.can_undo(), "el paso de mapa no se deshace")
			assert_false(f.stack.can_undo())
			# Salir: el grupo vuelve delante de la puerta.
			var back: MapNavigator.Frame = nav.back(prof)
			assert_eq(back, root)
			assert_eq(_party(f.doc).size(), 0)
			var out: Array[MapToken] = _party(doc)
			assert_eq(out.size(), 2)
			assert_eq(out[0].cell, ch.entrance)
			doc.remove_token(foe.id)
			for t: MapToken in out:
				doc.remove_token(t.id)


## Volver a entrar en el mismo edificio lo encuentra como se dejó (mismo
## documento, con lo que se dejó dentro); otro edificio es otro documento.
func test_revisit_keeps_child_session() -> void:
	var prof: SystemProfile = _profile("DND5")
	var doc: MapDocument = _settlement(CODE_VILLAGE)
	var nav: MapNavigator = MapNavigator.new()
	nav.open_root(doc)
	var a: MapChild = doc.level(0).children[0]
	var b: MapChild = doc.level(0).children[1]
	var fa: MapNavigator.Frame = nav.enter(a, 0, prof)
	var guard: MapToken = _token(fa.doc, fa.level_index, a.to_child_cell(a.entrance), MapToken.SIDE_NEUTRAL, "Tabernero")
	nav.back(prof)
	var fb: MapNavigator.Frame = nav.enter(b, 0, prof)
	assert_ne(fb.doc, fa.doc)
	nav.back(prof)
	var again: MapNavigator.Frame = nav.enter(a, 0, prof)
	assert_eq(again, fa)
	assert_not_null(again.doc.token(guard.id), "lo de dentro sigue ahí")


## Sin grupo también se entra (el DM mira el edificio), y back en la raíz
## falla con su error.
func test_enter_without_party_and_back_at_root() -> void:
	var prof: SystemProfile = _profile("DND5")
	var doc: MapDocument = _settlement(CODE_VILLAGE)
	var nav: MapNavigator = MapNavigator.new()
	nav.open_root(doc)
	assert_false(nav.can_go_back())
	assert_null(nav.back(prof))
	assert_eq(nav.error, "UI_NAV_NO_PARENT")
	var f: MapNavigator.Frame = nav.enter(doc.level(0).children[2], 0, prof)
	assert_not_null(f)
	assert_eq(f.doc.tokens.size(), 0)
	assert_true(nav.can_go_back())
	assert_null(nav.enter(null, 0, prof))
	assert_eq(nav.error, "UI_NAV_NO_CHILD")


# --- Pantalla principal -----------------------------------------------------------

## Doble clic real (push_input) en la huella de un edificio: entra, el botón
## de volver aparece con el nombre de la aldea, el código es el del edificio y
## la ficha del grupo va con él; volver lo deshace todo.
func test_double_click_enters_building_and_back_returns() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	vp.gui_disable_input = false
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = CODE_VILLAGE
	main.call("_generate_from_text")
	await wait_process_frames(3)
	var view: MapView2D = main.get("_view")
	var doc: MapDocument = main.get("_doc")
	var ch: MapChild = doc.level(0).children[0]
	main.call("_add_token")
	var tok: MapToken = doc.tokens[0]
	var stack: CommandStack = main.get("_stack")
	assert_true(stack.execute(MoveTokenCommand.new(tok.id, ch.entrance, 0)), "ficha a la puerta")
	var center: Vector2i = ch.rect.position + ch.rect.size / 2
	var pos: Vector2 = view.get_global_transform() * doc.grid.cell_to_pixel(center, view.cell_px)
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	vp.push_input(mm, true)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(ev, true)
	var up: InputEventMouseButton = ev.duplicate()
	up.pressed = false
	up.double_click = false
	up.button_mask = 0
	vp.push_input(up, true)
	await wait_process_frames(3)
	var nav: MapNavigator = main.get("_nav")
	assert_eq(nav.depth(), 2, "doble clic entra en el edificio")
	var inner: MapDocument = main.get("_doc")
	assert_eq(inner.seed_code, ch.seed_code)
	assert_eq(edit.text, ch.seed_code)
	var back_btn: Button = main.get("_back_btn")
	assert_true(back_btn.visible)
	assert_string_contains(back_btn.text, tr("SETTLEMENT_VILLAGE"))
	assert_eq(_party(inner).size(), 1)
	assert_eq(view.level_index, ch.child_level)
	assert_gt(inner.level(ch.child_level).explored(PartyVision.VIEWER_PARTY).count(1), 0, "explora al llegar")
	# En 1ª persona, la ficha de la puerta mira a la puerta (no a la fachada).
	var opt: OptionButton = main.get("_view_opt")
	opt.select(2)
	main.call("_apply_view")
	var v3: MapView3D = main.get("_view3d")
	var me: MapToken = inner.token(v3.selected_token)
	assert_not_null(me)
	var facing: int = v3.get("_fp_facing")
	assert_true(MapEdge.is_door(inner.level(ch.child_level).get_edge(me.cell, facing)), "mira a la puerta")
	opt.select(0)
	main.call("_apply_view")
	main.call("_go_back")
	await wait_process_frames(2)
	assert_eq(nav.depth(), 1)
	var outer: MapDocument = main.get("_doc")
	assert_eq(outer, doc)
	assert_eq(edit.text, CODE_VILLAGE)
	assert_false(back_btn.visible)
	assert_eq(_party(outer).size(), 1)
	assert_eq(_party(outer)[0].cell, ch.entrance)


# --- Edificio → estancia (EST G2, ADR 029) ------------------------------------

const CODE_TAVERN: String = "RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T"


## Entrar en una estancia es un acercamiento 1:1: solo pasan las fichas del
## grupo que están dentro de ella, a su casilla equivalente; las demás se
## quedan. Al salir vuelven a la misma casilla del edificio y nivel.
func test_room_keeps_token_positions() -> void:
	var prof: SystemProfile = _profile("DND5")
	var doc: MapDocument = _settlement(CODE_TAVERN)
	var refs: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(CODE_TAVERN)
	assert_gt(refs.size(), 3)
	var ref: EstGeneratorG2.RoomRef = null
	for r: EstGeneratorG2.RoomRef in refs:
		if r.kind == "tavern":
			ref = r
	assert_not_null(ref)
	var nav: MapNavigator = MapNavigator.new()
	var root: MapNavigator.Frame = nav.open_root(doc)
	var inside: MapToken = _token(doc, ref.level, ref.entry, MapToken.SIDE_PLAYER, "Dentro")
	var outside_cell: Vector2i = Vector2i(-1, -1)
	for c: Vector2i in MapNavigator.free_cells_near(doc, ref.level, ref.entry, prof, 400):
		if not ref.rect.has_point(c):
			outside_cell = c
			break
	assert_ne(outside_cell, Vector2i(-1, -1))
	var outside: MapToken = _token(doc, ref.level, outside_cell, MapToken.SIDE_PLAYER, "Fuera")
	var f: MapNavigator.Frame = nav.enter(ref.to_map_child(), ref.level, prof, true)
	assert_not_null(f)
	if f == null:
		return
	# El mapa es exactamente el que da su código EST G2 (criterio de F3).
	# (Se compara el nivel: content_hash() incluye next_id, que la ficha que
	# entra hace avanzar aunque las fichas sean sesión.)
	var alone: GeneratorRegistry.Result = GeneratorRegistry.generate(ref.code)
	assert_eq(CanonicalJson.stringify(f.doc.level(0).content_to_dict()),
		CanonicalJson.stringify(alone.doc.level(0).content_to_dict()))
	assert_eq(f.doc.seed_code, alone.doc.seed_code)
	var party: Array[MapToken] = _party(f.doc)
	assert_eq(party.size(), 1, "solo la que estaba dentro")
	assert_eq(party[0].cell, ref.to_room_cell(ref.entry))
	assert_eq(party[0].level, 0)
	assert_not_null(doc.token(outside.id), "la de fuera se queda")
	assert_null(doc.token(inside.id))
	# Se mueve dentro y sale: misma casilla del edificio, mismo nivel.
	var lvl: MapLevel = f.doc.level(0)
	var target: Vector2i = party[0].cell
	for c: Vector2i in MapNavigator.free_cells_near(f.doc, 0, party[0].cell, prof, 20):
		if ref.rect.has_point(ref.to_building_cell(c)) and c != party[0].cell:
			target = c
	party[0].cell = target
	nav.back(prof)
	var back_party: Array[MapToken] = _party(doc)
	assert_eq(back_party.size(), 2)
	var found: bool = false
	for t: MapToken in back_party:
		if t.name == "Dentro":
			found = true
			assert_eq(t.cell, ref.to_building_cell(target))
			assert_eq(t.level, ref.level)
	assert_true(found)
	assert_eq(root.level_index, ref.level)
	assert_eq(lvl, f.doc.level(0))


## Cadena completa en la pantalla principal: aldea → taberna → sala común →
## volver dos veces. Los botones y la barra nombran cada sitio.
func test_settlement_building_room_chain_in_ui() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = CODE_VILLAGE
	main.call("_generate_from_text")
	await wait_process_frames(2)
	var doc: MapDocument = main.get("_doc")
	var tavern: MapChild = null
	for c: MapChild in doc.level(0).children:
		if c.kind == "tavern":
			tavern = c
	assert_eq(tavern.seed_code, CODE_TAVERN)
	main.call("_on_cell_activated", tavern.rect.position + Vector2i(1, 1))
	await wait_process_frames(2)
	var status: Label = main.get("_status")
	var view: MapView2D = main.get("_view")
	var bdoc: MapDocument = main.get("_doc")
	assert_eq(bdoc.seed_code, CODE_TAVERN)
	var ref: EstGeneratorG2.RoomRef = null
	for r: EstGeneratorG2.RoomRef in EstGeneratorG2.rooms_of(CODE_TAVERN):
		if r.kind == "tavern":
			ref = r
	view.level_index = ref.level
	main.call("_on_cell_activated", ref.entry)
	await wait_process_frames(2)
	var nav: MapNavigator = main.get("_nav")
	assert_eq(nav.depth(), 3)
	assert_eq(edit.text, ref.code)
	assert_string_contains(status.text, tr("ROOM_KIND_TAVERN"))
	var back_btn: Button = main.get("_back_btn")
	assert_string_contains(back_btn.text, tr("BUILDING_TAVERN"))
	main.call("_go_back")
	await wait_process_frames(2)
	assert_eq(nav.depth(), 2)
	assert_eq(edit.text, CODE_TAVERN)
	assert_eq(view.level_index, ref.level, "vuelve al nivel de la estancia")
	assert_string_contains(back_btn.text, tr("SETTLEMENT_VILLAGE"))
	main.call("_go_back")
	await wait_process_frames(2)
	assert_eq(nav.depth(), 1)
	assert_eq(edit.text, CODE_VILLAGE)


# --- Saltos y panel Lugares (ADR 050) -------------------------------------------

## Saltar entre hermanos sin llevar fichas: se mira el otro edificio y el
## grupo se queda; con "llevar", el grupo pasa por la puerta del destino; y
## subir a la aldea lo deja delante de la puerta por la que salió.
func test_jump_looks_or_carries_the_party() -> void:
	var prof: SystemProfile = _profile(SeedCode.parse(CODE_VILLAGE).system)
	var doc: MapDocument = _settlement(CODE_VILLAGE)
	var a: MapChild = doc.level(0).children[0]
	var b: MapChild = doc.level(0).children[1]
	var nav: MapNavigator = MapNavigator.new()
	nav.open_root(doc)
	_token(doc, 0, a.entrance, MapToken.SIDE_PLAYER, "P1")
	var fa: MapNavigator.Frame = nav.enter(a, 0, prof)
	assert_eq(_party(fa.doc).size(), 1)
	# Solo mirar el edificio B: la ficha sigue en A.
	var to_b: Array[MapChild] = [b]
	var fb: MapNavigator.Frame = nav.jump(to_b, 0, false, prof)
	assert_not_null(fb, nav.error)
	assert_eq(fb.doc.seed_code, b.seed_code)
	assert_eq(nav.depth(), 2)
	assert_eq(_party(fb.doc).size(), 0, "mirar no mueve fichas")
	assert_eq(_party(fa.doc).size(), 1)
	# Volver a A (ya visitado) llevándose a nadie y después saltar a B con el grupo.
	var to_a: Array[MapChild] = [a]
	assert_eq(nav.jump(to_a, 0, false, prof), fa, "A se reabre como se dejó")
	fb = nav.jump(to_b, 0, true, prof)
	assert_eq(_party(fa.doc).size(), 0)
	assert_eq(_party(fb.doc).size(), 1, "con llevar, el grupo llega")
	var t: MapToken = _party(fb.doc)[0]
	assert_eq(t.level, b.child_level)
	assert_true(Terrain.is_passable(fb.doc.level(t.level).get_terrain(t.cell)))
	# Subir a la aldea con el grupo: delante de la puerta de B.
	var root_path: Array[MapChild] = []
	var fr: MapNavigator.Frame = nav.jump(root_path, 0, true, prof)
	assert_eq(fr.doc, doc)
	assert_eq(nav.depth(), 1)
	var out: Array[MapToken] = _party(doc)
	assert_eq(out.size(), 1)
	assert_lte(absi(out[0].cell.x - b.entrance.x) + absi(out[0].cell.y - b.entrance.y), 3, "sale por la puerta de B")
	# Un hijo que no existe no rompe la ruta.
	var bad: MapChild = b.copy()
	bad.id = 999999
	bad.seed_code = "RPGM1-XXXX"
	var bad_path: Array[MapChild] = [bad]
	assert_null(nav.jump(bad_path, 0, false, prof))
	assert_eq(nav.depth(), 1)


## El panel Lugares lista los mapas visitados en árbol y los sitios del mapa
## actual (filtrables), y pide el salto; en la pantalla principal mueve la
## vista. "Añadir criatura" pone un goblin enemigo junto a la ficha elegida.
func test_places_panel_and_add_creature() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = CODE_VILLAGE
	main.call("_generate_from_text")
	await wait_process_frames(2)
	var doc: MapDocument = main.get("_doc")
	var panel: PlacesPanel = main.get("_places_panel")
	var btn: Button = main.get("_places_btn")
	btn.button_pressed = true
	btn.pressed.emit()
	await wait_process_frames(1)
	assert_true(panel.visible)
	assert_eq(panel.tree_count(), 1, "solo la aldea")
	var n: int = panel.here_count()
	assert_gt(n, 3, "sus edificios")
	var filt: LineEdit = panel.get("_filter")
	filt.text = panel.here_name(0).substr(0, 4)
	filt.text_changed.emit(filt.text)
	assert_between(panel.here_count(), 1, n)
	filt.text = ""
	filt.text_changed.emit("")
	# Ir al primer sitio solo a mirar.
	panel.go_here(0)
	await wait_process_frames(2)
	var nav: MapNavigator = main.get("_nav")
	assert_eq(nav.depth(), 2)
	var now_doc: MapDocument = main.get("_doc")
	assert_ne(now_doc, doc)
	assert_eq(panel.tree_count(), 2, "aldea y el edificio visitado")
	# Volver a la raíz desde el árbol.
	panel.go_tree(0)
	await wait_process_frames(2)
	now_doc = main.get("_doc")
	assert_eq(now_doc, doc)
	# Criatura: junto a la ficha elegida, enemiga por ser un monstruo.
	main.call("_add_token")
	var hero: MapToken = doc.tokens[-1]
	main.set("_selected_token", hero.id)
	var gob: MapToken = main.call("add_creature", "goblin")
	assert_not_null(gob)
	assert_eq(gob.side, MapToken.SIDE_ENEMY)
	assert_not_null(gob.sheet)
	assert_eq(gob.sheet.look.body, "humanoid_small")
	assert_lte(absi(gob.cell.x - hero.cell.x) + absi(gob.cell.y - hero.cell.y), 4, "junto a la ficha elegida")
	main.set("_selected_token", hero.id)
	var gob2: MapToken = main.call("add_creature", "goblin")
	assert_eq(gob2.name, gob.name + " 2", "nombres sin repetir")
	var npc: MapToken = main.call("add_creature", "bandit", MapToken.SIDE_ALLY)
	assert_eq(npc.side, MapToken.SIDE_ALLY, "bando elegido")
	var cb: MenuButton = main.get("_creature_btn")
	var pm: PopupMenu = cb.get_popup()
	assert_gt(pm.item_count, LookCatalog.load_default().presets.size(), "todas en el menú")