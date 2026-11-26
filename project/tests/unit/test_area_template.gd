extends GutTest
## Plantillas de área (core/rules/area_template.gd): geometría como datos del
## perfil y casillas cubiertas en las tres rejillas (PROYECTO §8 y §10.3).

const HEX_KINDS: PackedStringArray = ["hex_flat", "hex_pointy"]


func _profile(id: String) -> SystemProfile:
	var p: SystemProfile = SystemProfile.load_id(id)
	assert_true(p.is_valid(), p.error)
	return p


func _grid(kind: String, w: int = 30, h: int = 30) -> GridGeometry:
	return GridFactory.create(kind, w, h)


func _cells(p: SystemProfile, g: GridGeometry, id: String, origin: Vector2i, toward: Vector2i, ft: int, footprint: Array[Vector2i] = [], variant: String = "") -> Array[Vector2i]:
	var out: Array[Vector2i] = AreaTemplate.cells(p, g, id, origin, toward, ft, footprint, variant)
	_assert_well_formed(g, out)
	return out


## Dentro del mapa, en orden de índice y sin repetir.
func _assert_well_formed(g: GridGeometry, cells: Array[Vector2i]) -> void:
	var last: int = -1
	for c: Vector2i in cells:
		var i: int = g.index_of(c)
		assert_true(i >= 0, "fuera del mapa: %s" % c)
		assert_true(i > last, "desordenada o repetida: %s" % c)
		last = i


