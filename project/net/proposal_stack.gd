class_name ProposalStack
extends CommandStack
## Historial "de mentira" del cliente de red (F4, ADR 031). Las vistas creen
## que ejecutan comandos, pero aquí no se aplica nada: el comando se entrega a
## `accept` (la UI lo convierte en una propuesta al servidor) y la copia local
## del mapa solo cambia cuando el DM lo aprueba y llega la actualización.
## Así las vistas no necesitan saber si están en red.

## Callable(cmd: MapCommand) -> bool: true si se envió como propuesta.
var accept: Callable = Callable()


func execute(cmd: MapCommand, _merge: bool = false) -> bool:
	if not accept.is_valid():
		return false
	var ok: bool = accept.call(cmd)
	return ok


func execute_attached(_cmd: MapCommand) -> bool:
	return false


func undo() -> bool:
	return false


func redo() -> bool:
	return false
