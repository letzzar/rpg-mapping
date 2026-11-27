class_name RiggedFigure
extends RefCounted
## Figuras con esqueleto y animaciones (modelos KayKit, CC0; ADR 045). Los
## personajes (`Knight.glb`…) y las animaciones (`Rig_Medium_*.glb`)
## comparten el esqueleto `Rig_Medium`, así que a cada personaje se le pone
## un AnimationPlayer con la biblioteca de animaciones de los otros ficheros.
##
## Altura del modelo en sus unidades: se mide una vez por fichero (caché) y
## quien lo usa lo escala a su tamaño.

const ANIM_FILES: PackedStringArray = [
	"res://models/kaykit/Rig_Medium_General.glb",
	"res://models/kaykit/Rig_Medium_MovementBasic.glb",
]
const IDLE: String = "Idle_A"
const WALK: String = "Walking_A"

static var _library: AnimationLibrary = null
static var _heights: Dictionary[String, float] = {}


## Biblioteca con todas las animaciones de ANIM_FILES (se carga una vez).
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	for path: String in ANIM_FILES:
		var ps: PackedScene = load(path) as PackedScene
		if ps == null:
			continue
		var n: Node = ps.instantiate()
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			for anim_name: StringName in ap.get_animation_list():
				if not _library.has_animation(anim_name):
					var a: Animation = ap.get_animation(anim_name).duplicate()
					if String(anim_name).begins_with("Idle") or String(anim_name).begins_with("Walking") or String(anim_name).begins_with("Running"):
						a.loop_mode = Animation.LOOP_LINEAR
					_library.add_animation(anim_name, a)
		n.free()
	return _library


## Instancia el modelo `path` con su AnimationPlayer (null si no carga). El
## modelo mira a +Z y se apoya en y = 0, como las figuras procedurales.
static func create(path: String) -> Node3D:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var root: Node3D = ps.instantiate() as Node3D
	if root == null:
		return null
	var ap: AnimationPlayer = AnimationPlayer.new()
	ap.name = "Anim"
	root.add_child(ap)
	# Las pistas son "Rig_Medium/Skeleton3D:hueso", relativas a la raíz.
	ap.root_node = NodePath("..")
	ap.add_animation_library("", library())
	if ap.has_animation(IDLE):
		ap.play(IDLE)
	return root


## Pone la animación `anim_name` si no es ya la actual.
static func play(figure: Node3D, anim_name: String) -> void:
	var ap: AnimationPlayer = figure.get_node_or_null("Anim") as AnimationPlayer
	if ap != null and ap.has_animation(anim_name) and ap.current_animation != anim_name:
		ap.play(anim_name, 0.2)


## Altura del modelo (parte de arriba de sus mallas), en sus unidades.
static func height_of(path: String) -> float:
	if _heights.has(path):
		return _heights[path]
	var h: float = 2.0
	var ps: PackedScene = load(path) as PackedScene
	if ps != null:
		var n: Node = ps.instantiate()
		var top: float = 0.0
		for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi as MeshInstance3D
			top = maxf(top, m.get_aabb().end.y)
		if top > 0.0:
			h = top
		n.free()
	_heights[path] = h
	return h
