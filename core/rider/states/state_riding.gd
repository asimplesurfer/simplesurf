extends RiderState
## Movimiento normal sobre la tabla: avanza solo y el stick gira.
## Más adelante: pasa a drifting con A y gasta nitro con B.


func enter(previous: StringName) -> void:
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	if previous == &"fallen":
		rider.stood_up.emit()


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	rider.speed = move_toward(rider.speed, stats.cruise_speed, stats.acceleration * delta)
	rider.steer(input.steer, delta)
	rider.move_forward(delta)
