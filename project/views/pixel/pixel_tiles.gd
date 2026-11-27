class_name PixelTiles
extends RefCounted
## Tiles de pixel art de 32×32 generados por código (ADR 047): suelos (losas,
## tablones, hierba, tierra, tejado), agua, roca, escombros, foso y las tiras
## de muro, puerta y ventana para las aristas. Cada tile sale de un color base
## y su rampa (PixelCanvas.ramp), así que cualquier color de zona tiene su
## versión; hay VARIANTS variantes por tipo para que el suelo no se repita.
## Se guardan en caché por (tipo, color, variante).

const SIZE: int = 32
const VARIANTS: int = 4

const STONE: String = "stone"
const WOOD: String = "wood"
const GRASS: String = "grass"
const DIRT: String = "dirt"
const ROOF: String = "roof"
const WATER: String = "water"
const DEEP: String = "deep"
const ROCK: String = "rock"
const RUBBLE: String = "rubble"
const PIT: String = "pit"

## Colores base de los terrenos que no dependen de la zona.
const BASE_ROCK: Color = Color("5a4636")
const BASE_RUBBLE_FLOOR: Color = Color("c9b48a")
const BASE_WATER: Color = Color("4f9fc4")
const BASE_DEEP: Color = Color("235a8a")
const BASE_PIT: Color = Color("241812")
const BASE_BRICK: Color = Color("7d6a58")
const BASE_DOOR: Color = Color("9a6a32")
const BASE_IRON: Color = Color("4a4a50")
const BASE_GLASS: Color = Color("a8d4e6")

static var _cache: Dictionary[String, ImageTexture] = {}


## Tipo de suelo que corresponde a un color de relleno (mismo criterio que
## los patrones del sombreador 3D: marrón = madera, verde = hierba).
static func floor_kind(fill: Color, roof: bool = false) -> String:
	if roof:
		return ROOF
	if fill.g > fill.r * 1.08 and fill.g > fill.b * 1.05:
		return GRASS
	if fill.r > fill.g * 1.3 and fill.s > 0.25:
		return WOOD
	if fill.r > fill.g * 1.12 and fill.g > fill.b * 1.1 and fill.v < 0.75:
		return DIRT
	return STONE


## Tile del terreno (tipo de PixelTiles) con su color base y variante.
static func tile(kind: String, base: Color, variant: int) -> ImageTexture:
	var key: String = "%s|%s|%d" % [kind, PixelCanvas.color_key(base), variant % VARIANTS]
	if _cache.has(key):
		return _cache[key]
	var cv: PixelCanvas = build(kind, base, variant % VARIANTS)
	var tex: ImageTexture = cv.texture()
	_cache[key] = tex
	return tex


static func build(kind: String, base: Color, variant: int) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(SIZE, SIZE)
	var salt: int = variant * 7919 + kind.hash()
	match kind:
		STONE:
			_stone(cv, base, salt)
		WOOD:
			_wood(cv, base, salt)
		GRASS:
			_grass(cv, base, salt)
		DIRT:
			_dirt(cv, base, salt)
		ROOF:
			_roof(cv, base, salt)
		WATER:
			_water(cv, base, salt, 5)
		DEEP:
			_water(cv, base, salt, 2)
		ROCK:
			_rock(cv, base, salt)
		RUBBLE:
			_rubble(cv, base, salt)
		PIT:
			_pit(cv, base, salt)
		_:
			cv.fill(base)
	return cv


