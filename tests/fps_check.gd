extends SceneTree
## Comprueba que la física no depende de los FPS: hace siempre lo mismo
## (empujar, soltar, volver a empujar, saltar) durante los mismos segundos y
## mide distancia, velocidad y altura del salto. Se corre a distintos FPS:
##   godot --headless --path . --fixed-fps 30 --script res://tests/fps_check.gd
## e imprime una línea "FPS_CHECK {...}" para comparar.

var _fps: int = 60


func _initialize() -> void:
	_run.call_deferred()


## Pasos de física (60 por segundo, fijos): se espera y se mide por paso, así
## la prueba es exacta a cualquier FPS.
func _frames(seconds: float) -> int:
	return roundi(seconds * Engine.physics_ticks_per_second)


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _run() -> void:
	_fps = Engine.max_fps if Engine.max_fps > 0 else 60
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_fps = int(args[0])
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	GameSettings.load_settings()
	GameSettings.weather = GameSettings.Weather.SUNNY
	GameSettings.player_count = 1
	GameSettings.sandbox_wave_level = 0
	var m: Node = load("res://sandbox.tscn").instantiate()
	root.add_child(m)
	await physics_frame
	# Mar sin olas grandes: así se compara solo la física.
	(m.get_node("Water") as Water).clear_swells()
	var r: Rider = get_nodes_in_group("riders")[0]
	for i in _frames(0.5):
		await physics_frame
	var start := r.position
	_hold("p1_up", true)
	for i in _frames(4.0):
		await physics_frame
	var speed_push := r.speed
	var dist_push := Vector2(r.position.x - start.x, r.position.z - start.z).length()
	_hold("p1_up", false)
	for i in _frames(3.0):
		await physics_frame
	var dist_coast := Vector2(r.position.x - start.x, r.position.z - start.z).length()
	_hold("p1_up", true)
	for i in _frames(4.0):
		await physics_frame
	# Saltito: altura máxima sobre el agua y tiempo en el aire.
	var ev := InputEventAction.new()
	ev.action = "p1_a"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	var max_h := 0.0
	var air := 0.0
	var landed := false
	for i in _frames(3.0):
		await physics_frame
		if i == 2:
			var up := InputEventAction.new()
			up.action = "p1_a"
			up.pressed = false
			Input.parse_input_event(up)
		if not r.grounded:
			air += 1.0 / Engine.physics_ticks_per_second
			max_h = maxf(max_h, r.position.y - r.water_height())
		elif air > 0.0:
			landed = true
			break
	_hold("p1_up", false)
	print("FPS_CHECK %s" % JSON.stringify({
		"fps": _fps, "speed_push": snappedf(speed_push, 0.01), "dist_push": snappedf(dist_push, 0.01),
		"dist_coast": snappedf(dist_coast, 0.01), "jump_h": snappedf(max_h, 0.01), "air": snappedf(air, 0.01),
		"landed": landed,
	}))
	quit()
