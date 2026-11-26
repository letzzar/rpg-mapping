class_name MunGeneratorG1
extends RefCounted
## Generador de mundos MUN, versión G1 (PROYECTO §6.1, F6).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en LatticeNoise, Biome,
## GeoLayers, GeoNames, GeoLinks o en el cálculo del tamaño de ALD G1) EXIGE
## GEN NUEVO: copiar a core/gen/mun/legacy/, registrar G2 y añadir seeds
## doradas nuevas. REG G2 depende de este generador (regiones de un mundo).
##
## Puro y determinista (CLAUDE.md §6): solo enteros; el azar sale del Rng
## recibido (forks con nombre) y de LatticeNoise sembrado desde ellos; los
## diccionarios solo se consultan por clave o se recorren con claves ordenadas.
## La única memoria entre llamadas es la caché del último mundo (world_snapshot,
## para REG G2), que no cambia ninguna salida.
##
## ESCALA: el mundo es siempre el planeta entero (proyección equirectangular,
## cilíndrico: la columna W−1 linda con la 0 en el relieve). El tamaño es la
## RESOLUCIÓN: 1 casilla = 24 576 / W millas (large 2048×1024: 12 mi ≈ 20 km
## en convención; tiny 256×128: 96 mi). cell_mm() la da en mm para Units.
##
## Jerarquía de semillas (§5.2): raíz ─ fork("relief", nivel) ruido de cada
## octava · fork("plates", 0) placas · fork("plate_warp", 0..1) bordes de placa
## · fork("climate", 0..1) humedad y temperatura · fork("capitals", 0) y
## fork("towns", 0) asentamientos · fork("kingdom", k) peso y estilo del reino
## k · fork("settlement", k) parámetros ALD y nombre del asentamiento k ·
## hash64(semilla, "ALD", k) & (2⁴⁰ − 1) semilla del asentamiento k.
##
## Algoritmo (N = W×H casillas; ½ = rejilla de W/2×H/2; ¼ = W/4×H/4):
## 1. Relieve: ruido fractal por refinamiento (LatticeNoise.refine) desde una
##    red de 8×4 hasta W×H con amplitudes decrecientes (AMPS). Al pasar por
##    128×64 se suman las placas: Voronoi deformado de `plates` centros
##    (continentales u oceánicas según el % de tierra) + elevación en los
##    bordes según la deriva relativa (colisión = cordillera, subducción =
##    fosa y cordillera costera, separación = rift o dorsal), suavizado. O(N).
## 2. Nivel del mar por histograma (el `land_pct` % más alto es tierra) y
##    cuantización a un byte (GeoLayers): mar 0..63, tierra 64..255. O(N).
## 3. Clima: temperatura por latitud (28 − 0,0063·lat² °C) menos 6,5 °C/km de
##    altitud; humedad en ¼ recorriendo cada fila en el sentido del viento
##    dominante (alisios, ponientes, levantes polares): el mar la recarga, la
##    tierra la gasta y las subidas la descargan (sombra orográfica); por
##    banda de latitud (células de Hadley) y ruido. O(N/16).
## 4. Biomas (Biome.classify, Whittaker) por casilla con un tramado de ±8 en
##    la humedad para que los bordes no sean escalones de 4; montaña desde
##    2 000 m, hielo bajo −10 °C, humedal en tierras bajas muy húmedas,
##    plataforma y banquisa en el mar. O(N).
## 5. Hidrología en ½: inundación por prioridad (cubetas por byte de altura,
##    cada casilla desagua en la que la descubrió: sin pozos, todo llega al
##    mar), acumulación de lluvia en orden inverso, lagos donde el relleno
##    supera 2 escalones (80 m) con humedad suficiente, ríos donde la cuenca
##    supera el umbral (`rivers`). Se pasan a W×H como cadenas de 8 vecinos
##    con su dirección, y erosionan un escalón por clase. O(N/4).
## 6. Asentamientos y reinos en ½: capitales en los mejores sitios (bioma,
##    río, costa, lago) separadas; reinos por Dijkstra multifuente con peso
##    por reino (Voronoi ponderado) y coste de terreno: montañas y ríos hacen
##    de frontera natural, el agua no se cruza (islas lejanas sin reino).
##    Después pueblos, aldeas y caseríos por puntuación y separación mínima.
##    O(N/4 + s²).
## 7. Caminos en ¼: A* (8 vecinos, coste de terreno, los caminos ya hechos
##    abaratan) por el árbol mínimo de los asentamientos de cada reino y entre
##    reinos vecinos; se pasan a W×H en escalera de 4 vecinos. O(c · A*).
## 8. Volcado: terreno (mar profundo/somero, tierra, montaña = escombros),
##    zonas MapRoom "kingdom" en room_ids, costa, y un MapChild por
##    asentamiento con su código ALD G1 canónico. O(N).

const SCALE: String = "MUN"
const GEN: int = 1

const SIZE_IDS: PackedStringArray = ["tiny", "small", "medium", "large"]
const SIZE_DIMS: Array[Vector2i] = [Vector2i(256, 128), Vector2i(512, 256), Vector2i(1024, 512), Vector2i(2048, 1024)]
## Circunferencia del planeta en millas (2048 casillas × 12 mi).
const PLANET_MI: int = 24576
## Red inicial del ruido y red de las placas.
const BASE_W: int = 8
const BASE_H: int = 4
const PLATE_W: int = 128
const PLATE_H: int = 64
## Amplitud del ruido por nivel de refinamiento (8×4, 16×8 … 2048×1024).
const AMPS: PackedInt32Array = [11000, 7000, 4200, 2600, 1700, 1100, 700, 450, 290]
## Elevación base de las placas y radio (en la red de placas) de sus bordes.
const PLATE_CONT: int = 6500
const PLATE_OCEAN: int = -6500
const PLATE_EDGE_R: int = 3

## Clima: temperatura del mar por debajo de la cual hay banquisa (°C).
const SEA_ICE_T: int = -12
## Bandas de humedad por latitud cada 10° (0..90), en %.
const LAT_BAND: PackedInt32Array = [135, 115, 70, 55, 85, 105, 100, 75, 55, 45]

## Hidrología: profundidad mínima de relleno para un lago (escalones de
## GeoLayers.LAND_STEP_M) y humedad mínima (0..100).
const LAKE_DEPTH: int = 2
const LAKE_MIN_PRECIP: int = 30
## Umbral de cuenca (lluvia acumulada, ~30 por casilla de ½) de un arroyo con
## `rivers` = 5 en el mundo large; escala con √(casillas de ½) (la densidad de
## ríos en pantalla se parece en todos los tamaños) y con 6/(rivers + 1).
const RIVER_BASE: int = 2400

## Asentamientos con `settlements` = 5 por cada 100 % de tierra del planeta.
const SETTLEMENTS_PER_PLANET: int = 480

## Bioma -> habitabilidad 0..10 (capitales y asentamientos).
const HABITABILITY: PackedInt32Array = [0, 0, 0, 0, 0, 1, 4, 2, 10, 7, 8, 5, 1, 7, 5, 3, 3, 2]
## Bioma -> coste de paso (10 = llano) para reinos y caminos; 0 = no se pasa.
const TRAVEL_COST: PackedInt32Array = [0, 0, 0, 0, 0, 20, 16, 16, 10, 12, 14, 18, 18, 11, 16, 22, 22, 40]

## Direcciones de SquareGrid (N, E, S, O, NE, SE, SO, NO): la de los rasgos.
const DX: PackedInt32Array = [0, 1, 0, -1, 1, 1, -1, -1]
const DY: PackedInt32Array = [-1, 0, 1, 0, -1, 1, 1, -1]

