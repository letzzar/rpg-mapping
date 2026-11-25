class_name EstGeneratorG2
extends RefCounted
## Estancia de un edificio, EST G2 (PROYECTO §6.5, ADR 029). Criterio de F3:
## "regenerar una estancia aislada desde su código da el mismo resultado que
## dentro de la aldea".
##
## NO sustituye a EST G1 (estancia aislada con forma y puertas propias, que
## sigue igual y es la que genera la app al azar): es otro generador de la
## misma escala, registrado a la vez (GeneratorRegistry, clave EST-G2).
##
## Código: RPGM1-<SIS>-EST-G2-<PARAMS>-<SEED>-<CRC>, con PARAMS = los 7 campos
## de EDI G1 (mismo orden y defectos) + level + room (ParamSchemaRegistry.
## est_g2) y SEED = la semilla del edificio. Apunta a la estancia `room` (orden
## en la lista de su planta, el de EdiGeneratorG1.room_seed) del nivel `level`
## del edificio EDI G1 con esos parámetros y esa semilla.
##
## CUALQUIER CAMBIO QUE ALTERE LA SALIDA EXIGE GEN NUEVO (EST G3), también uno
## de EDI G1 (si EDI G1 pasa a legacy/, EST G2 debe seguir usando esa versión).
##
## Algoritmo (puro, determinista; coste ≈ distribución del edificio + amueblar
## una estancia, sin amueblar las demás):
## 1. EdiGeneratorG1.plan_building(params EDI, Rng.new(semilla)): el edificio
##    sin muebles, idéntico al de generate_building() antes de amueblar.
## 2. EdiGeneratorG1.furnish_room() SOLO para la estancia pedida: mismos
##    objetos que en el edificio completo (el amueblador solo lee las casillas
##    de su estancia y las aristas entre ellas; ver plan_building()).
## 3. Extracción por TRASLACIÓN: ventana = rectángulo de la estancia + un
##    anillo de RING casillas; el origen se redondea hacia abajo al paso de
##    traslación de la rejilla (AldGeneratorG1.translation_step: en hex odd-q
##    la x debe ser par, en odd-r la y), así que en hex puede haber una
##    columna o fila más de anillo a la izquierda o arriba. Casilla del
##    edificio = casilla de la estancia + offset; nivel del edificio = nivel
##    del documento (0) + level. Se copian:
##    - terreno y zona (MapRoom con el mismo kind, ids nuevos) de todas las
##      casillas de la ventana: la estancia y su anillo de contexto (lo que hay
##      al otro lado de cada muro, puerta o ventana: otra estancia, el pasillo,
##      el exterior, la entrada o el vacío de una planta alta);
##    - todas las aristas con las dos casillas dentro de la ventana (muros,
##      puertas y ventanas con sus banderas; en particular, todas las que tocan
##      la estancia);
##    - los objetos (todos de la estancia: ninguno sale de ella) y las
##      escaleras de casillas de la estancia, con to_level relativo
##      (to_level − level: −1 baja, +1 sube; fuera del documento de 1 nivel,
##      como un to_cell fuera del mapa: "sale de este mapa").
##    Los ids se asignan en orden: zonas, escaleras y objetos, cada grupo en el
##    orden de sus ids en el edificio.
##    No se copian los objetos ni las escaleras de las estancias vecinas
##    (contexto mínimo: el anillo es para ver qué hay detrás de cada puerta y
##    poder salir por ella, no para jugar en él).
##
## Garantía (por construcción, comprobada en test_est_g2 con los 7 tipos × 3
## rejillas, sótanos y varias plantas, todas sus estancias, y en la cadena
## ALD → EDI → estancia): las casillas, aristas, objetos y escaleras de la
## estancia son las del edificio trasladadas por `offset` (y level).

const SCALE: String = "EST"
const GEN: int = 2
## Versión de EDI de la que se extraen las estancias.
const EDI_SCALE: String = "EDI"
const EDI_GEN: int = 1
## Casillas de contexto alrededor de la estancia.
const RING: int = 1
## Claves de los dos campos propios (tras los de EDI G1).
const LEVEL_KEY: String = "level"
const ROOM_KEY: String = "room"

