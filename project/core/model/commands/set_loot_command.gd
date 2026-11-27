class_name SetLootCommand
extends MapCommand
## Cambia el contenido de un objeto (cofre, barril…) o el botín de una ficha
## (ADR 048): la lista entera y si los jugadores lo ven. Se deshace dejando
## lo de antes. El delta lleva la lista completa (se rehace igual, ADR 036).

const DELTA_OP: String = "set_loot"
const KIND_OBJECT: String = "object"
const KIND_TOKEN: String = "token"

var kind: String = KIND_OBJECT
## Nivel del objeto (las fichas no lo necesitan).
var level: int = 0
var target_id: int = -1
var items: Array[LootItem] = []
var revealed: bool = false
var _old_items: Array[LootItem] = []
var _old_revealed: bool = false
var _applied: bool = false


func _init(p_kind: String, p_level: int, p_id: int, p_items: Array[LootItem], p_revealed: bool) -> void:
	kind = p_kind
	level = p_level
	target_id = p_id
	items = LootItem.list_copy(p_items)
	revealed = p_revealed


static func for_object(p_level: int, object_id: int, p_items: Array[LootItem], p_revealed: bool) -> SetLootCommand:
	return SetLootCommand.new(KIND_OBJECT, p_level, object_id, p_items, p_revealed)


static func for_token(token_id: int, p_items: Array[LootItem], p_revealed: bool) -> SetLootCommand:
	return SetLootCommand.new(KIND_TOKEN, 0, token_id, p_items, p_revealed)


func label_key() -> String:
	return "CMD_SET_LOOT"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or items.size() > LootItem.MAX_ITEMS:
		return false
	var notify_level: int = level
	if kind == KIND_OBJECT:
		var lvl: MapLevel = d.level(level)
		var o: MapObject = lvl.object(target_id) if lvl != null else null
		if o == null:
			return false
		if LootItem.list_equals(o.contents, items) and o.contents_revealed == revealed:
			return false
		_old_items = o.contents
		_old_revealed = o.contents_revealed
		o.contents = LootItem.list_copy(items)
		o.contents_revealed = revealed
	elif kind == KIND_TOKEN:
		var t: MapToken = d.token(target_id)
		if t == null:
			return false
		if LootItem.list_equals(t.loot, items) and t.loot_revealed == revealed:
			return false
		_old_items = t.loot
		_old_revealed = t.loot_revealed
		t.loot = LootItem.list_copy(items)
		t.loot_revealed = revealed
		notify_level = t.level
	else:
		return false
	d.deltas.append(MapDelta.make(DELTA_OP, {"kind": kind, "level": level, "id": target_id,
		"items": LootItem.list_to_array(items), "revealed": revealed}))
	_applied = true
	d.notify_changed(notify_level, MapDocument.LAYER_OBJECTS if kind == KIND_OBJECT else MapDocument.LAYER_TOKENS)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	var notify_level: int = level
	if kind == KIND_OBJECT:
		var o: MapObject = d.level(level).object(target_id) if d.level(level) != null else null
		if o == null:
			return
		o.contents = _old_items
		o.contents_revealed = _old_revealed
	else:
		var t: MapToken = d.token(target_id)
		if t == null:
			return
		t.loot = _old_items
		t.loot_revealed = _old_revealed
		notify_level = t.level
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("kind", "") == kind and delta.data.get("id", -1) == target_id:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(notify_level, MapDocument.LAYER_OBJECTS if kind == KIND_OBJECT else MapDocument.LAYER_TOKENS)
