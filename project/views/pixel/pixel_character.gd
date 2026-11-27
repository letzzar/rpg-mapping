class_name PixelCharacter
extends RefCounted
## Sprites de pixel art de 32×32 de los personajes y enemigos (ADR 047),
## generados por capas a partir de su aspecto (CharacterLook) y del
## LookCatalog: complexión, piernas, torso, cabeza, capa, armas y accesorios,
## cada pieza con los colores del personaje y su rampa (PixelCanvas.ramp).
## Los humanoides se ven de frente; los cuadrúpedos, de perfil. Las
## complexiones con modelo KayKit se dibujan con sus `pixel_parts` y, en las
## manos, con lo que lleven (ADR 049).
## Se guardan en caché por aspecto.

const SIZE: int = 32
const OUTLINE: Color = Color(0.08, 0.05, 0.05, 1.0)
const BONE: Color = Color("e8dcc0")
const GOLD: Color = Color("d9b03c")
const FLAME: Color = Color("ffb030")
const DARK: Color = Color("3a3028")
const EYE: Color = Color("1b1414")
const CACHE_MAX: int = 128

static var _cache: Dictionary[String, ImageTexture] = {}


## Textura del sprite (compartida; no modificar).
static func texture(look: CharacterLook, cat: LookCatalog = null) -> ImageTexture:
	if cat == null:
		cat = LookCatalog.load_default()
	var key: String = CanonicalJson.stringify(look.to_dict())
	if _cache.has(key):
		return _cache[key]
	var tex: ImageTexture = render(look, cat).texture()
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = tex
	return tex


static func render(look: CharacterLook, cat: LookCatalog) -> PixelCanvas:
	var cv: PixelCanvas = PixelCanvas.new(SIZE, SIZE)
	var b: LookCatalog.Body = cat.body(look.body)
	var family: String = b.family if b != null else "humanoid"
	var parts: Dictionary[String, String] = {}
	if b != null and not b.model.is_empty():
		# El cuerpo, de sus pixel_parts; las manos, de lo que lleve (ADR 049).
		parts = b.pixel_parts.duplicate()
		for slot: String in b.slots:
			parts.erase(slot)
			if look.parts.has(slot):
				parts[slot] = look.parts[slot]
	else:
		parts = look.parts.duplicate()
	var pal: Palette = Palette.new(cat, look)
	match family:
		"quadruped":
			_quadruped(cv, pal, parts)
		"flyer":
			_flyer(cv, pal, parts)
		"arachnid":
			_arachnid(cv, pal)
		"dragon":
			_dragon(cv, pal, parts)
		"blob":
			_blob(cv, pal)
		"serpent":
			_serpent(cv, pal)
		_:
			var w: float = b.width if b != null else 1.0
			var small: bool = b != null and b.id.ends_with("_small")
			var skeleton: bool = _part(parts, "torso") == "ribs" or (b != null and b.id.contains("skeleton"))
			_humanoid(cv, pal, parts, w, small, skeleton)
	cv.outline(OUTLINE)
	return cv


## Rampas de los materiales del personaje.
class Palette:
	var skin: Array[Color]
	var hair: Array[Color]
	var cloth: Array[Color]
	var trim: Array[Color]
	var metal: Array[Color]
	var leather: Array[Color]
	var wood: Array[Color]
	var bone: Array[Color]
	var gold: Array[Color]
	var flame: Array[Color]

	func _init(cat: LookCatalog, look: CharacterLook) -> void:
		skin = PixelCanvas.ramp(cat.color_of(look, "skin"))
		hair = PixelCanvas.ramp(cat.color_of(look, "hair"))
		cloth = PixelCanvas.ramp(cat.color_of(look, "cloth"))
		trim = PixelCanvas.ramp(cat.color_of(look, "trim"))
		metal = PixelCanvas.ramp(cat.color_of(look, "metal"))
		leather = PixelCanvas.ramp(cat.color_of(look, "leather"))
		wood = PixelCanvas.ramp(cat.color_of(look, "wood"))
		bone = PixelCanvas.ramp(BONE)
		gold = PixelCanvas.ramp(GOLD)
		flame = PixelCanvas.ramp(FLAME)


## Caja con volumen: luz a la izquierda y arriba, sombra a la derecha y abajo.
static func _box(cv: PixelCanvas, x: int, y: int, w: int, h: int, r: Array[Color]) -> void:
	if w <= 0 or h <= 0:
		return
	cv.rect(x, y, w, h, r[2])
	cv.vline(x, y, y + h - 1, r[3])
	if w > 2:
		cv.vline(x + w - 1, y, y + h - 1, r[1])
	if h > 2:
		cv.hline(x, x + w - 1, y + h - 1, r[1])


