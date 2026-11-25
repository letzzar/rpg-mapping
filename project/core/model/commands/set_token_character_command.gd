class_name SetTokenCharacterCommand
extends MapCommand
## Cambia MapToken.character_ref de una ficha. En la partida en red (F4,
## ADR 031) así el DM da una ficha a un jugador ("player:<id>"): la sesión
## solo deja mover a cada jugador las fichas con su referencia. Al pasar de
## un mapa a otro la ficha conserva la referencia (MapNavigator copia la
## ficha entera), así que el jugador la sigue moviendo dentro del edificio.

const DELTA_OP: String = "set_token_character"

var token_id: int = -1
var character_ref: String = ""
var _old: String = ""
var _applied: bool = false


func _init(p_token_id: int, p_ref: String) -> void:
	token_id = p_token_id
	character_ref = p_ref


func label_key() -> String:
	return "CMD_SET_TOKEN_CHARACTER"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null:
		return false
	var t: MapToken = d.token(token_id)
	if t == null or t.character_ref == character_ref:
		return false
	_old = t.character_ref
	t.character_ref = character_ref
	d.deltas.append(MapDelta.make(DELTA_OP, {"token": token_id, "ref": character_ref}))
	_applied = true
	d.notify_changed(t.level, MapDocument.LAYER_TOKENS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	var t: MapToken = d.token(token_id)
	if t == null:
		return
	t.character_ref = _old
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("token", -1) == token_id:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(t.level, MapDocument.LAYER_TOKENS)
