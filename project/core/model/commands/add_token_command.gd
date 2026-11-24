class_name AddTokenCommand
extends MapCommand
## Añade una ficha al documento (y la quita al deshacer).

const DELTA_OP: String = "add_token"

var token: MapToken = null


## `p_token` debe traer ya su id (MapDocument.allocate_id()).
func _init(p_token: MapToken) -> void:
	token = p_token


func label_key() -> String:
	return "CMD_ADD_TOKEN"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or token == null or not d.grid.in_bounds(token.cell):
		return false
	if not d.add_token(token.copy()):
		return false
	d.deltas.append(MapDelta.make(DELTA_OP, {
		"token": token.id, "level": token.level, "x": token.cell.x, "y": token.cell.y,
		"side": token.side, "size": token.size_id, "name": token.name}))
	d.notify_changed(token.level, MapDocument.LAYER_TOKENS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or d.remove_token(token.id) == null:
		return
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("token", -1) == token.id:
			d.deltas.remove_at(i)
			break
	d.notify_changed(token.level, MapDocument.LAYER_TOKENS)
