class_name RegGeneratorG1
extends RefCounted
## Generador de regiones REG, versión G1: HEXCRAWL INDEPENDIENTE, sin mundo
## (PROYECTO §6.2, F6). La región de un mundo es REG G2.
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en RegCommon, LatticeNoise,
## Biome, GeoLayers, GeoNames, GeoLinks o en las tablas de MunGeneratorG1 que
## usa: HABITABILITY y TRAVEL_COST) EXIGE GEN NUEVO.
##
## Puro y entero. Semillas: raíz ─ fork("relief", 0) relieve · fork("climate",
## 0) humedad · fork("shape", 0) forma del paisaje · fork("settlements", 0) ·
## fork("pois", 0) · hash64(semilla, "ALD"|"MAZ", k) & (2⁴⁰ − 1) hijos.
##
## Algoritmo (n = width × height hexágonos de 6 mi):
## 1. Altura: fBm de 4 octavas de LatticeNoise.value_noise en coordenadas
##    reales del centro (milésimas de hexágono) + forma del paisaje (costa:
##    pendiente hacia un lado elegido al azar; islas: 3-5 cúpulas sobre un mar;
##    montañas: cresta; llanura: relieve ×0,4). Nivel del mar por percentil
##    (tierra 85 % mixto, 60 % costa, 35 % islas, 95 % montaña y llanura) y
##    cuantización (GeoLayers) con altura máxima por paisaje. O(n log n).
## 2. Clima: temperatura base del clima − 6,5 °C/km; humedad base + ruido +
##    15 cerca del mar. Biomas como en MUN (Biome.classify; montaña desde
##    2 000 m, humedal en tierras bajas muy húmedas, plataforma junto a la
##    costa). O(n).
## 3. Ríos y lagos: RegCommon.hydrology (desaguan al mar o salen del mapa). O(n).
## 4. Asentamientos ALD (el mejor sitio es un pueblo), caminos A* por su árbol
##    mínimo y puntos de interés (MAZ G1 para mazmorras, cuevas, minas, ruinas,
##    guaridas y tumbas; los demás, solo marcador). O(n log n · s).

const SCALE: String = "REG"
const GEN: int = 1

const LAND_PCT: Dictionary = {"mixed": 85, "coast": 60, "islands": 35, "mountains": 95, "plains": 95}
## Altura máxima (escalones de GeoLayers sobre el mar) por paisaje.
const TOP_E: Dictionary = {"mixed": 75, "coast": 55, "islands": 60, "mountains": 140, "plains": 18}
const CLIMATE_T: Dictionary = {"temperate": 13, "cold": 1, "warm": 24, "arid": 19, "wet": 15}
const CLIMATE_P: Dictionary = {"temperate": 50, "cold": 38, "warm": 55, "arid": 10, "wet": 82}


static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var w: int = code.params["width"]
	var h: int = code.params["height"]
	var grid: String = code.params["grid"]
	var climate: String = code.params["climate"]
	var landscape: String = code.params["landscape"]
	var settlements: int = code.params["settlements"]
	var pois: int = code.params["pois"]
	var child_grid: String = code.params["child_grid"]
	var style: String = code.params["style"]
	if not LAND_PCT.has(landscape) or not CLIMATE_T.has(climate):
		return null
	var ctx: RegCommon.Ctx = RegCommon.make_ctx(grid, w, h)
	ctx.system = code.system
	ctx.child_grid = child_grid
	ctx.style = style
	_relief(ctx, rng, landscape)
	var rain: PackedInt32Array = _climate(ctx, rng, climate)
	RegCommon.hydrology(ctx, rain, 40 * 10)
	RegCommon.coast_bits(ctx)
	var count: int = settlements * ctx.n / 300
	RegCommon.place_settlements(ctx, rng.fork("settlements", 0), count, rng.seed_value, 4, true)
	RegCommon.roads(ctx)
	RegCommon.place_pois(ctx, rng.fork("pois", 0), pois * ctx.n / 250, rng.seed_value)
	return RegCommon.to_document(ctx)


## Centro del hexágono i en milésimas de hexágono (distancias reales).
static func center_milli(ctx: RegCommon.Ctx, i: int) -> Vector2i:
	var x: int = i % ctx.w
	var y: int = i / ctx.w
	if ctx.grid.pointy:
		return Vector2i(x * 1000 + (y & 1) * 500, y * 866)
	return Vector2i(x * 866, y * 1000 + (x & 1) * 500)


