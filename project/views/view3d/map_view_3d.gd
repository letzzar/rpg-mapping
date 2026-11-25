class_name MapView3D
extends Node3D
## Vista 3D de un MapDocument (PROYECTO §7): cenital y 1ª persona.
##
## Solo lee el modelo; los cambios van por `command_stack` (comandos con
## deshacer), igual que en la vista 2D. La geometría sale de MapMeshBuilder
## y se reconstruye cuando cambia el documento, el nivel o la niebla.
##
## Cenital (MODE_TOP):
##   - Rueda: acercar/alejar. Botón central: desplazar. Botón derecho
##     arrastrando: girar e inclinar (0–60° desde la vertical). Q/E giran,
##     R/F inclinan, O alterna perspectiva/ortográfica.
##   - Clic izquierdo en una ficha: la selecciona (para la 1ª persona);
##     arrastrarla la mueve por la ruta más barata (MoveTokenCommand).
##   - Clic izquierdo en una puerta: abre/cierra.
## 1ª persona (MODE_FIRST_PERSON), en la ficha seleccionada:
##   - Espacio o E: abrir/cerrar la puerta de delante.
##   - W/↑ avanzar una casilla, S/↓ retroceder, A/← y D/→ girar (un lado de
##     la rejilla), botón derecho arrastrando: mirar alrededor.
##   - La altura de los ojos depende del tamaño de la ficha.

signal status_changed(text: String)
## Tras ejecutar un comando del usuario (mover, abrir puerta): la UI explora.
signal user_command_done
signal token_selected(token_id: int)

enum Mode { TOP, FIRST_PERSON }

const TILT_MIN: float = 0.0
const TILT_MAX: float = 60.0
const DIST_MIN: float = 4.0
const DIST_MAX: float = 400.0
const ZOOM_STEP: float = 1.15
const FOV_TOP: float = 40.0
const DEFAULT_FOV_FP: float = 75.0
## Altura de los ojos (m) por tamaño: solo aspecto de la vista.
const EYE_HEIGHT_M: Dictionary[String, float] = {
	"tiny": 0.5, "small": 1.0, "medium": 1.6, "large": 2.4, "huge": 3.6, "gargantuan": 5.0,
}
const SIDE_COLORS: Dictionary[String, Color] = {
	"player": Color("1d4f7c"), "ally": Color("2e7d4f"), "neutral": Color("6b6b6b"), "enemy": Color("a3261b"),
}

var document: MapDocument = null:
	set = set_document
var command_stack: CommandStack = null
var profile: SystemProfile = null
var level_index: int = 0
var mode: Mode = Mode.TOP
var dm_view: bool = true
var fog: bool = false
var fog_visible: PackedByteArray = PackedByteArray()
var fog_explored: PackedByteArray = PackedByteArray()
var fov_first_person: float = DEFAULT_FOV_FP
var selected_token: int = -1
var unit_system: Units.System = Units.System.METRIC
var unit_mode: Units.Mode = Units.Mode.CONVENTION
var diagonal_variant: String = ""
var interactive: bool = true
## Oculta no se reconstruye (se hace al activarla): cambiar de vista solo
## paga una construcción.
var active: bool = true
## Último tiempo de reconstrucción (ms), para comprobar el criterio de F2.
var last_build_ms: int = 0

var cell_m: float = 1.5
var _yaw: float = 0.0
var _tilt: float = 35.0
var _dist: float = 40.0
var _target: Vector3 = Vector3.ZERO
var _fp_yaw: float = 0.0
var _fp_pitch: float = 0.0
var _fp_facing: int = 0
var _ortho: bool = false

var _camera: Camera3D
var _env: WorldEnvironment
var _level_node: Node3D = null
var _tokens_node: Node3D
var _labels_node: Node3D
var _dirty: bool = false
var _panning: bool = false
var _rotating: bool = false
var _drag_token: int = -1
var _drag_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	_camera.near = 0.05
	_camera.far = 2000.0
	add_child(_camera)
	_env = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b1d14")
	_env.environment = e
	add_child(_env)
	_tokens_node = Node3D.new()
	_tokens_node.name = "Tokens"
	add_child(_tokens_node)
	_labels_node = Node3D.new()
	_labels_node.name = "Labels"
	add_child(_labels_node)
	rebuild()


