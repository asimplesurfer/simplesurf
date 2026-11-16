extends SceneTree
## Tests automáticos (sin pantalla). Se corren en GitHub Actions con:
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd
## Para correr solo algunos grupos (por nombre, o parte del nombre):
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd -- maps sandbox
##
## Cada grupo es un archivo en tests/suites/ (hereda de tests/test_base.gd).
## Antes de cada uno se dejan las opciones en un estado conocido, así cada
## grupo se puede correr solo.

## En orden: los primeros prueban lo básico.
const SUITES := [
	"res://tests/suites/test_menu.gd",
	"res://tests/suites/test_input.gd",
	"res://tests/suites/test_characters.gd",
	"res://tests/suites/test_race.gd",
	"res://tests/suites/test_bots.gd",
	"res://tests/suites/test_memory.gd",
	"res://tests/suites/test_maps.gd",
	"res://tests/suites/test_explore.gd",
	"res://tests/suites/test_sandbox.gd",
	"res://tests/suites/test_time_trial.gd",
	"res://tests/suites/test_feel.gd",
	"res://tests/suites/test_rider_states.gd",
]

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# En modo --script el autoload puede no estar: se crea a mano.
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	GameSettings.load_settings()
	var defaults := {
		"jump_style": GameSettings.jump_style,
		"wave_mode": GameSettings.wave_mode,
		"track_layout": GameSettings.track_layout,
	}
	var only := OS.get_cmdline_user_args()
	for path in SUITES:
		if not only.is_empty() and not Array(only).any(func(w: String) -> bool: return path.contains(w)):
			continue
		_reset_settings()
		var suite: Node = (load(path) as GDScript).new()
		suite.name = path.get_file().get_basename()
		suite.set("defaults", defaults)
		root.add_child(suite)
		print("\n=== %s ===" % suite.name)
		await suite.run()
		_checks += int(suite.get("_checks"))
		for f in suite.get("_failures"):
			_failures.append("%s: %s" % [suite.name, f])
		suite.queue_free()
		await process_frame
	_finish()


## Estado conocido antes de cada grupo: 1 jugador, sin bots, mapa Isla, sol,
## salto libre, y "atrás" apretado (avanza solo: los tests arrancan quietos y
## sueltan cuando hay que avanzar).
func _reset_settings() -> void:
	GameSettings.player_count = 1
	GameSettings.bot_count = 0
	GameSettings.track_layout = GameSettings.TrackLayout.CLASSIC
	GameSettings.weather = GameSettings.Weather.SUNNY
	GameSettings.jump_style = GameSettings.JumpStyle.FREE
	Engine.time_scale = 1.0
	for action in InputMap.get_actions():
		if String(action).begins_with("p1_") or String(action).begins_with("p2_"):
			Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = &"p1_down"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("TESTS OK (%d comprobaciones)" % _checks)
		quit(0)
	else:
		for f in _failures:
			print("  FALLÓ ", f)
		print("TESTS FALLIDOS: %d de %d" % [_failures.size(), _checks])
		quit(1)
