class_name SetEdgeCommand
extends MapCommand
## Cambia el valor de una arista (muro, puerta, vano y sus banderas).
## Uso típico: abrir/cerrar, bloquear o descubrir una puerta.

const DELTA_OP: String = "set_edge"

var level_index: int = 0
var edge_id: int = 0
var new_value: int = 0

var _old_value: int = -1


func _init(p_level: int, p_edge_id: int, p_value: int) -> void:
	level_index = p_level
	edge_id = p_edge_id
	new_value = p_value


## Comando que alterna la bandera `flag` de la arista (p. ej. FLAG_OPEN).
static func toggle_flag(doc: MapDocument, p_level: int, p_edge_id: int, flag: int) -> SetEdgeCommand:
	var current: int = doc.level(p_level).get_edge_by_id(p_edge_id)
	return SetEdgeCommand.new(p_level, p_edge_id,
		MapEdge.with_flag(current, flag, not MapEdge.has_flag(current, flag)))


func label_key() -> String:
	return "CMD_SET_EDGE"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or level_index < 0 or level_index >= d.level_count():
		return false
	if not MapEdge.is_valid(new_value):
		return false
	var lvl: MapLevel = d.level(level_index)
	if lvl.get_edge_by_id(edge_id) == new_value:
		return false
	var old: int = lvl.set_edge_by_id(edge_id, new_value)
	if old < 0:
		return false
	_old_value = old
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "edge": edge_id, "value": new_value}))
	d.notify_changed(level_index, MapDocument.LAYER_EDGES)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or _old_value < 0:
		return
	d.level(level_index).set_edge_by_id(edge_id, _old_value)
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("edge", -1) == edge_id:
			d.deltas.remove_at(i)
			break
	_old_value = -1
	d.notify_changed(level_index, MapDocument.LAYER_EDGES)
