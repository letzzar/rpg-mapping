class_name RemoveObjectCommand
extends MapCommand
## Quita un objeto de un nivel, generado o puesto a mano (editor de
## estancias, ADR 037). Se deshace volviéndolo a poner igual.

const DELTA_OP: String = "remove_object"

var level_index: int = 0
var object_id: int = 0
var _removed: MapObject = null
## Posición que tenía en la lista (se vuelve a poner ahí al deshacer).
var _index: int = -1


func _init(p_level: int, p_object_id: int) -> void:
	level_index = p_level
	object_id = p_object_id


func label_key() -> String:
	return "CMD_REMOVE_OBJECT"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null:
		return false
	_index = d.level(level_index).object_index(object_id)
	_removed = d.level(level_index).remove_object(object_id)
	if _removed == null:
		return false
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "id": object_id}))
	d.notify_changed(level_index, MapDocument.LAYER_OBJECTS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or _removed == null:
		return
	if not d.level(level_index).insert_object_at(_removed.copy(), _index):
		return
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var dl: MapDelta = d.deltas[i]
		if dl.op == DELTA_OP and dl.data.get("id", -1) == object_id:
			d.deltas.remove_at(i)
			break
	_removed = null
	d.notify_changed(level_index, MapDocument.LAYER_OBJECTS)
