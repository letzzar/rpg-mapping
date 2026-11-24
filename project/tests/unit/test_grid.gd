extends GutTest
## Tests de core/grid: geometría cuadrada, hex_flat y hex_pointy (ADR 012, 017).


func _grid(kind: String, w: int = 9, h: int = 8) -> GridGeometry:
	var g: GridGeometry = GridFactory.create(kind, w, h)
	assert_not_null(g, kind)
	return g


func _all_grids() -> Array[GridGeometry]:
	var out: Array[GridGeometry] = []
	for k: String in GridGeometry.KINDS:
		out.append(_grid(k))
	return out


## Casillas de muestra con todas las paridades de fila y columna.
func _sample_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(2, 6):
		for x: int in range(2, 6):
			out.append(Vector2i(x, y))
	return out


func test_factory() -> void:
	assert_eq(_grid("square").kind, GridGeometry.KIND_SQUARE)
	assert_eq(_grid("hex_flat").kind, GridGeometry.KIND_HEX_FLAT)
	assert_eq(_grid("hex_pointy").kind, GridGeometry.KIND_HEX_POINTY)
	assert_null(GridFactory.create("triangle", 4, 4))
	assert_null(GridFactory.create("square", 0, 4))
	assert_null(GridFactory.create("square", 4, GridGeometry.MAX_SIDE + 1))
	var g: GridGeometry = _grid("square", 5, 3)
	assert_eq(g.cell_count(), 15)
	assert_eq(g.index_of(Vector2i(4, 2)), 14)
	assert_eq(g.index_of(Vector2i(5, 0)), -1)
	assert_eq(g.cell_at(7), Vector2i(2, 1))


func test_square_neighbor_order() -> void:
	var g: GridGeometry = _grid("square")
	var expected: Array[Vector2i] = [
		Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5),
		Vector2i(6, 4), Vector2i(6, 6), Vector2i(4, 6), Vector2i(4, 4),
	]
	assert_eq(g.neighbors(Vector2i(5, 5)), expected)
	var corner: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	assert_eq(g.neighbors(Vector2i(0, 0)), corner)
	assert_eq(g.neighbors(Vector2i(0, 0), true).size(), 8)
	for d: int in 4:
		assert_eq(g.step_kind(d), GridGeometry.STEP_ORTHOGONAL)
		assert_eq(g.diagonal_components(d).size(), 0)
	for d: int in range(4, 8):
		assert_eq(g.step_kind(d), GridGeometry.STEP_DIAGONAL)
	# NE = N + E, SW = S + W.
	assert_eq(g.diagonal_components(4), PackedInt32Array([0, 1]))
	assert_eq(g.diagonal_components(6), PackedInt32Array([2, 3]))


## Valores de referencia de Red Blob Games (odd-q y odd-r).
func test_hex_neighbor_order() -> void:
	var flat: GridGeometry = _grid("hex_flat")
	var even_q: Array[Vector2i] = [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 2), Vector2i(1, 1),
	]
	assert_eq(flat.neighbors(Vector2i(2, 2)), even_q)
	var odd_q: Array[Vector2i] = [
		Vector2i(3, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(3, 3), Vector2i(2, 3), Vector2i(2, 2),
	]
	assert_eq(flat.neighbors(Vector2i(3, 2)), odd_q)
	var pointy: GridGeometry = _grid("hex_pointy")
	var even_r: Array[Vector2i] = [
		Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 2), Vector2i(1, 1),
	]
	assert_eq(pointy.neighbors(Vector2i(2, 2)), even_r)
	var odd_r: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 3), Vector2i(2, 2),
	]
	assert_eq(pointy.neighbors(Vector2i(2, 3)), odd_r)
	for d: int in 6:
		assert_eq(flat.step_kind(d), GridGeometry.STEP_HEX)
		assert_eq(pointy.diagonal_components(d).size(), 0)


func test_opposites_and_direction_between() -> void:
	for g: GridGeometry in _all_grids():
		for c: Vector2i in _sample_cells():
			for d: int in g.direction_count():
				var n: Vector2i = g.neighbor(c, d)
				assert_eq(g.neighbor(n, g.opposite(d)), c, "%s %s dir %d" % [g.kind, c, d])
				assert_eq(g.direction_between(c, n), d)
				assert_eq(g.distance(c, n), 1)
		assert_eq(g.direction_between(Vector2i(2, 2), Vector2i(6, 6)), -1)


