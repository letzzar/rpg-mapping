extends GutTest
## Tests de EST G3 (core/gen/est/est_generator_g3.gd): estancia en blanco,
## base del editor de estancias (PROYECTO §6.5 y §6.7, E2).
##
## Esquema (ida y vuelta, defectos, rangos, ids), forma del mapa (anillo de
## muro, interior de suelo, una entrada en el centro de la pared de abajo),
## conectividad desde la entrada en las tres rejillas y en todos los tamaños
## extremos, independencia de la semilla y apertura con
## GeneratorRegistry.generate(). Imprime los códigos de ejemplo y un ASCII
## (EST_G3_EXAMPLES).

const GRIDS: PackedStringArray = ["square", "hex_flat", "hex_pointy"]


func after_each() -> void:
	GeneratorRegistry.reset()


func _gen(code: String) -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "", code)
	return res.doc


# --- Esquema -------------------------------------------------------------------------

func test_schema_fields_and_defaults() -> void:
	var s: ParamSchema = ParamSchemaRegistry.get_schema("EST", 3)
	assert_not_null(s)
	if s == null:
		return
	assert_eq(s.validate(), "")
	assert_eq(s.field_keys(), PackedStringArray(["width", "height", "grid", "room_type"]))
	var w: ParamSchema.Field = s.fields[0]
	var h: ParamSchema.Field = s.fields[1]
	assert_eq([w.kind, w.min_value, w.max_value, w.default_value], [ParamSchema.KIND_INT, 3, 48, 9])
	assert_eq([h.kind, h.min_value, h.max_value, h.default_value], [ParamSchema.KIND_INT, 3, 48, 7])
	assert_eq(s.fields[2].ids, PackedStringArray(["square", "hex_flat", "hex_pointy"]))
	assert_eq(s.fields[2].capacity, 4)
	var rt: ParamSchema.Field = s.fields[3]
	assert_eq(rt.ids[0], MapRoom.KIND_ROOM)
	assert_eq(rt.capacity, 64)
	# Después de "room", los ids de EST G1 en su mismo orden.
	var g1: ParamSchema = ParamSchemaRegistry.get_schema("EST", 1)
	assert_eq(rt.ids.slice(1), g1.fields[0].ids)
	assert_true(rt.capacity >= g1.fields[0].capacity + 1)
	var d: Dictionary = s.default_values()
	assert_eq(d, {"width": 9, "height": 7, "grid": "square", "room_type": "room"})
	# Todo por defecto = "0"; las otras versiones de EST no cambian.
	assert_eq(s.resolve({}).text, "0")
	assert_true(GeneratorRegistry.has_generator("EST", 1))
	assert_true(GeneratorRegistry.has_generator("EST", 2))
	assert_true(GeneratorRegistry.has_generator("EST", 3))
	# Nombres visibles de todos los tipos (ROOM_KIND_*).
	var es: Translation = load("res://i18n/strings.es.translation")
	for id: String in rt.ids:
		assert_ne(String(es.get_message("ROOM_KIND_%s" % id.to_upper())), "", id)


func test_schema_round_trip_and_ranges() -> void:
	var cases: Array[Dictionary] = [
		{},
		{"width": 3, "height": 3},
		{"width": 48, "height": 48},
		{"width": 12, "height": 10, "grid": "hex_flat"},
		{"width": 3, "height": 48, "grid": "hex_pointy", "room_type": "guardroom"},
		{"width": 48, "height": 3, "grid": "hex_flat", "room_type": "crypt"},
		{"room_type": "tavern"},
	]
	var max_len: int = 0
	for params: Dictionary in cases:
		for seed_value: int in [0, 1, 0xFFFFFFFFFF]:
			var sc: SeedCode = SeedCode.create("DND5", "EST", 3, params, seed_value)
			assert_true(sc.is_valid(), "%s %s %s" % [params, sc.error, sc.error_field])
			var code: String = sc.encode()
			var back: SeedCode = SeedCode.parse(code)
			assert_true(back.is_valid(), code)
			assert_eq(back.encode(), code)
			assert_eq([back.scale, back.gen_version, back.seed_value], ["EST", 3, seed_value])
			for k: String in params.keys():
				var got: Variant = back.params[k]
				var want: Variant = params[k]
				# var_to_str distingue tipos (9 frente a "9") y evita comparar Variant sin tipo.
				assert_eq(var_to_str(got), var_to_str(want), "%s %s" % [code, k])
			max_len = maxi(max_len, code.split("-")[4].length())
	# Con todos los campos usados, PARAMS ocupa como mucho 4 caracteres.
	assert_true(max_len <= 4, "PARAMS de %d caracteres" % max_len)
	# Rangos y tipos.
	for bad: Dictionary in [{"width": 2}, {"width": 49}, {"height": 2}, {"height": 49}]:
		var sc2: SeedCode = SeedCode.create("DND5", "EST", 3, bad, 0)
		assert_eq(sc2.error, "SEED_ERR_PARAM_RANGE", str(bad))
	assert_eq(SeedCode.create("DND5", "EST", 3, {"grid": "octo"}, 0).error, "SEED_ERR_PARAM_ENUM")
	assert_eq(SeedCode.create("DND5", "EST", 3, {"room_type": "dungeon"}, 0).error, "SEED_ERR_PARAM_ENUM")
	assert_eq(SeedCode.create("DND5", "EST", 3, {"width": "9"}, 0).error, "SEED_ERR_PARAM_TYPE")
	assert_eq(SeedCode.create("DND5", "EST", 3, {"size": "small"}, 0).error, "SEED_ERR_PARAM_UNKNOWN")