const STYLE_IDS: PackedStringArray = ["mixed", "human", "dwarf", "elf"]
const GRID_IDS: PackedStringArray = ["square", "hex_flat", "hex_pointy"]
const CLIMATE_IDS: PackedStringArray = ["earthlike", "cold", "warm", "arid", "wet"]


class Params:
	extends RefCounted
	var size_id: String = "large"
	var w: int = 2048
	var h: int = 1024
	var land_pct: int = 35
	var kingdoms: int = 12
	var climate: String = "earthlike"
	var plates: int = 12
	var rivers: int = 5
	var settlements: int = 5
	var child_grid: String = "square"
	var style: String = "mixed"


## Asentamiento colocado (para REG G2 y los tests).
class Settlement:
	extends RefCounted
	var cell: Vector2i = Vector2i.ZERO
	var size_id: String = ""
	var kingdom: int = 0
	var code: String = ""
	var label: String = ""
	var style: String = ""
	var score: int = 0


## Copia de solo lectura del contenido de un mundo (caché de REG G2), hecha
## con duplicate(): editar el documento después no la cambia.
class Snapshot:
	extends RefCounted
	var code: String = ""
	var w: int = 0
	var h: int = 0
	var elevation: PackedByteArray = PackedByteArray()
	var biome: PackedByteArray = PackedByteArray()
	var features: PackedByteArray = PackedByteArray()
	var kingdom_of: PackedInt32Array = PackedInt32Array()
	## Índice de reino (1..) -> nombre (índice 0 sin usar).
	var kingdom_names: PackedStringArray = PackedStringArray()
	var settlements: Array[Settlement] = []


class Result:
	extends RefCounted
	var doc: MapDocument = null
	var land_cells: int = 0
	var river_cells: int = 0
	var lake_cells: int = 0
	var road_cells: int = 0
	var kingdoms: int = 0
	var settlements: Array[Settlement] = []
	var roads_built: int = 0
	var roads_failed: int = 0
	var biome_counts: PackedInt32Array = PackedInt32Array()
	## Índice de reino (1..) por casilla de W×H y nombres (índice 0 sin usar).
	var kingdom_full: PackedInt32Array = PackedInt32Array()
	var kingdom_names: PackedStringArray = PackedStringArray()


class Ctx:
	extends RefCounted
	var p: Params = null
	var system: String = ""
	var seed_value: int = 0
	var w: int = 0
	var h: int = 0
	var elev: PackedByteArray = PackedByteArray()
	var biome: PackedByteArray = PackedByteArray()
	var terrain: PackedByteArray = PackedByteArray()
	var features: PackedByteArray = PackedByteArray()
	var temp_row: PackedInt32Array = PackedInt32Array()
	var qw: int = 0
	var qh: int = 0
	var precip_q: PackedInt32Array = PackedInt32Array()
	var tnoise_q: PackedInt32Array = PackedInt32Array()
	var hw: int = 0
	var hh: int = 0
	## Bioma de la casilla (2x, 2y) de cada casilla de ½ (con lagos).
	var hbiome: PackedByteArray = PackedByteArray()
	var helev: PackedByteArray = PackedByteArray()
	## Clase de río en ½.
	var hriver: PackedByteArray = PackedByteArray()
	## Reino (índice 1..) de cada casilla de ½ (0 = ninguno).
	var hkingdom: PackedInt32Array = PackedInt32Array()
	var kingdom_count: int = 0
	var kingdom_style: PackedStringArray = PackedStringArray()
	var kingdom_names: PackedStringArray = PackedStringArray()
	## Pares de reinos vecinos (a * 1024 + b, a < b).
	var kingdom_pairs: Dictionary[int, bool] = {}


static var _cache: Snapshot = null


# --- Entrada -----------------------------------------------------------------

## Punto de entrada registrado en GeneratorRegistry.
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var res: Result = generate_world(params_from(code), code.system, rng)
	if res == null:
		return null
	_store_snapshot(code.encode(), res)
	return res.doc


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var size_id: String = code.params["size"]
	p.size_id = size_id
	var k: int = SIZE_IDS.find(size_id)
	var dims: Vector2i = SIZE_DIMS[maxi(0, k)]
	p.w = dims.x
	p.h = dims.y
	p.land_pct = code.params["land_pct"]
	p.kingdoms = code.params["kingdoms"]
	var climate: String = code.params["climate"]
	p.climate = climate
	p.plates = code.params["plates"]
	p.rivers = code.params["rivers"]
	p.settlements = code.params["settlements"]
	var cg: String = code.params["child_grid"]
	p.child_grid = cg
	var st: String = code.params["style"]
	p.style = st
	return p


## Millas por casilla de un mundo de `width` casillas de ancho.
static func cell_miles(width: int) -> int:
	return PLANET_MI / maxi(1, width)


## Lado de una casilla de un mundo de `width` casillas en mm (Units).
static func cell_mm(width: int, mode: Units.Mode = Units.Mode.CONVENTION) -> int:
	return Units.mi_to_mm(cell_miles(width), mode)


## Mundo completo (puro). null si los parámetros no son válidos.
static func generate_world(p: Params, system: String, rng: Rng) -> Result:
	if SIZE_IDS.find(p.size_id) < 0 or CLIMATE_IDS.find(p.climate) < 0 or GRID_IDS.find(p.child_grid) < 0 or STYLE_IDS.find(p.style) < 0:
		return null
	var ctx: Ctx = Ctx.new()
	ctx.p = p
	ctx.system = system
	ctx.seed_value = rng.seed_value
	ctx.w = p.w
	ctx.h = p.h
	var res: Result = Result.new()
	var field: PackedInt32Array = _relief(ctx, rng)
	_quantize(ctx, field)
	field = PackedInt32Array()
	_climate(ctx, rng)
	_biomes(ctx, rng)
	_hydrology(ctx, res)
	_kingdoms_and_settlements(ctx, rng, res)
	_roads(ctx, res)
	_finish(ctx, res)
	return res


# --- 1. Relieve ---------------------------------------------------------------

static func _relief(ctx: Ctx, rng: Rng) -> PackedInt32Array:
	var f: PackedInt32Array = LatticeNoise.white(rng.fork("relief", 0).next_u32(), BASE_W, BASE_H, AMPS[0])
	var w: int = BASE_W
	var h: int = BASE_H
	var level: int = 0
	while w < ctx.w:
		level += 1
		f = LatticeNoise.refine(f, w, h, AMPS[level], rng.fork("relief", level).next_u32(), true)
		w *= 2
		h *= 2
		if w == PLATE_W:
			var t: PackedInt32Array = _plates(ctx, rng)
			for i: int in f.size():
				f[i] += t[i]
	return f


