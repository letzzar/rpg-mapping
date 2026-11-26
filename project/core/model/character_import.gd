class_name CharacterImport
extends RefCounted
## Importadores de personajes (PROYECTO §10.1, ADR 034): CSV sencillo y JSON
## genérico con mapeo de campos. Ambos dan CharacterSheet con el sistema del
## perfil activo.
##
## Campos reconocidos (cabeceras CSV o claves del mapeo JSON), en inglés o
## español, sin distinguir mayúsculas ni tildes:
## - name / nombre; size / tamaño (id del perfil: "medium", "mediano"…);
## - side / bando (player, ally, neutral, enemy; jugador, aliado, neutral,
##   enemigo); no es del personaje sino de su ficha: va en Result.sides;
## - speed / velocidad (= walk), y cada modo de movimiento del perfil por su id
##   (fly, swim…) o su nombre en español (vuelo, nado, trepar, excavar);
## - cada sentido del perfil por su id (darkvision…) o en español
##   (vision_en_la_oscuridad, vista_ciega…);
## - initiative / iniciativa (modificador, puede ser negativo);
## - preset / modelo: un modelo tipo del catálogo (aspecto y tamaño).
## Las distancias son pies; "9 m" se convierte con la convención de Units
## (1,5 m = 5 ft). Columnas desconocidas se ignoran y se avisan.

## Alias (normalizados) → campo interno. Los modos y sentidos del perfil se
## añaden por su id.
const ALIASES: Dictionary[String, String] = {
	"name": "name", "nombre": "name",
	"size": "size", "size_id": "size", "tamano": "size",
	"side": "side", "bando": "side",
	"speed": "walk", "velocidad": "walk", "walk": "walk", "caminar": "walk", "andar": "walk",
	"vuelo": "fly", "volar": "fly", "nado": "swim", "nadar": "swim",
	"trepar": "climb", "escalar": "climb", "excavar": "burrow",
	"vision_en_la_oscuridad": "darkvision", "vision_oscuridad": "darkvision",
	"vista_ciega": "blindsight", "sentido_ciego": "blindsight",
	"sentir_vibraciones": "tremorsense", "vision_verdadera": "truesight",
	"vision_en_penumbra": "low_light_vision", "olfato": "scent",
	"initiative": "initiative", "iniciativa": "initiative", "init": "initiative",
	"preset": "preset", "modelo": "preset",
}
const SIZE_ALIASES: Dictionary[String, String] = {
	"diminuto": "tiny", "pequeno": "small", "mediano": "medium",
	"grande": "large", "enorme": "huge", "gargantuesco": "gargantuan",
}
const _NORM_FROM: PackedStringArray = ["á", "é", "í", "ó", "ú", "ü", "ñ", " ", "-"]
const _NORM_TO: PackedStringArray = ["a", "e", "i", "o", "u", "u", "n", "_", "_"]
const SIDE_ALIASES: Dictionary[String, String] = {
	"jugador": "player", "aliado": "ally", "neutral": "neutral", "enemigo": "enemy",
	"player": "player", "ally": "ally", "enemy": "enemy",
}


class Result:
	extends RefCounted
	var sheets: Array[CharacterSheet] = []
	## Bando de la ficha de cada personaje ("" = sin indicar).
	var sides: PackedStringArray = PackedStringArray()
	## Avisos legibles: "fila 3: tamaño desconocido 'xx'" (no traducidos: son
	## diagnóstico del fichero del usuario, con nombres de columna suyos).
	var warnings: PackedStringArray = PackedStringArray()
	## Error que impide importar; "" si se importó algo.
	var error: String = ""