## Losas irregulares: dos hileras de 16 px con juntas desplazadas; cada losa
## con su luz arriba a la izquierda, sombra abajo a la derecha y alguna grieta.
static func _stone(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[1].lerp(r[0], 0.3))
	for row: int in 2:
		var y0: int = row * 16
		var x: int = -(PixelCanvas.hash_int(row, 0, salt) % 10)
		var k: int = 0
		while x < SIZE:
			var w: int = 10 + PixelCanvas.hash_int(row, k, salt) % 9
			var h: int = PixelCanvas.hash_int(row, k, salt + 1)
			var face: Color = r[2] if h % 3 != 0 else r[2].lerp(r[3], 0.35)
			# Interior de la losa (1 px de junta alrededor).
			for yy: int in range(y0 + 1, y0 + 15):
				for xx: int in range(x + 1, x + w):
					cv.px(_wrap(xx), yy, face)
			for xx: int in range(x + 1, x + w):
				cv.px(_wrap(xx), y0 + 1, r[3])
				cv.px(_wrap(xx), y0 + 14, r[1].lerp(r[2], 0.4))
			for yy: int in range(y0 + 1, y0 + 15):
				cv.px(_wrap(x + 1), yy, r[3])
			if h % 5 == 0:
				var cx: int = x + 3 + h % maxi(1, w - 5)
				var cy: int = y0 + 4 + (h >> 4) % 7
				cv.px(_wrap(cx), cy, r[1])
				cv.px(_wrap(cx + 1), cy + 1, r[1])
				cv.px(_wrap(cx + 1), cy + 2, r[1])
				cv.px(_wrap(cx + 2), cy + 3, r[1])
			if h % 7 == 1:
				cv.px(_wrap(x + 2 + h % maxi(1, w - 3)), y0 + 3 + (h >> 3) % 10, r[4])
			x += w
			k += 1


## Tablones horizontales de 8 px con veta, cabezas desplazadas y clavos.
static func _wood(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[2])
	for p: int in 4:
		var y0: int = p * 8
		var tone: Color = r[2] if (p + salt) % 2 == 0 else r[2].lerp(r[1], 0.25)
		cv.rect(0, y0, SIZE, 8, tone)
		cv.hline(0, SIZE - 1, y0, r[3])
		cv.hline(0, SIZE - 1, y0 + 7, r[1])
		var cut: int = PixelCanvas.hash_int(p, 1, salt) % SIZE
		cv.vline(cut, y0, y0 + 7, r[0])
		cv.px(_wrap(cut + 1), y0 + 1, r[3])
		cv.px(_wrap(cut - 2), y0 + 3, r[0])
		cv.px(_wrap(cut + 3), y0 + 3, r[0])
		for g: int in 3:
			var gx: int = PixelCanvas.hash_int(p, g + 5, salt) % SIZE
			var gy: int = y0 + 2 + (PixelCanvas.hash_int(p, g + 9, salt) % 4)
			var gl: int = 3 + PixelCanvas.hash_int(p, g + 13, salt) % 6
			for i: int in gl:
				cv.px(_wrap(gx + i), gy, r[1])


static func _grass(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[2])
	for i: int in 40:
		var h: int = PixelCanvas.hash_int(i, 3, salt)
		var x: int = h % SIZE
		var y: int = (h >> 5) % SIZE
		match h % 4:
			0:
				# Mata: una V de luz.
				cv.px(x, y, r[3])
				cv.px(_wrap(x + 2), y, r[3])
				cv.px(_wrap(x + 1), (y + 1) % SIZE, r[3])
			1:
				cv.px(x, y, r[1])
			2:
				cv.px(x, y, r[1])
				cv.px(x, (y + 1) % SIZE, r[1])
			_:
				cv.px(x, y, r[4] if h % 11 == 0 else r[3])
	# Alguna flor suelta.
	var f: int = PixelCanvas.hash_int(9, 9, salt)
	if f % 3 == 0:
		cv.px(f % SIZE, (f >> 6) % SIZE, Color("f0e070") if f % 2 == 0 else Color("e8e0f0"))


static func _dirt(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[2])
	for i: int in 34:
		var h: int = PixelCanvas.hash_int(i, 4, salt)
		var x: int = h % SIZE
		var y: int = (h >> 5) % SIZE
		cv.px(x, y, r[1] if h % 3 != 0 else r[3])
		if h % 9 == 0:
			cv.px(_wrap(x + 1), y, r[1])
			cv.px(x, (y + 1) % SIZE, r[0])


