extends GutTest
## Tests de EST G2 (core/gen/est/est_generator_g2.gd, ADR 029): código de
## estancia de un edificio. Criterio de F3: "regenerar una estancia aislada
## desde su código da el mismo resultado que dentro de la aldea".
##
## Para muchos edificios EDI G1 (7 tipos × 3 rejillas, sótanos, varias
## plantas) y TODAS sus estancias, el código EST G2 regenera exactamente la
## estancia del edificio completo (terreno, zonas, aristas, objetos y
## escaleras trasladados por offset), más la cadena ALD → EDI → estancia y los
## errores. Imprime tiempos (EST_G2_TIMING), los códigos de la taberna de la
## aldea de ejemplo y ASCII de muestra. No graba seeds doradas (esquema
## pendiente de aprobar).

const TYPES: PackedStringArray = ["tavern", "house", "smithy", "temple", "shop", "inn", "guardhouse"]
const STYLES: PackedStringArray = ["human", "dwarf", "elf"]
## Aldea de ejemplo (PROYECTO §6.3) y su taberna hija.
const ALD_EXAMPLE: String = "RPGM1-DND5-ALD-G1-0-H8DJRFAE-W"
const TAVERN_CHILD: String = "RPGM1-DND5-EDI-G1-Y00-BC23VGX8-T"


func after_each() -> void:
	GeneratorRegistry.reset()


func _edi_code(params: Dictionary, seed_value: int, system: String = "DND5") -> String:
	var sc: SeedCode = SeedCode.create(system, "EDI", 1, params, seed_value)
	assert_true(sc.is_valid(), "%s %s" % [sc.error, sc.error_field])
	return sc.encode()


# --- Esquema, registro y textos -------------------------------------------------------

func test_schema_registry_and_texts() -> void:
	var g1: ParamSchema = ParamSchemaRegistry.get_schema("EST", 1)
	var g2: ParamSchema = ParamSchemaRegistry.get_schema("EST", 2)
	var edi: ParamSchema = ParamSchemaRegistry.get_schema("EDI", 1)
	assert_not_null(g1)
	assert_not_null(g2)
	if g1 == null or g2 == null or edi == null:
		return
	# G1 intacto: mismo esquema de siempre.
	assert_eq(g1.field_keys(), PackedStringArray(["room_type", "grid", "size", "style", "shape", "doors", "clutter"]))
	# G2 = los 7 campos de EDI G1, idénticos y en el mismo orden, + level + room.
	assert_eq(g2.field_keys(), PackedStringArray(["building_type", "grid", "style", "floors", "cellar", "size", "clutter", "level", "room"]))
	for i: int in edi.fields.size():
		var a: ParamSchema.Field = edi.fields[i]
		var b: ParamSchema.Field = g2.fields[i]
		assert_eq([a.kind, a.key, a.min_value, a.max_value, a.default_value, a.capacity], [b.kind, b.key, b.min_value, b.max_value, b.default_value, b.capacity], a.key)
		assert_eq(a.ids, b.ids, a.key)
	assert_true(GeneratorRegistry.has_generator("EST", 1))
	assert_true(GeneratorRegistry.has_generator("EST", 2))
	for lang: String in ["es", "en"]:
		var tr_file: Translation = load("res://i18n/strings.%s.translation" % lang)
		for k: String in [EstGeneratorG2.ERR_LEVEL, EstGeneratorG2.ERR_ROOM]:
			assert_ne(String(tr_file.get_message(k)), "", "%s %s" % [lang, k])


