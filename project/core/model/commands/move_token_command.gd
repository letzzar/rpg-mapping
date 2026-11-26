class_name MoveTokenCommand
extends MapCommand
## Mueve una ficha a otra casilla (y opcionalmente a otro nivel).
##
## No valida reglas de movimiento: eso lo decide quien crea el comando (la
## vista avisa del coste; el DM puede mover libremente). Sí rechaza destinos
## fuera del mapa o niveles inexistentes.

const DELTA_OP: String = "move_token"

var token_id: int = 0
var to_cell: Vector2i = Vector2i.ZERO
var to_level: int = 0
## Coste en pies de la ruta (lo calcula quien crea el comando). Si es el
## turno de la ficha se suma a lo gastado (TurnTracker.moved_ft, ADR 035).
var cost_ft: int = 0

var _from_cell: Vector2i = Vector2i.ZERO
var _from_level: int = 0
## Destino original del primer paso (para fusionar arrastres consecutivos).
var _applied: bool = false
var _counted_ft: int = 0


func _init(p_token_id: int, p_to_cell: Vector2i, p_to_level: int, p_cost_ft: int = 0) -> void:
	token_id = p_token_id
	to_cell = p_to_cell
	to_level = p_to_level
	cost_ft = maxi(0, p_cost_ft)


func label_key() -> String:
	return "CMD_MOVE_TOKEN"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null:
		return false
	var t: MapToken = d.token(token_id)
	if t == null or to_level < 0 or to_level >= d.level_count() or not d.grid.in_bounds(to_cell):
		return false
	if t.cell == to_cell and t.level == to_level:
		return false
	_from_cell = t.cell
	_from_level = t.level
	t.cell = to_cell
	t.level = to_level
	d.deltas.append(MapDelta.make(DELTA_OP, {
		"token": token_id, "level": to_level, "x": to_cell.x, "y": to_cell.y, "cost": cost_ft}))
	_applied = true
	_counted_ft = cost_ft if d.turns.current_token_id() == token_id else 0
	d.turns.moved_ft += _counted_ft
	d.notify_changed(_from_level, MapDocument.LAYER_TOKENS)
	if to_level != _from_level:
		d.notify_changed(to_level, MapDocument.LAYER_TOKENS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	var t: MapToken = d.token(token_id)
	if t == null:
		return
	t.cell = _from_cell
	t.level = _from_level
	d.turns.moved_ft = maxi(0, d.turns.moved_ft - _counted_ft)
	_counted_ft = 0
	_remove_last_delta(d)
	_applied = false
	d.notify_changed(_from_level, MapDocument.LAYER_TOKENS)
	if to_level != _from_level:
		d.notify_changed(to_level, MapDocument.LAYER_TOKENS)


func _remove_last_delta(d: MapDocument) -> void:
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("token", -1) == token_id:
			d.deltas.remove_at(i)
			return
