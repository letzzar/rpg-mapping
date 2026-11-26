extends GutTest
## Turnos e iniciativa (F5, ADR 035): orden, pasar turno, movimiento gastado
## por MoveTokenCommand (con deshacer), bloqueo por velocidad en la vista y en
## el servidor, filtro para los jugadores y el panel.

var _doc: MapDocument
var _stack: CommandStack
var _p: SystemProfile


func before_each() -> void:
	_p = SystemProfile.load_id("dnd5e_2024")
	_doc = MapDocument.create("square", 10, 6)
	_doc.level(0).fill_terrain(Terrain.FLOOR)
	_stack = CommandStack.new(_doc)


func _token(token_name: String, cell: Vector2i, side: String = MapToken.SIDE_PLAYER, speed: int = 30, init_mod: int = 0) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = _doc.allocate_id()
	t.name = token_name
	t.cell = cell
	t.side = side
	t.sheet = CharacterSheet.new()
	t.sheet.name = token_name
	t.sheet.speeds = {"walk": speed}
	t.sheet.has_initiative = true
	t.sheet.initiative = init_mod
	assert_true(_stack.execute(AddTokenCommand.new(t)))
	return _doc.token(t.id)


func _panel() -> TurnPanel:
	var panel: TurnPanel = TurnPanel.new()
	panel.profile = _p
	panel.execute = func(cmd: MapCommand) -> bool: return _stack.execute(cmd)
	add_child_autofree(panel)
	panel.set_document(_doc)
	return panel


func test_order_ties_and_advance() -> void:
	var a: MapToken = _token("A", Vector2i(0, 0), MapToken.SIDE_PLAYER, 30, 1)
	var b: MapToken = _token("B", Vector2i(1, 0), MapToken.SIDE_PLAYER, 30, 3)
	var c: MapToken = _token("C", Vector2i(2, 0), MapToken.SIDE_ENEMY)
	var tt: TurnTracker = TurnTracker.new()
	tt.order = PackedInt32Array([a.id, b.id, c.id])
	tt.initiative = {a.id: 15, b.id: 15, c.id: 20}
	tt.sort_order(_doc)
	assert_eq(tt.order, PackedInt32Array([c.id, b.id, a.id]), "mayor primero; empate: mayor modificador")
	tt.active = true
	tt.moved_ft = 10
	tt.advance(_doc)
	assert_eq(tt.current_token_id(), b.id)
	assert_eq(tt.moved_ft, 0)
	tt.advance(_doc)
	tt.advance(_doc)
	assert_eq(tt.round, 2, "al dar la vuelta, ronda nueva")
	assert_eq(tt.current_token_id(), c.id)
	# Ida y vuelta por JSON dentro del documento.
	_doc.turns = tt
	var back: MapDocument.LoadResult = MapDocument.from_json(_doc.to_canonical_json())
	assert_eq(back.error, "")
	assert_true(back.doc.turns.equals(tt))
	# Sin turnos, el mapa se guarda como antes de ADR 035.
	_doc.turns = TurnTracker.new()
	assert_false(_doc.to_canonical_json().contains("\"turns\""))


func test_moves_spend_speed_only_on_own_turn_with_undo() -> void:
	var a: MapToken = _token("A", Vector2i(0, 0), MapToken.SIDE_PLAYER, 25)
	var b: MapToken = _token("B", Vector2i(0, 2))
	var tt: TurnTracker = TurnTracker.new()
	tt.order = PackedInt32Array([a.id, b.id])
	tt.active = true
	assert_true(_stack.execute(SetTurnsCommand.new(tt)))
	assert_true(_stack.execute(MoveTokenCommand.new(a.id, Vector2i(2, 0), 0, 10)))
	assert_eq(_doc.turns.moved_ft, 10)
	assert_eq(_doc.turns.remaining_ft(a, _p), 15)
	assert_true(_stack.execute(MoveTokenCommand.new(b.id, Vector2i(2, 2), 0, 10)))
	assert_eq(_doc.turns.moved_ft, 10, "fuera de su turno no gasta")
	_stack.undo()
	_stack.undo()
	assert_eq(_doc.turns.moved_ft, 0, "deshacer devuelve el movimiento")
	_stack.undo()
	assert_false(_doc.turns.active, "deshacer el inicio del combate")
	# Bloqueo: solo con la opción y para la ficha del turno.
	tt.block_over_speed = true
	assert_true(_stack.execute(SetTurnsCommand.new(tt)))
	assert_true(_doc.turns.blocks_move(a, _p, 30))
	assert_false(_doc.turns.blocks_move(a, _p, 25))
	assert_false(_doc.turns.blocks_move(b, _p, 300))


func test_view_blocks_and_shows_remaining() -> void:
	var a: MapToken = _token("A", Vector2i(0, 0), MapToken.SIDE_PLAYER, 10)
	var tt: TurnTracker = TurnTracker.new()
	tt.order = PackedInt32Array([a.id])
	tt.active = true
	tt.block_over_speed = true
	assert_true(_stack.execute(SetTurnsCommand.new(tt)))
	var view: MapView2D = MapView2D.new()
	view.document = _doc
	view.profile = _p
	view.command_stack = _stack
	add_child_autofree(view)
	var drag: Callable = func(to: Vector2i) -> void:
		for step: Array in [[Vector2i(_doc.token(a.id).cell), true], [to, false]]:
			var at: Vector2i = step[0]
			var down: bool = step[1]
			var mm: InputEventMouseMotion = InputEventMouseMotion.new()
			mm.position = _doc.grid.cell_to_pixel(at, view.cell_px)
			view.process_input(mm, false)
			var ev: InputEventMouseButton = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = down
			ev.position = mm.position
			view.process_input(ev, false)
	drag.call(Vector2i(4, 0))
	assert_eq(_doc.token(a.id).cell, Vector2i(0, 0), "20 ft con 10 de velocidad: bloqueado")
	drag.call(Vector2i(2, 0))
	assert_eq(_doc.token(a.id).cell, Vector2i(2, 0))
	assert_eq(_doc.turns.moved_ft, 10)
	drag.call(Vector2i(3, 0))
	assert_eq(_doc.token(a.id).cell, Vector2i(2, 0), "ya no le queda")


