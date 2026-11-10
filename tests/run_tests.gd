extends SceneTree
## Tests automáticos (sin pantalla). Se corren en GitHub Actions con:
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd
## Simulan pulsaciones de botones y revisan que el Rider se comporte bien.

const FPS := 60

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var rider := main.get_node("Rider") as Rider
	_check(rider != null, "existe el Rider")
	if rider == null:
		_finish()
		return
	var water := main.get_node("Water") as Water

	_check(rider.is_fallen(), "el juego empieza con el jugador caído")
	_check(rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "empieza en el agua")

	await _wait(1.0)
	_check(rider.is_fallen(), "sin pulsar nada sigue caído")

	await _mash(2.0, 3.0)
	_check(
		rider.recovery_stage == Rider.RecoveryStage.IN_WATER,
		"spamear lento (2 por segundo) no alcanza para subirse"
	)

	await _mash(8.0, 2.5)
	_check(
		rider.recovery_stage == Rider.RecoveryStage.PRONE,
		"spamear rápido lo sube acostado a la tabla"
	)
	_check(rider.is_fallen(), "acostado todavía no está parado")

	await _wait(3.0)
	_check(rider.is_fallen(), "si deja de spamear se queda acostado")

	await _mash(8.0, 3.0)
	_check(not rider.is_fallen(), "seguir spameando lo pone de pie")
	_check(rider.recovery_stage == Rider.RecoveryStage.STANDING, "etapa = parado")

	await _wait(2.0)
	_check(rider.speed > 10.0, "de pie avanza solo (velocidad %.1f)" % rider.speed)

	var start_heading := rider.heading
	var start_pos := rider.global_position
	await _hold(&"p1_right", 1.0)
	_check(rider.heading < start_heading - 1.0, "derecha gira a la derecha")
	await _hold(&"p1_left", 1.0)
	_check(absf(rider.heading - start_heading) < 0.2, "izquierda gira a la izquierda")
	_check(start_pos.distance_to(rider.global_position) > 10.0, "se desplaza por el agua")

	var expected_y := water.height_at(rider.global_position.x, rider.global_position.z)
	_check(absf(rider.global_position.y - expected_y) < 0.001, "flota a la altura de la ola")

	await _press(&"p1_debug_fall")
	await _wait(0.2)
	_check(rider.is_fallen(), "R lo tira de la tabla")
	_check(rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "y cae al agua")

	await _wait(1.0)
	_check(rider.speed < 4.0, "en el agua frena (velocidad %.1f)" % rider.speed)

	_finish()


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if ok:
		print("  OK    ", description)
	else:
		print("  FALLA ", description)
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


func _send(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _press(action: StringName) -> void:
	_send(action, true)
	await process_frame
	_send(action, false)
	await process_frame


## Pulsa A `rate` veces por segundo durante `seconds`.
func _mash(rate: float, seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(seconds * FPS):
		if i % interval == 0:
			_send(&"p1_a", true)
		elif i % interval == 1:
			_send(&"p1_a", false)
		await process_frame


func _hold(action: StringName, seconds: float) -> void:
	_send(action, true)
	await _wait(seconds)
	_send(action, false)
	await process_frame
