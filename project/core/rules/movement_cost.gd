class_name MovementCost
extends RefCounted
## Coste de movimiento por casillas según un SystemProfile (PROYECTO.md §10.3).
##
## Un camino es una lista de pasos; cada paso es un entero con banderas
## (STEP_DIAGONAL, STEP_DIFFICULT). Solo enteros: el resultado es idéntico en
## todas las plataformas y sirve también al servidor del DM para validar.

const STEP_DIAGONAL: int = 1
const STEP_DIFFICULT: int = 2


## Coste total en pies. `diagonal_variant` = "" usa movement.diagonal_ft;
## si no, una de movement.diagonal_variants (opción de mesa).
static func path_cost_ft(profile: SystemProfile, steps: PackedInt32Array, diagonal_variant: String = "") -> int:
	var pattern: PackedInt32Array = profile.diagonal_ft
	if not diagonal_variant.is_empty():
		assert(profile.diagonal_variants.has(diagonal_variant), "MovementCost: variante de diagonal desconocida")
		pattern = profile.diagonal_variants[diagonal_variant]
	var total: int = 0
	var diagonals: int = 0
	for step: int in steps:
		var cost: int = profile.cell_ft
		if step & STEP_DIAGONAL:
			cost = pattern[diagonals % pattern.size()]
			diagonals += 1
		if step & STEP_DIFFICULT and not profile.difficult_visual_only:
			cost = cost * profile.difficult_multiplier_pct / 100 + profile.difficult_extra_ft
		total += cost
	return total
