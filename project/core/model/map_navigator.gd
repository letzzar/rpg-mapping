class_name MapNavigator
extends RefCounted
## Navegación jerárquica entre mapas (F3): asentamiento → edificio (y, más
## adelante, edificio → estancia, región → asentamiento).
##
## Guarda la ruta de mapas abiertos (`frames`, el último es el actual). Cada
## mapa conserva su sesión (fichas, niebla explorada, deltas) mientras la ruta
## siga abierta, y los hijos ya visitados se guardan en su padre: volver a
## entrar en la misma taberna la encuentra como se dejó.
##
## Al entrar o salir pasa las fichas del grupo (PartyVision.SIDES_IN_PARTY)
## por la puerta: dentro aparecen en la casilla del hijo que corresponde a la
## entrada (MapChild.entrance, ADR 027) y fuera, otra vez delante de ella. El
## paso se hace con comandos (RemoveTokenCommand / AddTokenCommand) en la
## pila de cada mapa y después se vacían las dos historias: deshacer no puede
## devolver una ficha a un mapa que ya no se está mirando.
##
## No toca nodos ni escenas: la UI solo muestra `current()`.

class Frame:
	extends RefCounted
	var doc: MapDocument = null
	var stack: CommandStack = null
	## Nivel que se estaba mirando (se restaura al volver).
	var level_index: int = 0
	## Hijo del padre por el que se entró (null en la raíz).
	var child: MapChild = null
	## Hijos ya generados de este mapa, por MapChild.id.
	var visited: Dictionary[int, Frame] = {}


var frames: Array[Frame] = []
## Último error (clave i18n), "" si la última operación fue bien.
var error: String = ""


## Empieza una ruta nueva con `doc` como raíz (al generar desde un código).
func open_root(doc: MapDocument) -> Frame:
	frames.clear()
	var f: Frame = Frame.new()
	f.doc = doc
	f.stack = CommandStack.new(doc)
	frames.append(f)
	return f


func current() -> Frame:
	return frames[-1] if not frames.is_empty() else null


func depth() -> int:
	return frames.size()


func can_go_back() -> bool:
	return frames.size() > 1


## Padre del mapa actual (null en la raíz).
func parent() -> Frame:
	return frames[-2] if frames.size() > 1 else null


## Entra en `child` (de `current()`, nivel `from_level`). Genera el hijo desde
## su código la primera vez. Devuelve el nuevo mapa actual o null con `error`.
func enter(child: MapChild, from_level: int, profile: SystemProfile) -> Frame:
	error = ""
	var here: Frame = current()
	if here == null or child == null:
		error = "UI_NAV_NO_CHILD"
		return null
	var f: Frame = here.visited.get(child.id, null)
	if f == null:
		var res: GeneratorRegistry.Result = GeneratorRegistry.generate(child.seed_code)
		if res.doc == null:
			error = res.error
			return null
		f = Frame.new()
		f.doc = res.doc
		f.stack = CommandStack.new(res.doc)
		f.child = child
		f.level_index = child.child_level
		here.visited[child.id] = f
	here.level_index = from_level
	_move_party(here, from_level, f, child.child_level, child.to_child_cell(child.entrance), profile)
	f.level_index = child.child_level
	frames.append(f)
	return f


## Vuelve al mapa padre, sacando al grupo por la puerta del hijo.
func back(profile: SystemProfile) -> Frame:
	error = ""
	if not can_go_back():
		error = "UI_NAV_NO_PARENT"
		return null
	var inner: Frame = frames.pop_back()
	var outer: Frame = current()
	_move_party(inner, -1, outer, outer.level_index, inner.child.entrance, profile)
	return outer


## Fichas del grupo de `src` (en `src_level`, o en todos si es -1) a `dst`,
## en las casillas libres más cercanas a `start` (nivel `dst_level`).
func _move_party(src: Frame, src_level: int, dst: Frame, dst_level: int, start: Vector2i, profile: SystemProfile) -> void:
	var party: Array[MapToken] = []
	for t: MapToken in src.doc.tokens:
		if PartyVision.SIDES_IN_PARTY.has(t.side) and (src_level < 0 or t.level == src_level):
			party.append(t)
	if party.is_empty():
		return
	var cells: Array[Vector2i] = free_cells_near(dst.doc, dst_level, start, profile, party.size())
	var k: int = 0
	for t: MapToken in party:
		if k >= cells.size():
			break  # No caben: se quedan fuera (no ocurre con un grupo normal).
		var moved: MapToken = t.copy()
		src.stack.execute(RemoveTokenCommand.new(t.id))
		moved.id = dst.doc.allocate_id()
		moved.level = dst_level
		moved.cell = cells[k]
		k += 1
		dst.stack.execute(AddTokenCommand.new(moved))
	src.stack.clear()
	dst.stack.clear()


## Hasta `max_count` casillas transitables y sin ficha de `level`, por
## distancia en pasos (sin cruzar muros ni puertas cerradas) desde `start`.
## Para en cuanto tiene bastantes: una ciudad tiene ~35 000 casillas y
## recorrerla entera costaba ~0,5 s por entrada o salida.
static func free_cells_near(doc: MapDocument, level: int, start: Vector2i, profile: SystemProfile, max_count: int = 64) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var g: GridGeometry = doc.grid
	if not g.in_bounds(start) or level < 0 or level >= doc.level_count():
		return out
	var lvl: MapLevel = doc.level(level)
	var mask: PackedByteArray = lvl.movement_mask()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(g.cell_count())
	var queue: Array[Vector2i] = [start]
	seen[g.index_of(start)] = 1
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var passable: bool = (mask[g.index_of(c)] & MapLevel.MOVE_PASSABLE) != 0
		if passable and (profile == null or doc.tokens_at(level, c, profile).is_empty()):
			out.append(c)
			if out.size() >= max_count:
				break
		if not passable and c != start:
			continue
		for dir: int in g.direction_count():
			var n: Vector2i = g.neighbor(c, dir)
			if not g.in_bounds(n):
				continue
			var ni: int = g.index_of(n)
			if seen[ni] != 0 or (mask[ni] & MapLevel.MOVE_PASSABLE) == 0:
				continue
			if dir < g.edge_direction_count() and not MapEdge.is_traversable(lvl.get_edge(c, dir)):
				continue
			seen[ni] = 1
			queue.append(n)
	return out
