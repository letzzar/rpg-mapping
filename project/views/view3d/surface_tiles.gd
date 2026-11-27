class_name SurfaceTiles
extends RefCounted
## Texturas de superficie de la vista 2.5D (ADR 051), generadas por código:
## losas, tablones, hierba, agua, tierra, ladrillo de muro y tablones de
## puerta, con VARIANTS variantes cada una para que el suelo no se repita.
## Dos juegos con las mismas capas:
## - pixel art: los tiles de 32×32 de PixelTiles (los mismos de la vista 2D)
##   y ladrillo y puerta dibujados igual, para muestrear sin suavizado;
## - normal: 64×64 suaves (ruido de valor, biseles y vetas), con mipmaps.
## Cada téxel se guarda dividido por el color medio de su capa (y por 2): el
## sombreador lo multiplica por el color del vértice, así se conservan el
## color de cada zona, la niebla y la luz horneadas.
## Capa = KIND * VARIANTS + variante (el orden de KINDS lo usa el sombreador).

const KINDS: PackedStringArray = ["stone", "wood", "grass", "water", "dirt", "brick", "door", "rock", "sand", "snow", "cobble"]
const VARIANTS: int = 4
const PIXEL_SIZE: int = 32
const SMOOTH_SIZE: int = 64

## Color natural de cada tipo (el de la zona lo tiñe después).
const BASES: Dictionary[String, Color] = {
	"stone": Color("9a9184"),
	"wood": Color("9a6a3e"),
	"grass": Color("6a9a48"),
	"water": Color("4f9fc4"),
	"dirt": Color("8a6a48"),
	"brick": Color("8f7b62"),
	"door": Color("9a6a32"),
	"rock": Color("5a4636"),
	"sand": Color("d6c08a"),
	"snow": Color("e8eef2"),
	"cobble": Color("a39a8c"),
}


## Capa (tipo de SurfaceTiles) de un entorno de Surroundings, o -1.
static func kind_of_surroundings(s: String) -> int:
	match s:
		Surroundings.COBBLE:
			return KINDS.find("cobble")
		Surroundings.ROCK:
			return KINDS.find("rock")
		_:
			return KINDS.find(s)

static var _arrays: Dictionary[bool, Texture2DArray] = {}


## Las texturas (pixel art o normales), creadas la primera vez.
static func array(pixel: bool) -> Texture2DArray:
	if _arrays.has(pixel):
		return _arrays[pixel]
	var images: Array[Image] = []
	for kind: String in KINDS:
		for v: int in VARIANTS:
			var img: Image = pixel_image(kind, v) if pixel else smooth_image(kind, v)
			images.append(_normalized(img, true))
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(images)
	_arrays[pixel] = arr
	return arr


## Número de capas (para las pruebas).
static func layer_count() -> int:
	return KINDS.size() * VARIANTS


# --- Pixel art -------------------------------------------------------------------

static func pixel_image(kind: String, variant: int) -> Image:
	var base: Color = BASES[kind]
	match kind:
		"stone":
			return PixelTiles.build(PixelTiles.STONE, base, variant).image
		"wood":
			return PixelTiles.build(PixelTiles.WOOD, base, variant).image
		"grass":
			return PixelTiles.build(PixelTiles.GRASS, base, variant).image
		"water":
			return PixelTiles.build(PixelTiles.WATER, base, variant).image
		"dirt":
			return PixelTiles.build(PixelTiles.DIRT, base, variant).image
		"brick":
			return _pixel_brick(base, variant).image
		"rock":
			return PixelTiles.build(PixelTiles.ROCK, base, variant).image
		"sand", "snow":
			return PixelTiles.build(PixelTiles.DIRT, base, variant).image
		"cobble":
			return _pixel_cobble(base, variant).image
		_:
			return _pixel_door(base, variant).image


