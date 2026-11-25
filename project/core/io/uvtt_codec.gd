class_name UvttCodec
extends RefCounted
## Intercambio con otras mesas virtuales en **Universal VTT** (`.uvtt` /
## `.dd2vtt`, formato 0.3; PROYECTO §7, ADR 013 y 030).
##
## Formato (JSON): `resolution` {map_origin, map_size en casillas,
## pixels_per_grid}, `line_of_sight` (polilíneas de muro en casillas),
## `portals` (puertas: posición, extremos, giro, cerrada), `lights`
## (posición, alcance en casillas, intensidad, color AARRGGBB, sombras),
## `environment` e `image` (PNG en base64).
##
## No toca nodos: la imagen la renderiza la UI (PngExporter) y se pasa en
## bytes. Coordenadas en "casillas" = píxeles de la vista con cell_px = 1, así
## que en hex también se exportan muros y puertas (en distancia entre
## centros); las otras mesas solo conocen la rejilla cuadrada, por eso la
## importación crea siempre un mapa cuadrado.

const FORMAT: float = 0.3
## Mapa más grande que se importa (en casillas por lado).
const MAX_SIDE: int = 512
## Distancia máxima (en casillas) de un tramo de muro a una línea de la
## rejilla para encajarlo en una arista al importar.
const SNAP: float = 0.2
## Paso de muestreo de los tramos diagonales al importar (en casillas).
const SAMPLE_STEP: float = 0.05
## Un tramo es horizontal/vertical si se desvía menos de esto (fracción de su
## longitud, ≈ 3°).
const AXIS_TOLERANCE: float = 0.05
## Color de las luces exportadas (AARRGGBB, luz cálida de antorcha).
const LIGHT_COLOR: String = "ffffd9a0"
## Objeto del catálogo que se usa como luz al importar (sus propiedades; el
## alcance se toma del fichero).
const IMPORT_LIGHT_OBJECT: String = "torch_sconce"


class ImportResult:
	extends RefCounted
	var doc: MapDocument = null
	## Imagen del mapa (null si no traía o no se pudo leer).
	var image: Image = null
	## Clave i18n del error ("" si fue bien).
	var error: String = ""
	var walls: int = 0
	var doors: int = 0
	var lights: int = 0
	## Longitud (en casillas) de muro diagonal o curvo aproximada en escalera.
	var approximated_length: float = 0.0


# --- Exportar -------------------------------------------------------------------

