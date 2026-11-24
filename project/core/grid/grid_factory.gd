class_name GridFactory
extends RefCounted
## Crea la geometría de rejilla a partir de su id (los de GridGeometry.KINDS).
##
## Va aparte de GridGeometry para que la clase base no tenga que conocer a sus
## subclases (evita referencias cíclicas entre scripts con class_name).


## Geometría de `kind` ("square", "hex_flat", "hex_pointy") de width×height
## casillas; null si el tipo es desconocido o el tamaño no está en
## [1, GridGeometry.MAX_SIDE].
static func create(kind: String, width: int, height: int) -> GridGeometry:
	if width < 1 or height < 1 or width > GridGeometry.MAX_SIDE or height > GridGeometry.MAX_SIDE:
		return null
	match kind:
		GridGeometry.KIND_SQUARE:
			return SquareGrid.new(width, height)
		GridGeometry.KIND_HEX_FLAT:
			return HexGrid.new(false, width, height)
		GridGeometry.KIND_HEX_POINTY:
			return HexGrid.new(true, width, height)
	return null
