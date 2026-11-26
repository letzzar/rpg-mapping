class_name RegGeneratorG2
extends RefCounted
## Generador de regiones REG, versión G2: REGIÓN DE UN MUNDO MUN G1 (PROYECTO
## §6.2, F6). Es a MUN G1 lo que EST G2 a EDI G1: el código lleva los
## parámetros del mundo (campos 0-8), la región (rx, ry) y los suyos; SEED es
## la semilla del mundo. La región independiente es REG G1.
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en RegCommon, en MUN G1 o en
## lo que este usa) EXIGE GEN NUEVO.
##
## Necesita el mundo: lo pide a MunGeneratorG1.world_snapshot() (caché del
## último mundo generado; si no está, lo genera: ~3,5 s el large en
## escritorio). La salida no depende de la caché (test).
##
## GEOMETRÍA: el planeta se divide en una rejilla fija de 128 × 86 regiones de
## 16 × 12 casillas del mundo large (192 × 144 mi), sea cual sea `size` (en
## los mundos de menos resolución la región cae entre menos casillas). Cada
## región son COLS × ROWS hexágonos de 6 mi (flat 37 × 24, pointy 32 × 28),
## con el centro de cada uno en coordenadas reales (milésimas de casilla
## large): un hexágono plano avanza 433 (5,196 mi) en x por columna y 500
## (6 mi) en y por fila, con las columnas impares medio hexágono más abajo
## (al revés en pointy).
##
## Algoritmo (n hexágonos):
## 1. Altura: interpolación bilineal de la elevación del mundo + ruido local
##    (±8 escalones). Bioma: una de las 4 casillas vecinas del mundo con
##    probabilidad igual a su peso bilineal (los bordes de bioma se funden), y
##    coherente con tierra/agua. Reino: el de la casilla más cercana. O(n).
## 2. Ríos y caminos del mundo: cada tramo (casilla → la siguiente) se traza
##    con la línea hex entre sus hexágonos (ríos con su dirección y clase). O(n).
## 3. Asentamientos del mundo en su hexágono (MISMO código ALD y nombre), más
##    aldeas y caseríos propios (`villages`), caminos A* que reutilizan los
##    del mundo, y puntos de interés (`pois`) como en REG G1. O(n log n · s).

const SCALE: String = "REG"
const GEN: int = 2

const REGION_W: int = 16
const REGION_H: int = 12
const REGIONS_X: int = 128
const REGIONS_Y: int = 86
const FLAT_DIMS: Vector2i = Vector2i(37, 24)
const POINTY_DIMS: Vector2i = Vector2i(32, 28)
## Campos de MUN G1 al principio del esquema (mismo orden).
const MUN_FIELDS: PackedStringArray = ["size", "land_pct", "kingdoms", "climate", "plates", "rivers", "settlements", "child_grid", "style"]


