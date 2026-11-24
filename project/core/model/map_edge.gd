class_name MapEdge
extends RefCounted
## Valor de una arista de MapLevel (ADR 018): muros finos, puertas y vanos.
##
## Un entero: los 4 bits bajos son el tipo (KIND_*) y los siguientes, banderas
## (FLAG_*). 0 = arista libre (no se guarda). Los valores entran en el hash:
## no renumerar; los tipos y banderas nuevos se añaden con valores nuevos.
##
## Bloqueo (lo que usan la ruta automática y la futura línea de visión):
##   tipo          movimiento y visión
##   WALL          siempre
##   DOOR          si está cerrada (con llave o sin ella)
##   SECRET_DOOR   si no está descubierta o está cerrada
##   ARCH (vano)   nunca
## Decisión de Víctor (ADR 020): cualquier puerta cerrada corta la ruta
## automática hasta que alguien la abra (un comando); FLAG_LOCKED solo indica
## que abrirla exige llave o prueba. La CONECTIVIDAD de un mapa generado
## (todas las salas accesibles) sí cuenta las puertas como franqueables:
## is_traversable().

const NONE: int = 0
const KIND_WALL: int = 1
const KIND_DOOR: int = 2
const KIND_SECRET_DOOR: int = 3
const KIND_ARCH: int = 4
const KIND_MASK: int = 0xF

const FLAG_OPEN: int = 0x10
const FLAG_LOCKED: int = 0x20
## Puerta secreta ya encontrada por los jugadores.
const FLAG_DISCOVERED: int = 0x40
const FLAGS_MASK: int = 0x70


static func make(edge_kind: int, flags: int = 0) -> int:
	return (edge_kind & KIND_MASK) | (flags & FLAGS_MASK)


static func kind_of(v: int) -> int:
	return v & KIND_MASK


static func has_flag(v: int, flag: int) -> bool:
	return (v & flag) != 0


## Devuelve `v` con `flag` puesta o quitada.
static func with_flag(v: int, flag: int, on: bool) -> int:
	return (v | flag) if on else (v & ~flag)


static func is_door(v: int) -> bool:
	var k: int = kind_of(v)
	return k == KIND_DOOR or k == KIND_SECRET_DOOR


## Valor que se puede guardar: tipo conocido, sin bits sobrantes, y banderas
## solo en puertas (FLAG_DISCOVERED solo en las secretas).
static func is_valid(v: int) -> bool:
	if v == NONE:
		return true
	if (v & ~(KIND_MASK | FLAGS_MASK)) != 0:
		return false
	var k: int = kind_of(v)
	if k < KIND_WALL or k > KIND_ARCH:
		return false
	if not is_door(v) and (v & FLAGS_MASK) != 0:
		return false
	if k == KIND_DOOR and has_flag(v, FLAG_DISCOVERED):
		return false
	return true


static func blocks_movement(v: int) -> bool:
	match kind_of(v):
		KIND_WALL:
			return true
		KIND_DOOR:
			return not has_flag(v, FLAG_OPEN)
		KIND_SECRET_DOOR:
			return not (has_flag(v, FLAG_DISCOVERED) and has_flag(v, FLAG_OPEN))
	return false


## Se puede llegar a cruzar (abriendo, forzando o encontrando la puerta): todo
## salvo un muro. Es el criterio de "sala accesible" de los generadores.
static func is_traversable(v: int) -> bool:
	return kind_of(v) != KIND_WALL


static func blocks_sight(v: int) -> bool:
	match kind_of(v):
		KIND_WALL:
			return true
		KIND_DOOR:
			return not has_flag(v, FLAG_OPEN)
		KIND_SECRET_DOOR:
			return not (has_flag(v, FLAG_DISCOVERED) and has_flag(v, FLAG_OPEN))
	return false
