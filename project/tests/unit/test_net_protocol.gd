extends GutTest
## Partida en red (F4): tramas WebSocket del servidor, mensajes comprimidos y
## lectura de peticiones HTTP. Sin sockets: corre igual en escritorio y web.


func _masked(opcode: int, text: String, fin: bool = true) -> PackedByteArray:
	return WsCodec.encode_masked(opcode, text.to_utf8_buffer(), PackedByteArray([0x12, 0x34, 0x56, 0x78]), fin)


## Ejemplo de la RFC 6455 §1.3.
func test_accept_key_matches_rfc_example() -> void:
	assert_eq(WsCodec.accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")


## Las tres formas de longitud (7 bits, 16 bits, 64 bits) en los límites.
func test_encode_length_forms() -> void:
	for n: int in [0, 125, 126, 65535, 65536]:
		var p: PackedByteArray = PackedByteArray()
		p.resize(n)
		var f: PackedByteArray = WsCodec.encode(WsCodec.OP_BINARY, p)
		assert_eq(f[0], 0x82, "FIN + binario")
		var header: int = 2 if n < 126 else (4 if n <= 0xFFFF else 10)
		assert_eq(f.size(), header + n, "tamaño con %d bytes" % n)
		if n >= 126 and n <= 0xFFFF:
			assert_eq(f[1], 126)
			assert_eq((f[2] << 8) | f[3], n)
		elif n > 0xFFFF:
			assert_eq(f[1], 127)


## El decodificador desenmascara, junta fragmentos aunque lleguen byte a
## byte y deja pasar los ping entre fragmentos.
func test_decoder_unmasks_and_joins_fragments() -> void:
	var stream: PackedByteArray = PackedByteArray()
	stream.append_array(_masked(WsCodec.OP_TEXT, "hola ", false))
	stream.append_array(_masked(WsCodec.OP_PING, "?"))
	stream.append_array(_masked(WsCodec.OP_CONTINUATION, "mundo"))
	var big: String = "x".repeat(70000)
	stream.append_array(_masked(WsCodec.OP_BINARY, big))
	var dec: WsCodec.Decoder = WsCodec.Decoder.new()
	var got: Array[WsCodec.Frame] = []
	for i: int in stream.size():
		got.append_array(dec.feed(stream.slice(i, i + 1)))
	assert_eq(dec.error, "")
	assert_eq(got.size(), 3)
	assert_eq(got[0].opcode, WsCodec.OP_PING)
	assert_eq(got[1].opcode, WsCodec.OP_TEXT)
	assert_eq(got[1].payload.get_string_from_utf8(), "hola mundo")
	assert_eq(got[2].payload.size(), 70000)


func test_decoder_rejects_bad_frames() -> void:
	var unmasked: WsCodec.Decoder = WsCodec.Decoder.new()
	unmasked.feed(WsCodec.encode(WsCodec.OP_TEXT, "x".to_utf8_buffer()))
	assert_ne(unmasked.error, "", "un cliente siempre enmascara")
	var big: WsCodec.Decoder = WsCodec.Decoder.new(1000)
	big.feed(_masked(WsCodec.OP_BINARY, "y".repeat(1001)))
	assert_ne(big.error, "", "mensaje mayor que el límite")
	var orphan: WsCodec.Decoder = WsCodec.Decoder.new()
	orphan.feed(_masked(WsCodec.OP_CONTINUATION, "z"))
	assert_ne(orphan.error, "", "continuación sin mensaje")


func test_message_round_trip_and_garbage() -> void:
	var msg: Dictionary = {"t": NetMessage.MOVE, "token": 7, "level": 0, "x": 3, "y": 4}
	var b: PackedByteArray = NetMessage.encode(msg)
	var back: Dictionary = NetMessage.decode(b, NetMessage.MAX_FROM_CLIENT)
	assert_eq(_s(back, "t"), NetMessage.MOVE)
	assert_eq(_i(back, "x"), 3)
	assert_eq(NetMessage.decode(PackedByteArray([1, 2, 3]), 1024), {}, "no es gzip")
	assert_eq(NetMessage.decode("{\"t\":1}".to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP), 1024), {}, "t no es texto")
	# Una "bomba" de gzip no pasa del límite.
	var bomb: PackedByteArray = ("{\"t\":\"x\",\"a\":\"" + "a".repeat(200000) + "\"}").to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	assert_lt(bomb.size(), 2000)
	assert_eq(NetMessage.decode(bomb, NetMessage.MAX_FROM_CLIENT), {}, "más de 64 KB al descomprimir")


