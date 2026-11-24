extends SceneTree
## Herramienta de desarrollo: renderiza mapas de ejemplo a PNG con la vista
## 2D real (necesita ventana, no funciona en --headless).
##
##   godot --path project -s res://tests/render/render_samples.gd -- <carpeta> <código>...
##
## Sin códigos, usa uno por rejilla. Añade una ficha para ver el dibujo.

const DEFAULT_CODES: Array[String] = [
	"RPGM1-DND5-MAZ-G1-0-HWX23H6N-W",
	"RPGM1-PF2E-MAZ-G1-80-PK2XDSZR-5",
	"RPGM1-DND5-MAZ-G1-WKA0G0-W7HE7S75-0",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var codes: Array[String] = []
	for i: int in range(1, args.size()):
		codes.append(args[i])
	if codes.is_empty():
		codes = DEFAULT_CODES
	var host: Node = Node.new()
	root.add_child(host)
	for code: String in codes:
		var res: GeneratorRegistry.Result = GeneratorRegistry.generate(code)
		if res.doc == null:
			printerr("ERROR ", code, ": ", res.error)
			continue
		var sc: SeedCode = SeedCode.parse(code)
		var profile: SystemProfile = SystemProfile.find_by_seed_code(sc.system)
		var path: String = out_dir.path_join(code + ".png")
		var err: Error = await PngExporter.save(host, res.doc, 0, profile, path, 48 if res.doc.scale == "EST" else 24, true)
		print("PNG ", path, " -> ", error_string(err))
	quit()
