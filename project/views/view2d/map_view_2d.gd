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
## Se abrió o cerró una puerta con el ratón (ya ejecutado el comando).
signal door_toggled(edge_id: int, opened: bool)

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
const COL_TEMPLATE: Color = Color(0.85, 0.42, 0.10, 0.35)
const COL_TEMPLATE_EDGE: Color = Color(0.62, 0.25, 0.05, 0.9)
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
## Color de fondo y de lo no explorado (negro en el proyector, ADR 039).
var background: Color = COL_BG
## Velo de lo explorado que no se ve ahora (0 = nada; en el proyector, poco:
## con miniaturas físicas, lo ya recorrido tiene que leerse bien).
var explored_veil: float = 0.65
var grid_color: Color = COL_GRID
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
## Plantilla de área activa (id del perfil; "" = herramienta apagada). Con
## ella, el botón izquierdo arrastrado marca origen y dirección (ADR 035).
var template_id: String = "":
	set = set_template
## Tamaño de la plantilla (radio, lado o longitud) en pies.
var template_ft: int = 0:
	set = set_template_ft
## Herramienta del editor de estancias (ADR 037); "" = apagado. Formas:
## "terrain:<id de Terrain.IDS>", "edge:<none|wall|door|secret_door|arch|window>",
## "object:<id del catálogo>", "erase_object".
var edit_tool: String = "":
	set = set_edit_tool
## Orientación de los objetos que se colocan (0-3, como MapObject.facing).
var edit_facing: int = 0
var _edit_dragging: bool = false
var _edit_cells: Array[Vector2i] = []
var _edit_edges: PackedInt64Array = PackedInt64Array()
var _hover_edge: int = -1
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _tpl_origin: Vector2i = Vector2i(-1, -1)
var _tpl_toward: Vector2i = Vector2i(-1, -1)
var _tpl_dragging: bool = false
var _tpl_cells: Array[Vector2i] = []
## Zona que se ve en el proyector (esquinas en coordenadas del mapa; vacío =
## sin proyector). Solo en la pantalla del DM (ADR 039).
var projector_area: PackedVector2Array = PackedVector2Array():
	set(v):
		projector_area = v
		queue_redraw()
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
	draw_rect(Rect2(Vector2.ZERO, g.map_pixel_size(cell_px)), background)
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
		var fill: Color = TERRAIN_COLORS[t] if t >= 0 and t < TERRAIN_COLORS.size() else background
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
			_draw_outline(poly, grid_color, -1.0)
	_draw_outlines(g, lvl)
	_draw_edges(g, lvl)
	_draw_features(g, lvl)
	_draw_objects(g, lvl)
	_draw_children(g, lvl)
	if fog:
		_draw_fog(g)
	_draw_template(g)
	_draw_edit(g)
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
			a = explored_veil
		else:
			a = 1.0
		var c: Vector2i = g.cell_at(i)
		var poly: PackedVector2Array = g.cell_polygon(c, cell_px)
		if a >= 1.0:
			# Algo mayor que la casilla, para tapar también los contornos.
			var center: Vector2 = g.cell_to_pixel(c, cell_px)
			for k: int in poly.size():
				poly[k] = center.lerp(poly[k], 1.12)
			draw_colored_polygon(poly, background)
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
	if projector_area.size() == 4:
		var closed: PackedVector2Array = projector_area.duplicate()
		closed.append(projector_area[0])
		draw_polyline(closed, Color(0.37, 0.71, 0.84, 0.9), maxf(2.0, cell_px * 0.06))
		_draw_label(font, projector_area[0] + Vector2(cell_px * 0.2, cell_px * 0.5), tr("UI_PROJ_AREA"), Color("1d4f7c"))
	if _drag_token >= 0 and _drag_route != null and _drag_route.found:
		var t: MapToken = document.token(_drag_token)
		var budget: int = document.turns.remaining_ft(t, profile) if t != null else 0
		var too_far: bool = t != null and t.speed_ft(profile) > 0 and _drag_route.cost_ft > budget
		var col: Color = COL_PATH_FAR if too_far else COL_PATH_OK
		var pts: PackedVector2Array = PackedVector2Array()
		for c: Vector2i in _drag_route.cells:
			pts.append(g.cell_to_pixel(c, cell_px))
		if pts.size() >= 2:
			draw_polyline(pts, col, cell_px * 0.08)
		draw_circle(pts[pts.size() - 1], cell_px * 0.15, col)
		var text: String = _format_ft(_drag_route.cost_ft)
		if t != null and t.id == document.turns.current_token_id() and t.speed_ft(profile) > 0:
			text += "  " + tr("UI_SPEED_LEFT").replace("{left}", _format_ft(maxi(0, budget - _drag_route.cost_ft)))
		if t != null and too_far:
			text += "  " + tr("UI_OVER_SPEED_BLOCKED" if document.turns.block_over_speed else "UI_OVER_SPEED")
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
			if not edit_tool.is_empty():
				_edit_button(mb.pressed, cell)
				get_viewport().set_input_as_handled()
				return
			if not template_id.is_empty():
				_template_button(mb.pressed, cell)
				get_viewport().set_input_as_handled()
				return
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
	if not edit_tool.is_empty():
		_edit_motion(cell)
		return
	if _tpl_dragging:
		if document.grid.in_bounds(cell) and cell != _tpl_toward:
			_tpl_toward = cell
			_update_template()
		return
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
		_toggle_door(on_door)
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
		_toggle_door(edge)