func _rect(x0: int, y0: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(y0, y0 + h):
		for x: int in range(x0, x0 + w):
			out.append(Vector2i(x, y))
	return out


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(cells)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func _offsets(origin: Vector2i, offs: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o: Vector2i in offs:
		out.append(origin + o)
	return _sorted(out)


# --- Datos de los perfiles ---------------------------------------------------

func test_profiles_describe_templates() -> void:
	var dnd: SystemProfile = _profile("dnd5e_2024")
	assert_eq(dnd.area_templates, PackedStringArray(["cone", "cube", "cylinder", "emanation", "line", "sphere"]))
	assert_eq(dnd.area_template("sphere").shape, SystemProfile.SHAPE_CIRCLE)
	assert_eq(dnd.area_template("sphere").origin, SystemProfile.ORIGIN_CORNER)
	assert_eq(dnd.area_template("cube").shape, SystemProfile.SHAPE_SQUARE)
	assert_eq(dnd.area_template("cone").cone_width_pct, 100)
	assert_eq(dnd.area_template("line").line_width_ft, 5)
	assert_true(dnd.area_template("emanation").includes_origin)
	assert_eq(dnd.area_template_default_ft("sphere"), 20)
	assert_eq(dnd.area_template_default_ft("cone"), 15)
	assert_eq(dnd.area_template_default_ft("burst"), 0, "plantilla de otro sistema")
	assert_null(dnd.area_template("burst"))
	var pf: SystemProfile = _profile("pf2e")
	assert_eq(pf.area_templates, PackedStringArray(["burst", "cone", "emanation", "line"]))
	assert_eq(pf.area_template("burst").origin, SystemProfile.ORIGIN_CORNER)
	assert_eq(pf.area_template("cone").cone_width_pct, 200)
	assert_eq(pf.area_template_default_ft("burst"), 20)
	# Solo vistas: 5e = anchura igual a la distancia (semiabertura atan(1/2)); PF2e 45°.
	assert_almost_eq(dnd.area_template("cone").cone_half_angle_rad(), atan(0.5), 1e-6)
	assert_almost_eq(pf.area_template("cone").cone_half_angle_rad(), PI / 4.0, 1e-6)
	for id: String in pf.area_templates:
		assert_gt(pf.area_template_default_ft(id), 0, id)


func _load_mutated(templates: Array) -> SystemProfile:
	var src: String = FileAccess.get_file_as_string(SystemProfile.DIR + "dnd5e_2024.json")
	var root: Dictionary = JSON.parse_string(src)
	root["area_templates"] = templates
	var path: String = "user://perfil_plantillas.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(root))
	f.close()
	var p: SystemProfile = SystemProfile.load_path(path)
	DirAccess.remove_absolute(path)
	return p


func test_invalid_templates_are_rejected() -> void:
	var cases: Array = [
		[{"id": "x", "shape": "star", "default_ft": 10}, "shape"],
		[{"id": "x", "shape": "circle", "default_ft": 10}, "origin"],
		[{"id": "x", "shape": "circle", "default_ft": 10, "origin": "edge"}, "origin"],
		[{"id": "x", "shape": "cone", "default_ft": 10}, "cone_width_pct"],
		[{"id": "x", "shape": "cone", "default_ft": 10, "cone_width_pct": 0}, "cone_width_pct"],
		[{"id": "x", "shape": "line", "default_ft": 10}, "line_width_ft"],
		[{"id": "x", "shape": "square", "default_ft": 0}, "default_ft"],
		[{"id": "x", "shape": "square", "default_ft": 10, "origin": "corner"}, "origin"],
		[{"id": "x", "shape": "emanation", "default_ft": 10}, "includes_origin"],
		["cone", "area_templates"],
	]
	for c: Array in cases:
		var p: SystemProfile = _load_mutated([c[0]])
		assert_false(p.is_valid(), str(c[0]))
		assert_string_contains(p.error, str(c[1]))
	var dup: SystemProfile = _load_mutated([
		{"id": "x", "shape": "square", "default_ft": 10},
		{"id": "x", "shape": "square", "default_ft": 15},
	])
	assert_false(dup.is_valid())
	assert_string_contains(dup.error, "repetido")


func test_unknown_or_empty_templates() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	assert_true(_cells(p, g, "burst", c, c, 20).is_empty(), "no es de 5e")
	assert_true(_cells(p, g, "sphere", c, c, 0).is_empty())
	assert_true(_cells(p, g, "sphere", c, c, -5).is_empty())
	# Cono y línea sin dirección.
	assert_true(_cells(p, g, "cone", c, c, 15).is_empty())
	assert_true(_cells(p, g, "line", c, c, 30).is_empty())


# --- Cuadrícula: D&D 5e (SRD 5.2) --------------------------------------------

func test_dnd_sphere_and_cylinder_square() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	# Diagonal de 5 ft: la esfera de 20 ft desde la intersección es un
	# cuadrado de 8×8 (4 casillas a cada lado de la esquina).
	assert_eq(_cells(p, g, "sphere", c, c, 20), _rect(6, 6, 8, 8))
	assert_eq(_cells(p, g, "cylinder", c, c, 10), _rect(8, 8, 4, 4))
	assert_eq(_cells(p, g, "sphere", c, c, 5), _rect(9, 9, 2, 2))
	# Variante de mesa 5/10: octógono, como la explosión de PF2e.
	assert_eq(_cells(p, g, "sphere", c, c, 20, [], "alternate_5_10").size(), 44)


func test_dnd_cube_square() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	assert_eq(_cells(p, g, "cube", c, c, 10), _rect(10, 10, 2, 2))
	assert_eq(_cells(p, g, "cube", c, c, 15), _rect(10, 10, 3, 3))
	# Un lado que no es múltiplo de la casilla se redondea hacia arriba.
	assert_eq(_cells(p, g, "cube", c, c, 12).size(), 9)


func test_dnd_cone_square() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	# 15 ft al este: vértice en el borde este de la casilla; anchura = distancia.
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, -1), Vector2i(3, 0), Vector2i(3, 1)]
	assert_eq(_cells(p, g, "cone", c, Vector2i(25, 10), 15), _offsets(c, east))
	# 15 ft en diagonal (SE): vértice en la esquina.
	var se: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3),
	]
	assert_eq(_cells(p, g, "cone", c, Vector2i(13, 13), 15), _offsets(c, se))
	# Simetría: las cuatro direcciones ortogonales dan lo mismo.
	for t: Vector2i in [Vector2i(10, 0), Vector2i(0, 10), Vector2i(10, 29)]:
		assert_eq(_cells(p, g, "cone", c, t, 15).size(), 5, str(t))
	# Solo cuenta la dirección, no lo lejos que esté `toward`.
	assert_eq(_cells(p, g, "cone", c, Vector2i(11, 10), 15), _cells(p, g, "cone", c, Vector2i(29, 10), 15))


func test_dnd_line_square() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	var east: Array[Vector2i] = []
	var diag: Array[Vector2i] = []
	for i: int in range(1, 7):
		east.append(Vector2i(i, 0))
		diag.append(Vector2i(i, i))
	assert_eq(_cells(p, g, "line", c, Vector2i(20, 10), 30), _offsets(c, east))
	# En diagonal la medida de 5e cuenta 5 ft por casilla: 6 casillas.
	assert_eq(_cells(p, g, "line", c, Vector2i(25, 25), 30), _offsets(c, diag))
	# Rumbo oblicuo: franja de una casilla, contigua (vecinas en 8 direcciones).
	var oblique: Array[Vector2i] = _cells(p, g, "line", c, Vector2i(20, 14), 30)
	assert_false(oblique.is_empty())
	var cols: Dictionary[int, bool] = {}
	for cell: Vector2i in oblique:
		cols[cell.x] = true
		assert_true(cell.x - c.x <= 6, str(cell))
	assert_eq(cols.size(), 6, "una o dos casillas por columna, sin huecos")


