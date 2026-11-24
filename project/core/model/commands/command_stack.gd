class_name CommandStack
extends RefCounted
## Historial de deshacer/rehacer sobre un documento.
##
## Uso:
##   var stack := CommandStack.new(doc)
##   stack.execute(MoveTokenCommand.new(...))
##   stack.undo(); stack.redo()
## Emite `changed` después de cada operación que modifica el documento, para
## que las vistas se redibujen.

signal changed

## Número máximo de pasos que se pueden deshacer (los más antiguos se olvidan).
const DEFAULT_LIMIT: int = 200

var document: Object = null
var limit: int = DEFAULT_LIMIT

var _done: Array[MapCommand] = []
var _undone: Array[MapCommand] = []


func _init(doc: Object = null, max_steps: int = DEFAULT_LIMIT) -> void:
	document = doc
	limit = maxi(1, max_steps)


## Aplica el comando. Si se aplica, borra el historial de rehacer. Si
## `merge` es true y el último comando lo absorbe, no crea un paso nuevo.
func execute(cmd: MapCommand, merge: bool = false) -> bool:
	if not cmd.apply(document):
		return false
	_undone.clear()
	if merge and not _done.is_empty() and _done[-1].merge_with(cmd):
		changed.emit()
		return true
	_done.append(cmd)
	while _done.size() > limit:
		_done.pop_front()
	changed.emit()
	return true


## Aplica `cmd` como parte del último paso del historial (se deshará junto
## con él). Si no hay paso previo, crea uno nuevo. No borra el historial de
## rehacer si no se aplica.
func execute_attached(cmd: MapCommand) -> bool:
	if _done.is_empty():
		return execute(cmd)
	if not cmd.apply(document):
		return false
	_undone.clear()
	var last: MapCommand = _done[-1]
	var comp: CompositeCommand = last as CompositeCommand
	if comp == null:
		var parts: Array[MapCommand] = [last]
		comp = CompositeCommand.new(parts)
		_done[-1] = comp
	comp.parts.append(cmd)
	changed.emit()
	return true


func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


func undo() -> bool:
	if _done.is_empty():
		return false
	var cmd: MapCommand = _done.pop_back()
	cmd.revert(document)
	_undone.append(cmd)
	changed.emit()
	return true


func redo() -> bool:
	if _undone.is_empty():
		return false
	var cmd: MapCommand = _undone.pop_back()
	if not cmd.apply(document):
		# El documento cambió por otra vía y el comando ya no aplica: se
		# descarta el resto del historial de rehacer para no desincronizar.
		_undone.clear()
		changed.emit()
		return false
	_done.append(cmd)
	changed.emit()
	return true


## Clave i18n del paso que se desharía ("" si no hay).
func undo_label_key() -> String:
	return _done[-1].label_key() if not _done.is_empty() else ""


func redo_label_key() -> String:
	return _undone[-1].label_key() if not _undone.is_empty() else ""


## Comandos aplicados, del más antiguo al más reciente (base de los deltas).
func applied() -> Array[MapCommand]:
	return _done.duplicate()


func clear() -> void:
	_done.clear()
	_undone.clear()
	changed.emit()
