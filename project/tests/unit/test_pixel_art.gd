extends GutTest
## Modo pixel art (ADR 047): tiles, muebles y personajes generados por código,
## deterministas y completos (todo terreno, mueble y aspecto tiene su sprite),
## y su uso en las vistas 2D y 3D y en la pantalla principal.


func _count_opaque(img: Image) -> int:
	var n: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				n += 1
	return n


func _colors(img: Image) -> int:
	var seen: Dictionary[String, bool] = {}
	for y: int in img.get_height():
		for x: int in img.get_width():
			seen[img.get_pixel(x, y).to_html()] = true
	return seen.size()


func test_tiles_are_deterministic_varied_and_low_color() -> void:
	var kinds: Array[String] = [PixelTiles.STONE, PixelTiles.WOOD, PixelTiles.GRASS, PixelTiles.DIRT,
		PixelTiles.ROOF, PixelTiles.WATER, PixelTiles.DEEP, PixelTiles.ROCK, PixelTiles.RUBBLE, PixelTiles.PIT]
	for k: String in kinds:
		var a: PixelCanvas = PixelTiles.build(k, Color("a08060"), 1)
		var b: PixelCanvas = PixelTiles.build(k, Color("a08060"), 1)
		assert_eq(a.image.get_size(), Vector2i(32, 32), k)
		assert_eq(a.image.get_data(), b.image.get_data(), "mismo tile cada vez: " + k)
		assert_eq(_count_opaque(a.image), 32 * 32, "tile opaco: " + k)
		assert_lte(_colors(a.image), 16, "paleta corta: " + k)
	var v0: PixelCanvas = PixelTiles.build(PixelTiles.STONE, Color("fbf0d2"), 0)
	var v1: PixelCanvas = PixelTiles.build(PixelTiles.STONE, Color("fbf0d2"), 1)
	assert_ne(v0.image.get_data(), v1.image.get_data(), "las variantes cambian")
	# Los colores de zona eligen el tipo de suelo.
	assert_eq(PixelTiles.floor_kind(Color("fbf0d2")), PixelTiles.STONE)
	assert_eq(PixelTiles.floor_kind(Color("9a6a3a")), PixelTiles.WOOD)
	assert_eq(PixelTiles.floor_kind(Color("6f9a4c")), PixelTiles.GRASS)
	assert_eq(PixelTiles.floor_kind(Color("b9785a"), true), PixelTiles.ROOF)
	for t: ImageTexture in [PixelTiles.wall_strip(), PixelTiles.door_strip(), PixelTiles.window_strip()]:
		assert_eq(t.get_size(), Vector2(32, 8))
	assert_eq(PixelTiles.stairs(true).get_size(), Vector2(32, 32))


func test_every_furniture_has_a_sprite_from_its_model() -> void:
	var models: ObjectModels = ObjectModels.load_default()
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var n: int = 0
	for id: String in cat.ids:
		var e: ObjectCatalog.Entry = cat.entry(id)
		var cv: PixelCanvas = PixelObjects.render(e.id, e.size, 0.0, models)
		assert_eq(cv.width, e.size.x * 32, e.id)
		assert_gte(cv.height, e.size.y * 32, "y algo más por arriba (vista 3/4): " + e.id)
		assert_gt(_count_opaque(cv.image), 40, "se ve: " + e.id)
		n += 1
	assert_eq(n, cat.ids.size())
	# Girado un cuarto de vuelta, la cama (1×2) ocupa 2×1 y su dibujo cambia.
	var bed0: PixelCanvas = PixelObjects.render("bed", Vector2i(1, 2), 0.0, models)
	var bed1: PixelCanvas = PixelObjects.render("bed", Vector2i(2, 1), -TAU / 4.0, models)
	assert_eq(bed1.width, 64)
	assert_gt(_count_opaque(bed1.image), _count_opaque(bed0.image) / 2)
	# Determinista.
	var again: PixelCanvas = PixelObjects.render("bed", Vector2i(1, 2), 0.0, models)
	assert_eq(bed0.image.get_data(), again.image.get_data())