func test_dnd_emanation_square() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	assert_eq(_cells(p, g, "emanation", c, c, 10), _rect(8, 8, 5, 5))
	# Criatura Grande (2×2): 5 ft desde cada lado de su espacio.
	var large: Array[Vector2i] = g.footprint(c, 2)
	assert_eq(_cells(p, g, "emanation", c, c, 5, large), _rect(9, 9, 4, 4))


# --- Cuadrícula: PF2e (ORC) ---------------------------------------------------

func test_pf2e_burst_square() -> void:
	var p: SystemProfile = _profile("pf2e")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	# Desde una esquina, diagonales alternas 5/10.
	assert_eq(_cells(p, g, "burst", c, c, 5), _rect(9, 9, 2, 2))
	var b10: Array[Vector2i] = _rect(8, 8, 4, 4)
	for corner: Vector2i in [Vector2i(8, 8), Vector2i(11, 8), Vector2i(8, 11), Vector2i(11, 11)]:
		b10.erase(corner)
	assert_eq(_cells(p, g, "burst", c, c, 10), b10)
	assert_eq(_cells(p, g, "burst", c, c, 20).size(), 44)
	assert_eq(_cells(p, g, "burst", c, c, 30).size(), 96)


func test_pf2e_cone_square() -> void:
	var p: SystemProfile = _profile("pf2e")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	# Ortogonal: la primera casilla comparte borde con el espacio.
	var east: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1),
		Vector2i(3, -1), Vector2i(3, 0), Vector2i(3, 1),
	]
	assert_eq(_cells(p, g, "cone", c, Vector2i(20, 10), 15), _offsets(c, east))
	# Diagonal: cuarto de círculo desde la esquina (6 casillas a 15 ft).
	var se: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 3),
	]
	assert_eq(_cells(p, g, "cone", c, Vector2i(15, 15), 15), _offsets(c, se))


func test_pf2e_line_and_emanation_square() -> void:
	var p: SystemProfile = _profile("pf2e")
	var g: GridGeometry = _grid("square")
	var c: Vector2i = Vector2i(10, 10)
	# 30 ft en diagonal con 5/10: 4 casillas.
	var diag: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]
	assert_eq(_cells(p, g, "line", c, Vector2i(20, 20), 30), _offsets(c, diag))
	assert_eq(_cells(p, g, "line", c, Vector2i(10, 0), 30).size(), 6)
	# Emanación de 10 ft: 5×5 sin las esquinas (a 15 ft).
	assert_eq(_cells(p, g, "emanation", c, c, 10).size(), 21)


# --- Bordes del mapa -----------------------------------------------------------

func test_map_edges_clip() -> void:
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("square", 12, 8)
	var corner: Vector2i = Vector2i(0, 0)
	assert_eq(_cells(p, g, "sphere", corner, corner, 20), _rect(0, 0, 4, 4))
	assert_eq(_cells(p, g, "emanation", corner, corner, 10), _rect(0, 0, 3, 3))
	assert_eq(_cells(p, g, "cube", Vector2i(10, 6), Vector2i(10, 6), 20), _rect(10, 6, 2, 2))
	# Cono hacia fuera del mapa: vacío; desde la segunda columna, solo la primera.
	assert_true(_cells(p, g, "cone", Vector2i(0, 4), Vector2i(-5, 4), 15).is_empty())
	var one: Array[Vector2i] = [Vector2i(0, 4)]
	assert_eq(_cells(p, g, "cone", Vector2i(1, 4), Vector2i(-5, 4), 15), one)
	var line: Array[Vector2i] = _cells(p, g, "line", Vector2i(5, 4), Vector2i(30, 4), 60)
	assert_eq(line, _rect(6, 4, 6, 1))
	# Origen fuera del mapa: solo lo que cae dentro.
	assert_eq(_cells(p, g, "sphere", Vector2i(-1, -1), Vector2i(-1, -1), 10), _rect(0, 0, 1, 1))
	# Plantillas enormes: acotadas, sin desbordar.
	var big: GridGeometry = _grid("square", 40, 40)
	assert_eq(_cells(p, big, "sphere", Vector2i(20, 20), Vector2i(20, 20), 100000).size(), 1600)
	assert_false(_cells(p, big, "cone", Vector2i(0, 0), Vector2i(4000, 3999), 100000).is_empty())


