extends RiderState
## Caído de la tabla. Hay que spamear A para recuperarse, en dos etapas:
##   1. En el agua  -> se sube a la tabla y queda acostado (puede remar un poco).
##   2. Acostado    -> se para sobre la tabla y vuelve a `riding`.
## Cada pulsación llena una barra que se vacía sola: solo avanza quien
## pulsa más rápido que una velocidad mínima.

## Barra de spam de la etapa actual (0..1).
var meter: float = 0.0
## Tiempo que falta de la animación de subirse; mientras tanto no cuenta el spam.
var _climb_timer: float = 0.0


func enter(_previous: StringName) -> void:
	meter = 0.0
	_climb_timer = 0.0
	rider.reset_steer()
	rider.set_recovery_stage(Rider.RecoveryStage.IN_WATER)
	rider.fell.emit()
	rider.mash_progress_changed.emit(meter, rider.recovery_stage)


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	var prone := rider.recovery_stage == Rider.RecoveryStage.PRONE

	# Frenado: fuerte si viene rápido (se acaba de caer), suave si está remando.
	var drag := stats.water_drag if rider.speed > stats.paddle_max_speed else stats.paddle_drag
	rider.speed = move_toward(rider.speed, 0.0, drag * delta)

	if prone:
		rider.apply_steer(input.steer, delta, stats.prone_turn_factor)
	else:
		rider.reset_steer()

	if _climb_timer > 0.0:
		_climb_timer -= delta
	elif input.mash_presses > 0:
		meter += stats.mash_fill_per_press * input.mash_presses
		rider.mash_pressed.emit()
		if prone:
			rider.speed = minf(
				rider.speed + stats.paddle_impulse * input.mash_presses, stats.paddle_max_speed
			)

	meter = maxf(0.0, meter - stats.mash_decay_per_second * delta)
	rider.move_forward(delta)
	rider.stick_to_water(delta, false)

	if meter >= 1.0:
		_advance_stage()
	else:
		rider.mash_progress_changed.emit(meter, rider.recovery_stage)


func _advance_stage() -> void:
	meter = 0.0
	if rider.recovery_stage == Rider.RecoveryStage.IN_WATER:
		rider.set_recovery_stage(Rider.RecoveryStage.PRONE)
		_climb_timer = rider.stats.climb_time
		rider.mash_progress_changed.emit(meter, rider.recovery_stage)
	else:
		state_machine.transition_to(&"riding")
