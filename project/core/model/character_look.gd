class_name CharacterLook
extends RefCounted
## Aspecto modular de un personaje (PROYECTO §10.2): complexión, una pieza
## por ranura y un color por material. Los ids válidos los da LookCatalog
## (data/characters/look_catalog.json); aquí solo se guardan.

## Complexión (LookCatalog.Body.id).
var body: String = "humanoid_medium"
## Ranura ("head"…) → id de pieza. Ranura ausente = sin pieza.
var parts: Dictionary[String, String] = {}
## Material ("skin"…) → color. Material ausente = color por defecto del
## catálogo.
var colors: Dictionary[String, Color] = {}


func copy() -> CharacterLook:
	var c: CharacterLook = CharacterLook.new()
	c.body = body
	c.parts = parts.duplicate()
	c.colors = colors.duplicate()
	return c


func to_dict() -> Dictionary:
	var p: Dictionary = {}
	for k: String in parts:
		p[k] = parts[k]
	var c: Dictionary = {}
	for k: String in colors:
		c[k] = "#" + colors[k].to_html(false)
	return {"body": body, "parts": p, "colors": c}


static func from_dict(r: JsonReader, d: Dictionary) -> CharacterLook:
	var l: CharacterLook = CharacterLook.new()
	l.body = r.get_str(d, "body")
	var p: Dictionary = r.get_dict(d, "parts")
	for k: Variant in p:
		l.parts[r.to_str(k, "parts")] = r.to_str(p[k], "parts")
	var c: Dictionary = r.get_dict(d, "colors")
	for k: Variant in c:
		var hex: String = r.to_str(c[k], "colors")
		if not Color.html_is_valid(hex):
			r.fail("color no válido: " + hex)
			continue
		l.colors[r.to_str(k, "colors")] = Color.html(hex)
	return l
