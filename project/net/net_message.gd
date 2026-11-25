class_name NetMessage
extends RefCounted
## Mensajes de la partida en red (ADR 031): un diccionario {"t": tipo, ...}
## en JSON comprimido con gzip, enviado como mensaje binario de WebSocket.
## El JSON de un nivel de mazmorra ocupa decenas de KB y casi todo son listas
## de enteros repetidos: comprimido queda en unos pocos KB.
##
## Tipos (cliente → servidor):
##   hello  {room, token}            entrar con el código de sala y el del jugador
##   move   {token, level, x, y}     propone mover una ficha propia
##   ping   {level, x, y}            señala una casilla a todos
## Tipos (servidor → cliente):
##   welcome {name, ref, system}     acceso aceptado: nombre, ficha propia, sistema
##   map     {grid, levels, title}   mapa nuevo: el cliente vacía su copia
##   level   {i, content, explored}  contenido filtrado de un nivel + niebla
##   vision  {i, visible}            casillas que el grupo ve ahora en un nivel
##   tokens  {list}                  fichas que el jugador puede ver
##   ping    {level, x, y, name}     alguien señaló una casilla
##   notice  {key}                   aviso para la barra de estado (clave i18n)
##   denied  {key}                   acceso rechazado (y se cierra)

const HELLO: String = "hello"
const MOVE: String = "move"
const PING: String = "ping"
const WELCOME: String = "welcome"
const MAP: String = "map"
const LEVEL: String = "level"
const VISION: String = "vision"
const TOKENS: String = "tokens"
const NOTICE: String = "notice"
const DENIED: String = "denied"

## Límites al descomprimir (un mensaje malicioso no puede pedir más memoria).
const MAX_FROM_CLIENT: int = 64 * 1024
const MAX_FROM_SERVER: int = 64 * 1024 * 1024


static func encode(msg: Dictionary) -> PackedByteArray:
	return CanonicalJson.stringify(msg).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


## Diccionario del mensaje, o {} si no es un mensaje válido (gzip roto,
## demasiado grande, no es JSON o le falta "t").
static func decode(data: PackedByteArray, max_size: int) -> Dictionary:
	# Cabecera gzip y tamaño sin comprimir (los 4 últimos bytes, RFC 1952):
	# así lo que no es gzip o anuncia más del límite se descarta sin intentar
	# descomprimirlo (y sin errores del motor en el registro).
	if data.size() < 18 or data[0] != 0x1F or data[1] != 0x8B:
		return {}
	var n: int = data.size()
	var isize: int = data[n - 4] | (data[n - 3] << 8) | (data[n - 2] << 16) | (data[n - 1] << 24)
	if isize == 0 or isize > max_size:
		return {}
	var raw: PackedByteArray = data.decompress_dynamic(max_size, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var json: JSON = JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		return {}
	var v: Variant = json.data
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	if typeof(d.get("t")) != TYPE_STRING:
		return {}
	return d


## Bytes en base64 para el JSON (niebla y visibilidad: 1 byte por casilla).
static func bytes_to_text(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b) if not b.is_empty() else ""


static func text_to_bytes(s: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(s) if not s.is_empty() else PackedByteArray()
