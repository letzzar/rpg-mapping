class_name NetClient
extends RefCounted
## Cliente de la partida en red (jugador; F4, ADR 031). Mantiene una copia
## del mapa que solo tiene lo que el servidor deja ver (PlayerView) y propone
## movimientos. Sin nodos: quien lo usa llama a poll() en cada fotograma.
##
## En web el navegador hace el TLS (la página ya se aceptó con el mismo
## certificado y origen). En escritorio hay que pasar TLSOptions (las
## pruebas usan TLSOptions.client() con el certificado del servidor).

signal connected
## Se cerró la conexión (por el servidor o por la red).
signal closed
## Acceso aceptado: nombre del jugador.
signal welcomed(player_name: String)
## Acceso rechazado (clave i18n).
signal denied(key: String)
## Mapa nuevo: `document` es otro objeto.
signal map_reset
## Cambió lo visible de un nivel.
signal vision_changed(level_index: int)
signal pinged(level_index: int, cell: Vector2i, who: String)
## Aviso del servidor (clave i18n), p. ej. movimiento rechazado.
signal notice(key: String)

## Copia filtrada del mapa (null hasta el primer "map").
var document: MapDocument = null
var player_name: String = ""
## MapToken.character_ref de las fichas propias.
var my_ref: String = ""
## Código de sistema (SystemProfile.seed_code) del DM.
var system_code: String = ""
var title: String = ""
## Visible ahora por nivel (vacío = nadie del grupo en ese nivel).
var visible: Array[PackedByteArray] = []
## Último error de conexión (texto técnico).
var error: String = ""

var _ws: WebSocketPeer = null
var _room: String = ""
var _token: String = ""
var _open: bool = false


## Conecta a `url` (wss://servidor:puerto/ws) y se identifica con el código
## de sala y el del jugador.
func connect_to(url: String, room: String, token: String, tls: TLSOptions = null) -> Error:
	close()
	_room = room
	_token = token
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 64 * 1024 * 1024
	_ws.max_queued_packets = 4096
	var err: Error = _ws.connect_to_url(url, tls)
	if err != OK:
		error = error_string(err)
		_ws = null
	return err


func is_open() -> bool:
	return _open


func close() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_open = false


func poll() -> void:
	if _ws == null:
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _open:
		_open = true
		connected.emit()
		_send({"t": NetMessage.HELLO, "room": _room, "token": _token})
	# También al cerrarse: el último mensaje (p. ej. "denied") puede llegar
	# junto con el cierre.
	while _ws != null and _ws.get_available_packet_count() > 0:
		handle_message(NetMessage.decode(_ws.get_packet(), NetMessage.MAX_FROM_SERVER))
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_open = false
		closed.emit()


## true si la ficha es del jugador.
func owns(t: MapToken) -> bool:
	return t != null and not my_ref.is_empty() and t.character_ref == my_ref


func propose_move(token_id: int, level_index: int, cell: Vector2i) -> void:
	_send({"t": NetMessage.MOVE, "token": token_id, "level": level_index, "x": cell.x, "y": cell.y})


func send_ping(level_index: int, cell: Vector2i) -> void:
	_send({"t": NetMessage.PING, "level": level_index, "x": cell.x, "y": cell.y})


func visible_of(level_index: int) -> PackedByteArray:
	return visible[level_index] if level_index >= 0 and level_index < visible.size() else PackedByteArray()


func _send(msg: Dictionary) -> void:
	if _ws != null and _open:
		_ws.put_packet(NetMessage.encode(msg))


## Aplica un mensaje del servidor. Público para las pruebas sin red.
func handle_message(msg: Dictionary) -> void:
	if msg.is_empty():
		return
	var r: JsonReader = JsonReader.new()
	var t: String = msg["t"]
	match t:
		NetMessage.WELCOME:
			player_name = r.get_str(msg, "name")
			my_ref = r.get_str(msg, "ref")
			system_code = r.get_str(msg, "system")
			welcomed.emit(player_name)
		NetMessage.DENIED:
			denied.emit(r.get_str(msg, "key"))
			close()
		NetMessage.MAP:
			var g: Dictionary = r.get_dict(msg, "grid")
			var doc: MapDocument = MapDocument.create(r.get_str(g, "kind"), r.get_int(g, "width"), r.get_int(g, "height"), r.get_int(msg, "levels"))
			if doc == null or not r.ok():
				return
			document = doc
			title = r.get_str(msg, "title")
			visible.clear()
			visible.resize(doc.level_count())
			map_reset.emit()
		NetMessage.LEVEL:
			_load_level(r, msg)
		NetMessage.VISION:
			var vi: int = r.get_int(msg, "i")
			if document != null and r.ok() and vi >= 0 and vi < visible.size():
				var vb: PackedByteArray = NetMessage.text_to_bytes(r.get_str(msg, "visible"))
				visible[vi] = vb if vb.size() == document.grid.cell_count() else PackedByteArray()
				vision_changed.emit(vi)
		NetMessage.TOKENS:
			if document == null:
				return
			document.tokens.clear()
			for td: Dictionary in r.get_dicts(msg, "list"):
				document.add_token(MapToken.from_dict(r, td))
			document.notify_changed(-1, MapDocument.LAYER_TOKENS)
		NetMessage.PING:
			pinged.emit(r.get_int(msg, "level"), Vector2i(r.get_int(msg, "x"), r.get_int(msg, "y")), r.get_str(msg, "name"))
		NetMessage.NOTICE:
			notice.emit(r.get_str(msg, "key"))


func _load_level(r: JsonReader, msg: Dictionary) -> void:
	var i: int = r.get_int(msg, "i")
	if document == null or not r.ok() or i < 0 or i >= document.level_count():
		return
	var lvl: MapLevel = MapLevel.new(document.grid)
	lvl.load_dicts(r, r.get_dict(msg, "content"), {})
	lvl.load_explored(PartyVision.VIEWER_PARTY, NetMessage.text_to_bytes(r.get_str(msg, "explored")))
	if not r.ok():
		push_warning("nivel %d recibido no válido: %s" % [i, r.error])
		return
	document.levels[i] = lvl
	document.notify_changed(i, MapDocument.LAYER_ALL)
