class_name Rng
extends RefCounted
## Generador pseudoaleatorio determinista del proyecto: PCG32 (XSH RR 64/32),
## idéntico a pcg32_random_r / pcg32_srandom_r de la referencia de O'Neill.
##
## Por qué propio (ADR 003): RandomNumberGenerator del motor puede cambiar entre
## versiones; este código da la misma secuencia en escritorio y en web.
##
## Reglas (CLAUDE.md §6.1): los generadores reciben un Rng como parámetro y no
## usan ninguna otra fuente de aleatoriedad. Todas las salidas son enteras.
## CAMBIAR CUALQUIER MÉTODO QUE CONSUMA NÚMEROS CAMBIA LOS MAPAS: exige subir
## GEN y regenerar seeds doradas.

## 6364136223846793005 (multiplicador LCG de PCG; cabe en int64).
const MULTIPLIER: int = 6364136223846793005
const TWO_POW_32: int = 0x1_0000_0000

## Semilla con la que se creó (se usa en fork(), no el estado actual).
var seed_value: int
## Flujo (secuencia) de PCG.
var stream: int

var _state: int = 0
var _inc: int = 0


func _init(p_seed: int = 0, p_stream: int = 0) -> void:
	seed_value = p_seed
	stream = p_stream
	# pcg32_srandom_r
	_state = 0
	_inc = (p_stream << 1) | 1
	next_u32()
	_state += p_seed
	next_u32()


## Siguiente entero sin signo de 32 bits en [0, 2^32).
func next_u32() -> int:
	var old: int = _state
	_state = old * MULTIPLIER + _inc
	var xorshifted: int = Bits64.lsr(Bits64.lsr(old, 18) ^ old, 27) & Bits64.MASK32
	var rot: int = Bits64.lsr(old, 59)
	return Bits64.rotr32(xorshifted, rot)


## Entero uniforme en [0, bound), 1 <= bound <= 2^32, sin sesgo
## (pcg32_boundedrand_r: rechazo por debajo del umbral).
func bounded(bound: int) -> int:
	assert(bound >= 1 and bound <= TWO_POW_32, "Rng.bounded: límite fuera de rango")
	var threshold: int = (TWO_POW_32 - bound) % bound
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % bound
	return 0  # Inalcanzable; satisface al analizador.


## Entero uniforme en [lo, hi] (ambos incluidos). hi - lo < 2^32.
func range_int(lo: int, hi: int) -> int:
	assert(hi >= lo, "Rng.range_int: hi < lo")
	return lo + bounded(hi - lo + 1)


## true con probabilidad permille/1000 (sin floats; 0 = nunca, 1000 = siempre).
func chance_permille(permille: int) -> bool:
	return bounded(1000) < permille


## Índice aleatorio para una colección de `size` elementos (size >= 1).
func pick_index(size: int) -> int:
	return bounded(size)


## Índice elegido con pesos enteros no negativos (al menos uno > 0).
func pick_weighted(weights: PackedInt32Array) -> int:
	var total: int = 0
	for w: int in weights:
		assert(w >= 0, "Rng.pick_weighted: peso negativo")
		total += w
	assert(total > 0, "Rng.pick_weighted: todos los pesos son 0")
	var r: int = bounded(total)
	for i: int in weights.size():
		r -= weights[i]
		if r < 0:
			return i
	return weights.size() - 1


## Barajado Fisher–Yates en el sitio.
func shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = bounded(i + 1)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## Rng hijo independiente del consumo de este (PROYECTO.md §5.2): depende solo
## de la semilla original, del tipo y del id estable del hijo.
func fork(child_type: String, child_id: int) -> Rng:
	return Rng.new(SplitMix64.hash64(seed_value, child_type, child_id))
