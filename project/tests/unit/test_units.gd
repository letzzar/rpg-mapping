extends GutTest
## Tests de core/units (PROYECTO.md §9).

var _prev_locale: String = ""


func before_each() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("es")


func after_each() -> void:
	TranslationServer.set_locale(_prev_locale)


func test_ft_to_mm_modes() -> void:
	assert_eq(Units.ft_to_mm(5), 1500)
	assert_eq(Units.ft_to_mm(30), 9000)
	assert_eq(Units.ft_to_mm(5, Units.Mode.EXACT), 1524)
	assert_eq(Units.ft_to_mm(30, Units.Mode.EXACT), 9144)


func test_mi_to_mm_modes() -> void:
	assert_eq(Units.mi_to_mm(6), 10_000_000)
	assert_eq(Units.mi_to_mm(6, Units.Mode.EXACT), 9_656_064)


func test_cells_to_mm() -> void:
	assert_eq(Units.cells_to_mm(6, 5), 9000)
	assert_eq(Units.cells_to_mm(6, 5, Units.Mode.EXACT), 9144)


func test_format_metric_es() -> void:
	assert_eq(Units.format_distance(9000, Units.System.METRIC), "9 m")
	assert_eq(Units.format_distance(9144, Units.System.METRIC), "9,14 m")
	assert_eq(Units.format_distance(1500, Units.System.METRIC), "1,5 m")
	assert_eq(Units.format_distance(10_000_000, Units.System.METRIC), "10 km")
	assert_eq(Units.format_distance(9_656_064, Units.System.METRIC), "9,66 km")
	assert_eq(Units.format_distance(-1500, Units.System.METRIC), "-1,5 m")
	assert_eq(Units.format_distance(0, Units.System.METRIC), "0 m")


func test_format_imperial_roundtrip_both_modes() -> void:
	for mode: Units.Mode in [Units.Mode.CONVENTION, Units.Mode.EXACT]:
		assert_eq(Units.format_distance(Units.ft_to_mm(30, mode), Units.System.IMPERIAL, mode), "30 ft")
		assert_eq(Units.format_distance(Units.ft_to_mm(5, mode), Units.System.IMPERIAL, mode), "5 ft")
		assert_eq(Units.format_distance(Units.mi_to_mm(6, mode), Units.System.IMPERIAL, mode), "6 mi")


func test_format_uses_locale_separator() -> void:
	TranslationServer.set_locale("en")
	assert_eq(Units.format_distance(9144, Units.System.METRIC), "9.14 m")
