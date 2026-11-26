class_name GeoLinks
extends RefCounted
## Enlaces de mundo y región con sus hijos (F6): asentamientos ALD, puntos de
## interés (MAZ o sin mapa) y regiones de un mundo. Puro y entero.
##
## Los hijos de MUN y REG no están a la misma escala que su padre (una casilla
## del mundo son 12 millas; una de la aldea, 5 pies), así que MapChild no es
## una traslación 1:1 como en ALD → EDI: solo valen `rect` (la casilla o
## ventana del padre), `entrance` (casilla del padre donde aparece el grupo al
## salir) y `entrance − offset` (casilla del hijo donde aparece al entrar).
## MapNavigator ya trabaja así sin cambios en modo "por la puerta"
## (keep_positions = false); keep_positions = true no tiene sentido aquí.

const CHILD_SEED_MASK: int = (1 << 40) - 1


## Casilla de entrada a un asentamiento ALD G1 sin generarlo: el centro de su
## mapa (la plaza está en el centro, desplazada tierra adentro con costa;
## MapNavigator busca la casilla libre más cercana). Mismo tamaño que
## AldGeneratorG1.generate_settlement (map_size con la orientación de su
## semilla). Vector2i.ZERO si el código no es válido.
static func ald_entry_cell(ald: SeedCode) -> Vector2i:
	if not ald.is_valid() or ald.scale != "ALD" or ald.gen_version != 1:
		return Vector2i.ZERO
	var p: AldGeneratorG1.Params = AldGeneratorG1.params_from(ald)
	var data: AldData = AldData.load_default()
	var ss: AldData.SizeSpec = data.size_spec(p.size_id)
	if ss == null:
		return Vector2i.ZERO
	var horizontal: bool = Rng.new(ald.seed_value).fork("orientation", 0).chance_permille(500)
	var dims: Vector2i = AldGeneratorG1.map_size(p, ss, horizontal)
	return Vector2i(dims.x / 2, dims.y / 2)


## Hijo de un asentamiento en la casilla `cell` del padre.
static func settlement_child(id: int, cell: Vector2i, size_id: String, code: SeedCode, label: String, room_id: int) -> MapChild:
	var c: MapChild = MapChild.new()
	c.id = id
	c.kind = size_id
	c.seed_code = code.encode()
	c.label = label
	c.room_id = room_id
	c.rect = Rect2i(cell, Vector2i.ONE)
	c.entrance = cell
	c.offset = cell - ald_entry_cell(code)
	c.child_level = 0
	return c


## Hijo de un punto de interés: con mapa MAZ (`code` válido) o solo marcador
## (seed_code = ""; la UI no debe ofrecer "entrar"). La entrada de una
## mazmorra MAZ G1 no se conoce sin generarla (~0,1 s cada una): `offset`
## lleva la entrada del padre a la casilla (0, 0) del hijo, que en MAZ no es
## transitable, y MapNavigator.enter usa entonces la zona "entrance" del hijo.
static func poi_child(id: int, cell: Vector2i, kind: String, code_text: String, room_id: int) -> MapChild:
	var c: MapChild = MapChild.new()
	c.id = id
	c.kind = kind
	c.seed_code = code_text
	c.room_id = room_id
	c.rect = Rect2i(cell, Vector2i.ONE)
	c.entrance = cell
	c.offset = cell
	c.child_level = 0
	return c
