class_name AldGeneratorG1
extends RefCounted
## Generador de asentamientos ALD, versión G1 (PROYECTO §6.3, ADR 027).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en AldData, en
## data/settlements, en el bloque "settlement" de data/styles, y también en lo
## que usa de EDI: la huella, la planta baja y el código de cada edificio)
## EXIGE GEN NUEVO: copiar a core/gen/ald/legacy/, registrar G2 y añadir seeds
## doradas nuevas.
##
## Puro y determinista (CLAUDE.md §6): solo enteros, todo el azar sale del Rng
## recibido y de sus hijos, listas en orden fijo; los diccionarios solo se
## consultan por clave.
##
## ESCALA: 1 casilla = la casilla táctica del sistema (5 ft = 1,5 m), la misma
## que EDI. Así la huella de cada edificio es EXACTAMENTE la de su mapa EDI y la
## ficha puede pasar de la calle al edificio sin conversión (ADR 027).
##
## EDIFICIOS = HIJOS EDI. El edificio de orden k tiene:
##   - parámetros EDI de building_spec(): tipo (obligatorios del tamaño y luego
##     por pesos de tamaño × prosperidad × estilo), tamaño EDI, sótano, plantas
##     y clutter, sacados SOLO de Rng.new(semilla).fork("building", k);
##   - semilla hija child_seed() = hash64(semilla, "EDI", k) recortada a 40 bits
##     (los mismos que las semillas de la app: el código del edificio mide lo
##     mismo que uno aleatorio);
##   - su código RPGM1-<SIS>-EDI-G1-<params>-<semilla hija>, guardado en el
##     documento (MapChild). Regenerar ese código da el mismo edificio que
##     describe la aldea: la huella es footprint_size() de EDI, y la puerta
##     principal, la trasera y las ventanas salen de
##     EdiGeneratorG1.plan_ground_floor() con esos parámetros y esa semilla
##     (la misma planta baja que genera EDI; test_ald_generator lo compara).
##   Ni la semilla ni los parámetros de un edificio dependen de los demás.
##
## Jerarquía de semillas (§5.2):
##   raíz ── fork("orientation", 0)   eje de la calle principal
##        ├─ fork("water", 0)         río o costa
##        ├─ fork("crossroads", 0)    ¿segunda calle principal?
##        ├─ fork("road", 0..3)       mitades de las dos calles principales
##        ├─ fork("branches", 0)      dónde salen las ramas
##        ├─ fork("branch", id)       cada rama (calle o callejón)
##        ├─ fork("count", 0)         nº de edificios
##        ├─ fork("building", k)      parámetros EDI del edificio k
##        ├─ fork("place", 0)         desempates de la parcelación
##        └─ hash64(semilla, "EDI", k) & (2^40 - 1)   semilla del edificio k
##
## Algoritmo (n = casillas del mapa, b = edificios, f = casillas de fachada):
## 1. Mapa W×H del tamaño (data), ampliado si hay muralla, costa o río
##    (map_size: compensa el suelo edificable que se pierde). Agua: río perpendicular a la calle principal,
##    que serpentea a un lado de la plaza (agua profunda con orillas poco
##    profundas), o costa en un lado paralelo a la calle principal. O(n).
## 2. Asentamiento: elipse centrada (desplazada tierra adentro si hay costa).
##    Con muralla, su borde es la muralla (terreno WALL; abierta donde pasa el
##    agua) y la zona edificable queda WALL_GAP casillas por dentro. Zona
##    edificable = dentro de la elipse y a más de 1 casilla del agua; sin
##    muralla, las parcelas pueden salir de la elipse junto a las calles
##    (arrabales). O(n).
## 3. Plaza en el centro. Calles principales: una a lo largo del eje (de borde a
##    borde, puente al cruzar el río, puerta al cruzar la muralla) y, con
##    crossroads_permille, otra perpendicular (se detiene ante el agua).
##    - Orgánico: cada calle es un "caminante" que avanza y, con turn_permille
##      del estilo, se desvía una casilla (pasos de 4 vecinos en coordenadas
##      offset: conexos en las tres rejillas). Ramas perpendiculares cada
##      branch_every casillas, de branch_length de largo, en branch_levels
##      niveles (calles y callejones); una rama se detiene al salir de la zona
##      edificable y se une (y para) al tocar otra calle: no deja tiras de
##      una casilla entre calles paralelas.
##    - Retícula (layout = grid): principales rectas y calles cada grid_block.
##    Después, se quita toda calle que no se alcance desde la plaza (BFS), así
##    que la red de calles es conexa. O(n + longitud de calles).
## 4. Parcelación: casillas de fachada (libres, con una calle o la plaza al
##    lado) ordenadas por distancia a la plaza + desempate al azar (0..JITTER).
##    Cada edificio (los obligatorios primero, junto a la plaza; el resto de
##    mayor a menor huella) ocupa la primera fachada libre donde cabe su
##    parcela: huella EDI + anillo de 1 casilla (el anillo exterior del mapa
##    EDI) + patio detrás (yard), alineada a
##    la calle (centro, izquierda o derecha) y con la paridad de la rejilla
##    (translation_step: en hex odd-q/odd-r solo se puede trasladar de 2 en 2
##    en un eje sin cambiar los vecinos). Una fachada que falló con una
##    parcela de w×h no se vuelve a probar con otra mayor o igual en los dos
##    lados. Los edificios que no caben se descartan (se cuentan en Result).
##    O(f log f + b × (f + parcela)) con la poda.
## 5. Volcado: terreno y zonas (MapRoom: field, garden, street, plaza, bridge,
##    gate, town_wall; por edificio, yard y building), muro en arista en todo
##    el contorno de cada huella, puertas exteriores y ventanas de su planta
##    baja EDI, y un MapChild por edificio con su código. O(n + b × huella).
##
## Garantías por construcción: las calles forman una sola componente que
## contiene la plaza (paso 3); cada parcela es un rectángulo transitable que
## toca una calle por su casilla de fachada y rodea la huella por completo (el
## anillo), así que la puerta principal (y la trasera) de todo edificio se
## alcanza desde la calle (Connectivity y un BFS sin agua en los tests).