func test_every_preset_has_its_own_character_sprite() -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	var seen: Dictionary[String, String] = {}
	for p: LookCatalog.Preset in cat.presets:
		var cv: PixelCanvas = PixelCharacter.render(cat.look_from_preset(p), cat)
		assert_eq(cv.image.get_size(), Vector2i(32, 32), p.id)
		assert_gt(_count_opaque(cv.image), 150, "se ve: " + p.id)
		var key: String = Marshalls.raw_to_base64(cv.image.get_data()).sha256_text()
		assert_false(seen.has(key), "%s no es igual que %s" % [p.id, seen.get(key, "")])
		seen[key] = p.id
	# Las complexiones KayKit se dibujan con sus pixel_parts (piezas que existen).
	for b: LookCatalog.Body in cat.bodies:
		if b.model.is_empty():
			continue
		assert_false(b.pixel_parts.is_empty(), b.id)
		for slot: String in b.pixel_parts:
			assert_not_null(cat.part(b.pixel_parts[slot]), "%s: %s" % [b.id, b.pixel_parts[slot]])
	# El color del personaje cambia el sprite.
	var look: CharacterLook = cat.look_from_preset(cat.preset("warrior"))
	var a: PixelCanvas = PixelCharacter.render(look, cat)
	look.colors["metal"] = Color("d9b03c")
	var b2: PixelCanvas = PixelCharacter.render(look, cat)
	assert_ne(a.image.get_data(), b2.image.get_data())


func _doc_with_token() -> Array:
	var gen: GeneratorRegistry.Result = GeneratorRegistry.generate("RPGM1-DND5-EST-G1-223-QN75YR3H-Y")
	var d: MapDocument = gen.doc
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	for i: int in d.grid.cell_count():
		var c: Vector2i = d.grid.cell_at(i)
		if d.level(0).get_terrain(c) == Terrain.FLOOR and d.level(0).objects_at(c).is_empty():
			t.cell = c
			break
	t.side = MapToken.SIDE_PLAYER
	t.sheet = CharacterSheet.new()
	var cat: LookCatalog = LookCatalog.load_default()
	t.sheet.look = cat.look_from_preset(cat.preset("kk_knight"))
	d.tokens.append(t)
	return [d, t]


func test_views_draw_in_pixel_art() -> void:
	var pair: Array = _doc_with_token()
	var d: MapDocument = pair[0]
	var t: MapToken = pair[1]
	assert_gt(d.level(0).objects.size(), 0)
	var v: MapView2D = MapView2D.new()
	v.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(v)
	v.document = d
	v.pixel_art = true
	assert_eq(v.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	v.queue_redraw()
	await wait_process_frames(2)
	v.pixel_art = false
	assert_ne(v.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	# 3D: la figura es un sprite que mira a cámara.
	var v3: MapView3D = MapView3D.new()
	v3.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(v3)
	v3.document = d
	v3.active = true
	v3.pixel_art = true
	v3.rebuild()
	var holder: Node3D = v3.get_node("Tokens").get_node("T%d" % t.id)
	var spr: Sprite3D = holder.get_node_or_null("PixelFigure") as Sprite3D
	assert_not_null(spr, "sprite en vez del modelo")
	if spr != null:
		assert_eq(spr.billboard, BaseMaterial3D.BILLBOARD_FIXED_Y)
		assert_eq(spr.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	v3.pixel_art = false
	v3.rebuild()
	holder = v3.get_node("Tokens").get_node("T%d" % t.id)
	assert_null(holder.get_node_or_null("PixelFigure"), "sin pixel art, el modelo de siempre")


func test_main_switch_lowers_3d_resolution() -> void:
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var box: SubViewportContainer = main.get("_view3d_box")
	main.call("set_pixel_art", true)
	var on: bool = main.call("is_pixel_art")
	assert_true(on)
	assert_eq(box.stretch_shrink, 3)
	assert_not_null(box.material)
	main.call("set_pixel_art", false)
	on = main.call("is_pixel_art")
	assert_false(on)
	assert_eq(box.stretch_shrink, 1)
	assert_null(box.material)