func test_canonical_code() -> void:
	var def: String = EstGeneratorG3.canonical_code("DND5", 9, 7, "square")
	assert_true(def.begins_with("RPGM1-DND5-EST-G3-0-0-"), def)
	var hex: String = EstGeneratorG3.canonical_code("DND5", 12, 10, "hex_flat")
	var sc: SeedCode = SeedCode.parse(hex)
	assert_true(sc.is_valid(), hex)
	assert_eq(sc.seed_value, EstGeneratorG3.CANONICAL_SEED)
	assert_eq([sc.params["width"], sc.params["height"], sc.params["grid"], sc.params["room_type"]], [12, 10, "hex_flat", "room"])
	var typed: SeedCode = SeedCode.parse(EstGeneratorG3.canonical_code("PF2E", 5, 4, "hex_pointy", "crypt"))
	assert_eq([typed.system, typed.params["room_type"]], ["PF2E", "crypt"])
	assert_eq(EstGeneratorG3.canonical_code("DND5", 2, 7, "square"), "")
	assert_eq(EstGeneratorG3.canonical_code("DND5", 9, 7, "square", "dungeon"), "")


# --- Mapa -----------------------------------------------------------------------------

## Problemas de una estancia en blanco (vacío = correcta).
func _problems(doc: MapDocument, w: int, h: int, room_type: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		out.append("sin documento")
		return out
	if doc.level_count() != 1:
		out.append("niveles: %d" % doc.level_count())
		return out
	var grid: GridGeometry = doc.grid
	if grid.width != w + 2 or grid.height != h + 2:
		out.append("tamaño %d×%d" % [grid.width, grid.height])
		return out
	var level: MapLevel = doc.level(0)
	if level.rooms.size() != 2 or level.rooms[0].kind != room_type or level.rooms[1].kind != MapRoom.KIND_ENTRANCE:
		out.append("zonas inesperadas")
		return out
	if not level.objects.is_empty() or not level.stairs.is_empty():
		out.append("objetos o escaleras")
	var room_id: int = level.rooms[0].id
	var landing: Vector2i = EstGeneratorG3.landing_cell(w, h)
	var entry: Vector2i = EstGeneratorG3.entry_cell(w, h)
	var room_cells: int = 0
	for i: int in grid.cell_count():
		var c: Vector2i = grid.cell_at(i)
		var inside: bool = c.x >= 1 and c.x <= w and c.y >= 1 and c.y <= h
		var t: int = level.terrain[i]
		if inside:
			room_cells += 1
			if t != Terrain.FLOOR or level.room_ids[i] != room_id:
				out.append("interior %s" % c)
		elif c == landing:
			if t != Terrain.FLOOR or level.room_ids[i] != level.rooms[1].id:
				out.append("rellano %s" % c)
		elif t != Terrain.WALL:
			out.append("anillo %s" % c)
	if room_cells != w * h:
		out.append("casillas %d" % room_cells)
	# Puerta en el centro de la pared de abajo.
	if entry.x != 1 + (w - 1) / 2 or entry.y != h:
		out.append("entrada %s" % entry)
	var doors: int = 0
	for i: int in grid.cell_count():
		var c2: Vector2i = grid.cell_at(i)
		for d: int in grid.edge_direction_count():
			var n: Vector2i = grid.neighbor(c2, d)
			if not grid.in_bounds(n) or grid.index_of(n) < i:
				continue
			var e: int = level.get_edge(c2, d)
			if MapEdge.kind_of(e) == MapEdge.KIND_DOOR:
				doors += 1
				if not ((c2 == entry and n == landing) or (c2 == landing and n == entry)):
					out.append("puerta fuera de sitio %s-%s" % [c2, n])
	if doors != 1:
		out.append("puertas: %d" % doors)
	if Connectivity.unreachable_count(doc, 0, landing) != 0:
		out.append("casillas inaccesibles desde la entrada")
	return out


func test_blank_rooms_all_grids_and_sizes() -> void:
	var sizes: Array[Vector2i] = [Vector2i(9, 7), Vector2i(3, 3), Vector2i(48, 48), Vector2i(3, 48), Vector2i(48, 3),
		Vector2i(4, 4), Vector2i(12, 10), Vector2i(5, 8), Vector2i(10, 5)]
	var checked: int = 0
	for g: String in GRIDS:
		for sz: Vector2i in sizes:
			var code: String = EstGeneratorG3.canonical_code("DND5", sz.x, sz.y, g)
			var doc: MapDocument = _gen(code)
			var probs: PackedStringArray = _problems(doc, sz.x, sz.y, MapRoom.KIND_ROOM)
			assert_true(probs.is_empty(), "%s: %s" % [code, ", ".join(probs)])
			checked += 1
	assert_eq(checked, GRIDS.size() * 9)


## Todas las anchuras y alturas en las tres rejillas: el suelo se alcanza
## desde la entrada (pasos por arista; la puerta es el único hueco).
func test_connectivity_exhaustive() -> void:
	var failures: int = 0
	for g: String in GRIDS:
		for w: int in range(3, 49, 3):
			for h: int in range(3, 49, 5):
				var p: EstGeneratorG3.Params = EstGeneratorG3.Params.new()
				p.width = w
				p.height = h
				p.grid_kind = g
				var doc: MapDocument = EstGeneratorG3.generate_blank(p)
				if doc == null or Connectivity.unreachable_count(doc, 0, EstGeneratorG3.landing_cell(w, h)) != 0:
					failures += 1
	assert_eq(failures, 0)


func test_room_type_and_seed_independence() -> void:
	var typed: MapDocument = _gen(EstGeneratorG3.canonical_code("DND5", 6, 5, "hex_pointy", "crypt"))
	assert_true(_problems(typed, 6, 5, "crypt").is_empty())
	# La semilla no cambia el contenido (solo el código, que no es canónico).
	var base: String = EstGeneratorG3.canonical_code("DND5", 12, 10, "hex_flat")
	var a: MapDocument = _gen(base)
	var other: SeedCode = SeedCode.create("DND5", "EST", 3, {"width": 12, "height": 10, "grid": "hex_flat"}, 0x9ABCDEF012)
	var b: MapDocument = _gen(other.encode())
	if a == null or b == null:
		return
	b.seed_code = a.seed_code
	assert_eq(a.content_hash(), b.content_hash())
	# Determinista: dos veces lo mismo.
	assert_eq(_gen(base).content_hash(), a.content_hash())
	assert_eq([a.scale, a.gen_version, a.seed_code], ["EST", 3, base])


func test_print_examples() -> void:
	var lines: PackedStringArray = PackedStringArray(["EST_G3_EXAMPLES"])
	for args: Array in [[9, 7, "square"], [12, 10, "hex_flat"], [12, 10, "hex_pointy"], [3, 3, "square"], [48, 48, "square"]]:
		var w: int = args[0]
		var h: int = args[1]
		var g: String = args[2]
		lines.append(EstGeneratorG3.canonical_code("DND5", w, h, g))
	lines.append(EstGeneratorG3.canonical_code("PF2E", 6, 5, "hex_pointy", "crypt"))
	# Coste (medido en el test, no en core/gen): la mayor, 48×48.
	var p: EstGeneratorG3.Params = EstGeneratorG3.Params.new()
	p.width = 48
	p.height = 48
	var t0: int = Time.get_ticks_usec()
	for i: int in 10:
		EstGeneratorG3.generate_blank(p)
	lines.append("EST_G3_TIMING 48x48: %d us de media" % ((Time.get_ticks_usec() - t0) / 10))
	var doc: MapDocument = _gen(EstGeneratorG3.canonical_code("DND5", 9, 7, "square"))
	if doc != null:
		var level: MapLevel = doc.level(0)
		for y: int in doc.grid.height:
			var row: String = ""
			for x: int in doc.grid.width:
				var c: Vector2i = Vector2i(x, y)
				if level.get_terrain(c) == Terrain.WALL:
					row += "#"
				elif level.get_room_id(c) == level.rooms[1].id:
					row += "E"
				else:
					row += "."
			lines.append(row)
	lines.append("EST_G3_EXAMPLES_END")
	gut.p("\n".join(lines))
	assert_true(true)
