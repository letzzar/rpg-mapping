class_name RegCommon
extends RefCounted
## Partes comunes de REG G1 (hexcrawl independiente) y REG G2 (región de un
## mundo MUN G1): hidrología en hex, costa, asentamientos ALD, caminos A*,
## puntos de interés y volcado al MapDocument (PROYECTO §6.2).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA EXIGE GEN NUEVO EN REG G1 Y G2.
## Puro y entero; el azar sale de los Rng recibidos.
##
## ESCALA: 1 hexágono = HEX_MI millas (6 mi = 10 km en convención) de lado
## plano a lado plano; cell_mm() para Units.

const HEX_MI: int = 6
const CHILD_SEED_MASK: int = (1 << 40) - 1

## Puntos de interés: id (kind del MapChild = "poi_" + id; i18n "POI_" + id
## en mayúsculas). Los que tienen mapa llevan un código MAZ G1 (ver _poi_code).
const POI_IDS: PackedStringArray = [
	"ruins", "tower", "shrine", "monument", "dungeon", "cave", "mine", "lair",
	"camp", "standing_stones", "oasis", "shipwreck", "tomb",
]
## Con mazmorra (layout de MAZ G1) y salas [min, max].
const POI_MAZ: Dictionary = {
	"ruins": ["mixed", 6, 12], "dungeon": ["built", 8, 20], "cave": ["cave", 5, 12],
	"mine": ["cave", 8, 16], "lair": ["cave", 3, 8], "tomb": ["built", 4, 10],
}


class Site:
	extends RefCounted
	var cell: Vector2i = Vector2i.ZERO
	## Tamaño ALD (hamlet…city) o "poi_<id>".
	var kind: String = ""
	var code: String = ""
	var label: String = ""


class Ctx:
	extends RefCounted
	var grid: HexGrid = null
	var w: int = 0
	var h: int = 0
	var n: int = 0
	## Vecino de la casilla i en la dirección d: nb[i * 6 + d] (−1 = fuera).
	var nb: PackedInt32Array = PackedInt32Array()
	var elev: PackedByteArray = PackedByteArray()
	var biome: PackedByteArray = PackedByteArray()
	var features: PackedByteArray = PackedByteArray()
	## Reino (1..) por casilla; 0 = ninguno.
	var kingdom: PackedInt32Array = PackedInt32Array()
	var kingdom_names: PackedStringArray = PackedStringArray([""])
	var system: String = "DND5"
	var child_grid: String = "square"
	var style: String = "mixed"
	var settlements: Array[Site] = []
	var pois: Array[Site] = []
	## Casillas ocupadas por un hijo (1).
	var used: PackedByteArray = PackedByteArray()


static func make_ctx(kind: String, w: int, h: int) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.grid = GridFactory.create(kind, w, h) as HexGrid
	ctx.w = w
	ctx.h = h
	ctx.n = w * h
	ctx.nb.resize(ctx.n * 6)
	for i: int in ctx.n:
		var c: Vector2i = Vector2i(i % w, i / w)
		for d: int in 6:
			ctx.nb[i * 6 + d] = ctx.grid.index_of(ctx.grid.neighbor(c, d))
	ctx.elev.resize(ctx.n)
	ctx.biome.resize(ctx.n)
	ctx.features.resize(ctx.n)
	ctx.kingdom.resize(ctx.n)
	ctx.used.resize(ctx.n)
	return ctx


## Lado de un hexágono de región en mm (Units).
static func cell_mm(mode: Units.Mode = Units.Mode.CONVENTION) -> int:
	return Units.mi_to_mm(HEX_MI, mode)


static func is_land(ctx: Ctx, i: int) -> bool:
	return not Biome.is_water(ctx.biome[i])


# --- Hidrología (REG G1) --------------------------------------------------------