## Ladrillos de 8×4 en hilera trabada (como la tira de muro de la vista 2D).
static func _pixel_brick(base: Color, variant: int) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(PIXEL_SIZE, PIXEL_SIZE)
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[0])
	for row: int in PIXEL_SIZE / 4:
		var off: int = 4 if row % 2 == 1 else 0
		for b: int in 5:
			var x0: int = b * 8 - off
			var h: int = PixelCanvas.hash_int(b, row, 31 + variant)
			var face: Color = r[2] if h % 3 != 0 else r[1].lerp(r[2], 0.5)
			if h % 11 == 0:
				face = r[2].lerp(r[3], 0.4)
			for yy: int in range(row * 4, row * 4 + 3):
				for xx: int in range(x0, x0 + 7):
					cv.px(posmod(xx, PIXEL_SIZE), yy, face)
			for xx: int in range(x0, x0 + 6):
				cv.px(posmod(xx, PIXEL_SIZE), row * 4, r[3])
	return cv


## Empedrado: cantos redondeados de 6-8 px con juntas oscuras.
static func _pixel_cobble(base: Color, variant: int) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(PIXEL_SIZE, PIXEL_SIZE)
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[0])
	for gy: int in 4:
		for gx: int in 4:
			var h: int = PixelCanvas.hash_int(gx, gy, 211 + variant)
			var cx: float = float(gx * 8) + 4.0 + float(h % 3) - 1.0 + (4.0 if gy % 2 == 1 else 0.0)
			var cy: float = float(gy * 8) + 4.0 + float((h >> 3) % 3) - 1.0
			var face: Color = r[2] if h % 4 != 0 else r[1].lerp(r[2], 0.5)
			for dy: int in range(-4, 5):
				for dx: int in range(-4, 5):
					var d: float = Vector2(float(dx), float(dy)).length()
					if d <= 3.2:
						var col: Color = face
						if dx + dy < -2:
							col = r[3]
						elif dx + dy > 3:
							col = r[1]
						cv.px(posmod(int(cx) + dx, PIXEL_SIZE), posmod(int(cy) + dy, PIXEL_SIZE), col)
	return cv


## Tablones verticales con dos herrajes.
static func _pixel_door(base: Color, variant: int) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(PIXEL_SIZE, PIXEL_SIZE)
	var r: Array[Color] = PixelCanvas.ramp(base)
	var iron: Array[Color] = PixelCanvas.ramp(PixelTiles.BASE_IRON)
	cv.fill(r[2])
	for x: int in range(0, PIXEL_SIZE, 6):
		cv.vline(x, 0, PIXEL_SIZE - 1, r[1])
		cv.vline(x + 1, 0, PIXEL_SIZE - 1, r[3])
		for y: int in PIXEL_SIZE:
			if PixelCanvas.hash_int(x, y, 77 + variant) % 9 == 0:
				cv.px(x + 3, y, r[1].lerp(r[2], 0.5))
	for by: int in [6, 24]:
		cv.rect(0, by, PIXEL_SIZE, 2, iron[2])
		cv.hline(0, PIXEL_SIZE - 1, by, iron[3])
	return cv


# --- Normales (suaves) ----------------------------------------------------------

