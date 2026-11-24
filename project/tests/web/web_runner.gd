extends Node
## Ejecuta toda la batería GUT dentro de una exportación (pensado para el
## preset "Web Tests"; criterio de aceptación de F0: tests verdes en web).
##
## Al terminar escribe en la consola una línea fácil de buscar:
##   WEB_TESTS_RESULT scripts=<n> tests=<n> passing=<n> failing=<n> asserts=<n>
## y, en el navegador, pone ese mismo texto como título del documento para
## poder leerlo sin abrir la consola.

const RUNNER_SCENE: String = "res://addons/gut/gui/GutRunner.tscn"
const GUT_CONFIG: String = "res://addons/gut/gut_config.gd"

var _runner: Node = null


@warning_ignore("unsafe_method_access")
@warning_ignore("unsafe_property_access")
func _ready() -> void:
	# Fuerza el _static_init del cargador de GUT (igual que gut_cmdln.gd).
	var _loader: Object = load("res://addons/gut/gut_loader.gd")
	var cfg: Object = (load(GUT_CONFIG) as GDScript).new()
	var opts: Dictionary = cfg.get("options")
	opts["dirs"] = ["res://tests"]
	opts["include_subdirs"] = true
	opts["should_exit"] = false
	opts["should_exit_on_success"] = false
	opts["hide_orphans"] = true
	_runner = (load(RUNNER_SCENE) as PackedScene).instantiate()
	_runner.call("set_gut_config", cfg)
	get_tree().root.add_child.call_deferred(_runner)
	_start.call_deferred()


@warning_ignore("unsafe_method_access")
func _start() -> void:
	var gut: Node = _runner.call("get_gut")
	gut.connect("end_run", _on_end_run)
	_runner.call("run_tests")


@warning_ignore("unsafe_method_access")
@warning_ignore("unsafe_call_argument")
func _on_end_run() -> void:
	var gut: Node = _runner.call("get_gut")
	var collector: Object = gut.call("get_test_collector")
	var scripts: Array = collector.get("scripts")
	var tests: int = 0
	var failing: int = 0
	var skipped: int = 0
	for s: Object in scripts:
		var ran: int = s.call("get_ran_test_count")
		var failed: int = s.call("get_failing_test_count")
		tests += ran
		failing += failed
		if s.get("was_skipped") == true or s.get("is_loaded") == false:
			skipped += 1
	var asserts: int = gut.call("get_assert_count")
	var line: String = "WEB_TESTS_RESULT scripts=%d skipped=%d tests=%d passing=%d failing=%d asserts=%d" % [
		scripts.size(), skipped, tests, tests - failing, failing, asserts]
	print(line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.title = %s;" % JSON.stringify(line))