func set_document(doc: MapDocument) -> void:
	if document != null and document.changed.is_connected(_on_doc_changed):
		document.changed.disconnect(_on_doc_changed)
	document = doc
	level_index = 0
	selected_token = -1
	if document != null:
		document.changed.connect(_on_doc_changed)
		if profile != null:
			cell_m = float(Units.ft_to_mm(profile.cell_ft, Units.Mode.CONVENTION)) / 1000.0
		fit()
	mark_dirty()


func _on_doc_changed(_level: int, _layer: String) -> void:
	mark_dirty()


## Pide reconstruir al final del fotograma (varios cambios = una sola vez).
func mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	if _dirty:
		rebuild()


func set_fog(enabled: bool, visible_map: PackedByteArray, explored: PackedByteArray) -> void:
	fog = enabled
	fog_visible = visible_map
	fog_explored = explored
	mark_dirty()


# --- Construcción -------------------------------------------------------------

func rebuild() -> void:
	_dirty = false
	if not is_inside_tree() or not active:
		return
	var t0: int = Time.get_ticks_msec()
	if _level_node != null:
		_level_node.queue_free()
		_level_node = null
	for n: Node in _tokens_node.get_children():
		n.queue_free()
	for n: Node in _labels_node.get_children():
		n.queue_free()
	if document == null or level_index >= document.level_count():
		last_build_ms = Time.get_ticks_msec() - t0
		return
	var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
	opts.cell_m = cell_m
	opts.dm_view = dm_view and not fog
	opts.fog = fog
	opts.visible = fog_visible
	opts.explored = fog_explored
	opts.ceiling = mode == Mode.FIRST_PERSON
	if mode == Mode.FIRST_PERSON:
		MapMeshBuilder.set_distance_fade(cell_m * 1.5, cell_m * 14.0)
	else:
		MapMeshBuilder.set_distance_fade(0.0, 0.0)
	_level_node = MapMeshBuilder.build_level(document, level_index, opts)
	add_child(_level_node)
	_build_tokens()
	if mode == Mode.TOP:
		_build_labels()
	_update_camera()
	last_build_ms = Time.get_ticks_msec() - t0


func _cell_visible(c: Vector2i) -> bool:
	if not fog:
		return true
	var i: int = document.grid.index_of(c)
	return i >= 0 and i < fog_visible.size() and fog_visible[i] != 0


func _build_tokens() -> void:
	var g: GridGeometry = document.grid
	for t: MapToken in document.tokens:
		if t.level != level_index or (t.hidden and not dm_view):
			continue
		var party: bool = PartyVision.SIDES_IN_PARTY.has(t.side)
		if fog and not party and not _cell_visible(t.cell):
			continue
		if mode == Mode.FIRST_PERSON and t.id == selected_token:
			continue
		var cells: Array[Vector2i] = document.token_cells(t, profile) if profile != null else [t.cell]
		var center: Vector2 = Vector2.ZERO
		for c: Vector2i in cells:
			center += g.cell_to_pixel(c, cell_m)
		center /= float(cells.size())
		var radius: float = cell_m * 0.38 * sqrt(float(cells.size()))
		var height: float = _eye_height(t.size_id) * 0.9
		var mi: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = radius * 0.75
		cyl.bottom_radius = radius
		cyl.height = height
		cyl.radial_segments = 20
		cyl.rings = 1
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		var side_col: Color = SIDE_COLORS.get(t.side, SIDE_COLORS["neutral"])
		mat.albedo_color = side_col
		if t.id == selected_token or t.id == _drag_token:
			mat.albedo_color = mat.albedo_color.lightened(0.35)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = mat
		mi.mesh = cyl
		mi.position = MapMeshBuilder.v3(center, height * 0.5)
		_tokens_node.add_child(mi)
		var lbl: Label3D = Label3D.new()
		lbl.text = t.name
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Tamaño fijo en pantalla: legible desde lejos y sin tapar la vista
		# en 1ª persona cuando hay una ficha al lado.
		lbl.fixed_size = true
		lbl.pixel_size = 0.0012
		lbl.font_size = 32
		lbl.outline_size = 10
		lbl.modulate = Color.WHITE
		lbl.position = MapMeshBuilder.v3(center, height + 0.35)
		_tokens_node.add_child(lbl)


