class_name PixelObjects
extends RefCounted
## Sprites de pixel art de los muebles en vista 3/4 (ADR 047). No se dibujan
## a mano: se rasterizan los mismos modelos de primitivas de la 3D
## (data/models/objects.json, ADR 041) con un rayo por píxel algo inclinado
## hacia el norte (se ve la tapa y el frente, como en los RPG). Así
## cada mueble del catálogo, y los que se añadan, tiene su sprite coherente
## con su modelo 3D. La luz viene del noroeste, el color sale de la rampa del
## material, las aristas entre alturas distintas se marcan y el sprite lleva
## contorno y sombra arrojada de 1 px.

const PX_PER_CELL: int = 32
## Metros por casilla para que el sombreado tenga la proporción real.
const CELL_M: float = 1.5
const LIGHT: Vector3 = Vector3(-0.45, 0.8, -0.4)
const OUTLINE: Color = Color(0.09, 0.06, 0.04, 1.0)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.35)
const NO_HIT: float = -1000.0
## Inclinación del rayo (metros hacia el norte por metro de bajada): lo alto
## se dibuja más arriba que su huella, y el sprite crece por arriba.
const OBLIQUE: float = 0.45
const RAY_H: float = 10.0

static var _cache: Dictionary[String, ImageTexture] = {}


## Una primitiva lista para el rayo: base y su inversa, en metros.
class Prim:
	var shape: String = "box"
	var m: Basis = Basis.IDENTITY
	var inv: Basis = Basis.IDENTITY
	var pos: Vector3 = Vector3.ZERO
	var taper: float = 1.0
	var ramp: Array[Color] = []
	var glow: bool = false


## Sprite del objeto ocupando `cells_size` casillas (ancho × alto del mapa ya
## girado) y mirando a `angle` radianes (0 = frente al norte; el mismo giro
## que la 3D: -facing·TAU/direcciones). La textura mide cells_size·32 de ancho
## y algo más de alto: las filas de más (top_pad) van POR ENCIMA de la huella.
static func texture(catalog_id: String, cells_size: Vector2i, angle: float, models: ObjectModels = null) -> ImageTexture:
	var key: String = "%s|%dx%d|%.4f" % [catalog_id, cells_size.x, cells_size.y, angle]
	if _cache.has(key):
		return _cache[key]
	if models == null:
		models = ObjectModels.load_default()
	var cv: PixelCanvas = render(catalog_id, cells_size, angle, models)
	var tex: ImageTexture = cv.texture()
	_cache[key] = tex
	return tex


