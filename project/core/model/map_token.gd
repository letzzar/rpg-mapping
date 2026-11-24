class_name MapToken
extends RefCounted
## Ficha de un personaje o criatura. Es estado de SESIÓN (no lo crean los
## generadores): no entra en MapDocument.content_hash().

const SIDE_PLAYER: String = "player"
const SIDE_ALLY: String = "ally"
const SIDE_NEUTRAL: String = "neutral"
const SIDE_ENEMY: String = "enemy"
const SIDES: PackedStringArray = ["player", "ally", "neutral", "enemy"]

## Id estable (único en todo el documento).
var id: int = 0
var name: String = ""
## Nivel (índice en MapDocument.levels) y casilla de anclaje.
var level: int = 0
var cell: Vector2i = Vector2i.ZERO
## Id de tamaño del perfil de sistema ("medium"…); casillas que ocupa:
## SystemProfile.size_cells() y MapDocument.token_cells().
var size_id: String = "medium"
var side: String = SIDE_NEUTRAL
## Ruta o id del personaje (*.rpgm-char.json); "" si no tiene ficha.
var character_ref: String = ""
## Solo la ve el DM.
var hidden: bool = false


func copy() -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = id
	t.name = name
	t.level = level
	t.cell = cell
	t.size_id = size_id
	t.side = side
	t.character_ref = character_ref
	t.hidden = hidden
	return t


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"level": level,
		"cell": [cell.x, cell.y],
		"size_id": size_id,
		"side": side,
		"character_ref": character_ref,
		"hidden": hidden,
	}


static func from_dict(r: JsonReader, d: Dictionary) -> MapToken:
	var t: MapToken = MapToken.new()
	t.id = r.get_int(d, "id")
	t.name = r.get_str(d, "name")
	t.level = r.get_int(d, "level")
	t.cell = r.get_vec2i(d, "cell")
	t.size_id = r.get_str(d, "size_id")
	t.side = r.get_str(d, "side")
	t.character_ref = r.get_str(d, "character_ref")
	t.hidden = r.get_bool(d, "hidden")
	if not SIDES.has(t.side):
		r.fail("side desconocido: " + t.side)
	return t
