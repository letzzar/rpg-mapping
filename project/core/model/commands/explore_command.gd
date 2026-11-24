class_name ExploreCommand
extends MapCommand
## Marca casillas como exploradas por un observador (niebla de guerra,
## PROYECTO §7). Es estado de partida (sesión): no cambia content_hash().
##
## Solo guarda las casillas que de verdad cambian, en orden por filas, para
## deshacer exactamente. Lo normal es ejecutarlo unido al movimiento que lo
## provoca (CommandStack.execute_attached): deshacer el movimiento vuelve a
## tapar lo que esa ficha descubrió.

const DELTA_OP: String = "explore"

var level_index: int = 0
var viewer: String = ""
var cells: Array[Vector2i] = []

var _changed: Array[Vector2i] = []


func _init(p_level: int, p_viewer: String, p_cells: Array[Vector2i]) -> void:
	level_index = p_level
	viewer = p_viewer
	cells = p_cells.duplicate()


## Comando con las casillas visibles (visible_map != 0) aún no exploradas.
static func from_visible(doc: MapDocument, p_level: int, p_viewer: String, visible: PackedByteArray) -> ExploreCommand:
	var lvl: MapLevel = doc.level(p_level)
	var out: Array[Vector2i] = []
	for i: int in visible.size():
		if visible[i] != 0:
			var c: Vector2i = doc.grid.cell_at(i)
			if not lvl.is_explored(p_viewer, c):
				out.append(c)
	return ExploreCommand.new(p_level, p_viewer, out)


func label_key() -> String:
	return "CMD_EXPLORE"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or level_index < 0 or level_index >= d.level_count() or viewer.is_empty():
		return false
	var lvl: MapLevel = d.level(level_index)
	_changed.clear()
	for c: Vector2i in cells:
		if d.grid.in_bounds(c) and not lvl.is_explored(viewer, c):
			_changed.append(c)
	if _changed.is_empty():
		return false
	var list: Array = []
	for c: Vector2i in _changed:
		lvl.set_explored(viewer, c, true)
		list.append([c.x, c.y])
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "viewer": viewer, "cells": list}))
	d.notify_changed(level_index, MapDocument.LAYER_FOG)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or _changed.is_empty():
		return
	var lvl: MapLevel = d.level(level_index)
	for c: Vector2i in _changed:
		lvl.set_explored(viewer, c, false)
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var delta: MapDelta = d.deltas[i]
		if delta.op == DELTA_OP and delta.data.get("viewer", "") == viewer:
			d.deltas.remove_at(i)
			break
	_changed.clear()
	d.notify_changed(level_index, MapDocument.LAYER_FOG)
