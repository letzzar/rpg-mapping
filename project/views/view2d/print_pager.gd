class_name PrintPager
extends RefCounted
## Impresión a escala real por páginas (PROYECTO §7, ADR 014 y 042): parte
## el nivel en hojas A4 o Carta con la casilla a su medida (1 pulgada o
## 25 mm), renderiza cada hoja por separado (solo su trozo de mapa, no el
## mapa entero en una imagen gigante) y las junta en un PDF.
##
## Cada hoja lleva marcas de esquina para alinearlas al unirlas y su
## posición ("fila 2, columna 3 de 3 × 4"). La orientación (vertical u
## horizontal) se elige sola: la que necesite menos hojas.

const PT_PER_INCH: float = 72.0
const PAPERS: Dictionary[String, Vector2] = {
	"a4": Vector2(595.28, 841.89),
	"letter": Vector2(612.0, 792.0),
}
## Medida de la casilla en milímetros: 25,4 (1 pulgada) o 25.
const CELL_MM_OPTIONS: PackedFloat32Array = [25.4, 25.0]
## Margen de la hoja (las impresoras no llegan al borde), en puntos.
const MARGIN_PT: float = 28.0
## Resolución de las imágenes (puntos por pulgada de la impresión).
const DEFAULT_DPI: int = 150


class Options:
	extends RefCounted
	var paper: String = "a4"
	var cell_mm: float = 25.4
	var dpi: int = DEFAULT_DPI
	var dm_view: bool = false
	var show_tokens: bool = false
	var show_grid: bool = true


class Layout:
	extends RefCounted
	## Papel en puntos (ya girado si va apaisado).
	var paper_pt: Vector2 = Vector2.ZERO
	var landscape: bool = false
	## Zona imprimible en puntos.
	var area_pt: Vector2 = Vector2.ZERO
	## Casilla en puntos.
	var cell_pt: float = 72.0
	var columns: int = 1
	var rows: int = 1

	func page_count() -> int:
		return columns * rows


## Cómo se reparte el mapa `doc` en hojas con estas opciones.
static func layout(doc: MapDocument, o: Options) -> Layout:
	var paper: Vector2 = PAPERS.get(o.paper, PAPERS["a4"])
	var cell_pt: float = o.cell_mm / 25.4 * PT_PER_INCH
	var map_pt: Vector2 = doc.grid.map_pixel_size(1.0) * cell_pt
	var best: Layout = null
	for landscape: bool in [false, true]:
		var l: Layout = Layout.new()
		l.landscape = landscape
		l.paper_pt = Vector2(paper.y, paper.x) if landscape else paper
		l.area_pt = l.paper_pt - Vector2(MARGIN_PT, MARGIN_PT) * 2.0
		l.cell_pt = cell_pt
		l.columns = maxi(1, ceili(map_pt.x / l.area_pt.x - 0.0001))
		l.rows = maxi(1, ceili(map_pt.y / l.area_pt.y - 0.0001))
		if best == null or l.page_count() < best.page_count():
			best = l
	return best


## Renderiza las hojas y devuelve el PDF (vacío si no se pudo: sin
## renderizador, en modo headless, las imágenes salen vacías).
static func build_pdf(host: Node, doc: MapDocument, level_index: int, profile: SystemProfile, o: Options) -> PackedByteArray:
	var l: Layout = layout(doc, o)
	var px_per_pt: float = float(o.dpi) / PT_PER_INCH
	var cell_px: float = l.cell_pt * px_per_pt
	var page_px: Vector2i = Vector2i(roundi(l.area_pt.x * px_per_pt), roundi(l.area_pt.y * px_per_pt))
	var pages: Array[PdfWriter.Page] = []
	for row: int in l.rows:
		for col: int in l.columns:
			var img: Image = await render_page(host, doc, level_index, profile, o, cell_px, page_px,
				Vector2(col * page_px.x, row * page_px.y), row, col, l)
			if img == null or img.is_empty():
				return PackedByteArray()
			var rect: Rect2 = Rect2(Vector2(MARGIN_PT, MARGIN_PT), l.area_pt)
			pages.append(PdfWriter.page_from_image(img, l.paper_pt, rect))
	return PdfWriter.build(pages)


## Imagen de una hoja: el trozo del mapa que empieza en `origin_px` (en
## píxeles del mapa a `cell_px`), con marcas y etiqueta.
static func render_page(host: Node, doc: MapDocument, level_index: int, profile: SystemProfile, o: Options,
		cell_px: float, page_px: Vector2i, origin_px: Vector2, row: int, col: int, l: Layout) -> Image:
	if host == null or not host.is_inside_tree():
		return null
	var vp: SubViewport = SubViewport.new()
	vp.size = page_px
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg: ColorRect = ColorRect.new()
	bg.color = Color.WHITE
	bg.size = Vector2(page_px)
	vp.add_child(bg)
	var view: MapView2D = MapView2D.new()
	view.interactive = false
	view.cell_px = cell_px
	view.profile = profile
	view.dm_view = o.dm_view
	view.show_grid = o.show_grid
	view.show_tokens = o.show_tokens
	# Fondo blanco fuera del mapa: ahorra tinta.
	view.background = Color.WHITE
	view.ink_saver = true
	view.document = doc
	view.level_index = level_index
	view.position = -origin_px
	vp.add_child(view)
	var marks: Node2D = Node2D.new()
	var label: String = TranslationServer.translate("UI_PRINT_PAGE_LABEL") \
		.replace("{n}", str(row * l.columns + col + 1)).replace("{total}", str(l.page_count())) \
		.replace("{row}", str(row + 1)).replace("{col}", str(col + 1)) \
		.replace("{rows}", str(l.rows)).replace("{cols}", str(l.columns)) \
		.replace("{cell}", "%s mm" % String.num(o.cell_mm, 1).replace(".", ","))
	marks.draw.connect(func() -> void: _draw_marks(marks, Vector2(page_px), label))
	vp.add_child(marks)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


static func _draw_marks(ci: CanvasItem, size: Vector2, label: String) -> void:
	var col: Color = Color(0.2, 0.2, 0.2)
	var tick: float = size.x * 0.03
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var dx: float = tick if corner.x == 0.0 else -tick
		var dy: float = tick if corner.y == 0.0 else -tick
		ci.draw_line(corner, corner + Vector2(dx, 0), col, 2.0)
		ci.draw_line(corner, corner + Vector2(0, dy), col, 2.0)
	var font: Font = ThemeDB.fallback_font
	var fs: int = maxi(12, int(size.x * 0.016))
	var ts: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at: Vector2 = Vector2(size.x - ts.x - tick * 1.5, size.y - tick * 0.6)
	ci.draw_rect(Rect2(at + Vector2(-6, -ts.y), ts + Vector2(12, 8)), Color(1, 1, 1, 0.85))
	ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
