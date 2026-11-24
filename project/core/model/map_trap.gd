class_name MapTrap
extends RefCounted
## Trampa en una casilla. Las reglas (CD, daño) no van aquí: dependen del
## sistema y del contenido con licencia; `trap_id` remite a un paquete.

var id: int = 0
var cell: Vector2i = Vector2i.ZERO
## Id del tipo de trampa (paquete de contenido; p. ej. "pit_hidden").
var trap_id: String = ""
## Oculta a los jugadores (solo la ve el DM).
var hidden: bool = true
## Armada (false = desactivada o ya disparada).
var armed: bool = true


func copy() -> MapTrap:
	var t: MapTrap = MapTrap.new()
	t.id = id
	t.cell = cell
	t.trap_id = trap_id
	t.hidden = hidden
	t.armed = armed
	return t


func to_dict() -> Dictionary:
	return {"id": id, "cell": [cell.x, cell.y], "trap_id": trap_id, "hidden": hidden, "armed": armed}


static func from_dict(r: JsonReader, d: Dictionary) -> MapTrap:
	var t: MapTrap = MapTrap.new()
	t.id = r.get_int(d, "id")
	t.cell = r.get_vec2i(d, "cell")
	t.trap_id = r.get_str(d, "trap_id")
	t.hidden = r.get_bool(d, "hidden")
	t.armed = r.get_bool(d, "armed")
	return t
