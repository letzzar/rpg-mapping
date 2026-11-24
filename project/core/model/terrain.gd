class_name Terrain
extends RefCounted
## Tipos de terreno de la capa por casilla de MapLevel (un byte por casilla).
##
## Los valores se guardan en el documento y entran en el hash: NO renumerar ni
## reutilizar; para un tipo nuevo, añadir un valor al final (y subir GEN de los
## generadores que lo empiecen a usar). Las propiedades no dependen del
## sistema de juego (lo que cuesta el terreno difícil sí: SystemProfile).
## Nombres visibles: clave i18n "TERRAIN_" + IDS[t].to_upper().

## Sin excavar / fuera del mapa útil (roca maciza en una mazmorra).
const VOID: int = 0
const FLOOR: int = 1
## Muro macizo que ocupa la casilla (muro grueso, columna). Los muros finos y
## las puertas van en las aristas (MapEdge, ADR 018).
const WALL: int = 2
## Escombros: suelo con terreno difícil.
const RUBBLE: int = 3
const WATER_SHALLOW: int = 4
const WATER_DEEP: int = 5
## Sima o foso: no se puede pisar andando.
const PIT: int = 6
const COUNT: int = 7
const IDS: PackedStringArray = ["void", "floor", "wall", "rubble", "water_shallow", "water_deep", "pit"]


static func is_valid(t: int) -> bool:
	return t >= 0 and t < COUNT


## Se puede entrar andando.
static func is_passable(t: int) -> bool:
	return t == FLOOR or t == RUBBLE or t == WATER_SHALLOW or t == WATER_DEEP


## Cuenta como terreno difícil (el coste extra sale del perfil del sistema).
static func is_difficult(t: int) -> bool:
	return t == RUBBLE or t == WATER_SHALLOW or t == WATER_DEEP


## Bloquea la línea de visión.
static func blocks_sight(t: int) -> bool:
	return t == VOID or t == WALL


## Macizo (en 3D se extruye hasta la altura de muro).
static func is_solid(t: int) -> bool:
	return t == VOID or t == WALL
