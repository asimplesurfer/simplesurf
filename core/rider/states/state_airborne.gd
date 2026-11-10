extends RiderState
## En el aire (por salto o lanzado por una ola).
## Mantener A hace girar la tabla bajo el jugador (truco) y carga nitro.
## Al soltar, la tabla termina el giro hasta quedar mirando al frente.
## Si toca el agua sin haber terminado el giro: truco fallido, nitro a 0 y al agua.

var _hold_time: float = 0.0
var _spins: int = 0


func enter(_previous: StringName) -> void:
	_hold_time = 0.0
	_spins = 0
	rider.trick_angle = 0.0


func exit() -> void:
	rider.trick_angle = 0.0


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	rider.apply_steer(input.steer, delta, stats.air_turn_factor)
	rider.move_forward(delta)

	if input.trick:
		_hold_time += delta
	else:
		_hold_time = 0.0

	if input.trick and _hold_time >= stats.trick_hold_delay:
		# Girando: la tabla rota y se carga nitro.
		rider.trick_angle += stats.trick_spin_speed * delta
		rider.add_nitro(stats.trick_nitro_rate * delta)
	elif rider.trick_angle > 0.0:
		# Soltó el botón: termina el giro hasta la próxima vuelta completa.
		var target := ceilf(rider.trick_angle / TAU - 0.001) * TAU
		rider.trick_angle = minf(rider.trick_angle + stats.trick_spin_speed * delta, target)
		if rider.trick_angle >= target - 0.0001:
			_spins += roundi(target / TAU)
			rider.trick_angle = 0.0

	if rider.update_air(delta):
		if rider.trick_angle > 0.0:
			rider.reset_nitro()
			rider.trick_failed.emit()
			state_machine.transition_to(&"fallen")
		else:
			if _spins > 0:
				rider.trick_landed.emit(_spins)
			state_machine.transition_to(&"riding")