const SCALE: String = "ALD"
const GEN: int = 1

## Casillas entre el borde del mapa y la elipse del asentamiento.
const MAP_MARGIN: int = 3
## Casillas libres entre la muralla y la zona edificable.
const WALL_GAP: int = 2
## Desempate al azar de la distancia de una fachada a la plaza (casillas).
const JITTER: int = 6
## Pasos rectos al empezar una rama (se separa de su calle madre).
const STRAIGHT_START: int = 2
## Desvío lateral máximo de una rama.
const BRANCH_MAX_DEV: int = 2
## Semillas hijas de 40 bits, como las de la app (8 caracteres como mucho).
const CHILD_SEED_BITS: int = 40
const CHILD_SEED_MASK: int = (1 << CHILD_SEED_BITS) - 1

## Clase de cada casilla durante la generación.
const K_FIELD: int = 0
const K_GARDEN: int = 1
const K_STREET: int = 2
const K_PLAZA: int = 3
const K_BRIDGE: int = 4
const K_GATE: int = 5
const K_WALL: int = 6
const K_SHALLOW: int = 7
const K_DEEP: int = 8
const K_YARD: int = 9
const K_BUILDING: int = 10
## Zona (MapRoom.kind) de cada clase con zona única ("" = sin zona).
const ZONE_OF_CLASS: PackedStringArray = ["field", "garden", "street", "plaza", "bridge", "gate", "town_wall", "", "", "", ""]

## Vecinos de 4 en coordenadas offset (N, E, S, O). En las tres rejillas son
## vecinos de verdad: (x±1, y) y (x, y±1) comparten lado también en odd-q y
## odd-r. Por eso las calles se trazan con ellos sin ramas por rejilla.
const OFFS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Los 8 desplazamientos de ±1: contienen a los vecinos de cualquier rejilla.
const OFFS8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Modos del caminante.
const MODE_MAIN: int = 0
## Principal que se detiene ante el agua (no hace puente).
const MODE_MAIN_DRY: int = 1
const MODE_BRANCH: int = 2
## Resultado de probar una posición del caminante.
const ST_OK: int = 0
const ST_JOIN: int = 1
const ST_BLOCKED: int = 2


## Parámetros resueltos (campos del esquema ALD G1).
class Params:
	extends RefCounted
	var size_id: String = "village"
	var grid_kind: String = "square"
	var style: String = "human"
	var wall: bool = false
	var water: String = "none"
	var prosperity: String = "average"
	var layout: String = "organic"


## Edificio hijo (también es el informe que leen los tests).
class Building:
	extends RefCounted
	var order: int = 0
	var edi: EdiGeneratorG1.Params = null
	var child_seed: int = 0
	## Código EDI canónico del hijo.
	var code: String = ""
	## Huella interior (ancho × alto) de EDI.
	var dims: Vector2i = Vector2i.ZERO
	## Planta baja del EDI (coordenadas del mapa hijo).
	var ground: EdiGeneratorG1.Floor = null
	## Nivel de la planta baja en el mapa hijo (1 con sótano).
	var ground_level: int = 0
	var placed: bool = false
	## Casilla del asentamiento que corresponde a la (0, 0) del mapa hijo.
	var offset: Vector2i = Vector2i.ZERO
	var parcel: Rect2i = Rect2i()
	var footprint: Rect2i = Rect2i()
	## Casilla (del asentamiento) delante de la puerta principal.
	var entrance: Vector2i = Vector2i(-1, -1)
	var room_id: int = 0
	var yard_room_id: int = 0


## Calle trazada por el caminante.
class Walk:
	extends RefCounted
	## Casillas del eje, en orden.
	var cells: Array[Vector2i] = []
	var fwd: Vector2i = Vector2i.ZERO
	## La calle ocupa cells[i] + thick × k, k = 0..width-1.
	var thick: Vector2i = Vector2i.ZERO
	var width: int = 1
	## 0 = principal, 1 = calle, 2 = callejón.
	var level: int = 0


## Estado de la generación.
class Ctx:
	extends RefCounted
	var w: int = 0
	var h: int = 0
	## Clase K_* por casilla.
	var cls: PackedByteArray = PackedByteArray()
	## Clase antes de trazar calles (para quitar las que no se alcanzan).
	var base: PackedByteArray = PackedByteArray()
	## 1 = zona de calles secundarias (elipse interior, lejos del agua).
	var area: PackedByteArray = PackedByteArray()
	## 1 = se puede parcelar: con muralla, lo mismo que `area`; sin ella, todo
	## el mapa salvo el margen (arrabales a lo largo de las calles), siempre
	## lejos del agua.
	var lot: PackedByteArray = PackedByteArray()
	## 1 = agua o vecina del agua.
	var near_water: PackedByteArray = PackedByteArray()
	## Calle que pintó cada casilla (0 = ninguna).
	var owner: PackedInt32Array = PackedInt32Array()
	## Edificio (índice + 1) de cada casilla de parcela.
	var parcel_of: PackedInt32Array = PackedInt32Array()
	var center: Vector2i = Vector2i.ZERO
	## Radios de la elipse del asentamiento (x, y).
	var radii: Vector2i = Vector2i.ZERO
	var horizontal: bool = true

	func idx(c: Vector2i) -> int:
		if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
			return -1
		return c.y * w + c.x

	func is_street(i: int) -> bool:
		var k: int = cls[i]
		return k == K_STREET or k == K_PLAZA or k == K_BRIDGE or k == K_GATE


## Resultado de generate_settlement().
class Result:
	extends RefCounted
	var doc: MapDocument = null
	## Todos los edificios intentados, en orden (placed = false si no cupo).
	var buildings: Array[Building] = []
	var population: int = 0
	var plaza_cell: Vector2i = Vector2i.ZERO
	var street_cells: int = 0
	var walks: int = 0

	func placed_count() -> int:
		var n: int = 0
		for b: Building in buildings:
			if b.placed:
				n += 1
		return n