# --- Humanoides ---------------------------------------------------------------

## Medidas de un humanoide en el lienzo (de frente, pies en y = 29).
class Layout:
	var head_top: int
	var head_h: int
	var torso_top: int
	var torso_h: int
	var legs_top: int
	var tw: int
	var eye_y: int

	func left() -> int:
		return 16 - tw

	func right() -> int:
		return 15 + tw

	func torso_bottom() -> int:
		return torso_top + torso_h - 1

	func head_bottom() -> int:
		return head_top + head_h - 1


static func _layout(width: float, small: bool) -> Layout:
	var l: Layout = Layout.new()
	l.tw = clampi(roundi(6.0 * width), 5, 8)
	if small:
		l.head_top = 10
		l.head_h = 10
		l.torso_top = 20
		l.torso_h = 5
	elif width >= 1.2:
		l.head_top = 4
		l.head_h = 10
		l.torso_top = 14
		l.torso_h = 10
	else:
		l.head_top = 6
		l.head_h = 10
		l.torso_top = 16
		l.torso_h = 8
	l.legs_top = l.torso_top + l.torso_h
	l.eye_y = l.head_top + 5
	return l


static func _humanoid(cv: PixelCanvas, p: Palette, parts: Dictionary[String, String], width: float, small: bool, skeleton: bool) -> void:
	var l: Layout = _layout(width, small)
	var skin: Array[Color] = p.bone if skeleton else p.skin
	var torso: String = _part(parts, "torso")
	var head: String = _part(parts, "head")
	# Detrás del cuerpo: capa, mochila y carcaj.
	if _part(parts, "cloak") == "cloak":
		_cloak(cv, p, l)
	match _part(parts, "accessory"):
		"backpack":
			_box(cv, l.left() - 2, l.torso_top - 1, 3, 7, p.leather)
			_box(cv, l.right(), l.torso_top - 1, 3, 7, p.leather)
		"quiver":
			for k: int in 3:
				cv.vline(l.right() - 1 + k, l.torso_top - 6 + k, l.torso_top + 1, p.wood[2])
				cv.px(l.right() - 1 + k, l.torso_top - 7 + k, p.trim[3])
	# Piernas (una túnica larga las tapa).
	_legs(cv, p, l, _part(parts, "legs"), torso == "robe", skeleton, skin)
	# Torso y brazos.
	_torso(cv, p, l, torso, skin)
	_arms(cv, p, l, torso, skin, skeleton)
	match _part(parts, "accessory"):
		"backpack":
			cv.vline(l.left() + 2, l.torso_top, l.torso_bottom() - 1, p.leather[1])
			cv.vline(l.right() - 2, l.torso_top, l.torso_bottom() - 1, p.leather[1])
		"quiver":
			cv.line(l.left() + 1, l.torso_bottom() - 1, l.right() - 1, l.torso_top, p.leather[1])
		"pouch":
			_box(cv, l.right() - 3, l.torso_bottom() - 1, 3, 3, p.leather)
	# Cabeza.
	_head(cv, p, l, head, skin, skeleton)
	# En las manos.
	var hy: int = l.torso_bottom() + 1
	_main_hand(cv, p, l.left() - 2, hy, _part(parts, "main_hand"))
	_off_hand(cv, p, l.right() + 2, hy, _part(parts, "off_hand"))
	if _part(parts, "cloak") == "cloak":
		cv.px(15, l.torso_top, p.gold[3])
		cv.px(16, l.torso_top, p.gold[2])


static func _cloak(cv: PixelCanvas, p: Palette, l: Layout) -> void:
	for y: int in range(l.torso_top, 30):
		var spread: int = 1 + (y - l.torso_top) / 4
		cv.hline(l.left() - 1 - spread, l.right() + 1 + spread, y, p.trim[1] if y % 3 != 0 else p.trim[2])
	cv.vline(l.left() - 2, l.torso_top + 1, 28, p.trim[2])


