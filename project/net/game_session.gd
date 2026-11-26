class_name GameSession
extends RefCounted
## Lógica de la partida en red del lado del DM (ADR 031), sin nodos ni
## sockets: recibe mensajes de cada conexión (`receive`) y entrega bytes a
## `send_bytes(peer, datos)`. WssServer pone el transporte; las pruebas, uno
## falso en memoria.
##
## - Acceso: código de sala + código de cada jugador (PROYECTO §11). Sin los
##   dos, la conexión se cierra.
## - Autoridad del DM: los jugadores solo PROPONEN mover sus fichas; la sesión
##   lo valida (ficha suya, casilla explorada y libre, ruta posible con las
##   puertas de verdad) y emite `move_approved`: quien la usa (la UI del DM)
##   lo ejecuta en su historial, así que el DM puede deshacerlo. Igual con
##   abrir o cerrar una puerta (door_approved), si el DM lo permite.
## - Lo que se envía es PlayerView (niebla filtrada en el servidor) y solo lo
##   que cambió: el nivel, la visión o las fichas cuyo mensaje es distinto del
##   último enviado.

## Se aprobó un movimiento propuesto por un jugador.
signal move_approved(cmd: MoveTokenCommand)
## Se aprobó abrir o cerrar una puerta propuesto por un jugador.
signal door_approved(cmd: SetEdgeCommand)
## Alguien (jugador) señaló una casilla.
signal pinged(level_index: int, cell: Vector2i, who: String)
## Cambió la lista de jugadores o su estado de conexión.
signal players_changed

const MAX_PEERS: int = 16
const MAX_PLAYERS: int = 12
## Prefijo de MapToken.character_ref de las fichas de un jugador de la sala.
const REF_PREFIX: String = "player:"
## Alfabeto de los códigos (Crockford: sin I, L, O ni U, fáciles de dictar).
const CODE_ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const ROOM_CODE_LENGTH: int = 6
const PLAYER_CODE_LENGTH: int = 10
## Milisegundos mínimos entre dos señales de la misma conexión.
const PING_INTERVAL_MS: int = 400
## Espera entre el aviso "denied" y el cierre: el WebSocketPeer de Godot
## descarta los mensajes que llegan junto con el cierre, así que el cliente
## no vería el motivo. Normalmente el cliente cierra él antes.
const DENY_CLOSE_DELAY_MS: int = 1500


class Player:
	extends RefCounted
	var id: int = 0
	var name: String = ""
	## Código secreto del jugador (va en su enlace de invitación).
	var code: String = ""
	## Conexión activa (0 = desconectado).
	var peer: int = 0

	## Valor de MapToken.character_ref de sus fichas.
	func ref() -> String:
		return REF_PREFIX + str(id)


var room_code: String = ""
var players: Array[Player] = []
## Callable(peer: int, data: PackedByteArray) que envía un mensaje.
var send_bytes: Callable = Callable()
## Callable(peer: int) que cierra una conexión.
var close_peer: Callable = Callable()
## Espera antes de cerrar una conexión rechazada (0 = en el acto; pruebas).
var deny_close_delay_ms: int = DENY_CLOSE_DELAY_MS
## Si los jugadores pueden abrir y cerrar puertas (con su ficha al lado).
var players_open_doors: bool = true

var _doc: MapDocument = null
var _profile: SystemProfile = null
var _opts: PartyVision.Options = PartyVision.Options.new()
var _title: String = ""
var _next_player_id: int = 1
## peer -> id de jugador (0 = aún sin identificar).
var _peers: Dictionary[int, int] = {}
var _last_ping: Dictionary[int, int] = {}
var _dirty: bool = false
## Conexiones rechazadas pendientes de cerrar: peer -> instante (ms).
var _closing: Dictionary[int, int] = {}
# Últimos mensajes enviados (bytes ya codificados), para mandar solo cambios
# y ponerse al día a quien entra.
var _map_msg: PackedByteArray = PackedByteArray()
var _level_msgs: Array[PackedByteArray] = []
var _vision_msgs: Array[PackedByteArray] = []
var _tokens_msg: PackedByteArray = PackedByteArray()
## Ids de las fichas del último envío (las que ven los jugadores).
var _seen_tokens: Dictionary[int, bool] = {}


func _init() -> void:
	room_code = random_code(ROOM_CODE_LENGTH)


## Código al azar del alfabeto Crockford (Crypto: no es generación de mapas,
## y debe ser impredecible).
static func random_code(length: int) -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(length)
	var out: String = ""
	for b: int in bytes:
		out += CODE_ALPHABET[b & 31]
	return out


# --- Jugadores -------------------------------------------------------------

