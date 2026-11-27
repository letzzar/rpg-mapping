class_name MapMeshBuilder
extends RefCounted
## Construye la geometría 3D de un nivel de un MapDocument (PROYECTO §7,
## ADR 025). SOLO VISTAS: usa float; no toca el modelo.
##
## Todo sale de primitivas generadas (sin assets): suelo por casilla, caras
## de pared donde una casilla transitable linda con roca o vacío (ADR 018:
## volúmenes por casilla), cajas finas en las aristas con muro, marcos y hojas
## de puerta, cajas para objetos, peldaños y aspas de trampa.
##
## Materiales sin sombreado con color por vértice: el "sombreado" (caras más
## oscuras según su orientación) y la NIEBLA y la LUZ del modelo (PartyVision)
## se hornean en el color. Así 2D, 3D y 1ª persona muestran exactamente las
## mismas casillas visibles/exploradas, y funciona igual en Compatibility
## (WebGL 2) sin luces dinámicas.

const TERRAIN_COLORS: Array[Color] = [
	Color("2b1d14"),  # void
	Color("e9dcb8"),  # floor
	Color("5a4030"),  # wall (roca)
	Color("b89460"),  # rubble
	Color("7fb9cc"),  # water_shallow
	Color("1d4f7c"),  # water_deep
	Color("140e0a"),  # pit
]
const COL_WALL_FACE: Color = Color("8f7b62")
const COL_WALL_TOP: Color = Color("3a2a1e")
const COL_CEILING: Color = Color("2e231b")
## Suelo exterior de un edificio (calle o patio): más gris que el de dentro.
const COL_OUTDOOR: Color = Color("c9c3a6")
## Suelo de las zonas de un asentamiento (ALD, ADR 027) por MapRoom.kind. Las
## que no aparecen (salas, estancias, la huella de un edificio) usan el color
## del terreno. MAZ, EST y EDI no usan estas zonas: no cambian.
const ZONE_COLORS: Dictionary[String, Color] = {
	"street": Color("cdbb94"),
	"plaza": Color("e2d2a4"),
	"bridge": Color("9a7452"),
	"gate": Color("a89276"),
	"yard": Color("d6cf9f"),
	"garden": Color("a9bf7c"),
	"field": Color("bccb8c"),
}
const COL_EDGE_WALL: Color = Color("6e5a46")
const COL_DOOR: Color = Color("8a5f1f")
const COL_SECRET: Color = Color("5fb4d6")
const COL_WINDOW: Color = Color("a8d4e6")
const COL_LOCK: Color = Color("2b1d14")
const COL_OBJ_BLOCK: Color = Color("8a5f1f")
const COL_OBJ_FREE: Color = Color("c9a46a")
const COL_OBJ_LIGHT: Color = Color("f7dc8e")
const COL_TRAP: Color = Color("a3261b")
const COL_STAIR: Color = Color("a89276")


class Options:
	extends RefCounted
	## Metros entre centros de casilla (5 ft = 1,5 m por convención).
	var cell_m: float = 1.5
	var wall_h: float = 3.0
	var door_h: float = 2.2
	## Hueco de las ventanas (MapEdge.KIND_WINDOW), en metros.
	var window_sill_h: float = 0.9
	var window_top_h: float = 2.0
	## Vista del DM: secretas y trampas ocultas visibles.
	var dm_view: bool = true
	## Niebla: con `fog`, las casillas no exploradas no se construyen, las
	## exploradas no visibles se oscurecen y las visibles usan su luz.
	var fog: bool = false
	var visible: PackedByteArray = PackedByteArray()
	var explored: PackedByteArray = PackedByteArray()
	## Techo sobre las casillas transitables (1ª persona).
	var ceiling: bool = false


