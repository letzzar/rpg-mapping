class_name WssServer
extends RefCounted
## Servidor TLS del DM (ADR 016 y 031): en UN SOLO puerto sirve por HTTPS el
## cliente web (los ficheros de la exportación "Web") y acepta el WebSocket
## seguro en la ruta /ws. Mismo origen: el jugador acepta una vez el
## certificado al abrir la página y el WSS funciona sin más avisos ni
## contenido mixto.
##
## Sin nodos: quien lo usa llama a poll() en cada fotograma. Cada conexión
## WebSocket tiene un id (> 0) para send()/close() y las señales.
##
## HTTP mínimo: solo GET, sin keep-alive (una petición por conexión) y sin
## rangos. Los ficheros se leen una vez y quedan en memoria, también
## comprimidos con gzip si el navegador lo acepta (el .wasm de Godot baja de
## ~40 MB a ~10 MB).

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal message_received(id: int, data: PackedByteArray)

const DEFAULT_PORT: int = 47830
const WS_PATH: String = "/ws"
const MAX_HEADER: int = 16 * 1024
const MAX_CONNECTIONS: int = 64
const HANDSHAKE_TIMEOUT_MS: int = 15000
## Espera máxima a que el cliente responda al cierre de un WebSocket.
const CLOSE_TIMEOUT_MS: int = 2000
## Bytes como máximo escritos por conexión y llamada a poll().
const WRITE_BUDGET: int = 8 * 1024 * 1024
## Una escritura cabe siempre en UN registro TLS. Ver _flush().
const WRITE_CHUNK: int = 4 * 1024
## Tamaño máximo de un mensaje de un jugador.
const MAX_CLIENT_MESSAGE: int = 256 * 1024

const MIME: Dictionary[String, String] = {
	"html": "text/html; charset=utf-8",
	"js": "application/javascript",
	"wasm": "application/wasm",
	"pck": "application/octet-stream",
	"png": "image/png",
	"ico": "image/x-icon",
	"svg": "image/svg+xml",
	"json": "application/json",
	"webmanifest": "application/manifest+json",
}
const COMPRESSIBLE: PackedStringArray = ["html", "js", "wasm", "pck", "json", "svg"]

enum State { TLS, HTTP, WS, CLOSING }


class Conn:
	extends RefCounted
	var id: int = 0
	var tls: StreamPeerTLS = null
	var state: int = State.TLS
	var created_ms: int = 0
	var head: PackedByteArray = PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	var out_pos: int = 0
	## Longitud de la última escritura que no salió (0 = ninguna): hay que
	## repetirla exactamente igual (contrato de mbedtls_ssl_write).
	var retry_len: int = 0
	var decoder: WsCodec.Decoder = null
	## Cierre de WebSocket en curso: se espera el cierre del cliente antes de
	## cortar (si se corta antes, el TCP puede descartar lo último enviado).
	var ws_closing: bool = false
	var closing_ms: int = 0


## Carpeta con index.html del cliente web; "" = no sirve páginas (solo WSS).
var web_root: String = ""
## Comprimir con gzip lo que lo admita (si el navegador lo acepta).
var use_gzip: bool = true
## Error de la última operación (texto técnico).
var error: String = ""

var _tcp: TCPServer = null
var _tls_options: TLSOptions = null
var _conns: Array[Conn] = []
var _next_id: int = 1
var _files: Dictionary[String, PackedByteArray] = {}
var _gz_files: Dictionary[String, PackedByteArray] = {}


func start(port: int, key: CryptoKey, cert: X509Certificate, bind_address: String = "*") -> Error:
	stop()
	_tls_options = TLSOptions.server(key, cert)
	_tcp = TCPServer.new()
	var err: Error = _tcp.listen(port, bind_address)
	if err != OK:
		error = "no se pudo escuchar en el puerto %d (%s)" % [port, error_string(err)]
		_tcp = null
	return err


func is_listening() -> bool:
	return _tcp != null and _tcp.is_listening()


func port() -> int:
	return _tcp.get_local_port() if _tcp != null else 0


func stop() -> void:
	for c: Conn in _conns.duplicate():
		_drop(c)
	_conns.clear()
	if _tcp != null:
		_tcp.stop()
	_tcp = null


## Conexiones WebSocket abiertas.
func peer_count() -> int:
	var n: int = 0
	for c: Conn in _conns:
		if c.state == State.WS:
			n += 1
	return n


func send(id: int, data: PackedByteArray) -> void:
	var c: Conn = _find(id)
	if c != null and c.state == State.WS:
		c.out.append_array(WsCodec.encode(WsCodec.OP_BINARY, data))


## Cierra la conexión (tras enviar lo pendiente).
func close(id: int) -> void:
	var c: Conn = _find(id)
	if c != null and c.state == State.WS:
		_begin_ws_close(c, 1000)


func _begin_ws_close(c: Conn, status: int) -> void:
	c.out.append_array(WsCodec.encode_close(status))
	c.state = State.CLOSING
	c.ws_closing = true
	c.closing_ms = Time.get_ticks_msec()
	peer_disconnected.emit(c.id)