static func _legs(cv: PixelCanvas, p: Palette, l: Layout, legs: String, robe: bool, skeleton: bool, skin: Array[Color]) -> void:
	var y0: int = l.legs_top
	var lw: int = maxi(2, l.tw - 2)
	var lx: int = 16 - 1 - lw
	var rx: int = 17
	if robe:
		_box(cv, 12, 28, 3, 2, p.leather)
		_box(cv, 17, 28, 3, 2, p.leather)
		return
	var r: Array[Color] = p.cloth
	match legs:
		"trousers":
			r = p.cloth
		"greaves":
			r = p.metal
		_:
			r = skin
	if legs.is_empty() and skeleton:
		cv.rect(lx + lw / 2, y0, 2, 29 - y0, p.bone[2])
		cv.rect(rx + lw / 2 - 1, y0, 2, 29 - y0, p.bone[2])
		cv.hline(lx + lw / 2 - 1, lx + lw / 2 + 1, 29, p.bone[1])
		cv.hline(rx + lw / 2 - 1, rx + lw / 2 + 1, 29, p.bone[1])
		return
	_box(cv, lx, y0, lw, 30 - y0, r)
	_box(cv, rx, y0, lw, 30 - y0, r)
	# Botas.
	var boots: Array[Color] = p.metal if legs == "greaves" else p.leather
	_box(cv, lx - 1, 28, lw + 1, 2, boots)
	_box(cv, rx, 28, lw + 1, 2, boots)
	if legs == "greaves":
		cv.hline(lx, lx + lw - 1, y0 + 2, p.metal[4])
		cv.hline(rx, rx + lw - 1, y0 + 2, p.metal[4])


static func _torso(cv: PixelCanvas, p: Palette, l: Layout, torso: String, skin: Array[Color]) -> void:
	var x: int = l.left()
	var w: int = l.tw * 2
	var y: int = l.torso_top
	var h: int = l.torso_h
	match torso:
		"robe":
			for yy: int in range(y, 30):
				var flare: int = (yy - y) / 4
				cv.hline(x - flare, x + w - 1 + flare, yy, p.cloth[2])
				cv.px(x - flare, yy, p.cloth[3])
				cv.px(x + w - 1 + flare, yy, p.cloth[1])
			cv.vline(15, y + 1, 29, p.trim[2])
			cv.vline(16, y + 1, 29, p.trim[1])
			var fl: int = (29 - y) / 4
			cv.hline(x - fl, x + w - 1 + fl, 29, p.trim[1])
			cv.hline(x + 2, x + w - 3, y + h - 2, p.trim[2])
		"leather_armor":
			_box(cv, x, y, w, h, p.leather)
			cv.line(x + 1, y, x + w - 2, y + h - 3, p.trim[1])
			cv.hline(x, x + w - 1, y + h - 2, p.leather[0])
			cv.px(15, y + h - 2, p.gold[3])
		"plate_armor":
			_box(cv, x, y, w, h, p.metal)
			cv.vline(15, y + 1, y + h - 3, p.metal[1])
			cv.px(x + 2, y + 1, p.metal[4])
			cv.px(x + 3, y + 1, p.metal[4])
			cv.px(x + 2, y + 2, p.metal[4])
			cv.hline(x, x + w - 1, y + h - 2, p.trim[2])
			cv.hline(x, x + w - 1, y + h - 1, p.trim[1])
		"ribs":
			_box(cv, x + 2, y, w - 4, h, PixelCanvas.ramp(DARK))
			cv.vline(15, y, y + h - 1, p.bone[2])
			cv.vline(16, y, y + h - 1, p.bone[1])
			for yy: int in range(y + 1, y + h - 2, 2):
				cv.hline(x + 2, x + w - 3, yy, p.bone[2])
				cv.px(x + 2, yy, p.bone[3])
			cv.hline(x + 3, x + w - 4, y + h - 1, p.bone[1])
		"rags":
			_box(cv, x, y, w, h, p.cloth)
			for xx: int in range(x, x + w, 2):
				cv.image.set_pixel(xx, y + h - 1, Color(0, 0, 0, 0))
			cv.rect(x + 3, y + 2, 2, 2, skin[1])
			cv.px(x + w - 4, y + 4, skin[1])
		_:
			# Túnica (y lo que no tenga dibujo propio).
			_box(cv, x, y, w, h, p.cloth)
			cv.hline(x, x + w - 1, y + h - 2, p.leather[1])
			cv.px(15, y + h - 2, p.gold[3])
			cv.px(15, y, skin[2])
			cv.px(16, y, skin[2])
			cv.px(15, y + 1, skin[1])


