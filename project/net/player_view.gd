class_name PlayerView
extends RefCounted
## Lo que el servidor envía a los jugadores (ADR 031): el mapa del DM
## FILTRADO por la niebla del grupo. Es la regla de oro 6 (la niebla se filtra
## en el servidor): un jugador nunca recibe el código de semilla ni casillas,
## puertas, objetos o fichas que el grupo no ha explorado o no ve, así que ni
## leyendo el tráfico puede ver el mapa entero.
##
## Por nivel:
## - Casillas no exploradas por el grupo (`PartyVision.VIEWER_PARTY`) →
##   Terrain.VOID y sin zona.
## - Aristas: solo las que tocan una casilla explorada; una puerta secreta sin
##   descubrir se envía como muro.
## - Salas, objetos, escaleras y mapas hijos con alguna casilla explorada; los
##   hijos sin su código (regeneraría el interior). Trampas: solo las
##   visibles (no ocultas) en casillas exploradas.
## Fichas: las del grupo no ocultas (en cualquier nivel) y las demás no
## ocultas solo si alguna casilla de su huella se ve ahora; sin
## `character_ref` salvo las del grupo (la ficha del DM no es asunto suyo), y
## de las ajenas, el personaje sin velocidades, sentidos ni iniciativa.
##
## La visión es la del grupo entero (la misma niebla que la vista "Jugadores"
## del DM), no la de cada personaje por separado: así se calcula una vez por
## cambio para todos los clientes.


class LevelView:
	extends RefCounted
	## content_to_dict() filtrado (lo que carga MapLevel.load_dicts()).
	var content: Dictionary = {}
	var explored: PackedByteArray = PackedByteArray()
	## Visible ahora (0 = no; Visibility.DIM/BRIGHT); vacío si no hay nadie
	## del grupo en el nivel.
	var visible: PackedByteArray = PackedByteArray()


class Snapshot:
	extends RefCounted
	var levels: Array[LevelView] = []
	## MapToken.to_dict() de las fichas que ven los jugadores.
	var tokens: Array[Dictionary] = []
	## TurnTracker.to_dict() reducido a esas fichas (ADR 035).
	var turns: Dictionary = {}


static func build(doc: MapDocument, profile: SystemProfile, opts: PartyVision.Options) -> Snapshot:
	var snap: Snapshot = Snapshot.new()
	for li: int in doc.level_count():
		var lv: LevelView = LevelView.new()
		var lvl: MapLevel = doc.level(li)
		lv.explored = lvl.explored(PartyVision.VIEWER_PARTY)
		if not PartyVision.party_tokens(doc, li).is_empty():
			lv.visible = PartyVision.compute(doc, li, profile, opts).visible
		lv.content = filter_level(lvl, lv.explored)
		snap.levels.append(lv)
	for t: MapToken in doc.tokens:
		if t.hidden or doc.level(t.level) == null:
			continue
		var in_party: bool = PartyVision.SIDES_IN_PARTY.has(t.side)
		if not in_party and not _token_seen(doc, t, profile, snap.levels[t.level].visible):
			continue
		var d: Dictionary = t.to_dict()
		# El botín solo si el DM lo ha enseñado (ADR 048).
		if not t.loot_revealed:
			d.erase("loot")
		if not in_party:
			d["character_ref"] = ""
			# De una criatura ajena solo se ve su aspecto (ADR 034).
			if t.sheet != null:
				d["sheet"] = t.sheet.public_copy().to_dict()
		snap.tokens.append(d)
	snap.turns = filter_turns(doc.turns, snap.tokens).to_dict()
	return snap


## Turnos que ven los jugadores: solo las fichas que reciben (con su
## iniciativa), y el turno actual solo si es de una de ellas (si le toca a
## una criatura oculta, para ellos no hay turno en marcha: no se delata).
static func filter_turns(src: TurnTracker, tokens: Array[Dictionary]) -> TurnTracker:
	var seen: Dictionary[int, bool] = {}
	for td: Dictionary in tokens:
		var tid: int = td["id"]
		seen[tid] = true
	var out: TurnTracker = TurnTracker.new()
	out.round = src.round
	out.block_over_speed = src.block_over_speed
	var cur: int = src.current_token_id()
	for id: int in src.order:
		if not seen.has(id):
			continue
		if id == cur:
			out.current = out.order.size()
			out.active = true
			out.moved_ft = src.moved_ft
		out.order.append(id)
		if src.initiative.has(id):
			out.initiative[id] = src.initiative[id]
	return out


