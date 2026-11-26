extends GutTest
## Universal VTT (ADR 030): exportación, importación e ida y vuelta.

const CODE_MAZ: String = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
const CODE_TAVERN: String = "RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T"



func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_not_null(res.doc, code)
	return res.doc


func _seg(ax: float, ay: float, bx: float, by: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(ax, ay), Vector2(bx, by)])


## ¿Qué hay en el lado `dir` de la casilla transitable `c`? "wall", "door
## abierta/cerrada" u "open". Ventanas y vanos cuentan como "open" (UVTT no
## los tiene: no tapan la visión).
func _side(doc: MapDocument, level: int, c: Vector2i, dir: int, dm: bool) -> String:
	var g: GridGeometry = doc.grid
	var lvl: MapLevel = doc.level(level)
	var v: int = lvl.get_edge(c, dir)
	match MapEdge.kind_of(v):
		MapEdge.KIND_WALL:
			return "wall"
		MapEdge.KIND_DOOR:
			return "door_open" if MapEdge.has_flag(v, MapEdge.FLAG_OPEN) else "door_closed"
		MapEdge.KIND_SECRET_DOOR:
			if dm or MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED):
				return "door_open" if MapEdge.has_flag(v, MapEdge.FLAG_OPEN) else "door_closed"
			return "wall"
	var n: Vector2i = g.neighbor(c, dir)
	if g.in_bounds(n) and Terrain.is_solid(lvl.get_terrain(n)):
		return "wall"
	return "open"


## Exportar y reimportar conserva, en cada lado de cada casilla no maciza,
## si hay muro, puerta (y si está abierta) o nada.
func _check_round_trip(code: String, level: int, dm: bool) -> void:
	var doc: MapDocument = _gen(code)
	# Una puerta abierta para comprobar también "closed".
	var lvl0: MapLevel = doc.level(level)
	for id: int in lvl0.edge_ids():
		if MapEdge.kind_of(lvl0.get_edge_by_id(id)) == MapEdge.KIND_DOOR:
			lvl0.set_edge_by_id(id, MapEdge.with_flag(lvl0.get_edge_by_id(id), MapEdge.FLAG_OPEN, true))
			break
	var d: Dictionary = UvttCodec.export_level(doc, level, PackedByteArray(), 50, dm)
	var res: UvttCodec.ImportResult = UvttCodec.import_text(UvttCodec.to_json(d))
	assert_eq(res.error, "", code)
	if res.doc == null:
		return
	assert_eq(res.doc.grid.width, doc.grid.width)
	assert_eq(res.doc.grid.height, doc.grid.height)
	assert_almost_eq(res.approximated_length, 0.0, 0.001, "todo encaja en la rejilla")
	var g: GridGeometry = doc.grid
	var lvl: MapLevel = doc.level(level)
	var bad: int = 0
	for i: int in g.cell_count():
		var c: Vector2i = g.cell_at(i)
		if Terrain.is_solid(lvl.get_terrain(c)):
			continue
		for dir: int in g.edge_direction_count():
			var want: String = _side(doc, level, c, dir, dm)
			var got: String = _side(res.doc, 0, c, dir, true)
			if want != got:
				bad += 1
				if bad <= 5:
					assert_eq(got, want, "%s casilla %s lado %d" % [code, c, dir])
	assert_eq(bad, 0, code)


func test_round_trip_dungeon() -> void:
	_check_round_trip(CODE_MAZ, 0, false)
	_check_round_trip(CODE_MAZ, 0, true)


func test_round_trip_building_floor() -> void:
	# Planta baja de la taberna (nivel 1: tiene sótano): muros en arista,
	# puertas y ventanas.
	_check_round_trip(CODE_TAVERN, 1, false)


