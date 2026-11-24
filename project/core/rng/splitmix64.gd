class_name SplitMix64
extends RefCounted
## SplitMix64 (Steele, Lea, Flood 2014; versión de referencia de Vigna).
##
## Uso en el proyecto: derivar semillas hijas con hash64() (PROYECTO.md §5.2)
## sin generar el resto del árbol. No se usa como generador principal: para
## eso está Rng (PCG32).
##
## Las constantes uint64 se escriben como su equivalente int64 con signo
## porque los literales mayores que 2^63-1 no caben en un int de GDScript.

## 0x9E3779B97F4A7C15
const GAMMA: int = -7046029254386353131
## 0xBF58476D1CE4E5B9
const MUL1: int = -4658895280553007687
## 0x94D049BB133111EB
const MUL2: int = -7723592293110705685

var state: int


func _init(seed_value: int = 0) -> void:
	state = seed_value


## Siguiente valor de 64 bits (como int64 con el mismo patrón de bits).
func next_u64() -> int:
	state += GAMMA
	return finalize(state)


## Función de mezcla de SplitMix64 (biyectiva sobre 64 bits).
static func finalize(z_in: int) -> int:
	var z: int = z_in
	z = (z ^ Bits64.lsr(z, 30)) * MUL1
	z = (z ^ Bits64.lsr(z, 27)) * MUL2
	return z ^ Bits64.lsr(z, 31)


## Un paso de SplitMix64 sobre `x` sin estado: finalize(x + GAMMA).
static func mix(x: int) -> int:
	return finalize(x + GAMMA)


## Semilla de un hijo: hash64(seed_padre, tipo_hijo, id_estable_hijo).
##
## Se absorben, en este orden y cada uno con mix(h ^ palabra):
##   1. la longitud en bytes de `child_type` (UTF-8),
##   2. los bytes UTF-8 de `child_type` en palabras de 8 bytes little-endian
##      (la última rellenada con ceros),
##   3. `child_id`.
## Incluir la longitud evita colisiones entre ("ab", x) y ("ab\0", x).
## CAMBIAR ESTA FUNCIÓN CAMBIA TODAS LAS SEMILLAS: exige subir GEN en todas
## las escalas y regenerar seeds doradas.
static func hash64(parent_seed: int, child_type: String, child_id: int) -> int:
	var bytes: PackedByteArray = child_type.to_utf8_buffer()
	var h: int = mix(parent_seed)
	h = mix(h ^ bytes.size())
	var i: int = 0
	while i < bytes.size():
		var word: int = 0
		for k: int in range(8):
			if i + k < bytes.size():
				word |= bytes[i + k] << (8 * k)
		h = mix(h ^ word)
		i += 8
	h = mix(h ^ child_id)
	return h
