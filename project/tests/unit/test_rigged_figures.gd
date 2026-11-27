extends GutTest
## Figuras con esqueleto (KayKit, CC0; ADR 045): cada modelo carga, lleva las
## animaciones de reposo y andar del esqueleto común y, en la vista 3D, anda
## con su animación al moverse.


func test_every_model_loads_with_animations() -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	var models: int = 0
	for b: LookCatalog.Body in cat.bodies:
		if b.model.is_empty():
			continue
		models += 1
		var n: Node3D = RiggedFigure.create(b.model)
		assert_not_null(n, b.model)
		if n == null:
			continue
		add_child_autofree(n)
		var ap: AnimationPlayer = n.get_node("Anim") as AnimationPlayer
		assert_true(ap.has_animation(RiggedFigure.IDLE), b.id)
		assert_true(ap.has_animation(RiggedFigure.WALK), b.id)
		assert_eq(ap.current_animation, RiggedFigure.IDLE, "empieza en reposo")
		assert_eq(ap.get_animation(RiggedFigure.WALK).loop_mode, Animation.LOOP_LINEAR)
		assert_between(RiggedFigure.height_of(b.model), 1.5, 3.5, "altura en sus unidades")
		# Las pistas encuentran los huesos del esqueleto del personaje.
		var anim: Animation = ap.get_animation(RiggedFigure.WALK)
		var path: NodePath = anim.track_get_path(0)
		assert_not_null(n.get_node_or_null(NodePath(path.get_concatenated_names())), String(path))
	assert_eq(models, 10)


## Armas y escudos KayKit en las manos (ADR 049): cada modelo tipo cuelga sus
## piezas del hueso de su mano, y las figuras con esqueleto solo ofrecen
## piezas con modelo.
func test_presets_hold_their_weapons() -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	var held: int = 0
	for pr: LookCatalog.Preset in cat.presets:
		var b: LookCatalog.Body = cat.body(pr.body)
		if b.model.is_empty():
			continue
		var look: CharacterLook = cat.look_from_preset(pr)
		assert_false(look.parts.is_empty(), pr.id + " lleva algo en la mano")
		var n: Node3D = RiggedFigure.create(b.model)
		add_child_autofree(n)
		assert_eq(RiggedFigure.equip(n, look, cat), look.parts.size(), pr.id)
		var att: BoneAttachment3D = n.find_child("Hand_main_hand", true, false) as BoneAttachment3D
		assert_not_null(att, pr.id)
		if att != null:
			assert_eq(att.bone_name, "handslot.r")
			assert_eq(att.get_child_count(), 1, "el modelo del arma")
		held += 1
		for slot: String in b.slots:
			for p: LookCatalog.Part in cat.parts_for(b.id, slot):
				assert_false(p.model.is_empty(), "%s: %s sin modelo" % [b.id, p.id])
				assert_true(ResourceLoader.exists(p.model), p.model)
	assert_eq(held, 10)
	# Las figuras de primitivas siguen ofreciendo también las piezas sin modelo.
	var ids: Array[String] = []
	for p: LookCatalog.Part in cat.parts_for("humanoid_medium", "main_hand"):
		ids.append(p.id)
	assert_true(ids.has("spear") and ids.has("greatsword"))


func test_view_uses_model_and_walk_animation() -> void:
	var d: MapDocument = MapDocument.create("square", 8, 4)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var s: CommandStack = CommandStack.new(d)
	var t: MapToken = MapToken.new()
	t.id = d.allocate_id()
	t.cell = Vector2i(1, 1)
	t.side = MapToken.SIDE_PLAYER
	t.sheet = CharacterSheet.new()
	var cat: LookCatalog = LookCatalog.load_default()
	t.sheet.look = cat.look_from_preset(cat.preset("kk_knight"))
	assert_true(s.execute(AddTokenCommand.new(t)))
	var v: MapView3D = MapView3D.new()
	v.profile = SystemProfile.load_id("dnd5e_2024")
	add_child_autofree(v)
	v.document = d
	v.active = true
	v.walk_cells_per_s = 1.0
	v.rebuild()
	var holder: Node3D = v.get_node("Tokens").get_node("T%d" % t.id)
	var rig: Node3D = null
	for c: Node in holder.get_children():
		if c.get_node_or_null("Anim") != null:
			rig = c
	assert_not_null(rig, "el caballero es el modelo con esqueleto")
	var ap: AnimationPlayer = rig.get_node("Anim")
	assert_eq(ap.current_animation, RiggedFigure.IDLE)
	assert_true(s.execute(MoveTokenCommand.new(t.id, Vector2i(5, 1), 0)))
	v.rebuild()
	await wait_process_frames(3)
	holder = v.get_node("Tokens").get_node("T%d" % t.id)
	for c: Node in holder.get_children():
		if c.get_node_or_null("Anim") != null:
			rig = c
	ap = rig.get_node("Anim")
	assert_eq(ap.current_animation, RiggedFigure.WALK, "anda al moverse")
	# Hacia el este (el primer paso puede ser en diagonal: en 5e cuesta igual).
	assert_gt(sin(rig.rotation.y), 0.6, "mira hacia donde va")
	v.walk_cells_per_s = 1000.0
	await wait_process_frames(3)
	assert_eq(ap.current_animation, RiggedFigure.IDLE, "y vuelve al reposo")
