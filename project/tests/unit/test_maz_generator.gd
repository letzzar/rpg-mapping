extends GutTest
## Tests de propiedades de MAZ G1 (core/gen/maz) con muchas semillas y en las
## tres rejillas: conectividad desde la entrada, nº de salidas, sin salas
## vacías ni aisladas, rasgos sobre suelo, bordes cerrados y determinismo.
##
## También genera las seeds doradas PROPUESTAS (aún no grabadas: el esquema
## MAZ G1 está pendiente de aprobación) e imprime "<código> <sha256>" para
## copiarlas a tests/golden/golden_seeds.txt cuando se aprueben.

const LAYOUTS: PackedStringArray = ["built", "cave", "mixed"]


func after_each() -> void:
	GeneratorRegistry.reset()


func _code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	var sc: SeedCode = SeedCode.create(system, "MAZ", 1, params, seed_value)
	assert_true(sc.is_valid(), "%s %s" % [sc.error, sc.error_field])
	return sc.encode()


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "", code)
	return res.doc


## Problemas de un documento generado (vacío = correcto).
func _problems(doc: MapDocument, code: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var sc: SeedCode = SeedCode.parse(code)
	var exits: int = sc.params["exits"]
	var levels: int = sc.params["levels"]
	var rooms_max: int = sc.params["rooms"]
	var grid: GridGeometry = doc.grid
	if doc.level_count() != levels:
		out.append("niveles: %d" % doc.level_count())
		return out
	# Entrada y salidas (solo nivel 0).
	var entrance: Vector2i = Vector2i(-1, -1)
	var entrances: int = 0
	var exit_count: int = 0
	for li: int in levels:
		var level: MapLevel = doc.level(li)
		var room_count: int = 0
		for r: MapRoom in level.rooms:
			var cells: Array[Vector2i] = level.room_cells(r.id)
			if cells.is_empty():
				out.append("nivel %d: zona %d vacía" % [li, r.id])
				continue
			if r.kind == MapRoom.KIND_ROOM or r.kind == MapRoom.KIND_CAVE:
				room_count += 1
			elif r.kind == MapRoom.KIND_ENTRANCE or r.kind == MapRoom.KIND_EXIT:
				if li != 0:
					out.append("salida fuera del nivel 0")
				if cells.size() != 1 or not _on_border(grid, cells[0]):
					out.append("salida %d no es una casilla del borde" % r.id)
				if r.kind == MapRoom.KIND_ENTRANCE:
					entrances += 1
					entrance = cells[0]
				else:
					exit_count += 1
			else:
				out.append("tipo de zona inesperado: " + r.kind)
		var forced: int = (1 if li > 0 else 0) + (1 if li < levels - 1 else 0)
		if room_count < 1 or room_count > maxi(rooms_max, forced):
			out.append("nivel %d: %d salas" % [li, room_count])
		# Borde: solo las salidas son transitables.
		for i: int in grid.cell_count():
			var c: Vector2i = grid.cell_at(i)
			if _on_border(grid, c) and Terrain.is_passable(level.terrain[i]):
				var kind: String = level.room(level.room_ids[i]).kind if level.room_ids[i] != 0 else ""
				if kind != MapRoom.KIND_ENTRANCE and kind != MapRoom.KIND_EXIT:
					out.append("nivel %d: suelo en el borde %s" % [li, c])
		# Rasgos sobre suelo.
		for t: MapTrap in level.traps:
			if not Terrain.is_passable(level.get_terrain(t.cell)) or level.get_room_id(t.cell) == 0:
				out.append("trampa fuera de una sala en %s" % t.cell)
			if not level.stairs_at(t.cell).is_empty():
				out.append("trampa sobre escalera en %s" % t.cell)
		for o: MapObject in level.objects:
			for c: Vector2i in level.object_cells(o):
				if not Terrain.is_passable(level.get_terrain(c)):
					out.append("objeto %d en la roca" % o.id)
		for s: MapStair in level.stairs:
			var other: MapLevel = doc.level(s.to_level)
			if other == null or absi(s.to_level - li) != 1 or s.to_cell != s.cell:
				out.append("escalera %d mal enlazada" % s.id)
				continue
			if not Terrain.is_passable(level.get_terrain(s.cell)) or not Terrain.is_passable(other.get_terrain(s.to_cell)):
				out.append("escalera %d en la roca" % s.id)
		# Aristas: solo entre casillas, al menos una transitable, valor válido.
		for id: int in level.edge_ids():
			var cells2: Array[Vector2i] = grid.edge_cells(id)
			var v: int = level.get_edge_by_id(id)
			if not MapEdge.is_valid(v):
				out.append("arista no válida")
			if not (Terrain.is_passable(level.get_terrain(cells2[0])) and Terrain.is_passable(level.get_terrain(cells2[1]))):
				out.append("arista junto a la roca en %s" % cells2[0])
	var stair_total: int = 0
	for l: MapLevel in doc.levels:
		stair_total += l.stairs.size()
	if stair_total != 2 * (levels - 1):
		out.append("escaleras: %d" % stair_total)
	if entrances != 1 or exit_count != exits - 1:
		out.append("entradas %d, salidas %d (se pedían %d en total)" % [entrances, exit_count, exits])
		return out
	var missing: int = Connectivity.unreachable_count(doc, 0, entrance)
	if missing != 0:
		out.append("%d casillas transitables inaccesibles desde la entrada" % missing)
	return out


func _on_border(grid: GridGeometry, c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 or c.x == grid.width - 1 or c.y == grid.height - 1


func _check(params: Dictionary, seed_value: int, system: String = "DND5") -> MapDocument:
	var code: String = _code(params, seed_value, system)
	var doc: MapDocument = _gen(code)
	if doc == null:
		return null
	assert_eq(_problems(doc, code), PackedStringArray(), code)
	var again: MapDocument = _gen(code)
	assert_eq(again.content_hash(), doc.content_hash(), "determinismo: " + code)
	return doc


# --- Propiedades ----------------------------------------------------------------

func test_registered() -> void:
	assert_true(GeneratorRegistry.has_generator("MAZ", 1))
	assert_eq(ParamSchemaRegistry.maz_g1().validate(), "")


func test_properties_many_seeds_all_grids_and_layouts() -> void:
	for kind: String in GridGeometry.KINDS:
		for layout: String in LAYOUTS:
			for s: int in [1, 2, 3, 0xDEADBEEF]:
				var doc: MapDocument = _check({"grid": kind, "layout": layout, "rooms": 6}, s)
				if doc != null:
					assert_eq(doc.grid_kind(), kind)
					assert_eq(doc.width(), 32, "rooms 6 -> small")


func test_levels_exits_and_stairs() -> void:
	for kind: String in GridGeometry.KINDS:
		for s: int in [7, 8]:
			var doc: MapDocument = _check({"grid": kind, "layout": "mixed", "rooms": 5, "levels": 3, "exits": 4}, s)
			if doc == null:
				continue
			# La misma casilla arriba y abajo (plantas coherentes).
			for s0: MapStair in doc.level(0).stairs:
				assert_eq(doc.level(1).stairs_at(s0.cell).size(), 1)


func test_defaults_and_sizes() -> void:
	var doc: MapDocument = _check({}, 42)
	if doc != null:
		assert_eq(doc.width(), 48, "12 salas -> medium")
		assert_eq(doc.height(), 36)
		assert_eq(doc.scale, "MAZ")
		assert_eq(doc.gen_version, 1)
	var tight: MapDocument = _check({"rooms": 64, "size": "small"}, 5)
	if tight != null:
		assert_eq(tight.width(), 32)
	var huge: MapDocument = _check({"rooms": 40, "layout": "mixed", "style": "elf"}, 9)
	if huge != null:
		assert_eq(huge.width(), 96)
	assert_eq(MazGeneratorG1.map_size("auto", 6), Vector2i(32, 24))
	assert_eq(MazGeneratorG1.map_size("auto", 7), Vector2i(48, 36))
	assert_eq(MazGeneratorG1.map_size("auto", 29), Vector2i(96, 72))
	assert_eq(MazGeneratorG1.map_size("large", 1), Vector2i(64, 48))


func test_styles_and_single_room() -> void:
	for style: String in MazGeneratorG1.STYLE_IDS:
		_check({"style": style, "rooms": 6, "layout": "mixed"}, 3)
	var one: MapDocument = _check({"rooms": 1, "corridor_pct": 0}, 4)
	if one != null:
		var rooms: int = 0
		for r: MapRoom in one.level(0).rooms:
			if r.kind == MapRoom.KIND_ROOM:
				rooms += 1
		assert_eq(rooms, 1)


func test_seed_changes_output() -> void:
	var a: MapDocument = _gen(_code({"rooms": 6}, 1))
	var b: MapDocument = _gen(_code({"rooms": 6}, 2))
	if a != null and b != null:
		assert_ne(a.content_hash(), b.content_hash())


func test_densities() -> void:
	for kind: String in GridGeometry.KINDS:
		var dense: MapDocument = _check({"grid": kind, "rooms": 8, "trap_density": 10, "secret_door_density": 10}, 21)
		var none: MapDocument = _check({"grid": kind, "rooms": 8, "trap_density": 0, "secret_door_density": 0}, 21)
		if dense == null or none == null:
			continue
		var rooms: int = 0
		for r: MapRoom in dense.level(0).rooms:
			if r.kind == MapRoom.KIND_ROOM:
				rooms += 1
		assert_eq(dense.level(0).traps.size(), rooms, "1 trampa por sala con densidad 10")
		assert_true(_count_edges(dense.level(0), MapEdge.KIND_SECRET_DOOR) >= 1)
		assert_true(_count_edges(dense.level(0), MapEdge.KIND_DOOR) + _count_edges(dense.level(0), MapEdge.KIND_SECRET_DOOR) >= 1)
		assert_eq(none.level(0).traps.size(), 0)
		assert_eq(_count_edges(none.level(0), MapEdge.KIND_SECRET_DOOR), 0)


func test_cave_layout_has_caves_and_no_inner_walls() -> void:
	var doc: MapDocument = _check({"layout": "cave", "rooms": 6, "grid": "hex_pointy"}, 31)
	if doc == null:
		return
	for r: MapRoom in doc.level(0).rooms:
		assert_true(r.kind != MapRoom.KIND_ROOM, "en cueva no hay salas construidas")


func _count_edges(level: MapLevel, kind: int) -> int:
	var n: int = 0
	for id: int in level.edge_ids():
		if MapEdge.kind_of(level.get_edge_by_id(id)) == kind:
			n += 1
	return n


# --- Seeds doradas propuestas (pendientes de aprobar el esquema) ---------------

## [sistema, parámetros, semilla]: cubre las tres rejillas, los tres tipos,
## varios niveles, salidas, densidades, estilos, tamaños y una semilla corta.
static func proposals() -> Array:
	return [
		["DND5", {}, 0x8F3A21C4D5],
		["DND5", {"layout": "cave"}, 0x93B0C1D2E3],
		["DND5", {"layout": "mixed", "levels": 2}, 0xA1B2C3D4E5],
		["PF2E", {"grid": "hex_flat"}, 0xB4C5D6E7F8],
		["PF2E", {"grid": "hex_flat", "layout": "cave", "rooms": 8}, 0xC0FFEE1234],
		["DND5", {"grid": "hex_flat", "layout": "mixed", "exits": 3, "style": "elf"}, 0xD00DFEED42],
		["DND5", {"grid": "hex_pointy", "levels": 3, "trap_density": 6, "secret_door_density": 5}, 0xE1E2E3E4E5],
		["PF2E", {"grid": "hex_pointy", "layout": "cave", "size": "small", "rooms": 6}, 0xF0E1D2C3B4],
		["DND5", {"grid": "hex_pointy", "layout": "mixed", "corridor_pct": 60, "style": "dwarf"}, 0x8123456789],
		["DND5", {"rooms": 24, "size": "large", "exits": 4, "levels": 2, "style": "dwarf"}, 0x9ABCDEF012],
		["PF2E", {"rooms": 1, "corridor_pct": 0, "trap_density": 0, "secret_door_density": 0}, 42],
	]


func test_proposed_golden_seeds() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for item: Variant in proposals():
		var entry: Array = item
		var system: String = entry[0]
		var params: Dictionary = entry[1]
		var seed_value: int = entry[2]
		var doc: MapDocument = _check(params, seed_value, system)
		if doc != null:
			lines.append("%s %s" % [doc.seed_code, doc.content_hash()])
	assert_eq(lines.size(), proposals().size())
	print("MAZ_GOLDEN_PROPOSALS_BEGIN\n%s\nMAZ_GOLDEN_PROPOSALS_END" % "\n".join(lines))


## Vista ASCII para revisión (se imprime en el log de los tests):
## '#' roca, '.' sala, ':' cueva, ',' pasillo, '@' entrada, 'E' salida,
## '>' escalera, '^' trampa. En hex_pointy las filas impares van desplazadas.
static func ascii(doc: MapDocument, level_index: int) -> String:
	var level: MapLevel = doc.level(level_index)
	var grid: GridGeometry = doc.grid
	var rows: PackedStringArray = PackedStringArray()
	for y: int in grid.height:
		var row: String = " " if grid.kind == GridGeometry.KIND_HEX_POINTY and y % 2 == 1 else ""
		for x: int in grid.width:
			var c: Vector2i = Vector2i(x, y)
			var ch: String = "#"
			if Terrain.is_passable(level.get_terrain(c)):
				var rid: int = level.get_room_id(c)
				ch = ","
				if rid != 0:
					match level.room(rid).kind:
						MapRoom.KIND_ROOM:
							ch = "."
						MapRoom.KIND_CAVE:
							ch = ":"
						MapRoom.KIND_ENTRANCE:
							ch = "@"
						MapRoom.KIND_EXIT:
							ch = "E"
			if not level.stairs_at(c).is_empty():
				ch = ">"
			elif not level.traps_at(c).is_empty():
				ch = "^"
			row += ch + (" " if grid.kind == GridGeometry.KIND_HEX_POINTY else "")
		rows.append(row)
	return "\n".join(rows)


func test_print_ascii_samples() -> void:
	for kind: String in GridGeometry.KINDS:
		var code: String = _code({"grid": kind, "layout": "mixed", "rooms": 6}, 1)
		var doc: MapDocument = _gen(code)
		if doc != null:
			print("%s\n%s\n" % [code, ascii(doc, 0)])
	pass_test("ASCII impreso")