func test_panel_flow() -> void:
	var a: MapToken = _token("A", Vector2i(0, 0), MapToken.SIDE_PLAYER, 30, 2)
	var e: MapToken = _token("Orco", Vector2i(3, 0), MapToken.SIDE_ENEMY, 30, 0)
	var panel: TurnPanel = _panel()
	var rolls: Array[int] = [10, 18]
	panel.roll_d20 = func() -> int: return rolls.pop_front()
	watch_signals(panel)
	panel.add_level_tokens()
	assert_eq(_doc.turns.order.size(), 2)
	panel.roll_missing()
	assert_eq(_doc.turns.initiative[a.id], 12, "10 + 2")
	assert_eq(_doc.turns.initiative[e.id], 18)
	assert_eq(_doc.turns.order[0], e.id, "ordenado")
	panel.start()
	assert_signal_emitted_with_parameters(panel, "turn_started", [e.id])
	assert_eq(panel.status_text(), tr("UI_TURNS_NOW").replace("{name}", "Orco").replace("{round}", "1"))
	panel.next_turn()
	assert_eq(_doc.turns.current_token_id(), a.id)
	panel.set_initiative(a.id, 25)
	panel.sort_by_initiative()
	assert_eq(_doc.turns.order[0], a.id)
	assert_eq(_doc.turns.current_token_id(), a.id, "ordenar no cambia de quién es el turno")
	panel.remove_token(a.id)
	assert_eq(_doc.turns.current_token_id(), e.id, "quitar la del turno pasa a la siguiente")
	panel.end_combat()
	assert_false(_doc.turns.active)
	assert_eq(_doc.turns.order.size(), 1, "se conserva el orden")
	# Todo se deshace paso a paso.
	for _i: int in 7:
		_stack.undo()
	assert_eq(_doc.turns.order.size(), 2)
	assert_false(_doc.turns.has_token(-1))
	# En solo lectura (jugadores) no se cambia nada.
	var before: String = CanonicalJson.stringify(_doc.turns.to_dict())
	panel.read_only = true
	panel.add_level_tokens()
	panel.end_combat()
	assert_eq(CanonicalJson.stringify(_doc.turns.to_dict()), before)


func test_players_get_filtered_turns_and_server_checks_turn() -> void:
	var hero: MapToken = _token("Ana", Vector2i(0, 0), MapToken.SIDE_PLAYER, 15)
	var orc: MapToken = _token("Orco", Vector2i(5, 0), MapToken.SIDE_ENEMY)
	var ghost: MapToken = _token("Fantasma", Vector2i(9, 5), MapToken.SIDE_ENEMY)
	ghost.hidden = true
	var tt: TurnTracker = TurnTracker.new()
	tt.order = PackedInt32Array([ghost.id, hero.id, orc.id])
	tt.initiative = {ghost.id: 20, hero.id: 12, orc.id: 8}
	tt.active = true
	tt.current = 0
	_doc.turns = tt
	var seen: Array[Dictionary] = [hero.to_dict(), orc.to_dict()]
	var f: TurnTracker = PlayerView.filter_turns(tt, seen)
	assert_eq(f.order, PackedInt32Array([hero.id, orc.id]))
	assert_false(f.initiative.has(ghost.id))
	assert_false(f.active, "le toca a una oculta: para ellos no hay turno")
	tt.current = 1
	f = PlayerView.filter_turns(tt, seen)
	assert_true(f.active)
	assert_eq(f.current_token_id(), hero.id)
	# Servidor: la ficha del jugador solo se mueve en su turno y sin pasarse.
	var ses: GameSession = GameSession.new()
	var p: GameSession.Player = ses.add_player("Ana")
	hero.character_ref = p.ref()
	var opts: PartyVision.Options = PartyVision.Options.new()
	opts.ambient_lit = true
	ses.set_document(_doc, _p, "Prueba")
	ses.set_vision_options(opts)
	var vis: PartyVision.Result = PartyVision.compute(_doc, 0, _p, opts)
	assert_true(ExploreCommand.from_visible(_doc, 0, PartyVision.VIEWER_PARTY, vis.visible).apply(_doc))
	ses.flush()
	tt.block_over_speed = true
	assert_eq(ses.validate_move(p, hero.id, 0, Vector2i(2, 0)), "", "su turno, 10 ft de 15")
	assert_eq(ses.validate_move(p, hero.id, 0, Vector2i(4, 0)), "NET_MOVE_TOO_FAR")
	tt.current = 2
	assert_eq(ses.validate_move(p, hero.id, 0, Vector2i(1, 0)), "NET_MOVE_NOT_YOUR_TURN")
	tt.active = false
	assert_eq(ses.validate_move(p, hero.id, 0, Vector2i(4, 0)), "", "sin combate, libre")