## CSV con cabecera. Separador `,`, `;` o tabulador (el más frecuente en la
## cabecera); comillas dobles como en RFC 4180.
static func from_csv(text: String, profile: SystemProfile) -> Result:
	var res: Result = Result.new()
	var rows: Array[PackedStringArray] = parse_csv(text)
	if rows.size() < 2:
		res.error = "CHAR_IMPORT_EMPTY"
		return res
	var fields: PackedStringArray = PackedStringArray()
	for h: String in rows[0]:
		var f: String = field_for(h, profile)
		fields.append(f)
		if f.is_empty() and not h.strip_edges().is_empty():
			res.warnings.append("columna ignorada: '%s'" % h.strip_edges())
	if not fields.has("name"):
		res.error = "CHAR_IMPORT_NO_NAME"
		return res
	for ri: int in range(1, rows.size()):
		var values: Dictionary[String, String] = {}
		for ci: int in mini(fields.size(), rows[ri].size()):
			if not fields[ci].is_empty():
				values[fields[ci]] = rows[ri][ci].strip_edges()
		_add(res, values, profile, "fila %d" % (ri + 1))
	if res.sheets.is_empty() and res.error.is_empty():
		res.error = "CHAR_IMPORT_EMPTY"
	return res


## JSON: nuestro formato (*.rpgm-char.json), una lista de objetos o un
## objeto. `mapping`: campo (como las cabeceras CSV: "name", "walk",
## "darkvision"…) → ruta con puntos en el objeto ("stats.speed.walk",
## "senses.0.range"). Sin mapeo se buscan los campos por su nombre.
static func from_json(text: String, profile: SystemProfile, mapping: Dictionary[String, String] = {}) -> Result:
	var res: Result = Result.new()
	var parsed: Variant = CharacterSheet.parse_json_quiet(text)
	var items: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		items = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if d.get("format", "") == CharacterSheet.FORMAT:
			var lr: CharacterSheet.LoadResult = CharacterSheet.from_json(text)
			if lr.sheet == null:
				res.error = "CHAR_IMPORT_BAD_FILE"
				res.warnings.append(lr.error)
			else:
				res.sheets.append(lr.sheet)
				res.sides.append("")
			return res
		items = [d]
	else:
		res.error = "CHAR_IMPORT_BAD_FILE"
		return res
	for i: int in items.size():
		if typeof(items[i]) != TYPE_DICTIONARY:
			res.warnings.append("elemento %d: no es un objeto" % (i + 1))
			continue
		var obj: Dictionary = items[i]
		var values: Dictionary[String, String] = {}
		if mapping.is_empty():
			for k: Variant in obj:
				var f: String = field_for(str(k), profile)
				var v: Variant = obj[k]
				if not f.is_empty() and typeof(v) != TYPE_DICTIONARY and typeof(v) != TYPE_ARRAY:
					values[f] = _scalar(v)
		else:
			for f: String in mapping:
				var v: Variant = value_at(obj, mapping[f])
				var field: String = field_for(f, profile)
				if v != null and not field.is_empty():
					values[field] = _scalar(v)
		_add(res, values, profile, "elemento %d" % (i + 1))
	if res.sheets.is_empty() and res.error.is_empty():
		res.error = "CHAR_IMPORT_EMPTY"
	return res


## Campos que se pueden mapear con el perfil `profile`, en orden de
## presentación.
static func mappable_fields(profile: SystemProfile) -> PackedStringArray:
	var out: PackedStringArray = ["name", "size", "side", "walk"]
	if profile != null:
		for m: String in profile.movement_modes:
			if not out.has(m):
				out.append(m)
		for s: String in profile.senses:
			out.append(s)
	out.append_array(["initiative", "preset"])
	return out


## Rutas con valor simple (texto, número, booleano) del primer objeto del
## JSON `text` ("stats.speed.walk"…), en orden; vacío si no hay objetos.
static func leaf_paths(text: String) -> PackedStringArray:
	var parsed: Variant = CharacterSheet.parse_json_quiet(text)
	if typeof(parsed) == TYPE_ARRAY:
		var a: Array = parsed
		parsed = a[0] if not a.is_empty() else null
	var out: PackedStringArray = PackedStringArray()
	if typeof(parsed) == TYPE_DICTIONARY:
		_collect_paths(parsed, "", out)
	return out


