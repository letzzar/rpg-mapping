extends SceneTree
## Renderiza los iconos de los objetos KayKit del botín (ADR 049) a
## project/models/kaykit/items/icons/<modelo>.png (64×64, fondo
## transparente). Se guardan en el repositorio: así el panel los carga en
## cualquier plataforma (también en web y en headless, donde no se puede
## renderizar). Volver a lanzarlo solo si cambian los modelos o el encuadre.
##
##   godot --path project -s ../tools/render_loot_icons.gd
## (con ventana: en --headless no hay renderizado)

const SIZE: int = 64
const OUT_DIR: String = "res://models/kaykit/items/icons"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kinds: LootKinds = LootKinds.load_default()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(SIZE * 4, SIZE * 4)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	vp.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	vp.add_child(env)
	var holder: Node3D = Node3D.new()
	vp.add_child(holder)
	for k: LootKinds.Kind in kinds.kinds:
		if k.model.is_empty():
			continue
		var ps: PackedScene = load("res://models/kaykit/items/%s.gltf" % k.model) as PackedScene
		if ps == null:
			push_error("no carga " + k.model)
			continue
		var n: Node3D = ps.instantiate() as Node3D
		holder.add_child(n)
		# De cara (el giro con más superficie a la vista: el arco de lado, el
		# libro por la tapa), algo girado para que se vea el volumen y, si es
		# largo, en diagonal como en un inventario.
		var best: Vector3 = Vector3.ZERO
		var best_area: float = -1.0
		for pitch: int in [0, 90]:
			for yaw: int in range(0, 180, 10):
				n.rotation_degrees = Vector3(pitch, yaw, 0)
				var b: AABB = _aabb(n)
				if b.size.x * b.size.y > best_area * 1.05:
					best_area = b.size.x * b.size.y
					best = Vector3(pitch, yaw, 0)
		best.y -= 25.0
		n.rotation_degrees = best
		var box: AABB = _aabb(n)
		if box.size.y > box.size.x * 1.6:
			n.rotation_degrees = best + Vector3(0, 0, -40)
		box = _aabb(n)
		var center: Vector3 = box.get_center()
		var side: float = maxf(box.size.x, box.size.y) * 1.12
		cam.size = side
		cam.position = center + Vector3(0, 0, 10)
		cam.look_at(center)
		for i: int in 4:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var out: String = ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, k.model])
		img.save_png(out)
		print("icono: ", out)
		holder.remove_child(n)
		n.free()
	quit()


## Caja de todas las mallas de `n`, en coordenadas del mundo.
func _aabb(n: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
