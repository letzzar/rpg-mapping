extends GutTest
## Partida en red (F4): lo que el servidor deja ver a los jugadores
## (PlayerView, niebla filtrada en el servidor) y la sesión (acceso con
## códigos, validación de movimientos, envío de solo lo que cambia), con un
## transporte en memoria. Sin sockets: corre igual en escritorio y web.
##
## Mapa de prueba 10×5, todo suelo e iluminado, con un muro vertical entre
## x = 4 y x = 5 (en la fila 2, una puerta secreta sin descubrir). El grupo
## está a la izquierda y no ve nada de la derecha.

const EAST: int = 1

var _doc: MapDocument
var _profile: SystemProfile
var _opts: PartyVision.Options
var _hero: MapToken
var _goblin: MapToken
var _hidden_goblin: MapToken
var _far_orc: MapToken


func before_each() -> void:
	_profile = SystemProfile.find_by_seed_code("DND5")
	_doc = MapDocument.create("square", 10, 5)
	_doc.seed_code = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"
	var lvl: MapLevel = _doc.level(0)
	lvl.fill_terrain(Terrain.FLOOR)
	for y: int in 5:
		var v: int = MapEdge.make(MapEdge.KIND_SECRET_DOOR) if y == 2 else MapEdge.make(MapEdge.KIND_WALL)
		lvl.set_edge(Vector2i(4, y), EAST, v)
	_add_object(lvl, Vector2i(1, 0))
	_add_object(lvl, Vector2i(7, 0))
	_add_trap(lvl, Vector2i(2, 1), true)
	_add_trap(lvl, Vector2i(2, 3), false)
	_hero = _token(Vector2i(1, 2), MapToken.SIDE_PLAYER, "Héroe", false)
	_goblin = _token(Vector2i(3, 2), MapToken.SIDE_ENEMY, "Trasgo", false)
	_hidden_goblin = _token(Vector2i(2, 4), MapToken.SIDE_ENEMY, "Emboscado", true)
	_far_orc = _token(Vector2i(7, 2), MapToken.SIDE_ENEMY, "Orco", false)
	_opts = PartyVision.Options.new()
	_opts.ambient_lit = true
	var r: PartyVision.Result = PartyVision.compute(_doc, 0, _profile, _opts)
	assert_true(ExploreCommand.from_visible(_doc, 0, PartyVision.VIEWER_PARTY, r.visible).apply(_doc))


func _token(cell: Vector2i, side: String, token_name: String, hidden: bool) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = _doc.allocate_id()
	t.name = token_name
	t.cell = cell
	t.side = side
	t.hidden = hidden
	t.character_ref = "fichas/" + token_name + ".json"
	assert_true(_doc.add_token(t))
	return t


func _add_object(lvl: MapLevel, cell: Vector2i) -> void:
	var o: MapObject = MapObject.new()
	o.id = _doc.allocate_id()
	o.catalog_id = "table"
	o.cell = cell
	assert_true(lvl.add_object(o))


func _add_trap(lvl: MapLevel, cell: Vector2i, hidden: bool) -> void:
	var t: MapTrap = MapTrap.new()
	t.id = _doc.allocate_id()
	t.cell = cell
	t.trap_id = "pit"
	t.hidden = hidden
	assert_true(lvl.add_trap(t))


func _names(list: Array[Dictionary]) -> String:
	var out: PackedStringArray = PackedStringArray()
	for d: Dictionary in list:
		var n: String = d["name"]
		out.append(n)
	return ",".join(out)


# --- PlayerView ------------------------------------------------------------------

