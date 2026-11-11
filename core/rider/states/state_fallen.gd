extends RiderState
## Caído de la tabla. Hay que spamear A para recuperarse: una sola barra que
## se llena con una cantidad fija de pulsaciones y nunca baja.
##   - A la mitad se sube a la tabla y queda acostado (puede remar un poco).
##   - Llena, se para sobre la tabla y vuelve a `riding`.
## Las pulsaciones cuentan siempre (también mientras se sube a la tabla).

## Progreso total de la barra (0..1).
var meter: float = 0.0
## Tiempo que falta de la animación de subirse a la tabla.
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

	_climb_timer = maxf(_climb_timer - delta, 0.0)
	if input.mash_presses > 0:
		meter = minf(meter + stats.mash_fill_per_press * input.mash_presses, 1.0)
		rider.mash_pressed.emit()
		if prone:
			rider.speed = minf(
				rider.speed + stats.paddle_impulse * input.mash_presses, stats.paddle_max_speed
			)

	rider.move_forward(delta)
	rider.stick_to_water(delta, false)

	if not prone and meter >= 0.5:
		rider.set_recovery_stage(Rider.RecoveryStage.PRONE)
		_climb_timer = stats.climb_time
	# Llena: se para (apenas termina de subirse, si todavía estaba en eso).
	if meter >= 1.0 and _climb_timer <= 0.0:
		state_machine.transition_to(&"riding")
		return
	rider.mash_progress_changed.emit(meter, rider.recovery_stage)