## EST G1 sigue igual y la app (GEN = 1 al generar al azar) sigue creando G1.
func test_est_g1_untouched() -> void:
	var sc: SeedCode = SeedCode.create("DND5", "EST", 1, {"grid": "hex_flat"}, 0x8A1B2C3D4E)
	assert_true(sc.is_valid())
	var code: String = sc.encode()
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
	assert_eq(res.error, "")
	if res.doc == null:
		return
	assert_eq(res.doc.gen_version, 1)
	var direct: MapDocument = EstGeneratorG1.generate_room(EstGeneratorG1.params_from(SeedCode.parse(code)), Rng.new(0x8A1B2C3D4E))
	direct.seed_code = code
	direct.scale = "EST"
	direct.gen_version = 1
	assert_eq(res.doc.content_hash(), direct.content_hash())
	# Un código G1 conocido (seed dorada) sigue siendo G1.
	assert_eq(SeedCode.parse("RPGM1-DND5-EST-G1-0-H8DJRFAE-M").gen_version, 1)


func test_codes_round_trip() -> void:
	var edi: String = _edi_code({"building_type": "inn", "grid": "hex_pointy", "floors": 3, "cellar": true, "style": "elf"}, 0xABCDE12345)
	var code: String = EstGeneratorG2.room_code(edi, 2, 5)
	assert_ne(code, "")
	var sc: SeedCode = SeedCode.parse(code)
	assert_true(sc.is_valid(), code)
	assert_eq(sc.encode(), code)
	assert_eq([sc.scale, sc.gen_version, sc.seed_value], ["EST", 2, 0xABCDE12345])
	var lv: int = sc.params["level"]
	var rm: int = sc.params["room"]
	assert_eq([lv, rm], [2, 5])
	assert_eq(EstGeneratorG2.building_code(code), edi)
	# Fuera del esquema o código que no es EDI G1: "".
	assert_eq(EstGeneratorG2.room_code(edi, 8, 0), "")
	assert_eq(EstGeneratorG2.room_code(edi, 0, 64), "")
	assert_eq(EstGeneratorG2.room_code("RPGM1-DND5-EST-G1-0-H8DJRFAE-M", 0, 0), "")
	assert_eq(EstGeneratorG2.room_code("basura", 0, 0), "")
	assert_eq(EstGeneratorG2.building_code(edi), "")
	# El sistema viaja con el código.
	var pf: String = _edi_code({}, 77, "PF2E")
	assert_true(EstGeneratorG2.room_code(pf, 0, 0).begins_with("RPGM1-PF2E-EST-G2-"))


# --- Comparación estancia ↔ edificio ----------------------------------------------------

