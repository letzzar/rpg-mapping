extends GutTest
## Tests de core/rules: perfiles de data/systems y coste de movimiento.

const D: int = MovementCost.STEP_DIAGONAL
const T: int = MovementCost.STEP_DIFFICULT


func _profile(id: String) -> SystemProfile:
	var p: SystemProfile = SystemProfile.load_id(id)
	assert_true(p.is_valid(), p.error)
	return p


func test_all_profiles_load_and_have_unique_seed_codes() -> void:
	var ids: PackedStringArray = SystemProfile.available_ids()
	assert_eq(ids, PackedStringArray(["dnd5e_2024", "pf2e"]))
	var codes: Dictionary[String, String] = {}
	for id: String in ids:
		var p: SystemProfile = _profile(id)
		assert_eq(p.id, id)
		assert_false(codes.has(p.seed_code), "seed_code repetido: " + p.seed_code)
		codes[p.seed_code] = id
		# El código del perfil debe ser aceptado por el formato RPGM1.
		assert_true(SeedCode.is_system_code(p.seed_code), p.seed_code)
		assert_false(p.license.is_empty())


func test_dnd5e_movement() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	assert_eq(p.default_speed_ft, 30)
	# 3 diagonales a 5 ft cada una.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([D, D, D])), 15)
	# Variante opcional 5/10/5.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([D, D, D]), "alternate_5_10"), 20)
	# Terreno difícil ×2.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([0, T, D | T])), 25)
	assert_eq(p.size_space_ft_x10["tiny"], 25)


func test_pf2e_movement() -> void:
	var p: SystemProfile = _profile("pf2e")
	assert_eq(p.default_speed_ft, 25)
	# Diagonales alternas 5/10/5/10.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([D, D, D, D])), 30)
	# Difícil +5 por casilla; la alternancia continúa: 5+5, luego 10+5.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([D | T, D | T])), 25)
	# Los pasos ortogonales no rompen la alternancia.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([D, 0, D])), 20)


## Perfil derivado de dnd5e_2024.json con los cambios de `mutate` (recibe el
## diccionario raíz). Se escribe en user:// y se carga como cualquier perfil.
func _custom_profile(mutate: Callable) -> SystemProfile:
	var p: SystemProfile = _load_mutated(mutate)
	assert_true(p.is_valid(), p.error)
	return p


## Como _custom_profile() pero sin exigir que sea válido.
func _load_mutated(mutate: Callable) -> SystemProfile:
	var src: String = FileAccess.get_file_as_string(SystemProfile.DIR + "dnd5e_2024.json")
	var root: Dictionary = JSON.parse_string(src)
	mutate.call(root)
	var path: String = "user://perfil_prueba.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(root))
	f.close()
	var p: SystemProfile = SystemProfile.load_path(path)
	DirAccess.remove_absolute(path)
	return p


## Perfil de prueba con bandas genéricas (no corresponde a ningún sistema
## publicado: el mecanismo de bandas se mantiene para perfiles propios, ADR 011).
func _bands_profile() -> SystemProfile:
	return _custom_profile(func(root: Dictionary) -> void:
		root["id"] = "test_bands"
		root["seed_code"] = "TBND"
		var grid: Dictionary = root["grid"]
		grid["measure"] = "bands"
		var movement: Dictionary = root["movement"]
		var terrain: Dictionary = movement["difficult_terrain"]
		terrain["visual_only"] = true
		root["sizes_occupy_cells"] = false
		root["range_bands"] = [
			{"id": "adjacent", "max_cells": 1},
			{"id": "near", "max_cells": 6},
			{"id": "far", "max_cells": 12},
			{"id": "beyond", "max_cells": -1},
		]
	)


func test_bands_and_visual_terrain() -> void:
	var p: SystemProfile = _bands_profile()
	assert_eq(p.measure, "bands")
	assert_false(p.sizes_occupy_cells)
	assert_eq(p.band_for_cells(1), "adjacent")
	assert_eq(p.band_for_cells(2), "near")
	assert_eq(p.band_for_cells(6), "near")
	assert_eq(p.band_for_cells(12), "far")
	assert_eq(p.band_for_cells(13), "beyond")
	assert_eq(p.band_for_cells(500), "beyond")
	# Terreno difícil solo visual: no cambia el coste.
	assert_eq(MovementCost.path_cost_ft(p, PackedInt32Array([T, T])), 10)


