class_name MapView2D
extends Node2D
## Vista 2D cenital de un MapDocument (PROYECTO.md §7).
##
## Solo lee el modelo: todo cambio pasa por `command_stack` (comandos con
## deshacer). Dibuja terreno, aristas (muros y puertas), salas, objetos,
## escaleras, trampas y fichas, con rejilla cuadrada o hexagonal.
##
## Interacción (si `interactive`):
##   - Arrastrar una ficha con el botón izquierdo: muestra la ruta más barata
##     y su coste según el perfil; al soltar, mueve la ficha (MoveTokenCommand).
##     Si el coste supera la velocidad, avisa pero no bloquea (§10.3).
##   - Clic izquierdo cerca de una puerta: abre/cierra (SetEdgeCommand).
##   - Doble clic en una ficha que está sobre una escalera: la lleva a la
##     casilla y nivel de destino (MoveTokenCommand con otro nivel); en otra
##     casilla, la UI centra la vista en ella (	oken_activated).
##   - Arrastrar con el botón derecho: regla de medir (distancia o banda).
##   - Botón central: desplazar. Rueda: zoom alrededor del puntero.
##
## Las coordenadas en píxeles usan float: es la vista, nunca el modelo.

signal status_changed(text: String)
signal token_selected(token_id: int)
## Tras ejecutar un comando del usuario (mover, abrir puerta): la UI explora.
signal user_command_done
## Doble clic izquierdo en una casilla sin ficha (la UI entra en el edificio
## que haya ahí, F3).
signal cell_activated(cell: Vector2i)
## Una ficha tomó una escalera hacia otro nivel (la UI muestra ese nivel).
signal stairs_taken(token_id: int, level: int)
## Doble clic en una ficha que no está en una escalera (la UI centra en ella).
signal token_activated(token_id: int)

const ZOOM_MIN: float = 0.2
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 1.15
## Distancia máxima (en casillas) de un clic a una puerta para abrirla o
## cerrarla; más cerca aún, la puerta gana a la ficha de esa casilla.
const DOOR_HIT_FRAC: float = 0.25
const DOOR_OVER_TOKEN_FRAC: float = 0.12

const COL_BG: Color = Color("2b1d14")
const COL_GRID: Color = Color(0.35, 0.25, 0.15, 0.35)
const COL_WALL_EDGE: Color = Color("3a2a1e")
const COL_OUTLINE: Color = Color("120b07")
const COL_DOOR: Color = Color("8a5f1f")
const COL_DOOR_OPEN: Color = Color("f7dc8e")
const COL_SECRET: Color = Color("5fb4d6")
## Cristal de las ventanas (F3).
const COL_WINDOW: Color = Color("a8d4e6")
## Tejado de los edificios de un asentamiento (ALD, F3).
const COL_ROOF: Color = Color("b9785a")
const COL_PATH_OK: Color = Color(0.11, 0.31, 0.49, 0.9)
const COL_PATH_FAR: Color = Color(0.70, 0.15, 0.10, 0.9)
const COL_RULER: Color = Color(0.55, 0.37, 0.12, 0.95)
const COL_PING: Color = Color("5fb4d6")
const COL_PING_TEXT: Color = Color("1d4f7c")
## Duración de una señal en pantalla.
const PING_MS: int = 2500
const TERRAIN_COLORS: Array[Color] = [
	Color("2b1d14"),  # void
	Color("fbf0d2"),  # floor
	Color("5a4030"),  # wall (roca)
	Color("c9a46a"),  # rubble
	Color("8fcde3"),  # water_shallow
	Color("1d4f7c"),  # water_deep
	Color("140e0a"),  # pit
]
const SIDE_COLORS: Dictionary[String, Color] = {
	"player": Color("1d4f7c"),
	"ally": Color("2e7d4f"),
	"neutral": Color("6b6b6b"),
	"enemy": Color("a3261b"),
}
## Marca por bando además del color (accesibilidad, §14).
const SIDE_MARKS: Dictionary[String, String] = {
	"player": "●", "ally": "◆", "neutral": "■", "enemy": "▲",
}

var document: MapDocument = null:
	set = set_document
var command_stack: CommandStack = null
var profile: SystemProfile = null
var level_index: int = 0
## Distancia en píxeles entre centros de casilla (a zoom 1).
var cell_px: float = 48.0
var show_grid: bool = true
## Vista del DM: muestra puertas secretas y trampas ocultas.
var dm_view: bool = true
var interactive: bool = true
var unit_system: Units.System = Units.System.METRIC
var unit_mode: Units.Mode = Units.Mode.CONVENTION
var diagonal_variant: String = ""