## Inundación por prioridad desde el mar y el borde del mapa (los ríos pueden
## salir de la región), acumulación de `rain` y ríos donde supera `thr`;
## lagos donde el relleno supera 2 escalones con lluvia >= 30. O(n).
static func hydrology(ctx: Ctx, rain: PackedInt32Array, thr: int) -> void:
	var n: int = ctx.n
	var recv: PackedInt32Array = PackedInt32Array()
	recv.resize(n)
	recv.fill(-2)
	var lvl: PackedByteArray = PackedByteArray()
	lvl.resize(n)
	var nxt: PackedInt32Array = PackedInt32Array()
	nxt.resize(n)
	var head: PackedInt32Array = PackedInt32Array()
	head.resize(256)
	head.fill(-1)
	var tail: PackedInt32Array = PackedInt32Array()
	tail.resize(256)
	tail.fill(-1)
	for i: int in n:
		if not is_land(ctx, i):
			recv[i] = -1
	for i: int in n:
		if recv[i] != -2:
			continue
		var outlet: int = -2
		for d: int in 6:
			var j: int = ctx.nb[i * 6 + d]
			if j < 0:
				outlet = -1
				break
			if not is_land(ctx, j):
				outlet = j
				break
		if outlet == -2:
			continue
		recv[i] = outlet
		var l0: int = ctx.elev[i]
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
			for d: int in 6:
				var j: int = ctx.nb[c * 6 + d]
				if j < 0 or recv[j] != -2:
					continue
				recv[j] = c
				var l: int = maxi(ctx.elev[j], b)
				lvl[j] = l
				nxt[j] = -1
				if tail[l] == -1:
					head[l] = j
				else:
					nxt[tail[l]] = j
				tail[l] = j
	var acc: PackedInt32Array = rain.duplicate()
	for k: int in range(order.size() - 1, -1, -1):
		var c: int = order[k]
		var r: int = recv[c]
		if r >= 0 and is_land(ctx, r):
			acc[r] += acc[c]
	var feat: PackedByteArray = ctx.features
	var biome: PackedByteArray = ctx.biome
	for c: int in order:
		if lvl[c] - ctx.elev[c] >= 2 and rain[c] >= 30:
			biome[c] = Biome.LAKE
	var river: PackedByteArray = PackedByteArray()
	river.resize(n)
	for c: int in order:
		if biome[c] != Biome.LAKE and biome[c] != Biome.ICE and acc[c] >= thr:
			river[c] = 3 if acc[c] >= thr * 16 else (2 if acc[c] >= thr * 4 else 1)
	# El cauce sigue aguas abajo aunque cruce hielo (como en MUN G1).
	for k: int in range(order.size() - 1, -1, -1):
		var c: int = order[k]
		var r: int = recv[c]
		if river[c] > 0 and r >= 0 and is_land(ctx, r) and biome[r] != Biome.LAKE and river[r] < river[c]:
			river[r] = river[c]
	for c: int in order:
		if river[c] == 0:
			continue
		var cls: int = river[c]
		var r: int = recv[c]
		var dir: int = -1
		if r >= 0:
			for d: int in 6:
				if ctx.nb[c * 6 + d] == r:
					dir = d
		else:
			for d: int in 6:
				if ctx.nb[c * 6 + d] < 0:
					dir = d
					break
		feat[c] = GeoLayers.with_river(feat[c], cls, dir)
	ctx.features = feat
	ctx.biome = biome


## Bit de costa: tierra con un vecino de mar (no lago).
static func coast_bits(ctx: Ctx) -> void:
	var feat: PackedByteArray = ctx.features
	for i: int in ctx.n:
		if not is_land(ctx, i):
			feat[i] = feat[i] & ~GeoLayers.COAST
			continue
		var coast: bool = false
		for d: int in 6:
			var j: int = ctx.nb[i * 6 + d]
			if j >= 0 and Biome.is_sea(ctx.biome[j]):
				coast = true
		feat[i] = (feat[i] | GeoLayers.COAST) if coast else (feat[i] & ~GeoLayers.COAST)
	ctx.features = feat


# --- Asentamientos ---------------------------------------------------------------

static func score(ctx: Ctx, i: int) -> int:
	var b: int = ctx.biome[i]
	var s: int = MunGeneratorG1.HABITABILITY[b] * 2
	if ctx.elev[i] >= GeoLayers.HILLS_E:
		s -= 3
	if GeoLayers.river_class(ctx.features[i]) > 0:
		s += 6
	if GeoLayers.is_coast(ctx.features[i]):
		s += 4
	for d: int in 6:
		var j: int = ctx.nb[i * 6 + d]
		if j >= 0 and ctx.biome[j] == Biome.LAKE:
			s += 3
			break
	return s


static func _habitable(ctx: Ctx, i: int) -> bool:
	return is_land(ctx, i) and ctx.biome[i] != Biome.ICE and ctx.used[i] == 0


## Hijo de un asentamiento que ya tiene código (los del mundo en REG G2).
static func add_settlement(ctx: Ctx, i: int, size_id: String, code: String, label: String) -> void:
	var s: Site = Site.new()
	s.cell = Vector2i(i % ctx.w, i / ctx.w)
	s.kind = size_id
	s.code = code
	s.label = label
	ctx.settlements.append(s)
	ctx.used[i] = 1