func _build_labels() -> void:
	var g: GridGeometry = document.grid
	var lvl: MapLevel = document.level(level_index)
	for o: MapObject in lvl.objects:
		var cells: Array[Vector2i] = lvl.object_cells(o)
		if cells.is_empty():
			continue
		var any_seen: bool = false
		var center: Vector2 = Vector2.ZERO
		for c: Vector2i in cells:
			center += g.cell_to_pixel(c, cell_m)
			var i: int = g.index_of(c)
			if MapMeshBuilder.fog_factor(_build_opts_for_fog(), i) > 0.0:
				any_seen = true
		if not any_seen:
			continue
		center /= float(cells.size())
		var label: String = tr("OBJ_" + o.catalog_id.to_upper())
		if label.begins_with("OBJ_"):
			label = o.catalog_id
		var lbl: Label3D = Label3D.new()
		lbl.text = label
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.fixed_size = true
		lbl.no_depth_test = true
		lbl.pixel_size = 0.001
		lbl.font_size = 28
		lbl.outline_size = 10
		lbl.modulate = Color("fbf0d2")
		lbl.outline_modulate = Color("2b1d14")
		lbl.position = MapMeshBuilder.v3(center, maxf(0.12, float(o.height_mm) / 1000.0) + 0.3)
		_labels_node.add_child(lbl)
	# Edificios de un asentamiento (mapas hijos): su tipo sobre la huella.
	var fog_opts: MapMeshBuilder.Options = _build_opts_for_fog()
	for ch: MapChild in lvl.children:
		var a: Vector2 = g.cell_to_pixel(ch.rect.position, cell_m)
		var b: Vector2 = g.cell_to_pixel(ch.rect.end - Vector2i(1, 1), cell_m)
		if MapMeshBuilder.fog_factor(fog_opts, g.index_of(ch.entrance)) <= 0.0:
			continue
		var blbl: Label3D = Label3D.new()
		blbl.text = tr("BUILDING_" + ch.kind.to_upper())
		blbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		blbl.fixed_size = true
		blbl.no_depth_test = true
		blbl.pixel_size = 0.001
		blbl.font_size = 36
		blbl.outline_size = 12
		blbl.modulate = Color("fbf0d2")
		blbl.outline_modulate = Color("2b1d14")
		blbl.position = MapMeshBuilder.v3((a + b) * 0.5, 3.6)
		_labels_node.add_child(blbl)


func _build_opts_for_fog() -> MapMeshBuilder.Options:
	var o: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
	o.fog = fog
	o.visible = fog_visible
	o.explored = fog_explored
	return o


# --- Cámara -------------------------------------------------------------------

## Centra la cámara cenital en el mapa entero.
func fit() -> void:
	if document == null:
		return
	var size: Vector2 = document.grid.map_pixel_size(cell_m)
	_target = Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	_dist = clampf(maxf(size.x, size.y) * 0.95, DIST_MIN, DIST_MAX)
	_yaw = 0.0
	_tilt = 35.0
	_update_camera()


func set_mode(m: Mode) -> void:
	mode = m
	if mode == Mode.FIRST_PERSON:
		_enter_first_person()
	mark_dirty()
	_update_camera()


func _enter_first_person() -> void:
	if document == null:
		return
	var t: MapToken = document.token(selected_token)
	if t == null or t.level != level_index:
		# Sin selección: la primera ficha del grupo en este nivel.
		var party: Array[MapToken] = PartyVision.party_tokens(document, level_index)
		if party.is_empty() and not document.tokens.is_empty():
			party = [document.tokens[0]]
		selected_token = party[0].id if not party.is_empty() else -1
	_fp_pitch = 0.0
	_fp_facing = _longest_open_direction()
	_fp_yaw = _facing_yaw(_fp_facing)


