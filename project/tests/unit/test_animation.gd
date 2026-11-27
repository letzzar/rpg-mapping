extends GutTest
## Animaciones de las fichas en 3D (F5, ADR 043): andan por la ruta al
## moverse, el recorrido sobrevive a las reconstrucciones y acaban en su
## casilla.


func test_token_walks_along_route_and_settles() -> void:
	var d: MapDocument = MapDocument.create("square", 8, 4)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(d)
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.cell = Vector2i(1, 1)
	t.side = MapToken.SIDE_PLAYER
	t.sheet = CharacterSheet.new()
	t.sheet.look = LookCatalog.load_default().default_look("humanoid_medium")
	assert_true(s.execute(AddTokenCommand.new(t)))
	var v: MapView3D = MapView3D.new()
	v.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(v)
	v.document = d
	v.active = true
	# Lento: en el navegador de pruebas un fotograma puede tardar más que
	# todo el paseo a la velocidad normal.
	v.walk_cells_per_s = 1.0
	v.rebuild()
	assert_false(v.is_animating(), "al aparecer no anda")
	assert_true(s.execute(MoveTokenCommand.new(t.id, Vector2i(4, 1), 0)))
	v.rebuild()
	assert_true(v.is_animating(), "al moverse anda")
	await wait_seconds(0.25)
	var holder: Node3D = v.get_node("Tokens").get_node("T%d" % t.id)
	assert_lt(holder.position.x, -0.1, "a mitad de camino, aún por detrás de su casilla")
	# Una reconstrucción a mitad no corta el paseo.
	v.rebuild()
	assert_true(v.is_animating())
	v.walk_cells_per_s = 1000.0
	await wait_process_frames(3)
	holder = v.get_node("Tokens").get_node("T%d" % t.id)
	assert_false(v.is_animating(), "llegó")
	assert_almost_eq(holder.position, Vector3.ZERO, Vector3(0.001, 0.001, 0.001), "en su casilla")
	# Sin animaciones, aparece directamente.
	v.animate = false
	assert_true(s.execute(MoveTokenCommand.new(t.id, Vector2i(6, 2), 0)))
	v.rebuild()
	assert_false(v.is_animating())
