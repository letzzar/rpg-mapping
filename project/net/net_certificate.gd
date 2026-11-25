class_name NetCertificate
extends RefCounted
## Certificado TLS del servidor del DM (PROYECTO §11: solo WSS/HTTPS).
##
## Si en `dir` hay `server.key` y `server.crt` se usan tal cual: así el DM
## puede poner un certificado propio (p. ej. de su dominio) sustituyendo esos
## dos ficheros. Si no, se crea uno autofirmado (RSA 2048, 10 años) y se
## guarda para que el navegador de cada jugador solo tenga que aceptarlo una
## vez y no en cada partida.

const DEFAULT_DIR: String = "user://net"
const KEY_FILE: String = "server.key"
const CERT_FILE: String = "server.crt"
const ISSUER: String = "CN=RPG Mapping,O=RPG Mapping,C=ES"

var key: CryptoKey = null
var cert: X509Certificate = null
## Fichero del certificado (para la huella).
var cert_path: String = ""
## true si se acaba de crear (no existía).
var created: bool = false
## Mensaje técnico si falló; "" si hay clave y certificado.
var error: String = ""


static func load_or_create(dir: String = DEFAULT_DIR) -> NetCertificate:
	var nc: NetCertificate = NetCertificate.new()
	var key_path: String = dir.path_join(KEY_FILE)
	var cert_path: String = dir.path_join(CERT_FILE)
	nc.cert_path = cert_path
	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path):
		nc.key = CryptoKey.new()
		nc.cert = X509Certificate.new()
		if nc.key.load(key_path) != OK or nc.cert.load(cert_path) != OK:
			nc.error = "no se pudo leer " + dir
		return nc
	DirAccess.make_dir_recursive_absolute(dir)
	var crypto: Crypto = Crypto.new()
	nc.key = crypto.generate_rsa(2048)
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var year: int = now["year"]
	var month: int = now["month"]
	var day: int = now["day"]
	var stamp: String = "%02d%02d000000" % [month, mini(day, 28)]
	# Desde hace un año (relojes desajustados) hasta dentro de 10 años.
	nc.cert = crypto.generate_self_signed_certificate(nc.key, ISSUER, str(year - 1) + stamp, str(year + 10) + stamp)
	if nc.key.save(key_path) != OK or nc.cert.save(cert_path) != OK:
		nc.error = "no se pudo guardar en " + dir
	nc.created = true
	return nc


## Huella SHA-256 del certificado (hex con dos puntos), para comprobar a
## mano en el navegador que es el del DM.
func fingerprint() -> String:
	if cert_path.is_empty() or not FileAccess.file_exists(cert_path):
		return ""
	# Del fichero y sin bytes nulos: save_to_string() deja un NUL al final y
	# convertirlo a texto llena el registro de avisos Unicode.
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(cert_path)
	var clean: PackedByteArray = PackedByteArray()
	for b: int in raw:
		if b != 0:
			clean.append(b)
	var pem: String = clean.get_string_from_ascii()
	var b64: String = pem.replace("-----BEGIN CERTIFICATE-----", "").replace("-----END CERTIFICATE-----", "").strip_escapes().replace(" ", "")
	var der: PackedByteArray = Marshalls.base64_to_raw(b64)
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(der)
	var hex: String = ctx.finish().hex_encode().to_upper()
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(0, hex.length(), 2):
		parts.append(hex.substr(i, 2))
	return ":".join(parts)