static func render(catalog_id: String, cells_size: Vector2i, angle: float, models: ObjectModels) -> PixelCanvas:
	var w: int = maxi(1, cells_size.x) * PX_PER_CELL
	var foot_h: int = maxi(1, cells_size.y) * PX_PER_CELL
	var shapes: Array[LookCatalog.Shape] = models.shapes(catalog_id)
	if shapes.is_empty():
		var fb: PixelCanvas = PixelCanvas.new(w, foot_h)
		_fallback(fb)
		return fb
	var prepared: Array[Prim] = []
	var top_m: float = 0.0
	for s: LookCatalog.Shape in shapes:
		prepared.append(_prepare(s, models))
		top_m = maxf(top_m, s.pos.y + 0.5 * maxf(s.size.y, maxf(s.size.x, s.size.z) * CELL_M))
	var pad: int = top_pad_for(top_m)
	var h: int = foot_h + pad
	var cv: PixelCanvas = PixelCanvas.new(w, h)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(w * h)
	var cols: Array[Color] = []
	cols.resize(w * h)
	var light: Vector3 = LIGHT.normalized()
	var cos_a: float = cos(-angle)
	var sin_a: float = sin(-angle)
	for j: int in h:
		for i: int in w:
			# Píxel → casillas desde el centro de la huella, girado al revés
			# del objeto para quedar en sus coordenadas (frente a -z).
			var mx: float = ((float(i) + 0.5) / PX_PER_CELL - float(w) / PX_PER_CELL * 0.5) * CELL_M
			var mz: float = ((float(j - pad) + 0.5) / PX_PER_CELL - float(foot_h) / PX_PER_CELL * 0.5) * CELL_M + RAY_H * OBLIQUE
			var o: Vector3 = Vector3(mx * cos_a + mz * sin_a, RAY_H, -mx * sin_a + mz * cos_a)
			var dir: Vector3 = Vector3(-OBLIQUE * sin_a, -1.0, -OBLIQUE * cos_a)
			var best_t: float = INF
			var best_y: float = NO_HIT
			var best_col: Color = Color(0, 0, 0, 0)
			for p: Prim in prepared:
				var hit: Array = _hit(p, o, dir)
				if hit.is_empty():
					continue
				var t: float = hit[0]
				if t >= best_t:
					continue
				best_t = t
				best_y = hit[1]
				var n: Vector3 = hit[2]
				var r: Array[Color] = p.ramp
				if p.glow:
					best_col = r[4] if (i + j) % 3 != 0 else r[3]
					continue
				var d: float = n.dot(light)
				if d >= 0.93:
					best_col = r[3]
				elif d >= 0.55:
					best_col = r[2]
				elif d >= -0.5:
					best_col = r[1]
				else:
					best_col = r[0].lerp(r[1], 0.5)
			heights[j * w + i] = best_y
			cols[j * w + i] = best_col
	# Aristas: el píxel más bajo junto a uno bastante más alto se oscurece
	# (la mesa se separa de sus patas, el cofre de su tapa).
	for j: int in h:
		for i: int in w:
			var y0: float = heights[j * w + i]
			if y0 <= NO_HIT:
				continue
			var c: Color = cols[j * w + i]
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var x2: int = i + d.x
				var y2: int = j + d.y
				if x2 < 0 or y2 < 0 or x2 >= w or y2 >= h:
					continue
				if heights[y2 * w + x2] > y0 + 0.12:
					c = c.darkened(0.35)
					break
			cv.px(i, j, c)
	# Sombra arrojada hacia el sureste de lo que se levanta del suelo.
	var shadow: PixelCanvas = PixelCanvas.new(w, h)
	for j: int in h:
		for i: int in w:
			if heights[j * w + i] > NO_HIT:
				continue
			for k: int in [1, 2]:
				var sx: int = i - k
				var sy: int = j - k
				if sx >= 0 and sy >= 0 and heights[sy * w + sx] > 0.25:
					shadow.px(i, j, SHADOW)
					break
	cv.outline(OUTLINE)
	shadow.stamp(cv, 0, 0)
	return shadow


## Datos de cada primitiva listos para el rayo: base y su inversa en metros.
static func _prepare(s: LookCatalog.Shape, models: ObjectModels) -> Prim:
	var to_m: Basis = Basis.from_scale(Vector3(CELL_M, 1.0, CELL_M))
	var rot: Basis = Basis.from_euler(Vector3(deg_to_rad(s.rot.x), deg_to_rad(s.rot.y), deg_to_rad(s.rot.z)))
	var m: Basis = to_m * rot * Basis.from_scale(Vector3(maxf(s.size.x, 0.001), maxf(s.size.y, 0.001), maxf(s.size.z, 0.001)))
	var base: Color = models.color_of(s.mat)
	var p: Prim = Prim.new()
	p.shape = s.shape
	p.m = m
	p.inv = m.inverse()
	p.pos = to_m * s.pos
	p.taper = s.taper
	p.ramp = PixelCanvas.ramp(base)
	p.glow = s.mat == "flame" or s.mat == "candle"
	return p


## Filas que se añaden por encima de la huella para lo que se levanta
## `top_m` metros (con la inclinación OBLIQUE).
static func top_pad_for(top_m: float) -> int:
	return ceili(maxf(0.0, top_m) * OBLIQUE / CELL_M * PX_PER_CELL) + 2