## Diferencias entre la estancia `ref` del edificio completo `building` (EDI
## G1 de verdad, con todo amueblado) y su documento EST G2 `room` (vacío = igual).
func _room_mismatches(building: MapDocument, ref: EstGeneratorG2.RoomRef, room: MapDocument) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if room.level_count() != 1 or room.grid_kind() != building.grid_kind():
		out.append("niveles o rejilla")
		return out
	if Vector2i(room.width(), room.height()) != ref.map_size:
		out.append("tamaño %dx%d" % [room.width(), room.height()])
		return out
	var bg: GridGeometry = building.grid
	var g: GridGeometry = room.grid
	var src: MapLevel = building.level(ref.level)
	var dst: MapLevel = room.level(0)
	# Anillo: al menos RING casillas alrededor de la estancia.
	var rr: Rect2i = Rect2i(ref.rect.position - ref.offset, ref.rect.size)
	if rr.position.x < EstGeneratorG2.RING or rr.position.y < EstGeneratorG2.RING \
			or rr.end.x + EstGeneratorG2.RING > room.width() or rr.end.y + EstGeneratorG2.RING > room.height():
		out.append("sin anillo")
	# Terreno y zonas (biyección de ids) en toda la ventana.
	var zone_map: Dictionary[int, int] = {}
	var room_zone: int = -1
	for i: int in g.cell_count():
		var c: Vector2i = g.cell_at(i)
		var bc: Vector2i = ref.to_building_cell(c)
		if not bg.in_bounds(bc):
			if dst.get_terrain(c) != Terrain.VOID or dst.get_room_id(c) != 0:
				out.append("fuera del edificio %s" % c)
			continue
		if dst.get_terrain(c) != src.get_terrain(bc):
			out.append("terreno %s" % c)
		var sid: int = src.get_room_id(bc)
		var did: int = dst.get_room_id(c)
		if (sid == 0) != (did == 0):
			out.append("zona %s" % c)
		elif sid != 0:
			if zone_map.has(sid) and zone_map[sid] != did:
				out.append("zona partida %s" % c)
			zone_map[sid] = did
			var sk: String = src.room(sid).kind
			var dk: String = dst.room(did).kind
			if sk != dk:
				out.append("tipo de zona %s: %s/%s" % [c, sk, dk])
		if ref.rect.has_point(bc):
			if room_zone < 0:
				room_zone = did
			elif did != room_zone:
				out.append("estancia con dos zonas %s" % c)
	if room_zone > 0:
		var rz: MapRoom = dst.room(room_zone)
		if rz == null or rz.kind != ref.kind:
			out.append("tipo de la estancia")
		if dst.room_cells(room_zone).size() != ref.rect.size.x * ref.rect.size.y:
			out.append("casillas de la estancia")
	var targets: Dictionary[int, bool] = {}
	for v: int in zone_map.values():
		if targets.has(v):
			out.append("dos zonas del edificio en una")
		targets[v] = true
	# Aristas: todas las de la ventana iguales (las que tocan la estancia, sí o sí).
	for i2: int in g.cell_count():
		var c2: Vector2i = g.cell_at(i2)
		var bc2: Vector2i = ref.to_building_cell(c2)
		for d: int in g.edge_direction_count():
			if not g.in_bounds(g.neighbor(c2, d)) or not bg.in_bounds(bc2):
				continue
			if dst.get_edge(c2, d) != src.get_edge(bc2, d):
				out.append("arista %s/%d: %d/%d" % [c2, d, src.get_edge(bc2, d), dst.get_edge(c2, d)])
	for eid: int in dst.edge_ids():
		var e: Vector3i = g.edge_from_id(eid)
		if src.get_edge(ref.to_building_cell(Vector2i(e.x, e.y)), e.z) != dst.get_edge_by_id(eid):
			out.append("arista de más %s" % e)
	# Objetos de la estancia (todo lo demás igual salvo id y casilla trasladada).
	var expected: PackedStringArray = PackedStringArray()
	for o: MapObject in src.objects:
		if ref.rect.has_point(o.cell):
			var od: Dictionary = o.to_dict()
			od.erase("id")
			od["cell"] = [o.cell.x - ref.offset.x, o.cell.y - ref.offset.y]
			expected.append(CanonicalJson.stringify(od))
	var got: PackedStringArray = PackedStringArray()
	for o2: MapObject in dst.objects:
		var od2: Dictionary = o2.to_dict()
		od2.erase("id")
		got.append(CanonicalJson.stringify(od2))
	if got != expected:
		out.append("objetos: %d esperados, %d obtenidos" % [expected.size(), got.size()])
	# Escaleras de la estancia (nivel relativo).
	var exp_s: PackedStringArray = PackedStringArray()
	for s: MapStair in src.stairs:
		if ref.rect.has_point(s.cell):
			exp_s.append("%s>%d@%s/%d" % [s.cell - ref.offset, s.to_level - ref.level, s.to_cell - ref.offset, s.facing])
	var got_s: PackedStringArray = PackedStringArray()
	for s2: MapStair in dst.stairs:
		got_s.append("%s>%d@%s/%d" % [s2.cell, s2.to_level, s2.to_cell, s2.facing])
	if got_s != exp_s:
		out.append("escaleras %s / %s" % [exp_s, got_s])
	if not dst.traps.is_empty() or not dst.children.is_empty():
		out.append("trampas o hijos")
	return out


