extends SceneTree
## Tests automáticos (sin pantalla). Se corren en GitHub Actions con:
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd
## Simulan pulsaciones de botones y revisan que el Rider se comporte bien.

const FPS := 60

var _failures: Array[String] = []
var _checks: int = 0
var _tricks_landed: int = 0
var _main: Node
var _rider: Rider
var _water: Water
var _waves: WaveManager


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_rider = _main.get_node("Rider") as Rider
	_water = _main.get_node("Water") as Water
	_waves = _main.get_node("WaveManager") as WaveManager
	_check(_rider != null and _water != null and _waves != null, "existen Rider, Water y WaveManager")
	if _rider == null or _water == null or _waves == null:
		_finish()
		return
	# Sin olas grandes al azar durante los tests de movimiento.
	_waves.enabled = false
	_water.clear_swells()
	_rider.trick_landed.connect(func(_spins: int) -> void: _tricks_landed += 1)

	_test_pad_layouts()
	await _test_get_up()
	await _test_throttle_and_steer()
	await _test_jump_and_tricks()
	await _test_drift()
	await _test_swells()
	_finish()


func _test_pad_layouts() -> void:
	print("Mandos:")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.GENERIC)
	_check(_has_button(&"p1_a", 2), "mando genérico: ✕ (botón 2) es A")
	_check(_has_button(&"p1_debug_fall", 0), "mando genérico: △ (botón 0) es caerse")
	_check(not _has_button(&"p1_a", JOY_BUTTON_A), "mando genérico: △ ya no es A")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.STANDARD)
	_check(_has_button(&"p1_a", JOY_BUTTON_A), "mando estándar: A es A")
	_check(_has_button(&"p1_drift", JOY_BUTTON_X), "mando estándar: X derrapa")
	_check(_has_button(&"p1_left", JOY_BUTTON_DPAD_LEFT), "la cruceta sigue funcionando")


