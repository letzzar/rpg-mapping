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
## Dueño de la ficha en la partida en red ("player:<id>", GameSession) o
## referencia libre; "" si no es de nadie.
var character_ref: String = ""
## Solo la ve el DM.
var hidden: bool = false
## Personaje que representa (velocidades, sentidos, retrato y aspecto);
## null = ficha genérica (velocidad del perfil, disco de color). ADR 034.
var sheet: CharacterSheet = null
## Botín que lleva (enemigos, PNJ; ADR 048). Es de esta ficha, no del
## personaje: dos goblins iguales pueden llevar cosas distintas. Solo se
## guarda si hay algo.
var loot: Array[LootItem] = []
## El DM lo enseña a los jugadores.
var loot_revealed: bool = false


## Velocidad caminando: la del personaje o, sin él, la del perfil.
func speed_ft(profile: SystemProfile) -> int:
	if sheet != null:
		return sheet.speed_ft("walk", profile)
	return profile.default_speed_ft if profile != null else 0


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
	t.sheet = sheet.copy() if sheet != null else null
	t.loot = LootItem.list_copy(loot)
	t.loot_revealed = loot_revealed
	return t


func to_dict() -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"name": name,
		"level": level,
		"cell": [cell.x, cell.y],
		"size_id": size_id,
		"side": side,
		"character_ref": character_ref,
		"hidden": hidden,
	}
	if sheet != null:
		d["sheet"] = sheet.to_dict()
	if not loot.is_empty():
		d["loot"] = LootItem.list_to_array(loot)
	if loot_revealed:
		d["loot_revealed"] = true
	return d


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
	# Opcional: los mapas anteriores a F5 no lo tienen.
	if d.has("sheet"):
		t.sheet = CharacterSheet.from_dict(r, r.get_dict(d, "sheet"))
	if d.has("loot"):
		t.loot = LootItem.list_from_array(r, r.get_array(d, "loot"))
	t.loot_revealed = d.has("loot_revealed") and r.get_bool(d, "loot_revealed")
	if not SIDES.has(t.side):
		r.fail("side desconocido: " + t.side)
	return t
