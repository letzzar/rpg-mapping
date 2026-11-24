extends SceneTree
## Herramienta de desarrollo: captura la pantalla principal real en 2D, 3D
## cenital y 1ª persona, con y sin niebla, a PNG (necesita ventana; no
## funciona en --headless). Sirve para revisar las vistas sin tocar la app.
##
##   godot --path project -s res://tests/render/render_views.gd -- <carpeta> [código]

const DEFAULT_CODE: String = "RPGM1-DND5-MAZ-G1-0-HWX23H6N-W"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var code: String = args[1] if args.size() > 1 else DEFAULT_CODE
	root.size = Vector2i(1400, 860)
	var scene: PackedScene = load("res://ui/main.tscn")
	var main: Control = scene.instantiate()
	root.add_child(main)
	await process_frame
	var edit: LineEdit = main.get("_code_edit")
	edit.text = code
	main.call("_generate_from_text")
	await _frames(3)
	main.call("_add_token")
	main.call("_add_token")
	var view_opt: OptionButton = main.get("_view_opt")
	var aud: OptionButton = main.get("_audience_opt")
	var shots: Array = [
		["2d_dm", 0, 0], ["3d_dm", 1, 0], ["3d_players", 1, 1], ["2d_players", 0, 1], ["fp_players", 2, 1], ["fp_dm", 2, 0],
	]
	for s: Array in shots:
		var aud_i: int = s[2]
		var view_i: int = s[1]
		aud.select(aud_i)
		main.call("_refresh_vision")
		view_opt.select(view_i)
		var ms: int = main.call("_apply_view")
		await _frames(4)
		var img: Image = root.get_texture().get_image()
		var path: String = out_dir.path_join("%s_%s.png" % [code, s[0]])
		img.save_png(path)
		print("PNG ", path, " (cambio de vista ", ms, " ms)")
	# 1ª persona tras avanzar unos pasos.
	var v3: MapView3D = main.get("_view3d")
	for k: int in 6:
		if not v3.step_first_person(1):
			v3.turn_first_person(1)
		await _frames(1)
	await _frames(3)
	var img2: Image = root.get_texture().get_image()
	img2.save_png(out_dir.path_join("%s_fp_walk.png" % code))
	quit()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