## Acumulador de triángulos con color por vértice.
class Geo:
	extends RefCounted
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		for k: int in 3:
			normals.append(n)
			colors.append(col)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	## Cuadrilátero con color por esquina (degradados de las paredes).
	func quad4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		for p: Vector3 in [a, b, c, a, c, d]:
			verts.append(p)
			normals.append(n)
		for col: Color in [ca, cb, cc, ca, cc, cd]:
			colors.append(col)

	func is_empty() -> bool:
		return verts.is_empty()

	func to_mesh(mat: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var m: ArrayMesh = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m


## Patrones de textura del shader (ADR 041).
const PATTERN_NONE: int = 0
const PATTERN_FLOOR: int = 1
const PATTERN_WALLS: int = 2
const PATTERN_DETAILS: int = 3

static var _materials: Dictionary[int, ShaderMaterial] = {}


## Material (map_vertex_color.gdshader) con el patrón `pattern`: sin luz,
## color por vértice en sRGB, sin recorte de caras y oscurecimiento por
## distancia. Uno por patrón, compartido por todos los niveles.
static func material(pattern: int = PATTERN_NONE) -> ShaderMaterial:
	if not _materials.has(pattern):
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = load("res://views/view3d/map_vertex_color.gdshader")
		m.set_shader_parameter("pattern", pattern)
		_materials[pattern] = m
	return _materials[pattern]


static func _all_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for p: int in [PATTERN_NONE, PATTERN_FLOOR, PATTERN_WALLS, PATTERN_DETAILS]:
		out.append(material(p))
	return out


## Oscurecimiento por distancia (m); fade_end <= fade_start lo desactiva.
static func set_distance_fade(fade_start: float, fade_end: float) -> void:
	for m: ShaderMaterial in _all_materials():
		m.set_shader_parameter("fade_start", fade_start)
		m.set_shader_parameter("fade_end", fade_end)


## Lado de la casilla (m) para alinear las losas con la rejilla.
static func set_cell_size(cell_m: float) -> void:
	for m: ShaderMaterial in _all_materials():
		m.set_shader_parameter("cell_m", cell_m)


## Texturas activadas o no (colores lisos).
static func set_textures(on: bool) -> void:
	for m: ShaderMaterial in _all_materials():
		m.set_shader_parameter("texture_strength", 1.0 if on else 0.0)


## Pixel art (ADR 047): las texturas procedurales se calculan por téxel
## (`texels` por casilla, 0 = continuo) y con pocos tonos.
static func set_pixel_texels(texels: int) -> void:
	for m: ShaderMaterial in _all_materials():
		m.set_shader_parameter("pixel_texels", float(texels))


## Punto 3D (x, y, z) desde un punto 2D de la rejilla en metros.
static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Factor de brillo de una casilla según la niebla (0 = no se construye).
static func fog_factor(opts: Options, i: int) -> float:
	if not opts.fog:
		return 1.0
	if i < 0:
		return 0.0
	var vis: int = opts.visible[i] if i < opts.visible.size() else 0
	if vis == Visibility.BRIGHT:
		return 1.0
	if vis == Visibility.DIM:
		return 0.7
	if i < opts.explored.size() and opts.explored[i] != 0:
		return 0.35
	return 0.0


## Las paredes salen donde una casilla transitable linda con roca o vacío.
static func is_solid_terrain(t: int) -> bool:
	return t == Terrain.WALL or t == Terrain.VOID


## Construye el nivel. Devuelve un Node3D con un MeshInstance3D por grupo.
static func build_level(doc: MapDocument, level_index: int, opts: Options) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Level%d" % level_index
	var lvl: MapLevel = doc.level(level_index)
	if lvl == null:
		return root
	var g: GridGeometry = doc.grid
	var floor_geo: Geo = Geo.new()
	var wall_geo: Geo = Geo.new()
	var detail_geo: Geo = Geo.new()
	var factor: PackedFloat32Array = PackedFloat32Array()
	factor.resize(g.cell_count())
	for i: int in g.cell_count():
		factor[i] = fog_factor(opts, i)
	_build_cells(g, lvl, opts, factor, floor_geo, wall_geo)
	_build_edges(g, lvl, opts, factor, wall_geo)
	_build_objects(g, lvl, opts, factor, detail_geo)
	_build_features(g, lvl, level_index, opts, factor, detail_geo)
	set_cell_size(opts.cell_m)
	for pair: Array in [["Floor", floor_geo, PATTERN_FLOOR], ["Walls", wall_geo, PATTERN_WALLS], ["Details", detail_geo, PATTERN_DETAILS]]:
		var geo: Geo = pair[1]
		if geo.is_empty():
			continue
		var pattern: int = pair[2]
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = pair[0]
		mi.mesh = geo.to_mesh(material(pattern))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func _build_cells(g: GridGeometry, lvl: MapLevel, opts: Options, factor: PackedFloat32Array,
		floor_geo: Geo, wall_geo: Geo) -> void:
	var cm: float = opts.cell_m
	var h: float = opts.wall_h
	var caps: Dictionary[int, float] = {}
	var outdoor: PackedByteArray = outdoor_mask(lvl)
	var zone_cols: Dictionary[int, Color] = zone_colors_by_room(lvl)
	for i: int in g.cell_count():
		var f: float = factor[i]
		if f <= 0.0:
			continue
		var c: Vector2i = g.cell_at(i)
		var t: int = lvl.terrain[i]
		if is_solid_terrain(t):
			continue
		var poly: PackedVector2Array = g.cell_polygon(c, cm)
		var center: Vector2 = g.cell_to_pixel(c, cm)
		var col: Color = TERRAIN_COLORS[t] if t < TERRAIN_COLORS.size() else TERRAIN_COLORS[0]
		if outdoor[i] != 0 and t == Terrain.FLOOR:
			col = COL_OUTDOOR
		if t == Terrain.FLOOR and zone_cols.has(lvl.room_ids[i]):
			col = zone_cols[lvl.room_ids[i]]
		var y_floor: float = -0.6 if t == Terrain.PIT else (-0.15 if t == Terrain.WATER_DEEP else 0.0)
		# Junta de rejilla: casilla oscura debajo y la casilla algo menor
		# encima (las líneas son el hueco entre las dos).
		_fan(floor_geo, center, poly, y_floor, col * (f * 0.78), true)
		var inner: PackedVector2Array = PackedVector2Array()
		for q: Vector2 in poly:
			inner.append(center.lerp(q, 0.94))
		_fan(floor_geo, center, inner, y_floor + 0.003, col * f, true)
		if opts.ceiling and outdoor[i] == 0:
			_fan(floor_geo, center, poly, h, COL_CEILING * f, false)
		for dir: int in g.edge_direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			var ni: int = g.index_of(n)
			if ni >= 0 and not is_solid_terrain(lvl.terrain[ni]):
				continue
			# Si el lado ya tiene arista (muro fino, puerta o ventana de un
			# edificio, cuyas plantas altas lindan con VOID), la dibuja
			# _build_edges: una cara maciza taparía la ventana. En MAZ y EST
			# las aristas solo separan casillas transitables: no cambia nada.
			if lvl.get_edge(c, dir) != MapEdge.NONE:
				continue
			var seg: PackedVector2Array = g.edge_segment(c, dir, cm)
			var shade: float = _face_shade(seg[1] - seg[0])
			var top: Color = COL_WALL_FACE * (f * shade)
			var bottom: Color = COL_WALL_FACE * (f * shade * 0.55)
			wall_geo.quad4(v3(seg[0], 0.0), v3(seg[1], 0.0), v3(seg[1], h), v3(seg[0], h), bottom, bottom, top, top)
			if ni >= 0:
				var prev: float = caps.get(ni, 0.0)
				caps[ni] = maxf(prev, f)
	# Tapas de la roca que asoma (vista cenital), con el brillo de la casilla
	# transitable vecina más clara.
	if opts.ceiling:
		return
	for ni: int in caps.keys():
		var c2: Vector2i = g.cell_at(ni)
		var cf: float = caps[ni]
		_fan(wall_geo, g.cell_to_pixel(c2, cm), g.cell_polygon(c2, cm), h, COL_WALL_TOP * cf, true)


## Color de suelo de una zona (alfa 0 = la zona no tiene color propio).
static func zone_color(kind: String) -> Color:
	if ZONE_COLORS.has(kind):
		var c: Color = ZONE_COLORS[kind]
		return c
	return Color(0, 0, 0, 0)


## Id de sala -> color de suelo, para las zonas con color propio.
static func zone_colors_by_room(lvl: MapLevel) -> Dictionary[int, Color]:
	var out: Dictionary[int, Color] = {}
	for r: MapRoom in lvl.rooms:
		if ZONE_COLORS.has(r.kind):
			out[r.id] = ZONE_COLORS[r.kind]
	return out


## 1 por casilla al aire libre: zonas de MapRoom.OUTDOOR_KINDS (el exterior de
## un edificio, las calles, parcelas y campos de un asentamiento) y, si el
## nivel tiene alguna, también sus zonas de entrada/salida (el rellano de la
## calle). En una mazmorra la entrada está bajo tierra: sin zonas al aire
## libre no cuenta.
static func outdoor_mask(lvl: MapLevel) -> PackedByteArray:
	var g: GridGeometry = lvl.grid
	var m: PackedByteArray = PackedByteArray()
	m.resize(g.cell_count())
	var ids: Dictionary[int, bool] = {}
	var has_outside: bool = false
	for r: MapRoom in lvl.rooms:
		if MapRoom.OUTDOOR_KINDS.has(r.kind):
			has_outside = true
	if not has_outside:
		return m
	for r: MapRoom in lvl.rooms:
		if MapRoom.OUTDOOR_KINDS.has(r.kind) or r.kind == MapRoom.KIND_ENTRANCE or r.kind == MapRoom.KIND_EXIT:
			ids[r.id] = true
	for i: int in g.cell_count():
		if ids.has(lvl.room_ids[i]):
			m[i] = 1
	return m


## Oscurece las caras según su orientación para dar volumen sin luces.
static func _face_shade(along: Vector2) -> float:
	var a: float = absf(along.normalized().dot(Vector2(0.6, 0.8)))
	return 0.72 + 0.28 * a


static func _fan(geo: Geo, center: Vector2, poly: PackedVector2Array, y: float, col: Color, up: bool) -> void:
	var cy: Vector3 = v3(center, y)
	for k: int in poly.size():
		var a: Vector3 = v3(poly[k], y)
		var b: Vector3 = v3(poly[(k + 1) % poly.size()], y)
		if up:
			geo.tri(cy, b, a, col)
		else:
			geo.tri(cy, a, b, col)


## Caja a lo largo del segmento p0-p1 (grosor horizontal `th`) entre alturas.
static func box_along(geo: Geo, p0: Vector2, p1: Vector2, th: float, y0: float, y1: float, col: Color) -> void:
	var d: Vector2 = (p1 - p0)
	if d.length() < 0.0001:
		return
	var nrm: Vector2 = Vector2(-d.y, d.x).normalized() * (th * 0.5)
	var c: Array[Vector2] = [p0 + nrm, p1 + nrm, p1 - nrm, p0 - nrm]
	var shade: float = _face_shade(d)
	for k: int in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var s: float = shade if k % 2 == 0 else shade * 0.85
		geo.quad(v3(a, y0), v3(b, y0), v3(b, y1), v3(a, y1), col * s)
	geo.quad(v3(c[0], y1), v3(c[1], y1), v3(c[2], y1), v3(c[3], y1), col * 1.05)


## Caja de base rectangular (centro, medio ancho y medio fondo) entre alturas.
static func box(geo: Geo, center: Vector2, half: Vector2, y0: float, y1: float, col: Color) -> void:
	box_along(geo, center - Vector2(half.x, 0.0), center + Vector2(half.x, 0.0), half.y * 2.0, y0, y1, col)


static func _edge_factor(g: GridGeometry, factor: PackedFloat32Array, id: int) -> float:
	var f: float = 0.0
	for c: Vector2i in g.edge_cells(id):
		var i: int = g.index_of(c)
		if i >= 0:
			f = maxf(f, factor[i])
	return f


static func _build_edges(g: GridGeometry, lvl: MapLevel, opts: Options, factor: PackedFloat32Array, geo: Geo) -> void:
	var cm: float = opts.cell_m
	var h: float = opts.wall_h
	var th: float = cm * 0.12
	for id: int in lvl.edge_ids():
		var f: float = _edge_factor(g, factor, id)
		if f <= 0.0:
			continue
		var v: int = lvl.get_edge_by_id(id)
		var ce: Vector3i = g.edge_from_id(id)
		var seg: PackedVector2Array = g.edge_segment(Vector2i(ce.x, ce.y), ce.z, cm)
		var k: int = MapEdge.kind_of(v)
		var secret: bool = k == MapEdge.KIND_SECRET_DOOR
		if k == MapEdge.KIND_WINDOW:
			# Muro con hueco a media altura: alféizar, dintel, jambas y un
			# cristal fino (se ve a través: no tapa la visión del modelo).
			var wa: Vector2 = seg[0].lerp(seg[1], 0.2)
			var wb: Vector2 = seg[0].lerp(seg[1], 0.8)
			box_along(geo, seg[0], wa, th, 0.0, h, COL_EDGE_WALL * f)
			box_along(geo, wb, seg[1], th, 0.0, h, COL_EDGE_WALL * f)
			box_along(geo, wa, wb, th, 0.0, opts.window_sill_h, COL_EDGE_WALL * f)
			box_along(geo, wa, wb, th, opts.window_top_h, h, COL_EDGE_WALL * f)
			box_along(geo, wa, wb, th * 0.15, opts.window_sill_h, opts.window_top_h, COL_WINDOW * f)
			continue
		if k == MapEdge.KIND_WALL or (secret and not opts.dm_view and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED)):
			box_along(geo, seg[0], seg[1], th, 0.0, h, COL_EDGE_WALL * f)
			continue
		var a: Vector2 = seg[0].lerp(seg[1], 0.15 if k != MapEdge.KIND_ARCH else 0.2)
		var b: Vector2 = seg[0].lerp(seg[1], 0.85 if k != MapEdge.KIND_ARCH else 0.8)
		box_along(geo, seg[0], a, th, 0.0, h, COL_EDGE_WALL * f)
		box_along(geo, b, seg[1], th, 0.0, h, COL_EDGE_WALL * f)
		box_along(geo, a, b, th, opts.door_h, h, COL_EDGE_WALL * f)
		if k == MapEdge.KIND_ARCH:
			continue
		var col: Color = (COL_SECRET if secret else COL_DOOR) * f
		if MapEdge.has_flag(v, MapEdge.FLAG_OPEN):
			# Hoja girada 90° sobre la bisagra `a`, hacia la casilla dueña.
			var along: Vector2 = b - a
			var owner_c: Vector2 = g.cell_to_pixel(Vector2i(ce.x, ce.y), cm)
			var perp: Vector2 = Vector2(-along.y, along.x)
			if perp.dot(owner_c - a) < 0.0:
				perp = -perp
			box_along(geo, a, a + perp, th * 0.6, 0.0, opts.door_h * 0.98, col)
		else:
			box_along(geo, a, b, th * 0.6, 0.0, opts.door_h * 0.98, col)
			if MapEdge.has_flag(v, MapEdge.FLAG_LOCKED):
				var mid: Vector2 = (a + b) * 0.5
				box(geo, mid, Vector2(cm * 0.05, th * 0.7), 1.0, 1.15, COL_LOCK * f)