func test_grid_systems_have_no_bands() -> void:
	assert_eq(_profile("dnd5e_2024").band_for_cells(3), "")


func test_invalid_profiles_are_rejected() -> void:
	assert_false(SystemProfile.load_id("no_existe").is_valid())
	var path: String = "user://perfil_malo.json"
	var src: String = FileAccess.get_file_as_string(SystemProfile.DIR + "dnd5e_2024.json")
	assert_string_contains(src, '"cell_ft": 5,')
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(src.replace('"cell_ft": 5,', '"cell_ft": 2.5,'))
	f.close()
	var p: SystemProfile = SystemProfile.load_path(path)
	assert_false(p.is_valid())
	assert_string_contains(p.error, "cell_ft")
	DirAccess.remove_absolute(path)
	var no_hex: SystemProfile = _load_mutated(func(root: Dictionary) -> void:
		var mv: Dictionary = root["movement"]
		mv.erase("hex_step_ft")
	)
	assert_false(no_hex.is_valid())
	assert_string_contains(no_hex.error, "hex_step_ft")
	var bad_corner: SystemProfile = _load_mutated(func(root: Dictionary) -> void:
		var mv: Dictionary = root["movement"]
		mv["diagonal_corner_rule"] = "never"
	)
	assert_false(bad_corner.is_valid())
	assert_string_contains(bad_corner.error, "diagonal_corner_rule")


# --- F1: rejillas, rutas y bandas (criterio de aceptación de F1: movimiento
# correcto en los 2 sistemas y en un perfil de bandas, en ambas rejillas) ----

const H: int = MovementCost.STEP_HEX
const SQUARE: String = GridGeometry.KIND_SQUARE
const HEX_KINDS: PackedStringArray = ["hex_flat", "hex_pointy"]


## Nivel w×h todo suelo.
func _open_level(kind: String, w: int, h: int) -> MapLevel:
	var doc: MapDocument = MapDocument.create(kind, w, h)
	assert_not_null(doc)
	var l: MapLevel = doc.level(0)
	l.fill_terrain(Terrain.FLOOR)
	return l


## Los tres perfiles del criterio de aceptación.
func _three_profiles() -> Array[SystemProfile]:
	var out: Array[SystemProfile] = [_profile("dnd5e_2024"), _profile("pf2e"), _bands_profile()]
	return out


