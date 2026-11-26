class_name SetTerrainCommand
extends MapCommand
## Pinta un tipo de terreno en varias casillas de un nivel (editor de
## estancias, ADR 037). Una pincelada entera es un solo paso de deshacer. Solo
## guarda las casillas que cambian de verdad.

const DELTA_OP: String = "set_terrain"

var level_index: int = 0
var cells: Array[Vector2i] = []
var terrain: int = Terrain.FLOOR

var _changed: Array[Vector2i] = []
var _old: PackedByteArray = PackedByteArray()


func _init(p_level: int, p_cells: Array[Vector2i], p_terrain: int) -> void:
	level_index = p_level
	cells = p_cells.duplicate()
	terrain = p_terrain


func label_key() -> String:
	return "CMD_SET_TERRAIN"


func apply(doc: Object) -> bool:
	var d: MapDocument = doc as MapDocument
	if d == null or d.level(level_index) == null or not Terrain.is_valid(terrain):
		return false
	var lvl: MapLevel = d.level(level_index)
	_changed.clear()
	_old.clear()
	var seen: Dictionary[Vector2i, bool] = {}
	for c: Vector2i in cells:
		if seen.has(c) or not d.grid.in_bounds(c) or lvl.get_terrain(c) == terrain:
			continue
		seen[c] = true
		_changed.append(c)
		_old.append(lvl.get_terrain(c))
	if _changed.is_empty():
		return false
	var list: Array = []
	for c: Vector2i in _changed:
		lvl.set_terrain(c, terrain)
		list.append([c.x, c.y])
	d.deltas.append(MapDelta.make(DELTA_OP, {"level": level_index, "terrain": terrain, "cells": list}))
	d.notify_changed(level_index, MapDocument.LAYER_TERRAIN)
	return true


func revert(doc: Object) -> void:
	var d: MapDocument = doc as MapDocument
	if d == null or _changed.is_empty():
		return
	var lvl: MapLevel = d.level(level_index)
	for i: int in _changed.size():
		lvl.set_terrain(_changed[i], _old[i])
	for i: int in range(d.deltas.size() - 1, -1, -1):
		if d.deltas[i].op == DELTA_OP:
			d.deltas.remove_at(i)
			break
	_changed.clear()
	d.notify_changed(level_index, MapDocument.LAYER_TERRAIN)