static func _build_objects(g: GridGeometry, lvl: MapLevel, opts: Options, factor: PackedFloat32Array, geo: Geo) -> void:
	var cm: float = opts.cell_m
	for o: MapObject in lvl.objects:
		var cells: Array[Vector2i] = lvl.object_cells(o)
		var f: float = 0.0
		var lo: Vector2 = Vector2(INF, INF)
		var hi: Vector2 = Vector2(-INF, -INF)
		for c: Vector2i in cells:
			var i: int = g.index_of(c)
			if i >= 0:
				f = maxf(f, factor[i])
			var p: Vector2 = g.cell_to_pixel(c, cm)
			lo = lo.min(p)
			hi = hi.max(p)
		if f <= 0.0 or cells.is_empty():
			continue
		var center: Vector2 = (lo + hi) * 0.5
		# Modelo del objeto (ADR 041); sin modelo, la caja de siempre.
		var models: ObjectModels = ObjectModels.load_default()
		if models.has(o.catalog_id):
			var turn: float = -float(o.facing) * TAU / float(g.edge_direction_count())
			var place: Transform3D = Transform3D(Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(cm, 1.0, cm)), v3(center, 0.0))
			for s: LookCatalog.Shape in models.shapes(o.catalog_id):
				var light: bool = s.mat == "flame"
				append_shape(geo, s, place, models.color_of(s.mat) * (maxf(f, 0.8) if light else f), light)
			continue
		var half: Vector2 = (hi - lo) * 0.5 + Vector2(cm, cm) * 0.36
		var top: float = maxf(0.12, float(o.height_mm) / 1000.0)
		var col: Color = COL_OBJ_BLOCK if o.blocks_movement else COL_OBJ_FREE
		box(geo, center, half, 0.0, top, col * f)
		if o.light_bright_cells > 0 or o.light_dim_cells > 0:
			box(geo, center, half * 0.4, top, top + 0.25, COL_OBJ_LIGHT * maxf(f, 0.8))


