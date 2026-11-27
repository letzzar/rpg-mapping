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
	## Estancia propia con la que se abrió (texto canónico de la entrada de
	## MapDocument.child_overrides; "" = el hijo generado). Si en el padre
	## cambia, el mapa guardado en `visited` ya no vale (ADR 040).
	var override_key: String = ""
	## Entorno de alrededor (Surroundings, ADR 052): qué se ve fuera del mapa.
	var surroundings: String = ""


var frames: Array[Frame] = []
## Último error (clave i18n), "" si la última operación fue bien.
var error: String = ""


## Empieza una ruta nueva con `doc` como raíz (al generar desde un código).
func open_root(doc: MapDocument) -> Frame:
	frames.clear()
	var f: Frame = Frame.new()
	f.doc = doc
	f.stack = CommandStack.new(doc)
	f.surroundings = Surroundings.default_for(doc)
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
func enter(child: MapChild, from_level: int, profile: SystemProfile, keep_positions: bool = false, move_party: bool = true) -> Frame:
	error = ""
	var here: Frame = current()
	if here == null or child == null:
		error = "UI_NAV_NO_CHILD"
		return null
	# Hijo sustituido por una estancia propia (ADR 040): se abre ella, de un
	# nivel, y el grupo entra y sale por su puerta (no es el mismo sitio a la
	# misma escala, así que no hay casillas equivalentes).
	var ov: Dictionary = here.doc.child_overrides.get(child.id, {})
	var ov_key: String = CanonicalJson.stringify(ov) if not ov.is_empty() else ""
	var overridden: bool = not ov_key.is_empty()
	var child_level: int = 0 if overridden else child.child_level
	if overridden:
		keep_positions = false
	var f: Frame = here.visited.get(child.id, null)
	if f != null and f.override_key != ov_key:
		f = null
	if f == null:
		var doc: MapDocument = null
		if overridden:
			var lr: MapFile.LoadResult = RoomContent.from_override(ov)
			if lr.doc == null:
				error = lr.error
				return null
			doc = lr.doc
		else:
			var res: GeneratorRegistry.Result = GeneratorRegistry.generate(child.seed_code)
			if res.doc == null:
				error = res.error
				return null
			doc = res.doc
		f = Frame.new()
		f.doc = doc
		f.stack = CommandStack.new(doc)
		f.child = child
		f.level_index = child_level
		f.override_key = ov_key
		f.surroundings = Surroundings.of_child(here.doc, here.surroundings, from_level, child)
		here.visited[child.id] = f
	here.level_index = from_level
	f.keep_positions = keep_positions
	f.parent_level = from_level
	var door_cell: Vector2i = _door_cell(f, child, child_level, overridden, keep_positions)
	var moving: Array[MapToken] = []
	var targets: Array[Vector2i] = []
	var src_party: Array[MapToken] = []
	if move_party:
		src_party = _party_of(here.doc, from_level)
	for t: MapToken in src_party:
		if keep_positions and not child.rect.has_point(t.cell):
			continue
		moving.append(t)
		targets.append(child.to_child_cell(t.cell) if keep_positions else door_cell)
	_transfer(here, moving, f, child_level, targets, profile)
	f.level_index = child_level
	frames.append(f)
	return f


## Casilla por la que se entra en el hijo (su puerta).
static func _door_cell(f: Frame, child: MapChild, child_level: int, overridden: bool, keep_positions: bool) -> Vector2i:
	var door_cell: Vector2i = RoomContent.entrance_cell(f.doc) if overridden else child.to_child_cell(child.entrance)
	if not overridden and not keep_positions:
		door_cell = _usable_door(f.doc, child_level, door_cell)
	return door_cell


## Ruta de hijos desde la raíz hasta el mapa actual (vacía en la raíz).
func current_path() -> Array[MapChild]:
	var out: Array[MapChild] = []
	for i: int in range(1, frames.size()):
		out.append(frames[i].child)
	return out


## Salta a cualquier mapa (ADR 050): `path` son los hijos desde la raíz (los
## ya visitados se reabren como se dejaron; el último puede ser uno nuevo del
## mapa actual, que está en su nivel `last_from_level`). Sin `carry` solo
## cambia lo que se mira: las fichas se quedan donde estaban. Con `carry`, el
## grupo del mapa de partida va al destino: por la puerta del último hijo si
## se baja, o delante de la puerta por la que se salió si se sube.
func jump(path: Array[MapChild], last_from_level: int, carry: bool, profile: SystemProfile) -> Frame:
	error = ""
	if frames.is_empty():
		error = "UI_NAV_NO_CHILD"
		return null
	var origin: Frame = current()
	var old_frames: Array[Frame] = frames.duplicate()
	var k: int = 0
	while k < path.size() and k + 1 < frames.size() and frames[k + 1].child != null and path[k] != null \
			and frames[k + 1].child.id == path[k].id:
		k += 1
	# El hijo del destino por el que se había bajado (si se sube a él).
	var came_from: Frame = frames[k + 1] if k + 1 < frames.size() else null
	while frames.size() > k + 1:
		var inner: Frame = frames.pop_back()
		current().level_index = inner.parent_level
	for i: int in range(k, path.size()):
		var here: Frame = current()
		var c: MapChild = path[i]
		var known: Frame = null
		if c != null and here.visited.has(c.id):
			known = here.visited[c.id]
		var from_level: int = known.parent_level if known != null else last_from_level
		var keep: bool = known.keep_positions if known != null else false
		if enter(c, from_level, profile, keep, false) == null:
			# Se deja la ruta como estaba: un hijo que no se genera no rompe nada.
			var err: String = error
			frames = old_frames
			error = err
			return null
	var dst: Frame = current()
	if not carry or dst == origin:
		return dst
	var party: Array[MapToken] = _party_of(origin.doc, -1)
	if party.is_empty():
		return dst
	var level: int = dst.level_index
	var cell: Vector2i = Vector2i.ZERO
	if path.size() > k:
		var c: MapChild = path[-1]
		var ov: bool = not dst.override_key.is_empty()
		level = 0 if ov else c.child_level
		cell = _door_cell(dst, c, level, ov, false)
	elif came_from != null:
		level = came_from.parent_level
		cell = came_from.child.entrance
	var targets: Array[Vector2i] = []
	for t: MapToken in party:
		targets.append(cell)
	_transfer(origin, party, dst, level, targets, profile)
	dst.level_index = level
	return dst


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


## Casilla de llegada al entrar "por la puerta": `cell` si es transitable; si
## no (punto de interés de una región con mazmorra MAZ, cuya entrada no se
## conoce sin generarla, GeoLinks.poi_child), la primera casilla de la zona
## "entrance" del nivel; si tampoco la hay, `cell`.
static func _usable_door(doc: MapDocument, level: int, cell: Vector2i) -> Vector2i:
	var lvl: MapLevel = doc.level(level)
	if lvl == null or Terrain.is_passable(lvl.get_terrain(cell)):
		return cell
	for r: MapRoom in lvl.rooms:
		if r.kind == MapRoom.KIND_ENTRANCE:
			var cells: Array[Vector2i] = lvl.room_cells(r.id)
			if not cells.is_empty():
				return cells[0]
	return cell


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
