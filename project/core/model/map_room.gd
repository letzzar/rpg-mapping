class_name MapRoom
extends RefCounted
## Sala o zona de un nivel. Sus casillas están en la capa MapLevel.room_ids
## (cada casilla pertenece como mucho a una zona); usar MapLevel.room_cells().

## Ids de tipo habituales (texto libre [a-z0-9_]; nombre visible por i18n
## "ROOM_KIND_" + kind.to_upper()).
const KIND_ROOM: String = "room"
const KIND_CORRIDOR: String = "corridor"
const KIND_CAVE: String = "cave"
## Casilla del borde del mapa por la que se entra a la mazmorra (una).
const KIND_ENTRANCE: String = "entrance"
## Otras salidas al exterior (casilla del borde).
const KIND_EXIT: String = "exit"
## Terreno exterior alrededor de un edificio (EDI, F3).
const KIND_OUTSIDE: String = "outside"
## Zonas de un asentamiento (ALD G1, F3, ADR 027). Todas al aire libre salvo
## la huella del edificio (KIND_BUILDING) y la muralla (terreno WALL).
const KIND_STREET: String = "street"
const KIND_PLAZA: String = "plaza"
const KIND_BRIDGE: String = "bridge"
## Hueco de la muralla por donde pasa una calle principal.
const KIND_GATE: String = "gate"
const KIND_TOWN_WALL: String = "town_wall"
## Parcela de un edificio sin la huella (anillo de 1 casilla + patio).
const KIND_YARD: String = "yard"
const KIND_BUILDING: String = "building"
## Terreno libre dentro del asentamiento (huertos) y fuera de él (campos).
const KIND_GARDEN: String = "garden"
const KIND_FIELD: String = "field"
## Zonas al aire libre (las vistas no les ponen techo y usan su color).
const OUTDOOR_KINDS: PackedStringArray = [
	"outside", "street", "plaza", "bridge", "gate", "yard", "garden", "field",
]

## Id estable (único en todo el documento, de MapDocument.allocate_id()).
var id: int = 0
var kind: String = KIND_ROOM
## Nombre puesto por el DM ("" = sin nombre; la vista muestra uno por defecto).
var label: String = ""


static func make(p_id: int, p_kind: String, p_label: String = "") -> MapRoom:
	var r: MapRoom = MapRoom.new()
	r.id = p_id
	r.kind = p_kind
	r.label = p_label
	return r


func copy() -> MapRoom:
	return MapRoom.make(id, kind, label)


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "label": label}


static func from_dict(r: JsonReader, d: Dictionary) -> MapRoom:
	return MapRoom.make(r.get_int(d, "id"), r.get_str(d, "kind"), r.get_str(d, "label"))