## Contenido del nivel reducido a las casillas exploradas (`explored`: 1 byte
## por casilla).
static func filter_level(lvl: MapLevel, explored: PackedByteArray) -> Dictionary:
	var g: GridGeometry = lvl.grid
	var n: int = g.cell_count()
	var terrain: PackedByteArray = PackedByteArray()
	terrain.resize(n)
	terrain.fill(Terrain.VOID)
	var room_ids: PackedInt32Array = PackedInt32Array()
	room_ids.resize(n)
	room_ids.fill(0)
	var seen_rooms: Dictionary[int, bool] = {}
	for i: int in n:
		if explored[i] != 0:
			terrain[i] = lvl.terrain[i]
			room_ids[i] = lvl.room_ids[i]
			seen_rooms[lvl.room_ids[i]] = true
	var edges: Array = []
	for id: int in lvl.edge_ids():
		var e: Vector3i = g.edge_from_id(id)
		var a: Vector2i = Vector2i(e.x, e.y)
		var b: Vector2i = g.neighbor(a, e.z)
		if not _is_explored(g, explored, a) and not _is_explored(g, explored, b):
			continue
		var v: int = lvl.get_edge_by_id(id)
		if MapEdge.kind_of(v) == MapEdge.KIND_SECRET_DOOR and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED):
			v = MapEdge.make(MapEdge.KIND_WALL)
		edges.append([e.x, e.y, e.z, v])
	var rooms: Array = []
	for r: MapRoom in lvl.rooms:
		if seen_rooms.has(r.id):
			rooms.append(r.to_dict())
	var objects: Array = []
	for o: MapObject in lvl.objects:
		if _any_explored(g, explored, lvl.object_cells(o)):
			var od: Dictionary = o.to_dict()
			# El contenido solo si el DM lo ha enseñado (ADR 048).
			if not o.contents_revealed:
				od.erase("contents")
			objects.append(od)
	var stairs: Array = []
	for s: MapStair in lvl.stairs:
		if _is_explored(g, explored, s.cell):
			stairs.append(s.to_dict())
	var traps: Array = []
	for t: MapTrap in lvl.traps:
		if not t.hidden and _is_explored(g, explored, t.cell):
			traps.append(t.to_dict())
	var d: Dictionary = {
		"terrain": terrain,
		"room_ids": room_ids,
		"edges": edges,
		"rooms": rooms,
		"objects": objects,
		"stairs": stairs,
		"traps": traps,
	}
	var children: Array = []
	for c: MapChild in lvl.children:
		if _rect_explored(g, explored, c.rect):
			var cd: Dictionary = c.to_dict()
			cd["seed_code"] = ""
			children.append(cd)
	if not children.is_empty():
		d["children"] = children
	return d


static func _token_seen(doc: MapDocument, t: MapToken, profile: SystemProfile, visible: PackedByteArray) -> bool:
	if visible.is_empty():
		return false
	var cells: Array[Vector2i] = doc.token_cells(t, profile) if profile != null else [t.cell]
	for c: Vector2i in cells:
		var i: int = doc.grid.index_of(c)
		if i >= 0 and visible[i] != 0:
			return true
	return false


static func _is_explored(g: GridGeometry, explored: PackedByteArray, c: Vector2i) -> bool:
	var i: int = g.index_of(c)
	return i >= 0 and explored[i] != 0


static func _any_explored(g: GridGeometry, explored: PackedByteArray, cells: Array[Vector2i]) -> bool:
	for c: Vector2i in cells:
		if _is_explored(g, explored, c):
			return true
	return false


static func _rect_explored(g: GridGeometry, explored: PackedByteArray, r: Rect2i) -> bool:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			if _is_explored(g, explored, Vector2i(x, y)):
				return true
	return false