func _strip(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in n:
		out.append(Vector2i(x, 0))
	return out


func test_profile_patterns_sizes_and_lookup() -> void:
	var dnd: SystemProfile = _profile("dnd5e_2024")
	assert_eq(dnd.step_pattern(GridGeometry.STEP_ORTHOGONAL), PackedInt32Array([5]))
	assert_eq(dnd.step_pattern(GridGeometry.STEP_DIAGONAL), PackedInt32Array([5]))
	assert_eq(dnd.step_pattern(GridGeometry.STEP_DIAGONAL, "alternate_5_10"), PackedInt32Array([5, 10]))
	assert_eq(dnd.step_pattern(GridGeometry.STEP_HEX), PackedInt32Array([5]))
	assert_eq(dnd.diagonal_corner_rule, SystemProfile.CORNER_ANY_SIDE_FREE)
	assert_eq(_profile("pf2e").step_pattern(GridGeometry.STEP_DIAGONAL), PackedInt32Array([5, 10]))
	assert_eq(dnd.size_cells("tiny"), 1)
	assert_eq(dnd.size_cells("medium"), 1)
	assert_eq(dnd.size_cells("large"), 2)
	assert_eq(dnd.size_cells("huge"), 3)
	assert_eq(dnd.size_cells("gargantuan"), 4)
	assert_eq(dnd.size_cells("no_existe"), 1)
	assert_eq(_bands_profile().size_cells("huge"), 1)
	var pf: SystemProfile = SystemProfile.find_by_seed_code("PF2E")
	assert_not_null(pf)
	if pf != null:
		assert_eq(pf.id, "pf2e")
	assert_null(SystemProfile.find_by_seed_code("ZZZZ"))


func test_step_flags() -> void:
	assert_eq(MovementCost.step_flags(GridGeometry.STEP_HEX, true), H | T)
	assert_eq(MovementCost.step_flags(GridGeometry.STEP_DIAGONAL, false), D)
	assert_eq(MovementCost.step_flags(GridGeometry.STEP_ORTHOGONAL, true), T)
	assert_eq(MovementCost.step_kind_of(D | T), GridGeometry.STEP_DIAGONAL)
	assert_eq(MovementCost.step_kind_of(H), GridGeometry.STEP_HEX)
	assert_eq(MovementCost.step_kind_of(T), GridGeometry.STEP_ORTHOGONAL)
	# Hex: 5 + entrar en difícil (5e ×2 = 10; PF2e 5+5 = 10).
	assert_eq(MovementCost.path_cost_ft(_profile("dnd5e_2024"), PackedInt32Array([H, H | T])), 15)
	assert_eq(MovementCost.path_cost_ft(_profile("pf2e"), PackedInt32Array([H, H | T])), 15)
	# Los pasos hex no consumen la alternancia diagonal ni al revés.
	assert_eq(MovementCost.path_cost_ft(_profile("pf2e"), PackedInt32Array([D, H, D])), 20)


## Medición recta: [5e, PF2e, bandas] en las tres rejillas.
func test_measure_all_grids_and_systems() -> void:
	var profiles: Array[SystemProfile] = _three_profiles()
	var sq: GridGeometry = GridFactory.create(SQUARE, 20, 20)
	var cases: Array = [
		# [a, b, [5e, PF2e, bandas]]
		[Vector2i(0, 0), Vector2i(3, 3), [15, 20, 15]],
		[Vector2i(0, 0), Vector2i(4, 2), [20, 25, 20]],
		[Vector2i(5, 5), Vector2i(5, 0), [25, 25, 25]],
	]
	for c: Array in cases:
		var a: Vector2i = c[0]
		var b: Vector2i = c[1]
		var expected: Array = c[2]
		for i: int in profiles.size():
			var want: int = expected[i]
			assert_eq(MovementCost.measure_ft(profiles[i], sq, a, b), want, "%s %s-%s" % [profiles[i].id, a, b])
	assert_eq(MovementCost.measure_ft(profiles[0], sq, Vector2i(0, 0), Vector2i(3, 3), "alternate_5_10"), 20)
	for k: String in HEX_KINDS:
		var hx: GridGeometry = GridFactory.create(k, 20, 20)
		for p: SystemProfile in profiles:
			assert_eq(MovementCost.measure_ft(p, hx, Vector2i(0, 0), Vector2i(4, 0)), 20, "%s %s" % [p.id, k])
			assert_eq(MovementCost.measure_ft(p, hx, Vector2i(3, 3), Vector2i(3, 3)), 0)
	# Bandas a partir de la medida.
	var bands: SystemProfile = profiles[2]
	assert_eq(MovementCost.band_for_ft(bands, 5), "adjacent")
	assert_eq(MovementCost.band_for_ft(bands, 20), "near")
	assert_eq(MovementCost.band_for_ft(bands, MovementCost.measure_ft(bands, sq, Vector2i(0, 0), Vector2i(13, 2))), "beyond")
	assert_eq(MovementCost.band_for_ft(profiles[0], 20), "")
	assert_eq(MovementCost.ft_to_cells(bands, 12), 3)


## Ruta por una franja de 5 casillas con escombros en la central, en las tres
## rejillas (en hex_flat la fila 0 es un zigzag de vecinos).
func test_route_with_difficult_terrain_all_grids() -> void:
	var profiles: Array[SystemProfile] = _three_profiles()
	var expected: PackedInt32Array = PackedInt32Array([25, 25, 20])
	for k: String in GridGeometry.KINDS:
		var l: MapLevel = _open_level(k, 5, 1)
		l.set_terrain(Vector2i(2, 0), Terrain.RUBBLE)
		var path: Array[Vector2i] = _strip(5)
		for i: int in profiles.size():
			var p: SystemProfile = profiles[i]
			assert_eq(MovementCost.route_cost_ft(p, l, path), expected[i], "%s %s" % [p.id, k])
			var r: MovementCost.Route = MovementCost.find_route(p, l, Vector2i(0, 0), Vector2i(4, 0))
			assert_true(r.found, "%s %s" % [p.id, k])
			assert_eq(r.cost_ft, expected[i])
			assert_eq(r.cells, path)
		assert_eq(MovementCost.band_for_ft(profiles[2], MovementCost.route_cost_ft(profiles[2], l, path)), "near")


func test_route_avoids_difficult_when_cheaper() -> void:
	var l: MapLevel = _open_level(SQUARE, 3, 3)
	l.set_terrain(Vector2i(1, 1), Terrain.RUBBLE)
	var pf: MovementCost.Route = MovementCost.find_route(_profile("pf2e"), l, Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(pf.cost_ft, 15)
	assert_false(pf.cells.has(Vector2i(1, 1)))
	assert_eq(MovementCost.find_route(_profile("dnd5e_2024"), l, Vector2i(0, 0), Vector2i(2, 2)).cost_ft, 15)
	# Diagonal alterna exacta en la búsqueda (estado con fase).
	var open: MapLevel = _open_level(SQUARE, 5, 5)
	var r: MovementCost.Route = MovementCost.find_route(_profile("pf2e"), open, Vector2i(0, 0), Vector2i(4, 4))
	# 4 diagonales (5+10+5+10) o 3 diagonales y 2 rectas (20+10): 30 ft.
	assert_eq(r.cost_ft, 30)
	assert_eq(MovementCost.route_cost_ft(_profile("pf2e"), open, r.cells), 30)
	assert_eq(MovementCost.find_route(_profile("dnd5e_2024"), open, Vector2i(0, 0), Vector2i(4, 4)).cost_ft, 20)
	assert_eq(MovementCost.find_route(_profile("dnd5e_2024"), open, Vector2i(0, 0), Vector2i(4, 4), "alternate_5_10").cost_ft, 30)
	# Determinista.
	var again: MovementCost.Route = MovementCost.find_route(_profile("pf2e"), open, Vector2i(0, 0), Vector2i(4, 4))
	assert_eq(again.cells, r.cells)


func test_walls_and_doors_block_routes() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	for k: String in GridGeometry.KINDS:
		var l: MapLevel = _open_level(k, 3, 1)
		var path: Array[Vector2i] = _strip(3)
		var dir: int = l.grid.direction_between(Vector2i(0, 0), Vector2i(1, 0))
		assert_true(dir >= 0, k)
		l.set_edge(Vector2i(0, 0), dir, MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_OPEN))
		assert_eq(MovementCost.route_cost_ft(p, l, path), 10, "puerta abierta: %s" % k)
		l.set_edge(Vector2i(0, 0), dir, MapEdge.make(MapEdge.KIND_DOOR))
		assert_eq(MovementCost.route_cost_ft(p, l, path), -1, "puerta cerrada sin llave: %s" % k)
		l.set_edge(Vector2i(0, 0), dir, MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_LOCKED))
		assert_eq(MovementCost.route_cost_ft(p, l, path), -1, "con llave: %s" % k)
		assert_false(MovementCost.find_route(p, l, Vector2i(0, 0), Vector2i(2, 0)).found)
		l.set_edge(Vector2i(0, 0), dir, MapEdge.make(MapEdge.KIND_WALL))
		assert_eq(MovementCost.route_cost_ft(p, l, path), -1)
		l.set_edge(Vector2i(0, 0), dir, MapEdge.NONE)
		l.set_terrain(Vector2i(1, 0), Terrain.PIT)
		assert_eq(MovementCost.route_cost_ft(p, l, path), -1, "foso: %s" % k)
		l.set_terrain(Vector2i(1, 0), Terrain.WATER_DEEP)
		assert_eq(MovementCost.route_cost_ft(p, l, path), 15, "agua profunda = difícil: %s" % k)
		l.set_terrain(Vector2i(1, 0), Terrain.WALL)
		assert_eq(MovementCost.route_cost_ft(p, l, path), -1, "casilla maciza: %s" % k)
	# Casillas no vecinas.
	var open: MapLevel = _open_level(SQUARE, 4, 4)
	var jump: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
	assert_eq(MovementCost.route_cost_ft(p, open, jump), -1)
	var empty: Array[Vector2i] = []
	assert_eq(MovementCost.route_cost_ft(p, open, empty), 0)


