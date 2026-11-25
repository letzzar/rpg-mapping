class_name NetHostPanel
extends PanelContainer
## Panel del DM para la partida en red (F4, ADR 031): abre el servidor
## (HTTPS + WSS en un puerto), gestiona los jugadores (enlace de invitación,
## ficha asignada) y hace girar servidor y sesión cada fotograma.
##
## No toca el documento: lo que hay que cambiar (un movimiento aprobado, dar
## una ficha) lo pide con señales y lo ejecuta la pantalla principal en su
## historial (las vistas no modifican el modelo; el DM puede deshacerlo).

signal move_approved(cmd: MoveTokenCommand)
signal pinged(level_index: int, cell: Vector2i, who: String)
## Dar la ficha seleccionada al jugador con esta referencia.
signal assign_requested(player_ref: String, player_name: String)
signal status(text: String)

var session: GameSession = null
var server: WssServer = WssServer.new()

var _port: SpinBox
var _toggle: Button
var _info: Label
var _name_edit: LineEdit
var _players_title: Label
var _players_box: VBoxContainer
var _doc: MapDocument = null
var _profile: SystemProfile = null
var _title: String = ""
var _opts: PartyVision.Options = PartyVision.Options.new()


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	var head: Label = Label.new()
	head.text = tr("UI_NET_HOST")
	head.add_theme_font_size_override("font_size", 18)
	box.add_child(head)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var pl: Label = Label.new()
	pl.text = tr("UI_NET_PORT")
	row.add_child(pl)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = WssServer.DEFAULT_PORT
	row.add_child(_port)
	_toggle = Button.new()
	_toggle.text = tr("UI_NET_START")
	_toggle.pressed.connect(_on_toggle)
	row.add_child(_toggle)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = tr("UI_NET_STOPPED")
	box.add_child(_info)
	var add_row: HBoxContainer = HBoxContainer.new()
	box.add_child(add_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("UI_NET_PLAYER_NAME")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _add_player())
	add_row.add_child(_name_edit)
	var add_btn: Button = Button.new()
	add_btn.text = tr("UI_NET_ADD_PLAYER")
	add_btn.pressed.connect(_add_player)
	add_row.add_child(add_btn)
	_players_title = Label.new()
	box.add_child(_players_title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players_box)
	var help: Label = Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = tr("UI_NET_HELP")
	help.add_theme_font_size_override("font_size", 12)
	box.add_child(help)
	_new_session()
	set_process(false)


func is_hosting() -> bool:
	return server.is_listening()


## Mapa que ven los jugadores (lo llama la pantalla principal al cambiar de
## mapa o de sistema).
func set_document(doc: MapDocument, profile: SystemProfile, title: String) -> void:
	_doc = doc
	_profile = profile
	_title = title
	if session != null:
		session.set_document(doc, profile, title)


func set_vision_options(opts: PartyVision.Options) -> void:
	_opts = opts
	if session != null:
		session.set_vision_options(opts)


func mark_dirty() -> void:
	if session != null:
		session.mark_dirty()


func _new_session() -> void:
	session = GameSession.new()
	session.send_bytes = server.send
	session.close_peer = server.close
	session.move_approved.connect(func(cmd: MoveTokenCommand) -> void: move_approved.emit(cmd))
	session.pinged.connect(func(li: int, cell: Vector2i, who: String) -> void: pinged.emit(li, cell, who))
	session.players_changed.connect(_refresh_players)
	if not server.peer_connected.is_connected(_on_peer_connected):
		server.peer_connected.connect(_on_peer_connected)
		server.peer_disconnected.connect(func(id: int) -> void: session.peer_disconnected(id))
		server.message_received.connect(func(id: int, data: PackedByteArray) -> void: session.receive(id, data))
	session.set_vision_options(_opts)
	if _doc != null:
		session.set_document(_doc, _profile, _title)
	_refresh_players()


func _on_peer_connected(id: int) -> void:
	if not session.peer_connected(id):
		server.close(id)


func _process(_delta: float) -> void:
	server.poll()
	session.flush()