static func _arms(cv: PixelCanvas, p: Palette, l: Layout, torso: String, skin: Array[Color], skeleton: bool) -> void:
	var sleeve: Array[Color] = p.cloth
	match torso:
		"plate_armor":
			sleeve = p.metal
		"leather_armor":
			sleeve = p.leather
		"ribs":
			sleeve = p.bone
	var y0: int = l.torso_top + 1
	var y1: int = l.torso_bottom()
	var aw: int = 1 if skeleton else 2
	_box(cv, l.left() - aw, y0, aw, y1 - y0 + 1, sleeve)
	_box(cv, l.right() + 1, y0, aw, y1 - y0 + 1, sleeve)
	# Hombreras de la armadura.
	if torso == "plate_armor":
		_box(cv, l.left() - 2, l.torso_top, 3, 3, p.metal)
		_box(cv, l.right(), l.torso_top, 3, 3, p.metal)
	# Manos.
	cv.rect(l.left() - 2, y1 + 1, 2, 2, skin[2])
	cv.rect(l.right() + 1, y1 + 1, 2, 2, skin[1])


static func _head(cv: PixelCanvas, p: Palette, l: Layout, head: String, skin: Array[Color], skeleton: bool) -> void:
	var x0: int = 11
	var x1: int = 20
	var y0: int = l.head_top
	var y1: int = l.head_bottom()
	# Óvalo de la cara: sin las esquinas.
	for y: int in range(y0, y1 + 1):
		var inset: int = 1 if y == y0 or y == y1 else 0
		cv.hline(x0 + inset, x1 - inset, y, skin[2])
		cv.px(x0 + inset, y, skin[3])
		cv.px(x1 - inset, y, skin[1])
	cv.hline(x0 + 2, x1 - 2, y1, skin[1])
	var ey: int = l.eye_y
	if skeleton:
		cv.rect(12, ey - 1, 2, 2, skin[0])
		cv.rect(18, ey - 1, 2, 2, skin[0])
		cv.px(15, ey + 1, skin[0])
		cv.px(16, ey + 1, skin[0])
		for xx: int in range(13, 19, 2):
			cv.px(xx, ey + 3, skin[0])
	else:
		cv.px(13, ey, EYE)
		cv.px(18, ey, EYE)
		cv.px(13, ey - 1, Color(1, 1, 1, 0.5))
		cv.px(15, ey + 3, skin[1])
		cv.px(16, ey + 3, skin[1])
	match head:
		"hair_short":
			_hair(cv, p, l, false)
		"hair_long":
			_hair(cv, p, l, true)
		"hood":
			for y: int in range(y0 - 1, l.torso_top + 2):
				var inset: int = 1 if y == y0 - 1 else 0
				cv.hline(x0 - 1 + inset, x1 + 1 - inset, y, p.cloth[2])
			cv.vline(x0 - 1, y0, l.torso_top + 1, p.cloth[3])
			cv.vline(x1 + 1, y0, l.torso_top + 1, p.cloth[1])
			# Cara en sombra dentro de la capucha.
			for y: int in range(ey - 2, y1 + 1):
				cv.hline(13, 18, y, skin[1])
			cv.hline(13, 18, ey - 2, p.cloth[0])
			cv.px(14, ey, EYE)
			cv.px(17, ey, EYE)
		"helmet", "horned_helmet":
			for y: int in range(y0 - 1, ey - 1):
				var inset: int = 1 if y == y0 - 1 else 0
				cv.hline(x0 - 1 + inset, x1 + 1 - inset, y, p.metal[2])
			cv.hline(x0, x1 - 2, y0, p.metal[4])
			cv.hline(x0 - 1, x1 + 1, ey - 2, p.metal[1])
			cv.vline(15, ey - 1, ey + 1, p.metal[2])
			cv.vline(16, ey - 1, ey + 1, p.metal[1])
			cv.vline(x0 - 1, ey - 1, ey + 2, p.metal[2])
			cv.vline(x1 + 1, ey - 1, ey + 2, p.metal[1])
			if head == "horned_helmet":
				for k: int in 4:
					cv.px(x0 - 2 - k / 2, y0 - k, p.bone[2 if k < 2 else 3])
					cv.px(x1 + 2 + k / 2, y0 - k, p.bone[1 if k < 2 else 2])
		"wizard_hat":
			cv.hline(x0 - 3, x1 + 3, y0 + 1, p.cloth[1])
			cv.hline(x0 - 2, x1 + 2, y0 + 2, p.cloth[0])
			for k: int in range(0, y0 + 1):
				var half: int = 5 - k * 5 / maxi(1, y0 + 1)
				var cy: int = y0 - k
				var cx: int = 16 + k / 3
				cv.hline(cx - half, cx + half - 1, cy, p.cloth[2])
				cv.px(cx - half, cy, p.cloth[3])
			cv.hline(x0, x1, y0, p.trim[2])
		"crown":
			_hair(cv, p, l, false)
			cv.hline(x0, x1, y0 - 1, p.gold[2])
			cv.hline(x0, x1, y0, p.gold[1])
			for xx: int in [x0, 15, x1]:
				cv.px(xx, y0 - 2, p.gold[3])
			cv.px(15, y0 - 1, Color("c0303a"))
		"tusks":
			cv.px(14, ey + 3, p.bone[3])
			cv.px(17, ey + 3, p.bone[3])
			cv.px(14, ey + 2, p.bone[2])
			cv.px(17, ey + 2, p.bone[2])
		"horns_small":
			cv.px(x0 + 1, y0 - 1, p.bone[2])
			cv.px(x0, y0 - 2, p.bone[3])
			cv.px(x1 - 1, y0 - 1, p.bone[1])
			cv.px(x1, y0 - 2, p.bone[2])


