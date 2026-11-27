extends GutTest
## Personajes (F5, ADR 034): formato *.rpgm-char.json, catálogo de aspectos,
## figura 3D, comando de asignar personaje a una ficha, importadores CSV/JSON
## y lo que se envía de ellos a los jugadores.


func _profile() -> SystemProfile:
	return SystemProfile.load_id("dnd5e_2024")


func _sheet() -> CharacterSheet:
	var c: CharacterSheet = CharacterSheet.new()
	c.name = "Brunhilda"
	c.system = "dnd5e_2024"
	c.size_id = "medium"
	c.speeds = {"walk": 25, "climb": 15}
	c.senses = {"darkvision": 60}
	c.has_initiative = true
	c.initiative = -1
	var cat: LookCatalog = LookCatalog.load_default()
	c.look = cat.look_from_preset(cat.preset("warrior"))
	c.look.colors["cloth"] = Color("123456")
	return c


func test_sheet_round_trip() -> void:
	var c: CharacterSheet = _sheet()
	var img: Image = Image.create(300, 200, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	c.portrait_png = CharacterSheet.portrait_from_image(img)
	assert_false(c.portrait_png.is_empty())
	var back: CharacterSheet.LoadResult = CharacterSheet.from_json(c.to_json())
	assert_eq(back.error, "")
	assert_true(back.sheet.equals(c), "ida y vuelta sin pérdidas")
	assert_eq(back.sheet.speeds["climb"], 15)
	assert_eq(back.sheet.initiative, -1)
	assert_eq(back.sheet.look.colors["cloth"].to_html(false), "123456")
	var im: Image = back.sheet.portrait_image()
	assert_eq(im.get_size(), Vector2i(CharacterSheet.PORTRAIT_PX, CharacterSheet.PORTRAIT_PX), "retrato recortado y reducido")
	# Sin iniciativa ni retrato: las claves no aparecen.
	var plain: CharacterSheet = CharacterSheet.new()
	var d: Dictionary = plain.to_dict()
	assert_false(d.has("initiative"))
	assert_false(d.has("portrait_png"))


func test_sheet_rejects_bad_files() -> void:
	assert_ne(CharacterSheet.from_json("[1, 2]").error, "")
	var d: Dictionary = _sheet().to_dict()
	d["format"] = "otra-cosa"
	assert_ne(CharacterSheet.from_json(JSON.stringify(d)).error, "")
	d = _sheet().to_dict()
	d["speeds"] = {"walk": -5}
	assert_ne(CharacterSheet.from_json(JSON.stringify(d)).error, "", "velocidad negativa")
	d = _sheet().to_dict()
	d.erase("look")
	assert_ne(CharacterSheet.from_json(JSON.stringify(d)).error, "")


func test_speed_falls_back_to_walk_and_profile() -> void:
	var p: SystemProfile = _profile()
	var c: CharacterSheet = _sheet()
	assert_eq(c.speed_ft("climb", p), 15)
	assert_eq(c.speed_ft("fly", p), 25, "sin ese modo, la caminando")
	c.speeds.clear()
	assert_eq(c.speed_ft("walk", p), p.default_speed_ft, "sin velocidades, la del perfil")
	var t: MapToken = MapToken.new()
	assert_eq(t.speed_ft(p), p.default_speed_ft, "ficha sin personaje")
	t.sheet = _sheet()
	assert_eq(t.speed_ft(p), 25)


func test_catalog_is_valid_and_builds_every_body() -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	assert_eq(cat.error, "")
	assert_gt(cat.presets.size(), 5)
	for b: LookCatalog.Body in cat.bodies:
		# Los modelos con esqueleto se prueban en test_rigged_figures.gd.
		if not b.model.is_empty():
			assert_true(ResourceLoader.exists(b.model), b.model)
			continue
		var look: CharacterLook = cat.default_look(b.id)
		assert_false(cat.sanitize(look), b.id)
		for slot: String in b.slots:
			for p: LookCatalog.Part in cat.parts_for(b.id, slot):
				look.parts[slot] = p.id
				assert_false(cat.sanitize(look), "%s/%s" % [b.id, p.id])
		var mesh: ArrayMesh = CharacterModelBuilder.build_mesh(look, cat)
		assert_eq(mesh.get_surface_count(), 1, b.id)
		var aabb: AABB = mesh.get_aabb()
		assert_between(aabb.end.y, 0.75, 1.4, "altura de la figura de " + b.id)
		assert_almost_eq(aabb.position.y, 0.0, 0.02, "apoyada en el suelo: " + b.id)
	for pr: LookCatalog.Preset in cat.presets:
		assert_true(_profile().size_ids.has(pr.size_id), pr.id)
		assert_eq(tr("CHAR_PRESET_" + pr.id.to_upper()) != "CHAR_PRESET_" + pr.id.to_upper(), true, "nombre traducido de " + pr.id)
	for p: String in cat.slots:
		assert_ne(tr("CHAR_SLOT_" + p.to_upper()), "CHAR_SLOT_" + p.to_upper())
	for m: String in cat.materials:
		assert_ne(tr("CHAR_MAT_" + m.to_upper()), "CHAR_MAT_" + m.to_upper())
	for b: LookCatalog.Body in cat.bodies:
		assert_ne(tr("CHAR_BODY_" + b.id.to_upper()), "CHAR_BODY_" + b.id.to_upper())
		for slot: String in b.slots:
			for p: LookCatalog.Part in cat.parts_for(b.id, slot):
				assert_ne(tr("CHAR_PART_" + p.id.to_upper()), "CHAR_PART_" + p.id.to_upper())


func test_sanitize_fixes_unknown_look() -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	var l: CharacterLook = CharacterLook.new()
	l.body = "dragon"
	l.parts = {"head": "helmet", "tail": "x"}
	l.colors = {"skin": Color.RED, "plasma": Color.BLUE}
	assert_true(cat.sanitize(l))
	assert_not_null(cat.body(l.body))
	assert_false(l.colors.has("plasma"))
	l = cat.default_look("quadruped")
	l.parts["main_hand"] = "sword"
	assert_true(cat.sanitize(l), "un cuadrúpedo no empuña espadas")
	assert_false(l.parts.has("main_hand"))
	# La malla se cachea por aspecto.
	assert_same(CharacterModelBuilder.mesh_for(l, cat), CharacterModelBuilder.mesh_for(l.copy(), cat))


func test_set_token_sheet_command_with_undo() -> void:
	var d: MapDocument = MapDocument.create("square", 6, 4)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(d)
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.name = "P1"
	t.side = MapToken.SIDE_PLAYER
	assert_true(s.execute(AddTokenCommand.new(t)))
	var c: CharacterSheet = _sheet()
	c.size_id = "large"
	assert_true(s.execute(SetTokenSheetCommand.new(t.id, c)))
	var tk: MapToken = d.token(t.id)
	assert_eq(tk.name, "Brunhilda")
	assert_eq(tk.size_id, "large")
	assert_eq(d.token_cells(tk, _profile()).size(), 4, "ocupa 2×2")
	c.name = "Otro"
	assert_eq(tk.sheet.name, "Brunhilda", "la ficha guarda su copia")
	assert_false(s.execute(SetTokenSheetCommand.new(t.id, tk.sheet)), "mismo personaje: nada")
	# Guardar y cargar el mapa conserva el personaje.
	var back: MapDocument.LoadResult = MapDocument.from_json(d.to_canonical_json())
	assert_eq(back.error, "")
	assert_true(back.doc.token(t.id).sheet.equals(tk.sheet))
	s.undo()
	assert_null(d.token(t.id).sheet)
	assert_eq(d.token(t.id).name, "P1")
	assert_eq(d.token(t.id).size_id, "medium")
	s.redo()
	assert_eq(d.token(t.id).name, "Brunhilda")
	assert_true(s.execute(SetTokenSheetCommand.new(t.id, null)), "quitar el personaje")
	assert_null(d.token(t.id).sheet)
	assert_eq(d.token(t.id).name, "Brunhilda", "conserva el nombre")


func test_csv_import_spanish_headers() -> void:
	var csv: String = "﻿Nombre;Tamaño;Velocidad;Vuelo;Visión en la oscuridad;Iniciativa;Bando;Modelo;Notas\r\n" \
		+ "\"Ana; la Roja\";mediano;30;;60 ft;+2;jugador;ranger;algo\r\n" \
		+ "Grak;Grande;9 m;;;-1;enemigo;ogre;\r\n" \
		+ "\r\n" \
		+ ";pequeño;25;;;;;;\r\n" \
		+ "Pip;minúsculo;veinte;;;x;;dragón;\r\n"
	var r: CharacterImport.Result = CharacterImport.from_csv(csv, _profile())
	assert_eq(r.error, "")
	assert_eq(r.sheets.size(), 3)
	var ana: CharacterSheet = r.sheets[0]
	assert_eq(ana.name, "Ana; la Roja", "comillas con el separador dentro")
	assert_eq(ana.speeds, {"walk": 30} as Dictionary[String, int])
	assert_eq(ana.senses["darkvision"], 60)
	assert_eq(ana.initiative, 2)
	assert_eq(ana.look.parts["off_hand"], "bow", "modelo tipo")
	assert_eq(r.sides[0], "player")
	var grak: CharacterSheet = r.sheets[1]
	assert_eq(grak.size_id, "large")
	assert_eq(grak.speeds["walk"], 30, "9 m = 30 ft con la convención")
	assert_eq(grak.initiative, -1)
	assert_eq(r.sides[1], "enemy")
	var pip: CharacterSheet = r.sheets[2]
	assert_eq(pip.size_id, "medium", "tamaño desconocido: se queda el de por defecto")
	assert_false(pip.has_initiative)
	assert_true(pip.speeds.is_empty())
	# Avisos: columna Notas, fila sin nombre, tamaño, distancia, iniciativa y modelo.
	assert_eq(r.warnings.size(), 6, str(r.warnings))
	assert_eq(CharacterImport.from_csv("Tamaño,Velocidad\nmediano,30\n", _profile()).error, "CHAR_IMPORT_NO_NAME")
	assert_eq(CharacterImport.from_csv("", _profile()).error, "CHAR_IMPORT_EMPTY")


func test_parse_feet() -> void:
	assert_eq(CharacterImport.parse_feet("30"), 30)
	assert_eq(CharacterImport.parse_feet(" 40 pies "), 40)
	assert_eq(CharacterImport.parse_feet("1,5 m"), 5)
	assert_eq(CharacterImport.parse_feet("18m"), 60)
	assert_eq(CharacterImport.parse_feet("-5"), -1)
	assert_eq(CharacterImport.parse_feet("rápido"), -1)


func test_json_import_with_mapping() -> void:
	var text: String = JSON.stringify([
		{"nombre": "Lia", "stats": {"spd": {"walk": 35, "swim": "15 ft"}}, "vision": [{"range": 120}]},
		{"nombre": "Bo", "stats": {"spd": {"walk": 20}}},
		"basura",
	])
	var mapping: Dictionary[String, String] = {"name": "nombre", "walk": "stats.spd.walk", "swim": "stats.spd.swim", "darkvision": "vision.0.range"}
	var r: CharacterImport.Result = CharacterImport.from_json(text, _profile(), mapping)
	assert_eq(r.sheets.size(), 2)
	assert_eq(r.sheets[0].speeds, {"swim": 15, "walk": 35} as Dictionary[String, int])
	assert_eq(r.sheets[0].senses["darkvision"], 120)
	assert_eq(r.sheets[1].speeds["walk"], 20)
	assert_eq(r.warnings.size(), 1)
	# Propuesta de mapeo a partir de las rutas del primer objeto.
	var paths: PackedStringArray = CharacterImport.leaf_paths(text)
	assert_eq(paths, PackedStringArray(["nombre", "stats.spd.swim", "stats.spd.walk", "vision.0.range"]))
	var sug: Dictionary[String, String] = CharacterImport.suggest_mapping(paths, _profile())
	assert_eq(sug, {"name": "nombre", "swim": "stats.spd.swim", "walk": "stats.spd.walk"} as Dictionary[String, String])
	var dlg: CharacterMappingDialog = CharacterMappingDialog.new()
	add_child_autofree(dlg)
	dlg.setup(text, _profile())
	assert_eq(dlg.mapping(), sug, "el diálogo parte de la propuesta")
	# Sin mapeo: claves con nombre reconocible.
	r = CharacterImport.from_json('{"name": "Zed", "speed": 30, "fly": 60, "size": "small"}', _profile())
	assert_eq(r.sheets[0].speeds["fly"], 60)
	assert_eq(r.sheets[0].size_id, "small")
	# Nuestro formato.
	r = CharacterImport.from_json(_sheet().to_json(), _profile())
	assert_true(r.sheets[0].equals(_sheet()))
	assert_eq(CharacterImport.from_json("no", _profile()).error, "CHAR_IMPORT_BAD_FILE")


## Criterio de F5: crear un personaje y verlo en las 3 vistas. Por la
## pantalla principal: diseñador → ficha nueva; diseñador → cambiar la ficha
## seleccionada (se deshace); importar un CSV; y las vistas 2D, 3D y 1.ª
## persona lo dibujan (figura en 3D, retrato o silueta en 2D).
func test_create_character_and_see_it_in_three_views() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
	main.call("_generate_from_text")
	await wait_process_frames(2)
	var d: MapDocument = main.get("_doc")
	# Personaje nuevo sin ficha seleccionada: el diseñador crea la ficha.
	main.call("_open_designer")
	var des: CharacterDesigner = main.get("_designer")
	assert_true(des.visible, "se abre el diseñador")
	var preset_opt: OptionButton = des.get("_preset_opt")
	var wizard: int = 0
	var cat: LookCatalog = LookCatalog.load_default()
	for i: int in cat.presets.size():
		if cat.presets[i].id == "wizard":
			wizard = i + 1
	preset_opt.select(wizard)
	preset_opt.item_selected.emit(wizard)
	var name_edit: LineEdit = des.get("_name_edit")
	name_edit.text = "Merlina"
	name_edit.text_changed.emit("Merlina")
	var spins: Dictionary[String, SpinBox] = des.get("_speed_spins")
	spins["walk"].value = 25
	spins["fly"].value = 40
	await wait_process_frames(1)
	des.get_ok_button().pressed.emit()
	assert_eq(d.tokens.size(), 1)
	var t: MapToken = d.tokens[0]
	assert_eq(t.name, "Merlina")
	assert_eq(t.sheet.look.parts["main_hand"], "staff")
	assert_eq(t.sheet.speeds, {"fly": 40, "walk": 25} as Dictionary[String, int])
	assert_eq(t.speed_ft(SystemProfile.load_id("dnd5e_2024")), 25)
	# Editar la ficha seleccionada: un ogro grande.
	main.set("_selected_token", t.id)
	main.call("_open_designer")
	var size_opt: OptionButton = des.get("_size_opt")
	var p: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	size_opt.select(p.size_ids.find("large"))
	size_opt.item_selected.emit(p.size_ids.find("large"))
	des.get_ok_button().pressed.emit()
	assert_eq(d.token(t.id).size_id, "large")
	assert_eq(d.token(t.id).sheet.speeds["walk"], 25, "conserva lo demás")
	main.call("_undo")
	assert_eq(d.token(t.id).size_id, "medium", "se deshace")
	# Importar un CSV pone las fichas junto a la entrada, con su bando.
	var path: String = "user://test_chars.csv"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("name,size,speed,side,preset\nLobo gris,medium,40,enemy,wolf\nTordo,small,25,ally,halfling\n")
	f.close()
	main.call("import_characters_from", ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(d.tokens.size(), 3)
	var wolf: MapToken = d.tokens[1]
	assert_eq(wolf.side, MapToken.SIDE_ENEMY)
	assert_eq(wolf.sheet.look.body, "quadruped")
	assert_ne(wolf.cell, t.cell, "no se pisan")
	# Las tres vistas.
	var view_opt: OptionButton = main.get("_view_opt")
	for v: int in [0, 1, 2]:
		if v == 2:
			main.set("_selected_token", t.id)
		view_opt.select(v)
		main.call("_apply_view")
		await wait_process_frames(2)
	var v3: MapView3D = main.get("_view3d")
	view_opt.select(1)
	main.call("_apply_view")
	await wait_process_frames(1)
	var figures: int = 0
	for holder: Node in v3.get_node("Tokens").get_children():
		for n: Node in holder.get_children():
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi != null and mi.mesh is ArrayMesh:
				figures += 1
	assert_eq(figures, 3, "una figura por personaje en 3D")
	view_opt.select(0)
	main.call("_apply_view")
	await wait_process_frames(1)


func test_players_see_only_the_look_of_foreign_creatures() -> void:
	var d: MapDocument = MapDocument.create("square", 6, 4)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var p: SystemProfile = _profile()
	for side: String in [MapToken.SIDE_PLAYER, MapToken.SIDE_ENEMY]:
		var t: MapToken = MapToken.new()
		t.id = d.allocate_id()
		t.name = side
		t.side = side
		t.cell = Vector2i(1 if side == MapToken.SIDE_PLAYER else 3, 1)
		t.sheet = _sheet()
		d.add_token(t)
	var opts: PartyVision.Options = PartyVision.Options.new()
	opts.ambient_lit = true
	var snap: PlayerView.Snapshot = PlayerView.build(d, p, opts)
	assert_eq(snap.tokens.size(), 2)
	for td: Dictionary in snap.tokens:
		var r: JsonReader = JsonReader.new()
		var t: MapToken = MapToken.from_dict(r, td)
		assert_eq(r.error, "")
		assert_eq(t.sheet.look.parts["main_hand"], "sword", "el aspecto llega siempre")
		if t.side == MapToken.SIDE_PLAYER:
			assert_eq(t.sheet.speeds["walk"], 25)
		else:
			assert_true(t.sheet.speeds.is_empty(), "sin velocidades del enemigo")
			assert_true(t.sheet.senses.is_empty())
			assert_false(t.sheet.has_initiative)