static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var world: MunGeneratorG1.Snapshot = MunGeneratorG1.world_snapshot(world_code(code).encode())
	if world == null:
		return null
	var rx: int = code.params["rx"]
	var ry: int = code.params["ry"]
	var grid: String = code.params["grid"]
	var villages: int = code.params["villages"]
	var pois: int = code.params["pois"]
	var child_grid: String = code.params["child_grid"]
	var style: String = code.params["style"]
	var dims: Vector2i = dims_of(grid)
	var ctx: RegCommon.Ctx = RegCommon.make_ctx(grid, dims.x, dims.y)
	ctx.system = code.system
	ctx.child_grid = child_grid
	ctx.style = style
	ctx.kingdom_names = world.kingdom_names
	var seed_base: int = region_seed(rng.seed_value, rx, ry)
	var local: Rng = Rng.new(seed_base)
	_sample(ctx, world, rx, ry, local)
	_trace_world_lines(ctx, world, rx, ry)
	RegCommon.coast_bits(ctx)
	var origin: Vector2i = Vector2i(rx * REGION_W * 1000, ry * REGION_H * 1000)
	for s: MunGeneratorG1.Settlement in world.settlements:
		var lm: Vector2i = _world_to_large(world, Vector2i(s.cell.x * 1000 + 500, s.cell.y * 1000 + 500)) - origin
		if lm.x < 0 or lm.y < 0 or lm.x >= REGION_W * 1000 or lm.y >= REGION_H * 1000:
			continue
		# Dentro de la ventana, el hexágono más cercano recortado al mapa (como
		# en region_child: el del borde puede quedar medio hexágono fuera).
		var hc: Vector2i = hex_at(ctx.grid.pointy, lm)
		hc = Vector2i(clampi(hc.x, 0, ctx.w - 1), clampi(hc.y, 0, ctx.h - 1))
		var i: int = ctx.grid.index_of(hc)
		if i < 0 or ctx.used[i] != 0:
			continue
		if not RegCommon.is_land(ctx, i):
			ctx.elev[i] = GeoLayers.SEA_LEVEL
			ctx.biome[i] = Biome.GRASSLAND
		RegCommon.add_settlement(ctx, i, s.size_id, s.code, s.label)
	RegCommon.place_settlements(ctx, local.fork("settlements", 0), villages * ctx.n / 400, seed_base, 3, false)
	RegCommon.roads(ctx)
	RegCommon.coast_bits(ctx)
	RegCommon.place_pois(ctx, local.fork("pois", 0), pois * ctx.n / 250, seed_base)
	return RegCommon.to_document(ctx)


## Semilla propia de la región (aldeas y puntos de interés).
static func region_seed(world_seed: int, rx: int, ry: int) -> int:
	return SplitMix64.hash64(world_seed, "REG", ry * REGIONS_X + rx)


static func dims_of(grid: String) -> Vector2i:
	return POINTY_DIMS if grid == GridGeometry.KIND_HEX_POINTY else FLAT_DIMS


## Código MUN G1 del mundo de una región (sus campos 0-8 y su semilla).
static func world_code(code: SeedCode) -> SeedCode:
	var params: Dictionary = {}
	for k: String in MUN_FIELDS:
		params[k] = code.params[k]
	return SeedCode.create(code.system, "MUN", 1, params, code.seed_value)


## Centro del hexágono (col, row) en milésimas de casilla large, relativo al
## origen de la región.
static func hex_center(pointy: bool, cell: Vector2i) -> Vector2i:
	if pointy:
		return Vector2i(250 + cell.x * 500 + (cell.y & 1) * 250, 216 + cell.y * 433)
	return Vector2i(216 + cell.x * 433, 250 + cell.y * 500 + (cell.x & 1) * 250)


## Hexágono (aprox. el más cercano) de un punto en milésimas de casilla large
## relativo al origen de la región. Puede caer fuera del mapa.
static func hex_at(pointy: bool, p: Vector2i) -> Vector2i:
	if pointy:
		var row: int = LatticeNoise.floori_div(p.y, 433)
		return Vector2i(LatticeNoise.floori_div(p.x - (row & 1) * 250, 500), row)
	var col: int = LatticeNoise.floori_div(p.x, 433)
	return Vector2i(col, LatticeNoise.floori_div(p.y - (col & 1) * 250, 500))


## Milésimas de casilla del mundo -> milésimas de casilla large.
static func _world_to_large(world: MunGeneratorG1.Snapshot, p: Vector2i) -> Vector2i:
	return Vector2i(p.x * 2048 / world.w, p.y * 2048 / world.w)


