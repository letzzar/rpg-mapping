class_name SetTokenSheetCommand
extends MapCommand
## Pone (o quita, con null) el personaje de una ficha (ADR 034). La ficha
## toma su nombre (si no está vacío) y su tamaño, así que ocupa las casillas
## que le tocan y se mueve con su velocidad. Se deshace dejando la ficha como
## estaba.

const DELTA_OP: String = "set_token_sheet"

var token_id: int = -1
var sheet: CharacterSheet = null
var _old_sheet: CharacterSheet = null
var _old_name: String = ""
var _old_size: String = ""
var _applied: bool = false


func _init(p_token_id: int, p_sheet: CharacterSheet) -> void:
	token_id = p_token_id
	sheet = p_sheet.copy() if p_sheet != null else null


func label_key() -> String:
	return "CMD_SET_TOKEN_SHEET"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null:
		return false
	var t: MapToken = d.token(token_id)
	if t == null:
		return false
	if sheet == null and t.sheet == null:
		return false
	if sheet != null and sheet.equals(t.sheet) and t.size_id == sheet.size_id \
			and (sheet.name.is_empty() or t.name == sheet.name):
		return false
	_old_sheet = t.sheet
	_old_name = t.name
	_old_size = t.size_id
	t.sheet = sheet.copy() if sheet != null else null
	if sheet != null:
		if not sheet.name.is_empty():
			t.name = sheet.name
		t.size_id = sheet.size_id
	d.deltas.append(MapDelta.make(DELTA_OP, {"token": token_id, "name": t.name, "size_id": t.size_id}))
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
	t.sheet = _old_sheet
	t.name = _old_name
	t.size_id = _old_size
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("token", -1) == token_id:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(t.level, MapDocument.LAYER_TOKENS)