static func smooth_image(kind: String, variant: int) -> Image:
	var n: int = SMOOTH_SIZE
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var base: Color = BASES[kind]
	var salt: int = variant * 104729 + KINDS.find(kind) * 7919
	for y: int in n:
		for x: int in n:
			var u: float = (float(x) + 0.5) / float(n)
			var v: float = (float(y) + 0.5) / float(n)
			var k: float = 1.0
			var tint: Color = base
			match kind:
				"stone":
					k = _stone(u, v, salt)
				"wood":
					k = _planks(u, v, salt, true)
				"grass":
					k = _grass(u, v, salt)
					tint = base.lerp(Color("8ab04e"), clampf(_fbm(u, v, 3, 3, salt + 5) - 0.35, 0.0, 1.0))
				"water":
					k = 0.9 + 0.06 * sin((u * 2.0 + _fbm(u, v, 2, 2, salt) * 1.5) * TAU) + 0.08 * _fbm(u, v, 6, 6, salt + 9)
				"dirt":
					k = 0.82 + 0.3 * _fbm(u, v, 5, 5, salt) + (0.08 if _hash(int(u * 24.0), int(v * 24.0), salt) % 13 == 0 else 0.0)
				"brick":
					k = _brick(u, v, salt)
				"rock":
					k = 0.75 + 0.45 * _fbm(u, v, 4, 4, salt) * _fbm(u, v, 9, 9, salt + 2) + (0.15 if _fbm(u, v, 12, 12, salt + 4) > 0.72 else 0.0)
				"sand":
					k = 0.9 + 0.08 * sin((v * 6.0 + _fbm(u, v, 3, 3, salt) * 2.0) * TAU) + 0.08 * _fbm(u, v, 16, 16, salt + 1)
				"snow":
					k = 0.93 + 0.1 * _fbm(u, v, 5, 5, salt) - (0.06 if _hash(int(u * 40.0), int(v * 40.0), salt) % 17 == 0 else 0.0)
				"cobble":
					k = _cobble(u, v, salt)
				_:
					k = _planks(v, u, salt, false)
			var c: Color = Color(tint.r * k, tint.g * k, tint.b * k, 1.0)
			img.set_pixel(x, y, c)
	return img


## Losas: 2×2 por casilla con juntas, bisel (luz arriba-izquierda) y moteado.
static func _stone(u: float, v: float, salt: int) -> float:
	var cu: float = u * 2.0
	var cv: float = v * 2.0
	var row: int = floori(cv)
	cu += 0.5 * float(row % 2)
	var id_u: int = floori(cu)
	var fu: float = cu - floorf(cu)
	var fv: float = cv - floorf(cv)
	var edge: float = minf(minf(fu, 1.0 - fu), minf(fv, 1.0 - fv))
	var grout: float = smoothstep(0.0, 0.05, edge)
	var bevel: float = 1.0 + 0.12 * (smoothstep(0.12, 0.0, fu) + smoothstep(0.12, 0.0, fv)) - 0.12 * (smoothstep(0.88, 1.0, fu) + smoothstep(0.88, 1.0, fv))
	var tone: float = 0.88 + 0.18 * float(_hash(posmod(id_u, 2), row, salt) % 100) / 100.0
	var mott: float = 0.9 + 0.2 * _fbm(u, v, 8, 8, salt)
	return tone * bevel * mott * lerpf(0.55, 1.0, grout)


## Tablones (horizontales o verticales) con veta y cabezas desplazadas.
static func _planks(u: float, v: float, salt: int, nails: bool) -> float:
	var rows: float = 4.0
	var pv: float = v * rows
	var row: int = floori(pv)
	var fv: float = pv - floorf(pv)
	var shift: float = float(_hash(row, 0, salt) % 100) / 100.0
	var pu: float = fposmod(u + shift, 1.0) * 1.5
	var fu: float = pu - floorf(pu)
	var seam: float = smoothstep(0.0, 0.05, minf(fv, 1.0 - fv)) * smoothstep(0.0, 0.015, minf(fu, 1.0 - fu))
	var grain: float = 0.92 + 0.1 * sin((v * 40.0 + _fbm(u, v, 3, 12, salt + row) * 4.0) * PI)
	var tone: float = 0.86 + 0.2 * float(_hash(row, floori(pu), salt + 3) % 100) / 100.0
	var k: float = tone * grain * lerpf(0.5, 1.0, seam)
	if nails and fu > 0.04 and fu < 0.09 and absf(fv - 0.5) < 0.1:
		k *= 0.6
	return k


## Hierba: manchas de dos escalas y briznas claras.
static func _grass(u: float, v: float, salt: int) -> float:
	var k: float = 0.78 + 0.32 * _fbm(u, v, 4, 4, salt)
	var bx: int = int(u * 32.0)
	var by: int = int(v * 32.0)
	var h: int = _hash(bx, by, salt + 11)
	if h % 7 == 0:
		k += 0.18
	elif h % 11 == 0:
		k -= 0.15
	return k


