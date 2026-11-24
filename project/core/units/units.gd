class_name Units
extends RefCounted
## Unidades de distancia (PROYECTO.md §9).
##
## Internamente todo son casillas enteras o milímetros enteros: así no se
## acumulan errores de float y el resultado es idéntico en todas las
## plataformas. Mostrar una distancia SOLO con format_distance().
##
## Modos de conversión imperial ↔ métrico:
## - CONVENTION (por defecto): 5 ft = 1,5 m → 1 ft = 300 mm; 6 mi = 10 km.
##   Es la convención de las ediciones en español.
## - EXACT: 1 ft = 304,8 mm; 1 mi = 1 609 344 mm.

enum Mode { CONVENTION, EXACT }
enum System { METRIC, IMPERIAL }

const MM_PER_KM: int = 1_000_000
const FT_PER_MI: int = 5280


## Pies → mm (redondeo al mm más cercano).
static func ft_to_mm(ft: int, mode: Mode = Mode.CONVENTION) -> int:
	if mode == Mode.CONVENTION:
		return ft * 300
	return _div_round(ft * 3048, 10)


## Millas → mm (redondeo al mm más cercano).
static func mi_to_mm(mi: int, mode: Mode = Mode.CONVENTION) -> int:
	if mode == Mode.CONVENTION:
		return _div_round(mi * 10 * MM_PER_KM, 6)
	return mi * 1_609_344


## Casillas → mm, dado el lado de casilla del perfil en pies.
static func cells_to_mm(cells: int, cell_ft: int, mode: Mode = Mode.CONVENTION) -> int:
	return cells * ft_to_mm(cell_ft, mode)


## Texto de una distancia para la interfaz.
## - Métrico: "m" con hasta 2 decimales; "km" a partir de 1 km.
## - Imperial: "ft" con hasta 2 decimales; "mi" a partir de 1 mi.
## Separador decimal y símbolos salen de i18n (UNIT_DECIMAL_SEP, UNIT_FMT_*).
static func format_distance(mm: int, system: System, mode: Mode = Mode.CONVENTION) -> String:
	var prefix: String = "-" if mm < 0 else ""
	var a: int = absi(mm)
	var hundredths: int
	var key: String
	if system == System.METRIC:
		if a >= MM_PER_KM:
			hundredths = _div_round(a, MM_PER_KM / 100)
			key = "UNIT_FMT_KM"
		else:
			hundredths = _div_round(a, 10)
			key = "UNIT_FMT_M"
	else:
		var mi_mm: int = mi_to_mm(1, mode)
		if a >= mi_mm:
			hundredths = _div_round(a * 100, mi_mm)
			key = "UNIT_FMT_MI"
		else:
			# mm de un pie ×10 (3000 o 3048) para no perder el 0,8 del modo exacto.
			var ft_mm_x10: int = 3000 if mode == Mode.CONVENTION else 3048
			hundredths = _div_round(a * 1000, ft_mm_x10)
			key = "UNIT_FMT_FT"
	var number: String = prefix + _fixed2(hundredths)
	return TranslationServer.translate(key).replace("{value}", number)


## "1234" centésimas → "12,34"; quita ceros decimales sobrantes ("9,10"→"9,1", "9,00"→"9").
static func _fixed2(hundredths: int) -> String:
	var whole: int = hundredths / 100
	var frac: int = hundredths % 100
	if frac == 0:
		return str(whole)
	var sep: String = TranslationServer.translate("UNIT_DECIMAL_SEP")
	if frac % 10 == 0:
		return "%d%s%d" % [whole, sep, frac / 10]
	return "%d%s%02d" % [whole, sep, frac]


## División entera redondeando la mitad hacia arriba (numerador >= 0, d > 0).
static func _div_round(n: int, d: int) -> int:
	return (n + d / 2) / d