## Rayo desde `origin` en dirección `dir` (coordenadas del objeto, metros):
## [distancia, altura del impacto, normal] o [] si no toca la primitiva.
static func _hit(p: Prim, origin: Vector3, dir: Vector3) -> Array:
	var inv: Basis = p.inv
	var o: Vector3 = inv * (origin - p.pos)
	var d: Vector3 = inv * dir
	var res: Array = []
	match p.shape:
		"box":
			res = _box(o, d)
		"sphere":
			res = _sphere(o, d)
		"cylinder":
			res = _frustum(o, d, 1.0 if p.taper <= 0.0 else p.taper)
		"cone":
			res = _frustum(o, d, 0.0)
		_:
			res = _box(o, d)
	if res.is_empty():
		return []
	var t: float = res[0]
	var nl: Vector3 = res[1]
	var hit_world: Vector3 = p.m * (o + d * t) + p.pos
	var n: Vector3 = (inv.transposed() * nl).normalized()
	return [origin.distance_to(hit_world), hit_world.y, n]


static func _box(o: Vector3, d: Vector3) -> Array:
	var t_in: float = -INF
	var t_out: float = INF
	var n: Vector3 = Vector3.UP
	for a: int in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < -0.5 or o[a] > 0.5:
				return []
			continue
		var t1: float = (-0.5 - o[a]) / d[a]
		var t2: float = (0.5 - o[a]) / d[a]
		var sgn: float = -1.0
		if t1 > t2:
			var tmp: float = t1
			t1 = t2
			t2 = tmp
			sgn = 1.0
		if t1 > t_in:
			t_in = t1
			n = Vector3.ZERO
			n[a] = sgn
		t_out = minf(t_out, t2)
	if t_in > t_out or t_out < 0.0:
		return []
	return [maxf(t_in, 0.0), n]


static func _sphere(o: Vector3, d: Vector3) -> Array:
	var a: float = d.dot(d)
	var b: float = 2.0 * o.dot(d)
	var c: float = o.dot(o) - 0.25
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return []
	var t: float = (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0:
		return []
	return [t, (o + d * t).normalized()]


## Tronco de cono de eje y (radio 0,5 abajo y 0,5·top arriba), con tapas.
static func _frustum(o: Vector3, d: Vector3, top: float) -> Array:
	var c0: float = 0.25 * (1.0 + top)
	var c1: float = 0.5 * (top - 1.0)
	var best: float = INF
	var n: Vector3 = Vector3.UP
	# Pared: x² + z² = (c0 + c1·y)².
	var k0: float = c0 + c1 * o.y
	var a: float = d.x * d.x + d.z * d.z - c1 * c1 * d.y * d.y
	var b: float = 2.0 * (o.x * d.x + o.z * d.z - k0 * c1 * d.y)
	var c: float = o.x * o.x + o.z * o.z - k0 * k0
	if absf(a) > 1e-9:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq: float = sqrt(disc)
			for t: float in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				var p: Vector3 = o + d * t
				if t >= 0.0 and t < best and p.y >= -0.5 and p.y <= 0.5 and c0 + c1 * p.y >= 0.0:
					best = t
					n = Vector3(p.x, -c1 * (c0 + c1 * p.y), p.z)
	# Tapas.
	if absf(d.y) > 1e-9:
		for cap: float in [0.5, -0.5]:
			var t: float = (cap - o.y) / d.y
			var p: Vector3 = o + d * t
			var rad: float = c0 + c1 * cap
			if t >= 0.0 and t < best and p.x * p.x + p.z * p.z <= rad * rad:
				best = t
				n = Vector3(0, signf(cap), 0)
	if best == INF:
		return []
	return [best, n]


## Sin modelo: una caja de madera con su luz y su sombra.
static func _fallback(cv: PixelCanvas) -> void:
	var r: Array[Color] = PixelCanvas.ramp(Color("8a5f3a"))
	var m: int = 4
	cv.rect(m, m, cv.width - 2 * m, cv.height - 2 * m, r[2])
	cv.hline(m, cv.width - m - 1, m, r[3])
	cv.hline(m, cv.width - m - 1, cv.height - m - 1, r[1])
	cv.outline(OUTLINE)


static func clear_cache() -> void:
	_cache.clear()
