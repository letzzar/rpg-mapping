class_name EdiGeneratorG1
extends RefCounted
## Generador de edificios EDI, versión G1 (PROYECTO §6.4, ADR 026).
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA (aquí, en EdiData, en los datos
## data/buildings o en el bloque "building" de data/styles, y también en lo que
## usa de EST: EstFurnisherG1 y sus datos) EXIGE GEN NUEVO: copiar a
## core/gen/edi/legacy/, registrar G2 y añadir seeds doradas nuevas.
##
## Puro y determinista (CLAUDE.md §6): solo enteros, todo el azar sale del Rng
## recibido y de sus hijos, listas en orden fijo; los diccionarios solo se
## consultan por clave.
##
## Mapa: huella rectangular del edificio (w×h casillas interiores, según tipo,
## tamaño y % del estilo) rodeada por un anillo de 1 casilla: en la planta
## baja es suelo exterior (zona "outside" + "entrance" delante de la puerta
## principal + "exit" delante de la trasera); en las demás plantas, VOID.
## Niveles de abajo arriba: [sótano] + planta baja + plantas altas (MapStair
## sube si to_level > nivel propio).
##
## Muros (ADR 018): TODOS en arista, también el exterior (KIND_WALL entre una
## casilla de la huella y otra de otra estancia o de fuera). Así una ventana
## (KIND_WINDOW) es una arista del muro exterior que deja ver, Universal VTT
## (F3) exporta segmentos de muro sin vectorizar y el 3D (ADR 025) dibuja
## módulos de pared en el borde con huecos de puerta y ventana.
##
## Jerarquía de semillas (§5.2):
##   raíz ── fork("shrink", 0)         recorte de las plantas altas
##        ├─ fork("level", i)          planta i: distribución, puertas, ventanas
##        │    ├─ fork("layout", t)    intento t de distribución (BSP)
##        │    ├─ fork("doors", t)     puertas del intento t
##        │    └─ fork("windows", 0) ─ fork("room", k) ventanas de la estancia k
##        ├─ fork("stairs_up", i)      escalera de la planta i-1 a la i
##        ├─ fork("stairs_down", 0)    escalera de la planta baja al sótano
##        └─ hash64(semilla, "EST", nivel × 256 + orden)  mobiliario de cada
##             estancia: Rng.new(h).fork("furnish", 0), igual que EST G1 con
##             la semilla h (misma fuente de azar; ver room_seed()).
##
## Algoritmo por planta (coste ~O(intentos × (casillas + puertas²)) más el
## amueblado, que domina: O(objetos × casillas) por estancia):
## 1. Estancias de la planta (data: "ground", "upper" o "cellar") en orden de
##    prioridad, con su peso de área. Pares de adyacencia obligatorios.
## 2. Distribución:
##    - Con hub (pasillo/recibidor): "espina" de 1 casilla (2 si el lado
##      corto >= 10) a lo largo del eje largo, que pasa por la escalera que
##      llega de abajo; las demás estancias son rebanadas perpendiculares a
##      cada lado, proporcionales a su área (lado >= 3): todas tocan el hub.
##    - Sin hub: BSP por pesos (treemap) cortando siempre el lado largo,
##      con desplazamiento ±1 y lado bajo/alto al azar; hasta LAYOUT_TRIES
##      intentos hasta que todas las adyacencias obligatorias tengan puerta.
##      Si ninguno lo consigue: se añade un hub ("hall") y se usa la espina;
##      las adyacencias que no queden en contacto se cumplen A TRAVÉS del hub.
##    Si no caben (lado < 3), se descartan las últimas estancias de la lista.
## 3. Puertas (aristas KIND_DOOR): principal en la estancia "entrance" hacia
##    el exterior; trasera opcional; una por par obligatorio; una de cada
##    estancia al hub; y hasta que todas las estancias se alcancen desde la
##    raíz (entrada, o la escalera que llega), una a una vecina ya alcanzada.
##    Preferencia: ninguna casilla a distancia <= 1 de otra puerta; si no se
##    puede, sin compartir casilla. Nunca en una casilla de escalera.
## 4. Ventanas en las aristas exteriores (no en el sótano): ~aristas ×
##    window_permille × window_pct/100 / 1000, separadas de puertas y entre sí.
## 5. Escaleras: de la estancia "stairs_up" (planta baja) o del hub (plantas
##    altas) a la planta de arriba, dentro de su huella, en la misma casilla en
##    las dos plantas; al sótano desde "stairs_down".
## 6. Amueblado de cada estancia con EstFurnisherG1 (entradas = casillas de
##    sus puertas y escaleras, que quedan libres y conectadas).
##
## Garantías por construcción: toda estancia queda unida a la raíz de su planta
## por puertas (paso 3; la partición del rectángulo es conexa) y las plantas
## por escaleras, así que toda casilla transitable se alcanza desde la entrada
## (Connectivity; lo comprueban los tests con muchas semillas).

const SCALE: String = "EDI"
const GEN: int = 1

## Lado mínimo de una estancia.
const MIN_SIDE: int = 3
const LAYOUT_TRIES: int = 12
## Clave y tipo del hub que se añade si las adyacencias no se cumplen.
const FALLBACK_HUB_KEY: String = "_hall"
const HUB_KIND: String = "hall"
## Id estable de una estancia para su semilla: nivel × 256 + orden.
const ROOM_STRIDE: int = 256
const SIZE_IDS: PackedStringArray = ["auto", "small", "medium", "large"]


## Parámetros resueltos (campos del esquema EDI G1).
class Params:
	extends RefCounted
	var building_type: String = "tavern"
	var grid_kind: String = "square"
	var style: String = "human"
	## 0 = las del tipo.
	var floors: int = 0
	var cellar: bool = false
	var size_id: String = "auto"
	var clutter: int = 5


## Estancia de una planta.
class Slot:
	extends RefCounted
	var key: String = ""
	var kind: String = ""
	var area: int = 0
	var hub: bool = false
	var windows: bool = true
	## Índice en la lista de la planta (id estable de la semilla).
	var order: int = 0
	## Tamaño 0 = descartada (no cabía).
	var rect: Rect2i = Rect2i()
	## Id de la MapRoom (tras volcar al documento).
	var room_id: int = 0

	func placed() -> bool:
		return rect.size.x > 0 and rect.size.y > 0


## Planta en construcción (también es el informe que leen los tests).
class Floor:
	extends RefCounted
	var level_index: int = 0
	## EdiData.FLOOR_*.
	var floor_class: String = ""
	var footprint: Rect2i = Rect2i()
	var slots: Array[Slot] = []
	## Pares de índices de slots con puerta obligatoria.
	var pairs: Array[Vector2i] = []
	## Slot de cada casilla del mapa (-1 = fuera de la huella).
	var cell_slot: PackedInt32Array = PackedInt32Array()
	## Puertas y ventanas: (x, y, dirección) desde una casilla de la huella.
	var doors: Array[Vector3i] = []
	var windows: Array[Vector3i] = []
	## Índices de las casillas a ambos lados de cada puerta.
	var door_cells: PackedInt32Array = PackedInt32Array()
	var door_edges: Dictionary[int, bool] = {}
	## Escaleras de esta planta (la que llega de abajo y la que sube).
	var stairs: Array[Vector2i] = []
	## Escaleras que llegan de otra planta (la distribución las respeta).
	var cover: Array[Vector2i] = []
	## Se añadió el hub de reserva porque las adyacencias no se cumplían.
	var fallback_hub: bool = false
	## Casillas exteriores delante de la puerta principal y la trasera.
	var entrance_cell: Vector2i = Vector2i(-1, -1)
	var exit_cell: Vector2i = Vector2i(-1, -1)
	var root_slot: int = -1

	func hub_index() -> int:
		for i: int in slots.size():
			if slots[i].hub and slots[i].placed():
				return i
		return -1

	func slot_index(key: String) -> int:
		for i: int in slots.size():
			if slots[i].key == key and slots[i].placed():
				return i
		return -1

	func is_stair(c: Vector2i) -> bool:
		return stairs.has(c)


## Resultado de generate_building().
class Result:
	extends RefCounted
	var doc: MapDocument = null
	## Plantas por índice de nivel.
	var floors: Array[Floor] = []
	var ground_level: int = 0


## Punto de entrada registrado en GeneratorRegistry.
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var res: Result = generate_building(params_from(code), rng)
	return res.doc if res != null else null


static func params_from(code: SeedCode) -> Params:
	var p: Params = Params.new()
	var building_type: String = code.params["building_type"]
	var grid_kind: String = code.params["grid"]
	var style: String = code.params["style"]
	var floors: int = code.params["floors"]
	var cellar: bool = code.params["cellar"]
	var size_id: String = code.params["size"]
	var clutter: int = code.params["clutter"]
	p.building_type = building_type
	p.grid_kind = grid_kind
	p.style = style
	p.floors = floors
	p.cellar = cellar
	p.size_id = size_id
	p.clutter = clutter
	return p


## Semilla del mobiliario de la estancia `order` del nivel `level_index`
## (§5.2): con ella, Rng.new(semilla).fork("furnish", 0) es exactamente el Rng
## con el que EST G1 amueblaría una estancia aislada de esa semilla.
static func room_seed(building_seed: int, level_index: int, order: int) -> int:
	return SplitMix64.hash64(building_seed, "EST", level_index * ROOM_STRIDE + order)


## Huella interior (ancho × alto) del edificio.
static func footprint_size(bt: EdiData.BuildingType, sb: EdiData.StyleBuilding, size_id: String) -> Vector2i:
	var sid: String = bt.auto_size if size_id == "auto" or not EdiData.SIZE_IDS.has(size_id) else size_id
	var base: Vector2i = bt.footprint(sid)
	var w: int = maxi(EdiData.MIN_FOOTPRINT_SIDE, (base.x * sb.footprint_pct + 50) / 100)
	var h: int = maxi(EdiData.MIN_FOOTPRINT_SIDE, (base.y * sb.footprint_pct + 50) / 100)
	return Vector2i(w, h)


## Edificio completo a partir de sus parámetros y su Rng (puro). null si el
## tipo, el estilo o la rejilla no existen.
static func generate_building(p: Params, rng: Rng) -> Result:
	var data: EdiData = EdiData.load_default()
	if not data.is_valid():
		return null
	var bt: EdiData.BuildingType = data.building_type(p.building_type)
	var sb: EdiData.StyleBuilding = data.style_building(p.style)
	if bt == null or sb == null:
		return null
	var dims: Vector2i = footprint_size(bt, sb, p.size_id)
	var floors: int = p.floors if p.floors > 0 else bt.floors
	var cellar_n: int = 1 if p.cellar else 0
	var doc: MapDocument = MapDocument.create(p.grid_kind, dims.x + 2, dims.y + 2, floors + cellar_n)
	if doc == null:
		return null
	var res: Result = Result.new()
	res.doc = doc
	res.ground_level = cellar_n
	var grid: GridGeometry = doc.grid
	# Huellas: el sótano y la planta baja ocupan todo; cada planta alta puede
	# recortar un extremo de la de abajo.
	var fps: Array[Rect2i] = []
	for li: int in doc.level_count():
		fps.append(Rect2i(1, 1, dims.x, dims.y))
	var shrink_rng: Rng = rng.fork("shrink", 0)
	for li: int in range(cellar_n + 1, doc.level_count()):
		fps[li] = _shrunk(fps[li - 1], bt.upper_shrink_permille, shrink_rng)
	for li: int in doc.level_count():
		res.floors.append(null)
	var none: Array[Vector2i] = []
	var ground: Floor = _build_floor(grid, bt, sb, cellar_n, EdiData.FLOOR_GROUND, fps[cellar_n], none, rng.fork("level", cellar_n))
	_commit_floor(doc, ground)
	res.floors[cellar_n] = ground
	var below: Floor = ground
	for li: int in range(cellar_n + 1, doc.level_count()):
		var key: String = bt.stairs_up if below == ground else ""
		var s: Vector2i = _pick_stair(grid, below, key, fps[li], rng.fork("stairs_up", li))
		below.stairs.append(s)
		var cover: Array[Vector2i] = [s]
		var f: Floor = _build_floor(grid, bt, sb, li, EdiData.FLOOR_UPPER, fps[li], cover, rng.fork("level", li))
		_commit_floor(doc, f)
		_add_stair_pair(doc, li - 1, li, s)
		res.floors[li] = f
		below = f
	if p.cellar:
		var sd: Vector2i = _pick_stair(grid, ground, bt.stairs_down, fps[0], rng.fork("stairs_down", 0))
		ground.stairs.append(sd)
		var cover_c: Array[Vector2i] = [sd]
		var cf: Floor = _build_floor(grid, bt, sb, 0, EdiData.FLOOR_CELLAR, fps[0], cover_c, rng.fork("level", 0))
		_commit_floor(doc, cf)
		_add_stair_pair(doc, 0, cellar_n, sd)
		res.floors[0] = cf
	for f2: Floor in res.floors:
		_furnish_floor(doc, f2, p, rng.seed_value)
	return res


## Planta baja de un edificio SIN generar el resto (la usa ALD G1, ADR 027,
## para conocer la puerta principal, la trasera y las ventanas de cada
## edificio hijo sin pagar el amueblado). Es exactamente la planta que
## construye generate_building() con los mismos parámetros y el mismo Rng: sale
## solo de la huella y de fork("level", nivel de la planta baja), y sus puertas
## y ventanas se planifican antes que las escaleras, las demás plantas y el
## mobiliario, que no las tocan. Coordenadas de la rejilla del edificio
## ((ancho + 2) × (alto + 2), con el anillo exterior). No cambia la salida de
## EDI G1 (solo es otra entrada; lo vigilan sus seeds doradas y
## test_ald_generator). null si el tipo, el estilo o la rejilla no existen.
static func plan_ground_floor(p: Params, rng: Rng) -> Floor:
	var data: EdiData = EdiData.load_default()
	if not data.is_valid():
		return null
	var bt: EdiData.BuildingType = data.building_type(p.building_type)
	var sb: EdiData.StyleBuilding = data.style_building(p.style)
	if bt == null or sb == null:
		return null
	var dims: Vector2i = footprint_size(bt, sb, p.size_id)
	var grid: GridGeometry = GridFactory.create(p.grid_kind, dims.x + 2, dims.y + 2)
	if grid == null:
		return null
	var cellar_n: int = 1 if p.cellar else 0
	var none: Array[Vector2i] = []
	return _build_floor(grid, bt, sb, cellar_n, EdiData.FLOOR_GROUND, Rect2i(1, 1, dims.x, dims.y), none, rng.fork("level", cellar_n))


# --- Huellas y escaleras ---------------------------------------------------------

## Recorta max(1, largo/4) casillas de un extremo del eje largo con
## probabilidad `permille`, si quedan al menos 2·MIN_SIDE + 1.
static func _shrunk(fp: Rect2i, permille: int, rng: Rng) -> Rect2i:
	if not rng.chance_permille(permille):
		return fp
	var horizontal: bool = fp.size.x >= fp.size.y
	var long_side: int = fp.size.x if horizontal else fp.size.y
	var cut: int = maxi(1, long_side / 4)
	if long_side - cut < 2 * MIN_SIDE + 1:
		return fp
	var from_start: bool = rng.chance_permille(500)
	if horizontal:
		return Rect2i(fp.position.x + (cut if from_start else 0), fp.position.y, fp.size.x - cut, fp.size.y)
	return Rect2i(fp.position.x, fp.position.y + (cut if from_start else 0), fp.size.x, fp.size.y - cut)


## Casilla de la escalera que sale de la planta `f` hacia otra de huella
## `next_fp`: en la estancia `key` (o el hub, o la raíz), dentro de next_fp,
## fuera de las puertas y escaleras. Por niveles de preferencia (la primera
## lista no vacía; dentro, al azar):
##   0 en la estancia, sin puertas al lado, contra una pared y en una fila
##     que deja a la espina de arriba un lado >= MIN_SIDE a cada lado;
##   1 igual sin "contra una pared"; 2 sin la fila; 3 junto a una puerta;
##   4 en otra estancia; 5 cualquiera (también junto a otra escalera).
## La fila importa: con la escalera pegada al borde, la espina de la planta de
## arriba solo tiene un lado y caben la mitad de las habitaciones (medido: la
## posada perdía 2 de 6 dormitorios).
static func _pick_stair(grid: GridGeometry, f: Floor, key: String, next_fp: Rect2i, rng: Rng) -> Vector2i:
	var si: int = f.slot_index(key) if not key.is_empty() else -1
	if si < 0:
		si = f.hub_index()
	if si < 0:
		si = f.root_slot
	var horizontal: bool = next_fp.size.x >= next_fp.size.y
	var tiers: Array[Array] = [[], [], [], [], [], []]
	for i: int in grid.cell_count():
		var c: Vector2i = grid.cell_at(i)
		if f.cell_slot[i] < 0 or not next_fp.has_point(c) or f.door_cells.has(i) or f.stairs.has(c):
			continue
		var near_stair: bool = false
		for s: Vector2i in f.stairs:
			if grid.distance(s, c) <= 1:
				near_stair = true
		var near_door: bool = false
		for di: int in f.door_cells:
			if grid.distance(grid.cell_at(di), c) <= 1:
				near_door = true
		var tier: int = 5
		if not near_stair:
			if f.cell_slot[i] != si:
				tier = 4
			elif near_door:
				tier = 3
			else:
				var off: int = (c.y - next_fp.position.y) if horizontal else (c.x - next_fp.position.x)
				var span: int = next_fp.size.y if horizontal else next_fp.size.x
				var good_row: bool = off >= MIN_SIDE and span - off - 1 >= MIN_SIDE
				var against_wall: bool = false
				for d: int in grid.edge_direction_count():
					var ni: int = grid.index_of(grid.neighbor(c, d))
					if ni < 0 or f.cell_slot[ni] != si:
						against_wall = true
				tier = 2
				if good_row:
					tier = 0 if against_wall else 1
		tiers[tier].append(c)
	for t: Array in tiers:
		if not t.is_empty():
			var pick: Vector2i = t[rng.pick_index(t.size())]
			return pick
	return next_fp.position


static func _add_stair_pair(doc: MapDocument, lower: int, upper: int, cell: Vector2i) -> void:
	for pair: Vector2i in [Vector2i(lower, upper), Vector2i(upper, lower)]:
		var s: MapStair = MapStair.new()
		s.id = doc.allocate_id()
		s.cell = cell
		s.to_level = pair.y
		s.to_cell = cell
		s.facing = 0
		doc.level(pair.x).add_stair(s)


# --- Planta ----------------------------------------------------------------------

static func _build_floor(grid: GridGeometry, bt: EdiData.BuildingType, sb: EdiData.StyleBuilding, li: int,
		floor_class: String, fp: Rect2i, cover: Array[Vector2i], rng: Rng) -> Floor:
	var f: Floor = Floor.new()
	f.level_index = li
	f.floor_class = floor_class
	f.footprint = fp
	f.cover = cover.duplicate()
	var specs: Array[EdiData.RoomSpec] = bt.rooms_on(floor_class)
	var has_hub: bool = false
	for s: EdiData.RoomSpec in specs:
		has_hub = has_hub or s.hub
	if has_hub:
		_reset(grid, f, specs, false, bt)
		_spine_layout(f, rng.fork("layout", 0))
		_assign_cells(grid, f)
		_plan_doors(grid, f, bt, rng.fork("doors", 0))
	else:
		var accepted: bool = false
		for t: int in LAYOUT_TRIES:
			_reset(grid, f, specs, false, bt)
			var idx: PackedInt32Array = PackedInt32Array()
			for i: int in f.slots.size():
				idx.append(i)
			_treemap(f, idx, fp, rng.fork("layout", t))
			_assign_cells(grid, f)
			if _plan_doors(grid, f, bt, rng.fork("doors", t)):
				accepted = true
				break
		if not accepted:
			_reset(grid, f, specs, true, bt)
			f.fallback_hub = true
			_spine_layout(f, rng.fork("layout", LAYOUT_TRIES))
			_assign_cells(grid, f)
			_plan_doors(grid, f, bt, rng.fork("doors", LAYOUT_TRIES))
	_plan_windows(grid, f, bt, sb, rng.fork("windows", 0))
	return f


## Deja la planta sin distribución, con un slot por estancia de los datos (y
## el hub de reserva al final si `with_fallback_hub`).
static func _reset(grid: GridGeometry, f: Floor, specs: Array[EdiData.RoomSpec], with_fallback_hub: bool, bt: EdiData.BuildingType) -> void:
	f.slots.clear()
	for s: EdiData.RoomSpec in specs:
		var sl: Slot = Slot.new()
		sl.key = s.key
		sl.kind = s.kind
		sl.area = s.area
		sl.hub = s.hub
		sl.windows = s.windows and not s.hub
		sl.order = f.slots.size()
		f.slots.append(sl)
	if with_fallback_hub:
		var hub: Slot = Slot.new()
		hub.key = FALLBACK_HUB_KEY
		hub.kind = HUB_KIND
		hub.hub = true
		hub.windows = false
		hub.order = f.slots.size()
		f.slots.append(hub)
	f.pairs.clear()
	for pair: PackedStringArray in bt.adjacency:
		var a: int = -1
		var b: int = -1
		for i: int in f.slots.size():
			if f.slots[i].key == pair[0]:
				a = i
			elif f.slots[i].key == pair[1]:
				b = i
		if a >= 0 and b >= 0:
			f.pairs.append(Vector2i(a, b))
	f.cell_slot.resize(grid.cell_count())
	f.cell_slot.fill(-1)
	f.doors.clear()
	f.windows.clear()
	f.door_cells.clear()
	f.door_edges.clear()
	f.entrance_cell = Vector2i(-1, -1)
	f.exit_cell = Vector2i(-1, -1)
	f.root_slot = -1
	f.stairs = f.cover.duplicate()


static func _assign_cells(grid: GridGeometry, f: Floor) -> void:
	f.cell_slot.fill(-1)
	for i: int in f.slots.size():
		if not f.slots[i].placed():
			continue
		for c: Vector2i in rect_cells(f.slots[i].rect):
			var ci: int = grid.index_of(c)
			if ci >= 0:
				f.cell_slot[ci] = i


static func rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


# --- Distribución -----------------------------------------------------------------

## BSP por pesos: corta el lado largo de `rect` para repartir `idx` en dos
## grupos de peso parecido (prefijo de la lista, que conserva el orden de los
## datos y por tanto las cadenas de adyacencias), con ±1 al azar y el primer
## grupo en el lado bajo o alto al azar. Si el lado largo < 2·MIN_SIDE, la
## primera estancia se queda el rectángulo y las demás se descartan.
static func _treemap(f: Floor, idx: PackedInt32Array, rect: Rect2i, rng: Rng) -> void:
	var n: int = idx.size()
	if n == 0:
		return
	if n == 1:
		f.slots[idx[0]].rect = rect
		return
	var split_x: bool = rect.size.x >= rect.size.y
	var length: int = rect.size.x if split_x else rect.size.y
	if length < 2 * MIN_SIDE:
		f.slots[idx[0]].rect = rect
		return
	var total: int = 0
	for i: int in idx:
		total += f.slots[i].area
	var k: int = 1
	var prefix: int = f.slots[idx[0]].area
	var best: int = absi(2 * prefix - total)
	var wa: int = prefix
	for j: int in range(1, n - 1):
		prefix += f.slots[idx[j]].area
		var d: int = absi(2 * prefix - total)
		if d < best:
			best = d
			k = j + 1
			wa = prefix
	var la: int = clampi((length * wa + total / 2) / maxi(1, total) + rng.range_int(-1, 1), MIN_SIDE, length - MIN_SIDE)
	var flip: bool = rng.chance_permille(500)
	var a_off: int = length - la if flip else 0
	var b_off: int = 0 if flip else la
	var lb: int = length - la
	var ra: Rect2i
	var rb: Rect2i
	if split_x:
		ra = Rect2i(rect.position.x + a_off, rect.position.y, la, rect.size.y)
		rb = Rect2i(rect.position.x + b_off, rect.position.y, lb, rect.size.y)
	else:
		ra = Rect2i(rect.position.x, rect.position.y + a_off, rect.size.x, la)
		rb = Rect2i(rect.position.x, rect.position.y + b_off, rect.size.x, lb)
	_treemap(f, idx.slice(0, k), ra, rng)
	_treemap(f, idx.slice(k, n), rb, rng)


## Espina: el hub recorre el eje largo de la huella pasando por las escaleras
## que llegan (f.cover); las demás estancias son rebanadas perpendiculares a
## un lado y otro (cada lado vacío o de fondo >= MIN_SIDE), así que todas
## tocan el hub. Grosor preferido 1 (2 si el lado corto >= 10); se elige la
## posición de menor puntuación (grosor extra, un solo lado, lados desiguales)
## y, entre empates, al azar.
static func _spine_layout(f: Floor, rng: Rng) -> void:
	var fp: Rect2i = f.footprint
	var hub: int = -1
	var others: PackedInt32Array = PackedInt32Array()
	for i: int in f.slots.size():
		if f.slots[i].hub and hub < 0:
			hub = i
		elif not f.slots[i].hub:
			others.append(i)
	var horizontal: bool = fp.size.x >= fp.size.y
	var lo: int = fp.position.y if horizontal else fp.position.x
	var span: int = fp.size.y if horizontal else fp.size.x
	var along_lo: int = fp.position.x if horizontal else fp.position.y
	var length: int = fp.size.x if horizontal else fp.size.y
	var m: int = others.size()
	var t_pref: int = 1 if span < 10 else 2
	var cover_v: PackedInt32Array = PackedInt32Array()
	for c: Vector2i in f.cover:
		cover_v.append(c.y if horizontal else c.x)
	var best: int = 1 << 30
	var cands: Array[Vector2i] = []
	for t: int in range(mini(t_pref, span - 1), span):
		for p: int in range(lo, lo + span - t + 1):
			var da: int = p - lo
			var db: int = lo + span - p - t
			if (da > 0 and da < MIN_SIDE) or (db > 0 and db < MIN_SIDE) or da + db == 0:
				continue
			if m < 2 and da > 0 and db > 0:
				continue
			var covers: bool = true
			for v: int in cover_v:
				if v < p or v >= p + t:
					covers = false
			if not covers:
				continue
			var score: int = (t - t_pref) * 1000 + (0 if (da > 0 and db > 0) or m < 2 else 500) + absi(da - db)
			if score < best:
				best = score
				cands.clear()
			if score == best:
				cands.append(Vector2i(p, t))
	if hub < 0 or cands.is_empty() or m == 0:
		# Sin posición posible (no ocurre con huellas >= 6): todo es hub.
		if hub >= 0:
			f.slots[hub].rect = fp
		elif m > 0:
			f.slots[others[0]].rect = fp
		return
	var pick: Vector2i = cands[rng.pick_index(cands.size())]
	var p0: int = pick.x
	var th: int = pick.y
	var da2: int = p0 - lo
	var db2: int = lo + span - p0 - th
	f.slots[hub].rect = Rect2i(along_lo, p0, length, th) if horizontal else Rect2i(p0, along_lo, th, length)
	var cap_a: int = length / MIN_SIDE if da2 > 0 else 0
	var cap_b: int = length / MIN_SIDE if db2 > 0 else 0
	var keep: int = mini(m, cap_a + cap_b)
	var total: int = 0
	for j: int in keep:
		total += f.slots[others[j]].area
	var k_lo: int = maxi(1 if da2 > 0 else 0, keep - cap_b)
	var k_hi: int = mini(keep - (1 if db2 > 0 else 0), cap_a)
	var k: int = k_lo
	var best_k: int = 1 << 62
	var prefix: int = 0
	for j: int in range(0, k_hi + 1):
		if j >= k_lo:
			var d: int = absi(prefix * (da2 + db2) - total * da2)
			if d < best_k:
				best_k = d
				k = j
		if j < keep:
			prefix += f.slots[others[j]].area
	_slice_side(f, others.slice(0, k), horizontal, along_lo, length, lo, da2, rng)
	_slice_side(f, others.slice(k, keep), horizontal, along_lo, length, p0 + th, db2, rng)


## Rebanadas perpendiculares a la espina en un lado de fondo `depth` que
## empieza en `start` (eje corto): longitudes proporcionales al área, ±1 al
## azar y >= MIN_SIDE.
static func _slice_side(f: Floor, idx: PackedInt32Array, horizontal: bool, along_lo: int, length: int,
		start: int, depth: int, rng: Rng) -> void:
	var n: int = idx.size()
	if n == 0 or depth <= 0:
		return
	var total: int = 0
	for i: int in idx:
		total += f.slots[i].area
	var b: PackedInt32Array = PackedInt32Array()
	b.resize(n + 1)
	b[0] = along_lo
	b[n] = along_lo + length
	var cum: int = 0
	for k: int in range(1, n):
		cum += f.slots[idx[k - 1]].area
		b[k] = along_lo + (length * cum + total / 2) / maxi(1, total) + rng.range_int(-1, 1)
	for k: int in range(1, n):
		b[k] = maxi(b[k], b[k - 1] + MIN_SIDE)
	for k: int in range(n - 1, 0, -1):
		b[k] = mini(b[k], b[k + 1] - MIN_SIDE)
	for k: int in n:
		var len_k: int = b[k + 1] - b[k]
		f.slots[idx[k]].rect = Rect2i(b[k], start, len_k, depth) if horizontal else Rect2i(start, b[k], depth, len_k)


# --- Puertas ------------------------------------------------------------------------

## Planifica las puertas de la planta (sin tocar el documento). Devuelve true
## si todos los pares obligatorios tienen puerta directa. La conectividad se
## garantiza siempre.
static func _plan_doors(grid: GridGeometry, f: Floor, bt: EdiData.BuildingType, rng: Rng) -> bool:
	var ok: bool = true
	if f.floor_class == EdiData.FLOOR_GROUND:
		var ent: int = f.slot_index(bt.entrance)
		if ent < 0:
			ent = _first_placed(f)
		f.root_slot = ent
		f.entrance_cell = _add_exterior_door(grid, f, ent, Vector2i(-1, -1), rng)
		if not bt.back_door.is_empty() and rng.chance_permille(bt.back_door_permille):
			var bd: int = f.slot_index(bt.back_door)
			if bd >= 0 and f.entrance_cell.x >= 0:
				f.exit_cell = _add_exterior_door(grid, f, bd, f.entrance_cell, rng, false)
	else:
		f.root_slot = -1
		if not f.cover.is_empty():
			var ci: int = grid.index_of(f.cover[0])
			f.root_slot = f.cell_slot[ci] if ci >= 0 else -1
		if f.root_slot < 0:
			f.root_slot = _first_placed(f)
	for pair: Vector2i in f.pairs:
		if not f.slots[pair.x].placed() or not f.slots[pair.y].placed():
			continue
		if _has_door_between(grid, f, pair.x, pair.y):
			continue
		if not _add_door_between(grid, f, pair.x, PackedInt32Array([pair.y]), rng):
			ok = false
	var hub: int = f.hub_index()
	if hub >= 0:
		for i: int in f.slots.size():
			if i != hub and f.slots[i].placed() and not _has_door_between(grid, f, i, hub):
				_add_door_between(grid, f, i, PackedInt32Array([hub]), rng)
	_connect_all(grid, f, rng)
	return ok


static func _first_placed(f: Floor) -> int:
	for i: int in f.slots.size():
		if f.slots[i].placed() and not f.slots[i].hub:
			return i
	for i: int in f.slots.size():
		if f.slots[i].placed():
			return i
	return -1


## Une a la raíz toda estancia que no se alcance, con una puerta a una vecina
## ya alcanzada (el hub primero; luego cualquiera; y, si ninguna puerta cabe
## sin compartir casilla, compartiéndola). Repite hasta que no quede ninguna.
static func _connect_all(grid: GridGeometry, f: Floor, rng: Rng) -> void:
	var guard: int = 2 * f.slots.size() + 2
	while guard > 0:
		guard -= 1
		var reached: PackedByteArray = _reached_slots(grid, f)
		var progress: bool = false
		var all_in: bool = true
		for i: int in f.slots.size():
			if not f.slots[i].placed() or reached[i] != 0:
				continue
			all_in = false
			var hub_t: PackedInt32Array = PackedInt32Array()
			var hub: int = f.hub_index()
			if hub >= 0 and reached[hub] != 0:
				hub_t.append(hub)
			var any_t: PackedInt32Array = PackedInt32Array()
			for j: int in f.slots.size():
				if reached[j] != 0:
					any_t.append(j)
			if (not hub_t.is_empty() and _add_door_between(grid, f, i, hub_t, rng)) \
					or _add_door_between(grid, f, i, any_t, rng):
				progress = true
				break
		if not all_in and not progress:
			# Último recurso: la primera estancia aislada que pueda, aunque la
			# puerta comparta casilla con otra.
			var reached2: PackedByteArray = _reached_slots(grid, f)
			var any2: PackedInt32Array = PackedInt32Array()
			for j2: int in f.slots.size():
				if reached2[j2] != 0:
					any2.append(j2)
			for i2: int in f.slots.size():
				if f.slots[i2].placed() and reached2[i2] == 0 and _add_door_between(grid, f, i2, any2, rng, true):
					progress = true
					break
		if all_in or not progress:
			return


## Estancias alcanzables desde la raíz por puertas interiores.
static func _reached_slots(grid: GridGeometry, f: Floor) -> PackedByteArray:
	var reached: PackedByteArray = PackedByteArray()
	reached.resize(f.slots.size())
	reached.fill(0)
	if f.root_slot < 0:
		return reached
	reached[f.root_slot] = 1
	var changed: bool = true
	while changed:
		changed = false
		for dr: Vector3i in f.doors:
			var a: int = f.cell_slot[grid.index_of(Vector2i(dr.x, dr.y))]
			var ni: int = grid.index_of(grid.neighbor(Vector2i(dr.x, dr.y), dr.z))
			var b: int = f.cell_slot[ni] if ni >= 0 else -1
			if a < 0 or b < 0:
				continue
			if reached[a] != reached[b]:
				reached[a] = 1
				reached[b] = 1
				changed = true
	return reached


static func _has_door_between(grid: GridGeometry, f: Floor, a: int, b: int) -> bool:
	for dr: Vector3i in f.doors:
		var sa: int = f.cell_slot[grid.index_of(Vector2i(dr.x, dr.y))]
		var ni: int = grid.index_of(grid.neighbor(Vector2i(dr.x, dr.y), dr.z))
		var sb: int = f.cell_slot[ni] if ni >= 0 else -1
		if (sa == a and sb == b) or (sa == b and sb == a):
			return true
	return false


## 0 = ninguna casilla a distancia <= 1 de otra puerta; 1 = sin compartir
## casilla; 2 = comparte casilla con otra puerta.
static func _door_tier(grid: GridGeometry, f: Floor, a: Vector2i, b: Vector2i) -> int:
	var tier: int = 0
	for di: int in f.door_cells:
		var dc: Vector2i = grid.cell_at(di)
		if dc == a or dc == b:
			return 2
		if grid.distance(dc, a) <= 1 or grid.distance(dc, b) <= 1:
			tier = 1
	return tier


## Puerta entre una casilla de la estancia `a` y una de alguna de `targets`.
## Con `allow_shared` = false nunca comparte casilla con otra puerta (solo
## _connect_all lo permite, como último recurso para no dejar una estancia
## aislada).
static func _add_door_between(grid: GridGeometry, f: Floor, a: int, targets: PackedInt32Array, rng: Rng, allow_shared: bool = false) -> bool:
	var tiers: Array[Array] = [[], [], []]
	for c: Vector2i in rect_cells(f.slots[a].rect):
		if f.is_stair(c):
			continue
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(c, d)
			var ni: int = grid.index_of(n)
			if ni < 0 or not targets.has(f.cell_slot[ni]) or f.cell_slot[ni] == a or f.is_stair(n):
				continue
			if f.door_edges.has(grid.edge_id(c, d)):
				continue
			tiers[_door_tier(grid, f, c, n)].append(Vector3i(c.x, c.y, d))
	for ti: int in tiers.size():
		var t: Array = tiers[ti]
		if ti == 2 and not allow_shared:
			break
		if not t.is_empty():
			var pick: Vector3i = t[rng.pick_index(t.size())]
			_add_door(grid, f, pick)
			return true
	return false


## Puerta de la estancia `slot` al exterior; devuelve la casilla de fuera
## ((-1, -1) si no hay sitio). `avoid`: otra casilla exterior de la que
## alejarse (>= 2). `fallback_any`: si la estancia no toca el exterior,
## probar las demás en orden.
static func _add_exterior_door(grid: GridGeometry, f: Floor, slot: int, avoid: Vector2i, rng: Rng, fallback_any: bool = true) -> Vector2i:
	var order: PackedInt32Array = PackedInt32Array([slot])
	if fallback_any:
		for i: int in f.slots.size():
			if i != slot and f.slots[i].placed():
				order.append(i)
	for s: int in order:
		if s < 0 or not f.slots[s].placed():
			continue
		var tiers: Array[Array] = [[], [], []]
		for c: Vector2i in rect_cells(f.slots[s].rect):
			if f.is_stair(c):
				continue
			for d: int in grid.edge_direction_count():
				var n: Vector2i = grid.neighbor(c, d)
				if not grid.in_bounds(n) or f.cell_slot[grid.index_of(n)] != -1:
					continue
				if avoid.x >= 0 and grid.distance(n, avoid) < 2:
					continue
				tiers[_door_tier(grid, f, c, n)].append(Vector3i(c.x, c.y, d))
		for t: Array in tiers:
			if not t.is_empty():
				var pick: Vector3i = t[rng.pick_index(t.size())]
				_add_door(grid, f, pick)
				return grid.neighbor(Vector2i(pick.x, pick.y), pick.z)
	return Vector2i(-1, -1)


static func _add_door(grid: GridGeometry, f: Floor, door: Vector3i) -> void:
	var c: Vector2i = Vector2i(door.x, door.y)
	f.doors.append(door)
	f.door_cells.append(grid.index_of(c))
	f.door_cells.append(grid.index_of(grid.neighbor(c, door.z)))
	f.door_edges[grid.edge_id(c, door.z)] = true


# --- Ventanas -------------------------------------------------------------------------

static func _plan_windows(grid: GridGeometry, f: Floor, bt: EdiData.BuildingType, sb: EdiData.StyleBuilding, rng: Rng) -> void:
	if f.floor_class == EdiData.FLOOR_CELLAR or bt.window_permille <= 0 or sb.window_pct <= 0:
		return
	var inner: Array[Vector2i] = []
	for i: int in f.slots.size():
		var sl: Slot = f.slots[i]
		if not sl.placed() or not sl.windows:
			continue
		var cands: Array[Vector3i] = []
		for c: Vector2i in rect_cells(sl.rect):
			for d: int in grid.edge_direction_count():
				var n: Vector2i = grid.neighbor(c, d)
				if grid.in_bounds(n) and f.cell_slot[grid.index_of(n)] == -1:
					cands.append(Vector3i(c.x, c.y, d))
		var want: int = (cands.size() * bt.window_permille * sb.window_pct / 100 + 500) / 1000
		var wrng: Rng = rng.fork("room", i)
		var placed: int = 0
		while placed < want and not cands.is_empty():
			var k: int = wrng.pick_index(cands.size())
			var cand: Vector3i = cands[k]
			cands.remove_at(k)
			var c2: Vector2i = Vector2i(cand.x, cand.y)
			var n2: Vector2i = grid.neighbor(c2, cand.z)
			var clear: bool = not f.is_stair(c2)
			for di: int in f.door_cells:
				var dc: Vector2i = grid.cell_at(di)
				if grid.distance(dc, c2) <= 1 or dc == n2:
					clear = false
			for w: Vector2i in inner:
				if grid.distance(w, c2) <= 1:
					clear = false
			if not clear:
				continue
			f.windows.append(cand)
			inner.append(c2)
			placed += 1


# --- Volcado al documento ------------------------------------------------------------

static func _commit_floor(doc: MapDocument, f: Floor) -> void:
	var level: MapLevel = doc.level(f.level_index)
	var grid: GridGeometry = doc.grid
	var ground: bool = f.floor_class == EdiData.FLOOR_GROUND
	if ground:
		level.fill_terrain(Terrain.FLOOR)
	for sl: Slot in f.slots:
		if not sl.placed():
			continue
		var r: MapRoom = MapRoom.make(doc.allocate_id(), sl.kind)
		level.add_room(r)
		sl.room_id = r.id
		for c: Vector2i in rect_cells(sl.rect):
			level.set_terrain(c, Terrain.FLOOR)
			level.set_room_id(c, r.id)
	if ground:
		for pair: Array in [[f.entrance_cell, MapRoom.KIND_ENTRANCE], [f.exit_cell, MapRoom.KIND_EXIT]]:
			var cell: Vector2i = pair[0]
			var kind: String = pair[1]
			if cell.x >= 0:
				var z: MapRoom = MapRoom.make(doc.allocate_id(), kind)
				level.add_room(z)
				level.set_room_id(cell, z.id)
		var outside: MapRoom = MapRoom.make(doc.allocate_id(), MapRoom.KIND_OUTSIDE)
		level.add_room(outside)
		for i: int in grid.cell_count():
			if f.cell_slot[i] < 0 and level.room_ids[i] == 0:
				level.set_room_id(grid.cell_at(i), outside.id)
	var wall: int = MapEdge.make(MapEdge.KIND_WALL)
	for i: int in grid.cell_count():
		var si: int = f.cell_slot[i]
		if si < 0:
			continue
		var c: Vector2i = grid.cell_at(i)
		for d: int in grid.edge_direction_count():
			var ni: int = grid.index_of(grid.neighbor(c, d))
			if ni >= 0 and f.cell_slot[ni] == si:
				continue
			level.set_edge(c, d, wall)
	for dr: Vector3i in f.doors:
		level.set_edge(Vector2i(dr.x, dr.y), dr.z, MapEdge.make(MapEdge.KIND_DOOR))
	for wn: Vector3i in f.windows:
		level.set_edge(Vector2i(wn.x, wn.y), wn.z, MapEdge.make(MapEdge.KIND_WINDOW))


## Amuebla cada estancia de la planta con su semilla hija (room_seed).
static func _furnish_floor(doc: MapDocument, f: Floor, p: Params, building_seed: int) -> void:
	var grid: GridGeometry = doc.grid
	for i: int in f.slots.size():
		var sl: Slot = f.slots[i]
		if not sl.placed():
			continue
		var entries: Array[Vector2i] = room_entries(grid, f, i)
		var rng: Rng = Rng.new(room_seed(building_seed, f.level_index, sl.order)).fork("furnish", 0)
		EstFurnisherG1.furnish(doc, f.level_index, rect_cells(sl.rect), entries, sl.kind, p.style, p.clutter, rng)


## Casillas de la estancia `slot` junto a sus puertas y sus escaleras (las
## "entradas" del amueblado: quedan libres y conectadas).
static func room_entries(grid: GridGeometry, f: Floor, slot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dr: Vector3i in f.doors:
		var c: Vector2i = Vector2i(dr.x, dr.y)
		var n: Vector2i = grid.neighbor(c, dr.z)
		for e: Vector2i in [c, n]:
			var ei: int = grid.index_of(e)
			if ei >= 0 and f.cell_slot[ei] == slot and not out.has(e):
				out.append(e)
	for s: Vector2i in f.stairs:
		var si: int = grid.index_of(s)
		if si >= 0 and f.cell_slot[si] == slot and not out.has(s):
			out.append(s)
	return out
