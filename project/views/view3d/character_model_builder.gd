class_name CharacterModelBuilder
extends RefCounted
## Construye la figura 3D de un personaje (PROYECTO §10.2, ADR 034) a partir
## de su aspecto y del LookCatalog: une las primitivas de la complexión y de
## cada pieza en UNA malla con el color en los vértices y una luz fija ya
## aplicada (la escena 3D no tiene luces: el mapa también lleva el sombreado
## en los vértices). Altura 1, apoyada en y = 0 y mirando a +Z (al sur del
## mapa); quien la usa la escala.
##
## Las mallas se guardan por aspecto: muchas fichas iguales comparten malla y
## redibujar la vista no las rehace.

## Dirección de la luz horneada (hacia donde viene la luz, normalizada).
const LIGHT_DIR: Vector3 = Vector3(-0.45, 0.8, 0.4)
const AMBIENT: float = 0.55
const CACHE_MAX: int = 64

static var _cache: Dictionary[String, ArrayMesh] = {}
static var _material: StandardMaterial3D = null


## Malla de la figura (compartida; no modificar).
static func mesh_for(look: CharacterLook, cat: LookCatalog = null) -> ArrayMesh:
	if cat == null:
		cat = LookCatalog.load_default()
	var key: String = CanonicalJson.stringify(look.to_dict())
	if _cache.has(key):
		return _cache[key]
	var m: ArrayMesh = build_mesh(look, cat)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = m
	return m


## Material de las figuras: sin luz, color de vértice.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
	return _material


static func build_mesh(look: CharacterLook, cat: LookCatalog) -> ArrayMesh:
	var b: LookCatalog.Body = cat.body(look.body)
	var shapes: Array[LookCatalog.Shape] = []
	var width: float = 1.0
	if b != null:
		width = b.width
		shapes.append_array(cat.base_shapes(b.family))
		for slot: String in cat.slots:
			if not look.parts.has(slot) or not b.slots.has(slot):
				continue
			var p: LookCatalog.Part = cat.part(look.parts[slot])
			if p != null and p.family == b.family and p.slot == slot:
				shapes.append_array(p.shapes)
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var light: Vector3 = LIGHT_DIR.normalized()
	var squash: Basis = Basis.from_scale(Vector3(width, 1.0, width))
	for s: LookCatalog.Shape in shapes:
		var prim: PrimitiveMesh = _primitive(s)
		var arrays: Array = prim.get_mesh_arrays()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var rot: Basis = Basis.from_euler(Vector3(deg_to_rad(s.rot.x), deg_to_rad(s.rot.y), deg_to_rad(s.rot.z)))
		var xf: Transform3D = Transform3D(squash, Vector3.ZERO) * Transform3D(rot * Basis.from_scale(s.size), s.pos)
		var nbasis: Basis = xf.basis.inverse().transposed()
		var col: Color = cat.color_of(look, s.mat)
		var start: int = verts.size()
		for k: int in pv.size():
			verts.append(xf * pv[k])
			var n: Vector3 = (nbasis * pn[k]).normalized()
			normals.append(n)
			var lit: float = AMBIENT + (1.0 - AMBIENT) * maxf(0.0, n.dot(light))
			colors.append(Color(col.r * lit, col.g * lit, col.b * lit))
		for k: int in pi.size():
			indices.append(start + pi[k])
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, material())
	return mesh


## Primitiva de medidas 1 (se escala con Shape.size).
static func _primitive(s: LookCatalog.Shape) -> PrimitiveMesh:
	match s.shape:
		"sphere":
			var sp: SphereMesh = SphereMesh.new()
			sp.radius = 0.5
			sp.height = 1.0
			sp.radial_segments = 12
			sp.rings = 6
			return sp
		"cylinder", "cone":
			var cy: CylinderMesh = CylinderMesh.new()
			cy.bottom_radius = 0.5
			cy.top_radius = 0.0 if s.shape == "cone" else 0.5 * s.taper
			cy.height = 1.0
			cy.radial_segments = 10
			cy.rings = 1
			return cy
		_:
			var bx: BoxMesh = BoxMesh.new()
			bx.size = Vector3.ONE
			return bx