func test_player_view_hides_what_the_party_has_not_seen() -> void:
	var snap: PlayerView.Snapshot = PlayerView.build(_doc, _profile, _opts)
	var lv: PlayerView.LevelView = snap.levels[0]
	var terrain: PackedByteArray = lv.content["terrain"]
	for y: int in 5:
		for x: int in 10:
			var want: int = Terrain.FLOOR if x <= 4 else Terrain.VOID
			assert_eq(terrain[_doc.grid.index_of(Vector2i(x, y))], want, "casilla %d,%d" % [x, y])
	# La puerta secreta sin descubrir llega como muro.
	var edges: Array = lv.content["edges"]
	assert_eq(edges.size(), 5)
	for e: Array in edges:
		var v: int = e[3]
		assert_eq(MapEdge.kind_of(v), MapEdge.KIND_WALL)
	var objects: Array = lv.content["objects"]
	assert_eq(objects.size(), 1, "solo la mesa del lado explorado")
	var traps: Array = lv.content["traps"]
	assert_eq(traps.size(), 1, "la trampa oculta no se envía")
	assert_eq(_names(snap.tokens), "Héroe,Trasgo", "ni la ficha oculta ni el orco tras el muro")
	for d: Dictionary in snap.tokens:
		if _s(d, "name") == "Trasgo":
			assert_eq(_s(d, "character_ref"), "", "la ficha del DM no se envía")
		else:
			assert_eq(_s(d, "character_ref"), "fichas/Héroe.json")


## Descubierta la puerta, ya se envía como puerta secreta (descubierta).
func test_discovered_secret_door_is_sent() -> void:
	var lvl: MapLevel = _doc.level(0)
	lvl.set_edge(Vector2i(4, 2), EAST, MapEdge.make(MapEdge.KIND_SECRET_DOOR, MapEdge.FLAG_DISCOVERED))
	var lv: PlayerView.LevelView = PlayerView.build(_doc, _profile, _opts).levels[0]
	var kinds: Array[int] = []
	var edge_list: Array = lv.content["edges"]
	for e: Array in edge_list:
		var v: int = e[3]
		kinds.append(MapEdge.kind_of(v))
	assert_true(kinds.has(MapEdge.KIND_SECRET_DOOR))


# --- GameSession con transporte en memoria ---------------------------------------