func add_player(p_name: String) -> Player:
	if players.size() >= MAX_PLAYERS:
		return null
	var p: Player = Player.new()
	p.id = _next_player_id
	_next_player_id += 1
	p.name = p_name.strip_edges().left(32)
	if p.name.is_empty():
		p.name = "P" + str(p.id)
	p.code = random_code(PLAYER_CODE_LENGTH)
	players.append(p)
	players_changed.emit()
	return p


func remove_player(id: int) -> void:
	for k: int in players.size():
		if players[k].id == id:
			var p: Player = players[k]
			players.remove_at(k)
			if p.peer != 0:
				_drop(p.peer)
			players_changed.emit()
			return


func player(id: int) -> Player:
	for p: Player in players:
		if p.id == id:
			return p
	return null


## Jugador dueño de la ficha (por su character_ref); null si no es de nadie.
func owner_of(t: MapToken) -> Player:
	for p: Player in players:
		if t.character_ref == p.ref():
			return p
	return null


func connected_count() -> int:
	var n: int = 0
	for p: Player in players:
		if p.peer != 0:
			n += 1
	return n


# --- Estado que se comparte ------------------------------------------------

## Mapa que se juega (al navegar el DM a otro mapa, se llama otra vez).
func set_document(doc: MapDocument, profile: SystemProfile, title: String) -> void:
	_doc = doc
	_profile = profile
	_title = title
	_map_msg = PackedByteArray()
	_level_msgs.clear()
	_vision_msgs.clear()
	_tokens_msg = PackedByteArray()
	_dirty = true


## Opciones de luz del DM (ambiente iluminado, antorchas): cambian lo visible.
func set_vision_options(opts: PartyVision.Options) -> void:
	_opts = opts
	_dirty = true


## El documento cambió: se recalcula en el próximo flush().
func mark_dirty() -> void:
	_dirty = true


## Envía lo que cambió desde el último flush (la UI lo llama una vez por
## fotograma). Devuelve el número de mensajes enviados.
func flush() -> int:
	if not _closing.is_empty():
		var now: int = Time.get_ticks_msec()
		for peer: int in _closing.keys():
			var at: int = _closing[peer]
			if now >= at:
				_closing.erase(peer)
				_drop(peer)
	if not _dirty or _doc == null:
		return 0
	_dirty = false
	var sent: int = 0
	if _map_msg.is_empty():
		_map_msg = NetMessage.encode({
			"t": NetMessage.MAP,
			"grid": {"kind": _doc.grid.kind, "width": _doc.grid.width, "height": _doc.grid.height},
			"levels": _doc.level_count(),
			"title": _title,
		})
		sent += _broadcast(_map_msg)
	var snap: PlayerView.Snapshot = PlayerView.build(_doc, _profile, _opts)
	_level_msgs.resize(snap.levels.size())
	_vision_msgs.resize(snap.levels.size())
	for i: int in snap.levels.size():
		var lv: PlayerView.LevelView = snap.levels[i]
		var lm: PackedByteArray = NetMessage.encode({
			"t": NetMessage.LEVEL, "i": i, "content": lv.content,
			"explored": NetMessage.bytes_to_text(lv.explored)})
		if lm != _level_msgs[i]:
			_level_msgs[i] = lm
			sent += _broadcast(lm)
		var vm: PackedByteArray = NetMessage.encode({
			"t": NetMessage.VISION, "i": i, "visible": NetMessage.bytes_to_text(lv.visible)})
		if vm != _vision_msgs[i]:
			_vision_msgs[i] = vm
			sent += _broadcast(vm)
	_seen_tokens.clear()
	for td: Dictionary in snap.tokens:
		var tid: int = td["id"]
		_seen_tokens[tid] = true
	var tm: PackedByteArray = NetMessage.encode({"t": NetMessage.TOKENS, "list": snap.tokens})
	if tm != _tokens_msg:
		_tokens_msg = tm
		sent += _broadcast(tm)
	return sent


# --- Conexiones ------------------------------------------------------------

## Conexión nueva (aún sin identificar). false si ya hay demasiadas.
func peer_connected(peer: int) -> bool:
	if _peers.size() >= MAX_PEERS:
		return false
	_peers[peer] = 0
	return true


func peer_disconnected(peer: int) -> void:
	var pid: int = _peers.get(peer, 0)
	_peers.erase(peer)
	_last_ping.erase(peer)
	_closing.erase(peer)
	var p: Player = player(pid)
	if p != null and p.peer == peer:
		p.peer = 0
		players_changed.emit()


