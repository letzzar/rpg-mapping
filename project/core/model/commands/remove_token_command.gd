class_name RemoveTokenCommand
extends MapCommand
## Quita una ficha del documento (y la vuelve a poner al deshacer). Lo usa la
## navegación jerárquica (F3) para sacar al grupo de un mapa y meterlo en otro.

const DELTA_OP: String = "remove_token"

var token_id: int = -1
var _removed: MapToken = null


func _init(p_token_id: int) -> void:
	token_id = p_token_id


func label_key() -> String:
	return "CMD_REMOVE_TOKEN"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null:
		return false
	_removed = d.remove_token(token_id)
	if _removed == null:
		return false
	d.deltas.append(MapDelta.make(DELTA_OP, {"token": token_id}))
	d.notify_changed(_removed.level, MapDocument.LAYER_TOKENS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or _removed == null:
		return
	# add_token la devuelve a su sitio (la lista se ordena por id).
	if not d.add_token(_removed.copy()):
		return
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("token", -1) == token_id:
			d.deltas.remove_at(i)
			break
	d.notify_changed(_removed.level, MapDocument.LAYER_TOKENS)