## Campo de placas en la red PLATE_W×PLATE_H.
static func _plates(ctx: Ctx, rng: Rng) -> PackedInt32Array:
	var p: Params = ctx.p
	var prng: Rng = rng.fork("plates", 0)
	var count: int = p.plates
	var px: PackedInt32Array = PackedInt32Array()
	var py: PackedInt32Array = PackedInt32Array()
	var vx: PackedInt32Array = PackedInt32Array()
	var vy: PackedInt32Array = PackedInt32Array()
	for _k: int in count:
		px.append(prng.bounded(PLATE_W))
		py.append(prng.range_int(4, PLATE_H - 5))
		vx.append(prng.range_int(-3, 3))
		vy.append(prng.range_int(-3, 3))
	var order: Array = range(count)
	prng.shuffle(order)
	var n_cont: int = clampi((count * (p.land_pct + 10) + 50) / 100, 1, count)
	var cont: PackedByteArray = PackedByteArray()
	cont.resize(count)
	for i: int in n_cont:
		var k: int = order[i]
		cont[k] = 1
	# Deformación de las distancias (bordes de placa sinuosos), ±9 casillas.
	var warp: Array[PackedInt32Array] = []
	for a: int in 2:
		var wr: Rng = rng.fork("plate_warp", a)
		var f: PackedInt32Array = LatticeNoise.white(wr.next_u32(), 16, 8, 5)
		var ww: int = 16
		var wh: int = 8
		for amp: int in [3, 2, 1]:
			f = LatticeNoise.refine(f, ww, wh, amp, wr.next_u32(), true)
			ww *= 2
			wh *= 2
		warp.append(f)
	var n: int = PLATE_W * PLATE_H
	var plate: PackedInt32Array = PackedInt32Array()
	plate.resize(n)
	for y: int in PLATE_H:
		for x: int in PLATE_W:
			var i: int = y * PLATE_W + x
			var qx: int = x + warp[0][i]
			var qy: int = y + warp[1][i]
			var best: int = 0
			var best_d: int = 1 << 40
			for k: int in count:
				var dx: int = posmod(qx - px[k], PLATE_W)
				dx = mini(dx, PLATE_W - dx)
				var dy: int = qy - py[k]
				var d: int = dx * dx + dy * dy
				if d < best_d:
					best_d = d
					best = k
			plate[i] = best
	# Bordes: empuje relativo según la deriva.
	var edge: PackedInt32Array = PackedInt32Array()
	edge.resize(n)
	var boundary: PackedInt32Array = PackedInt32Array()
	for y: int in PLATE_H:
		for x: int in PLATE_W:
			var i: int = y * PLATE_W + x
			var a: int = plate[i]
			var best_v: int = 0
			for d: int in 4:
				var nx: int = posmod(x + DX[d], PLATE_W)
				var ny: int = y + DY[d]
				if ny < 0 or ny >= PLATE_H:
					continue
				var b: int = plate[ny * PLATE_W + nx]
				if b == a:
					continue
				var conv: int = (vx[a] - vx[b]) * DX[d] + (vy[a] - vy[b]) * DY[d]
				var v: int = 0
				if conv > 0:
					if cont[a] == 1:
						v = conv * (1100 if cont[b] == 1 else 900)
					elif cont[b] == 1:
						v = -conv * 450
					else:
						v = conv * 500
				elif conv < 0:
					v = conv * 300 if cont[a] == 1 else -conv * 250
				else:
					v = 150 if cont[a] == 1 else 0
				if absi(v) > absi(best_v):
					best_v = v
			if best_v != 0:
				edge[i] = best_v
				boundary.append(i)
	var spread: PackedInt32Array = PackedInt32Array()
	spread.resize(n)
	var r: int = PLATE_EDGE_R
	for i: int in boundary:
		var bx: int = i % PLATE_W
		var by: int = i / PLATE_W
		var v0: int = edge[i]
		for oy: int in range(-r, r + 1):
			var yy: int = by + oy
			if yy < 0 or yy >= PLATE_H:
				continue
			for ox: int in range(-r, r + 1):
				var dist: int = absi(ox) + absi(oy)
				if dist > r:
					continue
				var j: int = yy * PLATE_W + posmod(bx + ox, PLATE_W)
				var v: int = v0 * (r + 1 - dist) / (r + 1)
				if absi(v) > absi(spread[j]):
					spread[j] = v
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(n)
	for i: int in n:
		out[i] = (PLATE_CONT if cont[plate[i]] == 1 else PLATE_OCEAN) + spread[i]
	out = LatticeNoise.blur3(out, PLATE_W, PLATE_H, true)
	return LatticeNoise.blur3(out, PLATE_W, PLATE_H, true)


# --- 2. Nivel del mar y cuantización ------------------------------------------

static func _quantize(ctx: Ctx, f: PackedInt32Array) -> void:
	var n: int = f.size()
	var lo: int = f[0]
	var hi: int = f[0]
	for i: int in range(0, n, 5):
		var v: int = f[i]
		if v < lo:
			lo = v
		elif v > hi:
			hi = v
	const BUCKETS: int = 4096
	var span: int = maxi(1, hi - lo + 1)
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(BUCKETS)
	var samples: int = 0
	for i: int in range(0, n, 5):
		var b: int = clampi((f[i] - lo) * BUCKETS / span, 0, BUCKETS - 1)
		hist[b] += 1
		samples += 1
	var thr: int = _percentile(hist, samples, 100 - ctx.p.land_pct, lo, span)
	var top: int = maxi(thr + 1, _percentile(hist, samples, 998, lo, span, 1000))
	var bottom: int = mini(thr - 1, _percentile(hist, samples, 3, lo, span, 1000))
	var land_span: int = top - thr
	var sea_span: int = thr - bottom
	var sea: int = GeoLayers.SEA_LEVEL
	var e: PackedByteArray = PackedByteArray()
	e.resize(n)
	for i: int in n:
		var v: int = f[i]
		if v >= thr:
			var dv: int = mini(v - thr, land_span)
			e[i] = sea + dv * dv / land_span * (255 - sea) / land_span
		else:
			e[i] = sea - 1 - mini(sea - 1, (thr - 1 - v) * sea / sea_span)
	ctx.elev = e


## Valor por debajo del cual queda el `pct` (de `scale`) de las muestras.
static func _percentile(hist: PackedInt32Array, samples: int, pct: int, lo: int, span: int, scale: int = 100) -> int:
	var target: int = samples * pct / scale
	var acc: int = 0
	for b: int in hist.size():
		acc += hist[b]
		if acc > target:
			return lo + (b * span + hist.size() - 1) / hist.size()
	return lo + span


# --- 3. Clima ------------------------------------------------------------------

static func _climate(ctx: Ctx, rng: Rng) -> void:
	var p: Params = ctx.p
	var shift: int = 0
	match p.climate:
		"cold":
			shift = -7
		"warm":
			shift = 5
	var temp_row: PackedInt32Array = PackedInt32Array()
	temp_row.resize(ctx.h)
	for y: int in ctx.h:
		var lat100: int = absi(9000 - 18000 * (2 * y + 1) / (2 * ctx.h))
		temp_row[y] = 28 - 63 * lat100 * lat100 / 100000000 + shift
	ctx.temp_row = temp_row
	var qw: int = ctx.w / 4
	var qh: int = ctx.h / 4
	ctx.qw = qw
	ctx.qh = qh
	var qe: PackedByteArray = PackedByteArray()
	qe.resize(qw * qh)
	for y: int in qh:
		for x: int in qw:
			qe[y * qw + x] = ctx.elev[(4 * y) * ctx.w + 4 * x]
	var moist: PackedInt32Array = PackedInt32Array()
	moist.resize(qw * qh)
	var sea: int = GeoLayers.SEA_LEVEL
	# Pérdidas por paso proporcionales a la distancia (casilla de ¼ del mundo
	# large = 48 mi): misma humedad a la misma distancia en todos los tamaños.
	var fstep: int = 512 / qw
	for y: int in qh:
		var lat: int = absi(9000 - 18000 * (2 * y + 1) / (2 * qh)) / 100
		var dir: int = 1 if lat >= 30 and lat < 60 else -1
		var row: int = y * qw
		var x0: int = 0
		while x0 < qw and qe[row + x0] >= sea:
			x0 += 1
		var m: int = 1000 if x0 < qw else 350
		if x0 >= qw:
			x0 = 0
		var prev: int = qe[row + x0]
		for step: int in qw:
			var x: int = posmod(x0 + dir * step, qw)
			var e: int = qe[row + x]
			if e < sea:
				m = mini(1000, m + 160)
				moist[row + x] = m
			else:
				var rise: int = maxi(0, e - prev)
				var rain: int = m * (18 * fstep + rise * 14) / 1000
				moist[row + x] = mini(1000, m + rain)
				m = (m - rain) * (1000 - 8 * fstep) / 1000
			prev = e
	# Bandas de latitud, ruido y clima.
	var pr: Rng = rng.fork("climate", 0)
	var noise: PackedInt32Array = _coarse_noise(pr, qw, qh, [14, 9, 6, 4, 3, 2, 1, 1])
	var tr: Rng = rng.fork("climate", 1)
	var tnoise: PackedInt32Array = _coarse_noise(tr, qw, qh, [3, 2, 1, 1, 1, 0, 0, 0])
	var mul: int = 100
	match p.climate:
		"arid":
			mul = 65
		"wet":
			mul = 135
	var precip: PackedInt32Array = PackedInt32Array()
	precip.resize(qw * qh)
	for y: int in qh:
		var lat: int = absi(9000 - 18000 * (2 * y + 1) / (2 * qh))
		var k: int = mini(8, lat / 1000)
		var t: int = lat - k * 1000
		var band: int = (LAT_BAND[k] * (1000 - t) + LAT_BAND[k + 1] * t) / 1000
		for x: int in qw:
			var i: int = y * qw + x
			precip[i] = moist[i] * band / 1000 * mul / 100 + noise[i]
	precip = LatticeNoise.blur3(precip, qw, qh, true)
	for i: int in precip.size():
		precip[i] = clampi(precip[i], 0, 100)
	ctx.precip_q = precip
	ctx.tnoise_q = tnoise


