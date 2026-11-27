class_name LootItem
extends RefCounted
## Una línea del contenido de un contenedor (cofre, barril, estantería…) o
## del botín de una ficha (enemigo, PNJ), ADR 048. Texto libre: el programa
## no trae listas de objetos de reglas (licencias, §6 de CLAUDE.md); el DM
## escribe lo que quiera ("Monedas de oro" × 120, "Poción de curación").

const MAX_NAME: int = 120
const MAX_TEXT: int = 200
const MAX_QTY: int = 999999
## Máximo de líneas por contenedor o ficha (tamaño de los mensajes de red).
const MAX_ITEMS: int = 200

var name: String = ""
var qty: int = 1
## Valor como texto ("50 po", "3 gp"): cada sistema y mesa lo cuenta a su modo.
var value: String = ""
var note: String = ""


static func make(p_name: String, p_qty: int = 1, p_value: String = "", p_note: String = "") -> LootItem:
	var it: LootItem = LootItem.new()
	it.name = p_name.strip_edges().left(MAX_NAME)
	it.qty = clampi(p_qty, 1, MAX_QTY)
	it.value = p_value.strip_edges().left(MAX_TEXT)
	it.note = p_note.strip_edges().left(MAX_TEXT)
	return it


func copy() -> LootItem:
	return make(name, qty, value, note)


func equals(o: LootItem) -> bool:
	return o != null and o.name == name and o.qty == qty and o.value == value and o.note == note


func to_dict() -> Dictionary:
	var d: Dictionary = {"name": name, "qty": qty}
	if not value.is_empty():
		d["value"] = value
	if not note.is_empty():
		d["note"] = note
	return d


static func from_dict(r: JsonReader, d: Dictionary) -> LootItem:
	var it: LootItem = make(r.get_str(d, "name"), r.get_int(d, "qty"),
		str(d.get("value", "")), str(d.get("note", "")))
	if it.name.is_empty():
		r.fail("objeto del botín sin nombre")
	return it


# --- Listas -------------------------------------------------------------------

static func list_to_array(items: Array[LootItem]) -> Array:
	var out: Array = []
	for it: LootItem in items:
		out.append(it.to_dict())
	return out


static func list_from_array(r: JsonReader, arr: Array) -> Array[LootItem]:
	var out: Array[LootItem] = []
	for v: Variant in arr:
		if out.size() >= MAX_ITEMS:
			r.fail("demasiados objetos en el botín")
			break
		out.append(from_dict(r, r.to_dict(v, "loot")))
	return out


static func list_copy(items: Array[LootItem]) -> Array[LootItem]:
	var out: Array[LootItem] = []
	for it: LootItem in items:
		out.append(it.copy())
	return out


static func list_equals(a: Array[LootItem], b: Array[LootItem]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if not a[i].equals(b[i]):
			return false
	return true