## Dirección con arista por la que más casillas se puede avanzar en línea
## recta: así la 1ª persona no empieza mirando a una pared.
func _longest_open_direction() -> int:
	var t: MapToken = document.token(selected_token)
	if t == null or profile == null:
		return 0
	var g: GridGeometry = document.grid
	var lvl: MapLevel = document.level(level_index)
	var mask: PackedByteArray = lvl.movement_mask()
	var best: int = 0
	var best_run: int = -1
	for dir: int in g.edge_direction_count():
		var c: Vector2i = t.cell
		var run: int = 0
		while run < 30:
			var n: Vector2i = g.neighbor(c, dir)
			var i: int = g.index_of(n)
			if i < 0 or (mask[i] & MapLevel.MOVE_PASSABLE) == 0 or lvl.edge_blocks_movement(c, dir):
				break
			c = n
			run += 1
		if run > best_run:
			best_run = run
			best = dir
	return best


## Ángulo (radianes, alrededor de Y) que mira hacia la vecina en `dir`.
func _facing_yaw(dir: int) -> float:
	var t: MapToken = document.token(selected_token) if document != null else null
	var from: Vector2i = t.cell if t != null else Vector2i.ZERO
	var g: GridGeometry = document.grid
	var a: Vector2 = g.cell_to_pixel(from, 1.0)
	var b: Vector2 = g.cell_to_pixel(g.neighbor(from, dir), 1.0)
	var d: Vector2 = b - a
	# Cámara de Godot mira a -Z con yaw 0; el mapa crece en +X y +Z.
	return atan2(-d.x, -d.y)


func _update_camera() -> void:
	if _camera == null:
		return
	if mode == Mode.FIRST_PERSON and document != null and document.token(selected_token) != null:
		var t: MapToken = document.token(selected_token)
		var p: Vector2 = document.grid.cell_to_pixel(t.cell, cell_m)
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov_first_person
		_camera.position = MapMeshBuilder.v3(p, _eye_height(t.size_id))
		_camera.rotation = Vector3(_fp_pitch, _fp_yaw, 0.0)
		return
	var pitch: float = deg_to_rad(90.0 - _tilt)
	var offset: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)) * _dist
	offset = offset.rotated(Vector3.UP, _yaw)
	_camera.position = _target + offset
	_camera.look_at(_target, Vector3.UP if _tilt > 0.5 else Vector3(sin(_yaw), 0.0, cos(_yaw)) * -1.0)
	if _ortho:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = _dist * 0.75
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = FOV_TOP


static func _eye_height(size_id: String) -> float:
	var h: float = EYE_HEIGHT_M.get(size_id, 1.6)
	return h


func camera() -> Camera3D:
	return _camera


# --- Interacción --------------------------------------------------------------

## Punto de entrada del ratón y teclado (la UI se lo reenvía; posiciones en
## coordenadas del SubViewport).
func process_input(event: InputEvent) -> void:
	if not interactive or document == null:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		_handle_button(mb)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		_handle_motion(mm)
		return
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed:
		handle_key(k)


func _handle_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and mode == Mode.TOP:
				var steps: float = mb.factor if mb.factor > 0.0 else 1.0
				var f: float = pow(ZOOM_STEP, steps)
				_dist = clampf(_dist / f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else _dist * f, DIST_MIN, DIST_MAX)
				_update_camera()
		MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		MOUSE_BUTTON_RIGHT:
			_rotating = mb.pressed
		MOUSE_BUTTON_LEFT:
			if mode != Mode.TOP:
				return
			var cell: Vector2i = cell_at_screen(mb.position)
			if mb.pressed:
				_on_left_press(cell, mb.position)
			else:
				_on_left_release(cell)


func _handle_motion(mm: InputEventMouseMotion) -> void:
	if _rotating:
		if mode == Mode.TOP:
			_yaw -= mm.relative.x * 0.01
			_tilt = clampf(_tilt + mm.relative.y * 0.25, TILT_MIN, TILT_MAX)
		else:
			_fp_yaw -= mm.relative.x * 0.006
			_fp_pitch = clampf(_fp_pitch - mm.relative.y * 0.006, -1.2, 1.2)
		_update_camera()
	elif _panning and mode == Mode.TOP:
		var scale_m: float = _dist * 0.0018
		var right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var fwd: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
		_target -= right * mm.relative.x * scale_m + fwd * mm.relative.y * scale_m
		_update_camera()