## Tejas en hileras de 8 px, en escama, desplazadas media teja por hilera.
static func _roof(cv: PixelCanvas, base: Color, _salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[1])
	for row: int in 4:
		var y0: int = row * 8
		var off: int = 4 if row % 2 == 1 else 0
		for t: int in 5:
			var x0: int = t * 8 - off
			for yy: int in range(y0, y0 + 7):
				for xx: int in range(x0 + 1, x0 + 8):
					var dy: int = yy - y0
					# Borde inferior redondeado.
					if dy >= 5 and (xx == x0 + 1 or xx == x0 + 7):
						continue
					cv.px(_wrap(xx), yy, r[2] if dy < 5 else r[1].lerp(r[2], 0.5))
			cv.hline(x0 + 2, x0 + 6, y0, r[3])
			cv.px(_wrap(x0 + 2), y0 + 1, r[4])


static func _water(cv: PixelCanvas, base: Color, salt: int, waves: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[2])
	for i: int in 12:
		var h: int = PixelCanvas.hash_int(i, 6, salt)
		cv.px(h % SIZE, (h >> 5) % SIZE, r[1])
	for i: int in waves:
		var h: int = PixelCanvas.hash_int(i, 7, salt)
		var x: int = h % SIZE
		var y: int = 2 + (i * SIZE / maxi(1, waves) + (h >> 6) % 4) % (SIZE - 3)
		var l: int = 4 + h % 4
		for k: int in l:
			cv.px(_wrap(x + k), y, r[3])
		cv.px(_wrap(x + 1), y - 1, r[4])
		cv.px(_wrap(x + l), y + 1, r[3])


## Roca vista desde arriba: bloques redondeados con luz arriba y sombra abajo.
static func _rock(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[1])
	for i: int in 7:
		var h: int = PixelCanvas.hash_int(i, 8, salt)
		var cx: float = float(h % SIZE)
		var cy: float = float((h >> 5) % SIZE)
		var rad: float = 4.0 + float(h % 5)
		for dx: int in [-SIZE, 0, SIZE]:
			for dy: int in [-SIZE, 0, SIZE]:
				cv.circle(cx + dx, cy + dy, rad, r[2])
				cv.circle(cx + dx - 1.0, cy + dy - 1.5, rad * 0.55, r[3])
	for i: int in 10:
		var h: int = PixelCanvas.hash_int(i, 10, salt)
		cv.px(h % SIZE, (h >> 5) % SIZE, r[0])
		cv.px((h >> 3) % SIZE, (h >> 9) % SIZE, r[4])


static func _rubble(cv: PixelCanvas, base: Color, salt: int) -> void:
	_dirt(cv, base, salt)
	var stone: Array[Color] = PixelCanvas.ramp(Color("8a7a68"))
	for i: int in 9:
		var h: int = PixelCanvas.hash_int(i, 11, salt)
		var x: int = 2 + h % (SIZE - 5)
		var y: int = 2 + (h >> 5) % (SIZE - 5)
		var s: int = 1 + h % 3
		cv.rect(x - 1, y + s, s + 2, 1, stone[0])
		cv.rect(x, y, s + 1, s, stone[2])
		cv.px(x, y, stone[3])


static func _pit(cv: PixelCanvas, base: Color, salt: int) -> void:
	var r: Array[Color] = PixelCanvas.ramp(base)
	cv.fill(r[0])
	for i: int in 6:
		var h: int = PixelCanvas.hash_int(i, 12, salt)
		cv.px(h % SIZE, (h >> 5) % SIZE, r[1])


static func _wrap(x: int) -> int:
	return posmod(x, SIZE)


# --- Aristas ------------------------------------------------------------------

