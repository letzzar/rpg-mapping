class_name MapChild
extends RefCounted
## Mapa hijo anclado en un nivel (F3, ALD G1, ADR 027): un edificio de un
## asentamiento y, más adelante, una estancia de un edificio o un asentamiento
## de una región. Lo usa la navegación jerárquica (aldea → edificio → estancia)
## para abrir el hijo desde su código y situar la ficha en la casilla
## equivalente.
##
## Correspondencia de casillas: la casilla `c` del nivel `child_level` del
## mapa hijo está en la casilla `c + offset` de este nivel. Solo es una
## traslación (sin giro ni escala): el padre se diseña para que el hijo encaje
## 1:1 (en hex, `offset` respeta la paridad de la rejilla offset).
##
## Es contenido generado (entra en content_hash()), con id del contador único
## del documento.

var id: int = 0
## Tipo del hijo (en un edificio, el building_type de EDI; nombre visible por
## i18n "BUILDING_" + kind.to_upper()).
var kind: String = ""
## Código RPGM1 canónico que regenera el hijo.
var seed_code: String = ""
## Zona (MapRoom) de este nivel que ocupa su huella.
var room_id: int = 0
## Casilla de este nivel que corresponde a la (0, 0) del hijo.
var offset: Vector2i = Vector2i.ZERO
## Nivel del hijo que coincide con este (planta baja de un edificio: 1 si
## tiene sótano, 0 si no).
var child_level: int = 0
## Huella en casillas de este nivel.
var rect: Rect2i = Rect2i()
## Casilla de este nivel delante de la puerta principal (fuera de la huella).
var entrance: Vector2i = Vector2i.ZERO


func copy() -> MapChild:
	var c: MapChild = MapChild.new()
	c.id = id
	c.kind = kind
	c.seed_code = seed_code
	c.room_id = room_id
	c.offset = offset
	c.child_level = child_level
	c.rect = rect
	c.entrance = entrance
	return c


## Casilla del hijo (en child_level) que corresponde a `cell` de este nivel.
func to_child_cell(cell: Vector2i) -> Vector2i:
	return cell - offset


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"seed_code": seed_code,
		"room_id": room_id,
		"offset": [offset.x, offset.y],
		"child_level": child_level,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"entrance": [entrance.x, entrance.y],
	}


static func from_dict(r: JsonReader, d: Dictionary) -> MapChild:
	var c: MapChild = MapChild.new()
	c.id = r.get_int(d, "id")
	c.kind = r.get_str(d, "kind")
	c.seed_code = r.get_str(d, "seed_code")
	c.room_id = r.get_int(d, "room_id")
	c.offset = r.get_vec2i(d, "offset")
	c.child_level = r.get_int(d, "child_level")
	var rc: PackedInt32Array = r.get_ints(d, "rect")
	if rc.size() != 4:
		r.fail("'rect' debe ser [x, y, ancho, alto]")
	else:
		c.rect = Rect2i(rc[0], rc[1], rc[2], rc[3])
	c.entrance = r.get_vec2i(d, "entrance")
	return c