func _on_toggle() -> void:
	if is_hosting():
		server.stop()
		set_process(false)
		_toggle.text = tr("UI_NET_START")
		_info.text = tr("UI_NET_STOPPED")
		_refresh_players()
		return
	var cert: NetCertificate = NetCertificate.load_or_create()
	if not cert.error.is_empty():
		_info.text = tr("UI_NET_START_FAILED").replace("{error}", cert.error)
		return
	server.web_root = find_web_root()
	if server.start(int(_port.value), cert.key, cert.cert) != OK:
		_info.text = tr("UI_NET_START_FAILED").replace("{error}", server.error)
		return
	# Sala nueva en cada apertura: los enlaces de una partida anterior ya no
	# sirven (los jugadores se conservan con códigos nuevos).
	var names: Array[String] = []
	for p: GameSession.Player in session.players:
		names.append(p.name)
	_new_session()
	for n: String in names:
		session.add_player(n)
	set_process(true)
	_toggle.text = tr("UI_NET_STOP")
	var lines: PackedStringArray = PackedStringArray()
	lines.append(tr("UI_NET_LISTENING").replace("{room}", session.room_code))
	lines.append(tr("UI_NET_ADDRESSES").replace("{urls}", ", ".join(_base_urls())))
	if server.web_root.is_empty():
		lines.append(tr("UI_NET_NO_WEB"))
	lines.append(tr("UI_NET_CERT").replace("{fp}", cert.fingerprint().left(23) + "…"))
	_info.text = "\n".join(lines)
	_refresh_players()


## Carpeta con la exportación Web (index.html): "web" junto al ejecutable o,
## al ejecutar desde el proyecto, build/web del repositorio. "" si no hay.
static func find_web_root() -> String:
	var candidates: Array[String] = [
		OS.get_executable_path().get_base_dir().path_join("web"),
		ProjectSettings.globalize_path("res://").path_join("../build/web").simplify_path(),
	]
	for c: String in candidates:
		if FileAccess.file_exists(c.path_join("index.html")):
			return c
	return ""


## https://<ip>:<puerto> por cada dirección IPv4 de la red local (primero las
## privadas habituales), o localhost si no hay ninguna.
func _base_urls() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var others: PackedStringArray = PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		var url: String = "https://%s:%d" % [ip, server.port()]
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(url)
		else:
			others.append(url)
	out.append_array(others)
	if out.is_empty():
		out.append("https://localhost:%d" % server.port())
	return out


func invite_link(p: GameSession.Player) -> String:
	return "%s/?sala=%s&t=%s" % [_base_urls()[0], session.room_code, p.code]


func _add_player() -> void:
	var p: GameSession.Player = session.add_player(_name_edit.text)
	if p != null:
		_name_edit.clear()


func _token_count(p: GameSession.Player) -> int:
	var n: int = 0
	if _doc != null:
		for t: MapToken in _doc.tokens:
			if t.character_ref == p.ref():
				n += 1
	return n


func _refresh_players() -> void:
	if _players_box == null:
		return
	for ch: Node in _players_box.get_children():
		ch.queue_free()
	_players_title.text = tr("UI_NET_PLAYERS").replace("{connected}", str(session.connected_count())).replace("{total}", str(session.players.size()))
	for p: GameSession.Player in session.players:
		var row: VBoxContainer = VBoxContainer.new()
		var name_lbl: Label = Label.new()
		var state: String = tr("UI_NET_CONNECTED") if p.peer != 0 else tr("UI_NET_OFFLINE")
		name_lbl.text = "%s · %s · %s" % [p.name, state, tr("UI_NET_TOKENS").replace("{n}", str(_token_count(p)))]
		row.add_child(name_lbl)
		var btns: HFlowContainer = HFlowContainer.new()
		row.add_child(btns)
		var copy_btn: Button = Button.new()
		copy_btn.text = tr("UI_NET_COPY_LINK")
		copy_btn.disabled = not is_hosting()
		copy_btn.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(invite_link(p))
			status.emit(tr("UI_NET_LINK_COPIED").replace("{name}", p.name)))
		btns.add_child(copy_btn)
		var assign_btn: Button = Button.new()
		assign_btn.text = tr("UI_NET_ASSIGN")
		assign_btn.pressed.connect(func() -> void: assign_requested.emit(p.ref(), p.name))
		btns.add_child(assign_btn)
		var remove_btn: Button = Button.new()
		remove_btn.text = tr("UI_NET_REMOVE")
		remove_btn.pressed.connect(func() -> void: session.remove_player(p.id))
		btns.add_child(remove_btn)
		_players_box.add_child(row)
		_players_box.add_child(HSeparator.new())


## Tras dar una ficha: el número de fichas de cada jugador cambia.
func refresh() -> void:
	_refresh_players()
