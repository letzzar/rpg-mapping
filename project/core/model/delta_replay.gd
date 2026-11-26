class_name DeltaReplay
extends RefCounted
## Reaplica ediciones (PROYECTO §5 y §6.7, ADR 004 y 036): convierte cada
## MapDelta en el comando que lo creó y lo aplica sobre el documento. Como
## cada comando añade su propio delta al aplicarse, el documento recreado
## acaba con la misma lista de deltas que el original.
##
## Regla para comandos nuevos: su delta tiene que llevar TODO lo necesario
## para rehacerlo (no solo un resumen para el registro) y hay que añadir su
## `op` aquí, con un test de ida y vuelta en test_delta_replay.gd.


class Result:
	extends RefCounted
	## Deltas aplicados.
	var applied: int = 0
	## Clave i18n del error ("" si todo se aplicó).
	var error: String = ""
	## Detalle técnico (para el registro).
	var detail: String = ""


## Aplica `deltas` en orden sobre `doc` (sin historial). Se detiene en el
## primero que no se pueda aplicar.
static func replay(doc: MapDocument, deltas: Array[MapDelta]) -> Result:
	var res: Result = Result.new()
	for i: int in deltas.size():
		var dl: MapDelta = deltas[i]
		var r: JsonReader = JsonReader.new()
		var cmd: MapCommand = command_for(r, doc, dl)
		if cmd == null:
			res.error = "MAP_ERR_DELTA"
			res.detail = "delta %d (%s): %s" % [i, dl.op, r.error if not r.ok() else "operación desconocida"]
			return res
		if not cmd.apply(doc):
			res.error = "MAP_ERR_DELTA"
			res.detail = "delta %d (%s): no se puede aplicar" % [i, dl.op]
			return res
		# El contador de ids tiene que pasar de los ids ya usados.
		if dl.op == AddTokenCommand.DELTA_OP:
			doc.reserve_ids_through(r.get_int(dl.data, "token"))
		elif dl.op == AddObjectCommand.DELTA_OP:
			doc.reserve_ids_through(r.get_int(dl.data, "id"))
		res.applied += 1
	return res


## Comando equivalente a `dl` (null si la operación es desconocida o los
## datos no valen; el motivo queda en `r.error`).
static func command_for(r: JsonReader, doc: MapDocument, dl: MapDelta) -> MapCommand:
	var d: Dictionary = dl.data
	var cmd: MapCommand = null
	match dl.op:
		AddTokenCommand.DELTA_OP:
			cmd = AddTokenCommand.new(MapToken.from_dict(r, r.get_dict(d, "data")))
		RemoveTokenCommand.DELTA_OP:
			cmd = RemoveTokenCommand.new(r.get_int(d, "token"))
		MoveTokenCommand.DELTA_OP:
			cmd = MoveTokenCommand.new(r.get_int(d, "token"), Vector2i(r.get_int(d, "x"), r.get_int(d, "y")),
				r.get_int(d, "level"), r.get_int(d, "cost"))
		SetEdgeCommand.DELTA_OP:
			cmd = SetEdgeCommand.new(r.get_int(d, "level"), r.get_int(d, "edge"), r.get_int(d, "value"))
		ExploreCommand.DELTA_OP:
			cmd = ExploreCommand.new(r.get_int(d, "level"), r.get_str(d, "viewer"), _cells(r, d))
		ConcealCommand.DELTA_OP:
			cmd = ConcealCommand.new(r.get_int(d, "level"), r.get_str(d, "viewer"), _cells(r, d))
		SetTerrainCommand.DELTA_OP:
			cmd = SetTerrainCommand.new(r.get_int(d, "level"), _cells(r, d), r.get_int(d, "terrain"))
		AddObjectCommand.DELTA_OP:
			cmd = AddObjectCommand.new(r.get_int(d, "level"), MapObject.from_dict(r, r.get_dict(d, "object")))
		RemoveObjectCommand.DELTA_OP:
			cmd = RemoveObjectCommand.new(r.get_int(d, "level"), r.get_int(d, "id"))
		SetRoomCommand.DELTA_OP:
			cmd = SetRoomCommand.new(r.get_int(d, "level"), r.get_int(d, "room"), r.get_str(d, "kind"), r.get_str(d, "label"))
		SetTokenCharacterCommand.DELTA_OP:
			cmd = SetTokenCharacterCommand.new(r.get_int(d, "token"), r.get_str(d, "ref"))
		SetTokenSheetCommand.DELTA_OP:
			var sd: Dictionary = r.get_dict(d, "sheet")
			var sheet: CharacterSheet = CharacterSheet.from_dict(r, sd) if not sd.is_empty() else null
			cmd = SetTokenSheetCommand.new(r.get_int(d, "token"), sheet)
		SetTurnsCommand.DELTA_OP:
			cmd = SetTurnsCommand.new(TurnTracker.from_dict(r, r.get_dict(d, "turns")), r.get_str(d, "label"))
		_:
			return null
	return cmd if r.ok() else null


## Lista "cells" de pares [x, y].
static func _cells(r: JsonReader, d: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for v: Variant in r.get_array(d, "cells"):
		var pair: Array = r.to_array(v, "cells")
		if pair.size() != 2:
			r.fail("cells: se esperaba [x, y]")
			break
		cells.append(Vector2i(r.to_int(pair[0], "cells"), r.to_int(pair[1], "cells")))
	return cells
