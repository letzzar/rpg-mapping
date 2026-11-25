class_name WsCodec
extends RefCounted
## WebSocket (RFC 6455) del lado servidor, sin nodos (ADR 031). Lo usa
## WssServer porque el mismo puerto sirve el cliente web por HTTPS y el WSS
## (ADR 016): Godot no permite pasar a su WebSocketPeer una conexión cuya
## petición HTTP ya se ha leído para decidir si es una página o el WebSocket.
##
## - accept_key(): respuesta del saludo (Sec-WebSocket-Accept).
## - encode(): trama del servidor (sin máscara, un solo fragmento).
## - Decoder: acumula bytes del cliente y devuelve mensajes completos
##   (desenmascara, junta fragmentos, separa control: ping, pong, cierre).

const GUID: String = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

const OP_CONTINUATION: int = 0x0
const OP_TEXT: int = 0x1
const OP_BINARY: int = 0x2
const OP_CLOSE: int = 0x8
const OP_PING: int = 0x9
const OP_PONG: int = 0xA


## Valor de Sec-WebSocket-Accept para la clave del cliente.
static func accept_key(client_key: String) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update((client_key.strip_edges() + GUID).to_utf8_buffer())
	return Marshalls.raw_to_base64(ctx.finish())


## Trama completa (FIN) con `opcode` y la carga dada. El servidor no
## enmascara (RFC 6455 §5.1).
static func encode(opcode: int, payload: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.append(0x80 | (opcode & 0x0F))
	var n: int = payload.size()
	if n < 126:
		out.append(n)
	elif n <= 0xFFFF:
		out.append(126)
		out.append((n >> 8) & 0xFF)
		out.append(n & 0xFF)
	else:
		out.append(127)
		for k: int in 8:
			out.append((n >> (56 - 8 * k)) & 0xFF)
	out.append_array(payload)
	return out


## Trama de cierre con código de estado (1000 = normal).
static func encode_close(status: int = 1000) -> PackedByteArray:
	var p: PackedByteArray = PackedByteArray([(status >> 8) & 0xFF, status & 0xFF])
	return encode(OP_CLOSE, p)


## Un mensaje o trama de control ya completo.
class Frame:
	extends RefCounted
	var opcode: int = 0
	var payload: PackedByteArray = PackedByteArray()


## Decodificador incremental de tramas del CLIENTE (enmascaradas).
class Decoder:
	extends RefCounted
	## Tamaño máximo de un mensaje (protege de clientes que anuncian 2⁶³ bytes).
	var max_message: int = 1 << 20
	## Texto del error de protocolo; "" si todo va bien. Tras un error, la
	## conexión debe cerrarse (los bytes restantes no se interpretan).
	var error: String = ""

	var _buf: PackedByteArray = PackedByteArray()
	var _msg_opcode: int = -1
	var _msg: PackedByteArray = PackedByteArray()

	func _init(p_max_message: int = 1 << 20) -> void:
		max_message = p_max_message

	## Añade bytes recibidos y devuelve los mensajes/tramas de control que
	## queden completos, en orden.
	func feed(data: PackedByteArray) -> Array[Frame]:
		var out: Array[Frame] = []
		if not error.is_empty():
			return out
		_buf.append_array(data)
		while error.is_empty():
			var f: Frame = _next()
			if f == null:
				break
			out.append(f)
		return out

	func _next() -> Frame:
		if _buf.size() < 2:
			return null
		var b0: int = _buf[0]
		var b1: int = _buf[1]
		var fin: bool = (b0 & 0x80) != 0
		var opcode: int = b0 & 0x0F
		if (b0 & 0x70) != 0:
			error = "bits RSV sin extensión"
			return null
		if (b1 & 0x80) == 0:
			error = "trama de cliente sin máscara"
			return null
		var plen: int = b1 & 0x7F
		var pos: int = 2
		if plen == 126:
			if _buf.size() < 4:
				return null
			plen = (_buf[2] << 8) | _buf[3]
			pos = 4
		elif plen == 127:
			if _buf.size() < 10:
				return null
			plen = 0
			for k: int in 8:
				plen = (plen << 8) | _buf[2 + k]
			pos = 10
			if plen < 0:
				error = "longitud no válida"
				return null
		var control: bool = opcode >= 0x8
		if control and (plen > 125 or not fin):
			error = "trama de control no válida"
			return null
		if plen > max_message or (not control and _msg.size() + plen > max_message):
			error = "mensaje demasiado grande"
			return null
		if _buf.size() < pos + 4 + plen:
			return null
		var mask: PackedByteArray = _buf.slice(pos, pos + 4)
		var payload: PackedByteArray = _buf.slice(pos + 4, pos + 4 + plen)
		for i: int in plen:
			payload[i] = payload[i] ^ mask[i & 3]
		_buf = _buf.slice(pos + 4 + plen)
		if control:
			var c: Frame = Frame.new()
			c.opcode = opcode
			c.payload = payload
			return c
		if opcode == OP_CONTINUATION:
			if _msg_opcode < 0:
				error = "continuación sin mensaje"
				return null
			_msg.append_array(payload)
		else:
			if _msg_opcode >= 0:
				error = "mensaje nuevo sin terminar el anterior"
				return null
			if opcode != OP_TEXT and opcode != OP_BINARY:
				error = "opcode desconocido: %d" % opcode
				return null
			_msg_opcode = opcode
			_msg = payload
		if not fin:
			return _next()
		var m: Frame = Frame.new()
		m.opcode = _msg_opcode
		m.payload = _msg
		_msg_opcode = -1
		_msg = PackedByteArray()
		return m


## Trama de cliente (con máscara): solo para pruebas del servidor sin
## WebSocketPeer.
static func encode_masked(opcode: int, payload: PackedByteArray, mask: PackedByteArray, fin: bool = true) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.append((0x80 if fin else 0) | (opcode & 0x0F))
	var n: int = payload.size()
	if n < 126:
		out.append(0x80 | n)
	elif n <= 0xFFFF:
		out.append(0x80 | 126)
		out.append((n >> 8) & 0xFF)
		out.append(n & 0xFF)
	else:
		out.append(0x80 | 127)
		for k: int in 8:
			out.append((n >> (56 - 8 * k)) & 0xFF)
	out.append_array(mask)
	for i: int in n:
		out.append(payload[i] ^ mask[i & 3])
	return out