static func _hair(cv: PixelCanvas, p: Palette, l: Layout, long: bool) -> void:
	var y0: int = l.head_top
	cv.hline(12, 19, y0 - 1, p.hair[2])
	for y: int in range(y0, y0 + 3):
		cv.hline(11, 20, y, p.hair[2])
	cv.hline(12, 17, y0, p.hair[3])
	# Flequillo irregular.
	cv.px(13, y0 + 3, p.hair[1])
	cv.px(16, y0 + 3, p.hair[1])
	cv.px(17, y0 + 3, p.hair[1])
	var bottom: int = l.torso_top + 3 if long else l.eye_y - 1
	cv.rect(10, y0 + 1, 2, bottom - y0, p.hair[2])
	cv.rect(20, y0 + 1, 2, bottom - y0, p.hair[1])


static func _main_hand(cv: PixelCanvas, p: Palette, x: int, hy: int, item: String) -> void:
	match item:
		"sword", "dagger":
			var blade: int = 10 if item == "sword" else 5
			cv.vline(x, hy - blade - 1, hy - 2, p.metal[3])
			cv.vline(x + 1, hy - blade - 1, hy - 2, p.metal[1])
			cv.px(x, hy - blade - 2, p.metal[4])
			cv.hline(x - 1, x + 2, hy - 1, p.gold[2] if item == "sword" else p.leather[1])
			cv.vline(x, hy, hy + 2, p.leather[2])
		"scimitar":
			for k: int in 9:
				var cx: int = x - (k * k) / 20
				cv.px(cx, hy - 2 - k, p.metal[3])
				cv.px(cx + 1, hy - 2 - k, p.metal[1])
			cv.hline(x - 1, x + 2, hy - 1, p.trim[2])
			cv.vline(x, hy, hy + 2, p.trim[1])
		"axe":
			cv.vline(x + 1, hy - 9, hy + 3, p.wood[2])
			_box(cv, x - 3, hy - 9, 4, 5, p.metal)
			cv.vline(x - 3, hy - 10, hy - 4, p.metal[4])
		"mace":
			cv.vline(x + 1, hy - 6, hy + 3, p.wood[2])
			cv.circle(float(x) + 1.5, float(hy) - 7.5, 2.5, p.metal[2])
			cv.px(x + 1, hy - 9, p.metal[4])
			cv.px(x - 1, hy - 8, p.metal[1])
			cv.px(x + 4, hy - 8, p.metal[1])
		"spear":
			cv.vline(x + 1, 2, hy + 4, p.wood[2])
			cv.px(x + 1, 0, p.metal[4])
			cv.hline(x, x + 2, 1, p.metal[2])
			cv.hline(x, x + 2, 2, p.metal[1])
		"staff":
			cv.vline(x + 1, 4, hy + 4, p.wood[2])
			cv.vline(x + 2, 5, hy + 4, p.wood[1])
			cv.circle(float(x) + 2.0, 3.0, 2.0, p.trim[3])
			cv.px(x + 1, 2, p.trim[4])
		"club":
			for k: int in 9:
				var wdt: int = 1 + k / 4
				cv.hline(x + 1 - wdt / 2, x + 1 + wdt / 2, hy + 2 - k, p.wood[2] if k % 3 != 0 else p.wood[1])
		"greatsword":
			cv.rect(x, 1, 2, hy - 3, p.metal[3])
			cv.vline(x + 1, 1, hy - 3, p.metal[1])
			cv.px(x, 0, p.metal[4])
			cv.hline(x - 2, x + 3, hy - 2, p.gold[2])
			cv.vline(x, hy - 1, hy + 3, p.leather[2])
			cv.px(x, hy + 4, p.gold[3])
		"greataxe":
			cv.vline(x + 1, 2, hy + 5, p.wood[2])
			_box(cv, x - 4, 2, 5, 7, p.metal)
			_box(cv, x + 2, 3, 3, 5, p.metal)
			cv.vline(x - 4, 1, 9, p.metal[4])
		"crossbow":
			cv.rect(x - 1, hy - 3, 3, 6, p.wood[2])
			cv.hline(x - 4, x + 4, hy - 3, p.wood[1])
			cv.px(x - 4, hy - 2, p.wood[1])
			cv.px(x + 4, hy - 2, p.wood[1])
			cv.hline(x - 3, x + 3, hy - 2, Color(0.9, 0.88, 0.8, 0.9))
			cv.px(x, hy - 4, p.metal[3])
		"wand":
			cv.vline(x + 1, hy - 6, hy + 1, p.wood[1])
			cv.px(x + 1, hy - 7, p.trim[4])
			cv.px(x, hy - 7, p.trim[2])
			cv.px(x + 2, hy - 7, p.trim[2])
		_:
			pass