## Niebla (vista de jugadores): con `fog`, lo no explorado se tapa, lo
## explorado y no visible se oscurece y las fichas ajenas fuera de la vista
## se ocultan. Los mapas vienen de PartyVision y del nivel (los mismos que
## usa la vista 3D).
var fog: bool = false
var fog_visible: PackedByteArray = PackedByteArray()
var fog_explored: PackedByteArray = PackedByteArray()

var _drag_token: int = -1
## Retratos de las fichas con personaje: id de ficha → textura, y el hash
## del PNG con el que se hizo (para rehacerla si cambia).
var _portraits: Dictionary[int, Texture2D] = {}
var _portrait_keys: Dictionary[int, int] = {}
var _drag_route: MovementCost.Route = null
var _drag_target: Vector2i = Vector2i(-1, -1)
var _ruler_from: Vector2i = Vector2i(-1, -1)
var _ruler_to: Vector2i = Vector2i(-1, -1)
var _panning: bool = false
var _bg_source: Image = null
var _bg_texture: ImageTexture = null
## Fichas en el dibujo (PngExporter las quita para exportar a otra mesa).
var show_tokens: bool = true
## Señales activas: {level, cell, who, start (ms)}.
var _pings: Array[Dictionary] = []
## Posición del puntero del último evento, local a la vista y global (canvas).
var _pointer_local: Vector2 = Vector2.ZERO
var _pointer_global: Vector2 = Vector2.ZERO


func set_document(doc: MapDocument) -> void:
	if document != null and document.changed.is_connected(_on_doc_changed):
		document.changed.disconnect(_on_doc_changed)
	document = doc
	level_index = 0
	_cancel_drag()
	if document != null:
		document.changed.connect(_on_doc_changed)
	queue_redraw()


func _on_doc_changed(_level: int, _layer: String) -> void:
	queue_redraw()


## Centra el mapa en un rectángulo de pantalla (coordenadas del padre).
func fit_to(rect: Rect2) -> void:
	if document == null:
		return
	var size: Vector2 = document.grid.map_pixel_size(cell_px)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var z: float = clampf(minf(rect.size.x / size.x, rect.size.y / size.y) * 0.95, ZOOM_MIN, ZOOM_MAX)
	scale = Vector2(z, z)
	position = rect.position + (rect.size - size * z) * 0.5


## Centra en la pantalla las casillas `cells` (p. ej. lo explorado por un
## jugador en red) con un margen de una casilla.
func fit_region(cells: Rect2i, rect: Rect2) -> void:
	if document == null or cells.size.x <= 0 or cells.size.y <= 0:
		return
	var g: GridGeometry = document.grid
	var a: Vector2 = g.cell_to_pixel(cells.position, cell_px) - Vector2(cell_px, cell_px) * 1.5
	var b: Vector2 = g.cell_to_pixel(cells.end - Vector2i.ONE, cell_px) + Vector2(cell_px, cell_px) * 1.5
	var size: Vector2 = b - a
	var z: float = clampf(minf(rect.size.x / size.x, rect.size.y / size.y), ZOOM_MIN, ZOOM_MAX)
	scale = Vector2(z, z)
	position = rect.position + rect.size * 0.5 - (a + size * 0.5) * z


# --- Dibujo -------------------------------------------------------------------

func _draw() -> void:
	if document == null or level_index >= document.level_count():
		return
	var g: GridGeometry = document.grid
	var lvl: MapLevel = document.level(level_index)
	draw_rect(Rect2(Vector2.ZERO, g.map_pixel_size(cell_px)), COL_BG)
	# Mapa importado (UVTT): su imagen de fondo sustituye al color del suelo.
	var bg: Texture2D = _background_texture() if level_index == 0 else null
	if bg != null:
		draw_texture_rect(bg, Rect2(Vector2.ZERO, g.map_pixel_size(cell_px)), false)
	var outdoor: PackedByteArray = MapMeshBuilder.outdoor_mask(lvl)
	var zone_cols: Dictionary[int, Color] = MapMeshBuilder.zone_colors_by_room(lvl)
	# En 2D la huella de los edificios de un asentamiento se pinta como tejado.
	for r: MapRoom in lvl.rooms:
		if r.kind == MapRoom.KIND_BUILDING:
			zone_cols[r.id] = COL_ROOF
	for i: int in g.cell_count():
		var c: Vector2i = g.cell_at(i)
		var t: int = lvl.get_terrain(c)
		var poly: PackedVector2Array = g.cell_polygon(c, cell_px)
		var fill: Color = TERRAIN_COLORS[t] if t >= 0 and t < TERRAIN_COLORS.size() else COL_BG
		if outdoor[i] != 0 and t == Terrain.FLOOR:
			fill = MapMeshBuilder.COL_OUTDOOR
		if t == Terrain.FLOOR and zone_cols.has(lvl.room_ids[i]):
			fill = zone_cols[lvl.room_ids[i]]
		if bg == null or t != Terrain.FLOOR:
			draw_colored_polygon(poly, fill)
		if show_grid and Terrain.is_passable(t):
			# Ancho negativo = línea fina de 1 px de pantalla a cualquier zoom;
			# con 1.0 en coordenadas locales, al alejar quedaba < 1 px y las
			# líneas verticales u horizontales desaparecían según el redondeo.
			_draw_outline(poly, COL_GRID, -1.0)
	_draw_outlines(g, lvl)
	_draw_edges(g, lvl)
	_draw_features(g, lvl)
	_draw_objects(g, lvl)
	_draw_children(g, lvl)
	if fog:
		_draw_fog(g)
	_draw_overlays(g)
	if show_tokens:
		_draw_tokens(g)
	_draw_pings(g)