## Punto de entrada registrado en GeneratorRegistry.
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var res: Result = generate_settlement(params_from(code), code.system, rng)
	return res.doc if res != null else null


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var size_id: String = code.params["size"]
	var grid_kind: String = code.params["grid"]
	var style: String = code.params["style"]
	var wall: bool = code.params["wall"]
	var water: String = code.params["water"]
	var prosperity: String = code.params["prosperity"]
	var layout: String = code.params["layout"]
	p.size_id = size_id
	p.grid_kind = grid_kind
	p.style = style
	p.wall = wall
	p.water = water
	p.prosperity = prosperity
	p.layout = layout
	return p


## Semilla del edificio de orden `order` (§5.2), recortada a 40 bits.
static func child_seed(settlement_seed: int, order: int) -> int:
	return SplitMix64.hash64(settlement_seed, "EDI", order) & CHILD_SEED_MASK


## Edificio de orden `order` sin colocar: parámetros EDI, semilla hija y
## código. Puro: solo depende de los parámetros del asentamiento, de su
## semilla y de `order` (no de los demás edificios). null si faltan datos.
static func building_spec(p: Params, system: String, settlement_seed: int, order: int) -> Building:
	var data: AldData = AldData.load_default()
	var edi_data: EdiData = EdiData.load_default()
	if not data.is_valid() or not edi_data.is_valid():
		return null
	var ss: AldData.SizeSpec = data.size_spec(p.size_id)
	var pr: AldData.Prosperity = data.prosperity(p.prosperity)
	var st: AldData.StyleSettlement = data.style_settlement(p.style)
	if ss == null or pr == null or st == null:
		return null
	var rng: Rng = Rng.new(settlement_seed).fork("building", order)
	var weights: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	for t: int in data.type_ids.size():
		var wt: int = ss.type_weights[t] * pr.type_pct[t] * st.type_pct[t] / 10000
		weights.append(wt)
		total += wt
	if total <= 0:
		weights = ss.type_weights
	# Siempre se sortea (también para los obligatorios): así el resto de
	# decisiones del edificio no depende de si su tipo era obligatorio.
	var picked: String = data.type_ids[rng.pick_weighted(weights)]
	var type_id: String = ss.required[order] if order < ss.required.size() else picked
	var size_id: String = AldData.EDI_SIZE_IDS[rng.pick_weighted(pr.edi_size_weights)]
	var cellar: bool = rng.chance_permille(pr.cellar_permille)
	var extra_floor: bool = rng.chance_permille(ss.extra_floor_permille)
	var bt: EdiData.BuildingType = edi_data.building_type(type_id)
	if bt == null:
		return null
	var b: Building = Building.new()
	b.order = order
	b.edi = EdiGeneratorG1.Params.new()
	b.edi.building_type = type_id
	b.edi.grid_kind = p.grid_kind
	b.edi.style = p.style
	b.edi.floors = mini(4, bt.floors + 1) if extra_floor else 0
	b.edi.cellar = cellar
	b.edi.size_id = size_id
	b.edi.clutter = pr.clutter
	b.child_seed = child_seed(settlement_seed, order)
	b.ground_level = 1 if cellar else 0
	var sc: SeedCode = SeedCode.create(system, EdiGeneratorG1.SCALE, EdiGeneratorG1.GEN, {
		"building_type": type_id, "grid": p.grid_kind, "style": p.style, "floors": b.edi.floors,
		"cellar": cellar, "size": size_id, "clutter": pr.clutter}, b.child_seed)
	b.code = sc.encode()
	var sb: EdiData.StyleBuilding = edi_data.style_building(p.style)
	if sb == null:
		return null
	b.dims = EdiGeneratorG1.footprint_size(bt, sb, size_id)
	return b


## Paso mínimo de traslación que conserva los vecinos de la rejilla: (1, 1)
## en la cuadrada; en hex odd-q los vecinos dependen de la paridad de la
## columna (2, 1) y en odd-r de la de la fila (1, 2). Se mide, no se pregunta
## por el tipo de rejilla.
static func translation_step(grid: GridGeometry) -> Vector2i:
	var step: Vector2i = Vector2i(1, 1)
	var deltas: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	var probes: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]
	for axis: int in 2:
		var delta: Vector2i = deltas[axis]
		for c: Vector2i in probes:
			for d: int in grid.direction_count():
				if grid.neighbor(c + delta, d) != grid.neighbor(c, d) + delta:
					if axis == 0:
						step.x = 2
					else:
						step.y = 2
	return step


## Tamaño del mapa: el del tamaño (data) más lo que se pierde de suelo
## edificable, para que muralla y agua no dejen sin sitio a los edificios
## (medido: con muralla y costa una ciudad colocaba solo el 54 %):
## - muralla: ×1,15 en cada lado (sin arrabales fuera, y WALL_GAP por dentro);
## - costa: el mar se añade en el eje lateral (la tierra queda como sin costa);
## - río: su ancho + 4 (orillas y casillas junto al agua) en el eje principal.
static func map_size(p: Params, ss: AldData.SizeSpec, horizontal: bool) -> Vector2i:
	var len_a: int = ss.map.x if horizontal else ss.map.y
	var len_l: int = ss.map.y if horizontal else ss.map.x
	if p.wall:
		len_a = len_a * 115 / 100
		len_l = len_l * 115 / 100
	if p.water == "coast":
		# Mar = len_l/6 + 2 del total: total = (tierra + 2) × 6/5.
		len_l = (len_l + 2) * 6 / 5
	elif p.water == "river":
		len_a += ss.river_width + 4
	return Vector2i(len_a, len_l) if horizontal else Vector2i(len_l, len_a)


