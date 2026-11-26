class_name AddObjectCommand
extends MapCommand
## Pone un objeto (del catálogo, ya instanciado con su id) en un nivel
## (editor de estancias, ADR 037). Se deshace quitándolo.

const DELTA_OP: String = "add_object"

var level_index: int = 0
var object: MapObject = null


func _init(p_level: int, p_object: MapObject) -> void:
	level_index = p_level
	object = p_object.copy()


func label_key() -> String:
	return "CMD_ADD_OBJECT"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null or not d.grid.in_bounds(object.cell):
		return false
	if not d.level(level_index).add_object(object.copy()):
		return false
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "id": object.id, "object": object.to_dict()}))
	d.notify_changed(level_index, MapDocument.LAYER_OBJECTS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null or d.level(level_index).remove_object(object.id) == null:
		return
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var dl: MapDelta = d.deltas[i]
		if dl.op == DELTA_OP and dl.data.get("id", -1) == object.id:
			d.deltas.remove_at(i)
			break
	d.notify_changed(level_index, MapDocument.LAYER_OBJECTS)
