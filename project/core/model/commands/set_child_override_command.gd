class_name SetChildOverrideCommand
extends MapCommand
## Sustituye un hijo de este mapa (edificio de una aldea, estancia de un
## edificio) por una estancia propia, o vuelve al generado con `seed_code`
## vacío (E4, ADR 040). El delta lleva la estancia entera (código base +
## deltas de contenido): el guardado del mapa padre la contiene.

const DELTA_OP: String = "set_child_override"

var child_id: int = 0
## Código base de la estancia ("" = quitar la sustitución).
var seed_code: String = ""
var deltas: Array[MapDelta] = []
var _old: Dictionary = {}
var _had: bool = false
var _applied: bool = false


func _init(p_child_id: int, p_seed_code: String, p_deltas: Array[MapDelta] = []) -> void:
	child_id = p_child_id
	seed_code = p_seed_code
	for dl: MapDelta in p_deltas:
		deltas.append(dl.copy())


func label_key() -> String:
	return "CMD_SET_CHILD_OVERRIDE" if not seed_code.is_empty() else "CMD_CLEAR_CHILD_OVERRIDE"


## Lo que se guarda en MapDocument.child_overrides.
func entry() -> Dictionary:
	var list: Array = []
	for dl: MapDelta in deltas:
		list.append(dl.to_dict())
	return {"seed_code": seed_code, "deltas": list}


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null:
		return false
	_had = d.child_overrides.has(child_id)
	if seed_code.is_empty() and not _had:
		return false
	var e: Dictionary = entry()
	if _had and CanonicalJson.stringify(d.child_overrides[child_id]) == CanonicalJson.stringify(e):
		return false
	_old = d.child_overrides[child_id].duplicate(true) if _had else {}
	if seed_code.is_empty():
		d.child_overrides.erase(child_id)
	else:
		d.child_overrides[child_id] = e
	var data: Dictionary = e.duplicate(true)
	data["child"] = child_id
	d.deltas.append(MapDelta.make(DELTA_OP, data))
	_applied = true
	d.notify_changed(-1, MapDocument.LAYER_ALL)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or not _applied:
		return
	if _had:
		d.child_overrides[child_id] = _old
	else:
		d.child_overrides.erase(child_id)
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var dl: MapDelta = d.deltas[i]
		if dl.op == DELTA_OP and dl.data.get("child", -1) == child_id:
			d.deltas.remove_at(i)
			break
	_applied = false
	d.notify_changed(-1, MapDocument.LAYER_ALL)


## Estancia de una entrada de MapDocument.child_overrides: código y deltas.
static func override_deltas(e: Dictionary) -> Array[MapDelta]:
	var out: Array[MapDelta] = []
	var list: Array = e.get("deltas", [])
	for v: Variant in list:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var dd: Dictionary = v
		var data: Dictionary = dd.get("data", {})
		out.append(MapDelta.make(str(dd.get("op", "")), data))
	return out
