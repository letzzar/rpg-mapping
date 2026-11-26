class_name ProjectorWindow
extends Window
## Ventana del proyector (modo proyectado, ADR 039): la vista de los
## jugadores, a escala real sobre la mesa para poner encima miniaturas
## físicas. Sin interfaz: fondo negro, rejilla marcada, nada oculto, y por
## defecto sin fichas (las ponen los jugadores en la mesa).
##
## La imagen NO se mueve sola: si se moviera, las miniaturas dejarían de
## estar en su casilla. Solo cambia cuando el DM la desplaza, la centra, la
## gira o cambia la escala (calibración).

## Píxeles del proyector por casilla, al empezar (se calibra con una regla).
const DEFAULT_PX_PER_CELL: float = 96.0
## Lado del cuadrado de calibración, en casillas.
const CALIBRATION_CELLS: int = 4
const CONFIG_PATH: String = "user://projector.cfg"

## Dónde se guarda la calibración (las pruebas usan otro fichero para no
## pisar la del usuario).
var config_path: String = CONFIG_PATH
var view: MapView2D
var px_per_cell: float = DEFAULT_PX_PER_CELL:
	set = set_px_per_cell
## Giro de la imagen en cuartos de vuelta (0-3), según el lado de la mesa
## donde esté el proyector.
var quarter_turns: int = 0:
	set = set_quarter_turns
## Casilla (con decimales) que queda en el centro de la imagen.
var center_cell: Vector2 = Vector2.ZERO
var calibrating: bool = false:
	set = set_calibrating
## Largo en mm de una casilla en la mesa (texto de la calibración).
var cell_mm: int = 25

var _overlay: Control


func _init() -> void:
	title = "RPG Mapping"
	transient = false
	exclusive = false
	unresizable = false
	size = Vector2i(960, 600)
	# Ventana del sistema (otra pantalla) salvo sin pantalla (pruebas
	# headless), donde va incrustada. Se cambia con la ventana oculta (si no,
	# Godot lo rechaza); la enciende el panel.
	visible = false
	if DisplayServer.get_name() != "headless":
		force_native = true
	var bg: ColorRect = ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	view = MapView2D.new()
	view.interactive = false
	view.dm_view = false
	view.show_tokens = false
	view.background = Color.BLACK
	view.explored_veil = 0.15
	view.grid_color = Color(0.2, 0.14, 0.08, 0.75)
	add_child(view)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	size_changed.connect(apply_layout)


func set_document(doc: MapDocument, level_index: int) -> void:
	view.document = doc
	view.level_index = level_index
	apply_layout()


func set_px_per_cell(v: float) -> void:
	px_per_cell = clampf(v, 8.0, 600.0)
	apply_layout()


func set_quarter_turns(v: int) -> void:
	quarter_turns = posmod(v, 4)
	apply_layout()


func set_calibrating(v: bool) -> void:
	calibrating = v
	if _overlay != null:
		_overlay.queue_redraw()


## Desplaza la imagen `cells` casillas (en el sentido del mapa).
func shift(cells: Vector2) -> void:
	center_cell += cells
	apply_layout()


func center_on(cell: Vector2i) -> void:
	center_cell = Vector2(cell) + Vector2(0.5, 0.5)
	apply_layout()


## Coloca la vista: escala, giro y la casilla central en el centro.
func apply_layout() -> void:
	if view == null:
		return
	var k: float = px_per_cell / view.cell_px
	view.scale = Vector2(k, k)
	view.rotation = quarter_turns * PI * 0.5
	var map_pt: Vector2 = center_cell * view.cell_px
	if view.document != null:
		map_pt = view.document.grid.cell_to_pixel(Vector2i(floori(center_cell.x), floori(center_cell.y)), view.cell_px) \
			+ (center_cell - Vector2(floori(center_cell.x), floori(center_cell.y)) - Vector2(0.5, 0.5)) * view.cell_px
	var screen_center: Vector2 = Vector2(size) * 0.5
	view.position = screen_center - (Transform2D(view.rotation, Vector2.ZERO) * (map_pt * k))
	view.queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## Esquinas de la imagen proyectada en coordenadas del mapa (las de
## MapView2D, a su cell_px): para dibujarla en la pantalla del DM.
func area_polygon() -> PackedVector2Array:
	var inv: Transform2D = view.get_transform().affine_inverse()
	var s: Vector2 = Vector2(size)
	return PackedVector2Array([inv * Vector2.ZERO, inv * Vector2(s.x, 0), inv * s, inv * Vector2(0, s.y)])


func _draw_overlay() -> void:
	if not calibrating:
		return
	var side: float = px_per_cell * CALIBRATION_CELLS
	var c: Vector2 = _overlay.size * 0.5
	var r: Rect2 = Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
	_overlay.draw_rect(r, Color.WHITE, false, 3.0)
	for i: int in range(1, CALIBRATION_CELLS):
		var x: float = r.position.x + px_per_cell * i
		var y: float = r.position.y + px_per_cell * i
		_overlay.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.6), 1.0)
		_overlay.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.6), 1.0)
	var font: Font = ThemeDB.fallback_font
	var text: String = tr("UI_PROJ_CALIBRATE_HINT").replace("{cm}", "%d" % (CALIBRATION_CELLS * cell_mm / 10)) \
		.replace("{n}", str(CALIBRATION_CELLS))
	# Fondo oscuro detrás del texto: sobre el mapa no se leía.
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	var at: Vector2 = Vector2(clampf(c.x - ts.x * 0.5, 8.0, maxf(8.0, _overlay.size.x - ts.x - 8.0)), r.end.y + 40)
	_overlay.draw_rect(Rect2(at + Vector2(-10, -ts.y), ts + Vector2(20, 14)), Color(0, 0, 0, 0.85))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)


## Guarda escala, giro y pantalla para la próxima vez.
func save_settings(screen: int, show_tokens: bool) -> void:
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("projector", "px_per_cell", px_per_cell)
	cf.set_value("projector", "quarter_turns", quarter_turns)
	cf.set_value("projector", "screen", screen)
	cf.set_value("projector", "show_tokens", show_tokens)
	cf.save(config_path)


## Lee la configuración guardada; devuelve la pantalla (-1 si no hay).
func load_settings() -> Dictionary:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(config_path) != OK:
		return {}
	var ppc: float = cf.get_value("projector", "px_per_cell", DEFAULT_PX_PER_CELL)
	var turns: int = cf.get_value("projector", "quarter_turns", 0)
	px_per_cell = ppc
	quarter_turns = turns
	return {
		"screen": cf.get_value("projector", "screen", -1),
		"show_tokens": cf.get_value("projector", "show_tokens", false),
	}