## Mensaje recibido de una conexión.
func receive(peer: int, data: PackedByteArray) -> void:
	if not _peers.has(peer) or _peers[peer] < 0:
		return
	var msg: Dictionary = NetMessage.decode(data, NetMessage.MAX_FROM_CLIENT)
	if msg.is_empty():
		_deny(peer, "NET_ERR_PROTOCOL")
		return
	var t: String = msg["t"]
	var pid: int = _peers[peer]
	if pid == 0:
		if t != NetMessage.HELLO:
			_deny(peer, "NET_ERR_PROTOCOL")
			return
		_hello(peer, msg)
		return
	var p: Player = player(pid)
	if p == null:
		_deny(peer, "NET_ERR_KICKED")
		return
	match t:
		NetMessage.MOVE:
			_move(p, msg)
		NetMessage.DOOR:
			_door(p, msg)
		NetMessage.PING:
			_ping(p, msg)


func _hello(peer: int, msg: Dictionary) -> void:
	var room: String = str(msg.get("room", "")).to_upper()
	var code: String = str(msg.get("token", "")).to_upper()
	if room != room_code:
		_deny(peer, "NET_ERR_ROOM")
		return
	var found: Player = null
	for p: Player in players:
		if p.code == code:
			found = p
	if found == null:
		_deny(peer, "NET_ERR_TOKEN")
		return
	if found.peer != 0:
		# Entra otra vez (recarga de la página): la conexión vieja sobra.
		_drop(found.peer)
	found.peer = peer
	_peers[peer] = found.id
	_send(peer, NetMessage.encode({
		"t": NetMessage.WELCOME, "name": found.name, "ref": found.ref(),
		"system": _profile.seed_code if _profile != null else ""}))
	# Al día: lo ya calculado y, si hay cambios pendientes, el próximo flush.
	if not _map_msg.is_empty():
		_send(peer, _map_msg)
		for m: PackedByteArray in _level_msgs:
			_send(peer, m)
		for m: PackedByteArray in _vision_msgs:
			_send(peer, m)
		_send(peer, _tokens_msg)
	players_changed.emit()


func _move(p: Player, msg: Dictionary) -> void:
	var r: JsonReader = JsonReader.new()
	var token_id: int = r.get_int(msg, "token")
	var level_index: int = r.get_int(msg, "level")
	var cell: Vector2i = Vector2i(r.get_int(msg, "x"), r.get_int(msg, "y"))
	var key: String = validate_move(p, token_id, level_index, cell) if r.ok() else "NET_MOVE_INVALID"
	if not key.is_empty():
		_send(p.peer, NetMessage.encode({"t": NetMessage.NOTICE, "key": key}))
		# Que vuelva a ver la ficha donde está de verdad.
		_send(p.peer, _tokens_msg)
		return
	move_approved.emit(MoveTokenCommand.new(token_id, cell, level_index))


## "" si el jugador puede mover su ficha ahí; si no, la clave i18n del motivo.
## Para cambiar de nivel, la ficha tiene que estar en una escalera que lleve ahí.
func validate_move(p: Player, token_id: int, level_index: int, cell: Vector2i) -> String:
	if _doc == null or _profile == null:
		return "NET_MOVE_NO_MAP"
	var t: MapToken = _doc.token(token_id)
	if t == null or t.hidden or t.character_ref != p.ref():
		return "NET_MOVE_NOT_YOURS"
	var lvl: MapLevel = _doc.level(t.level)
	if level_index != t.level:
		return _validate_stairs(t, level_index, cell)
	if not _doc.grid.in_bounds(cell) or cell == t.cell:
		return "NET_MOVE_INVALID"
	if not lvl.is_explored(PartyVision.VIEWER_PARTY, cell):
		return "NET_MOVE_UNKNOWN_CELL"
	# Solo cuentan las fichas que el jugador ve: rechazar por una oculta o
	# fuera de la vista delataría que está ahí (la resuelve el DM).
	for other: MapToken in _doc.tokens_at(t.level, cell, _profile):
		if other.id != t.id and _seen_tokens.has(other.id):
			return "NET_MOVE_OCCUPIED"
	var route: MovementCost.Route = MovementCost.find_route(_profile, lvl, t.cell, cell)
	if route == null or not route.found:
		return "NET_MOVE_NO_ROUTE"
	return ""


## Cambio de nivel: solo por una escalera en la casilla de la ficha que lleve
## exactamente a ese nivel y casilla (el destino puede estar sin explorar:
## al llegar se explora). Ocupado solo por fichas que el jugador ve.
func _validate_stairs(t: MapToken, level_index: int, cell: Vector2i) -> String:
	if _doc.level(level_index) == null:
		return "NET_MOVE_INVALID"
	var found: bool = false
	for s: MapStair in _doc.level(t.level).stairs_at(t.cell):
		if s.to_level == level_index and s.to_cell == cell:
			found = true
	if not found:
		return "NET_MOVE_NO_STAIRS"
	for other: MapToken in _doc.tokens_at(level_index, cell, _profile):
		if other.id != t.id and _seen_tokens.has(other.id):
			return "NET_MOVE_OCCUPIED"
	return ""