func test_export_structure_and_determinism() -> void:
	var doc: MapDocument = _gen(CODE_MAZ)
	var d: Dictionary = UvttCodec.export_level(doc, 0, PackedByteArray([1, 2, 3]), 64)
	var reso: Dictionary = d["resolution"]
	var ppg: int = reso["pixels_per_grid"]
	assert_eq(ppg, 64)
	var size: Dictionary = reso["map_size"]
	var sx: float = size["x"]
	var sy: float = size["y"]
	assert_eq(sx, float(doc.grid.width))
	assert_eq(sy, float(doc.grid.height))
	var image_b64: String = d["image"]
	assert_eq(image_b64, Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])))
	var los: Array = d["line_of_sight"]
	assert_gt(los.size(), 0)
	for poly_v: Variant in los:
		var poly: Array = poly_v
		for p_v: Variant in poly:
			var p: Dictionary = p_v
			var x: float = p["x"]
			var y: float = p["y"]
			assert_between(x, 0.0, float(doc.grid.width))
			assert_between(y, 0.0, float(doc.grid.height))
	var portals: Array = d["portals"]
	assert_gt(portals.size(), 0, "la mazmorra tiene puertas")
	# Mismo mapa, mismo texto.
	var again: String = UvttCodec.to_json(UvttCodec.export_level(_gen(CODE_MAZ), 0, PackedByteArray([1, 2, 3]), 64))
	assert_eq(UvttCodec.to_json(d), again)


func test_lights_exported_and_imported() -> void:
	var doc: MapDocument = _gen(CODE_TAVERN)
	var lit: int = 0
	for o: MapObject in doc.level(1).objects:
		if maxi(o.light_bright_cells, o.light_dim_cells) > 0:
			lit += 1
	assert_gt(lit, 0, "la taberna tiene luces")
	var d: Dictionary = UvttCodec.export_level(doc, 1, PackedByteArray(), 50)
	var lights: Array = d["lights"]
	assert_eq(lights.size(), lit)
	var res: UvttCodec.ImportResult = UvttCodec.import_text(UvttCodec.to_json(d))
	assert_eq(res.lights, lit)
	var with_light: int = 0
	for o: MapObject in res.doc.level(0).objects:
		if o.light_dim_cells > 0:
			with_light += 1
	assert_eq(with_light, lit)


func test_merge_segments() -> void:
	var segs: Array[PackedVector2Array] = []
	for x: int in 10:
		segs.append(_seg(x, 2, x + 1, 2))
	segs.append(_seg(14, 2, 13, 2))  # Al revés y separado.
	segs.append(_seg(5, 0, 5, 1))
	segs.append(_seg(5, 1, 5, 2))
	var out: Array[PackedVector2Array] = UvttCodec.merge_segments(segs)
	assert_eq(out.size(), 3)
	var lens: Array[float] = []
	for p: PackedVector2Array in out:
		lens.append(p[0].distance_to(p[1]))
	lens.sort()
	assert_eq(lens, [1.0, 2.0, 10.0])


func test_import_snaps_and_drops() -> void:
	var text: String = JSON.stringify({
		"format": 0.3,
		"resolution": {"map_origin": {"x": 0, "y": 0}, "map_size": {"x": 6, "y": 4}, "pixels_per_grid": 70},
		# Muro casi en la línea x = 2 (desviado 0,05) y uno diagonal.
		"line_of_sight": [[{"x": 2.05, "y": 0}, {"x": 2.05, "y": 3}], [{"x": 3, "y": 0.5}, {"x": 5.5, "y": 3.5}]],
		"portals": [{"position": {"x": 2.0, "y": 3.5}, "bounds": [{"x": 2, "y": 3}, {"x": 2, "y": 4}], "rotation": 1.57, "closed": false, "freestanding": false}],
		"lights": [{"position": {"x": 0.5, "y": 0.5}, "range": 6, "intensity": 1, "color": "ffffffff", "shadows": true}],
	})
	var res: UvttCodec.ImportResult = UvttCodec.import_text(text)
	assert_eq(res.error, "")
	var lvl: MapLevel = res.doc.level(0)
	for y: int in 3:
		assert_eq(MapEdge.kind_of(lvl.get_edge(Vector2i(2, y), 3)), MapEdge.KIND_WALL, "muro encajado en x=2, fila %d" % y)
	var door: int = lvl.get_edge(Vector2i(2, 3), 3)
	assert_eq(MapEdge.kind_of(door), MapEdge.KIND_DOOR)
	assert_true(MapEdge.has_flag(door, MapEdge.FLAG_OPEN))
	assert_gt(res.approximated_length, 3.5, "la diagonal se aproxima en escalera")
	# La escalera separa (sin rodeos por dentro del mapa) las casillas de un
	# lado y otro de la diagonal: (5,1) queda arriba-derecha y (3,3) abajo-izq.
	var r: MovementCost.Route = null
	var prof: SystemProfile = null
	for pid: String in SystemProfile.available_ids():
		var p: SystemProfile = SystemProfile.load_id(pid)
		if p.is_valid() and p.seed_code == "DND5":
			prof = p
	r = MovementCost.find_route(prof, lvl, Vector2i(5, 1), Vector2i(4, 3), "")
	assert_true(not r.found or r.cells.size() > 4, "no se cruza la diagonal en línea recta")
	assert_eq(res.lights, 1)
	assert_eq(res.doc.level(0).objects[0].light_dim_cells, 6)
	assert_null(res.image)