## Asentamiento completo (puro). null si el tamaño, la prosperidad, el estilo
## o la rejilla no existen.
static func generate_settlement(p: Params, system: String, rng: Rng) -> Result:
	var data: AldData = AldData.load_default()
	if not data.is_valid():
		return null
	var ss: AldData.SizeSpec = data.size_spec(p.size_id)
	var st: AldData.StyleSettlement = data.style_settlement(p.style)
	if ss == null or st == null or data.prosperity(p.prosperity) == null:
		return null
	var horizontal: bool = rng.fork("orientation", 0).chance_permille(500)
	var dims: Vector2i = map_size(p, ss, horizontal)
	var doc: MapDocument = MapDocument.create(p.grid_kind, dims.x, dims.y, 1)
	if doc == null:
		return null
	var ctx: Ctx = Ctx.new()
	ctx.w = dims.x
	ctx.h = dims.y
	var n: int = ctx.w * ctx.h
	ctx.cls.resize(n)
	ctx.cls.fill(K_FIELD)
	ctx.area.resize(n)
	ctx.area.fill(0)
	ctx.lot.resize(n)
	ctx.lot.fill(0)
	ctx.near_water.resize(n)
	ctx.near_water.fill(0)
	ctx.owner.resize(n)
	ctx.owner.fill(0)
	ctx.parcel_of.resize(n)
	ctx.parcel_of.fill(0)
	ctx.horizontal = horizontal
	var res: Result = Result.new()
	res.doc = doc
	_make_water_and_center(ctx, p, ss, rng.fork("water", 0))
	_make_area_and_wall(ctx, p)
	_make_plaza(ctx, ss)
	ctx.base = ctx.cls.duplicate()
	res.walks = _make_streets(ctx, p, ss, st, rng)
	_keep_connected_streets(ctx)
	res.plaza_cell = ctx.center
	for i: int in n:
		if ctx.is_street(i):
			res.street_cells += 1
	# Edificios.
	var count: int = rng.fork("count", 0).range_int(ss.buildings.x, ss.buildings.y)
	var step: Vector2i = translation_step(doc.grid)
	var placer: Placer = Placer.new()
	placer.build(ctx, rng.fork("place", 0))
	for k: int in count:
		var b: Building = building_spec(p, system, rng.seed_value, k)
		if b == null:
			return null
		res.buildings.append(b)
	# Orden de colocación: los obligatorios primero (junto a la plaza) y el
	# resto de mayor a menor huella (empaquetado: las casas llenan los huecos
	# que dejan los grandes). Solo cambia dónde va cada uno, no su código.
	var keys: PackedInt64Array = PackedInt64Array()
	for b2: Building in res.buildings:
		var prio: int = 0 if b2.order < ss.required.size() else 1
		var big: int = 0xFFFF - (b2.dims.x + 2) * (b2.dims.y + 2)
		keys.append((prio << 40) | (big << 20) | b2.order)
	keys.sort()
	for key: int in keys:
		var b: Building = res.buildings[key & 0xFFFFF]
		_place(ctx, placer, b, ss.yard, step)
		if b.placed:
			b.ground = EdiGeneratorG1.plan_ground_floor(b.edi, Rng.new(b.child_seed))
			if b.ground == null:
				return null
			b.entrance = b.ground.entrance_cell + b.offset
			res.population += data.residents_of(b.edi.building_type)
	_commit(doc, ctx, res)
	return res


# --- 1-2. Agua, elipse, muralla y plaza ------------------------------------------

## Eje principal (A) y lateral (L) del mapa como vectores x, y.
static func _axes(ctx: Ctx) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	if not ctx.horizontal:
		out = [Vector2i(0, 1), Vector2i(1, 0)]
	return out


static func _set_water(ctx: Ctx, c: Vector2i, deep: bool) -> void:
	var i: int = ctx.idx(c)
	if i < 0:
		return
	if deep or ctx.cls[i] != K_DEEP:
		ctx.cls[i] = K_DEEP if deep else K_SHALLOW


static func _make_water_and_center(ctx: Ctx, p: Params, ss: AldData.SizeSpec, rng: Rng) -> void:
	var axes: Array[Vector2i] = _axes(ctx)
	var a_vec: Vector2i = axes[0]
	var l_vec: Vector2i = axes[1]
	var len_a: int = ctx.w if ctx.horizontal else ctx.h
	var len_l: int = ctx.h if ctx.horizontal else ctx.w
	var ca: int = len_a / 2
	var cl: int = len_l / 2
	var ra: int = len_a / 2 - MAP_MARGIN
	var rl: int = len_l / 2 - MAP_MARGIN
	if p.water == "river":
		# Río a lo largo de L, a un lado de la plaza, serpenteando ±3.
		var rw: int = ss.river_width
		var plaza_a: int = ss.plaza.x if ctx.horizontal else ss.plaza.y
		var off_min: int = maxi(plaza_a / 2 + rw + 4, ra / 3)
		var off: int = rng.range_int(off_min, maxi(off_min, ra / 2))
		var a0: int = ca + (off if rng.chance_permille(500) else -off)
		var pos: int = a0
		var drift: int = 1 if rng.chance_permille(500) else -1
		for t: int in len_l:
			if rng.chance_permille(250):
				if rng.chance_permille(300):
					drift = -drift
				if absi(pos + drift - a0) <= 3:
					pos += drift
			for k: int in rw:
				var a: int = pos - rw / 2 + k
				_set_water(ctx, a_vec * a + l_vec * t, k > 0 and k < rw - 1)
	elif p.water == "coast":
		# Mar en un lado paralelo a la calle principal; orilla de 2 casillas
		# poco profundas que oscila ±2 alrededor de len_l / 6.
		var depth: int = len_l / 6
		var low: bool = rng.chance_permille(500)
		var shore: int = depth
		for a2: int in len_a:
			if rng.chance_permille(300):
				shore = clampi(shore + (1 if rng.chance_permille(500) else -1), depth - 2, depth + 2)
			for l: int in shore:
				var lc: int = l if low else len_l - 1 - l
				_set_water(ctx, a_vec * a2 + l_vec * lc, l < shore - 2)
		var land: int = len_l - depth - 2
		rl = land / 2 - MAP_MARGIN
		cl = (depth + 2) + land / 2 if low else land / 2
	ctx.center = a_vec * ca + l_vec * cl
	ctx.radii = Vector2i(ra, rl) if ctx.horizontal else Vector2i(rl, ra)
	for i: int in ctx.w * ctx.h:
		var k: int = ctx.cls[i]
		if k != K_SHALLOW and k != K_DEEP:
			continue
		var c: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
		ctx.near_water[i] = 1
		for o: Vector2i in OFFS8:
			var ni: int = ctx.idx(c + o)
			if ni >= 0:
				ctx.near_water[ni] = 1


