class_name PngExporter
extends RefCounted
## Exporta un nivel de un MapDocument a PNG a una resolución conocida
## (píxeles por casilla), para imprimir o llevar a otra mesa virtual
## (PROYECTO.md §7; la impresión a escala por páginas llega antes de v1).
##
## Renderiza una MapView2D no interactiva en un SubViewport fuera de pantalla.
## Necesita un renderizador real: en modo headless no hay imagen.

const DEFAULT_PX_PER_CELL: int = 100
## Margen alrededor del mapa, en píxeles.
const MARGIN_PX: int = 0


## Renderiza y devuelve la imagen (null si no se pudo). `host` es cualquier
## nodo dentro del árbol, que hace de padre temporal del SubViewport.
static func render(host: Node, doc: MapDocument, level_index: int, profile: SystemProfile,
		px_per_cell: int = DEFAULT_PX_PER_CELL, dm_view: bool = false, show_grid: bool = true, show_tokens: bool = true) -> Image:
	if host == null or not host.is_inside_tree() or doc == null:
		return null
	var view: MapView2D = MapView2D.new()
	view.interactive = false
	view.cell_px = float(px_per_cell)
	view.profile = profile
	view.dm_view = dm_view
	view.show_grid = show_grid
	view.show_tokens = show_tokens
	view.document = doc
	view.level_index = level_index
	var size: Vector2 = doc.grid.map_pixel_size(view.cell_px)
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(ceili(size.x) + MARGIN_PX * 2, ceili(size.y) + MARGIN_PX * 2)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	view.position = Vector2(MARGIN_PX, MARGIN_PX)
	vp.add_child(view)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## Renderiza y guarda en `path`. Devuelve el código de error de Godot.
static func save(host: Node, doc: MapDocument, level_index: int, profile: SystemProfile, path: String,
		px_per_cell: int = DEFAULT_PX_PER_CELL, dm_view: bool = false, show_grid: bool = true) -> Error:
	var img: Image = await render(host, doc, level_index, profile, px_per_cell, dm_view, show_grid)
	if img == null or img.is_empty():
		return ERR_CANT_CREATE
	return img.save_png(path)