func handle_key(k: InputEventKey) -> void:
	if document == null:
		return
	if mode == Mode.TOP:
		match k.keycode:
			KEY_Q:
				_yaw += deg_to_rad(15.0)
			KEY_E:
				_yaw -= deg_to_rad(15.0)
			KEY_R:
				_tilt = clampf(_tilt + 5.0, TILT_MIN, TILT_MAX)
			KEY_F:
				_tilt = clampf(_tilt - 5.0, TILT_MIN, TILT_MAX)
			KEY_O:
				_ortho = not _ortho
			_:
				return
		_update_camera()
		return
	match k.keycode:
		KEY_W, KEY_UP:
			step_first_person(1)
		KEY_S, KEY_DOWN:
			step_first_person(-1)
		KEY_A, KEY_LEFT:
			turn_first_person(-1)
		KEY_D, KEY_RIGHT:
			turn_first_person(1)
		KEY_SPACE, KEY_E:
			toggle_door_ahead()


## Dirección de arista más cercana a donde mira la cámara: tras mirar con el
## ratón, "delante" es hacia donde se mira, no la última dirección girada.
func _sync_facing_to_view() -> void:
	var best: int = _fp_facing
	var best_diff: float = TAU
	for d: int in document.grid.edge_direction_count():
		var diff: float = absf(wrapf(_facing_yaw(d) - _fp_yaw, -PI, PI))
		if diff < best_diff:
			best_diff = diff
			best = d
	_fp_facing = best


## Abre o cierra la puerta de la arista que hay delante en 1ª persona.
func toggle_door_ahead() -> bool:
	var t: MapToken = document.token(selected_token)
	if t == null or command_stack == null:
		return false
	_sync_facing_to_view()
	var lvl: MapLevel = document.level(level_index)
	var v: int = lvl.get_edge(t.cell, _fp_facing)
	if not MapEdge.is_door(v):
		return false
	var secret_hidden: bool = MapEdge.kind_of(v) == MapEdge.KIND_SECRET_DOOR and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED)
	if secret_hidden and (fog or not dm_view):
		return false
	var id: int = document.grid.edge_id(t.cell, _fp_facing)
	if not command_stack.execute(SetEdgeCommand.toggle_flag(document, level_index, id, MapEdge.FLAG_OPEN)):
		return false
	user_command_done.emit()
	return true


## Gira a la dirección de arista vecina (horario = +1).
func turn_first_person(sign_dir: int) -> void:
	_sync_facing_to_view()
	var n: int = document.grid.edge_direction_count()
	# El orden de direcciones de cada rejilla no es siempre horario en las
	# primeras edge_direction_count(): se elige la siguiente por ángulo.
	var best: int = _fp_facing
	var best_delta: float = TAU
	var cur: float = _facing_yaw(_fp_facing)
	for d: int in n:
		if d == _fp_facing:
			continue
		var delta: float = wrapf((cur - _facing_yaw(d)) * float(sign_dir), 0.0, TAU)
		if delta > 0.01 and delta < best_delta:
			best_delta = delta
			best = d
	_fp_facing = best
	_fp_yaw = _facing_yaw(_fp_facing)
	_update_camera()


## Avanza (1) o retrocede (-1) una casilla con un MoveTokenCommand, si la
## ruta de un paso existe según el perfil (muros y puertas cerradas paran).
func step_first_person(sign_dir: int) -> bool:
	var t: MapToken = document.token(selected_token)
	if t == null or command_stack == null or profile == null:
		return false
	var g: GridGeometry = document.grid
	_sync_facing_to_view()
	var dir: int = _fp_facing if sign_dir > 0 else g.opposite(_fp_facing)
	var target: Vector2i = g.neighbor(t.cell, dir)
	if not g.in_bounds(target):
		return false
	var route: MovementCost.Route = MovementCost.find_route(profile, document.level(level_index), t.cell, target, diagonal_variant)
	if not route.found or route.cells.size() != 2:
		status_changed.emit(tr("UI_NO_ROUTE_STATUS"))
		return false
	var yaw_before: float = _fp_yaw
	if not command_stack.execute(MoveTokenCommand.new(t.id, target, level_index)):
		return false
	_fp_yaw = yaw_before
	status_changed.emit(tr("UI_MOVED").replace("{cost}", _format_ft(route.cost_ft)))
	user_command_done.emit()
	_update_camera()
	return true