## `count` asentamientos propios de la región, por puntuación + azar y a
## `spacing` hexágonos o más de los demás. `first_town`: el mejor es un
## pueblo (REG G1); si no, aldeas y caseríos (alrededor de los del mundo).
## Semilla ALD del k-ésimo: hash64(seed_base, "ALD", k) & (2⁴⁰ − 1).
static func place_settlements(ctx: Ctx, rng: Rng, count: int, seed_base: int, spacing: int, first_town: bool) -> void:
	if count <= 0:
		return
	var cands: Array[Vector2i] = []
	for i: int in ctx.n:
		if _habitable(ctx, i):
			cands.append(Vector2i(score(ctx, i) * 4 + rng.bounded(4), i))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x or (a.x == b.x and a.y < b.y))
	var k: int = 0
	for cand: Vector2i in cands:
		if k >= count:
			break
		var i: int = cand.y
		if ctx.used[i] != 0 or not _far_from_all(ctx, i, spacing):
			continue
		var sr: Rng = rng.fork("settlement", k)
		var size_id: String = "hamlet"
		if k == 0 and first_town:
			size_id = "town"
		else:
			var roll: int = sr.bounded(100)
			size_id = "village" if roll < 45 else ("town" if roll < 53 else "hamlet")
		var st: String = _style_for(ctx, i, sr)
		var water: String = "none"
		if GeoLayers.river_class(ctx.features[i]) > 0:
			water = "river"
		elif GeoLayers.is_coast(ctx.features[i]):
			water = "coast"
		var sc: int = score(ctx, i)
		var params: Dictionary = {
			"size": size_id, "grid": ctx.child_grid, "style": st,
			"wall": size_id == "town" and sr.chance_permille(500),
			"water": water,
			"prosperity": "rich" if sc >= 22 else ("poor" if sc < 12 else "average"),
			"layout": "organic",
		}
		var seed_value: int = SplitMix64.hash64(seed_base, "ALD", k) & CHILD_SEED_MASK
		var code: String = SeedCode.create(ctx.system, "ALD", 1, params, seed_value).encode()
		add_settlement(ctx, i, size_id, code, GeoNames.settlement(sr, st))
		k += 1


static func _far_from_all(ctx: Ctx, i: int, spacing: int) -> bool:
	var c: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
	for s: Site in ctx.settlements:
		if ctx.grid.distance(c, s.cell) < spacing:
			return false
	for s: Site in ctx.pois:
		if ctx.grid.distance(c, s.cell) < 2:
			return false
	return true


static func _style_for(ctx: Ctx, i: int, r: Rng) -> String:
	if ctx.style != "mixed":
		return ctx.style
	if ctx.elev[i] >= GeoLayers.HILLS_E + 10 or ctx.biome[i] == Biome.MOUNTAIN:
		return "dwarf" if r.chance_permille(700) else "human"
	if Biome.is_forest(ctx.biome[i]):
		return "elf" if r.chance_permille(500) else "human"
	return "dwarf" if r.chance_permille(60) else ("elf" if r.chance_permille(60) else "human")


# --- Caminos ---------------------------------------------------------------------

## Une los asentamientos con caminos: pares ordenados por distancia hex (y
## por índices) al estilo de Kruskal, saltando los que ya están unidos y los
## que están en masas de tierra distintas (sin paso por tierra); cada par se
## traza con A* (los caminos ya marcados, del mundo o anteriores, cuestan 4
## en vez del coste del bioma). Así todos los asentamientos de una misma masa
## de tierra quedan unidos. Coste O(s² log s + s · n log n).
static func roads(ctx: Ctx) -> void:
	var s: int = ctx.settlements.size()
	if s < 2:
		return
	var comp: PackedInt32Array = _land_components(ctx)
	var pairs: Array[Vector3i] = []
	for a: int in s:
		for b: int in range(a + 1, s):
			var ia: int = ctx.grid.index_of(ctx.settlements[a].cell)
			var ib: int = ctx.grid.index_of(ctx.settlements[b].cell)
			if comp[ia] == comp[ib]:
				pairs.append(Vector3i(a, b, ctx.grid.distance(ctx.settlements[a].cell, ctx.settlements[b].cell)))
	pairs.sort_custom(func(p: Vector3i, q: Vector3i) -> bool: return p.z < q.z or (p.z == q.z and (p.x < q.x or (p.x == q.x and p.y < q.y))))
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(s)
	for k: int in s:
		parent[k] = k
	for pr: Vector3i in pairs:
		var ra: int = _find(parent, pr.x)
		var rb: int = _find(parent, pr.y)
		if ra == rb:
			continue
		var a: Site = ctx.settlements[pr.x]
		var b: Site = ctx.settlements[pr.y]
		var path: PackedInt32Array = _astar(ctx, ctx.grid.index_of(a.cell), ctx.grid.index_of(b.cell))
		if path.is_empty():
			continue
		parent[ra] = rb
		var feat: PackedByteArray = ctx.features
		for i: int in path:
			if is_land(ctx, i):
				feat[i] = feat[i] | GeoLayers.ROAD
		ctx.features = feat