static func _off_hand(cv: PixelCanvas, p: Palette, x: int, hy: int, item: String) -> void:
	match item:
		"shield_round":
			cv.circle(float(x) + 0.5, float(hy) - 2.5, 5.0, p.metal[1])
			cv.circle(float(x) + 0.5, float(hy) - 2.5, 4.0, p.wood[2])
			cv.vline(x - 1, hy - 6, hy + 1, p.wood[1])
			cv.vline(x + 2, hy - 6, hy + 1, p.wood[1])
			cv.rect(x, hy - 3, 2, 2, p.metal[3])
		"shield_kite":
			for k: int in 12:
				var half: int = 4 if k < 6 else maxi(0, 4 - (k - 5) * 2 / 3)
				cv.hline(x - half, x + half, hy - 7 + k, p.metal[2])
				cv.px(x - half, hy - 7 + k, p.metal[3])
				cv.px(x + half, hy - 7 + k, p.metal[1])
			cv.vline(x, hy - 6, hy + 3, p.trim[2])
			cv.hline(x - 3, x + 3, hy - 4, p.trim[2])
		"torch":
			cv.vline(x, hy - 5, hy + 2, p.wood[2])
			cv.rect(x - 1, hy - 8, 3, 3, p.flame[2])
			cv.px(x, hy - 9, p.flame[4])
			cv.px(x, hy - 7, p.flame[4])
		"book":
			_box(cv, x - 2, hy - 3, 5, 6, p.leather)
			cv.vline(x + 2, hy - 2, hy + 1, Color("efe4c8"))
		"bow":
			for k: int in 17:
				var dx: int = 2 - absi(k - 8) / 3
				cv.px(x + dx, hy - 10 + k, p.wood[2])
			cv.vline(x - 1, hy - 9, hy + 5, Color(0.9, 0.88, 0.8, 0.9))
		"shield_spiked":
			cv.circle(float(x) + 0.5, float(hy) - 2.5, 5.0, p.metal[1])
			cv.circle(float(x) + 0.5, float(hy) - 2.5, 4.0, p.metal[2])
			cv.rect(x, hy - 3, 2, 2, p.metal[4])
			for d: Vector2i in [Vector2i(0, -6), Vector2i(0, 5), Vector2i(-5, 0), Vector2i(6, 0)]:
				cv.px(x + d.x, hy - 3 + d.y, p.metal[4])
		"shield_square":
			_box(cv, x - 4, hy - 7, 9, 10, p.wood)
			cv.hline(x - 4, x + 4, hy - 7, p.metal[3])
			cv.hline(x - 4, x + 4, hy + 2, p.metal[1])
			cv.hline(x - 4, x + 4, hy - 3, p.metal[2])
		"mug":
			_box(cv, x - 2, hy - 3, 4, 5, p.wood)
			cv.hline(x - 2, x + 1, hy - 4, Color("f2e6c0"))
			cv.vline(x + 2, hy - 2, hy, p.wood[1])
		_:
			pass


# --- Otras familias -------------------------------------------------------------