static func _relief(ctx: RegCommon.Ctx, rng: Rng, landscape: String) -> void:
	var s32: int = rng.fork("relief", 0).next_u32()
	var shape: Rng = rng.fork("shape", 0)
	var size: Vector2i = center_milli(ctx, ctx.n - 1) + Vector2i(1000, 1000)
	var side: int = shape.bounded(4)
	var domes: Array[Vector3i] = []
	if landscape == "islands":
		for _k: int in shape.range_int(3, 5):
			domes.append(Vector3i(shape.bounded(size.x), shape.bounded(size.y), shape.range_int(4000, 8000)))
	var ridge_y: int = shape.range_int(size.y / 4, size.y * 3 / 4)
	var v: PackedInt32Array = PackedInt32Array()
	v.resize(ctx.n)
	for i: int in ctx.n:
		var p: Vector2i = center_milli(ctx, i)
		var f: int = LatticeNoise.fbm(s32, p.x, p.y, 9000, 4)
		match landscape:
			"coast":
				var t: int = [p.x, size.x - p.x, p.y, size.y - p.y][side]
				var span: int = size.x if side < 2 else size.y
				f += 24000 * t / span - 9000
			"islands":
				var best: int = 0
				for d: Vector3i in domes:
					var dx: int = p.x - d.x
					var dy: int = p.y - d.y
					var dist: int = _isqrt(dx * dx + dy * dy)
					best = maxi(best, 20000 * maxi(0, d.z - dist) / d.z)
				f += best
			"mountains":
				f += 14000 * maxi(0, 6000 - absi(p.y - ridge_y)) / 6000
			"plains":
				f = f * 4 / 10
		v[i] = f
	var sorted: PackedInt32Array = v.duplicate()
	sorted.sort()
	var land_pct: int = LAND_PCT[landscape]
	var thr: int = sorted[clampi(ctx.n * (100 - land_pct) / 100, 0, ctx.n - 1)]
	var top: int = maxi(thr + 1, sorted[ctx.n - 1])
	var bottom: int = mini(thr - 1, sorted[0])
	var top_e: int = TOP_E[landscape]
	var sea: int = GeoLayers.SEA_LEVEL
	var elev: PackedByteArray = ctx.elev
	for i: int in ctx.n:
		var x: int = v[i]
		if x >= thr:
			var dv: int = x - thr
			elev[i] = sea + dv * dv / (top - thr) * top_e / (top - thr)
		else:
			elev[i] = sea - 1 - (thr - 1 - x) * (sea - 1) / maxi(1, thr - bottom)
	ctx.elev = elev


static func _climate(ctx: RegCommon.Ctx, rng: Rng, climate: String) -> PackedInt32Array:
	var s32: int = rng.fork("climate", 0).next_u32()
	var base_t: int = CLIMATE_T[climate]
	var base_p: int = CLIMATE_P[climate]
	var sea: int = GeoLayers.SEA_LEVEL
	var biome: PackedByteArray = ctx.biome
	var rain: PackedInt32Array = PackedInt32Array()
	rain.resize(ctx.n)
	# Distancia al mar en pasos (hasta 3), para la humedad y la plataforma.
	var near: PackedInt32Array = PackedInt32Array()
	near.resize(ctx.n)
	near.fill(99)
	for i: int in ctx.n:
		if ctx.elev[i] < sea:
			near[i] = 0
	for step: int in 3:
		for i: int in ctx.n:
			if near[i] != step:
				continue
			for d: int in 6:
				var j: int = ctx.nb[i * 6 + d]
				if j >= 0 and near[j] > step + 1:
					near[j] = step + 1
	for i: int in ctx.n:
		var e: int = ctx.elev[i]
		var p: Vector2i = center_milli(ctx, i)
		if e < sea:
			var land_near: bool = false
			for d: int in 6:
				var j: int = ctx.nb[i * 6 + d]
				if j >= 0 and ctx.elev[j] >= sea:
					land_near = true
			if base_t < -4:
				biome[i] = Biome.SEA_ICE
			elif land_near or e >= sea - 6:
				biome[i] = Biome.SHALLOW_SEA
			else:
				biome[i] = Biome.OCEAN
			continue
		var t: int = base_t - (e - sea) * GeoLayers.LAND_STEP_M * 65 / 10000 + LatticeNoise.fbm(s32 ^ 0x5A5A, p.x, p.y, 12000, 2) / 16000
		var pp: int = base_p + LatticeNoise.fbm(s32, p.x, p.y, 8000, 3) / 1500 + (15 if near[i] <= 2 else 0)
		rain[i] = clampi(pp, 0, 100)
		if e >= GeoLayers.MOUNTAIN_E:
			biome[i] = Biome.ICE if t < Biome.T_ICE else Biome.MOUNTAIN
		elif pp >= 84 and e <= sea + 2 and t >= 4:
			biome[i] = Biome.WETLAND
		else:
			biome[i] = Biome.classify(t, clampi(pp, 0, 100))
	ctx.biome = biome
	return rain


static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x