func _toggle_door(edge: int) -> void:
	if not command_stack.execute(SetEdgeCommand.toggle_flag(document, level_index, edge, MapEdge.FLAG_OPEN)):
		return
	# Antes que user_command_done: quien revela la sala de detrás lo une al
	# mismo paso de deshacer que la puerta (modo proyectado, ADR 039).
	door_toggled.emit(edge, MapEdge.has_flag(document.level(level_index).get_edge_by_id(edge), MapEdge.FLAG_OPEN))
	user_command_done.emit()


func _on_left_release(_cell: Vector2i) -> void:
	if _drag_token < 0:
		return
	if _drag_route != null and _drag_route.found and command_stack != null:
		var cost: int = _drag_route.cost_ft
		var mt: MapToken = document.token(_drag_token)
		if mt != null and document.turns.blocks_move(mt, profile, cost):
			status_changed.emit(tr("UI_OVER_SPEED_STATUS"))
		elif command_stack.execute(MoveTokenCommand.new(_drag_token, _drag_target, level_index, cost)):
			status_changed.emit(tr("UI_MOVED").replace("{cost}", _format_ft(cost)))
			user_command_done.emit()
	elif (_drag_route == null or not _drag_route.found) and _drag_target.x >= 0:
		var t: MapToken = document.token(_drag_token)
		if t != null and _drag_target != t.cell:
			# Sin esto la barra seguía mostrando el mensaje anterior.
			status_changed.emit(tr("UI_NO_ROUTE_STATUS"))
	_cancel_drag()


# --- Editor de estancias (ADR 037) --------------------------------------------

const EDGE_TOOL_KINDS: Dictionary[String, int] = {
	"none": 0, "wall": MapEdge.KIND_WALL, "door": MapEdge.KIND_DOOR,
	"secret_door": MapEdge.KIND_SECRET_DOOR, "arch": MapEdge.KIND_ARCH, "window": MapEdge.KIND_WINDOW,
}
## Distancia máxima (en casillas) del puntero a una arista para tomarla.
const EDGE_PICK_FRAC: float = 0.3


func set_edit_tool(tool: String) -> void:
	edit_tool = tool
	_edit_dragging = false
	_edit_cells.clear()
	_edit_edges.clear()
	_hover_edge = -1
	if not tool.is_empty():
		_cancel_drag()
	queue_redraw()


func _tool_kind() -> String:
	return edit_tool.get_slice(":", 0)


func _tool_arg() -> String:
	return edit_tool.get_slice(":", 1) if edit_tool.contains(":") else ""


func _edit_button(pressed: bool, cell: Vector2i) -> void:
	if command_stack == null:
		return
	match _tool_kind():
		"terrain", "edge", "reveal", "conceal":
			if pressed:
				_edit_dragging = true
				_edit_cells.clear()
				_edit_edges.clear()
				_edit_motion(cell)
			else:
				_edit_dragging = false
				_commit_stroke()
		"object":
			if pressed:
				place_object(_tool_arg(), cell, edit_facing)
		"erase_object":
			if pressed:
				erase_object_at(cell)
		"reveal_room":
			if pressed:
				reveal_region(cell)


func _edit_motion(cell: Vector2i) -> void:
	var g: GridGeometry = document.grid
	_hover_cell = cell if g.in_bounds(cell) else Vector2i(-1, -1)
	if _tool_kind() == "edge":
		_hover_edge = _edge_near(_pointer_local)
		if _edit_dragging and _hover_edge >= 0 and not _edit_edges.has(_hover_edge):
			_edit_edges.append(_hover_edge)
	elif (_tool_kind() == "terrain" or _tool_kind() == "reveal" or _tool_kind() == "conceal") \
			and _edit_dragging and g.in_bounds(cell) and not _edit_cells.has(cell):
		_edit_cells.append(cell)
	queue_redraw()