func test_diagonal_corner_rule() -> void:
	var any_side: SystemProfile = _profile("dnd5e_2024")
	var both_sides: SystemProfile = _custom_profile(func(root: Dictionary) -> void:
		root["id"] = "test_corners"
		root["seed_code"] = "TCRN"
		var mv: Dictionary = root["movement"]
		mv["diagonal_corner_rule"] = "both_sides_free"
	)
	var diag: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0)]
	# Columna maciza en (0,0): un rodeo libre (por (1,1)).
	var pillar: MapLevel = _open_level(SQUARE, 2, 2)
	pillar.set_terrain(Vector2i(0, 0), Terrain.WALL)
	assert_eq(MovementCost.route_cost_ft(any_side, pillar, diag), 5)
	assert_eq(MovementCost.route_cost_ft(both_sides, pillar, diag), -1)
	assert_eq(MovementCost.find_route(both_sides, pillar, Vector2i(0, 1), Vector2i(1, 0)).cost_ft, 10)
	# Muro fino horizontal que cruza la esquina: ningún rodeo libre.
	var thin: MapLevel = _open_level(SQUARE, 2, 2)
	thin.set_edge(Vector2i(0, 1), 0, MapEdge.make(MapEdge.KIND_WALL))
	thin.set_edge(Vector2i(1, 1), 0, MapEdge.make(MapEdge.KIND_WALL))
	assert_eq(MovementCost.route_cost_ft(any_side, thin, diag), -1)
	assert_false(MovementCost.find_route(any_side, thin, Vector2i(0, 1), Vector2i(1, 0)).found)