func poll() -> void:
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var tcp: StreamPeerTCP = _tcp.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			tcp.disconnect_from_host()
			continue
		tcp.set_no_delay(true)
		var c: Conn = Conn.new()
		c.tls = StreamPeerTLS.new()
		c.created_ms = Time.get_ticks_msec()
		if c.tls.accept_stream(tcp, _tls_options) != OK:
			tcp.disconnect_from_host()
			continue
		_conns.append(c)
	for c: Conn in _conns.duplicate():
		_poll_conn(c)


func _poll_conn(c: Conn) -> void:
	c.tls.poll()
	var st: int = c.tls.get_status()
	if st == StreamPeerTLS.STATUS_HANDSHAKING:
		if Time.get_ticks_msec() - c.created_ms > HANDSHAKE_TIMEOUT_MS:
			_drop(c)
		return
	if st != StreamPeerTLS.STATUS_CONNECTED:
		_drop(c)
		return
	if c.state == State.TLS:
		c.state = State.HTTP
	var avail: int = c.tls.get_available_bytes()
	if avail > 0:
		var res: Array = c.tls.get_partial_data(avail)
		var err: int = res[0]
		var data: PackedByteArray = res[1]
		if err != OK:
			_drop(c)
			return
		if c.state == State.HTTP:
			_on_http_bytes(c, data)
		elif c.state == State.WS:
			_on_ws_bytes(c, data)
		elif c.ws_closing and c.decoder.error.is_empty():
			# Solo interesa el cierre del cliente; lo demás se descarta.
			for f: WsCodec.Frame in c.decoder.feed(data):
				if f.opcode == WsCodec.OP_CLOSE:
					c.ws_closing = false
	if not _flush(c):
		_drop(c)
		return
	if c.state == State.CLOSING and c.out_pos >= c.out.size():
		var waited: int = Time.get_ticks_msec() - c.closing_ms
		if not c.ws_closing or not c.decoder.error.is_empty() or waited > CLOSE_TIMEOUT_MS:
			_drop(c)


## Escribe lo pendiente; false si la conexión falló.
##
## Cuando el socket no admite más, mbedtls se queda el registro ya cifrado y
## responde "reintentar" (put_partial_data da 0 enviados); la siguiente
## llamada DEBE llevar los mismos datos y la misma longitud, porque mbedtls
## envía lo que tenía guardado y da por escrita la longitud que se le pasa.
## Godot (put_partial_data) encadena varias mbedtls_ssl_write en una llamada:
## si el trozo ocupa más de un registro y el segundo se queda guardado, avisa
## solo de los bytes del primero, y el reintento ya no coincide con lo que
## mbedtls guardó. Así se perdían ~16 KB en mitad del .wasm con Chrome (que
## lee más despacio mientras descomprime) y fallaba
## (ERR_CONTENT_DECODING_FAILED); escribiendo con bloqueo llegaba entero.
## Por eso cada escritura cabe en un registro (4 KB, por debajo de cualquier
## tamaño máximo negociado) y, si no sale, se repite idéntica.
func _flush(c: Conn) -> bool:
	var budget: int = WRITE_BUDGET
	while c.out_pos < c.out.size() and budget > 0:
		var n: int = c.retry_len if c.retry_len > 0 else mini(WRITE_CHUNK, c.out.size() - c.out_pos)
		var chunk: PackedByteArray = c.out.slice(c.out_pos, c.out_pos + n)
		var res: Array = c.tls.put_partial_data(chunk)
		var err: int = res[0]
		var sent: int = res[1]
		if err != OK:
			return false
		if sent == 0:
			c.retry_len = n
			break
		c.retry_len = 0
		c.out_pos += sent
		budget -= sent
		if sent < n:
			break
	if c.out_pos >= c.out.size():
		c.out = PackedByteArray()
		c.out_pos = 0
	elif c.out_pos > 1024 * 1024:
		c.out = c.out.slice(c.out_pos)
		c.out_pos = 0
	return true


# --- HTTP ------------------------------------------------------------------

func _on_http_bytes(c: Conn, data: PackedByteArray) -> void:
	c.head.append_array(data)
	var text: String = c.head.get_string_from_ascii()
	var end: int = text.find("\r\n\r\n")
	if end < 0:
		if c.head.size() > MAX_HEADER:
			_respond(c, 431, "text/plain", "cabecera demasiado grande".to_utf8_buffer())
		return
	var req: Dictionary = parse_request(text.substr(0, end))
	c.head = PackedByteArray()
	if req.is_empty():
		_respond(c, 400, "text/plain", "petición no válida".to_utf8_buffer())
		return
	var method: String = req["method"]
	var path: String = req["path"]
	var headers: Dictionary = req["headers"]
	if method != "GET":
		_respond(c, 405, "text/plain", "solo GET".to_utf8_buffer())
		return
	if path == WS_PATH:
		_upgrade(c, headers)
		return
	_serve_file(c, path, str(headers.get("accept-encoding", "")))