## Dirección de la luz horneada en los modelos (la misma que en las figuras).
const MODEL_LIGHT: Vector3 = Vector3(-0.45, 0.8, 0.4)
static var _prim_cache: Dictionary[String, Array] = {}


## Añade una primitiva (LookCatalog.Shape) a `geo` con la transformación
## `place` y su color, con luz horneada por la normal (sin luz si `emissive`:
## llamas y brasas).
static func append_shape(geo: Geo, s: LookCatalog.Shape, place: Transform3D, col: Color, emissive: bool = false) -> void:
	var key: String = "%s:%s" % [s.shape, s.taper]
	if not _prim_cache.has(key):
		_prim_cache[key] = CharacterModelBuilder.primitive(s).get_mesh_arrays()
	var arrays: Array = _prim_cache[key]
	var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rot: Basis = Basis.from_euler(Vector3(deg_to_rad(s.rot.x), deg_to_rad(s.rot.y), deg_to_rad(s.rot.z)))
	var xf: Transform3D = place * Transform3D(rot * Basis.from_scale(s.size), s.pos)
	var nb: Basis = xf.basis.inverse().transposed()
	var light: Vector3 = MODEL_LIGHT.normalized()
	for k: int in pi.size():
		var vi: int = pi[k]
		var n: Vector3 = (nb * pn[vi]).normalized()
		geo.verts.append(xf * pv[vi])
		geo.normals.append(n)
		var lit: float = 1.0 if emissive else 0.55 + 0.45 * maxf(0.0, n.dot(light))
		geo.colors.append(Color(col.r * lit, col.g * lit, col.b * lit, col.a))


