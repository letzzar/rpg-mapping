class_name GeoLayers
extends RefCounted
## Capas geográficas de MapLevel para mundo y región (F6): significado de los
## bytes de MapLevel.elevation y MapLevel.features (el de MapLevel.biome está
## en Biome). Se serializan solo si no están vacías, así que los documentos
## de las otras escalas no cambian.
##
## ELEVACIÓN (1 byte por casilla, cuantizada; el nivel del mar es fijo):
##   e < SEA_LEVEL  : agua; profundidad = (SEA_LEVEL − e) × OCEAN_STEP_M m.
##   e >= SEA_LEVEL : tierra; altitud = (e − SEA_LEVEL) × LAND_STEP_M m
##                    (0 .. 7 640 m).
## El parámetro "% de tierra" de MUN decide qué parte queda por encima: no hay
## parámetro de nivel del mar aparte (serían dos formas de decir lo mismo).
##
## RASGOS (1 byte por casilla, bits):
##   bits 0-1  RIVER_MASK  clase de río: 0 ninguno, 1 arroyo, 2 río, 3 gran río.
##   bit 2     ROAD        camino.
##   bit 3     COAST       tierra junto al mar (4 vecinos en la cuadrada, 6 en hex).
##   bits 4-7  FLOW        dirección de la corriente + 1 (0 = sin río): índice
##                         de dirección de la rejilla del documento (0-7 en la
##                         cuadrada, 0-5 en hex; GridGeometry.neighbor).
## Las fronteras de reinos no se guardan: son los cambios de MapLevel.room_ids
## (una zona MapRoom de tipo "kingdom" por reino).

const SEA_LEVEL: int = 64
const LAND_STEP_M: int = 40
const OCEAN_STEP_M: int = 100
## Desde aquí la tierra es "montaña" para el bioma (2 000 m).
const MOUNTAIN_E: int = SEA_LEVEL + 50
## Colinas (800 m): coste de viaje mayor, sin cambiar el bioma.
const HILLS_E: int = SEA_LEVEL + 20

const RIVER_MASK: int = 0x03
const ROAD: int = 0x04
const COAST: int = 0x08
const FLOW_SHIFT: int = 4
const FLOW_MASK: int = 0xF0


static func is_land(e: int) -> bool:
	return e >= SEA_LEVEL


## Altitud (positiva) o profundidad (negativa) en metros.
static func meters(e: int) -> int:
	if e >= SEA_LEVEL:
		return (e - SEA_LEVEL) * LAND_STEP_M
	return (e - SEA_LEVEL) * OCEAN_STEP_M


static func river_class(f: int) -> int:
	return f & RIVER_MASK


static func has_road(f: int) -> bool:
	return (f & ROAD) != 0


static func is_coast(f: int) -> bool:
	return (f & COAST) != 0


## Dirección de la corriente (índice de dirección de la rejilla) o -1.
static func flow_dir(f: int) -> int:
	return ((f & FLOW_MASK) >> FLOW_SHIFT) - 1


## Byte de río con su clase (1..3) y dirección (o -1), conservando el resto.
static func with_river(f: int, river: int, dir: int) -> int:
	var out: int = (f & ~(RIVER_MASK | FLOW_MASK)) & 0xFF
	return out | (river & RIVER_MASK) | (((dir + 1) & 0xF) << FLOW_SHIFT)