# --- Hex ------------------------------------------------------------------------

func test_hex_circles_cube_and_emanation() -> void:
	for id: String in ["dnd5e_2024", "pf2e"]:
		var p: SystemProfile = _profile(id)
		var circle: String = "sphere" if id == "dnd5e_2024" else "burst"
		for kind: String in HEX_KINDS:
			var g: GridGeometry = _grid(kind)
			var c: Vector2i = Vector2i(10, 10)
			# En hex el círculo se centra en la casilla: radio 4 = 61 hexágonos.
			assert_eq(_cells(p, g, circle, c, c, 20), g.cells_in_radius(c, 4), kind)
			assert_eq(_cells(p, g, "emanation", c, c, 10).size(), 19, kind)
			# Huella Enorme (7 hex) + 5 ft = radio 2.
			var huge: Array[Vector2i] = g.footprint(c, 1, 7)
			assert_eq(_cells(p, g, "emanation", c, c, 5, huge), g.cells_in_radius(c, 2), kind)
	var dnd: SystemProfile = _profile("dnd5e_2024")
	for kind: String in HEX_KINDS:
		var g2: GridGeometry = _grid(kind)
		var o: Vector2i = Vector2i(10, 10)
		assert_eq(_cells(dnd, g2, "cube", o, o, 5).size(), 1, kind)
		assert_eq(_cells(dnd, g2, "cube", o, o, 10), g2.cells_in_radius(o, 1), kind)
		assert_eq(_cells(dnd, g2, "cube", o, o, 30), g2.cells_in_radius(o, 3), kind)


func test_hex_lines_follow_axes() -> void:
	for id: String in ["dnd5e_2024", "pf2e"]:
		var p: SystemProfile = _profile(id)
		for kind: String in HEX_KINDS:
			var g: GridGeometry = _grid(kind)
			var c: Vector2i = Vector2i(10, 10)
			for d: int in 6:
				var expected: Array[Vector2i] = []
				var cur: Vector2i = c
				for i: int in 6:
					cur = g.neighbor(cur, d)
					expected.append(cur)
				var far: Vector2i = g.neighbor(g.neighbor(cur, d), d)
				assert_eq(_cells(p, g, "line", c, far, 30), _sorted(expected), "%s %s dir %d" % [id, kind, d])


func test_hex_cones_symmetric() -> void:
	# Hacia cada vecino: 5e (anchura = distancia) 5 hexágonos a 15 ft; PF2e
	# (90°) 7. Las seis direcciones y las dos orientaciones dan lo mismo.
	var expected: Dictionary[String, int] = {"dnd5e_2024": 5, "pf2e": 7}
	for id: String in ["dnd5e_2024", "pf2e"]:
		var p: SystemProfile = _profile(id)
		for kind: String in HEX_KINDS:
			var g: GridGeometry = _grid(kind)
			var c: Vector2i = Vector2i(10, 10)
			for d: int in 6:
				var t: Vector2i = g.neighbor(g.neighbor(c, d), d)
				var cone: Array[Vector2i] = _cells(p, g, "cone", c, t, 15)
				assert_eq(cone.size(), expected[id], "%s %s dir %d" % [id, kind, d])
				assert_true(cone.has(g.neighbor(c, d)), "la primera casilla toca el espacio")
				for cell: Vector2i in cone:
					assert_true(g.distance(c, cell) <= 3, str(cell))


func test_hex_edges_clip() -> void:
	var p: SystemProfile = _profile("pf2e")
	for kind: String in HEX_KINDS:
		var g: GridGeometry = _grid(kind, 10, 10)
		var c: Vector2i = Vector2i(0, 0)
		assert_eq(_cells(p, g, "burst", c, c, 10), g.cells_in_radius(c, 2), kind)
		assert_eq(_cells(p, g, "emanation", Vector2i(9, 9), Vector2i(9, 9), 5), g.cells_in_radius(Vector2i(9, 9), 1), kind)


func test_deterministic_and_stable() -> void:
	# Mismas entradas -> misma lista; referencia fija para detectar cambios
	# de la geometría en cualquier plataforma (escritorio y web).
	var p: SystemProfile = _profile("dnd5e_2024")
	var g: GridGeometry = _grid("hex_pointy")
	var a: Array[Vector2i] = _cells(p, g, "cone", Vector2i(10, 10), Vector2i(17, 13), 30)
	var b: Array[Vector2i] = _cells(p, g, "cone", Vector2i(10, 10), Vector2i(17, 13), 30)
	assert_eq(a, b)
	assert_gt(a.size(), 0)
