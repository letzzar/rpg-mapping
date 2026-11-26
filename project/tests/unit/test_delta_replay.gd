extends GutTest
## Reaplicar ediciones y guardar/abrir mapas (E1 del editor de estancias,
## ADR 036): un mapa guardado como código + deltas vuelve a abrirse IGUAL
## (mismo full_hash), con todas las operaciones que existen.

const CODE: String = "RPGM1-DND5-MAZ-G1-35040-M6SC7N75-W"

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func _generate() -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(CODE)
	assert_not_null(res.doc, res.error)
	if res.doc.seed_code.is_empty():
		res.doc.seed_code = CODE
	return res.doc


func _floor_cells(doc: MapDocument, level: int, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mask: PackedByteArray = doc.level(level).movement_mask()
	for i: int in mask.size():
		if (mask[i] & MapLevel.MOVE_PASSABLE) != 0:
			out.append(doc.grid.cell_at(i))
			if out.size() >= n:
				break
	return out


func _token(doc: MapDocument, cell: Vector2i, token_name: String) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = doc.allocate_id()
	t.name = token_name
	t.cell = cell
	t.side = MapToken.SIDE_PLAYER
	return t


## Un mapa con una edición de cada tipo (y algo deshecho por medio).
func _edited() -> MapDocument:
	var doc: MapDocument = _generate()
	var s: CommandStack = CommandStack.new(doc)
	var p: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	var cells: Array[Vector2i] = _floor_cells(doc, 0, 8)
	var a: MapToken = _token(doc, cells[0], "Ana")
	assert_true(s.execute(AddTokenCommand.new(a)))
	var b: MapToken = _token(doc, cells[1], "Oculto")
	b.hidden = true
	b.side = MapToken.SIDE_ENEMY
	assert_true(s.execute(AddTokenCommand.new(b)))
	var gone: MapToken = _token(doc, cells[2], "Se va")
	assert_true(s.execute(AddTokenCommand.new(gone)))
	assert_true(s.execute(RemoveTokenCommand.new(gone.id)))
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.name = "Ana la Roja"
	sheet.speeds = {"walk": 25}
	sheet.look = LookCatalog.load_default().default_look("humanoid_small")
	assert_true(s.execute(SetTokenSheetCommand.new(a.id, sheet)))
	assert_true(s.execute(SetTokenCharacterCommand.new(a.id, "player:1")))
	var tt: TurnTracker = TurnTracker.new()
	tt.order = PackedInt32Array([a.id, b.id])
	tt.initiative = {a.id: 14, b.id: 9}
	tt.active = true
	assert_true(s.execute(SetTurnsCommand.new(tt, "CMD_TURNS_START")))
	assert_true(s.execute(MoveTokenCommand.new(a.id, cells[3], 0, 10)))
	# Deshecho: no debe quedar en el fichero.
	assert_true(s.execute(MoveTokenCommand.new(a.id, cells[4], 0, 5)))
	s.undo()
	var lvl: MapLevel = doc.level(0)
	for id: int in lvl.edge_ids():
		if MapEdge.kind_of(lvl.get_edge_by_id(id)) == MapEdge.KIND_DOOR:
			assert_true(s.execute(SetEdgeCommand.toggle_flag(doc, 0, id, MapEdge.FLAG_OPEN)))
			break
	var vis: PartyVision.Result = PartyVision.compute(doc, 0, p, PartyVision.Options.new())
	assert_true(s.execute(ExploreCommand.from_visible(doc, 0, PartyVision.VIEWER_PARTY, vis.visible)))
	# Escalera al otro nivel con la ficha (cambio de nivel).
	var st: MapStair = doc.level(0).stairs[0] if not doc.level(0).stairs.is_empty() else null
	if st != null and st.to_level > 0:
		assert_true(s.execute(MoveTokenCommand.new(a.id, st.cell, 0)))
		assert_true(s.execute(MoveTokenCommand.new(a.id, st.to_cell, st.to_level)))
	return doc


func test_round_trip_reopens_identical() -> void:
	var doc: MapDocument = _edited()
	var ops: Dictionary[String, bool] = {}
	for dl: MapDelta in doc.deltas:
		ops[dl.op] = true
	for op: String in ["add_token", "remove_token", "move_token", "set_edge", "explore",
			"set_token_character", "set_token_sheet", "set_turns"]:
		assert_true(ops.has(op), "el mapa de prueba usa " + op)
	var text: String = MapFile.to_json(doc)
	var res: MapFile.LoadResult = MapFile.from_json(text)
	assert_eq(res.error, "", res.detail)
	assert_eq(res.doc.full_hash(), doc.full_hash(), "fichas, niebla, puertas, turnos y deltas iguales")
	assert_eq(res.doc.next_id(), doc.next_id(), "incluidos los ids de fichas borradas")
	assert_eq(res.doc.token(doc.tokens[0].id).sheet.name, "Ana la Roja")
	assert_eq(res.doc.turns.moved_ft, doc.turns.moved_ft)
	# Guardar lo reabierto da el mismo fichero.
	assert_eq(MapFile.to_json(res.doc), text)
	# Lo que se guarda es mucho menor que el documento entero.
	assert_lt(text.length(), doc.to_canonical_json().length())


func test_errors() -> void:
	assert_eq(MapFile.from_json("no").error, "MAP_ERR_FILE")
	assert_eq(MapFile.from_json("{}").error, "MAP_ERR_FILE")
	var d: Dictionary = MapFile.to_dict(_edited())
	var v: Dictionary = d.duplicate(true)
	v["schema_version"] = 99
	assert_eq(MapFile.from_dict(v).error, "MAP_ERR_VERSION")
	var h: Dictionary = d.duplicate(true)
	h["content_hash"] = "0".repeat(64)
	assert_eq(MapFile.from_dict(h).error, "MAP_ERR_GENERATOR", "generador cambiado sin subir GEN")
	var bad: Dictionary = d.duplicate(true)
	var deltas: Array = bad["deltas"]
	deltas.append({"op": "move_token", "data": {"token": 99999, "level": 0, "x": 1, "y": 1, "cost": 0}})
	var r: MapFile.LoadResult = MapFile.from_dict(bad)
	assert_eq(r.error, "MAP_ERR_DELTA")
	assert_string_contains(r.detail, "move_token")
	var unk: Dictionary = d.duplicate(true)
	var deltas2: Array = unk["deltas"]
	deltas2.append({"op": "teleport", "data": {}})
	assert_eq(MapFile.from_dict(unk).error, "MAP_ERR_DELTA")
	var code: Dictionary = d.duplicate(true)
	code["seed_code"] = "RPGM1-DND5-MAZ-G1-35040-M6SC7N75-X"
	assert_ne(MapFile.from_dict(code).error, "", "código con errata")


func test_map_without_code_saves_whole_document() -> void:
	var doc: MapDocument = MapDocument.create("hex_flat", 7, 5)
	doc.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(doc)
	assert_true(s.execute(AddTokenCommand.new(_token(doc, Vector2i(2, 2), "Lía"))))
	var d: Dictionary = MapFile.to_dict(doc)
	assert_true(d.has("document"))
	assert_false(d.has("content_hash"))
	var res: MapFile.LoadResult = MapFile.from_json(MapFile.to_json(doc))
	assert_eq(res.error, "")
	assert_eq(res.doc.full_hash(), doc.full_hash())


func test_main_save_and_open() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = CODE
	main.call("_generate_from_text")
	main.call("_add_token")
	main.call("_add_token")
	var doc: MapDocument = main.get("_doc")
	var before: String = doc.full_hash()
	var path: String = ProjectSettings.globalize_path("user://test_map" + MapFile.EXTENSION)
	var saved: bool = main.call("save_map_to", path)
	assert_true(saved)
	edit.text = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
	main.call("_generate_from_text")
	var other: MapDocument = main.get("_doc")
	assert_ne(other.full_hash(), before)
	var opened: bool = main.call("open_map_from", path)
	assert_true(opened)
	var reopened: MapDocument = main.get("_doc")
	assert_eq(reopened.full_hash(), before)
	assert_eq(edit.text, CODE)
	DirAccess.remove_absolute(path)
	var missing: bool = main.call("open_map_from", path)
	assert_false(missing, "fichero que no existe")