## De perfil, mirando a la derecha.
static func _quadruped(cv: PixelCanvas, p: Palette, parts: Dictionary[String, String]) -> void:
	# Patas del otro lado, más oscuras.
	for lx: int in [9, 20]:
		cv.rect(lx, 21, 2, 8, p.skin[1])
	cv.line(5, 16, 2, 21, p.hair[2])
	cv.line(5, 17, 3, 21, p.hair[1])
	cv.ellipse(14.0, 18.0, 9.5, 5.5, p.skin[2])
	cv.ellipse(14.0, 20.0, 8.0, 2.5, p.skin[1])
	cv.ellipse(13.0, 15.5, 7.0, 2.0, p.skin[3])
	# Cuello y cabeza.
	cv.rect(21, 11, 4, 7, p.skin[2])
	cv.ellipse(25.0, 11.0, 4.0, 3.5, p.skin[2])
	cv.rect(27, 11, 4, 3, p.skin[2])
	cv.hline(27, 30, 13, p.skin[1])
	cv.px(30, 11, EYE)
	cv.px(25, 10, EYE)
	cv.vline(21, 9, 15, p.hair[2])
	cv.vline(22, 8, 12, p.hair[1])
	for lx: int in [7, 18]:
		_box(cv, lx, 21, 2, 8, p.skin)
		cv.hline(lx, lx + 1, 29, p.hair[0])
	match _part(parts, "head"):
		"ears":
			cv.px(23, 7, p.skin[2])
			cv.px(24, 7, p.skin[1])
			cv.px(23, 6, p.skin[3])
		"horns":
			cv.line(24, 8, 21, 4, p.bone[2])
			cv.line(26, 8, 28, 4, p.bone[3])
		"antlers":
			cv.line(24, 8, 22, 2, p.wood[2])
			cv.line(23, 5, 20, 4, p.wood[2])
			cv.line(26, 8, 28, 2, p.wood[3])
			cv.line(27, 5, 30, 4, p.wood[3])
	match _part(parts, "torso"):
		"saddle":
			_box(cv, 11, 12, 7, 3, p.leather)
			cv.rect(12, 15, 5, 4, p.cloth[2])
			cv.hline(12, 16, 18, p.trim[2])
		"barding":
			for y: int in range(13, 19):
				cv.hline(7 + (18 - y) / 3, 22 - (18 - y) / 3, y, p.metal[2] if y % 2 == 0 else p.metal[1])
			cv.hline(8, 21, 13, p.metal[4])
	match _part(parts, "accessory"):
		"saddlebags":
			_box(cv, 8, 17, 4, 4, p.leather)
		"collar":
			cv.vline(21, 12, 16, p.trim[2])
			cv.vline(22, 12, 16, p.trim[1])


static func _flyer(cv: PixelCanvas, p: Palette, parts: Dictionary[String, String]) -> void:
	# Alas abiertas.
	for k: int in 13:
		var y_top: int = 8 + k / 3
		var y_bot: int = 20 - k / 4
		cv.vline(13 - k, y_top, y_bot, p.hair[2] if k % 3 != 0 else p.hair[1])
		cv.vline(18 + k, y_top, y_bot, p.hair[1] if k % 3 != 0 else p.hair[0])
		cv.px(13 - k, y_top, p.hair[3])
	cv.ellipse(16.0, 19.0, 4.5, 6.5, p.skin[2])
	cv.ellipse(15.0, 18.0, 2.5, 4.0, p.skin[3])
	cv.circle(16.0, 10.0, 3.5, p.skin[2])
	cv.px(14, 9, EYE)
	cv.px(17, 9, EYE)
	cv.px(15, 12, p.gold[2])
	cv.px(16, 12, p.gold[1])
	cv.px(15, 13, p.gold[1])
	cv.hline(13, 14, 26, p.gold[2])
	cv.hline(17, 18, 26, p.gold[2])
	if _part(parts, "head") == "crest":
		cv.vline(16, 4, 6, p.trim[2])
		cv.px(17, 5, p.trim[3])
	if _part(parts, "accessory") == "flyer_collar":
		cv.hline(13, 18, 13, p.trim[2])


