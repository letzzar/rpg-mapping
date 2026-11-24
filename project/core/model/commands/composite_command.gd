class_name CompositeCommand
extends MapCommand
## Varios comandos que se deshacen y rehacen como un solo paso (p. ej. mover
## una ficha y explorar lo que ve desde su nueva casilla). Se aplican en
## orden y se deshacen al revés. La etiqueta es la del primero.

var parts: Array[MapCommand] = []


func _init(p_parts: Array[MapCommand] = []) -> void:
	parts = p_parts.duplicate()


func label_key() -> String:
	return parts[0].label_key() if not parts.is_empty() else super.label_key()


## Si una parte no aplica, deshace las anteriores y devuelve false.
func apply(doc: Object) -> bool:
	var done: int = 0
	for p: MapCommand in parts:
		if not p.apply(doc):
			break
		done += 1
	if done == parts.size():
		return not parts.is_empty()
	for i: int in range(done - 1, -1, -1):
		parts[i].revert(doc)
	return false


func revert(doc: Object) -> void:
	for i: int in range(parts.size() - 1, -1, -1):
		parts[i].revert(doc)