## Dentro de la elipse de centro `c` y radios `r` (aritmética entera).
static func _in_ellipse(cell: Vector2i, c: Vector2i, r: Vector2i) -> bool:
	if r.x <= 0 or r.y <= 0:
		return false
	var dx: int = cell.x - c.x
	var dy: int = cell.y - c.y
	return dx * dx * r.y * r.y + dy * dy * r.x * r.x <= r.x * r.x * r.y * r.y


static func _make_area_and_wall(ctx: Ctx, p: Params) -> void:
	var inner_r: Vector2i = ctx.radii - Vector2i(WALL_GAP + 1, WALL_GAP + 1) if p.wall else ctx.radii
	for i: int in ctx.w * ctx.h:
		var c: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
		var water: bool = ctx.cls[i] == K_SHALLOW or ctx.cls[i] == K_DEEP
		var inside: bool = _in_ellipse(c, ctx.center, ctx.radii)
		if not water and inside:
			ctx.cls[i] = K_GARDEN
		if inside and ctx.near_water[i] == 0 and _in_ellipse(c, ctx.center, inner_r):
			ctx.area[i] = 1
		var in_margin: bool = c.x >= MAP_MARGIN - 1 and c.y >= MAP_MARGIN - 1 and c.x <= ctx.w - MAP_MARGIN and c.y <= ctx.h - MAP_MARGIN
		if ctx.near_water[i] == 0 and (ctx.area[i] == 1 or (not p.wall and in_margin)):
			ctx.lot[i] = 1
		if p.wall and inside and not water:
			# Borde de la elipse: alguna de las 8 casillas de alrededor (que
			# contienen a los vecinos de cualquier rejilla) queda fuera. Así
			# ningún camino de vecinos cruza la muralla sin pisarla.
			for o: Vector2i in OFFS8:
				var nc: Vector2i = c + o
				if ctx.idx(nc) < 0 or not _in_ellipse(nc, ctx.center, ctx.radii):
					ctx.cls[i] = K_WALL
					break


static func _make_plaza(ctx: Ctx, ss: AldData.SizeSpec) -> void:
	var r: Rect2i = Rect2i(ctx.center - ss.plaza / 2, ss.plaza)
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var i: int = ctx.idx(Vector2i(x, y))
			if i >= 0 and ctx.cls[i] == K_GARDEN:
				ctx.cls[i] = K_PLAZA
				ctx.area[i] = 0


# --- 3. Calles -------------------------------------------------------------------

## Traza las calles; devuelve el nº de caminantes.
static func _make_streets(ctx: Ctx, p: Params, ss: AldData.SizeSpec, st: AldData.StyleSettlement, rng: Rng) -> int:
	var axes: Array[Vector2i] = _axes(ctx)
	var a_vec: Vector2i = axes[0]
	var l_vec: Vector2i = axes[1]
	var grid_layout: bool = p.layout == "grid"
	var ra: int = ctx.radii.x if ctx.horizontal else ctx.radii.y
	var rl: int = ctx.radii.y if ctx.horizontal else ctx.radii.x
	var turn_main: int = 0 if grid_layout else st.turn_permille / 2
	var crossroads: bool = grid_layout or rng.fork("crossroads", 0).chance_permille(ss.crossroads_permille)
	# Calle 1 a lo largo de A (puente si hay río, que la cruza); calle 2 a lo
	# largo de L (paralela al río o hacia el mar: se detiene ante el agua).
	var mode1: int = MODE_MAIN_DRY if p.water == "coast" else MODE_MAIN
	var queue: Array[Walk] = []
	var walk_id: int = 0
	var start1: Vector2i = ctx.center - l_vec * (ss.main_width / 2)
	for half: int in 2:
		walk_id += 1
		var wk: Walk = _walk(ctx, start1, a_vec * (1 if half == 0 else -1), l_vec, ss.main_width, ctx.w + ctx.h,
			turn_main, maxi(1, rl / 8), mode1, walk_id, rng.fork("road", half))
		queue.append(wk)
	if crossroads:
		var start2: Vector2i = ctx.center - a_vec * (ss.main_width / 2)
		for half2: int in 2:
			walk_id += 1
			var wk2: Walk = _walk(ctx, start2, l_vec * (1 if half2 == 0 else -1), a_vec, ss.main_width, ctx.w + ctx.h,
				turn_main, maxi(1, ra / 8), MODE_MAIN_DRY, walk_id, rng.fork("road", 2 + half2))
			queue.append(wk2)
	if grid_layout:
		_grid_streets(ctx, ss)
		return walk_id
	# Ramas: calles desde las principales y, en el segundo nivel, callejones.
	var brng: Rng = rng.fork("branches", 0)
	var qi: int = 0
	while qi < queue.size():
		var parent: Walk = queue[qi]
		qi += 1
		if parent.level >= ss.branch_levels:
			continue
		var width: int = ss.street_width if parent.level == 0 else ss.lane_width
		# La primera rama, también a branch_every del arranque: si saliera
		# antes, correría paralela a la calle abuela a 2-3 casillas y dejaría
		# una tira sin sitio para ninguna parcela.
		var next: int = brng.range_int(ss.branch_every.x, ss.branch_every.y)
		for i: int in parent.cells.size():
			if i < next:
				continue
			next = i + brng.range_int(ss.branch_every.x, ss.branch_every.y)
			var sides: int = brng.bounded(4)
			var length: int = brng.range_int(ss.branch_length.x, ss.branch_length.y)
			for side: int in [1, -1]:
				if (side == 1 and sides == 1) or (side == -1 and sides == 0):
					continue
				var c: Vector2i = parent.cells[i]
				var start: Vector2i = c + parent.thick * parent.width if side == 1 else c - parent.thick
				walk_id += 1
				var wk3: Walk = _walk(ctx, start, parent.thick * side, parent.fwd, width, length,
					st.turn_permille, BRANCH_MAX_DEV, MODE_BRANCH, walk_id, rng.fork("branch", walk_id))
				wk3.level = parent.level + 1
				if wk3.cells.size() >= 3:
					queue.append(wk3)
	return walk_id