## Empedrado: cantos redondeados (4×4 por casilla) con juntas y bisel.
static func _cobble(u: float, v: float, salt: int) -> float:
	var pu: float = u * 4.0
	var pv: float = v * 4.0
	var row: int = floori(pv)
	pu += 0.5 * float(row % 2)
	var col: int = floori(pu)
	var fu: float = pu - floorf(pu) - 0.5
	var fv: float = pv - floorf(pv) - 0.5
	var d: float = Vector2(fu, fv).length()
	var stone: float = smoothstep(0.5, 0.36, d)
	var light: float = 1.0 + 0.25 * (-fu - fv) * stone
	var tone: float = 0.85 + 0.25 * float(_hash(posmod(col, 4), row, salt) % 100) / 100.0
	return lerpf(0.45, tone * light, stone) * (0.94 + 0.1 * _fbm(u, v, 10, 10, salt))


## Hiladas de sillares con mortero y bisel.
static func _brick(u: float, v: float, salt: int) -> float:
	var rows: float = 4.0
	var pv: float = v * rows
	var row: int = floori(pv)
	var fv: float = pv - floorf(pv)
	var pu: float = u * 2.0 + 0.5 * float(row % 2)
	var col: int = floori(pu)
	var fu: float = pu - floorf(pu)
	var mortar: float = smoothstep(0.0, 0.07, minf(minf(fu, 1.0 - fu) * 0.5, minf(fv, 1.0 - fv)))
	var bevel: float = 1.0 + 0.1 * smoothstep(0.2, 0.0, fv) - 0.12 * smoothstep(0.8, 1.0, fv)
	var tone: float = 0.85 + 0.22 * float(_hash(posmod(col, 2), row, salt) % 100) / 100.0
	return tone * bevel * (0.92 + 0.14 * _fbm(u, v, 7, 7, salt)) * lerpf(0.5, 1.0, mortar)


## Ruido de valor (0..1) en dos octavas que se repite en u, v = 0..1 (fx, fy
## celdas de red por unidad): las texturas encajan entre casillas.
static func _fbm(u: float, v: float, fx: int, fy: int, salt: int) -> float:
	return 0.65 * _pnoise(u, v, fx, fy, salt) + 0.35 * _pnoise(u, v, fx * 2, fy * 2, salt + 1)


static func _pnoise(u: float, v: float, fx: int, fy: int, salt: int) -> float:
	var x: float = fposmod(u, 1.0) * float(fx)
	var y: float = fposmod(v, 1.0) * float(fy)
	var ix: int = floori(x)
	var iy: int = floori(y)
	var tx: float = x - float(ix)
	var ty: float = y - float(iy)
	var sx: float = tx * tx * (3.0 - 2.0 * tx)
	var sy: float = ty * ty * (3.0 - 2.0 * ty)
	var x1: int = (ix + 1) % fx
	var y1: int = (iy + 1) % fy
	var a: float = float(_hash(ix, iy, salt) % 1000) / 1000.0
	var b: float = float(_hash(x1, iy, salt) % 1000) / 1000.0
	var c: float = float(_hash(ix, y1, salt) % 1000) / 1000.0
	var d: float = float(_hash(x1, y1, salt) % 1000) / 1000.0
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)

static func _hash(x: int, y: int, salt: int) -> int:
	return PixelCanvas.hash_int(x, y, salt)


## Divide por el color medio y por 2 (el sombreador multiplica por 2 y por el
## color del vértice).
static func _normalized(src: Image, mipmaps: bool) -> Image:
	var img: Image = src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var sum: Vector3 = Vector3.ZERO
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y: int in h:
		for x: int in w:
			var c: Color = img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	var avg: Vector3 = sum / float(w * h)
	avg = Vector3(maxf(avg.x, 0.02), maxf(avg.y, 0.02), maxf(avg.z, 0.02))
	for y: int in h:
		for x: int in w:
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(clampf(c.r / avg.x * 0.5, 0.0, 1.0), clampf(c.g / avg.y * 0.5, 0.0, 1.0), clampf(c.b / avg.z * 0.5, 0.0, 1.0), 1.0))
	if mipmaps:
		img.generate_mipmaps()
	return img