## Ruido fractal de baja resolución en w×h (w = 8·2^k, h = 4·2^k) con
## amplitudes por nivel (se usan las que hagan falta).
static func _coarse_noise(r: Rng, w: int, h: int, amps: Array) -> PackedInt32Array:
	var cw: int = BASE_W
	var ch: int = BASE_H
	var a0: int = amps[0]
	var f: PackedInt32Array = LatticeNoise.white(r.next_u32(), cw, ch, a0)
	var level: int = 0
	while cw < w:
		level += 1
		var a: int = amps[mini(level, amps.size() - 1)]
		f = LatticeNoise.refine(f, cw, ch, a, r.next_u32(), true)
		cw *= 2
		ch *= 2
	return f


# --- 4. Biomas ------------------------------------------------------------------

static func _biomes(ctx: Ctx, rng: Rng) -> void:
	var n: int = ctx.w * ctx.h
	var lut: PackedByteArray = PackedByteArray()
	lut.resize(121 * 101)
	for t: int in 121:
		for pp: int in 101:
			lut[t * 101 + pp] = Biome.classify(t - 60, pp)
	var lapse: PackedInt32Array = PackedInt32Array()
	lapse.resize(256)
	for e: int in 256:
		lapse[e] = maxi(0, e - GeoLayers.SEA_LEVEL) * GeoLayers.LAND_STEP_M * 65 / 10000
	var biome: PackedByteArray = PackedByteArray()
	biome.resize(n)
	var terrain: PackedByteArray = PackedByteArray()
	terrain.resize(n)
	var elev: PackedByteArray = ctx.elev
	var precip: PackedInt32Array = ctx.precip_q
	var tnoise: PackedInt32Array = ctx.tnoise_q
	var sea: int = GeoLayers.SEA_LEVEL
	var shelf: int = sea - 6
	var mountain: int = GeoLayers.MOUNTAIN_E
	var s: int = rng.fork("climate", 2).next_u32()
	var w: int = ctx.w
	var qw: int = ctx.qw
	for y: int in ctx.h:
		var trow: int = ctx.temp_row[y]
		var row: int = y * w
		var qrow: int = (y >> 2) * qw
		for x: int in w:
			var i: int = row + x
			var e: int = elev[i]
			if e < sea:
				if trow < SEA_ICE_T:
					biome[i] = Biome.SEA_ICE
					terrain[i] = Terrain.WATER_DEEP
				elif e >= shelf:
					biome[i] = Biome.SHALLOW_SEA
					terrain[i] = Terrain.WATER_SHALLOW
				else:
					biome[i] = Biome.OCEAN
					terrain[i] = Terrain.WATER_DEEP
				continue
			var q: int = qrow + (x >> 2)
			var t: int = trow - lapse[e] + tnoise[q]
			s = (s * LatticeNoise.LCG_MUL + LatticeNoise.LCG_INC) & LatticeNoise.MASK32
			var pp: int = precip[q] + (s >> 28) - 8
			if e >= mountain:
				biome[i] = Biome.ICE if t < Biome.T_ICE else Biome.MOUNTAIN
				terrain[i] = Terrain.RUBBLE
				continue
			terrain[i] = Terrain.FLOOR
			if pp >= 84 and e <= sea + 2 and t >= 4:
				biome[i] = Biome.WETLAND
				continue
			biome[i] = lut[clampi(t + 60, 0, 120) * 101 + clampi(pp, 0, 100)]
	ctx.biome = biome
	ctx.terrain = terrain
	var feat: PackedByteArray = PackedByteArray()
	feat.resize(n)
	ctx.features = feat


# --- 5. Hidrología ------------------------------------------------------------------

