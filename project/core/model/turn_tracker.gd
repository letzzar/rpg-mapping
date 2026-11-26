class_name TurnTracker
extends RefCounted
## Seguimiento de turnos e iniciativa (PROYECTO §10.3, ADR 035): SOLO el
## orden y el movimiento gastado en el turno, sin automatizar el combate. Es
## estado de sesión del MapDocument (no entra en content_hash) y cambia por
## SetTurnsCommand (con deshacer) o, el movimiento gastado, por
## MoveTokenCommand.

## Hay combate en marcha (hay turno actual).
var active: bool = false
var round: int = 1
## Ids de ficha en el orden de los turnos.
var order: PackedInt32Array = PackedInt32Array()
## Índice en `order` del turno actual.
var current: int = 0
## Id de ficha → resultado de iniciativa (lo escribe o lo tira el DM).
var initiative: Dictionary[int, int] = {}
## Pies gastados por la ficha del turno actual.
var moved_ft: int = 0
## El DM no deja pasar de la velocidad (si no, solo se avisa).
var block_over_speed: bool = false


func copy() -> TurnTracker:
	var t: TurnTracker = TurnTracker.new()
	t.active = active
	t.round = round
	t.order = order.duplicate()
	t.current = current
	t.initiative = initiative.duplicate()
	t.moved_ft = moved_ft
	t.block_over_speed = block_over_speed
	return t


func equals(o: TurnTracker) -> bool:
	return o != null and CanonicalJson.stringify(to_dict()) == CanonicalJson.stringify(o.to_dict())


## Id de la ficha del turno actual; -1 si no hay combate.
func current_token_id() -> int:
	if not active or current < 0 or current >= order.size():
		return -1
	return order[current]


func has_token(token_id: int) -> bool:
	return order.has(token_id)


## Pies que le quedan a la ficha `t` en este turno: su velocidad menos lo
## gastado si es su turno; su velocidad entera si no lo es (o no hay
## combate). 0 = sin límite conocido.
func remaining_ft(t: MapToken, profile: SystemProfile) -> int:
	var speed: int = t.speed_ft(profile)
	if speed <= 0:
		return 0
	if t.id == current_token_id():
		return speed - moved_ft
	return speed


## true si el DM bloquea pasar de la velocidad y moverse `cost_ft` dejaría a
## la ficha `t` por encima de lo que le queda en su turno. Solo cuenta la
## ficha del turno actual; las demás se mueven libremente.
func blocks_move(t: MapToken, profile: SystemProfile, cost_ft: int) -> bool:
	if not block_over_speed or t.id != current_token_id() or t.speed_ft(profile) <= 0:
		return false
	return cost_ft > remaining_ft(t, profile)


## Pone las fichas `ids` en orden de iniciativa: mayor resultado primero; a
## igualdad, mayor modificador del personaje; luego, id menor (orden estable
## y sin azar). Las que no tienen resultado van al final.
func sort_order(doc: MapDocument) -> void:
	var ids: Array[int] = []
	for id: int in order:
		if doc.token(id) != null:
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ia: int = initiative.get(a, -10000)
		var ib: int = initiative.get(b, -10000)
		if ia != ib:
			return ia > ib
		var ma: int = _mod(doc, a)
		var mb: int = _mod(doc, b)
		if ma != mb:
			return ma > mb
		return a < b)
	order = PackedInt32Array(ids)


static func _mod(doc: MapDocument, id: int) -> int:
	var t: MapToken = doc.token(id)
	if t == null or t.sheet == null or not t.sheet.has_initiative:
		return -10000
	return t.sheet.initiative


## Pasa al turno siguiente (saltando fichas que ya no existen); al dar la
## vuelta, ronda nueva. El movimiento gastado vuelve a 0.
func advance(doc: MapDocument) -> void:
	if order.is_empty():
		active = false
		return
	moved_ft = 0
	for _i: int in order.size():
		current += 1
		if current >= order.size():
			current = 0
			round += 1
		if doc.token(order[current]) != null:
			return


func to_dict() -> Dictionary:
	var init: Dictionary = {}
	var keys: Array = initiative.keys()
	keys.sort()
	for k: int in keys:
		init[str(k)] = initiative[k]
	return {
		"active": active,
		"round": round,
		"order": Array(order),
		"current": current,
		"initiative": init,
		"moved_ft": moved_ft,
		"block_over_speed": block_over_speed,
	}


static func from_dict(r: JsonReader, d: Dictionary) -> TurnTracker:
	var t: TurnTracker = TurnTracker.new()
	t.active = r.get_bool(d, "active")
	t.round = r.get_int(d, "round")
	t.order = r.get_ints(d, "order")
	t.current = r.get_int(d, "current")
	var init: Dictionary = r.get_dict(d, "initiative")
	for k: Variant in init:
		var ks: String = r.to_str(k, "initiative")
		if not ks.is_valid_int():
			r.fail("initiative: clave no numérica '%s'" % ks)
			continue
		t.initiative[ks.to_int()] = r.to_int(init[k], "initiative")
	t.moved_ft = r.get_int(d, "moved_ft")
	t.block_over_speed = r.get_bool(d, "block_over_speed")
	if t.round < 1 or t.current < 0 or (t.active and t.current >= t.order.size()):
		r.fail("turns: ronda o turno actual no válidos")
	return t