func test_distance_and_step_counts() -> void:
	var sq: GridGeometry = _grid("square")
	assert_eq(sq.distance(Vector2i(0, 0), Vector2i(3, 5)), 5)
	assert_eq(sq.step_counts(Vector2i(0, 0), Vector2i(3, 5)), PackedInt32Array([2, 3, 0]))
	assert_eq(sq.step_counts(Vector2i(4, 1), Vector2i(0, 1)), PackedInt32Array([4, 0, 0]))
	for k: String in [GridGeometry.KIND_HEX_FLAT, GridGeometry.KIND_HEX_POINTY]:
		var hx: GridGeometry = _grid(k)
		# Recto por una fila en pointy / zigzag por la fila en flat: 4 pasos.
		assert_eq(hx.distance(Vector2i(0, 0), Vector2i(4, 0)), 4, k)
		assert_eq(hx.step_counts(Vector2i(0, 0), Vector2i(4, 0)), PackedInt32Array([0, 0, 4]))
		# Simetría y desigualdad triangular en todo el mapa de muestra.
		for a: Vector2i in _sample_cells():
			for b: Vector2i in _sample_cells():
				assert_eq(hx.distance(a, b), hx.distance(b, a))
				assert_true(hx.distance(a, b) <= hx.distance(a, Vector2i(0, 0)) + hx.distance(Vector2i(0, 0), b))


func test_cells_in_radius() -> void:
	var big: int = 40
	var sq: GridGeometry = _grid("square", big, big)
	assert_eq(sq.cells_in_radius(Vector2i(20, 20), 2).size(), 25)
	for k: String in [GridGeometry.KIND_HEX_FLAT, GridGeometry.KIND_HEX_POINTY]:
		var hx: GridGeometry = _grid(k, big, big)
		for r: int in 5:
			# 1 + 3r(r+1) hexágonos, con el centro en columna/fila par e impar.
			assert_eq(hx.cells_in_radius(Vector2i(20, 20), r).size(), 1 + 3 * r * (r + 1), "%s r=%d" % [k, r])
			assert_eq(hx.cells_in_radius(Vector2i(21, 21), r).size(), 1 + 3 * r * (r + 1))
	# Recorte al mapa y orden por filas.
	var clipped: Array[Vector2i] = sq.cells_in_radius(Vector2i(0, 0), 1)
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	assert_eq(clipped, expected)
	assert_eq(sq.cells_in_radius(Vector2i(0, 0), 1, false).size(), 9)


func test_square_line_reference() -> void:
	var g: GridGeometry = _grid("square")
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 2), Vector2i(4, 2)]
	assert_eq(g.line(Vector2i(0, 0), Vector2i(4, 2)), expected)
	var single: Array[Vector2i] = [Vector2i(3, 3)]
	assert_eq(g.line(Vector2i(3, 3), Vector2i(3, 3)), single)


func test_lines_are_contiguous_and_symmetric() -> void:
	for g: GridGeometry in _all_grids():
		for a: Vector2i in _sample_cells():
			for b: Vector2i in [Vector2i(0, 0), Vector2i(8, 7), Vector2i(8, 0), Vector2i(0, 7), Vector2i(5, 1), Vector2i(1, 6)]:
				var l: Array[Vector2i] = g.line(a, b)
				assert_eq(l.size(), g.distance(a, b) + 1, "%s %s-%s" % [g.kind, a, b])
				assert_eq(l[0], a)
				assert_eq(l[l.size() - 1], b)
				for i: int in range(1, l.size()):
					assert_eq(g.distance(l[i - 1], l[i]), 1, "%s %s-%s paso %d" % [g.kind, a, b, i])
				var back: Array[Vector2i] = g.line(b, a)
				back.reverse()
				assert_eq(back, l)


func test_edges_are_canonical() -> void:
	for g: GridGeometry in _all_grids():
		for c: Vector2i in _sample_cells():
			for d: int in g.edge_direction_count():
				var n: Vector2i = g.neighbor(c, d)
				var id: int = g.edge_id(c, d)
				assert_eq(g.edge_id(n, g.opposite(d)), id, "%s %s dir %d" % [g.kind, c, d])
				var e: Vector3i = g.edge_from_id(id)
				assert_true(e.z < g.edge_direction_count() / 2)
				assert_eq(g.edge_id(Vector2i(e.x, e.y), e.z), id)
				var cells: Array[Vector2i] = g.edge_cells(id)
				assert_true(cells.has(c) and cells.has(n))
	# Borde oeste de la cuadrada: la dueña es (-1, 0), lado E.
	var sq: GridGeometry = _grid("square", 3, 3)
	var west: int = sq.edge_id(Vector2i(0, 0), 3)
	assert_eq(sq.edge_from_id(west), Vector3i(-1, 0, 1))
	assert_true(sq.edge_touches_map(west))
	assert_false(sq.edge_touches_map(sq.edge_id(Vector2i(-1, -1), 1)))