static func _hydrology(ctx: Ctx, res: Result) -> void:
	var hw: int = ctx.w / 2
	var hh: int = ctx.h / 2
	var hn: int = hw * hh
	ctx.hw = hw
	ctx.hh = hh
	var sea: int = GeoLayers.SEA_LEVEL
	var he: PackedByteArray = PackedByteArray()
	he.resize(hn)
	var hb: PackedByteArray = PackedByteArray()
	hb.resize(hn)
	for y: int in hh:
		for x: int in hw:
			var fi: int = (2 * y) * ctx.w + 2 * x
			he[y * hw + x] = ctx.elev[fi]
			hb[y * hw + x] = ctx.biome[fi]
	# Inundación por prioridad (cubetas por byte de altura, FIFO en cada una).
	var recv: PackedInt32Array = PackedInt32Array()
	recv.resize(hn)
	recv.fill(-2)
	var lvl: PackedByteArray = PackedByteArray()
	lvl.resize(hn)
	var nxt: PackedInt32Array = PackedInt32Array()
	nxt.resize(hn)
	var head: PackedInt32Array = PackedInt32Array()
	head.resize(256)
	head.fill(-1)
	var tail: PackedInt32Array = PackedInt32Array()
	tail.resize(256)
	tail.fill(-1)
	for i: int in hn:
		if he[i] < sea:
			recv[i] = -1
	for y: int in hh:
		for x: int in hw:
			var i: int = y * hw + x
			if recv[i] != -2:
				continue
			var outlet: int = -2
			for d: int in 8:
				var ny: int = y + DY[d]
				if ny < 0 or ny >= hh:
					continue
				var j: int = ny * hw + posmod(x + DX[d], hw)
				if he[j] < sea:
					outlet = j
					break
			if outlet == -2 and (y == 0 or y == hh - 1):
				outlet = -1
			if outlet == -2:
				continue
			recv[i] = outlet
			var l0: int = he[i]
			lvl[i] = l0
			nxt[i] = -1
			if tail[l0] == -1:
				head[l0] = i
			else:
				nxt[tail[l0]] = i
			tail[l0] = i
	var order: PackedInt32Array = PackedInt32Array()
	for b: int in 256:
		while head[b] != -1:
			var c: int = head[b]
			head[b] = nxt[c]
			if head[b] == -1:
				tail[b] = -1
			order.append(c)
			var cx: int = c % hw
			var cy: int = c / hw
			for d: int in 8:
				var ny: int = cy + DY[d]
				if ny < 0 or ny >= hh:
					continue
				var j: int = ny * hw + posmod(cx + DX[d], hw)
				if recv[j] != -2:
					continue
				recv[j] = c
				var l: int = maxi(he[j], b)
				lvl[j] = l
				nxt[j] = -1
				if tail[l] == -1:
					head[l] = j
				else:
					nxt[tail[l]] = j
				tail[l] = j
	# Lluvia acumulada (orden inverso: cada casilla antes que su receptora).
	var acc: PackedInt32Array = PackedInt32Array()
	acc.resize(hn)
	var qw: int = ctx.qw
	for y: int in hh:
		for x: int in hw:
			acc[y * hw + x] = ctx.precip_q[(y >> 1) * qw + (x >> 1)] + 1
	for k: int in range(order.size() - 1, -1, -1):
		var c: int = order[k]
		var r: int = recv[c]
		if r >= 0 and he[r] >= sea:
			acc[r] += acc[c]
	# Lagos y ríos.
	var lake: PackedByteArray = PackedByteArray()
	lake.resize(hn)
	for c: int in order:
		if lvl[c] - he[c] >= LAKE_DEPTH and ctx.precip_q[((c / hw) >> 1) * qw + ((c % hw) >> 1)] >= LAKE_MIN_PRECIP:
			lake[c] = 1
			hb[c] = Biome.LAKE
	var river: PackedByteArray = PackedByteArray()
	river.resize(hn)
	if ctx.p.rivers > 0:
		var thr: int = maxi(30, RIVER_BASE * 6 / (ctx.p.rivers + 1) * _isqrt(hn) / 724)
		for c: int in order:
			if lake[c] == 1:
				continue
			var a: int = acc[c]
			if a >= thr and hb[c] != Biome.ICE:
				river[c] = 3 if a >= thr * 16 else (2 if a >= thr * 4 else 1)
		# Un río sigue hasta el mar o un lago aunque cruce hielo (las fuentes no
		# nacen en el hielo, pero el cauce no se corta): de arriba abajo.
		for k: int in range(order.size() - 1, -1, -1):
			var c: int = order[k]
			var r: int = recv[c]
			if river[c] > 0 and r >= 0 and he[r] >= sea and lake[r] == 0 and river[r] < river[c]:
				river[r] = river[c]
	ctx.helev = he
	ctx.hbiome = hb
	ctx.hriver = river
	# Pasar a W×H: ríos como cadenas de 8 vecinos, erosión ligera, lagos.
	var w: int = ctx.w
	var elev: PackedByteArray = ctx.elev
	var feat: PackedByteArray = ctx.features
	for c: int in order:
		var rc: int = river[c]
		if rc == 0:
			continue
		var cx: int = c % hw
		var cy: int = c / hw
		var r: int = recv[c]
		var dir: int = -1
		if r >= 0:
			var rx: int = r % hw
			var ry: int = r / hw
			var ddx: int = rx - cx
			if ddx > 1:
				ddx = -1
			elif ddx < -1:
				ddx = 1
			dir = _dir_of(ddx, ry - cy)
		var f0: int = (2 * cy) * w + 2 * cx
		feat[f0] = GeoLayers.with_river(feat[f0], rc, dir)
		elev[f0] = maxi(sea, elev[f0] - rc)
		if dir >= 0:
			var mx: int = posmod(2 * cx + DX[dir], w)
			var my: int = 2 * cy + DY[dir]
			var mi: int = my * w + mx
			if elev[mi] >= sea:
				feat[mi] = GeoLayers.with_river(feat[mi], rc, dir)
				elev[mi] = maxi(sea, elev[mi] - rc)
				res.river_cells += 1
		res.river_cells += 1
	for c: int in order:
		if lake[c] == 0:
			continue
		var cx: int = c % hw
		var cy: int = c / hw
		for oy: int in 2:
			for ox: int in 2:
				var fi: int = (2 * cy + oy) * w + 2 * cx + ox
				if elev[fi] < sea:
					continue
				ctx.biome[fi] = Biome.LAKE
				ctx.terrain[fi] = Terrain.WATER_DEEP
				feat[fi] = 0
				res.lake_cells += 1
	ctx.elev = elev
	ctx.features = feat


## Raíz cuadrada entera (por defecto) de n >= 0.
static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


static func _dir_of(dx: int, dy: int) -> int:
	for d: int in 8:
		if DX[d] == dx and DY[d] == dy:
			return d
	return -1


# --- 6. Reinos y asentamientos -----------------------------------------------------

## Puntuación de habitabilidad de una casilla de ½ (sin azar).
static func _score(ctx: Ctx, i: int) -> int:
	var hw: int = ctx.hw
	var b: int = ctx.hbiome[i]
	var s: int = HABITABILITY[b] * 2
	if ctx.helev[i] >= GeoLayers.HILLS_E:
		s -= 3
	var x: int = i % hw
	var y: int = i / hw
	var river: bool = ctx.hriver[i] > 0
	var coast: bool = false
	var lake: bool = false
	for d: int in 8:
		var ny: int = y + DY[d]
		if ny < 0 or ny >= ctx.hh:
			continue
		var j: int = ny * hw + posmod(x + DX[d], hw)
		var nb: int = ctx.hbiome[j]
		if Biome.is_sea(nb):
			coast = true
		elif nb == Biome.LAKE:
			lake = true
		if ctx.hriver[j] > 0:
			river = true
	if river:
		s += 6
	if coast:
		s += 4
	if lake:
		s += 3
	return s


static func _is_habitable(ctx: Ctx, i: int) -> bool:
	var b: int = ctx.hbiome[i]
	return not Biome.is_water(b) and b != Biome.ICE


static func _kingdoms_and_settlements(ctx: Ctx, rng: Rng, res: Result) -> void:
	var p: Params = ctx.p
	var hn: int = ctx.hw * ctx.hh
	var land: int = 0
	for i: int in hn:
		if _is_habitable(ctx, i):
			land += 1
	ctx.hkingdom = PackedInt32Array()
	ctx.hkingdom.resize(hn)
	ctx.kingdom_names = PackedStringArray([""])
	ctx.kingdom_style = PackedStringArray([""])
	if land == 0:
		return
	# Capitales.
	var capitals: Array[int] = []
	if p.kingdoms > 0:
		var cr: Rng = rng.fork("capitals", 0)
		var cands: Array[Vector2i] = _candidates(ctx, cr, p.kingdoms * 60)
		var spacing: int = _isqrt(land / p.kingdoms) * 6 / 10
		for _attempt: int in 3:
			for cand: Vector2i in cands:
				if capitals.size() >= p.kingdoms:
					break
				if _far_enough(ctx, cand.y, capitals, spacing):
					capitals.append(cand.y)
			if capitals.size() >= p.kingdoms:
				break
			spacing = spacing * 7 / 10
	ctx.kingdom_count = capitals.size()
	res.kingdoms = capitals.size()
	for k: int in capitals.size():
		var kr: Rng = rng.fork("kingdom", k)
		var st: String = _style_for(ctx, capitals[k], kr, p.style)
		ctx.kingdom_style.append(st)
		ctx.kingdom_names.append(GeoNames.realm(kr, st))
	_grow_kingdoms(ctx, rng, capitals, land)
	# Asentamientos: capitales (ciudades) y el resto por puntuación.
	var placed: Array[int] = capitals.duplicate()
	var sizes: PackedStringArray = PackedStringArray()
	for _c: int in capitals:
		sizes.append("city")
	var target: int = land * 1000 / hn * SETTLEMENTS_PER_PLANET * p.settlements / 5 / 1000
	if target > 0:
		var tr: Rng = rng.fork("towns", 0)
		var cands: Array[Vector2i] = _candidates(ctx, tr, target * 8)
		var spacing: int = maxi(2, _isqrt(land / maxi(1, target + capitals.size())) / 2)
		var others: Array[int] = []
		for cand: Vector2i in cands:
			if others.size() >= target:
				break
			if _far_enough(ctx, cand.y, placed, spacing):
				placed.append(cand.y)
				others.append(cand.y)
		for k: int in others.size():
			var rank: int = k * 100 / maxi(1, others.size())
			sizes.append("city" if rank < 3 else ("town" if rank < 22 else ("village" if rank < 65 else "hamlet")))
	for k: int in placed.size():
		res.settlements.append(_make_settlement(ctx, rng, k, placed[k], sizes[k], k < capitals.size()))


