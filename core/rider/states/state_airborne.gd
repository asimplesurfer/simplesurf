extends RiderState
## En el aire (por salto o lanzado por una ola).
## Mantener A hace girar la tabla bajo el jugador (truco). El nitro del truco
## se cobra al aterrizar bien (así no alimenta el turbo en el mismo salto).
## Al soltar, la tabla termina el giro hasta quedar mirando al frente.
## Si toca el agua sin haber terminado el giro: truco fallido, nitro a 0 y al agua.
## El turbo en el aire acelera hacia adelante y, la primera ráfaga de cada salto,
## da un solo empujón hacia arriba. La gravedad nunca cambia: el salto siempre
## es una parábola (nada de flotar). Muy arriba el aire es "fino": la subida se
## va frenando de a poco, así el salto hace una curva en vez de chocar con un techo.

var _hold_time: float = 0.0
var _spins: int = 0
## Ya usó el empujón hacia arriba del turbo en este salto.
var _kick_used: bool = false
## Ráfaga de turbo en curso (para notar cuándo empieza una nueva).
var _prev_turbo_time: float = 0.0
## Nitro ganado con trucos en este salto; se suma al aterrizar bien.
var _pending_nitro: float = 0.0
## Ya llegó al aire fino en este salto.
var _reached_thin_air: bool = false


func enter(_previous: StringName) -> void:
	_hold_time = 0.0
	_spins = 0
	_kick_used = false
	_prev_turbo_time = rider.turbo_time
	_pending_nitro = 0.0
	_reached_thin_air = false
	rider.trick_angle = 0.0


func exit() -> void:
	rider.trick_angle = 0.0
	rider.live_spins = 0


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	# Pop tardío: A apenas la ola lo lanzó.
	if (
		input.jump_pressed
		and GameSettings.jump_style == GameSettings.JumpStyle.WAVES
		and rider.wave_air_time >= 0.0
	):
		rider.try_pop_press()
	rider.apply_steer(input.steer, delta, stats.air_turn_factor)
	rider.move_forward(delta)

	# El truco solo arranca si da el tiempo de completar una vuelta antes de
	# tocar el agua (si no, ni empieza: así no te caés por algo imposible).
	# En el saltito tampoco se puede.
	if rider.trick_angle <= 0.0 and rider.time_to_land() < TAU / stats.trick_spin_speed + 0.08:
		_hold_time = 0.0
	elif input.trick and rider.can_trick:
		_hold_time += delta
	else:
		_hold_time = 0.0

	if input.trick and rider.can_trick and _hold_time >= stats.trick_hold_delay and (
		rider.trick_angle > 0.0 or rider.time_to_land() >= TAU / stats.trick_spin_speed + 0.08
	):
		# Girando: la tabla rota y se carga nitro.
		rider.trick_angle += stats.trick_spin_speed * delta
		_pending_nitro += stats.trick_nitro_rate * delta
	elif rider.trick_angle > 0.0:
		# Soltó el botón: termina el giro hasta la próxima vuelta completa.
		var target := ceilf(rider.trick_angle / TAU - 0.001) * TAU
		rider.trick_angle = minf(rider.trick_angle + stats.trick_spin_speed * delta, target)
		if rider.trick_angle >= target - 0.0001:
			_spins += roundi(target / TAU)
			rider.trick_angle = 0.0

	# Contador del HUD: vueltas ya completas del truco en curso.
	rider.live_spins = _spins + int(floor(rider.trick_angle / TAU + 0.0001))

	var thin := _thin_air()
	if thin > 0.0:
		_reached_thin_air = true

	if rider.turbo_request(input.turbo):
		# Empujón único, en el momento en que sale la ráfaga (no en el saltito
		# ni ya en el aire fino). Después, gravedad normal.
		var new_burst := rider.turbo_time > _prev_turbo_time + 0.0001
		if new_burst and not _kick_used and rider.can_trick and not _reached_thin_air:
			_kick_used = true
			rider.vertical_speed = maxf(rider.vertical_speed, 0.0) + stats.air_turbo_kick
		rider.speed = move_toward(
			rider.speed,
			stats.max_speed * stats.turbo_speed_mult,
			stats.acceleration * stats.turbo_accel_mult * delta
		)
		rider.turbo_active = true
	_prev_turbo_time = rider.turbo_time

	# Aire fino: la subida pierde impulso de a poco (la caída es normal).
	if thin > 0.0 and rider.vertical_speed > 0.0:
		var brake := stats.gravity * stats.air_thin_gravity + rider.vertical_speed * stats.air_thin_drag
		rider.vertical_speed = maxf(rider.vertical_speed - brake * thin * delta, 0.0)

	if rider.update_air(delta):
		# Handicap: si al giro le falta poco, cuenta como terminado.
		if rider.trick_angle > 0.0:
			var target := ceilf(rider.trick_angle / TAU - 0.001) * TAU
			if target - rider.trick_angle <= rider.trick_grace():
				_spins += roundi(target / TAU)
				rider.trick_angle = 0.0
		if rider.trick_angle > 0.0:
			rider.reset_nitro()
			rider.trick_failed.emit()
			state_machine.transition_to(&"fallen")
		else:
			if _pending_nitro > 0.0:
				rider.add_nitro(_pending_nitro)
				_pending_nitro = 0.0
			if _spins > 0:
				rider.trick_landed.emit(_spins)
			state_machine.transition_to(&"riding")


## 0 por debajo de air_soft_height, 1 en air_max_height (y sigue creciendo un
## poco más arriba, para que ni los saltos más fuertes se vayan muy lejos).
func _thin_air() -> float:
	var stats := rider.stats
	var h := rider.position.y - rider.water_height()
	var span := maxf(stats.air_max_height - stats.air_soft_height, 0.1)
	return clampf((h - stats.air_soft_height) / span, 0.0, 1.5)