func _has_button(action: StringName, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return true
	return false


func _test_get_up() -> void:
	print("Levantarse:")
	_check(_rider.is_fallen(), "el juego empieza con el jugador caído")
	_check(_rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "empieza en el agua")

	await _wait(1.0)
	_check(_rider.is_fallen(), "sin pulsar nada sigue caído")

	await _mash(2.0, 3.0)
	_check(
		_rider.recovery_stage == Rider.RecoveryStage.IN_WATER,
		"spamear lento (2 por segundo) no alcanza para subirse"
	)

	await _mash(8.0, 1.0)
	_check(
		_rider.recovery_stage == Rider.RecoveryStage.PRONE,
		"spamear rápido lo sube acostado a la tabla en ~1 s"
	)
	_check(_rider.is_fallen(), "acostado todavía no está parado")

	await _wait(3.0)
	_check(_rider.is_fallen(), "si deja de spamear se queda acostado")

	var frames_before := Engine.get_process_frames()
	await _mash_until_standing(8.0, 4.0)
	var seconds := float(Engine.get_process_frames() - frames_before) / FPS
	_check(not _rider.is_fallen(), "seguir spameando lo pone de pie")
	_check(seconds < 1.3, "pararse desde acostado tarda poco (%.2f s)" % seconds)
	_check(_rider.recovery_stage == Rider.RecoveryStage.STANDING, "etapa = parado")


func _test_throttle_and_steer() -> void:
	print("Acelerar y girar:")
	await _wait(2.5)
	_check(_rider.speed < 1.0, "parado sin acelerar no avanza solo (velocidad %.1f)" % _rider.speed)

	_set_action(&"p1_up", true)
	await _wait(3.0)
	_check(_rider.speed > 10.0, "W acelera (velocidad %.1f)" % _rider.speed)

	var start_heading := _rider.heading
	var start_pos := _rider.global_position
	await _hold(&"p1_right", 1.0)
	var turned := start_heading - _rider.heading
	_check(turned > 0.4, "derecha gira a la derecha (%.2f rad)" % turned)
	_check(turned < 1.3, "girar cuesta más que antes (%.2f rad en 1 s)" % turned)
	_check(start_pos.distance_to(_rider.global_position) > 8.0, "se desplaza por el agua")
	var trail := _rider.get_node("Visual/Trail") as BoardTrail
	_check(trail != null and trail._points.size() > 5, "la tabla deja estela")
	_check(trail != null and trail.mesh.get_surface_count() > 0, "la estela se dibuja")

	var expected_y := _water.height_at(_rider.global_position.x, _rider.global_position.z)
	_check(absf(_rider.global_position.y - expected_y) < 0.001, "flota a la altura de la ola")

	_set_action(&"p1_up", false)
	await _wait(1.0)
	_check(_rider.speed < 11.5, "al soltar W frena de a poco (velocidad %.1f)" % _rider.speed)
	_set_action(&"p1_up", true)
	await _wait(1.5)

	var launched := false
	for i in int(8.0 * FPS):
		if _state() != &"riding":
			launched = true
		await process_frame
	_check(not launched, "las olas chicas de fondo no lo lanzan al aire")


func _test_jump_and_tricks() -> void:
	print("Salto y trucos:")
	# Salto simple: toca y suelta.
	await _press(&"p1_a")
	_check(_state() == &"airborne", "ESPACIO salta")
	var tap_height := await _measure_jump_height()
	_check(tap_height > 0.4, "sube en el aire (%.2f m)" % tap_height)
	_check(_state() == &"riding", "aterriza y sigue andando")
	await _wait(0.3)

	# Salto cargado: mantener sin soltar; al llegar al máximo salta solo.
	_set_action(&"p1_a", true)
	await _wait(0.5)
	_check(_state() == &"riding", "mantener ESPACIO en el agua no salta todavía")
	_check(_rider.jump_charge > 0.3, "mantener ESPACIO carga el salto (%.2f)" % _rider.jump_charge)
	await _wait(0.6)
	_check(_state() == &"airborne", "al llegar a la carga máxima salta solo")
	# Soltar enseguida: si se sigue manteniendo en el aire, empieza un truco.
	_set_action(&"p1_a", false)
	var charged_height := await _measure_jump_height()
	_check(
		charged_height > tap_height * 2.0,
		"el salto cargado sube mucho más (%.2f m contra %.2f m)" % [charged_height, tap_height]
	)
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# Modo "tocar para saltar": salta enseguida al apretar.
	GameSettings.jump_mode = GameSettings.JumpMode.TAP
	_set_action(&"p1_a", true)
	await process_frame
	await process_frame
	_check(_state() == &"airborne", "modo tocar: salta al apretar, sin soltar")
	_set_action(&"p1_a", false)
	var tap_mode_height := await _measure_jump_height()
	_check(tap_mode_height > 1.0, "modo tocar: salto alto fijo (%.2f m)" % tap_mode_height)
	GameSettings.jump_mode = GameSettings.JumpMode.CHARGE
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# En el aire no se puede volver a saltar.
	await _press(&"p1_a")
	await _wait(0.2)
	var vs := _rider.vertical_speed
	await _press(&"p1_a")
	_check(_rider.vertical_speed < vs, "en el aire no hay doble salto")
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# Truco bien hecho: salto cargado, en el aire mantener un poco y soltar a tiempo.
	var tricks_before := _tricks_landed
	var nitro_before := _rider.nitro
	await _charged_jump(0.6)
	_set_action(&"p1_a", true)
	await _wait(0.3)
	_check(_rider.trick_angle > 0.0, "mantener ESPACIO en el aire gira la tabla")
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 2.0)
	_check(not _rider.is_fallen(), "soltar a tiempo: aterriza bien")
	_check(_tricks_landed == tricks_before + 1, "cuenta como truco")
	_check(_rider.nitro > nitro_before, "el truco carga nitro (%.2f)" % _rider.nitro)
	await _wait(0.3)

	# Truco fallido: mantener hasta tocar el agua.
	await _charged_jump(0.6)
	_set_action(&"p1_a", true)
	await _wait(1.5)
	_set_action(&"p1_a", false)
	_check(_rider.is_fallen(), "tocar el agua girando: se cae")
	_check(_rider.nitro == 0.0, "truco fallido: nitro a 0")

	await _mash_until_standing(8.0, 5.0)
	_check(not _rider.is_fallen(), "se vuelve a levantar")
	await _wait(3.0)


func _test_drift() -> void:
	print("Derrape:")
	_check(_rider.speed > 6.0, "va rápido antes de derrapar (%.1f)" % _rider.speed)

	# Un rival quieto que va a quedar detrás.
	var victim: Rider = load("res://core/rider/rider.tscn").instantiate()
	victim.player_index = 1
	_main.add_child(victim)
	await process_frame
	victim.state_machine.transition_to(&"riding")

	_set_action(&"p1_right", true)
	await _wait(0.2)
	_set_action(&"p1_drift", true)
	await process_frame
	await process_frame
	_check(_state() == &"drifting", "SHIFT derrapa")
	_check(_rider.drift_side == 1, "derrapa hacia el lado del giro")
	var speed_before := _rider.speed
	victim.global_position = _rider.global_position - _rider.forward() * 3.0
	victim.position.y = _water_height_here()
	await _wait(0.3)
	_check(_rider.speed < speed_before, "derrapar frena")
	var sheet := _rider.get_node("Visual/Spray/Sheet") as MeshInstance3D
	_check(sheet != null and sheet.visible, "derrapar levanta la cortina de agua")
	_check(victim.is_fallen(), "el agua del derrape tira al rival que está detrás")

	_set_action(&"p1_drift", false)
	_set_action(&"p1_right", false)
	await _wait(0.1)
	_check(_state() == &"riding", "soltar SHIFT termina el derrape")
	victim.queue_free()
	await _wait(1.0)