## `count` casillas de ½ habitables al azar, ordenadas por puntuación + azar
## (0..3) de mayor a menor (desempate por índice). Vector2i(puntuación, índice).
static func _candidates(ctx: Ctx, r: Rng, count: int) -> Array[Vector2i]:
	var hn: int = ctx.hw * ctx.hh
	var out: Array[Vector2i] = []
	var tries: int = 0
	while out.size() < count and tries < count * 20:
		tries += 1
		var i: int = r.bounded(hn)
		if not _is_habitable(ctx, i):
			continue
		out.append(Vector2i(_score(ctx, i) * 4 + r.bounded(4), i))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x or (a.x == b.x and a.y < b.y))
	return out


static func _far_enough(ctx: Ctx, i: int, placed: Array[int], spacing: int) -> bool:
	var hw: int = ctx.hw
	var x: int = i % hw
	var y: int = i / hw
	var s2: int = spacing * spacing
	for j: int in placed:
		var dx: int = absi(j % hw - x)
		dx = mini(dx, hw - dx)
		var dy: int = j / hw - y
		if dx * dx + dy * dy < s2:
			return false
	return true


## Estilo cultural de un sitio: el del parámetro, o por el terreno (alto ->
## enano; bosque -> élfico a medias; si no, humano).
static func _style_for(ctx: Ctx, i: int, r: Rng, forced: String) -> String:
	if forced != "mixed":
		return forced
	if ctx.helev[i] >= GeoLayers.HILLS_E + 10 or ctx.hbiome[i] == Biome.MOUNTAIN:
		return "dwarf" if r.chance_permille(700) else "human"
	if Biome.is_forest(ctx.hbiome[i]):
		return "elf" if r.chance_permille(500) else "human"
	return "dwarf" if r.chance_permille(60) else ("elf" if r.chance_permille(60) else "human")


## Coste de entrar en la casilla de ½ `j` (10 = llano); 0 = no se pasa.
static func _step_cost(ctx: Ctx, from: int, j: int) -> int:
	var c: int = TRAVEL_COST[ctx.hbiome[j]]
	if c == 0:
		return 0
	var e: int = ctx.helev[j]
	if e >= GeoLayers.HILLS_E:
		c += (e - GeoLayers.HILLS_E) / 3
	if ctx.hriver[j] > 0 and ctx.hriver[from] == 0:
		c += 12 * ctx.hriver[j]
	return c


## Reinos: Dijkstra multifuente con cubetas circulares (Dial) en ½.
static func _grow_kingdoms(ctx: Ctx, rng: Rng, capitals: Array[int], land: int) -> void:
	var k_count: int = capitals.size()
	if k_count == 0:
		return
	var hw: int = ctx.hw
	var hh: int = ctx.hh
	var hn: int = hw * hh
	var weight: PackedInt32Array = PackedInt32Array([0])
	for k: int in k_count:
		weight.append(rng.fork("kingdom", k).fork("weight", 0).range_int(60, 150))
	const B: int = 4096
	const INF: int = 1 << 30
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(hn)
	dist.fill(INF)
	var owner: PackedInt32Array = ctx.hkingdom
	var bhead: PackedInt32Array = PackedInt32Array()
	bhead.resize(B)
	bhead.fill(-1)
	var e_cell: PackedInt32Array = PackedInt32Array()
	var e_next: PackedInt32Array = PackedInt32Array()
	var pending: int = 0
	var limit: int = _isqrt(land / k_count) * 10 * 5
	for k: int in k_count:
		var c: int = capitals[k]
		dist[c] = 0
		owner[c] = k + 1
		e_cell.append(c)
		e_next.append(bhead[0])
		bhead[0] = e_cell.size() - 1
		pending += 1
	var cur: int = 0
	while pending > 0 and cur <= limit:
		var slot: int = cur % B
		while bhead[slot] != -1:
			var e: int = bhead[slot]
			bhead[slot] = e_next[e]
			pending -= 1
			var c: int = e_cell[e]
			if dist[c] != cur:
				continue
			var k: int = owner[c]
			var cx: int = c % hw
			var cy: int = c / hw
			for d: int in 8:
				var ny: int = cy + DY[d]
				if ny < 0 or ny >= hh:
					continue
				var j: int = ny * hw + posmod(cx + DX[d], hw)
				var sc: int = _step_cost(ctx, c, j)
				if sc == 0:
					continue
				if d >= 4:
					sc = sc * 14 / 10
				var nd: int = cur + maxi(1, sc * 100 / weight[k])
				if nd >= dist[j] or nd > limit:
					continue
				dist[j] = nd
				owner[j] = k
				e_cell.append(j)
				e_next.append(bhead[nd % B])
				bhead[nd % B] = e_cell.size() - 1
				pending += 1
		cur += 1
	ctx.hkingdom = owner
	# Pares de reinos vecinos (para los caminos entre reinos).
	for y: int in hh:
		for x: int in hw:
			var a: int = owner[y * hw + x]
			if a == 0:
				continue
			for d: int in [1, 2]:
				var ny: int = y + DY[d]
				if ny >= hh:
					continue
				var b: int = owner[ny * hw + posmod(x + DX[d], hw)]
				if b != 0 and b != a:
					ctx.kingdom_pairs[mini(a, b) * 1024 + maxi(a, b)] = true


static func _make_settlement(ctx: Ctx, rng: Rng, k: int, i: int, size_id: String, capital: bool) -> Settlement:
	var p: Params = ctx.p
	var sr: Rng = rng.fork("settlement", k)
	var s: Settlement = Settlement.new()
	var hw: int = ctx.hw
	s.cell = Vector2i(2 * (i % hw), 2 * (i / hw))
	s.size_id = size_id
	s.kingdom = ctx.hkingdom[i]
	s.score = _score(ctx, i)
	var st: String = ""
	if s.kingdom > 0 and (capital or sr.chance_permille(800)):
		st = ctx.kingdom_style[s.kingdom]
	else:
		st = _style_for(ctx, i, sr, p.style)
	s.style = st
	var water: String = "none"
	if ctx.hriver[i] > 0:
		water = "river"
	else:
		var x: int = i % hw
		var y: int = i / hw
		for d: int in 8:
			var ny: int = y + DY[d]
			if ny >= 0 and ny < ctx.hh and Biome.is_sea(ctx.hbiome[ny * hw + posmod(x + DX[d], hw)]):
				water = "coast"
				break
	var wall: bool = size_id == "city" or (size_id == "town" and sr.chance_permille(500)) or (size_id == "village" and sr.chance_permille(100))
	var prosperity: String = "average"
	if capital or s.score >= 22:
		prosperity = "rich"
	elif s.score < 12:
		prosperity = "poor"
	var layout: String = "organic"
	if (size_id == "city" and sr.chance_permille(300)) or (size_id == "town" and sr.chance_permille(100)):
		layout = "grid"
	var params: Dictionary = {
		"size": size_id, "grid": p.child_grid, "style": st, "wall": wall,
		"water": water, "prosperity": prosperity, "layout": layout,
	}
	var seed_value: int = SplitMix64.hash64(ctx.seed_value, "ALD", k) & GeoLinks.CHILD_SEED_MASK
	s.code = SeedCode.create(ctx.system, "ALD", 1, params, seed_value).encode()
	s.label = GeoNames.settlement(sr, st)
	return s