func test_import_errors() -> void:
	assert_eq(UvttCodec.import_text("no es json").error, "UVTT_ERR_JSON")
	assert_eq(UvttCodec.import_text("{}").error, "UVTT_ERR_RESOLUTION")
	assert_eq(UvttCodec.import_text(JSON.stringify({"resolution": {"map_size": {"x": 0, "y": 5}}})).error, "UVTT_ERR_SIZE")
	assert_eq(UvttCodec.import_text(JSON.stringify({"resolution": {"map_size": {"x": 9999, "y": 5}}})).error, "UVTT_ERR_SIZE")
	# Se restaura el idioma: dejarlo cambiado hacía que el resultado de los
	# tests siguientes dependiera del orden.
	var prev: String = TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	for k: String in ["UVTT_ERR_JSON", "UVTT_ERR_RESOLUTION", "UVTT_ERR_SIZE", "UI_UVTT_IMPORTED", "UI_UVTT_DROPPED", "UI_EXPORT_UVTT", "UI_IMPORT_UVTT"]:
		assert_ne(tr(k), k, k)
	TranslationServer.set_locale(prev)


func test_image_round_trip() -> void:
	var img: Image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.3))
	var doc: MapDocument = _gen(CODE_MAZ)
	var d: Dictionary = UvttCodec.export_level(doc, 0, img.save_png_to_buffer(), 2)
	var res: UvttCodec.ImportResult = UvttCodec.import_text(UvttCodec.to_json(d))
	assert_not_null(res.image)
	assert_eq(res.image.get_size(), Vector2i(40, 20))
	assert_eq(res.doc.background_image, res.image)
	# El fondo no entra en los hashes.
	var h: String = res.doc.content_hash()
	res.doc.background_image = null
	assert_eq(res.doc.content_hash(), h)


func test_hex_export_stays_inside_map() -> void:
	var hex_code: String = SeedCode.create("DND5", "MAZ", 1, {"grid": "hex_flat"}, 12345).encode()
	var doc: MapDocument = _gen(hex_code)
	assert_ne(doc.grid_kind(), "square")
	var d: Dictionary = UvttCodec.export_level(doc, 0, PackedByteArray(), 50)
	var size: Vector2 = doc.grid.map_pixel_size(1.0)
	var los: Array = d["line_of_sight"]
	assert_gt(los.size(), 0)
	for poly_v: Variant in los:
		var poly: Array = poly_v
		for p_v: Variant in poly:
			var p: Dictionary = p_v
			var x: float = p["x"]
			var y: float = p["y"]
			assert_between(x, -0.01, size.x + 0.01)
			assert_between(y, -0.01, size.y + 0.01)


## Importar desde la pantalla principal: nueva raíz con el fondo, sin código.
func test_open_in_main_screen() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var img: Image = Image.create(30, 30, false, Image.FORMAT_RGBA8)
	var doc: MapDocument = _gen(CODE_MAZ)
	var text: String = UvttCodec.to_json(UvttCodec.export_level(doc, 0, img.save_png_to_buffer(), 1))
	var ok: bool = main.call("open_uvtt_text", text, "prueba.uvtt")
	assert_true(ok)
	await wait_process_frames(2)
	var shown: MapDocument = main.get("_doc")
	assert_not_null(shown.background_image)
	var edit: LineEdit = main.get("_code_edit")
	assert_eq(edit.text, "")
	var status: Label = main.get("_status")
	assert_string_contains(status.text, "prueba.uvtt")
	var bad: bool = main.call("open_uvtt_text", "{}", "mal.uvtt")
	assert_false(bad)
	var still: MapDocument = main.get("_doc")
	assert_eq(still, shown, "un fichero malo no cambia el mapa")
