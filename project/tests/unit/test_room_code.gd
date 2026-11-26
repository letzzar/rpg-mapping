extends GutTest
## Tests de core/seed/room_code.gd e inflate.gd (editor de estancias E3,
## PROYECTO §5.5): id corto RPGU1 y código para compartir RPGS1 (ida y
## vuelta, erratas, alias, guiones y espacios, basura, bomba de
## descompresión, longitud típica y QR) y que RPGM1 no cambia.

const CROCKFORD: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## Ejemplos de la documentación (PROYECTO §5.3): si cambian, cambió RPGM1.
const MAZ_EXAMPLE: String = "RPGM1-DND5-MAZ-G1-FA8-3QV8M2KD-P"
const ALD_EXAMPLE: String = "RPGM1-PF2E-ALD-G3-0-1A-K"

var _base_code: String = ""


func before_all() -> void:
	ParamSchemaRegistry.reset()
	_base_code = EstGeneratorG3.canonical_code("DND5", 12, 10, "square")


func after_each() -> void:
	GeneratorRegistry.reset()


# --- Utilidades ----------------------------------------------------------------

func _field(d: Dictionary, key: String) -> String:
	var s: String = d[key]
	return s


func _fingerprint(text: String) -> PackedByteArray:
	return text.sha256_buffer()


## Código RPGS1 con una carga arbitraria (bytes sin comprimir), para probar
## la lectura con contenido que share_code() nunca escribiría.
func _code_from_bytes(raw: PackedByteArray) -> String:
	var z: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var payload: String = Base32Crockford.encode_bytes(z.slice(2, z.size() - 4))
	return "RPGS1-%s-%s" % [payload, RoomCode.check_char(RoomCode.DOMAIN_SHARE, payload)]


func _code_from_json(text: String) -> String:
	return _code_from_bytes(text.to_utf8_buffer())


