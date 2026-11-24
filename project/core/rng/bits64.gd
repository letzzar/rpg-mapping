class_name Bits64
extends RefCounted
## Utilidades para tratar el `int` de GDScript (int64 con signo) como entero
## de 64 bits SIN signo.
##
## Por qué: PCG32 y SplitMix64 se definen sobre uint64. GDScript solo tiene
## int64 con aritmética en complemento a dos (la suma y la multiplicación
## envuelven igual que en uint64), pero `>>` es aritmético (propaga el signo).
## Aquí se da el desplazamiento lógico y el formateo hexadecimal sin signo.

const MASK32: int = 0xFFFFFFFF


## Desplazamiento lógico a la derecha (rellena con ceros), 0 <= n <= 63.
static func lsr(x: int, n: int) -> int:
	if n <= 0:
		return x
	return (x >> n) & ~(-1 << (64 - n))


## Rotación a la derecha de un valor de 32 bits (0 <= x <= 0xFFFFFFFF).
static func rotr32(x: int, r: int) -> int:
	var rr: int = r & 31
	if rr == 0:
		return x
	return ((x >> rr) | (x << (32 - rr))) & MASK32


## Comparación sin signo: devuelve true si a < b como uint64.
static func ult(a: int, b: int) -> bool:
	# Invertir el bit de signo convierte el orden sin signo en orden con signo.
	return (a ^ (1 << 63)) < (b ^ (1 << 63))


## 16 dígitos hexadecimales en minúsculas, interpretando x como uint64.
static func to_hex(x: int) -> String:
	const DIGITS: String = "0123456789abcdef"
	var out: String = ""
	for i: int in range(15, -1, -1):
		out += DIGITS[lsr(x, i * 4) & 0xF]
	return out


## Inverso de to_hex(); admite de 1 a 16 dígitos. Devuelve 0 si no es válido.
static func from_hex(text: String) -> int:
	var v: int = 0
	for c: String in text.to_lower():
		var d: int = "0123456789abcdef".find(c)
		if d < 0:
			return 0
		v = (v << 4) | d
	return v
