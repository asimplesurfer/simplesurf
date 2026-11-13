extends RiderState
## Modo libre: acostado sobre la tabla, remando con los brazos. Con el stick
## hacia adelante va tomando impulso; cuando ya va lo bastante rápido (y sigue
## empujando), se para de un salto y pasa a `riding`. Sin empujar, se frena.

## Velocidad a la que se para (m/s).
const STAND_SPEED := 2.7
## Cuánto acelera remando (m/s²).
const PADDLE_ACCEL := 1.3
## Hay que estar empujando al menos así para pararse.
const STAND_PUSH := 0.6


func enter(_previous: StringName) -> void:
	rider.set_recovery_stage(Rider.RecoveryStage.PRONE)
	rider.jump_charge = 0.0
	rider.drift_side = 0


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	var push := maxf(input.throttle, 0.0)
	var target := stats.paddle_max_speed * push
	if rider.speed < target:
		rider.speed = move_toward(rider.speed, target, PADDLE_ACCEL * delta)
	else:
		var brake := 3.0 if input.throttle < -0.1 else 1.0
		rider.speed = move_toward(rider.speed, target, stats.paddle_drag * brake * delta)
	rider.apply_steer(input.steer, delta, stats.prone_turn_factor)
	rider.move_forward(delta)
	rider.stick_to_water(delta, false)
	if push >= STAND_PUSH and rider.speed >= STAND_SPEED:
		state_machine.transition_to(&"riding")