## Comprueba todas las estancias del edificio `edi_code`. Devuelve cuántas.
func _check_building(edi_code: String) -> int:
	var full: GeneratorRegistry.Result = GeneratorRegistry.generate(edi_code)
	assert_eq(full.error, "", edi_code)
	if full.doc == null:
		return 0
	var refs: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(edi_code)
	assert_true(refs.size() >= full.doc.level_count(), edi_code)
	var n: int = 0
	for ref: EstGeneratorG2.RoomRef in refs:
		assert_eq(ref.building_code, edi_code)
		assert_eq(EstGeneratorG2.building_code(ref.code), edi_code)
		var gen: GeneratorRegistry.Result = GeneratorRegistry.generate(ref.code)
		assert_eq(gen.error, "", ref.code)
		if gen.doc == null:
			continue
		assert_eq([gen.doc.scale, gen.doc.gen_version, gen.doc.seed_code], ["EST", 2, ref.code])
		assert_eq(_room_mismatches(full.doc, ref, gen.doc), PackedStringArray(), "%s (nivel %d, estancia %d)" % [ref.code, ref.level, ref.order])
		n += 1
	_check_refs(full.doc, refs, edi_code)
	return n


## Toda casilla de estancia del edificio está en exactamente una RoomRef; el
## exterior, la entrada y la salida en ninguna. entry es transitable en la
## estancia y offset respeta la paridad de la rejilla.
func _check_refs(doc: MapDocument, refs: Array[EstGeneratorG2.RoomRef], edi_code: String) -> void:
	var step: Vector2i = AldGeneratorG1.translation_step(doc.grid)
	var outdoor: PackedStringArray = [MapRoom.KIND_OUTSIDE, MapRoom.KIND_ENTRANCE, MapRoom.KIND_EXIT]
	var bad: int = 0
	for li: int in doc.level_count():
		var lvl: MapLevel = doc.level(li)
		for i: int in doc.grid.cell_count():
			var c: Vector2i = doc.grid.cell_at(i)
			var r: MapRoom = lvl.room(lvl.get_room_id(c))
			var hits: int = 0
			for ref: EstGeneratorG2.RoomRef in refs:
				if ref.contains(li, c):
					hits += 1
			var want: int = 1 if r != null and not outdoor.has(r.kind) else 0
			if hits != want:
				bad += 1
	assert_eq(bad, 0, "casillas mal asignadas a estancias: " + edi_code)
	for ref: EstGeneratorG2.RoomRef in refs:
		assert_true(ref.rect.has_point(ref.entry), "entry fuera: " + ref.code)
		assert_eq(posmod(ref.offset.x, step.x) + posmod(ref.offset.y, step.y), 0, "paridad: " + ref.code)
		assert_eq(ref.to_building_cell(ref.to_room_cell(ref.entry)), ref.entry)
		var mc: MapChild = ref.to_map_child()
		assert_eq([mc.seed_code, mc.child_level, mc.to_child_cell(mc.entrance)], [ref.code, 0, ref.to_room_cell(ref.entry)])


func test_every_room_of_many_buildings_is_exact() -> void:
	var rooms: int = 0
	var buildings: int = 0
	var i: int = 0
	for kind: String in GridGeometry.KINDS:
		for t: String in TYPES:
			i += 1
			var params: Dictionary = {"building_type": t, "grid": kind, "style": STYLES[i % 3]}
			if i % 2 == 0:
				params["cellar"] = true
			if i % 3 == 0:
				params["floors"] = 1 + i % 4
			if i % 5 == 0:
				params["size"] = "large"
			rooms += _check_building(_edi_code(params, 0x5000 + 37 * i, "DND5" if i % 2 == 0 else "PF2E"))
			buildings += 1
	print("EST_G2 estancias comprobadas=%d en %d edificios" % [rooms, buildings])
	assert_true(rooms >= 150, "estancias comprobadas: %d" % rooms)