static func _find(parent: PackedInt32Array, k: int) -> int:
	var r: int = k
	while parent[r] != r:
		r = parent[r]
	return r


## Componente (id >= 1) de cada casilla transitable por tierra (coste > 0, o
## con un hijo); 0 = agua o intransitable.
static func _land_components(ctx: Ctx) -> PackedInt32Array:
	var comp: PackedInt32Array = PackedInt32Array()
	comp.resize(ctx.n)
	var next_id: int = 0
	for start: int in ctx.n:
		if comp[start] != 0 or not _passable(ctx, start):
			continue
		next_id += 1
		comp[start] = next_id
		var queue: PackedInt32Array = PackedInt32Array([start])
		var head: int = 0
		while head < queue.size():
			var c: int = queue[head]
			head += 1
			for d: int in 6:
				var j: int = ctx.nb[c * 6 + d]
				if j >= 0 and comp[j] == 0 and _passable(ctx, j):
					comp[j] = next_id
					queue.append(j)
	return comp


static func _passable(ctx: Ctx, i: int) -> bool:
	return ctx.used[i] != 0 or (is_land(ctx, i) and MunGeneratorG1.TRAVEL_COST[ctx.biome[i]] > 0)

static func _cost(ctx: Ctx, i: int) -> int:
	if GeoLayers.has_road(ctx.features[i]):
		return 4
	var c: int = MunGeneratorG1.TRAVEL_COST[ctx.biome[i]]
	if c > 0 and ctx.elev[i] >= GeoLayers.HILLS_E:
		c += (ctx.elev[i] - GeoLayers.HILLS_E) / 3
	return c


static func _astar(ctx: Ctx, start: int, goal: int) -> PackedInt32Array:
	var n: int = ctx.n
	var g: PackedInt32Array = PackedInt32Array()
	g.resize(n)
	g.fill(1 << 30)
	var came: PackedInt32Array = PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(n)
	var heap: PackedInt64Array = PackedInt64Array()
	var goal_cell: Vector2i = Vector2i(goal % ctx.w, goal / ctx.w)
	g[start] = 0
	heap = _heap_push(heap, ctx.grid.distance(Vector2i(start % ctx.w, start / ctx.w), goal_cell) * 4, start)
	while not heap.is_empty():
		var top: int = heap[0]
		heap = _heap_pop(heap)
		var c: int = top & 0xFFFF
		if closed[c] == 1:
			continue
		closed[c] = 1
		if c == goal:
			var out: PackedInt32Array = PackedInt32Array()
			var k: int = goal
			while k != -1:
				out.append(k)
				k = came[k]
			out.reverse()
			return out
		for d: int in 6:
			var j: int = ctx.nb[c * 6 + d]
			if j < 0 or closed[j] == 1:
				continue
			var sc: int = _cost(ctx, j)
			if sc == 0 and j != goal:
				continue
			var ng: int = g[c] + maxi(sc, 4)
			if ng >= g[j]:
				continue
			g[j] = ng
			came[j] = c
			heap = _heap_push(heap, ng + ctx.grid.distance(Vector2i(j % ctx.w, j / ctx.w), goal_cell) * 4, j)
	return PackedInt32Array()


static func _heap_push(heap: PackedInt64Array, f: int, i: int) -> PackedInt64Array:
	heap.append((f << 16) | i)
	var k: int = heap.size() - 1
	while k > 0:
		var p: int = (k - 1) >> 1
		if heap[p] <= heap[k]:
			break
		var t: int = heap[p]
		heap[p] = heap[k]
		heap[k] = t
		k = p
	return heap


static func _heap_pop(heap: PackedInt64Array) -> PackedInt64Array:
	var last: int = heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if heap.is_empty():
		return heap
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
	return heap


# --- Puntos de interés -----------------------------------------------------------

