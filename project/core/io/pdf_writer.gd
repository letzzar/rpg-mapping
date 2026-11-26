class_name PdfWriter
extends RefCounted
## PDF mínimo de páginas con una imagen cada una (impresión a escala real,
## ADR 014 y 042). Godot no genera PDF; este formato basta: cada página es
## un XObject de imagen JPEG (filtro DCTDecode, que todo lector de PDF
## entiende) colocado a un tamaño exacto en puntos (1/72 de pulgada), así
## que la escala la fija el PDF y no la resolución de la imagen.

class Page:
	extends RefCounted
	## Tamaño del papel en puntos.
	var width_pt: float = 595.28
	var height_pt: float = 841.89
	## JPEG de la imagen y su tamaño en píxeles.
	var jpeg: PackedByteArray = PackedByteArray()
	var img_w: int = 0
	var img_h: int = 0
	## Rectángulo donde va la imagen, en puntos desde la esquina INFERIOR
	## izquierda (convenio de PDF).
	var rect_pt: Rect2 = Rect2()


## Página con `img` (se pasa a JPEG) en `rect_pt` de un papel de
## `paper_pt`. La imagen se estira al rectángulo: quien llama hace que sus
## proporciones coincidan.
static func page_from_image(img: Image, paper_pt: Vector2, rect_pt: Rect2, quality: float = 0.88) -> Page:
	var p: Page = Page.new()
	var im: Image = img.duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGB8)
	p.jpeg = im.save_jpg_to_buffer(quality)
	p.img_w = im.get_width()
	p.img_h = im.get_height()
	p.width_pt = paper_pt.x
	p.height_pt = paper_pt.y
	p.rect_pt = rect_pt
	return p


## Documento PDF 1.4 con las páginas en orden.
static func build(pages: Array[Page]) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var offsets: PackedInt64Array = PackedInt64Array()
	_ascii(out, "%PDF-1.4\n%âãÏÓ\n")
	# Objetos: 1 catálogo, 2 árbol de páginas y, por página, 3: página,
	# imagen y contenido.
	var n: int = 2 + pages.size() * 3
	offsets.resize(n + 1)
	offsets[1] = out.size()
	_ascii(out, "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
	var kids: String = ""
	for i: int in pages.size():
		kids += "%d 0 R " % (3 + i * 3)
	offsets[2] = out.size()
	_ascii(out, "2 0 obj\n<< /Type /Pages /Kids [%s] /Count %d >>\nendobj\n" % [kids.strip_edges(), pages.size()])
	for i: int in pages.size():
		var p: Page = pages[i]
		var po: int = 3 + i * 3
		var io: int = po + 1
		var co: int = po + 2
		offsets[po] = out.size()
		_ascii(out, "%d 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Resources << /XObject << /Im0 %d 0 R >> >> /Contents %d 0 R >>\nendobj\n"
			% [po, _num(p.width_pt), _num(p.height_pt), io, co])
		offsets[io] = out.size()
		_ascii(out, "%d 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>\nstream\n"
			% [io, p.img_w, p.img_h, p.jpeg.size()])
		out.append_array(p.jpeg)
		_ascii(out, "\nendstream\nendobj\n")
		var content: String = "q %s 0 0 %s %s %s cm /Im0 Do Q\n" % [
			_num(p.rect_pt.size.x), _num(p.rect_pt.size.y), _num(p.rect_pt.position.x), _num(p.rect_pt.position.y)]
		offsets[co] = out.size()
		_ascii(out, "%d 0 obj\n<< /Length %d >>\nstream\n%sendstream\nendobj\n" % [co, content.length(), content])
	var xref: int = out.size()
	_ascii(out, "xref\n0 %d\n0000000000 65535 f \n" % (n + 1))
	for k: int in range(1, n + 1):
		_ascii(out, "%010d 00000 n \n" % offsets[k])
	_ascii(out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [n + 1, xref])
	return out


## Número en puntos con 2 decimales, punto decimal (independiente del
## idioma del sistema).
static func _num(v: float) -> String:
	var hundredths: int = roundi(v * 100.0)
	var neg: String = "-" if hundredths < 0 else ""
	hundredths = absi(hundredths)
	return "%s%d.%02d" % [neg, hundredths / 100, hundredths % 100]


static func _ascii(out: PackedByteArray, s: String) -> void:
	out.append_array(s.to_utf8_buffer())