static func _sample(ctx: RegCommon.Ctx, world: MunGeneratorG1.Snapshot, rx: int, ry: int, local: Rng) -> void:
	var s_noise: int = local.fork("relief", 0).next_u32()
	var s_pick: int = local.fork("biome", 0).next_u32()
	var ww: int = world.w
	var wh: int = world.h
	var sea: int = GeoLayers.SEA_LEVEL
	var elev: PackedByteArray = ctx.elev
	var biome: PackedByteArray = ctx.biome
	var kingdom: PackedInt32Array = ctx.kingdom
	for i: int in ctx.n:
		var cell: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
		var lm: Vector2i = hex_center(ctx.grid.pointy, cell) + Vector2i(rx * REGION_W * 1000, ry * REGION_H * 1000)
		var wx: int = lm.x * ww / 2048
		var wy: int = lm.y * ww / 2048
		var u: int = wx - 500
		var v: int = wy - 500
		var x0: int = LatticeNoise.floori_div(u, 1000)
		var y0: int = LatticeNoise.floori_div(v, 1000)
		var fx: int = u - x0 * 1000
		var fy: int = v - y0 * 1000
		var xa: int = posmod(x0, ww)
		var xb: int = posmod(x0 + 1, ww)
		var ya: int = clampi(y0, 0, wh - 1)
		var yb: int = clampi(y0 + 1, 0, wh - 1)
		var idx: PackedInt32Array = PackedInt32Array([ya * ww + xa, ya * ww + xb, yb * ww + xa, yb * ww + xb])
		var wt: PackedInt32Array = PackedInt32Array([(1000 - fx) * (1000 - fy), fx * (1000 - fy), (1000 - fx) * fy, fx * fy])
		var e_sum: int = 0
		for k: int in 4:
			e_sum += world.elevation[idx[k]] * wt[k]
		var e: int = e_sum / 1000000 + LatticeNoise.fbm(s_noise, lm.x, lm.y, 3000, 2) / 4000
		e = clampi(e, 0, 255)
		# Bioma: esquina al azar con su peso; coherente con tierra/agua.
		var r: int = LatticeNoise.hash2(s_pick, cell.x, cell.y) % 1000000
		var pick: int = 3
		for k: int in 4:
			r -= wt[k]
			if r < 0:
				pick = k
				break
		var b: int = world.biome[idx[pick]]
		if (e >= sea) == Biome.is_water(b):
			var best: int = -1
			for k: int in 4:
				var bk: int = world.biome[idx[k]]
				if (e >= sea) != Biome.is_water(bk) and (best < 0 or wt[k] > wt[best]):
					best = k
			if best >= 0:
				b = world.biome[idx[best]]
			else:
				e = sea - 1 if e >= sea else sea
		elev[i] = e
		biome[i] = b
		var near: int = (clampi(LatticeNoise.floori_div(wy, 1000), 0, wh - 1)) * ww + posmod(LatticeNoise.floori_div(wx, 1000), ww)
		kingdom[i] = world.kingdom_of[near] if e >= sea else 0
	ctx.elev = elev
	ctx.biome = biome
	ctx.kingdom = kingdom


## Ríos y caminos del mundo que cruzan la ventana (con una casilla de margen).
static func _trace_world_lines(ctx: RegCommon.Ctx, world: MunGeneratorG1.Snapshot, rx: int, ry: int) -> void:
	var ww: int = world.w
	var origin: Vector2i = Vector2i(rx * REGION_W * 1000, ry * REGION_H * 1000)
	var x0: int = LatticeNoise.floori_div(rx * REGION_W * ww, 2048) - 1
	var x1: int = (rx + 1) * REGION_W * ww / 2048 + 1
	var y0: int = maxi(0, LatticeNoise.floori_div(ry * REGION_H * ww, 2048) - 1)
	var y1: int = mini(world.h - 1, (ry + 1) * REGION_H * ww / 2048 + 1)
	var feat: PackedByteArray = ctx.features
	for y: int in range(y0, y1 + 1):
		for xx: int in range(x0, x1 + 1):
			var x: int = posmod(xx, ww)
			var f: int = world.features[y * ww + x]
			var a: Vector2i = Vector2i(xx * 1000 + 500, y * 1000 + 500)
			var ha: Vector2i = hex_at(ctx.grid.pointy, _world_to_large(world, a) - origin)
			var rc: int = GeoLayers.river_class(f)
			var dir: int = GeoLayers.flow_dir(f)
			if rc > 0 and dir >= 0:
				var b: Vector2i = a + SquareGrid.DIRS[dir] * 1000
				var hb: Vector2i = hex_at(ctx.grid.pointy, _world_to_large(world, b) - origin)
				_trace(ctx, feat, ha, hb, rc, true)
			if GeoLayers.has_road(f):
				for d: int in [1, 2]:
					var nx: int = posmod(xx + SquareGrid.DIRS[d].x, ww)
					var ny: int = y + SquareGrid.DIRS[d].y
					if ny >= world.h or not GeoLayers.has_road(world.features[ny * ww + nx]):
						continue
					var b2: Vector2i = a + SquareGrid.DIRS[d] * 1000
					var hb2: Vector2i = hex_at(ctx.grid.pointy, _world_to_large(world, b2) - origin)
					_trace(ctx, feat, ha, hb2, 0, false)
	ctx.features = feat