## Petición HTTP: {"method", "path" (sin la consulta), "headers" (claves en
## minúsculas)}; {} si la línea de petición no es válida.
static func parse_request(head: String) -> Dictionary:
	var lines: PackedStringArray = head.split("\r\n")
	if lines.is_empty():
		return {}
	var first: PackedStringArray = lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/1."):
		return {}
	var target: String = first[1]
	var q: int = target.find("?")
	if q >= 0:
		target = target.substr(0, q)
	var headers: Dictionary = {}
	for k: int in range(1, lines.size()):
		var colon: int = lines[k].find(":")
		if colon > 0:
			headers[lines[k].substr(0, colon).strip_edges().to_lower()] = lines[k].substr(colon + 1).strip_edges()
	return {"method": first[0], "path": target.uri_decode(), "headers": headers}


func _upgrade(c: Conn, headers: Dictionary) -> void:
	var upgrade: String = str(headers.get("upgrade", "")).to_lower()
	var key: String = str(headers.get("sec-websocket-key", ""))
	if upgrade != "websocket" or key.is_empty() or str(headers.get("sec-websocket-version", "")) != "13":
		_respond(c, 400, "text/plain", "se esperaba un WebSocket".to_utf8_buffer())
		return
	# Otra web abierta en el navegador del jugador no puede conectarse a la
	# partida: el origen, si lo hay, debe ser este mismo servidor.
	var origin: String = str(headers.get("origin", ""))
	if not origin.is_empty() and origin != "https://" + str(headers.get("host", "")):
		_respond(c, 403, "text/plain", "origen no permitido".to_utf8_buffer())
		return
	var resp: String = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
		+ "Sec-WebSocket-Accept: " + WsCodec.accept_key(key) + "\r\n\r\n"
	c.out.append_array(resp.to_ascii_buffer())
	c.state = State.WS
	c.decoder = WsCodec.Decoder.new(MAX_CLIENT_MESSAGE)
	c.id = _next_id
	_next_id += 1
	peer_connected.emit(c.id)


func _serve_file(c: Conn, path: String, accept_encoding: String) -> void:
	if web_root.is_empty():
		_respond(c, 404, "text/plain", "este servidor no tiene el cliente web".to_utf8_buffer())
		return
	var rel: String = path.trim_prefix("/")
	if rel.is_empty():
		rel = "index.html"
	if rel.contains("..") or rel.contains("\\") or rel.contains(":"):
		_respond(c, 404, "text/plain", "no encontrado".to_utf8_buffer())
		return
	var ext: String = rel.get_extension().to_lower()
	if not MIME.has(ext):
		_respond(c, 404, "text/plain", "no encontrado".to_utf8_buffer())
		return
	var body: PackedByteArray = _file_bytes(rel)
	if body.is_empty():
		_respond(c, 404, "text/plain", "no encontrado".to_utf8_buffer())
		return
	var gzip: bool = use_gzip and COMPRESSIBLE.has(ext) and accept_encoding.contains("gzip")
	if gzip:
		if not _gz_files.has(rel):
			_gz_files[rel] = body.compress(FileAccess.COMPRESSION_GZIP)
		body = _gz_files[rel]
	_respond(c, 200, MIME[ext], body, "Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n" if gzip else "")


func _file_bytes(rel: String) -> PackedByteArray:
	if _files.has(rel):
		return _files[rel]
	var full: String = web_root.path_join(rel)
	if not FileAccess.file_exists(full):
		return PackedByteArray()
	var b: PackedByteArray = FileAccess.get_file_as_bytes(full)
	_files[rel] = b
	return b


func _respond(c: Conn, status: int, mime: String, body: PackedByteArray, extra: String = "") -> void:
	var reason: Dictionary[int, String] = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"}
	var head: String = "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\n%sConnection: close\r\n\r\n" \
		% [status, reason.get(status, "Error"), mime, body.size(), extra]
	c.out.append_array(head.to_ascii_buffer())
	c.out.append_array(body)
	c.state = State.CLOSING


# --- WebSocket ---------------------------------------------------------------

func _on_ws_bytes(c: Conn, data: PackedByteArray) -> void:
	for f: WsCodec.Frame in c.decoder.feed(data):
		match f.opcode:
			WsCodec.OP_BINARY, WsCodec.OP_TEXT:
				message_received.emit(c.id, f.payload)
			WsCodec.OP_PING:
				c.out.append_array(WsCodec.encode(WsCodec.OP_PONG, f.payload))
			WsCodec.OP_CLOSE:
				# Cierra el cliente: se responde y ya no hay que esperarle.
				close(c.id)
				c.ws_closing = false
				return
		if c.state != State.WS:
			return
	if not c.decoder.error.is_empty():
		_begin_ws_close(c, 1002)


func _find(id: int) -> Conn:
	for c: Conn in _conns:
		if c.id == id:
			return c
	return null


func _drop(c: Conn) -> void:
	var was_ws: bool = c.state == State.WS
	c.tls.disconnect_from_stream()
	_conns.erase(c)
	if was_ws:
		peer_disconnected.emit(c.id)