## Señala una casilla unos segundos (partida en red, F4): anillo que se
## expande con el nombre de quien la señaló.
func show_ping(p_level: int, cell: Vector2i, who: String) -> void:
	_pings.append({"level": p_level, "cell": cell, "who": who, "start": Time.get_ticks_msec()})
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var k: int = 0
	while k < _pings.size():
		var start: int = _pings[k]["start"]
		if now - start > PING_MS:
			_pings.remove_at(k)
		else:
			k += 1
	if _pings.is_empty():
		set_process(false)
	queue_redraw()


func _draw_pings(g: GridGeometry) -> void:
	var font: Font = ThemeDB.fallback_font
	var now: int = Time.get_ticks_msec()
	for p: Dictionary in _pings:
		var li: int = p["level"]
		if li != level_index:
			continue
		var cell: Vector2i = p["cell"]
		var start: int = p["start"]
		var who: String = p["who"]
		var f: float = clampf(float(now - start) / float(PING_MS), 0.0, 1.0)
		var center: Vector2 = g.cell_to_pixel(cell, cell_px)
		var col: Color = Color(COL_PING, 1.0 - f)
		for ring: int in 2:
			var r: float = cell_px * (0.3 + 1.2 * fmod(f * 2.0 + ring * 0.5, 1.0))
			draw_arc(center, r, 0.0, TAU, 40, col, maxf(2.0, cell_px * 0.08))
		draw_circle(center, cell_px * 0.12, col)
		if not who.is_empty():
			_draw_label(font, center + Vector2(cell_px * 0.4, -cell_px * 0.4), who, COL_PING_TEXT)


## Textura de MapDocument.background_image (se crea una vez por imagen).
func _background_texture() -> Texture2D:
	var img: Image = document.background_image
	if img == null or img.is_empty():
		return null
	if _bg_source != img:
		_bg_source = img
		_bg_texture = ImageTexture.create_from_image(img)
	return _bg_texture


func set_fog(enabled: bool, visible_map: PackedByteArray, explored: PackedByteArray) -> void:
	fog = enabled
	fog_visible = visible_map
	fog_explored = explored
	queue_redraw()


func _cell_visible(c: Vector2i) -> bool:
	if not fog:
		return true
	var i: int = document.grid.index_of(c)
	return i >= 0 and i < fog_visible.size() and fog_visible[i] != 0


## Velo por casilla, igual que el factor de MapMeshBuilder.fog_factor().
func _draw_fog(g: GridGeometry) -> void:
	for i: int in g.cell_count():
		var vis: int = fog_visible[i] if i < fog_visible.size() else 0
		var a: float = 0.0
		if vis == Visibility.BRIGHT:
			continue
		elif vis == Visibility.DIM:
			a = 0.3
		elif i < fog_explored.size() and fog_explored[i] != 0:
			a = 0.65
		else:
			a = 1.0
		var c: Vector2i = g.cell_at(i)
		var poly: PackedVector2Array = g.cell_polygon(c, cell_px)
		if a >= 1.0:
			# Algo mayor que la casilla, para tapar también los contornos.
			var center: Vector2 = g.cell_to_pixel(c, cell_px)
			for k: int in poly.size():
				poly[k] = center.lerp(poly[k], 1.12)
			draw_colored_polygon(poly, COL_BG)
		else:
			draw_colored_polygon(poly, Color(0.05, 0.03, 0.02, a))


func _draw_outline(poly: PackedVector2Array, col: Color, width: float) -> void:
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, col, width)


