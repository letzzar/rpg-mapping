class_name LootIcons
extends RefCounted
## Iconos de los tipos de objeto del botín (ADR 049). Los que tienen objeto
## KayKit usan su render (models/kaykit/items/icons/<modelo>.png, hecho con
## tools/render_loot_icons.gd); el resto (monedas, gemas, pociones,
## pergaminos, llaves, anillos) se dibujan por código en pixel art de 16×16.

const ICON_DIR: String = "res://models/kaykit/items/icons"
const DRAWN: int = 16
## Tamaño de todos los iconos (el de los renderizados).
const RENDER_SIZE: int = 64
const OUTLINE: Color = Color(0.08, 0.05, 0.05, 1.0)

static var _cache: Dictionary[String, Texture2D] = {}


## Icono del tipo `kind_id` (null si no hay tipo o no se conoce).
static func texture(kind_id: String, kinds: LootKinds = null) -> Texture2D:
	if kind_id.is_empty():
		return null
	if _cache.has(kind_id):
		return _cache[kind_id]
	if kinds == null:
		kinds = LootKinds.load_default()
	var k: LootKinds.Kind = kinds.kind(kind_id)
	if k == null:
		return null
	var tex: Texture2D = null
	if not k.model.is_empty():
		tex = load("%s/%s.png" % [ICON_DIR, k.model]) as Texture2D
	else:
		var cv: PixelCanvas = draw(kind_id)
		if cv != null:
			# A 64 px como los renderizados, con píxeles nítidos: así todos se
			# reducen igual (con suavizado) al tamaño del panel.
			var img: Image = cv.image.duplicate() as Image
			img.resize(RENDER_SIZE, RENDER_SIZE, Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_cache[kind_id] = tex
	return tex


## Icono dibujado por código (null si el tipo se dibuja con su modelo).
static func draw(kind_id: String) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(DRAWN, DRAWN)
	match kind_id:
		"coins":
			var g: Array[Color] = PixelCanvas.ramp(Color("d9b03c"))
			for c: Vector2i in [Vector2i(5, 10), Vector2i(10, 10), Vector2i(7, 6)]:
				cv.ellipse(float(c.x) + 0.5, float(c.y) + 0.5, 3.6, 2.6, g[1])
				cv.ellipse(float(c.x) + 0.5, float(c.y), 3.2, 2.1, g[2])
				cv.hline(c.x - 1, c.x + 1, c.y - 1, g[4])
		"gem":
			var r: Array[Color] = PixelCanvas.ramp(Color("c0304a"))
			for y: int in 4:
				cv.hline(5 - y, 10 + y, 4 + y, r[3] if y < 2 else r[2])
			for y: int in 6:
				cv.hline(2 + y, 13 - y, 8 + y, r[1] if y > 2 else r[2])
			cv.px(6, 5, r[4])
			cv.px(5, 6, r[4])
		"potion":
			var b: Array[Color] = PixelCanvas.ramp(Color("3c8fd0"))
			cv.circle(7.5, 10.0, 4.6, b[2])
			cv.circle(6.5, 9.0, 1.4, b[4])
			cv.rect(6, 2, 4, 4, Color(0.8, 0.85, 0.9, 0.9))
			cv.rect(6, 1, 4, 2, Color("8a6238"))
		"scroll":
			var p: Array[Color] = PixelCanvas.ramp(Color("e6d3a3"))
			cv.rect(4, 3, 8, 10, p[2])
			for y: int in [5, 7, 9]:
				cv.hline(5, 10, y, p[0])
			cv.rect(3, 2, 10, 2, p[1])
			cv.rect(3, 12, 10, 2, p[1])
			cv.px(8, 11, Color("a8322d"))
		"key":
			var m: Array[Color] = PixelCanvas.ramp(Color("c9a447"))
			cv.ellipse_ring(5.5, 5.5, 3.5, 3.5, m[2])
			cv.line(7, 7, 13, 13, m[2])
			cv.line(8, 7, 13, 12, m[3])
			cv.rect(11, 12, 2, 2, m[1])
			cv.rect(9, 10, 2, 2, m[1])
		"ring":
			var m: Array[Color] = PixelCanvas.ramp(Color("d9b03c"))
			cv.ellipse_ring(8.0, 9.5, 4.8, 4.0, m[2])
			cv.ellipse_ring(8.0, 9.0, 4.0, 3.4, m[3])
			cv.circle(8.0, 4.5, 2.0, Color("4ab0d9"))
			cv.px(7, 4, Color.WHITE)
		_:
			return null
	cv.outline(OUTLINE)
	return cv