class Wire:
	extends RefCounted
	var outbox: Dictionary[int, Array] = {}
	var closed: Array[int] = []

	func send(peer: int, data: PackedByteArray) -> void:
		if not outbox.has(peer):
			outbox[peer] = []
		outbox[peer].append(data)

	func close(peer: int) -> void:
		closed.append(peer)

	## Mensajes pendientes de `peer`, decodificados (y los quita).
	func take(peer: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var list: Array = outbox.get(peer, [])
		for b: PackedByteArray in list:
			out.append(NetMessage.decode(b, NetMessage.MAX_FROM_SERVER))
		outbox.erase(peer)
		return out


func _session(wire: Wire) -> GameSession:
	var s: GameSession = GameSession.new()
	s.send_bytes = wire.send
	s.close_peer = wire.close
	s.deny_close_delay_ms = 0
	s.set_document(_doc, _profile, "Mazmorra")
	s.set_vision_options(_opts)
	return s


func _hello(s: GameSession, peer: int, room: String, code: String) -> void:
	assert_true(s.peer_connected(peer))
	s.receive(peer, NetMessage.encode({"t": NetMessage.HELLO, "room": room, "token": code}))


func _types(msgs: Array[Dictionary]) -> String:
	var out: PackedStringArray = PackedStringArray()
	for m: Dictionary in msgs:
		var t: String = m["t"]
		out.append(t)
	return ",".join(out)


func test_access_needs_room_and_player_code() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	_hello(s, 1, "XXXXXX", ana.code)
	assert_eq(_types(wire.take(1)), "denied")
	_hello(s, 2, s.room_code, "MAL")
	var m: Array[Dictionary] = wire.take(2)
	assert_eq(_s(m[0], "key"), "NET_ERR_TOKEN")
	assert_true(wire.closed.has(1) and wire.closed.has(2))
	# Antes del saludo no se acepta nada más.
	assert_true(s.peer_connected(3))
	s.receive(3, NetMessage.encode({"t": NetMessage.MOVE, "token": _hero.id, "level": 0, "x": 2, "y": 2}))
	assert_eq(_s(wire.take(3)[0], "key"), "NET_ERR_PROTOCOL")
	assert_eq(ana.peer, 0)


## Un jugador entra, recibe el mapa filtrado y su copia (NetClient) es
## exactamente la de PlayerView; el código de semilla no viaja nunca.
func test_join_builds_the_filtered_copy() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	assert_true(SetTokenCharacterCommand.new(_hero.id, ana.ref()).apply(_doc))
	s.flush()
	_hello(s, 5, s.room_code.to_lower(), ana.code)
	assert_eq(ana.peer, 5)
	var raw: Array = wire.outbox[5]
	for b: PackedByteArray in raw:
		var text: String = b.decompress_dynamic(NetMessage.MAX_FROM_SERVER, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
		assert_false(text.contains(_doc.seed_code), "sin código de semilla")
	var c: NetClient = NetClient.new()
	for m: Dictionary in wire.take(5):
		c.handle_message(m)
	assert_eq(c.player_name, "Ana")
	assert_eq(c.system_code, "DND5")
	assert_eq(c.title, "Mazmorra")
	assert_not_null(c.document)
	var want: String = CanonicalJson.stringify(PlayerView.build(_doc, _profile, _opts).levels[0].content)
	assert_eq(CanonicalJson.stringify(c.document.level(0).content_to_dict()), want)
	assert_true(c.document.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(4, 4)))
	assert_false(c.document.level(0).is_explored(PartyVision.VIEWER_PARTY, Vector2i(5, 4)))
	assert_eq(c.visible_of(0).size(), 50)
	assert_eq(c.document.tokens.size(), 2)
	assert_true(c.owns(c.document.token(_hero.id)))
	assert_false(c.owns(c.document.token(_goblin.id)))


func test_moves_are_validated_by_the_server() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	var stack: CommandStack = CommandStack.new(_doc)
	assert_true(stack.execute(SetTokenCharacterCommand.new(_hero.id, ana.ref())))
	var approved: Array[MoveTokenCommand] = []
	s.move_approved.connect(func(cmd: MoveTokenCommand) -> void: approved.append(cmd))
	s.flush()
	_hello(s, 1, s.room_code, ana.code)
	wire.take(1)
	var cases: Array[Array] = [
		[_goblin.id, Vector2i(2, 2), "NET_MOVE_NOT_YOURS"],
		[_hero.id, Vector2i(7, 2), "NET_MOVE_UNKNOWN_CELL"],
		[_hero.id, Vector2i(3, 2), "NET_MOVE_OCCUPIED"],
		[_hero.id, Vector2i(1, 2), "NET_MOVE_INVALID"],
	]
	for cs: Array in cases:
		var tid: int = cs[0]
		var cell: Vector2i = cs[1]
		s.receive(1, NetMessage.encode({"t": NetMessage.MOVE, "token": tid, "level": 0, "x": cell.x, "y": cell.y}))
		var got: Array[Dictionary] = wire.take(1)
		var want_key: String = cs[2]
		assert_eq(_s(got[0], "key"), want_key)
	assert_eq(approved.size(), 0)
	# Válido: lo aprueba la sesión, lo ejecuta el DM y el cambio llega.
	s.receive(1, NetMessage.encode({"t": NetMessage.MOVE, "token": _hero.id, "level": 0, "x": 2, "y": 4}))
	assert_eq(approved.size(), 1)
	assert_true(stack.execute(approved[0]))
	s.mark_dirty()
	assert_gt(s.flush(), 0)
	assert_eq(_types(wire.take(1)), "tokens", "solo cambian las fichas (la vista es la misma con luz ambiente)")
	assert_eq(_doc.token(_hero.id).cell, Vector2i(2, 4), "sobre la ficha oculta: no se delata que está ahí")
	# Sin cambios no se envía nada.
	s.mark_dirty()
	assert_eq(s.flush(), 0)
	# Ya no es suya: la misma petición se rechaza.
	assert_true(stack.execute(SetTokenCharacterCommand.new(_hero.id, "")))
	s.receive(1, NetMessage.encode({"t": NetMessage.MOVE, "token": _hero.id, "level": 0, "x": 2, "y": 3}))
	assert_eq(_s(wire.take(1)[0], "key"), "NET_MOVE_NOT_YOURS")


## Un muro en medio: la ruta no existe y no se puede "saltar" por la
## puerta cerrada aunque la casilla esté explorada.
func test_move_without_route_is_rejected() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	_hero.character_ref = ana.ref()
	var lvl: MapLevel = _doc.level(0)
	for y: int in 5:
		lvl.set_edge(Vector2i(1, y), EAST, MapEdge.make(MapEdge.KIND_DOOR))
	s.flush()
	_hello(s, 1, s.room_code, ana.code)
	wire.take(1)
	s.receive(1, NetMessage.encode({"t": NetMessage.MOVE, "token": _hero.id, "level": 0, "x": 3, "y": 0}))
	assert_eq(_s(wire.take(1)[0], "key"), "NET_MOVE_NO_ROUTE")


func test_pings_reach_everyone_and_reconnect_replaces_old_peer() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	var bo: GameSession.Player = s.add_player("Bo")
	var dm_pings: Array[Vector2i] = []
	s.pinged.connect(func(_l: int, cell: Vector2i, _w: String) -> void: dm_pings.append(cell))
	s.flush()
	_hello(s, 1, s.room_code, ana.code)
	_hello(s, 2, s.room_code, bo.code)
	assert_eq(s.connected_count(), 2)
	wire.take(1)
	wire.take(2)
	s.receive(1, NetMessage.encode({"t": NetMessage.PING, "level": 0, "x": 3, "y": 1}))
	var got: Array[Dictionary] = wire.take(2)
	assert_eq(_types(got), "ping")
	assert_eq(_s(got[0], "name"), "Ana")
	assert_eq(dm_pings.size(), 1)
	assert_eq(dm_pings[0], Vector2i(3, 1))
	# Demasiado seguido: se ignora.
	s.receive(1, NetMessage.encode({"t": NetMessage.PING, "level": 0, "x": 4, "y": 1}))
	assert_eq(dm_pings.size(), 1)
	# Ana recarga la página: la conexión 1 se cierra y entra la 3.
	_hello(s, 3, s.room_code, ana.code)
	assert_true(wire.closed.has(1))
	assert_eq(ana.peer, 3)
	assert_eq(s.connected_count(), 2)
	s.remove_player(bo.id)
	assert_true(wire.closed.has(2))
	assert_eq(s.connected_count(), 1)


## Al cambiar de mapa (el DM entra en un edificio) los jugadores reciben un
## "map" nuevo y todos sus niveles.
func test_new_document_resets_clients() -> void:
	var wire: Wire = Wire.new()
	var s: GameSession = _session(wire)
	var ana: GameSession.Player = s.add_player("Ana")
	s.flush()
	_hello(s, 1, s.room_code, ana.code)
	wire.take(1)
	var other: MapDocument = MapDocument.create("hex_flat", 6, 6, 2)
	s.set_document(other, _profile, "Taberna")
	s.flush()
	var got: Array[Dictionary] = wire.take(1)
	assert_eq(_types(got), "map,level,vision,level,vision,tokens")
	var c: NetClient = NetClient.new()
	for m: Dictionary in got:
		c.handle_message(m)
	assert_eq(c.document.grid_kind(), "hex_flat")
	assert_eq(c.document.level_count(), 2)
	assert_eq(c.title, "Taberna")

func _s(d: Dictionary, key: String) -> String:
	var v: String = d.get(key, "")
	return v


func _i(d: Dictionary, key: String) -> int:
	var v: float = d.get(key, -1.0)
	return int(v)