func test_cost_field() -> void:
	var dnd: SystemProfile = _profile("dnd5e_2024")
	var sq: MapLevel = _open_level(SQUARE, 3, 3)
	var far_corner: int = sq.grid.index_of(Vector2i(2, 2))
	assert_eq(MovementCost.cost_field(dnd, sq, Vector2i(0, 0))[far_corner], 10)
	assert_eq(MovementCost.cost_field(_profile("pf2e"), sq, Vector2i(0, 0))[far_corner], 15)
	var limited: PackedInt32Array = MovementCost.cost_field(dnd, sq, Vector2i(0, 0), "", 5)
	assert_eq(limited[far_corner], -1)
	assert_eq(limited[sq.grid.index_of(Vector2i(1, 1))], 5)
	assert_eq(limited[0], 0)
	var hx: MapLevel = _open_level("hex_flat", 3, 3)
	assert_eq(MovementCost.cost_field(dnd, hx, Vector2i(0, 0))[hx.grid.index_of(Vector2i(2, 2))], 15)


func test_cells_within_ft() -> void:
	var dnd: SystemProfile = _profile("dnd5e_2024")
	var pf: SystemProfile = _profile("pf2e")
	var sq: GridGeometry = GridFactory.create(SQUARE, 20, 20)
	# 10 ft: cuadrado 5×5 en 5e; en PF2e las esquinas (5+10 = 15) quedan fuera.
	assert_eq(MovementCost.cells_within_ft(dnd, sq, Vector2i(10, 10), 10).size(), 25)
	assert_eq(MovementCost.cells_within_ft(pf, sq, Vector2i(10, 10), 10).size(), 21)
	var hx: GridGeometry = GridFactory.create("hex_pointy", 20, 20)
	assert_eq(MovementCost.cells_within_ft(dnd, hx, Vector2i(10, 10), 10).size(), 19)
