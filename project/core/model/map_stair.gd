class_name MapStair
extends RefCounted
## Escalera (o trampilla, pozo…) que comunica una casilla de un nivel con una
## casilla de otro. Sube si to_level > nivel propio; baja si es menor.

var id: int = 0
var cell: Vector2i = Vector2i.ZERO
## Índice del nivel de destino en MapDocument.levels.
var to_level: int = 0
var to_cell: Vector2i = Vector2i.ZERO
## Dirección con arista hacia la que se sube (para dibujarla).
var facing: int = 0


func copy() -> MapStair:
	var s: MapStair = MapStair.new()
	s.id = id
	s.cell = cell
	s.to_level = to_level
	s.to_cell = to_cell
	s.facing = facing
	return s


func to_dict() -> Dictionary:
	return {
		"id": id,
		"cell": [cell.x, cell.y],
		"to_level": to_level,
		"to_cell": [to_cell.x, to_cell.y],
		"facing": facing,
	}


static func from_dict(r: JsonReader, d: Dictionary) -> MapStair:
	var s: MapStair = MapStair.new()
	s.id = r.get_int(d, "id")
	s.cell = r.get_vec2i(d, "cell")
	s.to_level = r.get_int(d, "to_level")
	s.to_cell = r.get_vec2i(d, "to_cell")
	s.facing = r.get_int(d, "facing")
	return s