func _test_swells() -> void:
	print("Olas grandes:")
	var player := Vector2(_rider.global_position.x, _rider.global_position.z)
	var all_clear := true
	for i in 60:
		var s := _waves.make_swell()
		if s and not _waves.is_clear_of(s, player):
			all_clear = false
	_check(all_clear, "las olas nunca nacen encima del jugador")

	_waves.random_seed = 1234
	_waves._ready()
	_waves.enabled = true
	await _wait(6.0)
	_check(_water.swells.size() > 0, "aparecen olas grandes solas (%d)" % _water.swells.size())
	_waves.enabled = false
	_water.clear_swells()

	# Una ola quieta adelante: ir rápido hacia ella debe lanzarlo al aire.
	var s := Swell.new()
	var f := _rider.forward()
	var ahead := _rider.global_position + f * 25.0
	s.center = Vector2(ahead.x, ahead.z)
	s.direction = -Vector2(f.x, f.z)
	s.speed = 0.0
	s.max_amplitude = 2.0
	s.width = 4.0
	s.half_length = 20.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	_water.add_swell(s)
	_set_action(&"p1_up", true)
	var launched := false
	for i in int(4.0 * FPS):
		if _state() == &"airborne":
			launched = true
			break
		await process_frame
	_check(launched, "subir una ola grande con velocidad lo lanza al aire")


## Mantiene A `seconds` en el agua y suelta (salto cargado).
func _charged_jump(seconds: float) -> void:
	_set_action(&"p1_a", true)
	await _wait(seconds)
	_set_action(&"p1_a", false)
	await process_frame
	await process_frame


## Altura máxima sobre el agua hasta aterrizar.
func _measure_jump_height() -> float:
	var max_height := 0.0
	for i in int(2.5 * FPS):
		var h := _rider.global_position.y - _water_height_here()
		max_height = maxf(max_height, h)
		if _state() != &"airborne":
			break
		await process_frame
	return max_height


func _state() -> StringName:
	return _rider.state_machine.current_name


func _water_height_here() -> float:
	return _water.height_at(_rider.global_position.x, _rider.global_position.z)


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if ok:
		print("  OK    ", description)
	else:
		print("  FALLA ", description)
		if _rider:
			print(
				"        estado=%s vel=%.1f vel_vert=%.2f en_agua=%s carga=%.2f a=%s"
				% [
					_state(),
					_rider.speed,
					_rider.vertical_speed,
					_rider.grounded,
					_rider.jump_charge,
					Input.is_action_pressed(&"p1_a"),
				]
			)
		_failures.append(description)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("TESTS OK (%d comprobaciones)" % _checks)
		quit(0)
	else:
		print("TESTS FALLIDOS: %d de %d" % [_failures.size(), _checks])
		quit(1)


func _wait(seconds: float) -> void:
	for i in int(seconds * FPS):
		await process_frame


func _wait_until_state(state: StringName, max_seconds: float) -> void:
	for i in int(max_seconds * FPS):
		if _state() == state:
			return
		await process_frame


func _set_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


## Toca un botón. Los eventos simulados llegan al juego un frame después,
## por eso se espera un frame extra tras soltar.
func _press(action: StringName) -> void:
	_set_action(action, true)
	await process_frame
	await process_frame
	_set_action(action, false)
	await process_frame
	await process_frame


## Pulsa A `rate` veces por segundo durante `seconds`.
func _mash(rate: float, seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(seconds * FPS):
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame


## Spamea hasta que se pone de pie (o se acaba el tiempo).
func _mash_until_standing(rate: float, max_seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(max_seconds * FPS):
		if not _rider.is_fallen():
			break
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame
	_set_action(&"p1_a", false)
	await process_frame


func _hold(action: StringName, seconds: float) -> void:
	_set_action(action, true)
	await _wait(seconds)
	_set_action(action, false)
	await process_frame
