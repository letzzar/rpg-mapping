class_name GeoNames
extends RefCounted
## Nombres propios inventados (reinos y asentamientos de MUN G1 y REG G1/G2)
## por sílabas, según el estilo cultural (human, dwarf, elf). No son textos
## de interfaz: son contenido generado (entran en el hash), iguales en todos
## los idiomas, como un topónimo.
##
## CAMBIAR LAS TABLAS O EL ALGORITMO CAMBIA LOS MAPAS: exige GEN nuevo en MUN
## y REG.

const _ONSETS: Dictionary = {
	"human": ["b", "br", "c", "d", "dr", "f", "g", "gr", "h", "k", "l", "m", "n", "p", "r", "s", "st", "t", "th", "v", "w"],
	"dwarf": ["b", "d", "dr", "g", "gr", "k", "kh", "th", "z", "br", "t", "m", "n"],
	"elf": ["l", "th", "s", "f", "n", "c", "m", "r", "v", "y", "gl", "sh"],
}
const _VOWELS: Dictionary = {
	"human": ["a", "e", "i", "o", "u", "a", "e", "o", "ea", "ia"],
	"dwarf": ["a", "u", "o", "i", "a", "u"],
	"elf": ["a", "e", "i", "a", "e", "ae", "ia", "ie", "ea"],
}
const _CODAS: Dictionary = {
	"human": ["", "", "n", "r", "l", "s", "nd", "rd", "m", "th"],
	"dwarf": ["k", "m", "n", "r", "rn", "nd", "l", "z", "g", "th", "rk", "d"],
	"elf": ["", "", "", "l", "n", "s", "th", "r", "nd"],
}
const _SETTLEMENT_ENDS: Dictionary = {
	"human": ["ford", "ton", "wick", "ham", "mere", "dale", "bury", "field", "stead", "brook", "", "", ""],
	"dwarf": ["heim", "dum", "grund", "hold", "berg", "gard", "", "", ""],
	"elf": ["wen", "del", "las", "ion", "iel", "ath", "ost", "", "", ""],
}
const _REALM_ENDS: Dictionary = {
	"human": ["ia", "land", "mark", "or", "ia", "en"],
	"dwarf": ["heim", "dar", "grund", "kar", "um"],
	"elf": ["ië", "ondë", "aris", "elen", "orë"],
}
const STYLES: PackedStringArray = ["human", "dwarf", "elf"]


## Nombre de asentamiento (2-3 sílabas + terminación opcional).
static func settlement(rng: Rng, style: String) -> String:
	return _make(rng, style, _SETTLEMENT_ENDS)


## Nombre de reino.
static func realm(rng: Rng, style: String) -> String:
	return _make(rng, style, _REALM_ENDS)


static func _make(rng: Rng, style: String, ends: Dictionary) -> String:
	var st: String = style if STYLES.has(style) else "human"
	var onsets: Array = _ONSETS[st]
	var vowels: Array = _VOWELS[st]
	var codas: Array = _CODAS[st]
	var end_list: Array = ends[st]
	var syllables: int = 1 + rng.bounded(2)
	var out: String = ""
	for k: int in syllables:
		var o: String = onsets[rng.bounded(onsets.size())]
		var v: String = vowels[rng.bounded(vowels.size())]
		var c: String = codas[rng.bounded(codas.size())] if k == syllables - 1 else ""
		out += o + v + c
	var e: String = end_list[rng.bounded(end_list.size())]
	if e.is_empty() and out.length() < 4:
		var o2: String = onsets[rng.bounded(onsets.size())]
		var v2: String = vowels[rng.bounded(vowels.size())]
		e = o2 + v2
	out += e
	return out.substr(0, 1).to_upper() + out.substr(1)
