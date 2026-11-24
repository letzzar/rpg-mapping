class_name MapCommand
extends RefCounted
## Cambio reversible sobre un documento (PROYECTO.md §4, principio 2).
##
## Las vistas y la UI nunca modifican el modelo directamente: crean un
## MapCommand y lo pasan a CommandStack.execute(). Cada subclase guarda lo
## necesario para deshacerse (estado previo) y es determinista: aplicar la
## misma secuencia de comandos al mismo documento da siempre el mismo
## resultado, así que la lista de comandos aplicados sirve de base para los
## deltas de edición (seed + deltas).


## Clave i18n con la descripción para el historial ("Mover ficha"...).
func label_key() -> String:
	return "CMD_GENERIC"


## Aplica el cambio. Devuelve false si no se puede aplicar (p. ej. destino
## bloqueado); en ese caso no debe haber modificado nada.
func apply(_doc: Object) -> bool:
	return false


## Deshace exactamente lo hecho por apply().
func revert(_doc: Object) -> void:
	pass


## Si este comando puede absorber al siguiente (p. ej. varios pasos de un
## mismo arrastre), lo fusiona y devuelve true. Por defecto, no.
func merge_with(_next: MapCommand) -> bool:
	return false
