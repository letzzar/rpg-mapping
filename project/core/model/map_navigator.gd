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
## entrada (MapChild.entrance, ADR 027) y fuera, otra vez delante de ella (o,
## en modo `keep_positions`, edificio → estancia, cada una en su misma
## casilla: ver Frame.keep_positions). El
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
	## Modo de paso de fichas con el padre: false = "por la puerta" (todo el
	## grupo del nivel entra por MapChild.entrance; aldea → edificio); true =
	## "misma casilla" (solo las fichas del grupo que ya están dentro de la
	## huella pasan, cada una a su casilla equivalente; edificio → estancia,
	## que es un acercamiento 1:1 del mismo sitio).
	var keep_positions: bool = false
	## Nivel del padre desde el que se entró (destino al salir).
	var parent_level: int = 0


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
## `keep_positions`: ver Frame.keep_positions.
func enter(child: MapChild, from_level: int, profile: SystemProfile, keep_positions: bool = false) -> Frame:
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
	f.keep_positions = keep_positions
	f.parent_level = from_level
	var moving: Array[MapToken] = []
	var targets: Array[Vector2i] = []
	for t: MapToken in _party_of(here.doc, from_level):
		if keep_positions and not child.rect.has_point(t.cell):
			continue
		moving.append(t)
		targets.append(child.to_child_cell(t.cell) if keep_positions else child.to_child_cell(child.entrance))
	_transfer(here, moving, f, child.child_level, targets, profile)
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
	outer.level_index = inner.parent_level
	var moving: Array[MapToken] = _party_of(inner.doc, -1)
	var targets: Array[Vector2i] = []
	for t: MapToken in moving:
		targets.append(t.cell + inner.child.offset if inner.keep_positions else inner.child.entrance)
	_transfer(inner, moving, outer, inner.parent_level, targets, profile)
	return outer


## Fichas del grupo de `doc` en `level` (todas si es -1), en orden de la lista.
static func _party_of(doc: MapDocument, level: int) -> Array[MapToken]:
	var party: Array[MapToken] = []
	for t: MapToken in doc.tokens:
		if PartyVision.SIDES_IN_PARTY.has(t.side) and (level < 0 or t.level == level):
			party.append(t)
	return party


## Pasa `tokens` de `src` a `dst` (nivel `dst_level`): cada una a su casilla
## de `targets` si está libre y es transitable; si no, a la libre más cercana.
## Después vacía la historia de los dos mapas (cruzar no se deshace).
func _transfer(src: Frame, tokens: Array[MapToken], dst: Frame, dst_level: int, targets: Array[Vector2i], profile: SystemProfile) -> void:
	if tokens.is_empty():
		return
	for i: int in tokens.size():
		var t: MapToken = tokens[i]
		var cells: Array[Vector2i] = free_cells_near(dst.doc, dst_level, targets[i], profile, 1)
		if cells.is_empty():
			continue  # No cabe: se queda donde estaba (no ocurre con un grupo normal).
		var moved: MapToken = t.copy()
		src.stack.execute(RemoveTokenCommand.new(t.id))
		moved.id = dst.doc.allocate_id()
		moved.level = dst_level
		moved.cell = cells[0]
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