## Diccionario UVTT del nivel `level_index`. `png` = imagen del mapa ya
## renderizada a `px_per_cell` (vacío = sin imagen). Con `dm_view` false las
## puertas secretas sin descubrir salen como muro (lo que ven los jugadores).
static func export_level(doc: MapDocument, level_index: int, png: PackedByteArray, px_per_cell: int, dm_view: bool = false) -> Dictionary:
	var g: GridGeometry = doc.grid
	var lvl: MapLevel = doc.level(level_index)
	var size: Vector2 = g.map_pixel_size(1.0)
	var wall_segments: Array[PackedVector2Array] = []
	var portals: Array = []
	var seen: Dictionary[int, bool] = {}
	# 1) Aristas con valor (muros finos, puertas, ventanas, vanos).
	for id: int in lvl.edge_ids():
		var v: int = lvl.get_edge_by_id(id)
		var e: Vector3i = g.edge_from_id(id)
		var seg: PackedVector2Array = g.edge_segment(Vector2i(e.x, e.y), e.z, 1.0)
		seen[id] = true
		match MapEdge.kind_of(v):
			MapEdge.KIND_WALL:
				wall_segments.append(seg)
			MapEdge.KIND_DOOR:
				portals.append(_portal(seg, not MapEdge.has_flag(v, MapEdge.FLAG_OPEN)))
			MapEdge.KIND_SECRET_DOOR:
				if dm_view or MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED):
					portals.append(_portal(seg, not MapEdge.has_flag(v, MapEdge.FLAG_OPEN)))
				else:
					wall_segments.append(seg)
			_:
				pass  # Vano: nada. Ventana: no tapa la visión (UVTT no tiene ventanas).
	# 2) Muros por casilla (roca, vacío): el borde entre una casilla no maciza
	# y una maciza. El borde del mapa no es muro (asentamientos al aire libre).
	for i: int in g.cell_count():
		var c: Vector2i = g.cell_at(i)
		if Terrain.is_solid(lvl.get_terrain(c)):
			continue
		for dir: int in g.edge_direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if not g.in_bounds(n) or not Terrain.is_solid(lvl.get_terrain(n)):
				continue
			var id: int = g.edge_id(c, dir)
			if seen.has(id):
				continue
			seen[id] = true
			wall_segments.append(g.edge_segment(c, dir, 1.0))
	# 3) Luces: centro de las casillas del objeto, alcance = radio total.
	var lights: Array = []
	for o: MapObject in lvl.objects:
		var reach: int = maxi(o.light_bright_cells, o.light_dim_cells)
		if reach <= 0:
			continue
		var center: Vector2 = Vector2.ZERO
		var cells: Array[Vector2i] = lvl.object_cells(o)
		for c: Vector2i in cells:
			center += g.cell_to_pixel(c, 1.0)
		center /= float(maxi(1, cells.size()))
		lights.append({"position": _pt(center), "range": float(reach), "intensity": 1.0,
			"color": LIGHT_COLOR, "shadows": true})
	var los: Array = []
	for poly: PackedVector2Array in merge_segments(wall_segments):
		var pts: Array = []
		for p: Vector2 in poly:
			pts.append(_pt(p))
		los.append(pts)
	var d: Dictionary = {
		"format": FORMAT,
		"resolution": {
			"map_origin": {"x": 0.0, "y": 0.0},
			"map_size": {"x": _r(size.x), "y": _r(size.y)},
			"pixels_per_grid": px_per_cell,
		},
		"line_of_sight": los,
		"objects_line_of_sight": [],
		"portals": portals,
		"environment": {"baked_lighting": false, "ambient_light": "ffffffff"},
		"lights": lights,
		"image": Marshalls.raw_to_base64(png) if not png.is_empty() else "",
	}
	return d


static func to_json(d: Dictionary) -> String:
	return JSON.stringify(d, "", true, true)


static func _portal(seg: PackedVector2Array, closed: bool) -> Dictionary:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	return {
		"position": _pt((a + b) * 0.5),
		"bounds": [_pt(a), _pt(b)],
		"rotation": _r((b - a).angle()),
		"closed": closed,
		"freestanding": false,
	}


static func _pt(p: Vector2) -> Dictionary:
	return {"x": _r(p.x), "y": _r(p.y)}


## Redondeo a 1/10000 de casilla: ficheros estables y sin ruido de float.
static func _r(v: float) -> float:
	return roundf(v * 10000.0) / 10000.0