func _delta_texts(deltas: Array[MapDelta]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for dl: MapDelta in deltas:
		out.append(CanonicalJson.stringify(dl.to_dict()))
	return out


## Estancia EST G3 12×10 con 30 ediciones variadas, hechas con los comandos
## reales del editor: 10 pinceladas de terreno, 6 aristas, 10 objetos, 2
## borrados y 2 cambios de sala.
func _edited_room() -> MapDocument:
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(_base_code)
	assert_eq(res.error, "")
	var doc: MapDocument = res.doc
	if doc.seed_code.is_empty():
		doc.seed_code = _base_code
	var s: CommandStack = CommandStack.new(doc)
	var terrains: PackedInt32Array = [Terrain.WALL, Terrain.RUBBLE, Terrain.WATER_SHALLOW, Terrain.PIT]
	for k: int in 8:
		var cells: Array[Vector2i] = [Vector2i(2 + k, 3)]
		if k % 2 == 0:
			cells.append(Vector2i(2 + k, 4))
			cells.append(Vector2i(2 + k, 5))
		assert_true(s.execute(SetTerrainCommand.new(0, cells, terrains[k % terrains.size()])), "terreno %d" % k)
	var edge_values: PackedInt32Array = [
		MapEdge.make(MapEdge.KIND_DOOR), MapEdge.make(MapEdge.KIND_DOOR, MapEdge.FLAG_OPEN),
		MapEdge.make(MapEdge.KIND_WINDOW), MapEdge.make(MapEdge.KIND_SECRET_DOOR),
		MapEdge.make(MapEdge.KIND_ARCH), MapEdge.make(MapEdge.KIND_WALL)]
	for k: int in edge_values.size():
		var eid: int = doc.grid.edge_id(Vector2i(2 + k, 7), 0)
		assert_true(s.execute(SetEdgeCommand.new(0, eid, edge_values[k])), "arista %d" % k)
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var kinds: PackedStringArray = ["table_round", "chair", "chair", "bench", "barrel", "crate", "chest",
		"torch_sconce", "bed", "shelf"]
	var materials: PackedStringArray = ["oak", "", "granite"]
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in kinds.size():
		var e: ObjectCatalog.Entry = cat.entry(kinds[k])
		assert_not_null(e, kinds[k])
		var o: MapObject = cat.instantiate(e, doc.allocate_id(), Vector2i(1 + k, 9 - (k % 2)), k % 4, materials[k % 3])
		ids.append(o.id)
		assert_true(s.execute(AddObjectCommand.new(0, o)), kinds[k])
	assert_true(s.execute(RemoveObjectCommand.new(0, ids[2])))
	assert_true(s.execute(RemoveObjectCommand.new(0, ids[5])))
	var lvl: MapLevel = doc.level(0)
	assert_true(s.execute(SetRoomCommand.new(0, lvl.rooms[0].id, "tavern", "La Jarra Rota")))
	assert_true(s.execute(SetRoomCommand.new(0, lvl.rooms[1].id, lvl.rooms[1].kind, "Puerta del patio")))
	var back: Array[Vector2i] = [Vector2i(2, 4), Vector2i(4, 4)]
	assert_true(s.execute(SetTerrainCommand.new(0, back, Terrain.FLOOR)))
	var back2: Array[Vector2i] = [Vector2i(6, 5), Vector2i(8, 5), Vector2i(8, 4)]
	assert_true(s.execute(SetTerrainCommand.new(0, back2, Terrain.FLOOR)))
	assert_eq(doc.deltas.size(), 30)
	return doc


# --- Id corto -------------------------------------------------------------------

func test_short_id_format_and_round_trip() -> void:
	for t: String in ["", "a", "RPG Mapping", "estancia 1", "estancia 2"]:
		var fp: PackedByteArray = _fingerprint(t)
		var id: String = RoomCode.short_id(fp)
		assert_eq(id.length(), 20, id)
		assert_true(id.begins_with("RPGU1-"), id)
		var body: String = id.split("-")[1]
		# El cuerpo son los 60 primeros bits de la huella.
		var want: int = 0
		for i: int in 8:
			want = (want << 8) | fp[i]
		want = Bits64.lsr(want, 4)
		var got: int = 0
		for ch: String in body:
			got = (got << 5) | CROCKFORD.find(ch)
		assert_eq(got, want, id)
		var p: Dictionary = RoomCode.parse_short_id(id)
		assert_eq(_field(p, "error"), "", id)
		assert_eq(_field(p, "id"), id)
		assert_eq(RoomCode.kind_of(id), RoomCode.KIND_SHORT)
	# Mismo contenido, mismo id; distinto, distinto.
	assert_eq(RoomCode.short_id(_fingerprint("x")), RoomCode.short_id(_fingerprint("x")))
	assert_ne(RoomCode.short_id(_fingerprint("x")), RoomCode.short_id(_fingerprint("y")))
	# Huellas que no son SHA-256.
	assert_eq(RoomCode.short_id(PackedByteArray()), "")
	assert_eq(RoomCode.short_id("x".md5_buffer()), "")
	gut.p("ROOM_CODE_SHORT_EXAMPLE %s" % RoomCode.short_id(_fingerprint("RPG Mapping")))


func test_short_id_detects_every_single_typo() -> void:
	var checked: int = 0
	for t: String in ["a", "b", "c", "RPG Mapping"]:
		var id: String = RoomCode.short_id(_fingerprint(t))
		var tail: String = id.substr(6)  # cuerpo-control
		var positions: Array[int] = []
		for i: int in tail.length():
			if tail[i] != "-":
				positions.append(i)
		# Todas las sustituciones de un carácter (cuerpo y control).
		for i: int in positions:
			for ch: String in CROCKFORD:
				if ch == tail[i]:
					continue
				var bad: String = "RPGU1-" + tail.substr(0, i) + ch + tail.substr(i + 1)
				assert_eq(_field(RoomCode.parse_short_id(bad), "error"), RoomCode.ERR_CHECK, bad)
				checked += 1
		# Todas las transposiciones adyacentes (también la del último carácter
		# del cuerpo con el control, saltando el guion).
		for k: int in positions.size() - 1:
			var i: int = positions[k]
			var j: int = positions[k + 1]
			if tail[i] == tail[j]:
				continue
			var sw: PackedStringArray = PackedStringArray()
			for ch2: String in tail:
				sw.append(ch2)
			sw[i] = tail[j]
			sw[j] = tail[i]
			var bad2: String = "RPGU1-" + "".join(sw)
			assert_eq(_field(RoomCode.parse_short_id(bad2), "error"), RoomCode.ERR_CHECK, bad2)
			checked += 1
	assert_gt(checked, 4 * 13 * 31)


func test_short_id_tolerance() -> void:
	var body: String = "01ABCDEF0101"
	var id: String = "RPGU1-%s-%s" % [body, RoomCode.check_char(RoomCode.DOMAIN_SHORT, body)]
	assert_eq(_field(RoomCode.parse_short_id(id), "id"), id)
	var typed: String = "  rpgu1-oiabcdefolol-%s \n" % id.right(1).to_lower()
	assert_eq(_field(RoomCode.parse_short_id(typed), "id"), id, "minúsculas, espacios y alias")
	assert_eq(_field(RoomCode.parse_short_id("RPGU1 - %s - %s" % [body, id.right(1)]), "id"), id, "espacios internos")
	assert_eq(RoomCode.kind_of(typed), RoomCode.KIND_SHORT)


func test_short_id_errors() -> void:
	var id: String = RoomCode.short_id(_fingerprint("a"))
	var body: String = id.split("-")[1]
	for bad: String in ["", "hola", "RPGU1", "RPGU1--", "RPGU1-ABC-1", "RPGU1-%s" % body,
			"RPGU1-%s-%s-X" % [body, id.right(1)], "RPGU1-%sU-%s" % [body.substr(1), id.right(1)],
			"RPGU1-%s-XY" % body, "RPGX1-%s-%s" % [body, id.right(1)], MAZ_EXAMPLE]:
		var p: Dictionary = RoomCode.parse_short_id(bad)
		assert_eq(_field(p, "error"), RoomCode.ERR_FORMAT, bad)
		assert_eq(_field(p, "id"), "")
	assert_eq(_field(RoomCode.parse_short_id("RPGU2-%s-%s" % [body, id.right(1)]), "error"), RoomCode.ERR_VERSION)
	# Un cuerpo con el control de RPGS1 no vale como RPGU1 (dominios distintos).
	var other: String = "RPGU1-%s-%s" % [body, RoomCode.check_char(RoomCode.DOMAIN_SHARE, body)]
	assert_eq(_field(RoomCode.parse_short_id(other), "error"), RoomCode.ERR_CHECK)


# --- Código para compartir --------------------------------------------------------

func test_share_round_trip_and_replay() -> void:
	var doc: MapDocument = _edited_room()
	var code: String = RoomCode.share_code(doc.seed_code, doc.deltas)
	assert_ne(code, "")
	assert_true(code.begins_with("RPGS1-"), code)
	assert_eq(RoomCode.kind_of(code), RoomCode.KIND_SHARE)
	# Mismo contenido → mismo código.
	assert_eq(RoomCode.share_code(doc.seed_code, doc.deltas), code)
	var p: Dictionary = RoomCode.parse_share_code(code)
	assert_eq(_field(p, "error"), "")
	assert_eq(_field(p, "seed_code"), doc.seed_code)
	var deltas: Array[MapDelta] = p["deltas"]
	assert_eq(_delta_texts(deltas), _delta_texts(doc.deltas))
	# Reaplicar sobre la base regenerada da el mismo documento.
	var seed_text: String = _field(p, "seed_code")
	var res: GeneratorRegistry.Result = GeneratorRegistry.generate(seed_text)
	var again: MapDocument = res.doc
	if again.seed_code.is_empty():
		again.seed_code = doc.seed_code
	var rr: DeltaReplay.Result = DeltaReplay.replay(again, deltas)
	assert_eq(rr.error, "", rr.detail)
	assert_eq(again.full_hash(), doc.full_hash())
	# Sin ediciones también vale; otro contenido, otro código.
	var none: Array[MapDelta] = []
	var empty: String = RoomCode.share_code(doc.seed_code, none)
	assert_ne(empty, "")
	assert_eq(_field(RoomCode.parse_share_code(empty), "seed_code"), doc.seed_code)
	var fewer: Array[MapDelta] = doc.deltas.slice(0, 29)
	assert_ne(RoomCode.share_code(doc.seed_code, fewer), code)
	# El código de semilla se normaliza (minúsculas, espacios).
	assert_eq(RoomCode.share_code("  " + doc.seed_code.to_lower(), doc.deltas), code)


func test_share_text_round_trip() -> void:
	var labels: PackedStringArray = ["Cámara del Dragón 🐉", "comillas \" y \\ barra", "línea\nnueva\ttab", "", "日本"]
	for label: String in labels:
		var dl: MapDelta = MapDelta.make("set_room", {"level": 0, "room": 3, "kind": "crypt", "label": label})
		var list: Array[MapDelta] = [dl]
		var code: String = RoomCode.share_code(_base_code, list)
		assert_ne(code, "", label)
		var p: Dictionary = RoomCode.parse_share_code(code)
		assert_eq(_field(p, "error"), "", label)
		var back: Array[MapDelta] = p["deltas"]
		assert_eq(_delta_texts(back), _delta_texts(list), label)


func test_share_tolerance() -> void:
	var doc: MapDocument = _edited_room()
	var code: String = RoomCode.share_code(doc.seed_code, doc.deltas)
	var parts: PackedStringArray = code.split("-")
	assert_eq(parts.size(), 3)
	var payload: String = parts[1]
	# Guiones cada 5, espacios y saltos de línea, minúsculas y alias.
	var grouped: PackedStringArray = PackedStringArray()
	for k: int in range(0, payload.length(), 5):
		grouped.append(payload.substr(k, 5))
	var pretty: String = "  rpgs1-%s-%s\n" % ["-".join(grouped).to_lower(), parts[2].to_lower()]
	var p: Dictionary = RoomCode.parse_share_code(pretty)
	assert_eq(_field(p, "error"), "", "guiones y minúsculas")
	var wrapped: String = "RPGS1-" + payload.substr(0, 40) + "\n" + payload.substr(40) + " - " + parts[2]
	assert_eq(_field(RoomCode.parse_share_code(wrapped), "error"), "", "partido en líneas")
	var aliased: String = "RPGS1-%s-%s" % [payload.replace("0", "O").replace("1", "l"), parts[2]]
	assert_eq(_field(RoomCode.parse_share_code(aliased), "error"), "", "alias O y l")
	assert_eq(RoomCode.kind_of(pretty), RoomCode.KIND_SHARE)


func test_share_detects_typos_sample() -> void:
	var doc: MapDocument = _edited_room()
	var code: String = RoomCode.share_code(doc.seed_code, doc.deltas)
	var tail: String = code.substr(6)
	var checked: int = 0
	# Sustituciones: cada 7.ª posición, 4 caracteres distintos.
	for i: int in range(0, tail.length(), 7):
		if tail[i] == "-":
			continue
		for d: int in [1, 7, 16, 31]:
			var ch: String = CROCKFORD[(CROCKFORD.find(tail[i]) + d) % 32]
			var bad: String = "RPGS1-" + tail.substr(0, i) + ch + tail.substr(i + 1)
			assert_eq(_field(RoomCode.parse_share_code(bad), "error"), RoomCode.ERR_CHECK, "%d %s" % [i, ch])
			checked += 1
	# Transposiciones adyacentes en la carga.
	for i: int in range(0, tail.length() - 3, 11):
		if tail[i] == tail[i + 1] or tail[i] == "-" or tail[i + 1] == "-":
			continue
		var bad2: String = "RPGS1-" + tail.substr(0, i) + tail[i + 1] + tail[i] + tail.substr(i + 2)
		assert_eq(_field(RoomCode.parse_share_code(bad2), "error"), RoomCode.ERR_CHECK, "transposición %d" % i)
		checked += 1
	# El control: los 31 valores erróneos.
	for ch: String in CROCKFORD:
		if ch != code.right(1):
			assert_eq(_field(RoomCode.parse_share_code(code.left(code.length() - 1) + ch), "error"), RoomCode.ERR_CHECK)
			checked += 1
	assert_gt(checked, 100)


func test_share_garbage() -> void:
	for bad: String in ["", "   ", "hola", "RPGS1", "RPGS1-", "RPGS1--", "RPGS1-ABC", "RPGS1--X", "RPGS1-UUU-X",
			"RPGS1-ABC-XY", "RPGS1-AB?C-X", "RPGSX-ABC-X", MAZ_EXAMPLE, "RPGU1-ABC-X"]:
		var p: Dictionary = RoomCode.parse_share_code(bad)
		assert_eq(_field(p, "error"), RoomCode.ERR_FORMAT, bad)
		assert_eq(_field(p, "seed_code"), "")
		var none: Array[MapDelta] = p["deltas"]
		assert_eq(none.size(), 0)
	assert_eq(_field(RoomCode.parse_share_code("RPGS2-ABC-X"), "error"), RoomCode.ERR_VERSION)
	# Control correcto pero carga que no es DEFLATE válido, o con bits de
	# relleno distintos de 0.
	for payload: String in ["0", "ZZZZ", "ABCDEFGH", "Z".repeat(200), "0".repeat(16)]:
		var code: String = "RPGS1-%s-%s" % [payload, RoomCode.check_char(RoomCode.DOMAIN_SHARE, payload)]
		assert_eq(_field(RoomCode.parse_share_code(code), "error"), RoomCode.ERR_FORMAT, payload)
	# Flujo zlib entero (con cabecera y Adler-32): no es el formato.
	var z: PackedByteArray = ("[\"%s\"]" % _base_code).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	var zp: String = Base32Crockford.encode_bytes(z)
	assert_ne(_field(RoomCode.parse_share_code("RPGS1-%s-%s" % [zp, RoomCode.check_char(2, zp)]), "error"), "")
	# UTF-8 inválido tras descomprimir.
	var raw: PackedByteArray = ("[\"%s\",[4,0,1,\"k\",\"" % _base_code).to_utf8_buffer()
	raw.append_array(PackedByteArray([0xC3, 0x28, 0xFF]))
	raw.append_array("\"]]".to_utf8_buffer())
	assert_eq(_field(RoomCode.parse_share_code(_code_from_bytes(raw)), "error"), RoomCode.ERR_FORMAT)


func test_share_bad_json_and_ops() -> void:
	var c: String = "\"%s\"" % _base_code
	var bad_jsons: PackedStringArray = [
		"no es json", "{}", "[]", "[1]", "[%s" % c, "[%s,5]" % c, "[%s,[]]" % c, "[%s,[9,0]]" % c,
		"[%s,[-1,0]]" % c, "[%s,[0.5,0]]" % c, "[%s,[\"0\",0,1]]" % c,
		"[%s,[0,0,1,5]]" % c,                      # casillas impares
		"[%s,[0,0,1,5,1.5]]" % c,                  # no entero
		"[%s,[1,0,5]]" % c, "[%s,[1,0,5,2,9]]" % c,
		"[%s,[2,0,7,\"chair\",1,1,1,1,0,0,0,0,0,\"\",900]]" % c,   # le falta material
		"[%s,[2,0,7,\"chair\",1,1,1,1,0,0,8,0,0,\"\",900,\"\"]]" % c,  # flags > 7
		"[%s,[2,0,7,5,1,1,1,1,0,0,0,0,0,\"\",900,\"\"]]" % c,          # catalog_id no texto
		"[%s,[3,0]]" % c, "[%s,[4,0,1,\"k\"]]" % c, "[%s,[4,0,1,\"k\",5]]" % c,
		"[%s,[1,0,5,1e300]]" % c,
	]
	for j: String in bad_jsons:
		assert_eq(_field(RoomCode.parse_share_code(_code_from_json(j)), "error"), RoomCode.ERR_FORMAT, j)
	# Bien formado (aunque no sea canónico: espacios) se acepta.
	var ok: Dictionary = RoomCode.parse_share_code(_code_from_json("[ %s , [1, 0, 5, 2] ]" % c))
	assert_eq(_field(ok, "error"), "")
	# Código de semilla: se valida con SeedCode.parse y se devuelve su error.
	var typo: String = _base_code.left(_base_code.length() - 1) + ("X" if _base_code.right(1) != "X" else "Y")
	assert_eq(_field(RoomCode.parse_share_code(_code_from_json("[\"%s\"]" % typo)), "error"), SeedCode.ERR_CHECK)
	var future_body: String = "RPGM1-DND5-EST-G99-0-0"
	var future: String = "%s-%s" % [future_body, SeedCode.check_char(future_body)]
	assert_eq(_field(RoomCode.parse_share_code(_code_from_json("[\"%s\"]" % future)), "error"), SeedCode.ERR_SCHEMA)
	assert_eq(_field(RoomCode.parse_share_code(_code_from_json("[\"hola\"]")), "error"), SeedCode.ERR_FORMAT)


func test_share_code_rejects_what_it_cannot_represent() -> void:
	var ok: Array[MapDelta] = [MapDelta.make("set_edge", {"level": 0, "edge": 10, "value": 2})]
	assert_ne(RoomCode.share_code(_base_code, ok), "")
	assert_eq(RoomCode.share_code("RPGM1-DND5-EST-G3-0-0-X", ok), "", "código con errata")
	assert_eq(RoomCode.share_code("", ok), "")
	var cases: Array[MapDelta] = [
		MapDelta.make("add_token", {"token": 1, "data": {}}),                        # no es de contenido
		MapDelta.make("set_edge", {"level": 0, "edge": 10, "value": 2, "extra": 1}),  # le sobra algo
		MapDelta.make("set_edge", {"level": 0, "edge": 10}),                          # le falta algo
		MapDelta.make("set_edge", {"level": 0, "edge": "10", "value": 2}),            # tipo
		MapDelta.make("set_edge", {"level": 0, "edge": 1 << 60, "value": 2}),         # > 2^53
		MapDelta.make("set_terrain", {"level": 0, "terrain": 2, "cells": [[1, 2, 3]]}),
		MapDelta.make("set_room", {"level": 0, "room": 1, "kind": "x", "label": 5}),
		MapDelta.make("", {}),
	]
	for dl: MapDelta in cases:
		var list: Array[MapDelta] = [dl]
		assert_eq(RoomCode.share_code(_base_code, list), "", "%s %s" % [dl.op, dl.data])
	# content_deltas quita lo que es de la partida.
	var mixed: Array[MapDelta] = [cases[0], ok[0], MapDelta.make("explore", {"level": 0, "viewer": "p", "cells": []})]
	var content: Array[MapDelta] = RoomCode.content_deltas(mixed)
	assert_eq(content.size(), 1)
	assert_eq(content[0].op, "set_edge")


func test_decompression_bomb_and_size_limits() -> void:
	# 3 MB de '[' comprimen a ~3 KB: el lector para en 2 MB.
	var big: PackedByteArray = PackedByteArray()
	big.resize(3 * 1024 * 1024)
	big.fill(0x5B)
	var code: String = _code_from_bytes(big)
	assert_lt(code.length(), RoomCode.MAX_SHARE_CHARS)
	var t0: int = Time.get_ticks_msec()
	assert_eq(_field(RoomCode.parse_share_code(code), "error"), RoomCode.ERR_TOO_BIG)
	gut.p("ROOM_CODE_BOMB %d caracteres, rechazada en %d ms" % [code.length(), Time.get_ticks_msec() - t0])
	# Texto demasiado largo: se rechaza antes de mirar nada.
	assert_eq(_field(RoomCode.parse_share_code("RPGS1-" + "0".repeat(RoomCode.MAX_SHARE_CHARS) + "-0"), "error"), RoomCode.ERR_TOO_BIG)


func test_inflate_matches_engine() -> void:
	var samples: Array[PackedByteArray] = []
	samples.append("hola".to_utf8_buffer())                          # bloque fijo
	var noise: PackedByteArray = PackedByteArray()
	var x: int = 12345
	for i: int in 70000:
		x = (x * 1103515245 + 12345) & 0x7FFFFFFF
		noise.append((x >> 16) & 0xFF)
	samples.append(noise)                                             # bloques almacenados
	var text: String = ""
	for i: int in 3000:
		text += "[%d,%d,\"objeto_%d\"]" % [i % 37, (i * 7) % 101, i % 13]
	samples.append(text.to_utf8_buffer())                             # bloques dinámicos
	for s: PackedByteArray in samples:
		var z: PackedByteArray = s.compress(FileAccess.COMPRESSION_DEFLATE)
		var raw: PackedByteArray = z.slice(2, z.size() - 4)
		var r: Inflate.Result = Inflate.inflate_raw(raw, 1 << 20)
		assert_eq(r.status, Inflate.STATUS_OK)
		assert_eq(r.bytes, s)
		# Truncado, con bytes de sobra o con límite justo por debajo.
		assert_eq(Inflate.inflate_raw(raw.slice(0, raw.size() - 1), 1 << 20).status, Inflate.STATUS_ERROR)
		var extra: PackedByteArray = raw.duplicate()
		extra.append(0)
		assert_eq(Inflate.inflate_raw(extra, 1 << 20).status, Inflate.STATUS_ERROR)
		assert_eq(Inflate.inflate_raw(raw, s.size() - 1).status, Inflate.STATUS_TOO_BIG)
		assert_eq(Inflate.inflate_raw(raw, s.size()).status, Inflate.STATUS_OK)
	assert_eq(Inflate.inflate_raw(PackedByteArray(), 100).status, Inflate.STATUS_ERROR)
	assert_eq(Inflate.inflate_raw(PackedByteArray([0x07]), 100).status, Inflate.STATUS_ERROR, "tipo de bloque 3")


func test_typical_length_and_qr() -> void:
	var doc: MapDocument = _edited_room()
	var code: String = RoomCode.share_code(doc.seed_code, doc.deltas)
	var json_len: int = 0
	var naive: Array = []
	for dl: MapDelta in doc.deltas:
		naive.append(dl.to_dict())
	json_len = CanonicalJson.stringify({"seed_code": doc.seed_code, "deltas": naive}).length()
	var qr: QrCode = QrCode.encode_text(code, QrCode.ECC_M)
	var none: Array[MapDelta] = []
	var lines: PackedStringArray = PackedStringArray([
		"ROOM_CODE_TYPICAL base=%s deltas=%d" % [doc.seed_code, doc.deltas.size()],
		"  RPGS1: %d caracteres (JSON de deltas sin compactar: %d)" % [code.length(), json_len],
		"  QR M: %s" % (("versión %d" % qr.version) if qr != null else "no cabe en v1-10 (máx. %d bytes)" % QrCode.byte_capacity(10, QrCode.ECC_M)),
		"  sin ediciones: %s" % RoomCode.share_code(doc.seed_code, none),
		"  %s" % code,
	])
	gut.p("\n".join(lines))
	assert_ne(code, "")
	# Compactar tiene que compensar: mucho menos que el JSON directo.
	assert_lt(code.length(), json_len / 3)


# --- RPGM1 no cambia ---------------------------------------------------------------

func test_kind_of() -> void:
	assert_eq(RoomCode.kind_of(MAZ_EXAMPLE), RoomCode.KIND_SEED)
	assert_eq(RoomCode.kind_of("  rpgm1-dnd5-maz-g1-fa8-3qv8m2kd-p "), RoomCode.KIND_SEED)
	assert_eq(RoomCode.kind_of("RPGU1-0000000000000-0"), RoomCode.KIND_SHORT)
	assert_eq(RoomCode.kind_of("rpgs1-abc-x"), RoomCode.KIND_SHARE)
	for t: String in ["", "hola", "RPGM1", "RPGM2-X", "RPGU2-X", "RPGS", "XRPGS1-"]:
		assert_eq(RoomCode.kind_of(t), "", t)


func test_rpgm1_unchanged() -> void:
	for code: String in [MAZ_EXAMPLE, ALD_EXAMPLE]:
		var body: String = code.left(code.length() - 2)
		assert_eq(SeedCode.check_char(body), code.right(1), code)
	var sc: SeedCode = SeedCode.parse(_base_code)
	assert_true(sc.is_valid())
	assert_eq(sc.encode(), _base_code)
	# Seeds doradas de EST G3 (las del fichero; test_golden_seeds compara los hash).
	var f: FileAccess = FileAccess.open("res://tests/golden/golden_seeds.txt", FileAccess.READ)
	assert_not_null(f)
	var n: int = 0
	while f != null and not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var code2: String = line.split(" ")[0]
		var p: SeedCode = SeedCode.parse(code2)
		assert_eq(p.encode(), code2, code2)
		assert_eq(RoomCode.kind_of(code2), RoomCode.KIND_SEED)
		n += 1
	assert_gt(n, 5)
