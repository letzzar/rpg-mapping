class_name SetRoomCommand
extends MapCommand
## Cambia el tipo y el nombre de una sala (editor de estancias, ADR 037).

const DELTA_OP: String = "set_room"

var level_index: int = 0
var room_id: int = 0
var kind: String = ""
var label: String = ""
var _old_kind: String = ""
var _old_label: String = ""
var _applied: bool = false


func _init(p_level: int, p_room_id: int, p_kind: String, p_label: String) -> void:
	level_index = p_level
	room_id = p_room_id
	kind = p_kind
	label = p_label


func label_key() -> String:
	return "CMD_SET_ROOM"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null:
		return false
	var r: MapRoom = d.level(level_index).room(room_id)
	if r == null or kind.is_empty() or (r.kind == kind and r.label == label):
		return false
	_old_kind = r.kind
	_old_label = r.label
	r.kind = kind
	r.label = label
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "room": room_id, "kind": kind, "label": label}))
	_applied = true
	d.notify_changed(level_index, MapDocument.LAYER_ROOMS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	var r: MapRoom = d.level(level_index).room(room_id)
	if r == null:
		return
	r.kind = _old_kind
	r.label = _old_label
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var dl: MapDelta = d.deltas[i]
		if dl.op == DELTA_OP and dl.data.get("room", -1) == room_id:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(level_index, MapDocument.LAYER_ROOMS)
