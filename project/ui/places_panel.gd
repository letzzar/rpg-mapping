class_name PlacesPanel
extends PanelContainer
## Panel "Lugares" del DM (ADR 050): el árbol de mapas abiertos o visitados
## (mundo → región → ciudad → edificio → estancia) y los sitios del mapa que
## se mira, para ir a cualquiera con un doble clic. Puede ir solo a mirar
## (las fichas se quedan) o llevándose al grupo. No navega por sí mismo: pide
## el salto con `jump_requested` y la pantalla principal lo hace.

## Pide ir a `path` (hijos desde la raíz; el último puede ser nuevo, del
## nivel `from_level` del mapa actual), llevando al grupo si `carry`.
signal jump_requested(path: Array[MapChild], from_level: int, carry: bool)

## Máximo de sitios del mapa actual en la lista (una ciudad tiene cientos de
## edificios: se filtran por nombre).
const MAX_HERE: int = 300

## Nombre visible de un mapa (MapNavigator.Frame) — lo da la pantalla
## principal, que ya sabe nombrar cada escala.
var name_of: Callable = func(_f: MapNavigator.Frame) -> String: return ""

var _nav: MapNavigator = null
var _level: int = 0
var _tree: Tree
var _here_list: ItemList
var _filter: LineEdit
var _carry_opt: OptionButton
var _paths: Array = []
var _here: Array[MapChild] = []


func _init() -> void:
	custom_minimum_size = Vector2(280, 0)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	var title: Label = Label.new()
	title.text = tr("UI_PLACES")
	title.add_theme_color_override("font_color", Color("f7dc8e"))
	box.add_child(title)
	var hint: Label = Label.new()
	hint.text = tr("UI_PLACES_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	_carry_opt = OptionButton.new()
	_carry_opt.add_item(tr("UI_PLACES_LOOK"))
	_carry_opt.add_item(tr("UI_PLACES_CARRY"))
	_carry_opt.tooltip_text = tr("UI_PLACES_CARRY_TIP")
	box.add_child(_carry_opt)
	_tree = Tree.new()
	_tree.hide_root = false
	_tree.custom_minimum_size = Vector2(0, 180)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_on_tree_activated)
	box.add_child(_tree)
	var here_l: Label = Label.new()
	here_l.text = tr("UI_PLACES_HERE")
	box.add_child(here_l)
	_filter = LineEdit.new()
	_filter.placeholder_text = tr("UI_PLACES_FILTER")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _fill_here())
	box.add_child(_filter)
	_here_list = ItemList.new()
	_here_list.custom_minimum_size = Vector2(0, 160)
	_here_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_here_list.item_activated.connect(func(i: int) -> void: go_here(i))
	box.add_child(_here_list)
	var go: Button = Button.new()
	go.text = tr("UI_PLACES_GO")
	go.pressed.connect(_go_selected)
	box.add_child(go)


## Muestra la ruta de `nav`; `level` = nivel que se mira del mapa actual.
func set_navigator(nav: MapNavigator, level: int) -> void:
	_nav = nav
	_level = level
	refresh()


func carry() -> bool:
	return _carry_opt.selected == 1


func set_carry(on: bool) -> void:
	_carry_opt.select(1 if on else 0)


func refresh() -> void:
	_tree.clear()
	_paths.clear()
	if _nav == null or _nav.frames.is_empty():
		_fill_here()
		return
	var empty: Array[MapChild] = []
	_add_frame(null, _nav.frames[0], empty)
	_fill_here()


## Número de mapas del árbol (para las pruebas).
func tree_count() -> int:
	return _paths.size()


## Ruta del mapa `i` del árbol (orden de recorrido).
func tree_path(i: int) -> Array[MapChild]:
	var p: Array[MapChild] = []
	if i >= 0 and i < _paths.size():
		var src: Array = _paths[i]
		for c: MapChild in src:
			p.append(c)
	return p


## Sitios del mapa actual que se listan (ya filtrados).
func here_count() -> int:
	return _here.size()


func here_name(i: int) -> String:
	return _here_list.get_item_text(i) if i >= 0 and i < _here_list.item_count else ""


## Va al sitio `i` de la lista del mapa actual.
func go_here(i: int) -> void:
	if _nav == null or i < 0 or i >= _here.size():
		return
	var p: Array[MapChild] = _nav.current_path()
	p.append(_here[i])
	jump_requested.emit(p, _level, carry())


## Va al mapa `i` del árbol.
func go_tree(i: int) -> void:
	if i < 0 or i >= _paths.size():
		return
	jump_requested.emit(tree_path(i), _level, carry())


func _add_frame(parent: TreeItem, f: MapNavigator.Frame, path: Array[MapChild]) -> void:
	var it: TreeItem = _tree.create_item(parent)
	var label: String = name_of.call(f)
	var current: bool = f == _nav.current()
	if current:
		label = "▶ " + label
		it.set_custom_color(0, Color("f7dc8e"))
	it.set_text(0, label)
	it.set_metadata(0, _paths.size())
	_paths.append(path)
	if current:
		_tree.set_selected(it, 0)
	# Hijos visitados, por nombre (los diccionarios no tienen orden fijo).
	var kids: Array[MapNavigator.Frame] = []
	for id: int in f.visited:
		kids.append(f.visited[id])
	kids.sort_custom(func(a: MapNavigator.Frame, b: MapNavigator.Frame) -> bool:
		var na: String = name_of.call(a)
		var nb: String = name_of.call(b)
		return na.naturalnocasecmp_to(nb) < 0)
	for k: MapNavigator.Frame in kids:
		var p: Array[MapChild] = path.duplicate()
		p.append(k.child)
		_add_frame(it, k, p)


func _fill_here() -> void:
	_here_list.clear()
	_here.clear()
	if _nav == null or _nav.current() == null:
		return
	var doc: MapDocument = _nav.current().doc
	var lvl: MapLevel = doc.level(_level)
	if lvl == null:
		return
	var needle: String = _filter.text.strip_edges().to_lower()
	var items: Array = []
	for c: MapChild in lvl.children:
		if c.seed_code.is_empty() and not doc.child_overrides.has(c.id):
			continue  # Punto de interés sin mapa: no hay adónde ir.
		var fr: MapNavigator.Frame = MapNavigator.Frame.new()
		fr.child = c
		var n: String = name_of.call(fr)
		if not needle.is_empty() and not n.to_lower().contains(needle):
			continue
		items.append([n, c])
	items.sort_custom(func(a: Array, b: Array) -> bool:
		var na: String = a[0]
		var nb: String = b[0]
		return na.naturalnocasecmp_to(nb) < 0)
	for pair: Array in items:
		if _here.size() >= MAX_HERE:
			break
		var c: MapChild = pair[1]
		var n: String = pair[0]
		_here.append(c)
		_here_list.add_item(n)


func _on_tree_activated() -> void:
	var it: TreeItem = _tree.get_selected()
	if it != null:
		var i: int = it.get_metadata(0)
		go_tree(i)


func _go_selected() -> void:
	var sel: PackedInt32Array = _here_list.get_selected_items()
	if not sel.is_empty():
		go_here(sel[0])
		return
	var it: TreeItem = _tree.get_selected()
	if it != null:
		var i: int = it.get_metadata(0)
		go_tree(i)