## Contorno donde una casilla transitable linda con roca, vacío o el borde
## del mapa (solo visual: los muros del modelo se dibujan en _draw_edges).
func _draw_outlines(g: GridGeometry, lvl: MapLevel) -> void:
	var w: float = maxf(2.0, cell_px * 0.16)
	for i: int in g.cell_count():
		var c: Vector2i = g.cell_at(i)
		if not Terrain.is_passable(lvl.get_terrain(c)):
			continue
		for dir: int in g.edge_direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if g.in_bounds(n) and Terrain.is_passable(lvl.get_terrain(n)):
				continue
			var seg: PackedVector2Array = g.edge_segment(c, dir, cell_px)
			if seg.size() >= 2:
				draw_line(seg[0], seg[1], COL_OUTLINE, w)


func _draw_edges(g: GridGeometry, lvl: MapLevel) -> void:
	for id: int in lvl.edge_ids():
		var v: int = lvl.get_edge_by_id(id)
		var ce: Vector3i = g.edge_from_id(id)
		var seg: PackedVector2Array = g.edge_segment(Vector2i(ce.x, ce.y), ce.z, cell_px)
		if seg.size() < 2:
			continue
		var k: int = MapEdge.kind_of(v)
		var w: float = cell_px * 0.12
		match k:
			MapEdge.KIND_WALL:
				draw_line(seg[0], seg[1], COL_WALL_EDGE, w)
			MapEdge.KIND_ARCH:
				draw_line(seg[0], seg[0].lerp(seg[1], 0.2), COL_WALL_EDGE, w)
				draw_line(seg[1], seg[1].lerp(seg[0], 0.2), COL_WALL_EDGE, w)
			MapEdge.KIND_DOOR, MapEdge.KIND_SECRET_DOOR:
				_draw_door(seg, v, k == MapEdge.KIND_SECRET_DOOR, w)
			MapEdge.KIND_WINDOW:
				# Muro en los extremos y cristal claro en el centro (bloquea el
				# paso, no la vista).
				var a: Vector2 = seg[0].lerp(seg[1], 0.2)
				var b: Vector2 = seg[0].lerp(seg[1], 0.8)
				draw_line(seg[0], a, COL_WALL_EDGE, w)
				draw_line(b, seg[1], COL_WALL_EDGE, w)
				draw_line(a, b, COL_WALL_EDGE, w * 0.9)
				draw_line(a, b, COL_WINDOW, w * 0.45)


func _draw_door(seg: PackedVector2Array, v: int, secret: bool, w: float) -> void:
	var discovered: bool = MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED)
	if secret and not discovered and not dm_view:
		draw_line(seg[0], seg[1], COL_WALL_EDGE, w)
		return
	var a: Vector2 = seg[0].lerp(seg[1], 0.15)
	var b: Vector2 = seg[0].lerp(seg[1], 0.85)
	draw_line(seg[0], a, COL_WALL_EDGE, w)
	draw_line(b, seg[1], COL_WALL_EDGE, w)
	var open: bool = MapEdge.has_flag(v, MapEdge.FLAG_OPEN)
	var col: Color = COL_SECRET if secret else (COL_DOOR_OPEN if open else COL_DOOR)
	if open:
		# Hoja girada 90° sobre la bisagra en `a`.
		var dir: Vector2 = (b - a)
		draw_line(a, a + Vector2(-dir.y, dir.x), col, w * 0.6)
	else:
		draw_line(a, b, col, w * 1.6)
	if MapEdge.has_flag(v, MapEdge.FLAG_LOCKED):
		draw_circle((a + b) * 0.5, w * 0.7, COL_WALL_EDGE)


func _draw_features(g: GridGeometry, lvl: MapLevel) -> void:
	for s: MapStair in lvl.stairs:
		var p: Vector2 = g.cell_to_pixel(s.cell, cell_px)
		var r: float = cell_px * 0.35
		# Peldaños a la izquierda y flecha a la derecha. La flecha es un
		# polígono (no un glifo): el "▼" de la fuente quedaba diminuto y
		# pegado a los peldaños, casi invisible.
		for k: int in 4:
			var y: float = -r + k * r * 0.66
			draw_line(p + Vector2(-r, y), p + Vector2(r * 0.15, y), COL_WALL_EDGE, maxf(1.5, cell_px * 0.04))
		var up: bool = s.to_level < level_index
		var ac: Vector2 = p + Vector2(r * 0.6, 0.0)
		var h: float = r * 0.55
		var tip: float = -h if up else h
		var tri: PackedVector2Array = PackedVector2Array([
			ac + Vector2(0.0, tip), ac + Vector2(-h * 0.7, -tip * 0.6), ac + Vector2(h * 0.7, -tip * 0.6)])
		draw_colored_polygon(tri, COL_DOOR)
		_draw_outline(tri, COL_WALL_EDGE, maxf(1.0, cell_px * 0.02))
	for t: MapTrap in lvl.traps:
		if t.hidden and not dm_view:
			continue
		var p2: Vector2 = g.cell_to_pixel(t.cell, cell_px)
		var r2: float = cell_px * 0.25
		var col: Color = Color(0.64, 0.15, 0.10, 0.85 if t.armed else 0.35)
		draw_line(p2 + Vector2(-r2, -r2), p2 + Vector2(r2, r2), col, 3.0)
		draw_line(p2 + Vector2(-r2, r2), p2 + Vector2(r2, -r2), col, 3.0)