static func _collect_paths(v: Variant, prefix: String, out: PackedStringArray) -> void:
	if out.size() >= 400:
		return
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort()
		for k: Variant in keys:
			_collect_paths(d[k], prefix + str(k) + ".", out)
	elif typeof(v) == TYPE_ARRAY:
		var a: Array = v
		for i: int in mini(a.size(), 8):
			_collect_paths(a[i], prefix + str(i) + ".", out)
	elif not prefix.is_empty():
		out.append(prefix.trim_suffix("."))


## Mapeo propuesto: para cada campo, la primera ruta cuyo último tramo se
## reconoce como ese campo (["stats.speed" → walk]…).
static func suggest_mapping(paths: PackedStringArray, profile: SystemProfile) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for p: String in paths:
		var parts: PackedStringArray = p.split(".")
		for k: int in range(parts.size() - 1, -1, -1):
			if parts[k].is_valid_int():
				continue
			var f: String = field_for(parts[k], profile)
			if not f.is_empty() and not out.has(f):
				out[f] = p
			break
	return out


## Campo interno de una cabecera o clave ("" si no se reconoce).
static func field_for(header: String, profile: SystemProfile) -> String:
	var k: String = normalize(header)
	if ALIASES.has(k):
		return ALIASES[k]
	if profile != null and (profile.movement_modes.has(k) or profile.senses.has(k)):
		return k
	return ""


## Minúsculas, sin tildes y con "_" en vez de espacios o guiones.
static func normalize(s: String) -> String:
	var out: String = s.strip_edges().to_lower()
	for i: int in _NORM_FROM.size():
		out = out.replace(_NORM_FROM[i], _NORM_TO[i])
	return out


## Valor en una ruta con puntos ("a.b.0.c"); null si no existe.
static func value_at(obj: Variant, path: String) -> Variant:
	var cur: Variant = obj
	for key: String in path.split(".", false):
		if typeof(cur) == TYPE_DICTIONARY:
			var d: Dictionary = cur
			if not d.has(key):
				return null
			cur = d[key]
		elif typeof(cur) == TYPE_ARRAY and key.is_valid_int():
			var a: Array = cur
			var i: int = key.to_int()
			if i < 0 or i >= a.size():
				return null
			cur = a[i]
		else:
			return null
	return cur


## Distancia en pies de un texto ("30", "30 ft", "30 pies", "9 m", "9,5 m").
## -1 si no se entiende.
static func parse_feet(s: String) -> int:
	var t: String = s.strip_edges().to_lower().replace(",", ".")
	var metres: bool = false
	for suf: String in ["pies", "feet", "ft", "pie", "m"]:
		if t.ends_with(suf):
			metres = suf == "m"
			t = t.substr(0, t.length() - suf.length()).strip_edges()
			break
	if t.is_valid_int():
		var n: int = t.to_int()
		if not metres:
			return n if n >= 0 else -1
		return _metres_to_ft(n * 100)
	if metres and t.is_valid_float():
		# Centésimas de metro con aritmética entera tras el redondeo.
		var parts: PackedStringArray = t.split(".")
		var dec: String = (parts[1] + "00").substr(0, 2)
		var cm: int = parts[0].to_int() * 100 + dec.to_int()
		return _metres_to_ft(cm)
	return -1


## Centímetros → pies con la convención de Units (1,5 m = 5 ft), redondeado.
static func _metres_to_ft(cm: int) -> int:
	if cm < 0:
		return -1
	var mm_per_5ft: int = Units.ft_to_mm(5)
	return (cm * 10 * 5 + mm_per_5ft / 2) / mm_per_5ft