## Tira de muro de 32×8 (ladrillos de 8×4 en hilera trabada); se repite a lo
## largo de la arista.
static func wall_strip() -> ImageTexture:
	var key: String = "edge|wall"
	if _cache.has(key):
		return _cache[key]
	var cv: PixelCanvas = PixelCanvas.new(SIZE, 8)
	var r: Array[Color] = PixelCanvas.ramp(BASE_BRICK)
	cv.fill(r[0])
	for row: int in 2:
		var off: int = 4 if row == 1 else 0
		for b: int in 5:
			var x0: int = b * 8 - off
			var face: Color = r[2] if PixelCanvas.hash_int(b, row, 5) % 3 != 0 else r[1].lerp(r[2], 0.5)
			for yy: int in range(row * 4, row * 4 + 3):
				for xx: int in range(x0, x0 + 7):
					cv.px(_wrap(xx), yy, face)
			cv.hline(x0, x0 + 5, row * 4, r[3])
	return _store(key, cv)


## Puerta cerrada de 32×8: tablones verticales con dos herrajes. `tint`
## cambia la madera (puerta secreta = azulada).
static func door_strip(tint: Color = BASE_DOOR) -> ImageTexture:
	var key: String = "edge|door|" + PixelCanvas.color_key(tint)
	if _cache.has(key):
		return _cache[key]
	var cv: PixelCanvas = PixelCanvas.new(SIZE, 8)
	var r: Array[Color] = PixelCanvas.ramp(tint)
	var iron: Array[Color] = PixelCanvas.ramp(BASE_IRON)
	cv.fill(r[2])
	for x: int in range(0, SIZE, 5):
		cv.vline(x, 0, 7, r[1])
		cv.vline(x + 1, 0, 7, r[3])
	for bx: int in [6, 24]:
		cv.rect(bx, 0, 2, 8, iron[2])
		cv.vline(bx, 0, 7, iron[3])
	cv.hline(0, SIZE - 1, 0, r[0])
	cv.hline(0, SIZE - 1, 7, r[0])
	return _store(key, cv)


## Ventana de 32×8: marco de piedra y cristal con un reflejo.
static func window_strip() -> ImageTexture:
	var key: String = "edge|window"
	if _cache.has(key):
		return _cache[key]
	var cv: PixelCanvas = PixelCanvas.new(SIZE, 8)
	var r: Array[Color] = PixelCanvas.ramp(BASE_BRICK)
	var g: Array[Color] = PixelCanvas.ramp(BASE_GLASS)
	cv.fill(r[2])
	cv.rect(6, 2, 20, 4, g[2])
	cv.hline(7, 12, 2, g[4])
	cv.vline(16, 2, 5, r[1])
	cv.hline(0, SIZE - 1, 0, r[3])
	cv.hline(0, SIZE - 1, 7, r[0])
	return _store(key, cv)


## Escalera de 32×32 vista desde arriba: peldaños de piedra que se oscurecen
## hacia donde baja (`down`) o se aclaran hacia donde sube, con una flecha.
static func stairs(down: bool) -> ImageTexture:
	var key: String = "stairs|%s" % down
	if _cache.has(key):
		return _cache[key]
	var cv: PixelCanvas = PixelCanvas.new(SIZE, SIZE)
	var r: Array[Color] = PixelCanvas.ramp(Color("a89a86"))
	for s: int in 6:
		var y0: int = 2 + s * 5
		var shade: int = clampi((4 - s) if down else (s - 1), 0, 4)
		var face: Color = r[clampi(shade, 0, 4)]
		cv.rect(3, y0, 26, 4, face)
		cv.hline(3, 28, y0, r[mini(4, shade + 1)])
		cv.hline(3, 28, y0 + 4, r[0])
	cv.vline(2, 2, 31, r[0])
	cv.vline(29, 2, 31, r[0])
	var arrow: Color = Color("f0e0b0")
	var tip_y: int = 26 if down else 6
	var dir: int = -1 if down else 1
	for k: int in 5:
		cv.hline(16 - k, 15 + k, tip_y + dir * k, arrow)
	cv.rect(14, mini(tip_y + dir * 5, tip_y + dir * 11), 4, 7, arrow)
	cv.outline(Color(0.08, 0.05, 0.05, 1.0))
	return _store(key, cv)


static func _store(key: String, cv: PixelCanvas) -> ImageTexture:
	var tex: ImageTexture = cv.texture()
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()
