extends GutTest
## Partida en red (F4) con sockets de verdad en 127.0.0.1: WssServer (HTTPS
## + WSS en el mismo puerto, certificado autofirmado), GameSession y 8
## NetClient. Criterio de F4: 8 clientes y latencia < 150 ms. Solo en
## escritorio: en web no se puede abrir un servidor TCP.

const CERT_DIR: String = "user://test_net_cert"
const WEB_DIR: String = "user://test_net_web"
const CLIENTS: int = 8
const LATENCY_LIMIT_MS: int = 150
const EAST: int = 1

var _cert: NetCertificate
var _server: WssServer
var _session: GameSession
var _doc: MapDocument
var _profile: SystemProfile
var _stack: CommandStack


func before_all() -> void:
	if OS.has_feature("web"):
		return
	_cert = NetCertificate.load_or_create(CERT_DIR)
	DirAccess.make_dir_recursive_absolute(WEB_DIR)
	var f: FileAccess = FileAccess.open(WEB_DIR.path_join("index.html"), FileAccess.WRITE)
	f.store_string("<!doctype html><title>cliente</title>" + "<p>relleno</p>".repeat(2000))
	f.close()


func before_each() -> void:
	if OS.has_feature("web"):
		return
	_profile = SystemProfile.find_by_seed_code("DND5")
	_doc = MapDocument.create("square", 30, 20)
	_doc.level(0).fill_terrain(Terrain.FLOOR)
	_stack = CommandStack.new(_doc)
	_server = WssServer.new()
	_server.web_root = WEB_DIR
	assert_eq(_server.start(0, _cert.key, _cert.cert, "127.0.0.1"), OK)
	_session = GameSession.new()
	var opts: PartyVision.Options = PartyVision.Options.new()
	opts.ambient_lit = true
	_session.set_vision_options(opts)
	_session.set_document(_doc, _profile, "Prueba")
	_session.send_bytes = _server.send
	_session.close_peer = _server.close
	_server.peer_connected.connect(func(id: int) -> void:
		if not _session.peer_connected(id):
			_server.close(id))
	_server.peer_disconnected.connect(_session.peer_disconnected)
	_server.message_received.connect(_session.receive)
	_session.move_approved.connect(func(cmd: MoveTokenCommand) -> void:
		_stack.execute(cmd)
		_session.mark_dirty())


func after_each() -> void:
	if _server != null:
		_server.stop()


func _tls() -> TLSOptions:
	return TLSOptions.client(_cert.cert, "RPG Mapping")


## Hace girar servidor, sesión y clientes hasta que `done` sea true.
func _pump(clients: Array[NetClient], done: Callable, timeout_ms: int = 10000) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		_server.poll()
		_session.flush()
		for c: NetClient in clients:
			c.poll()
		if done.call():
			return true
		await get_tree().process_frame
	return false


func test_serves_the_web_client_over_https() -> void:
	if OS.has_feature("web"):
		pending("sin servidor TCP en web")
		return
	var expected: PackedByteArray = FileAccess.get_file_as_bytes(WEB_DIR.path_join("index.html"))
	for gzip: bool in [false, true]:
		var http: HTTPClient = HTTPClient.new()
		assert_eq(http.connect_to_host("127.0.0.1", _server.port(), _tls()), OK)
		var body: PackedByteArray = PackedByteArray()
		var headers: Dictionary = {}
		var requested: bool = false
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 10000:
			_server.poll()
			http.poll()
			var st: int = http.get_status()
			if st == HTTPClient.STATUS_CONNECTED and not requested:
				var h: PackedStringArray = ["Accept-Encoding: gzip"] if gzip else []
				http.request(HTTPClient.METHOD_GET, "/?sala=ABC&t=XYZ", h)
				requested = true
			elif st == HTTPClient.STATUS_BODY:
				headers = http.get_response_headers_as_dictionary()
				body.append_array(http.read_response_body_chunk())
			elif requested and (st == HTTPClient.STATUS_DISCONNECTED or (st == HTTPClient.STATUS_CONNECTED and not body.is_empty())):
				break
			await get_tree().process_frame
		var enc: String = headers.get("Content-Encoding", "")
		if gzip:
			assert_eq(enc, "gzip")
			body = body.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP)
			assert_lt(http.get_response_body_length(), expected.size() / 4, "comprimido")
		else:
			assert_eq(enc, "")
		assert_eq(http.get_response_code(), 200)
		assert_eq(body, expected, "index.html para / (gzip: %s)" % gzip)
		http.close()