static func _arachnid(cv: PixelCanvas, p: Palette) -> void:
	for k: int in 4:
		var y: int = 10 + k * 3
		var knee: int = 4 + k * 4
		cv.line(12, y, 4, knee, p.skin[1])
		cv.line(4, knee, 1, knee + 7, p.skin[1])
		cv.line(19, y, 27, knee, p.skin[2])
		cv.line(27, knee, 30, knee + 7, p.skin[2])
	cv.ellipse(16.0, 21.0, 7.5, 7.0, p.skin[2])
	cv.ellipse(14.5, 19.0, 3.5, 3.0, p.skin[3])
	cv.ellipse(16.0, 11.0, 4.5, 4.0, p.skin[2])
	# Marca del abdomen (reloj de arena).
	cv.hline(15, 16, 20, p.hair[2])
	cv.hline(14, 17, 21, p.hair[2])
	cv.hline(15, 16, 22, p.hair[2])
	cv.hline(14, 17, 23, p.hair[2])
	for ex: int in [14, 15, 16, 17]:
		cv.px(ex, 10, Color("e03a2a"))
	cv.px(15, 9, Color("ff8a6a"))


static func _dragon(cv: PixelCanvas, p: Palette, parts: Dictionary[String, String]) -> void:
	# Alas detrás.
	for k: int in 12:
		cv.vline(10 - k, 4 + k / 2, 18 - k / 3, p.hair[2] if k % 3 != 0 else p.hair[1])
		cv.vline(21 + k, 4 + k / 2, 18 - k / 3, p.hair[1] if k % 3 != 0 else p.hair[0])
	cv.line(10, 4, 0, 9, p.skin[1])
	cv.line(21, 4, 31, 9, p.skin[1])
	# Cola.
	cv.line(20, 27, 27, 29, p.skin[1])
	cv.line(27, 29, 30, 25, p.skin[1])
	cv.ellipse(16.0, 20.0, 7.0, 8.5, p.skin[2])
	cv.rect(14, 15, 4, 12, p.bone[1])
	for y: int in range(16, 27, 2):
		cv.hline(14, 17, y, p.bone[2])
	cv.ellipse(16.0, 8.0, 4.5, 4.0, p.skin[2])
	cv.rect(14, 10, 4, 3, p.skin[1])
	cv.px(14, 7, Color("f0d040"))
	cv.px(18, 7, Color("f0d040"))
	cv.px(15, 11, EYE)
	cv.px(16, 11, EYE)
	if _part(parts, "head") == "dragon_horns":
		cv.line(13, 5, 11, 1, p.bone[3])
		cv.line(19, 5, 21, 1, p.bone[2])
	for fx: int in [10, 20]:
		_box(cv, fx, 26, 3, 3, p.skin)


static func _blob(cv: PixelCanvas, p: Palette) -> void:
	var a: float = 0.92
	for y: int in range(10, 30):
		for x: int in range(3, 29):
			var nx: float = (float(x) + 0.5 - 16.0) / 12.5
			var ny: float = (float(y) + 0.5 - 22.0) / 11.5
			if nx * nx + ny * ny <= 1.0:
				cv.px(x, y, Color(p.skin[2] if y < 26 else p.skin[1], a))
	cv.ellipse(16.0, 23.0, 5.0, 3.5, Color(p.hair[2], 0.8))
	cv.ellipse(10.0, 15.0, 2.5, 2.0, p.skin[4])
	cv.px(21, 13, p.skin[3])
	cv.px(23, 18, p.skin[3])
	cv.rect(12, 17, 2, 2, EYE)
	cv.rect(18, 17, 2, 2, EYE)


static func _serpent(cv: PixelCanvas, p: Palette) -> void:
	cv.ellipse(16.0, 26.0, 12.0, 3.5, p.skin[1])
	cv.ellipse(16.0, 25.0, 11.0, 2.5, p.skin[2])
	cv.ellipse(15.0, 21.5, 8.5, 2.5, p.skin[2])
	cv.ellipse(15.0, 20.5, 7.0, 1.5, p.skin[3])
	for x: int in range(6, 27, 3):
		cv.px(x, 25, p.hair[2])
	for k: int in 11:
		var x: int = 20 - k / 4
		cv.hline(x, x + 2, 20 - k, p.skin[2])
		cv.px(x, 20 - k, p.skin[3])
		cv.px(x + 1, 20 - k, p.hair[2] if k % 2 == 0 else p.skin[2])
	cv.ellipse(19.0, 7.0, 4.5, 3.0, p.skin[2])
	cv.hline(16, 21, 5, p.skin[3])
	cv.px(20, 6, Color("f0d040"))
	cv.px(17, 6, Color("f0d040"))
	cv.px(23, 8, Color("c0303a"))
	cv.px(24, 9, Color("c0303a"))


static func _part(parts: Dictionary[String, String], slot: String) -> String:
	return parts[slot] if parts.has(slot) else ""


static func clear_cache() -> void:
	_cache.clear()