func _door(p: Player, msg: Dictionary) -> void:
	var r: JsonReader = JsonReader.new()
	var level_index: int = r.get_int(msg, "level")
	var edge: int = r.get_int(msg, "edge")
	var open: bool = r.get_bool(msg, "open")
	var key: String = validate_door(p, level_index, edge, open) if r.ok() else "NET_DOOR_INVALID"
	if not key.is_empty():
		_send(p.peer, NetMessage.encode({"t": NetMessage.NOTICE, "key": key}))
		return
	var v: int = _doc.level(level_index).get_edge_by_id(edge)
	door_approved.emit(SetEdgeCommand.new(level_index, edge, MapEdge.with_flag(v, MapEdge.FLAG_OPEN, open)))


## "" si el jugador puede dejar la puerta abierta (open) o cerrada; si no,
## la clave i18n del motivo. Hace falta una ficha suya en una de las dos
## casillas de la arista; las cerradas con llave y las secretas sin descubrir
## no se abren (una secreta sin descubrir la ve como muro: se responde igual
## que a un muro para no delatarla).
func validate_door(p: Player, level_index: int, edge: int, open: bool) -> String:
	if _doc == null or _profile == null:
		return "NET_MOVE_NO_MAP"
	if not players_open_doors:
		return "NET_DOOR_DISABLED"
	var lvl: MapLevel = _doc.level(level_index)
	if lvl == null or edge < 0 or not _doc.grid.edge_touches_map(edge):
		return "NET_DOOR_INVALID"
	var v: int = lvl.get_edge_by_id(edge)
	if not MapEdge.is_door(v):
		return "NET_DOOR_INVALID"
	if MapEdge.kind_of(v) == MapEdge.KIND_SECRET_DOOR and not MapEdge.has_flag(v, MapEdge.FLAG_DISCOVERED):
		return "NET_DOOR_INVALID"
	if MapEdge.has_flag(v, MapEdge.FLAG_OPEN) == open:
		return "NET_DOOR_INVALID"
	if open and MapEdge.has_flag(v, MapEdge.FLAG_LOCKED):
		return "NET_DOOR_LOCKED"
	var sides: Array[Vector2i] = _doc.grid.edge_cells(edge)
	for t: MapToken in _doc.tokens:
		if t.level != level_index or t.hidden or t.character_ref != p.ref():
			continue
		for c: Vector2i in _doc.token_cells(t, _profile):
			if sides.has(c):
				return ""
	return "NET_DOOR_TOO_FAR"


func _ping(p: Player, msg: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	var last: int = _last_ping.get(p.peer, -PING_INTERVAL_MS)
	if now - last < PING_INTERVAL_MS:
		return
	_last_ping[p.peer] = now
	var r: JsonReader = JsonReader.new()
	var li: int = r.get_int(msg, "level")
	var cell: Vector2i = Vector2i(r.get_int(msg, "x"), r.get_int(msg, "y"))
	if not r.ok() or _doc == null or _doc.level(li) == null or not _doc.grid.in_bounds(cell):
		return
	send_ping(li, cell, p.name)


## Señal en una casilla, a todos los jugadores y al DM (`pinged`).
func send_ping(level_index: int, cell: Vector2i, who: String) -> void:
	_broadcast(NetMessage.encode({"t": NetMessage.PING, "level": level_index, "x": cell.x, "y": cell.y, "name": who}))
	pinged.emit(level_index, cell, who)


func _broadcast(data: PackedByteArray) -> int:
	var n: int = 0
	for peer: int in _peers.keys():
		if _peers[peer] > 0:
			_send(peer, data)
			n += 1
	return n


func _send(peer: int, data: PackedByteArray) -> void:
	if send_bytes.is_valid() and not data.is_empty():
		send_bytes.call(peer, data)


func _deny(peer: int, key: String) -> void:
	_send(peer, NetMessage.encode({"t": NetMessage.DENIED, "key": key}))
	if deny_close_delay_ms <= 0:
		_drop(peer)
		return
	# Deja de atenderla ya (no está identificada) y la cierra después.
	_peers[peer] = -1
	_closing[peer] = Time.get_ticks_msec() + deny_close_delay_ms


func _drop(peer: int) -> void:
	if close_peer.is_valid():
		close_peer.call(peer)
	peer_disconnected(peer)