## Aplica la pincelada (terreno o aristas) como un solo paso de deshacer.
func _commit_stroke() -> void:
	var done: bool = false
	if _tool_kind() == "reveal" and not _edit_cells.is_empty():
		done = command_stack.execute(ExploreCommand.new(level_index, PartyVision.VIEWER_PARTY, _edit_cells))
	elif _tool_kind() == "conceal" and not _edit_cells.is_empty():
		done = command_stack.execute(ConcealCommand.new(level_index, PartyVision.VIEWER_PARTY, _edit_cells))
	elif _tool_kind() == "terrain" and not _edit_cells.is_empty():
		var t: int = Terrain.IDS.find(_tool_arg())
		done = t >= 0 and command_stack.execute(SetTerrainCommand.new(level_index, _edit_cells, t))
	elif _tool_kind() == "edge" and not _edit_edges.is_empty() and EDGE_TOOL_KINDS.has(_tool_arg()):
		var kind: int = EDGE_TOOL_KINDS[_tool_arg()]
		var value: int = MapEdge.make(kind) if kind != 0 else 0
		var lvl: MapLevel = document.level(level_index)
		var parts: Array[MapCommand] = []
		for id: int in _edit_edges:
			if lvl.get_edge_by_id(id) != value:
				parts.append(SetEdgeCommand.new(level_index, id, value))
		if parts.size() == 1:
			done = command_stack.execute(parts[0])
		elif parts.size() > 1:
			done = command_stack.execute(CompositeCommand.new(parts))
	_edit_cells.clear()
	_edit_edges.clear()
	if done:
		user_command_done.emit()
	queue_redraw()


## Coloca un objeto del catálogo con su esquina en `cell`. true si cabe (toda
## la huella dentro del mapa y en casillas transitables sin otro objeto que
## bloquee).
func place_object(catalog_id: String, cell: Vector2i, facing: int) -> bool:
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var e: ObjectCatalog.Entry = cat.entry(catalog_id)
	if e == null or command_stack == null or not document.grid.in_bounds(cell):
		return false
	var lvl: MapLevel = document.level(level_index)
	var o: MapObject = cat.instantiate(e, 0, cell, posmod(facing, 4), "")
	var mask: PackedByteArray = lvl.movement_mask()
	for c: Vector2i in lvl.object_cells(o):
		var i: int = document.grid.index_of(c)
		if i < 0 or (mask[i] & MapLevel.MOVE_PASSABLE) == 0:
			status_changed.emit(tr("UI_EDIT_NO_ROOM"))
			return false
	o.id = document.allocate_id()
	if not command_stack.execute(AddObjectCommand.new(level_index, o)):
		return false
	status_changed.emit(tr("UI_EDIT_OBJECT_PLACED").replace("{name}", tr("OBJ_" + catalog_id.to_upper())))
	user_command_done.emit()
	return true


## Revela a los jugadores la zona de `cell` (su sala o lo que se alcanza sin
## cruzar puertas cerradas; FogReveal). true si descubrió algo.
func reveal_region(cell: Vector2i) -> bool:
	if command_stack == null:
		return false
	var cells: Array[Vector2i] = FogReveal.region_cells(document, level_index, cell)
	if cells.is_empty() or not command_stack.execute(ExploreCommand.new(level_index, PartyVision.VIEWER_PARTY, cells)):
		return false
	user_command_done.emit()
	return true


## Quita el objeto de arriba en `cell`. true si había alguno.
func erase_object_at(cell: Vector2i) -> bool:
	if command_stack == null or not document.grid.in_bounds(cell):
		return false
	var objs: Array[MapObject] = document.level(level_index).objects_at(cell)
	if objs.is_empty():
		return false
	if not command_stack.execute(RemoveObjectCommand.new(level_index, objs[objs.size() - 1].id)):
		return false
	user_command_done.emit()
	return true


## Arista (cualquiera, haya o no muro) más cercana al punto, a menos de
## EDGE_PICK_FRAC casillas; -1 si no hay.
func _edge_near(p: Vector2) -> int:
	var g: GridGeometry = document.grid
	var cell: Vector2i = g.pixel_to_cell(p, cell_px)
	if not g.in_bounds(cell):
		return -1
	var best: int = -1
	var best_d: float = cell_px * EDGE_PICK_FRAC
	for dir: int in g.edge_direction_count():
		var seg: PackedVector2Array = g.edge_segment(cell, dir, cell_px)
		if seg.size() < 2:
			continue
		var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]))
		if d < best_d:
			best_d = d
			best = g.edge_id(cell, dir)
	return best