func _draw_objects(g: GridGeometry, lvl: MapLevel) -> void:
	var font: Font = ThemeDB.fallback_font
	# Con imagen de fondo (UVTT importado) el dibujo ya está en la imagen: de
	# los objetos (las luces importadas) solo se pinta el círculo de luz.
	var art: bool = level_index == 0 and _background_texture() != null
	for o: MapObject in lvl.objects:
		if art:
			if o.light_bright_cells > 0:
				draw_arc(g.cell_to_pixel(o.cell, cell_px), o.light_bright_cells * cell_px, 0.0, TAU, 48, Color(0.97, 0.86, 0.56, 0.5), 2.0)
			continue
		var cells: Array[Vector2i] = lvl.object_cells(o)
		var col: Color = Color("8a5f1f") if o.blocks_movement else Color("c9a46a")
		for c: Vector2i in cells:
			var poly: PackedVector2Array = g.cell_polygon(c, cell_px)
			var center: Vector2 = g.cell_to_pixel(c, cell_px)
			var inner: PackedVector2Array = PackedVector2Array()
			for q: Vector2 in poly:
				inner.append(center.lerp(q, 0.7))
			draw_colored_polygon(inner, Color(col, 0.85))
		if o.light_bright_cells > 0:
			var lp: Vector2 = g.cell_to_pixel(o.cell, cell_px)
			draw_arc(lp, o.light_bright_cells * cell_px, 0.0, TAU, 48, Color(0.97, 0.86, 0.56, 0.5), 2.0)
		var label: String = tr("OBJ_" + o.catalog_id.to_upper())
		if label.begins_with("OBJ_"):
			label = o.catalog_id
		_draw_object_label(font, g, cells, label)


