extends GutTest
## Impresión a escala real (ADR 042): reparto en hojas y PDF bien formado.
## El renderizado de las hojas necesita pantalla (en headless sale vacío):
## se comprobó a mano con la app y un lector de PDF.


func _doc(w: int, h: int) -> MapDocument:
	var d: MapDocument = MapDocument.create("square", w, h)
	d.level(0).fill_terrain(Terrain.FLOOR)
	return d


func test_layout_pages_and_orientation() -> void:
	var o: PrintPager.Options = PrintPager.Options.new()
	# A4 con márgenes de 28 pt: zona útil 539 × 786 pt = 7,49 × 10,9 casillas
	# de 1 pulgada. Un mapa de 7 × 10 cabe en una hoja vertical.
	var l: PrintPager.Layout = PrintPager.layout(_doc(7, 10), o)
	assert_eq(l.page_count(), 1)
	assert_false(l.landscape)
	assert_almost_eq(l.cell_pt, 72.0, 0.001, "1 pulgada = 72 puntos")
	# 10 × 7 cabe en una horizontal (en vertical serían 2).
	l = PrintPager.layout(_doc(10, 7), o)
	assert_eq(l.page_count(), 1)
	assert_true(l.landscape)
	# Mazmorra típica de 48 × 36.
	l = PrintPager.layout(_doc(48, 36), o)
	var portrait: int = ceili(48.0 / (539.28 / 72.0)) * ceili(36.0 / (785.89 / 72.0))
	var landscape: int = ceili(48.0 / (785.89 / 72.0)) * ceili(36.0 / (539.28 / 72.0))
	assert_eq(l.page_count(), mini(portrait, landscape))
	# 25 mm por casilla: algo más pequeña.
	o.cell_mm = 25.0
	assert_almost_eq(PrintPager.layout(_doc(4, 4), o).cell_pt, 25.0 / 25.4 * 72.0, 0.001)
	o.paper = "letter"
	assert_almost_eq(PrintPager.layout(_doc(4, 4), o).paper_pt.x, 612.0, 0.01)


func test_pdf_is_well_formed() -> void:
	var pages: Array[PdfWriter.Page] = []
	for k: int in 3:
		var img: Image = Image.create(40, 60, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2 * k, 0.5, 0.8))
		pages.append(PdfWriter.page_from_image(img, Vector2(595.28, 841.89), Rect2(28, 28, 539.28, 785.89)))
	var pdf: PackedByteArray = PdfWriter.build(pages)
	# Copia byte a byte en ASCII (los JPEG tienen ceros y bytes > 127, que
	# cortarían o desplazarían la conversión a texto).
	var clean: PackedByteArray = pdf.duplicate()
	for i: int in clean.size():
		if clean[i] >= 128 or (clean[i] < 32 and clean[i] != 10):
			clean[i] = 63
	var text: String = clean.get_string_from_ascii()
	assert_eq(text.length(), pdf.size())
	assert_true(text.begins_with("%PDF-1.4"))
	assert_true(pdf.slice(pdf.size() - 6).get_string_from_ascii().begins_with("%%EOF"))
	assert_string_contains(text, "/Count 3")
	assert_string_contains(text, "/MediaBox [0 0 595.28 841.89]")
	assert_string_contains(text, "q 539.28 0 0 785.89 28.00 28.00 cm /Im0 Do Q")
	# Tabla de referencias: cada desplazamiento apunta a "n 0 obj".
	var sx: int = text.rfind("startxref")
	var xref_at: int = text.substr(sx + 10).strip_edges().split("\n")[0].to_int()
	assert_eq(text.substr(xref_at, 4), "xref")
	var lines: PackedStringArray = text.substr(xref_at).split("\n")
	var count: int = lines[1].split(" ")[1].to_int()
	assert_eq(count, 2 + 3 * 3 + 1)
	for k: int in range(1, count):
		var off: int = lines[2 + k].substr(0, 10).to_int()
		assert_eq(text.substr(off, str(k).length() + 6), "%d 0 obj" % k, "objeto %d" % k)
	# El JPEG de cada página está entero (marca de inicio y de fin).
	var jpeg: PackedByteArray = pages[0].jpeg
	assert_eq(jpeg[0], 0xFF)
	assert_eq(jpeg[1], 0xD8)
	assert_eq(jpeg[jpeg.size() - 2], 0xFF)
	assert_eq(jpeg[jpeg.size() - 1], 0xD9)
