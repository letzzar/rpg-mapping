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
