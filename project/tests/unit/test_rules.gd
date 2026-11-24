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


## Perfil de prueba con bandas genéricas (no corresponde a ningún sistema
## publicado: el mecanismo de bandas se mantiene para perfiles propios, ADR 011).
func test_bands_and_visual_terrain() -> void:
	var src: String = FileAccess.get_file_as_string(SystemProfile.DIR + "dnd5e_2024.json")
	var root: Dictionary = JSON.parse_string(src)
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
	var path: String = "user://perfil_bandas.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(root))
	f.close()
	var p: SystemProfile = SystemProfile.load_path(path)
	DirAccess.remove_absolute(path)
	assert_true(p.is_valid(), p.error)
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
