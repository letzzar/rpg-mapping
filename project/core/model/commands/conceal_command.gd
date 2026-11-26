class_name ConcealCommand
extends MapCommand
## Vuelve a tapar casillas exploradas por un observador (modo proyectado,
## ADR 039: el DM oculta lo que reveló de más). Lo contrario de
## ExploreCommand; solo guarda las casillas que cambian.

const DELTA_OP: String = "conceal"

var level_index: int = 0
var viewer: String = ""
var cells: Array[Vector2i] = []
var _changed: Array[Vector2i] = []


func _init(p_level: int, p_viewer: String, p_cells: Array[Vector2i]) -> void:
	level_index = p_level
	viewer = p_viewer
	cells = p_cells.duplicate()


func label_key() -> String:
	return "CMD_CONCEAL"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null or viewer.is_empty():
		return false
	var lvl: MapLevel = d.level(level_index)
	_changed.clear()
	for c: Vector2i in cells:
		if d.grid.in_bounds(c) and lvl.is_explored(viewer, c) and not _changed.has(c):
			_changed.append(c)
	if _changed.is_empty():
		return false
	var list: Array = []
	for c: Vector2i in _changed:
		lvl.set_explored(viewer, c, false)
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
		lvl.set_explored(viewer, c, true)
	for i: int in range(d.deltas.size() - 1, -1, -1):
		var dl: MapDelta = d.deltas[i]
		if dl.op == DELTA_OP and dl.data.get("viewer", "") == viewer:
			d.deltas.remove_at(i)
			break
	_changed.clear()
	d.notify_changed(level_index, MapDocument.LAYER_FOG)