func _draw_edit(g: GridGeometry) -> void:
	if edit_tool.is_empty():
		return
	var col: Color = Color(0.36, 0.71, 0.84, 0.45)
	for c: Vector2i in _edit_cells:
		draw_colored_polygon(g.cell_polygon(c, cell_px), col)
	var edges: PackedInt64Array = _edit_edges.duplicate()
	if _hover_edge >= 0 and not edges.has(_hover_edge):
		edges.append(_hover_edge)
	for id: int in edges:
		var e: Vector3i = g.edge_from_id(id)
		var seg: PackedVector2Array = g.edge_segment(Vector2i(e.x, e.y), e.z, cell_px)
		if seg.size() >= 2:
			draw_line(seg[0], seg[1], Color(0.36, 0.71, 0.84, 0.95), maxf(2.0, cell_px * 0.12))
	if _hover_cell.x >= 0 and _tool_kind() != "edge":
		var poly: PackedVector2Array = g.cell_polygon(_hover_cell, cell_px)
		poly.append(poly[0])
		draw_polyline(poly, Color(0.36, 0.71, 0.84, 0.95), maxf(1.0, cell_px * 0.05))


# --- Plantillas de área (ADR 035) ---------------------------------------------

func set_template(id: String) -> void:
	template_id = id
	if id.is_empty():
		clear_template()
	else:
		_update_template()


func set_template_ft(ft: int) -> void:
	template_ft = maxi(0, ft)
	_update_template()


## Borra la plantilla dibujada (la herramienta sigue como esté).
func clear_template() -> void:
	_tpl_origin = Vector2i(-1, -1)
	_tpl_toward = Vector2i(-1, -1)
	_tpl_dragging = false
	_tpl_cells.clear()
	queue_redraw()


## Casillas que cubre la plantilla dibujada (vacío si no hay).
func template_cells() -> Array[Vector2i]:
	return _tpl_cells.duplicate()


func _template_button(pressed: bool, cell: Vector2i) -> void:
	if pressed:
		if not document.grid.in_bounds(cell):
			return
		_tpl_origin = cell
		_tpl_toward = cell
		_tpl_dragging = true
		_update_template()
	else:
		_tpl_dragging = false
		_update_template()


## Recalcula las casillas cubiertas. En una emanación, el origen es la huella
## de la ficha que haya en la casilla de origen.
func _update_template() -> void:
	_tpl_cells.clear()
	if document == null or profile == null or template_id.is_empty() or _tpl_origin.x < 0:
		queue_redraw()
		return
	var origin_cells: Array[Vector2i] = []
	var t: MapToken = _token_at(_tpl_origin)
	if t != null:
		origin_cells = _token_cells(t)
	_tpl_cells = AreaTemplate.cells(profile, document.grid, template_id, _tpl_origin, _tpl_toward, template_ft, origin_cells, diagonal_variant)
	status_changed.emit(_template_text())
	queue_redraw()


## "Cono de 15 ft: 6 casillas · 2 fichas dentro".
func _template_text() -> String:
	var inside: Dictionary[int, bool] = {}
	for c: Vector2i in _tpl_cells:
		for t: MapToken in document.tokens_at(level_index, c, profile):
			if (not t.hidden or dm_view) and (not fog or _cell_visible(c) or PartyVision.SIDES_IN_PARTY.has(t.side)):
				inside[t.id] = true
	return tr("UI_TEMPLATE_STATUS").replace("{name}", tr("TPL_" + template_id.to_upper())) \
		.replace("{size}", _format_ft(template_ft)).replace("{cells}", str(_tpl_cells.size())) \
		.replace("{tokens}", str(inside.size()))


func _draw_template(g: GridGeometry) -> void:
	if _tpl_cells.is_empty():
		return
	for c: Vector2i in _tpl_cells:
		var poly: PackedVector2Array = g.cell_polygon(c, cell_px)
		draw_colored_polygon(poly, COL_TEMPLATE)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, COL_TEMPLATE_EDGE, maxf(1.0, cell_px * 0.03))
	var o: Vector2 = g.cell_to_pixel(_tpl_origin, cell_px)
	draw_circle(o, cell_px * 0.12, COL_TEMPLATE_EDGE)
	if _tpl_toward != _tpl_origin:
		draw_line(o, g.cell_to_pixel(_tpl_toward, cell_px), COL_TEMPLATE_EDGE, maxf(1.0, cell_px * 0.04))


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