## Nombre completo centrado sobre la huella del objeto: se reduce la letra
## hasta que cabe y, si aun así no cabe, se parte en dos líneas. Antes se
## cortaba a 10 caracteres y al ancho de una casilla ("Mesa re", "Chimene").
func _draw_object_label(font: Font, g: GridGeometry, cells: Array[Vector2i], label: String) -> void:
	if cells.is_empty():
		return
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var center: Vector2 = Vector2.ZERO
	for c: Vector2i in cells:
		var q: Vector2 = g.cell_to_pixel(c, cell_px)
		lo = lo.min(q)
		hi = hi.max(q)
		center += q
	center /= float(cells.size())
	var avail: float = (hi.x - lo.x) + cell_px * 0.95
	var fs: int = int(cell_px * 0.22)
	var fs_min: int = maxi(6, int(cell_px * 0.15))
	while fs > fs_min and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	var col: Color = Color("2b1d14")
	if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail or not label.contains(" "):
		draw_string(font, center + Vector2(-avail * 0.5, fs * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, avail, fs, col)
		return
	draw_multiline_string(font, center + Vector2(-avail * 0.5, fs * 0.35 - fs * 0.55), label,
		HORIZONTAL_ALIGNMENT_CENTER, avail, fs, 2, col)


## Nombre del tipo de cada mapa hijo (edificios de un asentamiento) centrado
## en su huella, con la letra que quepa en su ancho.
func _draw_children(g: GridGeometry, lvl: MapLevel) -> void:
	if lvl.children.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	for ch: MapChild in lvl.children:
		var a: Vector2 = g.cell_to_pixel(ch.rect.position, cell_px)
		var b: Vector2 = g.cell_to_pixel(ch.rect.end - Vector2i(1, 1), cell_px)
		var center: Vector2 = (a + b) * 0.5
		var avail: float = absf(b.x - a.x) + cell_px * 0.5
		var label: String = tr("BUILDING_" + ch.kind.to_upper())
		var fs: int = int(cell_px * 0.9)
		while fs > 6 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
			fs -= 1
		draw_string_outline(font, center + Vector2(-avail * 0.5, fs * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, avail, fs, maxi(2, fs / 6), Color("fbf0d2"))
		draw_string(font, center + Vector2(-avail * 0.5, fs * 0.35), label,
			HORIZONTAL_ALIGNMENT_CENTER, avail, fs, Color("2b1d14"))


func _draw_tokens(g: GridGeometry) -> void:
	var font: Font = ThemeDB.fallback_font
	for t: MapToken in document.tokens:
		if t.level != level_index or (t.hidden and not dm_view):
			continue
		if fog and not PartyVision.SIDES_IN_PARTY.has(t.side) and not _cell_visible(t.cell):
			continue
		var cells: Array[Vector2i] = _token_cells(t)
		if cells.is_empty():
			continue
		var center: Vector2 = Vector2.ZERO
		for c: Vector2i in cells:
			center += g.cell_to_pixel(c, cell_px)
		center /= float(cells.size())
		var radius: float = cell_px * (0.42 if cells.size() == 1 else 0.42 * sqrt(float(cells.size())))
		var col: Color = SIDE_COLORS.get(t.side, SIDE_COLORS["neutral"])
		if t.id == _drag_token:
			col = Color(col, 0.5)
		if t.sheet != null:
			_draw_character_token(t, center, radius, col)
			continue
		draw_circle(center, radius, col)
		draw_arc(center, radius, 0.0, TAU, 32, Color("f7dc8e"), 2.0)
		var mark: String = SIDE_MARKS.get(t.side, "")
		var initial: String = t.name.substr(0, 2) if not t.name.is_empty() else mark
		var fs: int = int(radius * 0.8)
		draw_string(font, center + Vector2(-radius, fs * 0.35), initial,
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, Color.WHITE)


## Ficha con personaje (ADR 034): retrato recortado en círculo o, sin
## retrato, silueta de su complexión con los colores de su aspecto; aro del
## color del bando.
func _draw_character_token(t: MapToken, center: Vector2, radius: float, side_col: Color) -> void:
	TokenPainter.draw(self, t.sheet, center, radius, side_col, _portrait_texture(t))


## Textura del retrato de la ficha (en caché mientras no cambie).
func _portrait_texture(t: MapToken) -> Texture2D:
	if t.sheet == null or t.sheet.portrait_png.is_empty():
		_portraits.erase(t.id)
		return null
	var key: int = hash(t.sheet.portrait_png)
	if _portraits.has(t.id) and _portrait_keys.get(t.id, 0) == key:
		return _portraits[t.id]
	var img: Image = t.sheet.portrait_image()
	if img == null:
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_portraits[t.id] = tex
	_portrait_keys[t.id] = key
	return tex


func _draw_overlays(g: GridGeometry) -> void:
	var font: Font = ThemeDB.fallback_font
	if _drag_token >= 0 and _drag_route != null and _drag_route.found:
		var t: MapToken = document.token(_drag_token)
		var speed: int = t.speed_ft(profile) if t != null else 0
		var too_far: bool = speed > 0 and _drag_route.cost_ft > speed
		var col: Color = COL_PATH_FAR if too_far else COL_PATH_OK
		var pts: PackedVector2Array = PackedVector2Array()
		for c: Vector2i in _drag_route.cells:
			pts.append(g.cell_to_pixel(c, cell_px))
		if pts.size() >= 2:
			draw_polyline(pts, col, cell_px * 0.08)
		draw_circle(pts[pts.size() - 1], cell_px * 0.15, col)
		var text: String = _format_ft(_drag_route.cost_ft)
		if t != null and too_far:
			text += "  " + tr("UI_OVER_SPEED")
		_draw_label(font, pts[pts.size() - 1] + Vector2(cell_px * 0.3, -cell_px * 0.3), text, col)
	elif _drag_token >= 0 and _drag_target.x >= 0:
		var p: Vector2 = g.cell_to_pixel(_drag_target, cell_px)
		_draw_label(font, p, tr("UI_NO_ROUTE"), COL_PATH_FAR)
	if _ruler_from.x >= 0 and _ruler_to.x >= 0 and profile != null:
		var a: Vector2 = g.cell_to_pixel(_ruler_from, cell_px)
		var b: Vector2 = g.cell_to_pixel(_ruler_to, cell_px)
		draw_line(a, b, COL_RULER, cell_px * 0.06)
		draw_circle(a, cell_px * 0.1, COL_RULER)
		draw_circle(b, cell_px * 0.1, COL_RULER)
		_draw_label(font, b + Vector2(cell_px * 0.3, -cell_px * 0.3), _ruler_text(), COL_RULER)


func _draw_label(font: Font, at: Vector2, text: String, col: Color) -> void:
	var fs: int = int(cell_px * 0.32)
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_rect(Rect2(at + Vector2(-4, -size.y), size + Vector2(8, 6)), Color(0.98, 0.94, 0.82, 0.92))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _ruler_text() -> String:
	var ft: int = MovementCost.measure_ft(profile, document.grid, _ruler_from, _ruler_to, diagonal_variant)
	if profile.measure == "bands":
		var band: String = MovementCost.band_for_ft(profile, ft)
		return tr("BAND_" + band.to_upper()) + "  (" + _format_ft(ft) + ")"
	return _format_ft(ft)


func _format_ft(ft: int) -> String:
	return Units.format_distance(Units.ft_to_mm(ft, unit_mode), unit_system, unit_mode)


func _token_cells(t: MapToken) -> Array[Vector2i]:
	if profile != null:
		return document.token_cells(t, profile)
	var one: Array[Vector2i] = [t.cell]
	return one


# --- Interacción --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	process_input(event, false)


## Punto de entrada del ratón. Lo llama `_unhandled_input` cuando la vista
## va suelta, y el Control que la contiene (vía `gui_input`) cuando está
## dentro de una interfaz: un Control con mouse_filter STOP bajo el puntero
## consume el evento y nunca llegaría a `_unhandled_input`.
##
## `from_parent_gui`: la posición del evento es local al Control padre (como
## en gui_input); si no, está en coordenadas del viewport. La casilla sale de
## la posición del evento y no de get_local_mouse_position(), que lee el
## ratón del sistema: con eventos inyectados (pruebas, guiones) o táctiles
## apuntaba a otro sitio y el doble clic no encontraba el edificio.
func process_input(event: InputEvent, from_parent_gui: bool = true) -> void:
	if not interactive or document == null:
		return
	var me: InputEventMouse = event as InputEventMouse
	if me != null:
		var parent_ctrl: Control = get_parent() as Control
		if from_parent_gui and parent_ctrl != null:
			_pointer_global = parent_ctrl.get_global_transform() * me.position
		else:
			_pointer_global = get_viewport().get_canvas_transform().affine_inverse() * me.position
		_pointer_local = get_global_transform().affine_inverse() * _pointer_global
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		_handle_button(mb)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		_handle_motion(mm)


func _handle_button(mb: InputEventMouseButton) -> void:
	var cell: Vector2i = document.grid.pixel_to_cell(_pointer_local, cell_px)
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				# Windows agrupa varios pasos de rueda en un solo evento con
				# factor > 1, y los paneles táctiles envían factor < 1.
				var steps: float = mb.factor if mb.factor > 0.0 else 1.0
				var f: float = pow(ZOOM_STEP, steps)
				_zoom_at(_pointer_global, f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / f)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_ruler_from = cell if document.grid.in_bounds(cell) else Vector2i(-1, -1)
				_ruler_to = _ruler_from
			else:
				_ruler_from = Vector2i(-1, -1)
				_ruler_to = Vector2i(-1, -1)
			queue_redraw()
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click and _token_at(cell) == null:
				if document.grid.in_bounds(cell):
					cell_activated.emit(cell)
			elif mb.pressed and mb.double_click:
				var tk: MapToken = _token_at(cell)
				_cancel_drag()
				if not take_stairs(tk):
					token_activated.emit(tk.id)
			elif mb.pressed:
				_on_left_press(cell)
			else:
				_on_left_release(cell)
			get_viewport().set_input_as_handled()


func _handle_motion(mm: InputEventMouseMotion) -> void:
	if _panning:
		position += mm.relative
		return
	var cell: Vector2i = document.grid.pixel_to_cell(_pointer_local, cell_px)
	if _ruler_from.x >= 0:
		if document.grid.in_bounds(cell) and cell != _ruler_to:
			_ruler_to = cell
			queue_redraw()
		return
	if _drag_token >= 0 and cell != _drag_target:
		_drag_target = cell
		_update_route()
		queue_redraw()


func _on_left_press(cell: Vector2i) -> void:
	# Justo encima de una puerta, la puerta antes que la ficha: en un pasillo
	# de una casilla con fichas a los dos lados no había forma de pulsarla.
	var on_door: int = _door_edge_near(_pointer_local, DOOR_OVER_TOKEN_FRAC)
	if on_door >= 0 and command_stack != null:
		if command_stack.execute(SetEdgeCommand.toggle_flag(document, level_index, on_door, MapEdge.FLAG_OPEN)):
			user_command_done.emit()
		return
	var t: MapToken = _token_at(cell)
	if t != null:
		_drag_token = t.id
		_drag_target = t.cell
		_drag_route = null
		token_selected.emit(t.id)
		queue_redraw()
		return
	var edge: int = _door_edge_near(_pointer_local)
	if edge >= 0 and command_stack != null:
		if command_stack.execute(SetEdgeCommand.toggle_flag(document, level_index, edge, MapEdge.FLAG_OPEN)):
			user_command_done.emit()


func _on_left_release(_cell: Vector2i) -> void:
	if _drag_token < 0:
		return
	if _drag_route != null and _drag_route.found and command_stack != null:
		var cost: int = _drag_route.cost_ft
		if command_stack.execute(MoveTokenCommand.new(_drag_token, _drag_target, level_index)):
			status_changed.emit(tr("UI_MOVED").replace("{cost}", _format_ft(cost)))
			user_command_done.emit()
	elif (_drag_route == null or not _drag_route.found) and _drag_target.x >= 0:
		var t: MapToken = document.token(_drag_token)
		if t != null and _drag_target != t.cell:
			# Sin esto la barra seguía mostrando el mensaje anterior.
			status_changed.emit(tr("UI_NO_ROUTE_STATUS"))
	_cancel_drag()


## Desplaza la vista (sin cambiar el zoom) para que la casilla quede en el
## centro de ect (el área del mapa, en coordenadas del padre).
func center_on_cell(cell: Vector2i, rect: Rect2) -> void:
	if document == null:
		return
	var p: Vector2 = document.grid.cell_to_pixel(cell, cell_px)
	position = rect.position + rect.size * 0.5 - p * scale.x


## Escalera bajo la ficha que lleva a otro nivel de este mapa (las que salen
## del mapa, EST G2, no cuentan); null si no hay.
func stairs_under(t: MapToken) -> MapStair:
	if t == null or document == null:
		return null
	var lvl: MapLevel = document.level(t.level)
	if lvl == null:
		return null
	for s: MapStair in lvl.stairs_at(t.cell):
		if s.to_level >= 0 and s.to_level < document.level_count() and s.to_level != t.level:
			return s
	return null


## Lleva la ficha por la escalera en la que está. false si no hay escalera o
## el comando no se ejecutó.
func take_stairs(t: MapToken) -> bool:
	var s: MapStair = stairs_under(t)
	if s == null or command_stack == null:
		return false
	if not command_stack.execute(MoveTokenCommand.new(t.id, s.to_cell, s.to_level)):
		return false
	status_changed.emit(tr("UI_STAIRS_TAKEN").replace("{name}", t.name).replace("{level}", str(s.to_level + 1)))
	user_command_done.emit()
	stairs_taken.emit(t.id, s.to_level)
	return true


func _cancel_drag() -> void:
	_drag_token = -1
	_drag_route = null
	_drag_target = Vector2i(-1, -1)
	queue_redraw()


func _update_route() -> void:
	_drag_route = null
	var t: MapToken = document.token(_drag_token)
	if t == null or profile == null or not document.grid.in_bounds(_drag_target) or _drag_target == t.cell:
		return
	_drag_route = MovementCost.find_route(profile, document.level(level_index), t.cell, _drag_target, diagonal_variant)


func _token_at(cell: Vector2i) -> MapToken:
	if not document.grid.in_bounds(cell):
		return null
	# La última dibujada (encima) gana.
	for i: int in range(document.tokens.size() - 1, -1, -1):
		var t: MapToken = document.tokens[i]
		if t.level == level_index and (dm_view or not t.hidden) and _token_cells(t).has(cell):
			if fog and not PartyVision.SIDES_IN_PARTY.has(t.side) and not _cell_visible(t.cell):
				continue
			return t
	return null


## Id de la puerta cuya arista está más cerca del punto (en coordenadas
## locales), o -1 si no hay ninguna a menos de un cuarto de casilla.
func _door_edge_near(p: Vector2, max_frac: float = DOOR_HIT_FRAC) -> int:
	var g: GridGeometry = document.grid
	var lvl: MapLevel = document.level(level_index)
	var cell: Vector2i = g.pixel_to_cell(p, cell_px)
	if not g.in_bounds(cell):
		return -1
	var best: int = -1
	var best_d: float = cell_px * max_frac
	for dir: int in g.edge_direction_count():
		var v: int = lvl.get_edge(cell, dir)
		if not MapEdge.is_door(v):
			continue
		if MapEdge.kind_of(v) == MapEdge.KIND_SECRET_DOOR and not dm_view and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED):
			continue
		var seg: PackedVector2Array = g.edge_segment(cell, dir, cell_px)
		if seg.size() < 2:
			continue
		var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]))
		if d < best_d:
			best_d = d
			best = g.edge_id(cell, dir)
	return best


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var old: float = scale.x
	var z: float = clampf(old * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(z, old):
		return
	var local: Vector2 = get_global_transform().affine_inverse() * screen_point
	scale = Vector2(z, z)
	# Mantiene bajo el puntero el mismo punto del mapa.
	position = get_parent_global_mouse(screen_point) - local * z


func get_parent_global_mouse(screen_point: Vector2) -> Vector2:
	var parent: CanvasItem = get_parent() as CanvasItem
	if parent == null:
		return screen_point
	return parent.get_global_transform().affine_inverse() * screen_point