## Marca la línea hex de `a` a `b` como río (clase y dirección hacia la
## siguiente casilla, si aún no tenía) o como camino. Solo casillas de tierra.
static func _trace(ctx: RegCommon.Ctx, feat: PackedByteArray, a: Vector2i, b: Vector2i, river: int, is_river: bool) -> void:
	var line: Array[Vector2i] = ctx.grid.line(a, b)
	for k: int in line.size():
		var i: int = ctx.grid.index_of(line[k])
		if i < 0 or not RegCommon.is_land(ctx, i):
			continue
		if not is_river:
			feat[i] = feat[i] | GeoLayers.ROAD
			continue
		var f: int = feat[i]
		var dir: int = GeoLayers.flow_dir(f)
		if dir < 0 and k + 1 < line.size():
			dir = ctx.grid.direction_between(line[k], line[k + 1])
		feat[i] = GeoLayers.with_river(f, maxi(river, GeoLayers.river_class(f)), dir)


## Hijo "región" de la casilla `cell` de un mundo MUN G1 (no se guarda en el
## documento: hay 128 × 86 regiones). Id negativo y estable (−1 − índice de
## región) para que MapNavigator recuerde las visitadas sin chocar con los
## ids del documento. `rect` = ventana de la región en casillas del mundo;
## `entrance` = `cell`; al entrar, el grupo aparece en el hexágono de `cell`.
## null si el documento no es un MUN G1.
static func region_child(world_doc: MapDocument, cell: Vector2i, grid_kind: String = GridGeometry.KIND_HEX_FLAT, villages: int = 4, pois: int = 4) -> MapChild:
	var wc: SeedCode = SeedCode.parse(world_doc.seed_code)
	if not wc.is_valid() or wc.scale != "MUN" or wc.gen_version != 1:
		return null
	var ww: int = world_doc.width()
	var lm: Vector2i = Vector2i((cell.x * 1000 + 500) * 2048 / ww, (cell.y * 1000 + 500) * 2048 / ww)
	var rx: int = clampi(lm.x / (REGION_W * 1000), 0, REGIONS_X - 1)
	var ry: int = clampi(lm.y / (REGION_H * 1000), 0, REGIONS_Y - 1)
	var params: Dictionary = wc.params.duplicate()
	params["rx"] = rx
	params["ry"] = ry
	params["grid"] = grid_kind
	params["villages"] = villages
	params["pois"] = pois
	var code: SeedCode = SeedCode.create(wc.system, "REG", 2, params, wc.seed_value)
	if not code.is_valid():
		return null
	var hex: Vector2i = hex_at(grid_kind == GridGeometry.KIND_HEX_POINTY, lm - Vector2i(rx * REGION_W * 1000, ry * REGION_H * 1000))
	var dims: Vector2i = dims_of(grid_kind)
	hex = Vector2i(clampi(hex.x, 0, dims.x - 1), clampi(hex.y, 0, dims.y - 1))
	var c: MapChild = MapChild.new()
	c.id = -1 - (ry * REGIONS_X + rx)
	c.kind = "region"
	c.seed_code = code.encode()
	var x0: int = rx * REGION_W * ww / 2048
	var y0: int = ry * REGION_H * ww / 2048
	var x1: int = maxi(x0 + 1, (rx + 1) * REGION_W * ww / 2048)
	var y1: int = mini(world_doc.height(), maxi(y0 + 1, (ry + 1) * REGION_H * ww / 2048))
	c.rect = Rect2i(x0, y0, x1 - x0, y1 - y0)
	c.entrance = cell
	c.offset = cell - hex
	c.room_id = world_doc.level(0).get_room_id(cell)
	return c