## Lee un CSV en filas (sin las vacías).
static func parse_csv(text: String) -> Array[PackedStringArray]:
	var t: String = text.replace("\r\n", "\n").replace("\r", "\n")
	if t.begins_with("﻿"):
		t = t.substr(1)
	var first: String = t.get_slice("\n", 0)
	var sep: String = ","
	if first.count(";") > first.count(sep):
		sep = ";"
	if first.count("\t") > first.count(sep):
		sep = "\t"
	var rows: Array[PackedStringArray] = []
	var row: PackedStringArray = PackedStringArray()
	var cell: String = ""
	var quoted: bool = false
	var i: int = 0
	while i < t.length():
		var ch: String = t[i]
		if quoted:
			if ch == "\"":
				if i + 1 < t.length() and t[i + 1] == "\"":
					cell += "\""
					i += 1
				else:
					quoted = false
			else:
				cell += ch
		elif ch == "\"":
			quoted = true
		elif ch == sep:
			row.append(cell)
			cell = ""
		elif ch == "\n":
			row.append(cell)
			cell = ""
			if not _blank(row):
				rows.append(row)
			row = PackedStringArray()
		else:
			cell += ch
		i += 1
	row.append(cell)
	if not _blank(row):
		rows.append(row)
	return rows


static func _blank(row: PackedStringArray) -> bool:
	for c: String in row:
		if not c.strip_edges().is_empty():
			return false
	return true


static func _scalar(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if f == floorf(f):
			return str(int(f))
	return str(v)


static func _add(res: Result, values: Dictionary[String, String], profile: SystemProfile, where: String) -> void:
	var name: String = _v(values, "name")
	if name.is_empty():
		res.warnings.append("%s: sin nombre, se omite" % where)
		return
	var cat: LookCatalog = LookCatalog.load_default()
	var c: CharacterSheet = CharacterSheet.new()
	c.name = name
	c.system = profile.id if profile != null else ""
	c.look = cat.default_look("humanoid_medium")
	var preset_id: String = normalize(_v(values, "preset"))
	if not preset_id.is_empty():
		var p: LookCatalog.Preset = cat.preset(preset_id)
		if p == null:
			res.warnings.append("%s: modelo desconocido '%s'" % [where, values["preset"]])
		else:
			c.look = cat.look_from_preset(p)
			c.size_id = p.size_id
	var size: String = normalize(_v(values, "size"))
	if not size.is_empty():
		size = SIZE_ALIASES.get(size, size)
		if profile != null and not profile.size_ids.has(size):
			res.warnings.append("%s: tamaño desconocido '%s'" % [where, values["size"]])
		else:
			c.size_id = size
	var side: String = ""
	var side_raw: String = normalize(_v(values, "side"))
	if not side_raw.is_empty():
		side = SIDE_ALIASES.get(side_raw, "")
		if side.is_empty():
			res.warnings.append("%s: bando desconocido '%s'" % [where, values["side"]])
	var keys: Array = values.keys()
	keys.sort()
	for f: String in keys:
		var v: String = values[f]
		if v.is_empty():
			continue
		var is_mode: bool = f == "walk" or (profile != null and profile.movement_modes.has(f))
		var is_sense: bool = profile != null and profile.senses.has(f)
		if not is_mode and not is_sense:
			if f == "initiative":
				var s: String = v.trim_prefix("+")
				if s.is_valid_int():
					c.has_initiative = true
					c.initiative = s.to_int()
				else:
					res.warnings.append("%s: iniciativa no válida '%s'" % [where, v])
			continue
		var ft: int = parse_feet(v)
		if ft < 0:
			res.warnings.append("%s: distancia no válida en '%s': '%s'" % [where, f, v])
		elif is_mode:
			c.speeds[f] = ft
		else:
			c.senses[f] = ft
	res.sheets.append(c)
	res.sides.append(side)


static func _v(values: Dictionary[String, String], key: String) -> String:
	if not values.has(key):
		return ""
	return values[key]
