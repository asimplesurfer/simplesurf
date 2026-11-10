extends RiderState
## En el aire (por salto o lanzado por una ola).
## Mantener A hace girar la tabla bajo el jugador (truco) y carga nitro.
## Al soltar, la tabla termina el giro hasta quedar mirando al frente.
## Si toca el agua sin haber terminado el giro: truco fallido, nitro a 0 y al agua.
## El turbo sigue funcionando en el aire: empuja hacia arriba (cada vez más
## fuerte mientras se mantiene) y da más tiempo para trucos, gastando nitro.

var _hold_time: float = 0.0
var _spins: int = 0
var _air_turbo_time: float = 0.0


func enter(_previous: StringName) -> void:
	_hold_time = 0.0
	_spins = 0
	_air_turbo_time = 0.0
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

	if input.turbo and rider.nitro > 0.0:
		_air_turbo_time += delta
		var lift := stats.air_turbo_lift * exp(stats.air_turbo_growth * _air_turbo_time)
		rider.vertical_speed = minf(rider.vertical_speed + lift * delta, stats.air_turbo_max_up)
		rider.speed = move_toward(
			rider.speed,
			stats.max_speed * stats.turbo_speed_mult,
			stats.acceleration * stats.turbo_accel_mult * delta
		)
		rider.add_nitro(-stats.air_turbo_drain * delta)
		rider.turbo_active = true
	else:
		_air_turbo_time = 0.0

	if rider.update_air(delta):
		if rider.trick_angle > 0.0:
			rider.reset_nitro()
			rider.trick_failed.emit()
			state_machine.transition_to(&"fallen")
		else:
			if _spins > 0:
				rider.trick_landed.emit(_spins)
			state_machine.transition_to(&"riding")