## Claves i18n de error al generar (el código es válido pero el edificio no
## tiene ese nivel o esa estancia).
const ERR_LEVEL: String = "SEED_ERR_ROOM_LEVEL"
const ERR_ROOM: String = "SEED_ERR_ROOM"


## Estancia de un edificio y su relación con él (para la navegación).
class RoomRef:
	extends RefCounted
	## Código EDI G1 canónico del edificio.
	var building_code: String = ""
	## Código EST G2 canónico de la estancia.
	var code: String = ""
	## Nivel del edificio (índice en el documento EDI).
	var level: int = 0
	## Orden en la lista de su planta (room en el código).
	var order: int = 0
	## Tipo de estancia EST (kind de su MapRoom; i18n ROOM_KIND_<KIND>).
	var kind: String = ""
	## true si es el pasillo/recibidor (hub) de la planta.
	var hub: bool = false
	## Rectángulo de la estancia en casillas del edificio.
	var rect: Rect2i = Rect2i()
	## Casilla del edificio = casilla del documento de la estancia + offset.
	var offset: Vector2i = Vector2i.ZERO
	## Tamaño del documento de la estancia (estancia + anillo).
	var map_size: Vector2i = Vector2i.ZERO
	## Casilla del edificio, dentro de la estancia, junto a su primera puerta
	## (la que primero planificó EDI; si no tiene, su primera escalera; si
	## tampoco, la esquina de su rectángulo). Para dejar al grupo al entrar.
	var entry: Vector2i = Vector2i.ZERO

	## ¿Es (level, casilla del edificio) una casilla de esta estancia?
	func contains(p_level: int, building_cell: Vector2i) -> bool:
		return p_level == level and rect.has_point(building_cell)

	func to_room_cell(building_cell: Vector2i) -> Vector2i:
		return building_cell - offset

	func to_building_cell(room_cell: Vector2i) -> Vector2i:
		return room_cell + offset

	## MapChild equivalente (NO se guarda en el documento EDI, que está
	## congelado) para MapNavigator.enter(): child_level 0 (el documento de la
	## estancia tiene un nivel), entrance = entry, id estable 1 + level × 256 +
	## order (único dentro del edificio, que no tiene otros hijos).
	func to_map_child() -> MapChild:
		var c: MapChild = MapChild.new()
		c.id = 1 + level * EdiGeneratorG1.ROOM_STRIDE + order
		c.kind = kind
		c.seed_code = code
		c.offset = offset
		c.child_level = 0
		c.rect = rect
		c.entrance = entry
		return c


# --- Generador ---------------------------------------------------------------------

## Punto de entrada registrado en GeneratorRegistry. null si el edificio no
## tiene ese nivel o esa estancia (explain() dice cuál).
static func generate(code: SeedCode, _profile: SystemProfile, rng: Rng) -> MapDocument:
	var p: EdiGeneratorG1.Params = EdiGeneratorG1.params_from(code)
	var level: int = code.params[LEVEL_KEY]
	var order: int = code.params[ROOM_KEY]
	var res: EdiGeneratorG1.Result = EdiGeneratorG1.plan_building(p, rng)
	if res == null or level < 0 or level >= res.floors.size():
		return null
	var f: EdiGeneratorG1.Floor = res.floors[level]
	if order < 0 or order >= f.slots.size() or not f.slots[order].placed():
		return null
	EdiGeneratorG1.furnish_room(res.doc, f, order, p, rng.seed_value)
	return extract(res.doc, f, order)


## Clave i18n de por qué generate() devolvió null ("" si no lo sabe).
static func explain(code: SeedCode) -> String:
	var res: EdiGeneratorG1.Result = _plan(code)
	if res == null:
		return ""
	var level: int = code.params[LEVEL_KEY]
	var order: int = code.params[ROOM_KEY]
	if level < 0 or level >= res.floors.size():
		return ERR_LEVEL
	var f: EdiGeneratorG1.Floor = res.floors[level]
	if order < 0 or order >= f.slots.size() or not f.slots[order].placed():
		return ERR_ROOM
	return ""