## Une tramos que se tocan y siguen la misma dirección en polilíneas (un muro
## de 10 casillas sale como 1 tramo y no como 10). Determinista: ordena antes.
static func merge_segments(segments: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	# Normaliza cada tramo (extremo menor primero) y lo agrupa por recta.
	var by_line: Dictionary[String, Array] = {}
	for s: PackedVector2Array in segments:
		var a: Vector2 = Vector2(_r(s[0].x), _r(s[0].y))
		var b: Vector2 = Vector2(_r(s[1].x), _r(s[1].y))
		if b < a:
			var t: Vector2 = a
			a = b
			b = t
		var dir: Vector2 = (b - a).normalized()
		# Recta: dirección redondeada + distancia al origen (perpendicular).
		var normal: Vector2 = Vector2(-dir.y, dir.x)
		# (+ 0.0 convierte -0.0 en 0.0: si no, una misma recta daba dos claves.)
		var key: String = "%.3f,%.3f,%.3f" % [snappedf(dir.x, 0.001) + 0.0, snappedf(dir.y, 0.001) + 0.0, snappedf(normal.dot(a), 0.001) + 0.0]
		if not by_line.has(key):
			by_line[key] = []
		by_line[key].append([a, b])
	var keys: PackedStringArray = PackedStringArray()
	for k_v: String in by_line:
		keys.append(k_v)
	keys.sort()
	var out: Array[PackedVector2Array] = []
	for key: String in keys:
		var segs: Array = by_line[key]
		segs.sort_custom(func(x: Array, y: Array) -> bool:
			var xa: Vector2 = x[0]
			var ya: Vector2 = y[0]
			return xa < ya)
		var first: Array = segs[0]
		var cur_a: Vector2 = first[0]
		var cur_b: Vector2 = first[1]
		for k: int in range(1, segs.size()):
			var s: Array = segs[k]
			var sa: Vector2 = s[0]
			var sb: Vector2 = s[1]
			if sa.distance_to(cur_b) < 0.001:
				cur_b = sb
			elif sb > cur_b and sa < cur_b:
				cur_b = sb  # Solapados.
			elif not (sb <= cur_b):
				out.append(PackedVector2Array([cur_a, cur_b]))
				cur_a = sa
				cur_b = sb
		out.append(PackedVector2Array([cur_a, cur_b]))
	return out


# --- Importar -------------------------------------------------------------------

## Lee un fichero UVTT (texto JSON) y crea un mapa cuadrado de una planta:
## todo suelo, muros y puertas en las aristas más cercanas, luces como
## objetos de luz e imagen aparte (la vista la pinta de fondo).
static func import_text(text: String) -> ImportResult:
	var res: ImportResult = ImportResult.new()
	# JSON.new().parse(): parse_string() escribe el error en el registro.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		res.error = "UVTT_ERR_JSON"
		return res
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		res.error = "UVTT_ERR_JSON"
		return res
	var d: Dictionary = parsed
	var reso_v: Variant = d.get("resolution", null)
	if not (reso_v is Dictionary):
		res.error = "UVTT_ERR_RESOLUTION"
		return res
	var reso: Dictionary = reso_v
	var size_v: Variant = reso.get("map_size", null)
	var origin: Vector2 = _read_pt(reso.get("map_origin", null), Vector2.ZERO)
	var size: Vector2 = _read_pt(size_v, Vector2(-1, -1))
	var w: int = roundi(size.x)
	var h: int = roundi(size.y)
	if w < 1 or h < 1 or w > MAX_SIDE or h > MAX_SIDE:
		res.error = "UVTT_ERR_SIZE"
		return res
	var doc: MapDocument = MapDocument.create("square", w, h, 1)
	if doc == null:
		res.error = "UVTT_ERR_SIZE"
		return res
	var lvl: MapLevel = doc.level(0)
	lvl.fill_terrain(Terrain.FLOOR)
	# Muros.
	var los_v: Variant = d.get("line_of_sight", [])
	var polys: Array = los_v if los_v is Array else []
	var extra_v: Variant = d.get("objects_line_of_sight", [])
	if extra_v is Array:
		var extra: Array = extra_v
		polys = polys + extra
	var wall_ids: Dictionary[int, bool] = {}
	for poly_v: Variant in polys:
		if not (poly_v is Array):
			continue
		var poly: Array = poly_v
		for k: int in range(1, poly.size()):
			var a: Vector2 = _read_pt(poly[k - 1], Vector2.INF) - origin
			var b: Vector2 = _read_pt(poly[k], Vector2.INF) - origin
			if a == Vector2.INF or b == Vector2.INF:
				continue
			res.approximated_length += _rasterize(doc.grid, a, b, wall_ids)
	for id: int in wall_ids:
		lvl.set_edge_by_id(id, MapEdge.make(MapEdge.KIND_WALL))
	# Puertas (pisan el muro de su arista).
	var portals_v: Variant = d.get("portals", [])
	var portals: Array = portals_v if portals_v is Array else []
	var door_ids: Dictionary[int, bool] = {}
	for p_v: Variant in portals:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v
		var pos: Vector2 = _read_pt(p.get("position", null), Vector2.INF)
		if pos == Vector2.INF:
			continue
		var id: int = _nearest_edge(doc.grid, pos - origin)
		if id < 0:
			continue
		var closed_v: Variant = p.get("closed", true)
		var closed: bool = closed_v if closed_v is bool else true
		lvl.set_edge_by_id(id, MapEdge.make(MapEdge.KIND_DOOR, 0 if closed else MapEdge.FLAG_OPEN))
		wall_ids.erase(id)
		door_ids[id] = true
	res.walls = wall_ids.size()
	res.doors = door_ids.size()
	# Luces: objeto de luz del catálogo con el alcance del fichero.
	var lights_v: Variant = d.get("lights", [])
	var lights: Array = lights_v if lights_v is Array else []
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var entry: ObjectCatalog.Entry = cat.entry(IMPORT_LIGHT_OBJECT) if cat.error.is_empty() else null
	var used: Dictionary[Vector2i, bool] = {}
	for l_v: Variant in lights:
		if not (l_v is Dictionary) or entry == null:
			continue
		var l: Dictionary = l_v
		var pos: Vector2 = _read_pt(l.get("position", null), Vector2.INF)
		if pos == Vector2.INF:
			continue
		var cell: Vector2i = doc.grid.pixel_to_cell(pos - origin, 1.0)
		if not doc.grid.in_bounds(cell) or used.has(cell):
			continue
		used[cell] = true
		var reach: int = entry.light_dim_cells
		var range_v: Variant = l.get("range", null)
		if range_v is float:
			var rf: float = range_v
			reach = maxi(1, roundi(rf))
		elif range_v is int:
			var ri: int = range_v
			reach = maxi(1, ri)
		var o: MapObject = cat.instantiate(entry, doc.allocate_id(), cell, 0, "")
		# La mitad brillante y el total tenue, como las antorchas del catálogo.
		o.light_dim_cells = reach
		o.light_bright_cells = maxi(1, reach / 2)
		o.blocks_movement = false
		lvl.add_object(o)
		res.lights += 1
	# Imagen.
	var img_v: Variant = d.get("image", "")
	var img_s: String = img_v if img_v is String else ""
	if not img_s.is_empty():
		var bytes: PackedByteArray = Marshalls.base64_to_raw(img_s)
		var img: Image = Image.new()
		var err: Error = img.load_png_from_buffer(bytes)
		if err != OK:
			err = img.load_webp_from_buffer(bytes)
		if err != OK:
			err = img.load_jpg_from_buffer(bytes)
		if err == OK:
			res.image = img
	doc.background_image = res.image
	res.doc = doc
	return res


static func _read_pt(v: Variant, fallback: Vector2) -> Vector2:
	if not (v is Dictionary):
		return fallback
	var d: Dictionary = v
	var x: float = 0.0
	var y: float = 0.0
	var xv: Variant = d.get("x", null)
	var yv: Variant = d.get("y", null)
	if xv is float:
		x = xv
	elif xv is int:
		var xi: int = xv
		x = xi
	else:
		return fallback
	if yv is float:
		y = yv
	elif yv is int:
		var yi: int = yv
		y = yi
	else:
		return fallback
	return Vector2(x, y)


## Pasa un tramo de muro a aristas de la rejilla cuadrada. Devuelve la
## longitud que hubo que aproximar (0 si el tramo era horizontal o vertical).
##  - Horizontal o vertical: se encaja en la línea de la rejilla más cercana
##    y marca todas las aristas que recorre.
##  - Diagonal o curvo (Dungeondraft los exporta a trozos): **escalera** con
##    las aristas entre las casillas que atraviesa, para que siga tapando la
##    visión y el paso. (Encajar cada muestra en la línea más cercana dejaba
##    trocitos sueltos donde la diagonal cruzaba la rejilla.)
static func _rasterize(g: GridGeometry, a: Vector2, b: Vector2, out: Dictionary[int, bool]) -> float:
	var d: Vector2 = b - a
	var length: float = d.length()
	if length < 0.0001:
		return 0.0
	if absf(d.y) <= length * AXIS_TOLERANCE:
		var y: float = roundf((a.y + b.y) * 0.5)
		_mark_line(g, Vector2(minf(a.x, b.x), y), Vector2(maxf(a.x, b.x), y), out)
		return 0.0
	if absf(d.x) <= length * AXIS_TOLERANCE:
		var x: float = roundf((a.x + b.x) * 0.5)
		_mark_line(g, Vector2(x, minf(a.y, b.y)), Vector2(x, maxf(a.y, b.y)), out)
		return 0.0
	var steps: int = maxi(1, ceili(length / SAMPLE_STEP))
	var prev: Vector2i = _clamped_cell(g, a)
	for k: int in range(1, steps + 1):
		var cell: Vector2i = _clamped_cell(g, a.lerp(b, float(k) / float(steps)))
		if cell == prev:
			continue
		# Dos pasos ortogonales si cambia en diagonal (por la esquina).
		var mid: Vector2i = Vector2i(cell.x, prev.y)
		_mark_between(g, prev, mid, out)
		_mark_between(g, mid, cell, out)
		prev = cell
	return length


## Marca las aristas de una línea horizontal o vertical de la rejilla (sus
## extremos se redondean a esquinas).
static func _mark_line(g: GridGeometry, a: Vector2, b: Vector2, out: Dictionary[int, bool]) -> void:
	var from: Vector2i = Vector2i(roundi(a.x), roundi(a.y))
	var to: Vector2i = Vector2i(roundi(b.x), roundi(b.y))
	var step: Vector2i = Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var p: Vector2i = from
	while p != to:
		var id: int = _nearest_edge(g, Vector2(p) + Vector2(step) * 0.5)
		if id >= 0:
			out[id] = true
		p += step


## Arista entre dos casillas vecinas ortogonales (nada si son la misma).
static func _mark_between(g: GridGeometry, a: Vector2i, b: Vector2i, out: Dictionary[int, bool]) -> void:
	if a == b:
		return
	var dir: int = g.direction_between(a, b)
	if dir >= 0 and dir < g.edge_direction_count():
		out[g.edge_id(a, dir)] = true


static func _clamped_cell(g: GridGeometry, p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x), 0, g.width - 1), clampi(floori(p.y), 0, g.height - 1))


## Arista de la rejilla cuadrada más cercana al punto (en casillas), o -1 si
## no hay ninguna línea a menos de SNAP o cae fuera del mapa.
static func _nearest_edge(g: GridGeometry, p: Vector2) -> int:
	var dx: float = absf(p.x - roundf(p.x))
	var dy: float = absf(p.y - roundf(p.y))
	if minf(dx, dy) > SNAP:
		return -1
	if dy <= dx:
		# Línea horizontal y = fila: lado N de la casilla de abajo.
		var row: int = roundi(p.y)
		var col: int = floori(p.x)
		if col < 0 or col >= g.width or row < 0 or row > g.height:
			return -1
		if row == g.height:
			return g.edge_id(Vector2i(col, row - 1), 2)  # S de la última fila.
		return g.edge_id(Vector2i(col, row), 0)
	var c: int = roundi(p.x)
	var r: int = floori(p.y)
	if r < 0 or r >= g.height or c < 0 or c > g.width:
		return -1
	if c == g.width:
		return g.edge_id(Vector2i(c - 1, r), 1)  # E de la última columna.
	return g.edge_id(Vector2i(c, r), 3)  # W.
