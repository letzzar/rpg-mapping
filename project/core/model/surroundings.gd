class_name Surroundings
extends RefCounted
## Entorno de un mapa (ADR 052): qué hay fuera de él y en sus zonas al aire
## libre, para pintar un fondo acorde (hierba, empedrado, tierra, arena,
## nieve, roca bajo tierra, agua) en lugar del vacío. Se deduce del mapa de
## arriba al entrar (MapNavigator): una casa toma lo que rodea su huella en la
## aldea (calle → empedrado, huerto → hierba); una aldea, el bioma de su
## casilla en la región; una mazmorra está bajo tierra. Solo es visual: no
## cambia el documento ni sus hashes.

const NONE: String = ""
const GRASS: String = "grass"
const COBBLE: String = "cobble"
const DIRT: String = "dirt"
const SAND: String = "sand"
const SNOW: String = "snow"
const ROCK: String = "rock"
const WATER: String = "water"
const KINDS: PackedStringArray = ["grass", "cobble", "dirt", "sand", "snow", "rock", "water"]

const COLORS: Dictionary[String, Color] = {
	"grass": Color("6f9e4c"),
	"cobble": Color("a39a8c"),
	"dirt": Color("8f6e4a"),
	"sand": Color("d6c08a"),
	"snow": Color("e8eef2"),
	"rock": Color("4a3a2e"),
	"water": Color("4f9fc4"),
}

## Zonas de asentamiento → entorno de lo que las pisa.
const ZONE_KINDS: Dictionary[String, String] = {
	"street": "cobble",
	"plaza": "cobble",
	"gate": "cobble",
	"bridge": "cobble",
	"town_wall": "cobble",
	"garden": "grass",
	"field": "grass",
	"yard": "dirt",
}


static func color(kind: String) -> Color:
	return COLORS.get(kind, Color("2b1d14"))


## ¿Al aire libre? (sin muro en el borde del mapa: se ve el entorno).
static func is_open(kind: String) -> bool:
	return kind != NONE and kind != ROCK


## Entorno de un mapa sin padre (generado directamente).
static func default_for(doc: MapDocument) -> String:
	if doc == null:
		return NONE
	var sc: SeedCode = SeedCode.parse(doc.seed_code)
	if not sc.is_valid():
		return NONE
	match sc.scale:
		"MAZ":
			return ROCK
		"ALD", "EDI":
			return GRASS
		_:
			return NONE


## Entorno del hijo `child` del nivel `level` de `parent` (cuyo entorno es
## `parent_kind`).
static func of_child(parent: MapDocument, parent_kind: String, level: int, child: MapChild) -> String:
	if child == null:
		return NONE
	var sc: SeedCode = SeedCode.parse(child.seed_code)
	if sc.is_valid() and sc.scale == "MAZ":
		return ROCK
	if parent == null or parent.level(level) == null:
		return default_for(null)
	var lvl: MapLevel = parent.level(level)
	# Región o mundo: el bioma de la casilla.
	if not lvl.biome.is_empty():
		var i: int = parent.grid.index_of(child.rect.position + child.rect.size / 2)
		if i >= 0 and i < lvl.biome.size():
			return of_biome(lvl.biome[i])
		return GRASS
	# Estancia de un edificio (mismo sitio, más cerca): sigue dentro.
	if sc.is_valid() and sc.scale == "EST":
		return NONE
	# Asentamiento: lo que rodea la huella (una casilla alrededor).
	var counts: Dictionary[String, int] = {}
	var g: GridGeometry = parent.grid
	var r: Rect2i = child.rect.grow(1)
	var kinds_by_room: Dictionary[int, String] = {}
	for room: MapRoom in lvl.rooms:
		kinds_by_room[room.id] = room.kind
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var c: Vector2i = Vector2i(x, y)
			if child.rect.has_point(c) or not g.in_bounds(c):
				continue
			var k: String = _cell_kind(lvl, c, kinds_by_room, parent_kind)
			if k != NONE:
				var prev: int = counts.get(k, 0)
				counts[k] = prev + 1
	var best: String = parent_kind if is_open(parent_kind) else GRASS
	var best_n: int = 0
	for k: String in KINDS:
		var n: int = counts.get(k, 0)
		if n > best_n:
			best_n = n
			best = k
	return best


static func _cell_kind(lvl: MapLevel, c: Vector2i, kinds_by_room: Dictionary[int, String], parent_kind: String) -> String:
	var t: int = lvl.get_terrain(c)
	if t == Terrain.WATER_SHALLOW or t == Terrain.WATER_DEEP:
		return WATER
	if t == Terrain.RUBBLE:
		return DIRT
	if t != Terrain.FLOOR:
		return NONE
	var room: String = kinds_by_room.get(lvl.room_ids[lvl.grid.index_of(c)], "")
	if ZONE_KINDS.has(room):
		return ZONE_KINDS[room]
	if room == MapRoom.KIND_BUILDING:
		return NONE
	return parent_kind if is_open(parent_kind) else GRASS


static func of_biome(b: int) -> String:
	match b:
		Biome.OCEAN, Biome.SHALLOW_SEA, Biome.LAKE:
			return WATER
		Biome.SEA_ICE, Biome.ICE, Biome.TUNDRA:
			return SNOW
		Biome.DESERT, Biome.COLD_DESERT:
			return SAND
		Biome.MOUNTAIN, Biome.SAVANNA, Biome.SHRUBLAND:
			return DIRT
		_:
			return GRASS