func test_footprints() -> void:
	var sq: GridGeometry = _grid("square")
	assert_eq(sq.footprint(Vector2i(2, 2), 1).size(), 1)
	var large: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]
	assert_eq(sq.footprint(Vector2i(2, 2), 2), large)
	assert_eq(sq.footprint(Vector2i(2, 2), 3).size(), 9)
	# La cuadrada ignora hex_cells; la hex ignora el lado.
	assert_eq(sq.footprint(Vector2i(2, 2), 2, 19), large)
	var hx: GridGeometry = _grid("hex_flat")
	assert_eq(hx.footprint(Vector2i(4, 4), 4, 1).size(), 1)
	var tri_flat: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]
	assert_eq(hx.footprint(Vector2i(4, 4), 2, 3), tri_flat)
	var hp: GridGeometry = _grid("hex_pointy")
	var tri_pointy: Array[Vector2i] = [Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]
	assert_eq(hp.footprint(Vector2i(4, 4), 2, 3), tri_pointy)
	for g: GridGeometry in [hx, hp]:
		assert_eq(g.footprint(Vector2i(4, 4), 3, 7).size(), 7)
		assert_eq(g.footprint(Vector2i(4, 4), 4, 19).size(), 19)
		# Triángulo: los tres hexágonos se tocan entre sí.
		var t: Array[Vector2i] = g.footprint(Vector2i(3, 3), 2, 3)
		assert_eq(g.distance(t[0], t[1]), 1)
		assert_eq(g.distance(t[1], t[2]), 1)
		assert_eq(g.distance(t[0], t[2]), 1)
	# Con el perfil: grande = 3 hex, enorme = 7, gargantuesca = 19.
	var p: SystemProfile = SystemProfile.load_id("dnd5e_2024")
	assert_eq(p.size_hex_cells_of("medium"), 1)
	assert_eq(p.size_hex_cells_of("large"), 3)
	assert_eq(p.size_hex_cells_of("huge"), 7)
	assert_eq(p.size_hex_cells_of("gargantuan"), 19)
	assert_eq(p.size_hex_cells_of("no_existe"), 1)


func test_floor_and_round_div() -> void:
	assert_eq(GridGeometry.floor_div(-3, 2), -2)
	assert_eq(GridGeometry.floor_div(3, 2), 1)
	assert_eq(GridGeometry.floor_div(-4, 2), -2)
	assert_eq(GridGeometry.round_div(1, 2), 1)
	assert_eq(GridGeometry.round_div(-1, 2), 0)
	assert_eq(GridGeometry.round_div(5, 4), 1)
	assert_eq(GridGeometry.round_div(-7, 4), -2)


## Conversión casilla <-> píxel (solo vistas): ida y vuelta por el centro y
## por puntos cerca del centro; aristas sobre esquinas del polígono.
func test_pixel_conversion_roundtrip() -> void:
	var px: float = 32.0
	for g: GridGeometry in _all_grids():
		var size: Vector2 = g.map_pixel_size(px)
		assert_true(size.x > 0.0 and size.y > 0.0)
		for y: int in g.height:
			for x: int in g.width:
				var c: Vector2i = Vector2i(x, y)
				var center: Vector2 = g.cell_to_pixel(c, px)
				assert_eq(g.pixel_to_cell(center, px), c, "%s %s" % [g.kind, c])
				assert_eq(g.pixel_to_cell(center + Vector2(px * 0.3, -px * 0.2), px), c)
				assert_true(center.x > 0.0 and center.y > 0.0 and center.x < size.x and center.y < size.y)
		var c0: Vector2i = Vector2i(3, 3)
		var poly: PackedVector2Array = g.cell_polygon(c0, px)
		for d: int in g.edge_direction_count():
			var seg: PackedVector2Array = g.edge_segment(c0, d, px)
			assert_eq(seg.size(), 2)
			for p: Vector2 in seg:
				var on_corner: bool = false
				for q: Vector2 in poly:
					if p.distance_to(q) < 0.01:
						on_corner = true
				assert_true(on_corner, "%s dir %d" % [g.kind, d])
