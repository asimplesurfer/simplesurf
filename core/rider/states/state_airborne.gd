extends RiderState
## En el aire (por salto o lanzado por una ola).
## Mantener A hace trucos (el contador sube con cada tiempo completo). Al
## soltar, cuenta lo completado y la tabla vuelve rápido a su lugar (solo se
## ve: ya no puede tirarlo). Si toca el agua con A todavía apretada: truco
## fallido, nitro a 0 y al agua. El nitro del truco se cobra al aterrizar bien
## (así no alimenta el turbo en el mismo salto).
## El turbo en el aire acelera hacia adelante y, la primera ráfaga de cada salto,
## da un solo empujón hacia arriba. La gravedad nunca cambia: el salto siempre
## es una parábola (nada de flotar). Muy arriba el aire es "fino": la subida se
## va frenando de a poco, así el salto hace una curva en vez de chocar con un techo.

var _hold_time: float = 0.0
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
	_kick_used = false
	_prev_turbo_time = rider.turbo_time
	_pending_nitro = 0.0
	_reached_thin_air = false
	rider.trick_angle = 0.0
	# Trucos nuevos al azar para este salto.
	rider.trick_kinds.clear()
	rider.trick_units_done = 0
	rider.trick_scored = 0
	rider.trick_hold_start = 0.0
	rider.trick_releasing = false


func exit() -> void:
	rider.end_trick_preview()
	rider.trick_angle = 0.0
	rider.live_spins = 0
	rider.trick_units_done = 0
	rider.trick_scored = 0
	rider.trick_hold_start = 0.0
	rider.trick_releasing = false
	rider.trick_kinds.clear()


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

	# Cada truco solo arranca si da el tiempo de terminarlo antes de tocar el
	# agua (si no, ni empieza). Los largos salen en los saltos grandes; en el
	# saltito no se puede. Se mira el agua de verdad (una ola que sube adelante
	# o viene detrás lo alcanza antes).
	var unit_time := TAU / stats.trick_spin_speed
	var land_t := rider.time_to_land()
	if input.trick and rider.can_trick and not rider.trick_releasing:
		land_t = minf(land_t, rider.time_to_land_ahead(unit_time * 3.0 + 0.5))
	var fit_units := int(floor((land_t - 0.08) / unit_time))
	var spinning := rider.trick_angle > 0.0 and not rider.trick_releasing
	if not spinning and fit_units < 1:
		_hold_time = 0.0
	elif input.trick and rider.can_trick and not rider.trick_releasing:
		_hold_time += delta
	else:
		_hold_time = 0.0

	if rider.trick_preview:
		# Visor de trucos: mantiene el truco solo hasta terminarlo (uno solo).
		var done := rider.trick_units_now() >= Rider.TRICK_UNITS[rider.trick_kinds[0]] - 0.001
		input.trick = not done and not rider.trick_releasing
		_hold_time = maxf(_hold_time, stats.trick_hold_delay) if input.trick else 0.0
	var holding := input.trick and rider.can_trick and not rider.trick_releasing \
		and _hold_time >= stats.trick_hold_delay
	# Empieza un truco nuevo: se elige uno que llegue a terminarse.
	if holding and not spinning:
		rider.trick_hold_start = rider.trick_units_now()
	if holding and rider.trick_at(rider.trick_units_now() + 0.0001)[0] < 0:
		holding = rider.choose_next_trick(fit_units)
	if holding:
		# Haciendo el truco: avanza y se carga nitro (por tiempo).
		rider.trick_angle += stats.trick_spin_speed * delta
		_pending_nitro += stats.trick_nitro_rate * delta
		# Si sigue apretando al terminar uno, encadena otro: uno que llegue a
		# terminarse si hay, y si no, uno corto igual (el riesgo es del
		# jugador: si toca el agua con A apretada, se cae).
		if rider.trick_at(rider.trick_units_now())[0] < 0:
			if rider.trick_preview:
				# Visor: un solo truco; se queda justo al final.
				var end_units := float(Rider.TRICK_UNITS[rider.trick_kinds[0]])
				rider.trick_angle = (end_units - rider.trick_units_done) * TAU
			elif not rider.choose_next_trick(fit_units):
				rider.choose_next_trick(1)
	elif spinning:
		# Soltó A: cuenta lo que completó (lo que muestra el contador) y la
		# tabla vuelve rápido a su lugar.
		_release()
	if rider.trick_releasing:
		var target := rider.trick_end_angle()
		rider.trick_angle = minf(
			rider.trick_angle + stats.trick_spin_speed * stats.trick_release_speed_mult * delta, target
		)
		if rider.trick_angle >= target - 0.0001:
			rider.trick_units_done += roundi(target / TAU)
			rider.trick_angle = 0.0
			rider.trick_releasing = false

	# Contador del HUD: tiempos de truco completos que ya cuentan (los largos
	# suman más). Mientras la tabla vuelve a su lugar, no sube.
	rider.live_spins = rider.trick_scored + _held_units()

	var thin := 0.0 if rider.trick_preview else _thin_air()
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

	# Handicap: si le falta muy poco para tocar el agua con A apretada, el
	# juego suelta solo (como si hubiera soltado apenas a tiempo).
	if (
		rider.trick_angle > 0.0
		and not rider.trick_releasing
		and rider.trick_grace() > 0.0
		and rider.time_to_land() <= rider.trick_grace()
	):
		_release()
		rider.live_spins = rider.trick_scored

	if rider.update_air(delta):
		if rider.trick_angle > 0.0 and not rider.trick_releasing:
			# Tocó el agua con A apretada: truco fallido.
			rider.reset_nitro()
			rider.trick_failed.emit()
			state_machine.transition_to(&"fallen")
		else:
			if _pending_nitro > 0.0:
				rider.add_nitro(_pending_nitro)
				_pending_nitro = 0.0
			if rider.trick_scored > 0:
				rider.best_combo = maxi(rider.best_combo, rider.trick_scored)
				rider.trick_landed.emit(rider.trick_scored)
			state_machine.transition_to(&"riding")


## Tiempos completos desde que empezó a mantener A esta vez.
func _held_units() -> int:
	if rider.trick_angle <= 0.0 or rider.trick_releasing:
		return 0
	return maxi(int(floor(rider.trick_units_now() - rider.trick_hold_start + 0.0001)), 0)


## Suelta el truco: suma lo completado y la tabla vuelve a su lugar.
func _release() -> void:
	rider.trick_scored += _held_units()
	rider.trick_releasing = true


## 0 por debajo de air_soft_height, 1 en air_max_height (y sigue creciendo un
## poco más arriba, para que ni los saltos más fuertes se vayan muy lejos).
func _thin_air() -> float:
	var stats := rider.stats
	var h := rider.position.y - rider.water_height()
	var span := maxf(stats.air_max_height - stats.air_soft_height, 0.1)
	return clampf((h - stats.air_soft_height) / span, 0.0, 1.5)