## `count` puntos de interés en hexágonos de tierra libres, a 2 o más de
## cualquier otro hijo; tipo por pesos según el bioma (poi_weights). Semilla
## MAZ del k-ésimo: hash64(seed_base, "MAZ", k) & (2⁴⁰ − 1).
static func place_pois(ctx: Ctx, rng: Rng, count: int, seed_base: int) -> void:
	var k: int = 0
	var tries: int = 0
	while k < count and tries < count * 40:
		tries += 1
		var i: int = rng.bounded(ctx.n)
		if not is_land(ctx, i) or ctx.used[i] != 0 or not _far_from_all(ctx, i, 2):
			continue
		var pr: Rng = rng.fork("poi", k)
		var weights: PackedInt32Array = poi_weights(ctx, i)
		var id: String = POI_IDS[pr.pick_weighted(weights)]
		var s: Site = Site.new()
		s.cell = Vector2i(i % ctx.w, i / ctx.w)
		s.kind = "poi_" + id
		s.code = _poi_code(ctx, id, pr, SplitMix64.hash64(seed_base, "MAZ", k) & CHILD_SEED_MASK)
		ctx.pois.append(s)
		ctx.used[i] = 1
		k += 1


## Pesos de cada tipo de POI_IDS en la casilla i (bioma, altura, costa).
static func poi_weights(ctx: Ctx, i: int) -> PackedInt32Array:
	var b: int = ctx.biome[i]
	var high: bool = ctx.elev[i] >= GeoLayers.HILLS_E or b == Biome.MOUNTAIN
	var forest: bool = Biome.is_forest(b)
	var dry: bool = b == Biome.DESERT or b == Biome.COLD_DESERT
	var open: bool = b == Biome.GRASSLAND or b == Biome.SHRUBLAND or b == Biome.SAVANNA or b == Biome.TUNDRA
	var coast: bool = GeoLayers.is_coast(ctx.features[i])
	return PackedInt32Array([
		10, 6, 6, 6 if open or dry else 2, 8,
		10 if high else 2, 8 if high else 0, 6 if forest or high or b == Biome.WETLAND else 2,
		6 if open or forest else 1, 6 if open else 1, 14 if b == Biome.DESERT else 0,
		10 if coast else 0, 5,
	])


static func _poi_code(ctx: Ctx, id: String, r: Rng, seed_value: int) -> String:
	if not POI_MAZ.has(id):
		return ""
	var spec: Array = POI_MAZ[id]
	var layout: String = spec[0]
	var lo: int = spec[1]
	var hi: int = spec[2]
	var style: String = "dwarf" if id == "mine" else (ctx.style if ctx.style != "mixed" else "human")
	var params: Dictionary = {"rooms": r.range_int(lo, hi), "layout": layout, "grid": ctx.child_grid, "style": style}
	return SeedCode.create(ctx.system, "MAZ", 1, params, seed_value).encode()


# --- Volcado ---------------------------------------------------------------------

static func to_document(ctx: Ctx) -> MapDocument:
	var doc: MapDocument = MapDocument.create(ctx.grid.kind, ctx.w, ctx.h, 1)
	var level: MapLevel = doc.level(0)
	var room_of: PackedInt32Array = PackedInt32Array()
	room_of.resize(ctx.kingdom_names.size())
	for k: int in range(1, ctx.kingdom_names.size()):
		var present: bool = false
		for i: int in ctx.n:
			if ctx.kingdom[i] == k and is_land(ctx, i):
				present = true
				break
		if present:
			var room: MapRoom = MapRoom.make(doc.allocate_id(), "kingdom", ctx.kingdom_names[k])
			level.add_room(room)
			room_of[k] = room.id
	var terrain: PackedByteArray = PackedByteArray()
	terrain.resize(ctx.n)
	var rooms: PackedInt32Array = PackedInt32Array()
	rooms.resize(ctx.n)
	for i: int in ctx.n:
		var b: int = ctx.biome[i]
		if b == Biome.SHALLOW_SEA:
			terrain[i] = Terrain.WATER_SHALLOW
		elif Biome.is_water(b):
			terrain[i] = Terrain.WATER_DEEP
		else:
			terrain[i] = Terrain.RUBBLE if ctx.elev[i] >= GeoLayers.MOUNTAIN_E else Terrain.FLOOR
			rooms[i] = room_of[ctx.kingdom[i]]
	level.terrain = terrain
	level.room_ids = rooms
	level.biome = ctx.biome
	level.elevation = ctx.elev
	level.features = ctx.features
	for s: Site in ctx.settlements:
		var i: int = ctx.grid.index_of(s.cell)
		level.add_child_map(GeoLinks.settlement_child(doc.allocate_id(), s.cell, s.kind, SeedCode.parse(s.code), s.label, rooms[i]))
	for s: Site in ctx.pois:
		var i: int = ctx.grid.index_of(s.cell)
		level.add_child_map(GeoLinks.poi_child(doc.allocate_id(), s.cell, s.kind, s.code, rooms[i]))
	return doc