## Las 8 seeds doradas de EDI G1 (congeladas): todas sus estancias.
func test_golden_buildings_rooms_exact() -> void:
	var rooms: int = 0
	for code: String in ["RPGM1-DND5-EDI-G1-0-H8DJRFAE-3", "RPGM1-DND5-EDI-G1-A01-KCP3TKJZ-2", "RPGM1-PF2E-EDI-G1-52-NGYMWQV0-K",
			"RPGM1-DND5-EDI-G1-AA3-QN75YR3H-A", "RPGM1-DND5-EDI-G1-1E04-SSFP0WC2-N", "RPGM1-PF2E-EDI-G1-F015-VXG730MK-E",
			"RPGM1-DND5-EDI-G1-A46-W1RR54X4-6", "RPGM1-PF2E-EDI-G1-2820-Y619795N-E"]:
		assert_true(SeedCode.parse(code).is_valid(), code)
		rooms += _check_building(code)
	assert_true(rooms >= 40, "estancias: %d" % rooms)


func test_determinism_and_rooms_differ() -> void:
	var edi: String = _edi_code({"building_type": "guardhouse", "grid": "hex_flat", "cellar": true}, 0xC0FFEE)
	var refs: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(edi)
	var hashes: Dictionary[String, String] = {}
	for ref: EstGeneratorG2.RoomRef in refs:
		var a: MapDocument = GeneratorRegistry.generate(ref.code).doc
		var b: MapDocument = GeneratorRegistry.generate(ref.code).doc
		if a == null or b == null:
			fail_test(ref.code)
			continue
		assert_eq(a.content_hash(), b.content_hash(), ref.code)
		assert_false(hashes.has(a.content_hash()), "dos estancias iguales: " + ref.code)
		hashes[a.content_hash()] = ref.code
	assert_true(refs.size() >= 6)


func test_room_at_and_ref_of() -> void:
	var edi: String = _edi_code({"building_type": "tavern", "cellar": true}, 4242)
	var refs: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(edi)
	assert_false(refs.is_empty())
	for ref: EstGeneratorG2.RoomRef in refs:
		var at: EstGeneratorG2.RoomRef = EstGeneratorG2.room_at(edi, ref.level, ref.entry)
		assert_not_null(at)
		if at != null:
			assert_eq([at.level, at.order, at.code], [ref.level, ref.order, ref.code])
		var back: EstGeneratorG2.RoomRef = EstGeneratorG2.ref_of(ref.code)
		assert_not_null(back)
		if back != null:
			assert_eq([back.building_code, back.level, back.order, back.offset, back.rect, back.entry, back.kind, back.hub],
				[ref.building_code, ref.level, ref.order, ref.offset, ref.rect, ref.entry, ref.kind, ref.hub])
	# El anillo exterior y una casilla fuera del mapa no son estancias.
	assert_null(EstGeneratorG2.room_at(edi, 1, Vector2i(0, 0)))
	assert_null(EstGeneratorG2.room_at(edi, 1, Vector2i(-5, 3)))
	assert_null(EstGeneratorG2.room_at(edi, 9, Vector2i(2, 2)))
	assert_null(EstGeneratorG2.room_at("basura", 1, Vector2i(2, 2)))
	assert_null(EstGeneratorG2.ref_of(edi))


# --- Errores -------------------------------------------------------------------------------

