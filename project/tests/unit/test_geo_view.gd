extends GutTest
## Vista y navegación del mundo y la región (F6, ADR 044): dibujo por
## imagen, información de una casilla, distancias en km, entrar en la región
## de una casilla y de ahí en un asentamiento.

var _prev_locale: String = ""


func before_all() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_all() -> void:
	TranslationServer.set_locale(_prev_locale)


func test_world_region_settlement() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	add_child_autofree(vp)
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	vp.add_child(main)
	await wait_process_frames(2)
	var sc: SeedCode = SeedCode.create("DND5", "MUN", 1, {"size": "tiny"}, 777)
	assert_true(sc.is_valid(), sc.error)
	var edit: LineEdit = main.get("_code_edit")
	edit.text = sc.encode()
	main.call("_generate_from_text")
	await wait_process_frames(2)
	var doc: MapDocument = main.get("_doc")
	assert_eq(doc.scale, "MUN")
	var status: Label = main.get("_status")
	assert_string_contains(status.text, "Mundo de 256×128")
	var view: MapView2D = main.get("_view")
	assert_gt(view.scale_cell_mm, 100000000, "casillas de decenas de km")
	# Imagen del mundo: un píxel por casilla.
	var img: Image = MapView2D.geo_image(doc.grid, doc.level(0))
	assert_eq(img.get_size(), Vector2i(256, 128))
	# Una casilla de tierra sin asentamiento.
	var lvl: MapLevel = doc.level(0)
	var land: Vector2i = Vector2i(-1, -1)
	for i: int in doc.grid.cell_count():
		var c: Vector2i = doc.grid.cell_at(i)
		if GeoLayers.is_land(lvl.elevation[i]) and lvl.child_at(c) == null:
			land = c
			break
	assert_true(land.x >= 0)
	var info: String = view.geo_cell_text(land)
	assert_string_contains(info, tr("BIOME_" + Biome.IDS[lvl.biome[doc.grid.index_of(land)]].to_upper()))
	assert_string_contains(info, "de altitud")
	# Regla en km, no en pies.
	view.set("_ruler_from", land)
	view.set("_ruler_to", land + Vector2i(3, 0))
	var ruler: String = view.call("_ruler_text")
	assert_string_contains(ruler, "km")
	# Doble clic en la casilla: su región (hex).
	main.call("_on_cell_activated", land)
	var nav: MapNavigator = main.get("_nav")
	assert_eq(nav.depth(), 2)
	var region: MapDocument = main.get("_doc")
	assert_eq(region.scale, "REG")
	assert_true(region.grid.kind.begins_with("hex"))
	# De la región, a un asentamiento suyo.
	var town: MapChild = null
	for ch: MapChild in region.level(0).children:
		if not ch.kind.begins_with("poi_") and not ch.seed_code.is_empty():
			town = ch
			break
	if town != null:
		main.call("_on_cell_activated", town.rect.position)
		assert_eq(nav.depth(), 3)
		var ald: MapDocument = main.get("_doc")
		assert_eq(ald.scale, "ALD")
		main.call("_go_back")
		assert_eq(nav.depth(), 2)
	# Un punto de interés sin plano: solo se describe.
	for ch: MapChild in region.level(0).children:
		if ch.seed_code.is_empty():
			main.call("_on_cell_activated", ch.rect.position)
			assert_eq(nav.depth(), 2, "no se entra")
			assert_string_contains(status.text, "no tiene plano")
			break
	main.call("_go_back")
	assert_eq(nav.depth(), 1)
