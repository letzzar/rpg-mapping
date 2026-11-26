class_name Biome
extends RefCounted
## Biomas de las capas de mundo y región (F6, MUN G1 y REG G1/G2): un byte
## por casilla en MapLevel.biome.
##
## Los valores se guardan en el documento y entran en el hash: NO renumerar
## ni reutilizar; para uno nuevo, añadirlo AL FINAL (y subir GEN de los
## generadores que lo empiecen a usar). Nombre visible: clave i18n
## "BIOME_" + IDS[b].to_upper().
##
## Clasificación (Whittaker simplificado): temperatura media anual en °C y
## precipitación como índice 0..100 (classify()). Las montañas y el hielo se
## deciden antes por altura y temperatura.

const OCEAN: int = 0
## Plataforma continental (agua poco profunda junto a la costa).
const SHALLOW_SEA: int = 1
const LAKE: int = 2
## Mar helado (banquisa).
const SEA_ICE: int = 3
## Casquete o glaciar sobre tierra (y cumbres nevadas).
const ICE: int = 4
const TUNDRA: int = 5
## Bosque boreal.
const TAIGA: int = 6
## Estepa / desierto frío.
const COLD_DESERT: int = 7
const GRASSLAND: int = 8
## Matorral mediterráneo.
const SHRUBLAND: int = 9
const TEMPERATE_FOREST: int = 10
const TEMPERATE_RAINFOREST: int = 11
const DESERT: int = 12
const SAVANNA: int = 13
## Bosque tropical estacional.
const TROPICAL_FOREST: int = 14
## Selva tropical.
const RAINFOREST: int = 15
## Pantano / humedal.
const WETLAND: int = 16
## Alta montaña (roca, pastos alpinos).
const MOUNTAIN: int = 17
const COUNT: int = 18
const IDS: PackedStringArray = [
	"ocean", "shallow_sea", "lake", "sea_ice", "ice", "tundra", "taiga", "cold_desert",
	"grassland", "shrubland", "temperate_forest", "temperate_rainforest", "desert",
	"savanna", "tropical_forest", "rainforest", "wetland", "mountain",
]

## Bandas de temperatura de classify() (límite inferior, °C).
const T_ICE: int = -10
const T_TUNDRA: int = 0
const T_BOREAL: int = 7
const T_TROPICAL: int = 20


static func is_valid(b: int) -> bool:
	return b >= 0 and b < COUNT


## Agua (océano, plataforma, lago o banquisa).
static func is_water(b: int) -> bool:
	return b == OCEAN or b == SHALLOW_SEA or b == LAKE or b == SEA_ICE


## Mar abierto (no lago).
static func is_sea(b: int) -> bool:
	return b == OCEAN or b == SHALLOW_SEA or b == SEA_ICE


static func is_forest(b: int) -> bool:
	return b == TAIGA or b == TEMPERATE_FOREST or b == TEMPERATE_RAINFOREST or b == TROPICAL_FOREST or b == RAINFOREST


## Bioma de tierra por temperatura media (°C) y precipitación (0..100), sin
## montaña (la decide la altura). Tabla de Whittaker simplificada.
static func classify(temp_c: int, precip: int) -> int:
	if temp_c < T_ICE:
		return ICE
	if temp_c < T_TUNDRA:
		return TUNDRA
	if temp_c < T_BOREAL:
		return COLD_DESERT if precip < 18 else TAIGA
	if temp_c < T_TROPICAL:
		if precip < 14:
			return COLD_DESERT
		if precip < 32:
			return GRASSLAND
		if precip < 44:
			return SHRUBLAND
		if precip < 78:
			return TEMPERATE_FOREST
		return TEMPERATE_RAINFOREST
	if precip < 16:
		return DESERT
	if precip < 38:
		return SAVANNA
	if precip < 66:
		return TROPICAL_FOREST
	return RAINFOREST