func test_invalid_level_and_room_give_i18n_errors() -> void:
	# Taberna por defecto: 2 plantas sin sótano (niveles 0 y 1).
	var edi: String = _edi_code({}, 1)
	assert_eq(GeneratorRegistry.generate(EstGeneratorG2.room_code(edi, 2, 0)).error, EstGeneratorG2.ERR_LEVEL)
	assert_eq(GeneratorRegistry.generate(EstGeneratorG2.room_code(edi, 7, 0)).error, EstGeneratorG2.ERR_LEVEL)
	assert_eq(GeneratorRegistry.generate(EstGeneratorG2.room_code(edi, 0, 63)).error, EstGeneratorG2.ERR_ROOM)
	assert_eq(GeneratorRegistry.generate(EstGeneratorG2.room_code(edi, 1, 40)).error, EstGeneratorG2.ERR_ROOM)
	assert_null(EstGeneratorG2.ref_of(EstGeneratorG2.room_code(edi, 2, 0)))
	assert_eq(GeneratorRegistry.generate(EstGeneratorG2.room_code(edi, 0, 0)).error, "")
	# Fuera del esquema: error de parámetro al crear el código.
	var sc: SeedCode = SeedCode.create("DND5", "EST", 2, {"level": 8}, 1)
	assert_eq([sc.error, sc.error_field], [SeedCode.ERR_PARAM_RANGE, "level"])
	sc = SeedCode.create("DND5", "EST", 2, {"room": 64}, 1)
	assert_eq([sc.error, sc.error_field], [SeedCode.ERR_PARAM_RANGE, "room"])
	# Estancia descartada (no cabía): ERR_ROOM. Se busca una posada pequeña
	# con dormitorios descartados (ocurre a veces, PROYECTO §6.4).
	var found: String = ""
	for s: int in 400:
		var code: String = _edi_code({"building_type": "inn", "size": "small", "floors": 3}, 1000 + s)
		var res: EdiGeneratorG1.Result = EdiGeneratorG1.plan_building(EdiGeneratorG1.params_from(SeedCode.parse(code)), Rng.new(1000 + s))
		for f: EdiGeneratorG1.Floor in res.floors:
			for sl: EdiGeneratorG1.Slot in f.slots:
				if found.is_empty() and not sl.placed():
					found = EstGeneratorG2.room_code(code, f.level_index, sl.order)
		if not found.is_empty():
			break
	if found.is_empty():
		print("EST_G2 sin estancias descartadas en 400 posadas pequeñas (no se prueba ese caso)")
	else:
		assert_eq(GeneratorRegistry.generate(found).error, EstGeneratorG2.ERR_ROOM, found)


# --- Cadena del criterio de F3 ----------------------------------------------------------------

## ALD → código EDI hijo → código de estancia → la misma estancia que dentro
## del edificio de la aldea. En la planta baja, además, los muros, puertas y
## ventanas exteriores de la estancia son literalmente los del mapa de la
## aldea (casilla de la aldea = casilla de la estancia + offset + offset del
## edificio).
func test_chain_ald_edi_room() -> void:
	var codes: PackedStringArray = [ALD_EXAMPLE]
	for kind: String in ["hex_flat", "hex_pointy"]:
		var sc: SeedCode = SeedCode.create("DND5", "ALD", 1, {"size": "hamlet", "grid": kind, "style": "dwarf"}, 0xA1D0F3)
		codes.append(sc.encode())
	var rooms: int = 0
	var exterior_edges: int = 0
	var tavern_seen: bool = false
	for ald_code: String in codes:
		var ald: GeneratorRegistry.Result = GeneratorRegistry.generate(ald_code)
		assert_eq(ald.error, "", ald_code)
		if ald.doc == null:
			continue
		var alvl: MapLevel = ald.doc.level(0)
		var k: int = 0
		for child: MapChild in alvl.children:
			if child.seed_code == TAVERN_CHILD:
				tavern_seen = true
			elif k >= 5:
				continue
			k += 1
			rooms += _check_building(child.seed_code)
			for ref: EstGeneratorG2.RoomRef in EstGeneratorG2.rooms_of(child.seed_code):
				if ref.level != child.child_level:
					continue
				var room: MapDocument = GeneratorRegistry.generate(ref.code).doc
				if room == null:
					continue
				var g: GridGeometry = room.grid
				for y: int in range(ref.rect.position.y, ref.rect.end.y):
					for x: int in range(ref.rect.position.x, ref.rect.end.x):
						var bc: Vector2i = Vector2i(x, y)
						var ac: Vector2i = bc + child.offset
						for d: int in g.edge_direction_count():
							if child.rect.has_point(g.neighbor(ac, d)):
								continue
							exterior_edges += 1
							var av: int = alvl.get_edge(ac, d)
							var rv: int = room.level(0).get_edge(ref.to_room_cell(bc), d)
							assert_eq(rv, av, "%s %s/%d" % [ref.code, bc, d])
	assert_true(tavern_seen, "la taberna %s es hija de %s" % [TAVERN_CHILD, ALD_EXAMPLE])
	assert_true(rooms >= 60, "estancias: %d" % rooms)
	assert_true(exterior_edges >= 200, "aristas exteriores: %d" % exterior_edges)
	print("EST_G2_CHAIN estancias=%d aristas_exteriores=%d" % [rooms, exterior_edges])