## Ocho jugadores conectados por WSS; cada uno mueve su ficha y se mide el
## tiempo hasta que los ocho la ven en su sitio nuevo.
func test_eight_clients_and_latency() -> void:
	if OS.has_feature("web"):
		pending("sin servidor TCP en web")
		return
	var clients: Array[NetClient] = []
	var heroes: Array[int] = []
	for k: int in CLIENTS:
		var p: GameSession.Player = _session.add_player("J%d" % k)
		var t: MapToken = MapToken.new()
		t.id = _doc.allocate_id()
		t.name = p.name
		t.cell = Vector2i(2, 1 + 2 * k)
		t.side = MapToken.SIDE_PLAYER
		t.character_ref = p.ref()
		_stack.execute(AddTokenCommand.new(t))
		heroes.append(t.id)
		var c: NetClient = NetClient.new()
		assert_eq(c.connect_to("wss://127.0.0.1:%d/ws" % _server.port(), _session.room_code, p.code, _tls()), OK)
		clients.append(c)
	var r: PartyVision.Result = PartyVision.compute(_doc, 0, _profile, PartyVision.Options.new())
	_stack.execute(ExploreCommand.new(0, PartyVision.VIEWER_PARTY, _all_cells()))
	assert_gt(r.viewer_count, 0)
	_session.mark_dirty()
	var all_in: bool = await _pump(clients, func() -> bool:
		for c: NetClient in clients:
			if c.document == null or c.document.tokens.size() != CLIENTS:
				return false
		return true)
	assert_true(all_in, "los 8 conectados y con el mapa")
	assert_eq(_server.peer_count(), CLIENTS)
	assert_eq(_session.connected_count(), CLIENTS)
	var worst: int = 0
	for k: int in CLIENTS:
		var target: Vector2i = Vector2i(10 + k, 1 + 2 * k)
		var t0: int = Time.get_ticks_msec()
		clients[k].propose_move(heroes[k], 0, target)
		var hid: int = heroes[k]
		var seen: bool = await _pump(clients, func() -> bool:
			for c: NetClient in clients:
				var t: MapToken = c.document.token(hid)
				if t == null or t.cell != target:
					return false
			return true, 2000)
		var ms: int = Time.get_ticks_msec() - t0
		worst = maxi(worst, ms)
		assert_true(seen, "movimiento %d visto por todos" % k)
	gut.p("latencia peor de %d movimientos con %d clientes: %d ms" % [CLIENTS, CLIENTS, worst])
	assert_lt(worst, LATENCY_LIMIT_MS)
	# Un movimiento ajeno se rechaza y avisa solo al que lo pidió.
	var notices: Array[String] = []
	clients[0].notice.connect(func(key: String) -> void: notices.append(key))
	clients[0].propose_move(heroes[1], 0, Vector2i(20, 3))
	await _pump(clients, func() -> bool: return not notices.is_empty(), 2000)
	assert_eq(notices.size(), 1)
	if not notices.is_empty():
		assert_eq(notices[0], "NET_MOVE_NOT_YOURS")
	for c: NetClient in clients:
		c.close()


func test_wrong_codes_are_closed() -> void:
	if OS.has_feature("web"):
		pending("sin servidor TCP en web")
		return
	var p: GameSession.Player = _session.add_player("Ana")
	var c: NetClient = NetClient.new()
	var denied: Array[String] = []
	c.denied.connect(func(key: String) -> void: denied.append(key))
	assert_eq(c.connect_to("wss://127.0.0.1:%d/ws" % _server.port(), "ZZZZZZ", p.code, _tls()), OK)
	var clients: Array[NetClient] = [c]
	var done: bool = await _pump(clients, func() -> bool: return not denied.is_empty())
	assert_true(done)
	if done:
		assert_eq(denied[0], "NET_ERR_ROOM")
	assert_eq(p.peer, 0)


func _all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in _doc.grid.cell_count():
		out.append(_doc.grid.cell_at(i))
	return out
