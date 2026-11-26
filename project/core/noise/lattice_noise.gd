class_name LatticeNoise
extends RefCounted
## Ruido propio del proyecto (PROYECTO §5.1, CLAUDE.md §6.1): solo enteros,
## sin FastNoiseLite ni float, idéntico en escritorio y en web.
##
## Dos herramientas:
## 1. Refinamiento por octavas (refine): duplica la resolución de un campo
##    entero con interpolación bilineal entera y le suma ruido blanco uniforme
##    de amplitud dada. Encadenar refine() desde una red pequeña con
##    amplitudes decrecientes da ruido fractal (desplazamiento del punto medio
##    con interpolación bilineal). Coste O(casillas de salida) por nivel; la
##    cadena completa cuesta ~1,33 × las casillas finales. Es lo que permite
##    el mundo de 2048×1024 en pocos segundos: un fBm clásico de 8 octavas
##    evaluado casilla a casilla costaría ~8 veces más.
##    El ruido blanco sale de un LCG de 32 bits (Numerical Recipes) recorrido
##    en orden por filas: depende solo de la semilla del nivel y del tamaño.
## 2. Ruido de valor puntual (hash2, value_noise, fbm): para mapas pequeños
##    (hexcrawl de región, ~10³ casillas) donde se evalúa casilla a casilla.
##
## CAMBIAR CUALQUIER FUNCIÓN DE ESTE FICHERO CAMBIA LOS MAPAS DE MUN Y REG:
## exige GEN nuevo en los generadores que la usan (y conservar esta versión).

const MASK32: int = 0xFFFFFFFF
const LCG_MUL: int = 1664525
const LCG_INC: int = 1013904223


## Semilla de 32 bits (no negativa) a partir de una de 64.
static func seed32(seed_value: int) -> int:
	return (seed_value ^ (seed_value >> 32)) & MASK32


## Hash de 32 bits de (semilla, x, y), en [0, 2³²). Mezcla de tipo
## murmur/xxhash; todos los productos caben en int64 (operandos < 2³²·2³⁰).
static func hash2(s32: int, x: int, y: int) -> int:
	var h: int = (s32 ^ ((x & 0xFFFF) * 0x27D4EB2F) ^ ((y & 0xFFFF) * 0x165667B1)) & MASK32
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & MASK32
	h = ((h ^ (h >> 12)) * 0x297A2D39) & MASK32
	return h ^ (h >> 15)