static func _build_features(g: GridGeometry, lvl: MapLevel, level_index: int, opts: Options,
		factor: PackedFloat32Array, geo: Geo) -> void:
	var cm: float = opts.cell_m
	for s: MapStair in lvl.stairs:
		var i: int = g.index_of(s.cell)
		var f: float = factor[i] if i >= 0 else 0.0
		if f <= 0.0:
			continue
		var p: Vector2 = g.cell_to_pixel(s.cell, cm)
		var up: bool = s.to_level < level_index
		var half: float = cm * 0.36
		for k: int in 4:
			# Peldaños de -z a +z: suben (o bajan, hundidos) hacia +z.
			var z0: float = -half + k * half * 0.5
			var step_c: Vector2 = p + Vector2(0.0, z0 + half * 0.25)
			var hk: float = 0.25 * (k + 1)
			if up:
				box(geo, step_c, Vector2(half, half * 0.25), 0.0, hk, COL_STAIR * f)
			else:
				box(geo, step_c, Vector2(half, half * 0.25), -hk, -hk + 0.05, COL_STAIR * (f * 0.6))
	for t: MapTrap in lvl.traps:
		if t.hidden and not opts.dm_view:
			continue
		var i2: int = g.index_of(t.cell)
		var f2: float = factor[i2] if i2 >= 0 else 0.0
		if f2 <= 0.0:
			continue
		var p2: Vector2 = g.cell_to_pixel(t.cell, cm)
		var r: float = cm * 0.28
		box_along(geo, p2 + Vector2(-r, -r), p2 + Vector2(r, r), cm * 0.07, 0.01, 0.04, COL_TRAP * f2)
		box_along(geo, p2 + Vector2(-r, r), p2 + Vector2(r, -r), cm * 0.07, 0.01, 0.04, COL_TRAP * f2)