## Retícula: calles de street_width cada grid_block casillas en x y en y,
## solo dentro de la zona edificable (luego se quitan los trozos sueltos).
static func _grid_streets(ctx: Ctx, ss: AldData.SizeSpec) -> void:
	var sw: int = ss.street_width
	for axis: int in 2:
		var block: int = ss.grid_block.y if axis == 0 else ss.grid_block.x
		var c0: int = ctx.center.y if axis == 0 else ctx.center.x
		var span: int = ctx.h if axis == 0 else ctx.w
		var along: int = ctx.w if axis == 0 else ctx.h
		for k: int in range(1, span / block + 2):
			for sgn: int in [1, -1]:
				var line0: int = c0 + sgn * k * block - sw / 2
				for t: int in sw:
					var line: int = line0 + t
					if line < 0 or line >= span:
						continue
					for a: int in along:
						var cell: Vector2i = Vector2i(a, line) if axis == 0 else Vector2i(line, a)
						var i: int = ctx.idx(cell)
						if ctx.area[i] == 1 and ctx.cls[i] == K_GARDEN:
							ctx.cls[i] = K_STREET
							ctx.owner[i] = -1


## Casillas de la calle con eje en `axis_cell`.
static func _thick_cells(axis_cell: Vector2i, thick: Vector2i, width: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: int in width:
		out.append(axis_cell + thick * k)
	return out


## Caminante: traza una calle desde `start` hacia `fwd` (como mucho
## `max_steps` pasos) y la pinta. Con `turn_permille`, antes de cada paso
## (salvo los STRAIGHT_START primeros) puede desviarse una casilla hacia la
## deriva actual (que cambia de sentido con 300 ‰), sin pasar de `max_dev`.
static func _walk(ctx: Ctx, start: Vector2i, fwd: Vector2i, thick: Vector2i, width: int, max_steps: int,
		turn_permille: int, max_dev: int, mode: int, walk_id: int, rng: Rng) -> Walk:
	var wk: Walk = Walk.new()
	wk.fwd = fwd
	wk.thick = thick
	wk.width = width
	var s0: int = _probe(ctx, start, thick, width, mode, walk_id, 0)
	if s0 == ST_BLOCKED:
		return wk
	_paint(ctx, start, thick, width, walk_id)
	wk.cells.append(start)
	if s0 == ST_JOIN:
		return wk
	var pos: Vector2i = start
	var dev: int = 0
	var drift: int = 1 if rng.chance_permille(500) else -1
	for step: int in range(1, max_steps + 1):
		if turn_permille > 0 and step > STRAIGHT_START and rng.chance_permille(turn_permille):
			if rng.chance_permille(300):
				drift = -drift
			if absi(dev + drift) <= max_dev:
				var lp: Vector2i = pos + thick * drift
				# Un desvío solo si deja la calle libre: si al desviarse quedara
				# pegada a otra (ST_JOIN), se formaría una losa de calle de 4-6
				# casillas; mejor seguir recto y unirse de frente.
				var lateral_ok: bool = false
				if mode == MODE_BRANCH:
					lateral_ok = _probe(ctx, lp, thick, width, mode, walk_id, step) == ST_OK
				else:
					lateral_ok = _main_lateral_ok(ctx, pos, lp, thick, width)
				if lateral_ok:
					_paint(ctx, lp, thick, width, walk_id)
					wk.cells.append(lp)
					pos = lp
					dev += drift
		var np: Vector2i = pos + fwd
		var s: int = _probe(ctx, np, thick, width, mode, walk_id, step)
		if s == ST_BLOCKED:
			break
		_paint(ctx, np, thick, width, walk_id)
		wk.cells.append(np)
		pos = np
		if s == ST_JOIN:
			break
	return wk


## ¿Se puede pintar la calle con eje en `axis_cell`?
## - Principales: hasta el borde del mapa; MODE_MAIN_DRY se detiene ante el
##   agua. Nunca se unen (cruzan lo que encuentran).
## - Ramas: solo en zona edificable libre; si pisan otra calle, o (desde el
##   paso STRAIGHT_START) quedan pegadas a otra, se unen a ella y paran.
static func _probe(ctx: Ctx, axis_cell: Vector2i, thick: Vector2i, width: int, mode: int, walk_id: int, step: int) -> int:
	var cells: Array[Vector2i] = _thick_cells(axis_cell, thick, width)
	var join: bool = false
	for c: Vector2i in cells:
		var i: int = ctx.idx(c)
		if i < 0:
			return ST_BLOCKED
		var k: int = ctx.cls[i]
		if mode == MODE_MAIN:
			continue
		if k == K_SHALLOW or k == K_DEEP:
			return ST_BLOCKED
		if mode == MODE_MAIN_DRY:
			continue
		if ctx.is_street(i):
			if ctx.owner[i] != walk_id:
				join = true
			continue
		if ctx.area[i] == 0 or k != K_GARDEN:
			return ST_BLOCKED
	if mode != MODE_BRANCH:
		return ST_OK
	if join:
		return ST_JOIN
	if step >= STRAIGHT_START:
		for c2: Vector2i in cells:
			for o: Vector2i in OFFS4:
				var ni: int = ctx.idx(c2 + o)
				if ni >= 0 and ctx.is_street(ni) and ctx.owner[ni] != walk_id:
					return ST_JOIN
	return ST_OK


## Desvío lateral de una principal: lejos del agua (los puentes y la orilla,
## rectos) y sin correr a lo largo de la muralla.
static func _main_lateral_ok(ctx: Ctx, pos: Vector2i, lp: Vector2i, thick: Vector2i, width: int) -> bool:
	for c: Vector2i in _thick_cells(pos, thick, width) + _thick_cells(lp, thick, width):
		var i: int = ctx.idx(c)
		if i < 0 or ctx.near_water[i] != 0:
			return false
		var k: int = ctx.cls[i]
		if k == K_WALL or k == K_GATE:
			return false
	return true


static func _paint(ctx: Ctx, axis_cell: Vector2i, thick: Vector2i, width: int, walk_id: int) -> void:
	for c: Vector2i in _thick_cells(axis_cell, thick, width):
		var i: int = ctx.idx(c)
		if i < 0:
			continue
		match ctx.cls[i]:
			K_GARDEN, K_FIELD:
				ctx.cls[i] = K_STREET
				ctx.owner[i] = walk_id
				ctx.area[i] = 0
			K_SHALLOW, K_DEEP:
				ctx.cls[i] = K_BRIDGE
				ctx.owner[i] = walk_id
			K_WALL:
				ctx.cls[i] = K_GATE
				ctx.owner[i] = walk_id


## Quita las calles que no se alcanzan desde la plaza (BFS con vecinos de 4):
## la red que queda es conexa por construcción.
static func _keep_connected_streets(ctx: Ctx) -> void:
	var n: int = ctx.w * ctx.h
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var start: int = ctx.idx(ctx.center)
	if start < 0 or not ctx.is_street(start):
		return
	var queue: PackedInt32Array = PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var c: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
		for o: Vector2i in OFFS4:
			var ni: int = ctx.idx(c + o)
			if ni >= 0 and seen[ni] == 0 and ctx.is_street(ni):
				seen[ni] = 1
				queue.append(ni)
	for i2: int in n:
		if ctx.is_street(i2) and seen[i2] == 0:
			ctx.cls[i2] = ctx.base[i2]
			ctx.owner[i2] = 0


# --- 4. Parcelación ----------------------------------------------------------------

## Fachadas candidatas ordenadas y su memoria de fallos.
class Placer:
	extends RefCounted
	## Casilla de fachada y dirección (OFFS4) hacia la calle, por candidata.
	var cells: Array[Vector2i] = []
	var dirs: PackedInt32Array = PackedInt32Array()
	## Índices de candidatas en orden de prueba.
	var order: PackedInt32Array = PackedInt32Array()
	## Parcela más pequeña (ancho, alto del anillo) que ya falló; 0 = ninguna.
	var fail: Array[Vector2i] = []
	## Primera posición de `order` que puede seguir viva.
	var first: int = 0

	func build(ctx: Ctx, rng: Rng) -> void:
		var keys: PackedInt64Array = PackedInt64Array()
		for i: int in ctx.w * ctx.h:
			if not AldGeneratorG1._is_free_lot(ctx, i):
				continue
			var c: Vector2i = Vector2i(i % ctx.w, i / ctx.w)
			for d: int in OFFS4.size():
				var ni: int = ctx.idx(c + OFFS4[d])
				if ni < 0:
					continue
				var k: int = ctx.cls[ni]
				if k != K_STREET and k != K_PLAZA:
					continue
				var dist: int = absi(c.x - ctx.center.x) + absi(c.y - ctx.center.y)
				var score: int = dist + rng.range_int(0, JITTER)
				keys.append((score << 32) | cells.size())
				cells.append(c)
				dirs.append(d)
				fail.append(Vector2i.ZERO)
		keys.sort()
		for key: int in keys:
			order.append(key & 0xFFFFFFFF)


## Coloca el edificio en la primera fachada donde cabe su parcela.
static func _place(ctx: Ctx, placer: Placer, b: Building, yard: int, step: Vector2i) -> void:
	var ring: Vector2i = b.dims + Vector2i(2, 2)
	var yards: PackedInt32Array = PackedInt32Array([yard, 0]) if yard > 0 else PackedInt32Array([0])
	for oi: int in range(placer.first, placer.order.size()):
		var k: int = placer.order[oi]
		var f: Vector2i = placer.cells[k]
		if not _is_free_lot(ctx, ctx.idx(f)):
			if oi == placer.first:
				placer.first += 1
			continue
		var fl: Vector2i = placer.fail[k]
		if fl.x > 0 and ring.x >= fl.x and ring.y >= fl.y:
			continue
		for yd: int in yards:
			for align: int in 3:
				var rects: Array[Rect2i] = _parcel_rects(f, OFFS4[placer.dirs[k]], ring, align, yd, step)
				if _parcel_free(ctx, rects[1]):
					_occupy(ctx, b, rects[0], rects[1])
					return
		if fl.x == 0 or (ring.x <= fl.x and ring.y <= fl.y):
			placer.fail[k] = ring


## [anillo, parcela] para la fachada `f` con la calle en `f + dir`: el anillo
## (huella + 1) se apoya en la calle (alineado al centro, a la izquierda o a la
## derecha de `f`), se corre 1 casilla si la paridad de la rejilla lo exige y la
## parcela es el anillo más `f` más el patio detrás (lado opuesto a la calle).
static func _parcel_rects(f: Vector2i, dir: Vector2i, ring: Vector2i, align: int, yard: int, step: Vector2i) -> Array[Rect2i]:
	var rx: int = 0
	var ry: int = 0
	if dir.y != 0:
		ry = f.y if dir.y < 0 else f.y - (ring.y - 1)
		rx = _aligned(f.x, ring.x, align)
	else:
		rx = f.x if dir.x < 0 else f.x - (ring.x - 1)
		ry = _aligned(f.y, ring.y, align)
	# Paridad: en el eje de la calle se aleja de ella; en el otro, +1.
	if step.x == 2 and posmod(rx, 2) != 0:
		rx += -dir.x if dir.x != 0 else 1
	if step.y == 2 and posmod(ry, 2) != 0:
		ry += -dir.y if dir.y != 0 else 1
	var ring_rect: Rect2i = Rect2i(rx, ry, ring.x, ring.y)
	var parcel: Rect2i = ring_rect.merge(Rect2i(f, Vector2i.ONE))
	if yard > 0:
		# Patio detrás de la casa (en el lado opuesto a la calle).
		parcel = parcel.grow_individual(yard if dir.x > 0 else 0, yard if dir.y > 0 else 0,
			yard if dir.x < 0 else 0, yard if dir.y < 0 else 0)
	var out: Array[Rect2i] = [ring_rect, parcel]
	return out


## Inicio de un tramo de largo `length` que contiene `v`: centrado (0), con `v`
## al principio (1) o al final (2).
static func _aligned(v: int, length: int, align: int) -> int:
	if align == 1:
		return v
	if align == 2:
		return v - (length - 1)
	return v - (length - 1) / 2


static func _parcel_free(ctx: Ctx, r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > ctx.w or r.end.y > ctx.h:
		return false
	for y: int in range(r.position.y, r.end.y):
		var row: int = y * ctx.w
		for x: int in range(r.position.x, r.end.x):
			if not _is_free_lot(ctx, row + x):
				return false
	return true


## Casilla libre que se puede parcelar (huerto o campo, sin calle ni agua).
static func _is_free_lot(ctx: Ctx, i: int) -> bool:
	var k: int = ctx.cls[i]
	return ctx.lot[i] == 1 and (k == K_GARDEN or k == K_FIELD)


static func _occupy(ctx: Ctx, b: Building, ring_rect: Rect2i, parcel: Rect2i) -> void:
	b.placed = true
	b.offset = ring_rect.position
	b.parcel = parcel
	b.footprint = Rect2i(ring_rect.position + Vector2i(1, 1), b.dims)
	for y: int in range(parcel.position.y, parcel.end.y):
		for x: int in range(parcel.position.x, parcel.end.x):
			var i: int = y * ctx.w + x
			ctx.cls[i] = K_BUILDING if b.footprint.has_point(Vector2i(x, y)) else K_YARD
			ctx.parcel_of[i] = b.order + 1


# --- 5. Volcado al documento ---------------------------------------------------------

static func _commit(doc: MapDocument, ctx: Ctx, res: Result) -> void:
	var level: MapLevel = doc.level(0)
	var grid: GridGeometry = doc.grid
	var n: int = ctx.w * ctx.h
	# Zonas únicas, en el orden de las clases (solo las que tienen casillas).
	var zone_ids: PackedInt32Array = PackedInt32Array()
	zone_ids.resize(ZONE_OF_CLASS.size())
	zone_ids.fill(0)
	var present: PackedByteArray = PackedByteArray()
	present.resize(ZONE_OF_CLASS.size())
	present.fill(0)
	for i: int in n:
		present[ctx.cls[i]] = 1
	for k: int in ZONE_OF_CLASS.size():
		if present[k] != 0 and not ZONE_OF_CLASS[k].is_empty():
			var r: MapRoom = MapRoom.make(doc.allocate_id(), ZONE_OF_CLASS[k])
			level.add_room(r)
			zone_ids[k] = r.id
	# Por edificio: parcela (patio) y huella; ids en orden de edificio.
	var by_order: Dictionary[int, Building] = {}
	for b: Building in res.buildings:
		if not b.placed:
			continue
		by_order[b.order] = b
		var yr: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_YARD)
		level.add_room(yr)
		b.yard_room_id = yr.id
		var br: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_BUILDING)
		level.add_room(br)
		b.room_id = br.id
	for i2: int in n:
		var k2: int = ctx.cls[i2]
		var t: int = Terrain.FLOOR
		if k2 == K_WALL:
			t = Terrain.WALL
		elif k2 == K_SHALLOW:
			t = Terrain.WATER_SHALLOW
		elif k2 == K_DEEP:
			t = Terrain.WATER_DEEP
		level.terrain[i2] = t
		var rid: int = zone_ids[k2]
		if k2 == K_YARD or k2 == K_BUILDING:
			var owner_b: Building = by_order[ctx.parcel_of[i2] - 1]
			rid = owner_b.yard_room_id if k2 == K_YARD else owner_b.room_id
		level.room_ids[i2] = rid
	var wall: int = MapEdge.make(MapEdge.KIND_WALL)
	for b2: Building in res.buildings:
		if not b2.placed:
			continue
		# Muro en todo el contorno de la huella (como el muro exterior de EDI)…
		for y: int in range(b2.footprint.position.y, b2.footprint.end.y):
			for x: int in range(b2.footprint.position.x, b2.footprint.end.x):
				var c: Vector2i = Vector2i(x, y)
				for d: int in grid.edge_direction_count():
					if not b2.footprint.has_point(grid.neighbor(c, d)):
						level.set_edge(c, d, wall)
		# …con las puertas exteriores y las ventanas de su planta baja EDI,
		# trasladadas (la traslación conserva vecinos: translation_step).
		for dr: Vector3i in b2.ground.doors:
			var dc: Vector2i = Vector2i(dr.x, dr.y) + b2.offset
			if not b2.footprint.has_point(grid.neighbor(dc, dr.z)):
				level.set_edge(dc, dr.z, MapEdge.make(MapEdge.KIND_DOOR))
		for wn: Vector3i in b2.ground.windows:
			level.set_edge(Vector2i(wn.x, wn.y) + b2.offset, wn.z, MapEdge.make(MapEdge.KIND_WINDOW))
		var mc: MapChild = MapChild.new()
		mc.id = doc.allocate_id()
		mc.kind = b2.edi.building_type
		mc.seed_code = b2.code
		mc.room_id = b2.room_id
		mc.offset = b2.offset
		mc.child_level = b2.ground_level
		mc.rect = b2.footprint
		mc.entrance = b2.entrance
		level.add_child_map(mc)


## Población derivada de un documento ALD: suma de los habitantes de cada
## tipo de edificio hijo (data). En G1 no es un parámetro (ADR 027).
static func population_of(doc: MapDocument) -> int:
	var data: AldData = AldData.load_default()
	var total: int = 0
	for lvl: MapLevel in doc.levels:
		for c: MapChild in lvl.children:
			total += data.residents_of(c.kind)
	return total