## Campo w×h de ruido blanco uniforme en [-amp, amp] (LCG por filas).
static func white(s32: int, w: int, h: int, amp: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(w * h)
	var span: int = 2 * amp + 1
	var s: int = s32 & MASK32
	for i: int in w * h:
		s = (s * LCG_MUL + LCG_INC) & MASK32
		out[i] = (((s >> 16) * span) >> 16) - amp
	return out


## Duplica la resolución de `src` (sw×sh) -> (2sw)×(2sh): las casillas pares
## copian la de la red gruesa, las impares son la media entera (desplazamiento
## aritmético: redondeo hacia -inf) de sus 2 o 4 vecinas; después se suma ruido
## uniforme en [-amp, amp]. Con `wrap_x` la columna siguiente a la última es
## la 0 (mundo cilíndrico); en y se repite la última fila.
static func refine(src: PackedInt32Array, sw: int, sh: int, amp: int, s32: int, wrap_x: bool) -> PackedInt32Array:
	var fw: int = sw * 2
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(fw * sh * 2)
	var span: int = 2 * amp + 1
	var s: int = s32 & MASK32
	for cy: int in sh:
		var r0: int = cy * sw
		var r1: int = (cy + 1) * sw if cy + 1 < sh else r0
		var o0: int = 2 * cy * fw
		var o1: int = o0 + fw
		for cx: int in sw:
			var cx1: int = cx + 1
			if cx1 >= sw:
				cx1 = 0 if wrap_x else cx
			var a: int = src[r0 + cx]
			var b: int = src[r0 + cx1]
			var c: int = src[r1 + cx]
			var d: int = src[r1 + cx1]
			var fx: int = 2 * cx
			s = (s * LCG_MUL + LCG_INC) & MASK32
			out[o0 + fx] = a + (((s >> 16) * span) >> 16) - amp
			s = (s * LCG_MUL + LCG_INC) & MASK32
			out[o0 + fx + 1] = ((a + b) >> 1) + (((s >> 16) * span) >> 16) - amp
			s = (s * LCG_MUL + LCG_INC) & MASK32
			out[o1 + fx] = ((a + c) >> 1) + (((s >> 16) * span) >> 16) - amp
			s = (s * LCG_MUL + LCG_INC) & MASK32
			out[o1 + fx + 1] = ((a + b + c + d) >> 2) + (((s >> 16) * span) >> 16) - amp
	return out


## Desenfoque de caja 3×3 entero (suma / 9, redondeo hacia -inf). En x
## envuelve si `wrap_x`; en y repite el borde. Para campos gruesos.
static func blur3(src: PackedInt32Array, w: int, h: int, wrap_x: bool) -> PackedInt32Array:
	var tmp: PackedInt32Array = PackedInt32Array()
	tmp.resize(w * h)
	for y: int in h:
		var row: int = y * w
		for x: int in w:
			var xl: int = x - 1
			var xr: int = x + 1
			if xl < 0:
				xl = w - 1 if wrap_x else 0
			if xr >= w:
				xr = 0 if wrap_x else w - 1
			tmp[row + x] = src[row + xl] + src[row + x] + src[row + xr]
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(w * h)
	for y: int in h:
		var up: int = maxi(0, y - 1) * w
		var row: int = y * w
		var dn: int = mini(h - 1, y + 1) * w
		for x: int in w:
			out[row + x] = floori_div(tmp[up + x] + tmp[row + x] + tmp[dn + x], 9)
	return out


## Ruido de valor en un punto (coordenadas en milésimas de celda de la red):
## interpolación bilineal entera con suavizado (3t² − 2t³ en milésimas) de
## hash2 en las 4 esquinas. Resultado en [0, 65535].
static func value_noise(s32: int, xm: int, ym: int) -> int:
	var x0: int = floori_div(xm, 1000)
	var y0: int = floori_div(ym, 1000)
	var tx: int = _smooth(xm - x0 * 1000)
	var ty: int = _smooth(ym - y0 * 1000)
	var a: int = hash2(s32, x0, y0) >> 16
	var b: int = hash2(s32, x0 + 1, y0) >> 16
	var c: int = hash2(s32, x0, y0 + 1) >> 16
	var d: int = hash2(s32, x0 + 1, y0 + 1) >> 16
	var top: int = a * 1000 + (b - a) * tx
	var bot: int = c * 1000 + (d - c) * tx
	return (top * 1000 + (bot - top) * ty) / 1000000


## fBm de `octaves` octavas de value_noise (periodo inicial `period` en las
## mismas unidades que x, y; cada octava, la mitad de periodo y de peso).
## Resultado centrado en 0, en [-32768, 32767] aprox.
static func fbm(s32: int, x: int, y: int, period: int, octaves: int) -> int:
	var total: int = 0
	var weight_sum: int = 0
	var weight: int = 1 << octaves
	var p: int = maxi(1, period)
	for o: int in octaves:
		var so: int = (s32 + o * 0x9E3779B9) & MASK32
		total += (value_noise(so, x * 1000 / p, y * 1000 / p) - 32768) * weight
		weight_sum += weight
		weight >>= 1
		p = maxi(1, p >> 1)
	return total / weight_sum


## Suavizado 3t² − 2t³ con t en milésimas -> milésimas.
static func _smooth(t: int) -> int:
	return (t * t * (3000 - 2 * t)) / 1000000


## División entera redondeando hacia -infinito (b > 0).
static func floori_div(a: int, b: int) -> int:
	var q: int = a / b
	if a % b != 0 and a < 0:
		q -= 1
	return q
