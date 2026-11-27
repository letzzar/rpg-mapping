class_name PixelCanvas
extends RefCounted
## Lienzo de pixel art (ADR 047): una Image RGBA pequeña con las primitivas
## que usan los generadores de tiles, muebles y personajes (píxel, rectángulo,
## línea, círculo, elipse, contorno automático) y las rampas de color.
##
## Todo es determinista: la variación sale de `hash_int` (entero, sin
## randi()), así redibujar no hace parpadear nada y dos equipos ven lo mismo.
## Son vistas: no tocan el modelo ni el código de semilla.

var image: Image
var width: int
var height: int


func _init(w: int, h: int) -> void:
	width = w
	height = h
	image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))


func px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	if c.a >= 1.0:
		image.set_pixel(x, y, c)
	elif c.a > 0.0:
		image.set_pixel(x, y, image.get_pixel(x, y).blend(c))


func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Color(0, 0, 0, 0)
	return image.get_pixel(x, y)


func fill(c: Color) -> void:
	image.fill(c)


func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy: int in range(maxi(0, y), mini(height, y + h)):
		for xx: int in range(maxi(0, x), mini(width, x + w)):
			px(xx, yy, c)


func hline(x0: int, x1: int, y: int, c: Color) -> void:
	for x: int in range(mini(x0, x1), maxi(x0, x1) + 1):
		px(x, y, c)


func vline(x: int, y0: int, y1: int, c: Color) -> void:
	for y: int in range(mini(y0, y1), maxi(y0, y1) + 1):
		px(x, y, c)


## Línea de Bresenham (píxeles enteros, sin suavizado).
func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	while true:
		px(x, y, c)
		if x == x1 and y == y1:
			return
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


## Elipse rellena de centro (cx, cy) y semiejes rx, ry (admite medios
## píxeles: centro x.5 para anchos pares).
func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for y: int in range(maxi(0, floori(cy - ry)), mini(height, ceili(cy + ry) + 1)):
		for x: int in range(maxi(0, floori(cx - rx)), mini(width, ceili(cx + rx) + 1)):
			var nx: float = (float(x) + 0.5 - cx) / rx
			var ny: float = (float(y) + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				px(x, y, c)


func circle(cx: float, cy: float, r: float, c: Color) -> void:
	ellipse(cx, cy, r, r, c)


## Anillo de una elipse (solo el borde, 1 px).
func ellipse_ring(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y: int in range(maxi(0, floori(cy - ry)), mini(height, ceili(cy + ry) + 1)):
		for x: int in range(maxi(0, floori(cx - rx)), mini(width, ceili(cx + rx) + 1)):
			var nx: float = (float(x) + 0.5 - cx) / rx
			var ny: float = (float(y) + 0.5 - cy) / ry
			var d: float = nx * nx + ny * ny
			if d <= 1.0 and d > _ring_inner(rx, ry):
				px(x, y, c)


func _ring_inner(rx: float, ry: float) -> float:
	var k: float = 1.0 - 1.6 / maxf(1.0, minf(rx, ry))
	return maxf(0.0, k * k)


## Contorno de 1 px alrededor de todo lo opaco (los sprites de pixel art lo
## llevan para leerse sobre cualquier suelo). Solo pinta píxeles vacíos.
func outline(c: Color, diagonals: bool = false) -> void:
	var src: Image = image.duplicate()
	for y: int in height:
		for x: int in width:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var hit: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _opaque(src, x + d.x, y + d.y):
					hit = true
			if not hit and diagonals:
				for d: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
					if _opaque(src, x + d.x, y + d.y):
						hit = true
			if hit:
				image.set_pixel(x, y, c)


func _opaque(src: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and src.get_pixel(x, y).a > 0.0


## Copia otro lienzo encima en (ox, oy), con mezcla alfa.
func stamp(other: PixelCanvas, ox: int, oy: int) -> void:
	for y: int in other.height:
		for x: int in other.width:
			var c: Color = other.image.get_pixel(x, y)
			if c.a > 0.0:
				px(ox + x, oy + y, c)


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


# --- Color --------------------------------------------------------------------

## Rampa de 5 tonos de un color base, como se hace a mano en pixel art: las
## sombras se oscurecen y se van hacia el azul/violeta, las luces se aclaran y
## se van hacia el amarillo (no es solo multiplicar el brillo).
## [0] contorno, [1] sombra, [2] base, [3] luz, [4] brillo.
static func ramp(base: Color) -> Array[Color]:
	var out: Array[Color] = []
	out.append(_shift(base, -0.62, 0.25, 0.10))
	out.append(_shift(base, -0.30, 0.12, 0.05))
	out.append(Color(base, 1.0))
	out.append(_shift(base, 0.22, -0.10, 0.05))
	out.append(_shift(base, 0.42, -0.22, 0.09))
	return out


## dv: cambio de brillo (-1..1); ds: cambio de saturación; dh: cuánto se
## acerca el tono a su destino (frío al oscurecer, cálido al aclarar).
static func _shift(c: Color, dv: float, ds: float, dh: float) -> Color:
	var h: float = c.h
	var s: float = c.s
	var v: float = c.v
	var target: float = 0.68 if dv < 0.0 else 0.13
	if s > 0.04:
		h = _hue_toward(h, target, dh)
	s = clampf(s + ds * (1.0 if s > 0.04 else 0.0), 0.0, 1.0)
	if dv < 0.0:
		v = v * (1.0 + dv)
	else:
		v = v + (1.0 - v) * dv
	return Color.from_hsv(h, s, clampf(v, 0.0, 1.0), 1.0)


static func _hue_toward(h: float, target: float, amt: float) -> float:
	var d: float = target - h
	if d > 0.5:
		d -= 1.0
	elif d < -0.5:
		d += 1.0
	return fposmod(h + d * amt, 1.0)


## Entero pseudoaleatorio determinista a partir de coordenadas y una sal
## (mezcla tipo SplitMix con enteros de 32 bits; nunca negativo).
static func hash_int(x: int, y: int, salt: int = 0) -> int:
	var h: int = (x * 374761393 + y * 668265263 + salt * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


## Clave estable de un color para las cachés.
static func color_key(c: Color) -> String:
	return c.to_html(false)