## Documento de la estancia `slot` de la planta `f` de `building` (ya
## amueblada) por traslación (paso 3 del algoritmo). Un nivel.
static func extract(building: MapDocument, f: EdiGeneratorG1.Floor, slot: int) -> MapDocument:
	var rect: Rect2i = f.slots[slot].rect
	var win: Rect2i = window(building.grid, rect)
	var doc: MapDocument = MapDocument.create(building.grid_kind(), win.size.x, win.size.y, 1)
	if doc == null:
		return null
	var off: Vector2i = win.position
	var src: MapLevel = building.level(f.level_index)
	var dst: MapLevel = doc.level(0)
	var g: GridGeometry = doc.grid
	var bg: GridGeometry = building.grid
	# Zonas de la ventana, en orden de id del edificio.
	var zone_ids: PackedInt32Array = PackedInt32Array()
	for i: int in g.cell_count():
		var bc: Vector2i = g.cell_at(i) + off
		var rid: int = src.get_room_id(bc)
		if rid != 0 and not zone_ids.has(rid):
			zone_ids.append(rid)
	zone_ids.sort()
	var new_ids: Dictionary[int, int] = {}
	for rid2: int in zone_ids:
		var r: MapRoom = src.room(rid2)
		var nr: MapRoom = MapRoom.make(doc.allocate_id(), r.kind if r != null else MapRoom.KIND_ROOM, r.label if r != null else "")
		dst.add_room(nr)
		new_ids[rid2] = nr.id
	# Terreno, zonas y aristas con las dos casillas en la ventana.
	for i2: int in g.cell_count():
		var c: Vector2i = g.cell_at(i2)
		var bc2: Vector2i = c + off
		if not bg.in_bounds(bc2):
			continue
		dst.set_terrain(c, src.get_terrain(bc2))
		var rid3: int = src.get_room_id(bc2)
		if rid3 != 0:
			dst.set_room_id(c, new_ids[rid3])
		for d: int in g.edge_direction_count():
			if not g.in_bounds(g.neighbor(c, d)):
				continue
			var v: int = src.get_edge(bc2, d)
			if v != MapEdge.NONE:
				dst.set_edge(c, d, v)
	# Escaleras de la estancia (nivel relativo) y sus objetos.
	for s: MapStair in src.stairs:
		if not rect.has_point(s.cell):
			continue
		var ns: MapStair = s.copy()
		ns.id = doc.allocate_id()
		ns.cell = s.cell - off
		ns.to_cell = s.to_cell - off
		ns.to_level = s.to_level - f.level_index
		dst.add_stair(ns)
	for o: MapObject in src.objects:
		if not rect.has_point(o.cell):
			continue
		var no: MapObject = o.copy()
		no.id = doc.allocate_id()
		no.cell = o.cell - off
		dst.add_object(no)
	return doc


## Ventana del documento de la estancia en casillas del edificio: position =
## offset (redondeado al paso de traslación de la rejilla) y size = tamaño del
## documento. Contiene `rect` con al menos RING casillas alrededor.
static func window(grid: GridGeometry, rect: Rect2i) -> Rect2i:
	var step: Vector2i = AldGeneratorG1.translation_step(grid)
	var o0: Vector2i = rect.position - Vector2i(RING, RING)
	var off: Vector2i = Vector2i(o0.x - posmod(o0.x, step.x), o0.y - posmod(o0.y, step.y))
	return Rect2i(off, rect.end + Vector2i(RING, RING) - off)


# --- Funciones para la navegación edificio ↔ estancia -----------------------------

## Código EST G2 de la estancia `room_order` del nivel `level` del edificio
## `edi_code` (EDI G1). "" si edi_code no es un código EDI G1 válido o level/
## room_order se salen del esquema (0-7, 0-63). NO comprueba que el edificio
## tenga esa estancia (eso exige distribuirlo): usar rooms_of()/room_at().
static func room_code(edi_code: String, level: int, room_order: int) -> String:
	var sc: SeedCode = SeedCode.parse(edi_code)
	if not sc.is_valid() or sc.scale != EDI_SCALE or sc.gen_version != EDI_GEN:
		return ""
	var params: Dictionary = sc.params.duplicate()
	params[LEVEL_KEY] = level
	params[ROOM_KEY] = room_order
	var rc: SeedCode = SeedCode.create(sc.system, SCALE, GEN, params, sc.seed_value)
	return rc.encode() if rc.is_valid() else ""