# --- Muestras, tiempos y ASCII ---------------------------------------------------------------

func test_print_tavern_codes_timing_and_ascii() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for ref: EstGeneratorG2.RoomRef in EstGeneratorG2.rooms_of(TAVERN_CHILD):
		lines.append("  nivel %d estancia %d %s%s %s offset=%s mapa=%dx%d entry=%s" % [ref.level, ref.order, ref.kind,
			" (hub)" if ref.hub else "", ref.code, ref.offset, ref.map_size.x, ref.map_size.y, ref.entry])
	print("EST_G2_TAVERN %s\n%s" % [TAVERN_CHILD, "\n".join(lines)])
	assert_false(lines.is_empty())
	# Tiempos: edificio completo, distribución sola (rooms_of) y una estancia.
	var edis: PackedStringArray = [TAVERN_CHILD, "RPGM1-DND5-EDI-G1-1E04-SSFP0WC2-N", "RPGM1-PF2E-EDI-G1-F015-VXG730MK-E", "RPGM1-DND5-EDI-G1-A46-W1RR54X4-6"]
	for edi: String in edis:
		var t0: int = Time.get_ticks_usec()
		GeneratorRegistry.generate(edi)
		var t1: int = Time.get_ticks_usec()
		var refs: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(edi)
		var t2: int = Time.get_ticks_usec()
		var worst: int = 0
		for ref: EstGeneratorG2.RoomRef in refs:
			var a: int = Time.get_ticks_usec()
			GeneratorRegistry.generate(ref.code)
			worst = maxi(worst, Time.get_ticks_usec() - a)
		var t3: int = Time.get_ticks_usec()
		print("EST_G2_TIMING %s edificio=%d ms rooms_of=%d ms estancia_media=%d ms peor=%d ms (%d estancias)" % [edi,
			(t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000 / maxi(1, refs.size()), worst / 1000, refs.size()])
	# ASCII: la sala común de la taberna y su edificio (rejilla cuadrada).
	var edi_script: GDScript = load("res://tests/unit/test_edi_generator.gd")
	var refs2: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(TAVERN_CHILD)
	for ref2: EstGeneratorG2.RoomRef in refs2:
		if ref2.order <= 1 and ref2.level == 1:
			var doc: MapDocument = GeneratorRegistry.generate(ref2.code).doc
			if doc != null:
				var text: String = edi_script.call("ascii_square", doc, 0)
				print("%s (%s, offset %s)\n%s\n" % [ref2.code, ref2.kind, ref2.offset, text])
	var hexes: Array[String] = [_edi_code({"building_type": "temple", "grid": "hex_pointy", "cellar": true}, 0xBD4E5F6071)]
	var est_script: GDScript = load("res://tests/unit/test_est_generator.gd")
	for edi2: String in hexes:
		var r0: Array[EstGeneratorG2.RoomRef] = EstGeneratorG2.rooms_of(edi2)
		if not r0.is_empty():
			var hdoc: MapDocument = GeneratorRegistry.generate(r0[0].code).doc
			if hdoc != null:
				var htext: String = est_script.call("ascii", hdoc)
				print("%s (%s)\n%s\n" % [r0[0].code, r0[0].kind, htext])