## Casilla bajo un punto de pantalla (rayo contra el suelo y = 0).
func cell_at_screen(pos: Vector2) -> Vector2i:
	var p: Vector2 = ground_at_screen(pos)
	if p.x == INF:
		return Vector2i(-1, -1)
	return document.grid.pixel_to_cell(p, cell_m)


func ground_at_screen(pos: Vector2) -> Vector2:
	var from: Vector3 = _camera.project_ray_origin(pos)
	var dir: Vector3 = _camera.project_ray_normal(pos)
	if absf(dir.y) < 0.0001:
		return Vector2(INF, INF)
	var t: float = -from.y / dir.y
	if t < 0.0:
		return Vector2(INF, INF)
	var hit: Vector3 = from + dir * t
	return Vector2(hit.x, hit.z)


## Pantalla de un punto del suelo (para tests y depuración).
func screen_of_cell(cell: Vector2i) -> Vector2:
	var p: Vector2 = document.grid.cell_to_pixel(cell, cell_m)
	return _camera.unproject_position(MapMeshBuilder.v3(p, 0.0))


func _on_left_press(cell: Vector2i, pos: Vector2) -> void:
	var t: MapToken = _token_at(cell)
	if t != null:
		_drag_token = t.id
		selected_token = t.id
		_drag_cell = cell
		token_selected.emit(t.id)
		mark_dirty()
		return
	var edge: int = _door_edge_near(ground_at_screen(pos))
	if edge >= 0 and command_stack != null:
		if command_stack.execute(SetEdgeCommand.toggle_flag(document, level_index, edge, MapEdge.FLAG_OPEN)):
			user_command_done.emit()


func _on_left_release(cell: Vector2i) -> void:
	if _drag_token < 0:
		return
	var t: MapToken = document.token(_drag_token)
	_drag_token = -1
	if t == null or cell == t.cell or not document.grid.in_bounds(cell) or profile == null:
		mark_dirty()
		return
	var route: MovementCost.Route = MovementCost.find_route(profile, document.level(level_index), t.cell, cell, diagonal_variant)
	if not route.found:
		status_changed.emit(tr("UI_NO_ROUTE_STATUS"))
		mark_dirty()
		return
	if command_stack.execute(MoveTokenCommand.new(t.id, cell, level_index)):
		var text: String = tr("UI_MOVED").replace("{cost}", _format_ft(route.cost_ft))
		if profile.default_speed_ft > 0 and route.cost_ft > profile.default_speed_ft:
			text += "  " + tr("UI_OVER_SPEED")
		status_changed.emit(text)
		user_command_done.emit()


func _token_at(cell: Vector2i) -> MapToken:
	if not document.grid.in_bounds(cell):
		return null
	for i: int in range(document.tokens.size() - 1, -1, -1):
		var t: MapToken = document.tokens[i]
		if t.level != level_index or (t.hidden and not dm_view):
			continue
		var cells: Array[Vector2i] = document.token_cells(t, profile) if profile != null else [t.cell]
		if cells.has(cell):
			if fog and not PartyVision.SIDES_IN_PARTY.has(t.side) and not _cell_visible(t.cell):
				continue
			return t
	return null


## Puerta cuya arista está más cerca del punto del suelo (metros), a menos de
## un tercio de casilla; -1 si no hay.
func _door_edge_near(p: Vector2) -> int:
	if p.x == INF:
		return -1
	var g: GridGeometry = document.grid
	var lvl: MapLevel = document.level(level_index)
	var cell: Vector2i = g.pixel_to_cell(p, cell_m)
	if not g.in_bounds(cell):
		return -1
	var best: int = -1
	var best_d: float = cell_m * 0.33
	for dir: int in g.edge_direction_count():
		var v: int = lvl.get_edge(cell, dir)
		if not MapEdge.is_door(v):
			continue
		var secret_hidden: bool = MapEdge.kind_of(v) == MapEdge.KIND_SECRET_DOOR and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED)
		if secret_hidden and (fog or not dm_view):
			continue
		var seg: PackedVector2Array = g.edge_segment(cell, dir, cell_m)
		var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]))
		if d < best_d:
			best_d = d
			best = g.edge_id(cell, dir)
	return best


func _format_ft(ft: int) -> String:
	return Units.format_distance(Units.ft_to_mm(ft, unit_mode), unit_system, unit_mode)