# --- 7. Caminos ------------------------------------------------------------------

static func _roads(ctx: Ctx, res: Result) -> void:
	var list: Array[Settlement] = res.settlements
	if list.size() < 2:
		return
	var qw: int = ctx.qw
	var qh: int = ctx.qh
	var qn: int = qw * qh
	var cost: PackedInt32Array = PackedInt32Array()
	cost.resize(qn)
	for y: int in qh:
		for x: int in qw:
			var fi: int = (4 * y) * ctx.w + 4 * x
			var c: int = TRAVEL_COST[ctx.biome[fi]]
			var e: int = ctx.elev[fi]
			if c > 0 and e >= GeoLayers.HILLS_E:
				c += (e - GeoLayers.HILLS_E) / 3
			cost[y * qw + x] = c
	# Pares a unir: árbol mínimo por reino (Prim) y el par más cercano entre
	# reinos vecinos; los asentamientos sin reino, al más cercano.
	var pairs: Array[Vector3i] = []
	var by_kingdom: Dictionary[int, Array] = {}
	for k: int in list.size():
		var kk: int = list[k].kingdom
		if not by_kingdom.has(kk):
			by_kingdom[kk] = []
		by_kingdom[kk].append(k)
	for kk: int in range(1, ctx.kingdom_count + 1):
		if by_kingdom.has(kk):
			var members: Array = by_kingdom[kk]
			_prim(ctx, list, members, pairs)
	var pair_keys: Array = ctx.kingdom_pairs.keys()
	pair_keys.sort()
	for key: int in pair_keys:
		var a: int = key / 1024
		var b: int = key % 1024
		if not by_kingdom.has(a) or not by_kingdom.has(b):
			continue
		var best: Vector3i = Vector3i(-1, -1, 1 << 30)
		for i: int in by_kingdom[a]:
			for j: int in by_kingdom[b]:
				var d2: int = _dist2(ctx, list[i].cell, list[j].cell)
				if d2 < best.z:
					best = Vector3i(i, j, d2)
		if best.x >= 0:
			pairs.append(best)
	if by_kingdom.has(0):
		for i: int in by_kingdom[0]:
			var best: Vector3i = Vector3i(-1, -1, 1 << 30)
			for j: int in list.size():
				if j != i:
					var d2: int = _dist2(ctx, list[i].cell, list[j].cell)
					if d2 < best.z:
						best = Vector3i(i, j, d2)
			if best.x >= 0:
				pairs.append(best)
	pairs.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z < b.z or (a.z == b.z and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var max_d: int = qw / 6
	var road_q: PackedByteArray = PackedByteArray()
	road_q.resize(qn)
	var search: AStarQ = AStarQ.new(qw, qh, cost, road_q)
	for pr: Vector3i in pairs:
		var a: Vector2i = list[pr.x].cell / 4
		var b: Vector2i = list[pr.y].cell / 4
		if a == b:
			continue
		if maxi(absi(a.x - b.x), absi(a.y - b.y)) > max_d:
			continue
		var path: PackedInt32Array = search.find(a.y * qw + a.x, b.y * qw + b.x)
		if path.is_empty():
			res.roads_failed += 1
			continue
		res.roads_built += 1
		for i: int in path:
			search.road[i] = 1
		_paint_road(ctx, path, qw, res)


static func _dist2(ctx: Ctx, a: Vector2i, b: Vector2i) -> int:
	var dx: int = absi(a.x - b.x)
	dx = mini(dx, ctx.w - dx)
	var dy: int = a.y - b.y
	return dx * dx + dy * dy


## Árbol mínimo (Prim, O(m²)) de los asentamientos `members` (índices de list).
static func _prim(ctx: Ctx, list: Array[Settlement], members: Array, pairs: Array[Vector3i]) -> void:
	var m: int = members.size()
	if m < 2:
		return
	var in_tree: PackedByteArray = PackedByteArray()
	in_tree.resize(m)
	var best: PackedInt64Array = PackedInt64Array()
	best.resize(m)
	best.fill(1 << 60)
	var link: PackedInt32Array = PackedInt32Array()
	link.resize(m)
	link.fill(-1)
	best[0] = 0
	for _step: int in m:
		var u: int = -1
		for v: int in m:
			if in_tree[v] == 0 and (u < 0 or best[v] < best[u]):
				u = v
		in_tree[u] = 1
		if link[u] >= 0:
			var a: int = members[link[u]]
			var b: int = members[u]
			pairs.append(Vector3i(a, b, best[u]))
		for v: int in m:
			if in_tree[v] == 0:
				var i: int = members[u]
				var j: int = members[v]
				var d2: int = _dist2(ctx, list[i].cell, list[j].cell)
				if d2 < best[v]:
					best[v] = d2
					link[v] = u


## Pasa un camino de ¼ a W×H: de centro a centro de casilla de ¼ (+2, +2) en
## escalera de 4 vecinos (alternando x e y en las diagonales).
static func _paint_road(ctx: Ctx, path: PackedInt32Array, qw: int, res: Result) -> void:
	var w: int = ctx.w
	for k: int in range(path.size() - 1):
		var a: int = path[k]
		var b: int = path[k + 1]
		var x: int = 4 * (a % qw) + 2
		var y: int = 4 * (a / qw) + 2
		var tx: int = 4 * (b % qw) + 2
		var ty: int = 4 * (b / qw) + 2
		_mark_road(ctx, x, y, res)
		while x != tx or y != ty:
			if x != tx and (y == ty or absi(tx - x) >= absi(ty - y)):
				x += signi(tx - x)
			else:
				y += signi(ty - y)
			_mark_road(ctx, x, y, res)
	if path.size() == 1:
		_mark_road(ctx, 4 * (path[0] % qw) + 2, 4 * (path[0] / qw) + 2, res)


static func _mark_road(ctx: Ctx, x: int, y: int, res: Result) -> void:
	var i: int = y * ctx.w + x
	if ctx.elev[i] < GeoLayers.SEA_LEVEL or ctx.biome[i] == Biome.LAKE:
		return
	var f: int = ctx.features[i]
	if (f & GeoLayers.ROAD) == 0:
		ctx.features[i] = f | GeoLayers.ROAD
		res.road_cells += 1


## A* en la rejilla de ¼ (8 vecinos, sin envolver en x), con montículo
## binario propio (claves f·2²⁰ + índice: desempate determinista).
class AStarQ:
	extends RefCounted
	const MAX_EXPANSIONS: int = 40000
	var w: int = 0
	var h: int = 0
	var cost: PackedInt32Array
	var road: PackedByteArray
	var g: PackedInt32Array = PackedInt32Array()
	var came: PackedInt32Array = PackedInt32Array()
	var stamp: PackedInt32Array = PackedInt32Array()
	var closed: PackedInt32Array = PackedInt32Array()
	var search_id: int = 0
	var heap: PackedInt64Array = PackedInt64Array()

	func _init(p_w: int, p_h: int, p_cost: PackedInt32Array, p_road: PackedByteArray) -> void:
		w = p_w
		h = p_h
		cost = p_cost
		road = p_road
		g.resize(w * h)
		came.resize(w * h)
		stamp.resize(w * h)
		closed.resize(w * h)

	func _step(j: int) -> int:
		if road[j] != 0:
			return 4
		return cost[j]

	func find(start: int, goal: int) -> PackedInt32Array:
		search_id += 1
		heap.clear()
		var gx: int = goal % w
		var gy: int = goal / w
		g[start] = 0
		stamp[start] = search_id
		came[start] = -1
		_push(_h(start, gx, gy), start)
		var expansions: int = 0
		while not heap.is_empty():
			var top: int = _pop()
			var c: int = top & 0xFFFFF
			if closed[c] == search_id:
				continue
			closed[c] = search_id
			if c == goal:
				return _path(goal)
			expansions += 1
			if expansions > MAX_EXPANSIONS:
				break
			var cx: int = c % w
			var cy: int = c / w
			for d: int in 8:
				var nx: int = cx + MunGeneratorG1.DX[d]
				var ny: int = cy + MunGeneratorG1.DY[d]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				if closed[j] == search_id:
					continue
				var sc: int = _step(j)
				if sc == 0 and j != goal:
					continue
				sc = maxi(sc, 4)
				if d >= 4:
					sc = sc * 14 / 10
				var ng: int = g[c] + sc
				if stamp[j] == search_id and g[j] <= ng:
					continue
				stamp[j] = search_id
				g[j] = ng
				came[j] = c
				_push(ng + _h(j, gx, gy), j)
		return PackedInt32Array()

	func _h(i: int, gx: int, gy: int) -> int:
		var dx: int = absi(i % w - gx)
		var dy: int = absi(i / w - gy)
		return (maxi(dx, dy) * 10 + mini(dx, dy) * 4) * 7 / 10

	func _path(goal: int) -> PackedInt32Array:
		var out: PackedInt32Array = PackedInt32Array()
		var c: int = goal
		while c != -1:
			out.append(c)
			c = came[c]
		out.reverse()
		return out

	func _push(f: int, i: int) -> void:
		heap.append((f << 20) | i)
		var k: int = heap.size() - 1
		while k > 0:
			var parent: int = (k - 1) >> 1
			if heap[parent] <= heap[k]:
				break
			var t: int = heap[parent]
			heap[parent] = heap[k]
			heap[k] = t
			k = parent

	func _pop() -> int:
		var top: int = heap[0]
		var last: int = heap[heap.size() - 1]
		heap.resize(heap.size() - 1)
		if heap.is_empty():
			return top
		heap[0] = last
		var k: int = 0
		var n: int = heap.size()
		while true:
			var l: int = 2 * k + 1
			if l >= n:
				break
			var m: int = l
			if l + 1 < n and heap[l + 1] < heap[l]:
				m = l + 1
			if heap[k] <= heap[m]:
				break
			var t: int = heap[k]
			heap[k] = heap[m]
			heap[m] = t
			k = m
		return top


# --- 8. Volcado -----------------------------------------------------------------

static func _finish(ctx: Ctx, res: Result) -> void:
	var w: int = ctx.w
	var h: int = ctx.h
	var doc: MapDocument = MapDocument.create(GridGeometry.KIND_SQUARE, w, h, 1)
	var level: MapLevel = doc.level(0)
	# Zonas de reino (ids en orden de reino).
	var room_of: PackedInt32Array = PackedInt32Array([0])
	for k: int in range(1, ctx.kingdom_count + 1):
		var room: MapRoom = MapRoom.make(doc.allocate_id(), "kingdom", ctx.kingdom_names[k])
		level.add_room(room)
		room_of.append(room.id)
	var hw: int = ctx.hw
	var hk: PackedInt32Array = ctx.hkingdom
	var kingdom_full: PackedInt32Array = PackedInt32Array()
	kingdom_full.resize(w * h)
	var kingdom_idx: PackedInt32Array = PackedInt32Array()
	kingdom_idx.resize(w * h)
	var rooms_full: PackedInt32Array = PackedInt32Array()
	rooms_full.resize(w * h)
	var biome: PackedByteArray = ctx.biome
	var feat: PackedByteArray = ctx.features
	var elev: PackedByteArray = ctx.elev
	var sea: int = GeoLayers.SEA_LEVEL
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(Biome.COUNT)
	for y: int in h:
		var row: int = y * w
		var hrow: int = (y >> 1) * hw
		var up: int = maxi(0, y - 1) * w
		var dn: int = mini(h - 1, y + 1) * w
		for x: int in w:
			var i: int = row + x
			var b: int = biome[i]
			counts[b] += 1
			if elev[i] < sea or b == Biome.LAKE:
				continue
			res.land_cells += 1
			var k: int = hk[hrow + (x >> 1)]
			if k == 0 and ctx.kingdom_count > 0:
				k = _near_kingdom(ctx, x >> 1, y >> 1)
			if k > 0:
				kingdom_idx[i] = k
				rooms_full[i] = room_of[k]
			var xl: int = x - 1 if x > 0 else w - 1
			var xr: int = x + 1 if x < w - 1 else 0
			if Biome.is_sea(biome[row + xl]) or Biome.is_sea(biome[row + xr]) or Biome.is_sea(biome[up + x]) or Biome.is_sea(biome[dn + x]):
				feat[i] = feat[i] | GeoLayers.COAST
	res.biome_counts = counts
	level.terrain = ctx.terrain
	level.room_ids = rooms_full
	level.biome = biome
	level.elevation = elev
	level.features = feat
	for k: int in res.settlements.size():
		var s: Settlement = res.settlements[k]
		var code: SeedCode = SeedCode.parse(s.code)
		level.add_child_map(GeoLinks.settlement_child(doc.allocate_id(), s.cell, s.size_id, code, s.label, room_of[s.kingdom]))
	res.doc = doc
	res.kingdom_full = kingdom_idx
	res.kingdom_names = ctx.kingdom_names


## Reino de una casilla de ½ vecina (para la tierra fina junto a la costa cuya
## muestra de ½ es agua), en el orden fijo de las direcciones; 0 si ninguno.
static func _near_kingdom(ctx: Ctx, hx: int, hy: int) -> int:
	for d: int in 8:
		var ny: int = hy + DY[d]
		if ny < 0 or ny >= ctx.hh:
			continue
		var k: int = ctx.hkingdom[ny * ctx.hw + posmod(hx + DX[d], ctx.hw)]
		if k > 0:
			return k
	return 0


# --- Caché para REG G2 ------------------------------------------------------------

static func _store_snapshot(code_text: String, res: Result) -> void:
	var lvl: MapLevel = res.doc.level(0)
	var s: Snapshot = Snapshot.new()
	s.code = code_text
	s.w = res.doc.width()
	s.h = res.doc.height()
	# Copias: los Packed*Array se comparten por referencia y el documento puede
	# editarse después con comandos.
	s.elevation = lvl.elevation.duplicate()
	s.biome = lvl.biome.duplicate()
	s.features = lvl.features.duplicate()
	s.settlements = res.settlements
	s.kingdom_of = res.kingdom_full
	s.kingdom_names = res.kingdom_names
	_cache = s


## Contenido del mundo de código canónico `code_text` (MUN G1): de la caché si
## es el último generado; si no, lo genera (y lo deja en caché). null si el
## código no es válido.
static func world_snapshot(code_text: String) -> Snapshot:
	if _cache != null and _cache.code == code_text:
		return _cache
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code_text)
	if res.doc == null or _cache == null or _cache.code != code_text:
		return null
	return _cache


## Vacía la caché (tests: comprobar que REG G2 no depende de ella).
static func clear_cache() -> void:
	_cache = null
