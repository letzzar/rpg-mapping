extends GutTest
## Tests de core/rng: vectores de referencia publicados + propiedades.


func test_bits64_lsr_and_hex() -> void:
	assert_eq(Bits64.lsr(-1, 60), 0xF)
	assert_eq(Bits64.lsr(-1, 1), 0x7FFFFFFFFFFFFFFF)
	assert_eq(Bits64.to_hex(-1), "ffffffffffffffff")
	assert_eq(Bits64.to_hex(SplitMix64.GAMMA), "9e3779b97f4a7c15")
	assert_eq(Bits64.to_hex(SplitMix64.MUL1), "bf58476d1ce4e5b9")
	assert_eq(Bits64.to_hex(SplitMix64.MUL2), "94d049bb133111eb")
	assert_eq(Bits64.from_hex("94d049bb133111eb"), SplitMix64.MUL2)
	assert_true(Bits64.ult(1, -1))
	assert_false(Bits64.ult(-1, 1))


## Salida de pcg32-demo (pcg-c-basic) con pcg32_srandom_r(42, 54).
func test_pcg32_reference_vector() -> void:
	var rng: Rng = Rng.new(42, 54)
	var expected: Array[int] = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	for e: int in expected:
		assert_eq(rng.next_u32(), e)


## Vector de referencia de splitmix64.c (Vigna) con semilla 1234567.
## Los valores > 2^63-1 están escritos como su int64 con signo.
func test_splitmix64_reference_vector() -> void:
	var sm: SplitMix64 = SplitMix64.new(1234567)
	var expected: Array[int] = [
		6457827717110365317,
		3203168211198807973,
		-8629252141511181193,  # 9817491932198370423
		4593380528125082431,
		-2037821214251327795,  # 16408922859458223821
	]
	for e: int in expected:
		assert_eq(sm.next_u64(), e)


func test_same_seed_same_sequence() -> void:
	var a: Rng = Rng.new(123456789)
	var b: Rng = Rng.new(123456789)
	for i: int in range(1000):
		assert_eq(a.next_u32(), b.next_u32())


func test_bounded_in_range() -> void:
	var rng: Rng = Rng.new(7)
	for bound: int in [1, 2, 3, 6, 20, 1000, 0x1_0000_0000]:
		for i: int in range(200):
			var v: int = rng.bounded(bound)
			assert_true(v >= 0 and v < bound, "bounded(%d) = %d" % [bound, v])


func test_range_int_covers_all_values() -> void:
	var rng: Rng = Rng.new(99)
	var seen: Dictionary[int, int] = {}
	for i: int in range(600):
		var v: int = rng.range_int(1, 6)
		assert_true(v >= 1 and v <= 6)
		seen[v] = seen.get(v, 0) + 1
	assert_eq(seen.size(), 6)
	# Cada cara ~100; margen amplio para no ser frágil.
	for face: int in seen.keys():
		assert_between(seen[face], 60, 140)


func test_chance_permille_extremes() -> void:
	var rng: Rng = Rng.new(5)
	for i: int in range(100):
		assert_false(rng.chance_permille(0))
		assert_true(rng.chance_permille(1000))


func test_pick_weighted_skips_zero_weights() -> void:
	var rng: Rng = Rng.new(11)
	var weights: PackedInt32Array = PackedInt32Array([0, 3, 0, 1])
	for i: int in range(200):
		var idx: int = rng.pick_weighted(weights)
		assert_true(idx == 1 or idx == 3)


func test_shuffle_is_deterministic_permutation() -> void:
	var a: Array = range(20)
	var b: Array = range(20)
	Rng.new(2024).shuffle(a)
	Rng.new(2024).shuffle(b)
	assert_eq(a, b)
	var sorted_a: Array = a.duplicate()
	sorted_a.sort()
	assert_eq(sorted_a, range(20))
	assert_ne(a, range(20))


func test_fork_independent_of_consumption() -> void:
	var parent1: Rng = Rng.new(31337)
	var parent2: Rng = Rng.new(31337)
	for i: int in range(50):
		parent2.next_u32()
	var c1: Rng = parent1.fork("room", 4)
	var c2: Rng = parent2.fork("room", 4)
	assert_eq(c1.seed_value, c2.seed_value)
	assert_eq(c1.next_u32(), c2.next_u32())


func test_hash64_distinguishes_inputs() -> void:
	var base: int = SplitMix64.hash64(1, "room", 0)
	assert_ne(base, SplitMix64.hash64(1, "room", 1))
	assert_ne(base, SplitMix64.hash64(2, "room", 0))
	assert_ne(base, SplitMix64.hash64(1, "roon", 0))
	assert_ne(SplitMix64.hash64(1, "abcdefgh", 0), SplitMix64.hash64(1, "abcdefghi", 0))
	assert_eq(base, SplitMix64.hash64(1, "room", 0))


## Valores fijados el 2026-11-24 y verificados con una implementación
## independiente (BigInteger en PowerShell). Si este test falla, hash64 ha
## cambiado y TODAS las semillas hijas cambian: subir GEN.
func test_hash64_frozen_values() -> void:
	var got: Array[String] = [
		Bits64.to_hex(SplitMix64.hash64(0, "", 0)),
		Bits64.to_hex(SplitMix64.hash64(1, "room", 4)),
		Bits64.to_hex(SplitMix64.hash64(-1, "edificio_ñ", 123456789)),
	]
	gut.p("hash64 congelados: %s" % [got])
	assert_eq(got, FROZEN_HASH64)


const FROZEN_HASH64: Array[String] = ["238275bc38fcbe91", "2d863d0f5cf65e71", "7bc49ce75854e1e2"]
