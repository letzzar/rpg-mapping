class_name SetTurnsCommand
extends MapCommand
## Sustituye el seguimiento de turnos del documento por otro (ADR 035):
## empezar o terminar el combate, cambiar la iniciativa o el orden, pasar
## turno. Se deshace volviendo al anterior. La etiqueta (para el historial)
## la elige quien lo crea.

const DELTA_OP: String = "set_turns"

var turns: TurnTracker = null
var _label: String = "CMD_SET_TURNS"
var _old: TurnTracker = null
var _applied: bool = false


func _init(p_turns: TurnTracker, p_label: String = "CMD_SET_TURNS") -> void:
	turns = p_turns.copy()
	_label = p_label


func label_key() -> String:
	return _label


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or turns.equals(d.turns):
		return false
	_old = d.turns
	d.turns = turns.copy()
	# Estado entero, para recrearlo (ADR 036); la etiqueta, para el historial.
	d.deltas.append(MapDelta.make(DELTA_OP, {"turns": turns.to_dict(), "label": _label}))
	_applied = true
	d.notify_changed(-1, MapDocument.LAYER_TURNS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	d.turns = _old
	for i: int in range(d.deltas.size() - 1, -1, -1):
		if d.deltas[i].op == DELTA_OP:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(-1, MapDocument.LAYER_TURNS)