## Código EDI G1 del edificio de un código EST G2 ("" si no es EST G2 válido).
static func building_code(est_code: String) -> String:
	var sc: SeedCode = SeedCode.parse(est_code)
	if not sc.is_valid() or sc.scale != SCALE or sc.gen_version != GEN:
		return ""
	var params: Dictionary = sc.params.duplicate()
	params.erase(LEVEL_KEY)
	params.erase(ROOM_KEY)
	var bc: SeedCode = SeedCode.create(sc.system, EDI_SCALE, EDI_GEN, params, sc.seed_value)
	return bc.encode() if bc.is_valid() else ""


## Todas las estancias del edificio `edi_code` (EDI G1), por nivel y orden
## (también el pasillo/recibidor, con hub = true; no las zonas exteriores).
## Vacío si el código no es EDI G1 válido. Coste: distribuir el edificio sin
## amueblar (ver ADR 029; unos ms).
static func rooms_of(edi_code: String) -> Array[RoomRef]:
	var out: Array[RoomRef] = []
	var sc: SeedCode = SeedCode.parse(edi_code)
	if not sc.is_valid() or sc.scale != EDI_SCALE or sc.gen_version != EDI_GEN:
		return out
	var res: EdiGeneratorG1.Result = _plan(sc)
	if res == null:
		return out
	for f: EdiGeneratorG1.Floor in res.floors:
		for i: int in f.slots.size():
			if f.slots[i].placed():
				out.append(_make_ref(sc, res.doc.grid, f, i))
	return out


## Estancia del edificio `edi_code` que contiene la casilla `cell` (casillas
## del documento EDI) del nivel `level`; null si la casilla no es de ninguna
## (anillo exterior, entrada, vacío) o el código no es EDI G1 válido.
static func room_at(edi_code: String, level: int, cell: Vector2i) -> RoomRef:
	for r: RoomRef in rooms_of(edi_code):
		if r.contains(level, cell):
			return r
	return null


## Relación con su edificio de un código EST G2 (para volver: offset, nivel,
## entrada). null si no es EST G2 válido o el edificio no tiene esa estancia.
static func ref_of(est_code: String) -> RoomRef:
	var sc: SeedCode = SeedCode.parse(est_code)
	if not sc.is_valid() or sc.scale != SCALE or sc.gen_version != GEN:
		return null
	var res: EdiGeneratorG1.Result = _plan(sc)
	var level: int = sc.params[LEVEL_KEY]
	var order: int = sc.params[ROOM_KEY]
	if res == null or level < 0 or level >= res.floors.size():
		return null
	var f: EdiGeneratorG1.Floor = res.floors[level]
	if order < 0 or order >= f.slots.size() or not f.slots[order].placed():
		return null
	var esc: SeedCode = SeedCode.parse(building_code(est_code))
	return _make_ref(esc, res.doc.grid, f, order)


# --- Interno ---------------------------------------------------------------------------

## Edificio sin amueblar de un código EDI G1 o EST G2 (mismos 7 primeros campos).
static func _plan(sc: SeedCode) -> EdiGeneratorG1.Result:
	return EdiGeneratorG1.plan_building(EdiGeneratorG1.params_from(sc), Rng.new(sc.seed_value))


## `edi_sc`: código EDI G1 del edificio.
static func _make_ref(edi_sc: SeedCode, grid: GridGeometry, f: EdiGeneratorG1.Floor, slot: int) -> RoomRef:
	var sl: EdiGeneratorG1.Slot = f.slots[slot]
	var r: RoomRef = RoomRef.new()
	r.building_code = edi_sc.encode()
	r.code = room_code(r.building_code, f.level_index, sl.order)
	r.level = f.level_index
	r.order = sl.order
	r.kind = sl.kind
	r.hub = sl.hub
	r.rect = sl.rect
	var win: Rect2i = window(grid, sl.rect)
	r.offset = win.position
	r.map_size = win.size
	r.entry = sl.rect.position
	var found: bool = false
	for dr: Vector3i in f.doors:
		var c: Vector2i = Vector2i(dr.x, dr.y)
		var n: Vector2i = grid.neighbor(c, dr.z)
		for e: Vector2i in [c, n]:
			if not found and sl.rect.has_point(e):
				r.entry = e
				found = true
	if not found:
		for s: Vector2i in f.stairs:
			if not found and sl.rect.has_point(s):
				r.entry = s
				found = true
	return r
