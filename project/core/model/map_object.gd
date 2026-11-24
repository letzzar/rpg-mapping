class_name MapObject
extends RefCounted
## Objeto colocado en un nivel (mobiliario, cofres, antorchas…), PROYECTO §6.5.
##
## Las propiedades de juego se COPIAN del catálogo (data/objects) al colocarlo:
## así el documento es autosuficiente, el DM puede cambiarlas en una instancia
## y el hash refleja lo que de verdad hay en el mapa (si cambia el catálogo,
## cambia la salida del generador: eso exige subir GEN).

const COVER_NONE: int = 0
const COVER_HALF: int = 1
const COVER_THREE_QUARTERS: int = 2
const COVER_TOTAL: int = 3

## Id estable (único en todo el documento).
var id: int = 0
## Id del catálogo de data/objects (p. ej. "table_round").
var catalog_id: String = ""
## Casilla de anclaje (esquina superior izquierda de la huella).
var cell: Vector2i = Vector2i.ZERO
## Huella en casillas (ancho, alto) antes de girar. En hex es un rectángulo
## en coordenadas offset (aproximado); lo normal en hex es 1×1.
var size: Vector2i = Vector2i.ONE
## Orientación: índice de dirección con arista hacia la que mira el objeto
## (0..GridGeometry.edge_direction_count()-1; 0 = N en cuadrada y hex_flat,
## NE en hex_pointy). En la cuadrada, 1 y 3 intercambian ancho y alto.
var facing: int = 0
var cover: int = COVER_NONE
var difficult_terrain: bool = false
var blocks_movement: bool = false
var blocks_sight: bool = false
## Radio de luz brillante y tenue en casillas (0 = no ilumina).
var light_bright_cells: int = 0
var light_dim_cells: int = 0
## Tipo de interacción ("" = no interactuable; p. ej. "chest", "lever").
var interaction: String = ""
## Altura física en mm (vista 3D y línea de visión).
var height_mm: int = 0


func copy() -> MapObject:
	var o: MapObject = MapObject.new()
	o.id = id
	o.catalog_id = catalog_id
	o.cell = cell
	o.size = size
	o.facing = facing
	o.cover = cover
	o.difficult_terrain = difficult_terrain
	o.blocks_movement = blocks_movement
	o.blocks_sight = blocks_sight
	o.light_bright_cells = light_bright_cells
	o.light_dim_cells = light_dim_cells
	o.interaction = interaction
	o.height_mm = height_mm
	return o


func to_dict() -> Dictionary:
	return {
		"id": id,
		"catalog_id": catalog_id,
		"cell": [cell.x, cell.y],
		"size": [size.x, size.y],
		"facing": facing,
		"cover": cover,
		"difficult_terrain": difficult_terrain,
		"blocks_movement": blocks_movement,
		"blocks_sight": blocks_sight,
		"light_bright_cells": light_bright_cells,
		"light_dim_cells": light_dim_cells,
		"interaction": interaction,
		"height_mm": height_mm,
	}


static func from_dict(r: JsonReader, d: Dictionary) -> MapObject:
	var o: MapObject = MapObject.new()
	o.id = r.get_int(d, "id")
	o.catalog_id = r.get_str(d, "catalog_id")
	o.cell = r.get_vec2i(d, "cell")
	o.size = r.get_vec2i(d, "size")
	o.facing = r.get_int(d, "facing")
	o.cover = r.get_int(d, "cover")
	o.difficult_terrain = r.get_bool(d, "difficult_terrain")
	o.blocks_movement = r.get_bool(d, "blocks_movement")
	o.blocks_sight = r.get_bool(d, "blocks_sight")
	o.light_bright_cells = r.get_int(d, "light_bright_cells")
	o.light_dim_cells = r.get_int(d, "light_dim_cells")
	o.interaction = r.get_str(d, "interaction")
	o.height_mm = r.get_int(d, "height_mm")
	if o.cover < COVER_NONE or o.cover > COVER_TOTAL:
		r.fail("cover fuera de rango")
	if o.size.x < 1 or o.size.y < 1:
		r.fail("size debe ser >= 1")
	return o