func test_parse_request() -> void:
	var req: Dictionary = WssServer.parse_request("GET /index.html?sala=ABC&t=X HTTP/1.1\r\nHost: 10.0.0.2:47830\r\nUpgrade: websocket")
	assert_eq(_s(req, "method"), "GET")
	assert_eq(_s(req, "path"), "/index.html", "sin la consulta")
	var headers: Dictionary = req["headers"]
	assert_eq(_s(headers, "host"), "10.0.0.2:47830")
	assert_eq(_s(headers, "upgrade"), "websocket")
	assert_eq(WssServer.parse_request("basura"), {})


func test_random_codes_use_crockford_alphabet() -> void:
	var seen: Dictionary[String, bool] = {}
	for i: int in 50:
		var c: String = GameSession.random_code(10)
		assert_eq(c.length(), 10)
		for ch: String in c:
			assert_true(GameSession.CODE_ALPHABET.contains(ch), c)
		seen[c] = true
	assert_eq(seen.size(), 50, "no se repiten")

func _s(d: Dictionary, key: String) -> String:
	var v: String = d.get(key, "")
	return v


func _i(d: Dictionary, key: String) -> int:
	var v: float = d.get(key, -1.0)
	return int(v)


## Las direcciones de los enlaces: primero la de la red de verdad, después
## las de máquinas virtuales y VPN; sin bucle local ni autoconfiguradas.
## Datos reales de un equipo con WSL, VMware y Tailscale.
func test_invite_address_prefers_the_real_network() -> void:
	var ifaces: Array[Dictionary] = [
		{"name": "{472F}", "friendly": "vEthernet (Default Switch)", "addresses": ["fe80:0:0:0:4054:de50:e6c3:a60d", "172.26.64.1"]},
		{"name": "{628A}", "friendly": "Loopback Pseudo-Interface 1", "addresses": ["0:0:0:0:0:0:0:1", "127.0.0.1"]},
		{"name": "{8DAF}", "friendly": "VMware Network Adapter VMnet8", "addresses": ["192.168.222.1"]},
		{"name": "{9A79}", "friendly": "Conexión de área local", "addresses": ["169.254.177.24"]},
		{"name": "{B14C}", "friendly": "Ethernet", "addresses": ["10.10.5.19"]},
		{"name": "{3721}", "friendly": "Tailscale", "addresses": ["fd7a:115c:a1e0::f33a:eb52", "100.79.235.82"]},
		{"name": "wlan0", "addresses": ["192.168.1.40"]},
	]
	var ips: PackedStringArray = PackedStringArray()
	for a: Dictionary in NetHostPanel.rank_addresses(ifaces):
		var ip: String = a["ip"]
		ips.append(ip)
	assert_eq(",".join(ips), "10.10.5.19,192.168.1.40,172.26.64.1,192.168.222.1,100.79.235.82")

## Con un proxy delante (la imagen Docker del NAS, ADR 016) los enlaces llevan
## la dirección pública; siempre HTTPS y sin barra final. Se recuerda.
func test_invite_link_uses_public_address() -> void:
	assert_eq(NetHostPanel.normalize_public_url("  nas.local:8443/ "), "https://nas.local:8443")
	assert_eq(NetHostPanel.normalize_public_url("http://rpg.example.org"), "https://rpg.example.org")
	assert_eq(NetHostPanel.normalize_public_url("https://rpg.example.org//"), "https://rpg.example.org")
	assert_eq(NetHostPanel.normalize_public_url("   "), "")
	var cfg: String = "user://test_net_public.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg))
	var panel: NetHostPanel = NetHostPanel.new()
	panel.config_path = cfg
	add_child_autofree(panel)
	assert_eq(panel.public_url(), "")
	assert_string_starts_with(panel.base_url(), "https://")
	panel.set_public_url("nas.local:8443")
	var p: GameSession.Player = panel.session.add_player("Ana")
	assert_string_starts_with(panel.invite_link(p), "https://nas.local:8443/?sala=")
	var again: NetHostPanel = NetHostPanel.new()
	again.config_path = cfg
	add_child_autofree(again)
	assert_eq(again.public_url(), "https://nas.local:8443", "se recuerda")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg))
