class_name AIController
extends BaseController
## Bot: genera el mismo RiderInput que un jugador, a partir de lo que "ve"
## (coordenadas de pista: ángulo alrededor de la isla y desvío lateral).
##
## Prioridades:
##   1. Caído: spamear al máximo para levantarse (sin importar la dificultad).
##   2. Esquivar rocas que tiene adelante.
##   3. No quedar justo detrás de un rival cercano (puede derraparle encima).
##   4. Derrapar si tiene un rival justo detrás (según agresividad).
##   5. Ir al próximo círculo de velocidad (según dificultad).
##   6. Si no, ir por el lado de adentro (el camino más corto).
## En el aire hace trucos: mantiene mientras le da el tiempo para completar el
## giro antes de tocar el agua (a veces se equivoca, según la dificultad).

var difficulty: AIDifficulty

var rider: Rider
var course: Course
var race: RaceManager

var _rng := RandomNumberGenerator.new()
var _think_timer: float = 0.0
var _target_lateral: float = 0.0
var _noise: float = 0.0
var _mash_timer: float = 0.0
var _jump_hold: float = 0.0
var _jump_started: bool = false
var _drift_timer: float = 0.0
var _turbo_on: bool = false
var _trick_will_fail: bool = false
var _was_airborne: bool = false
## Decisión de ir o no a cada círculo (para no cambiar de idea a cada rato).
var _ring_choice: Dictionary = {}
## Lado elegido para esquivar cada roca (-1 / 1), hasta pasarla.
var _rock_side: Dictionary = {}
## Frenar un poco (hay una roca cerca).
var _brake: bool = false


func _ready() -> void:
	rider = get_parent() as Rider
	if difficulty == null:
		difficulty = AIDifficulty.preset(1)
	_rng.randomize()
	course = get_tree().get_first_node_in_group("course") as Course
	race = get_tree().get_first_node_in_group("race_manager") as RaceManager


func get_input(delta: float) -> RiderInput:
	var input := RiderInput.new()
	if rider == null or course == null or rider.controls_locked:
		return input
	var state := rider.state_machine.current_name
	if state == &"fallen":
		_jump_hold = 0.0
		_turbo_on = false
		return _mash(delta, input)
	if state == &"airborne":
		_air(delta, input)
	else:
		_drive(delta, input)
	_was_airborne = state == &"airborne"
	return input


func _mash(delta: float, input: RiderInput) -> RiderInput:
	_mash_timer -= delta
	if _mash_timer <= 0.0:
		_mash_timer = 1.0 / difficulty.mash_rate
		input.mash_presses = 1
	return input


# --- En el agua -------------------------------------------------------------

func _drive(delta: float, input: RiderInput) -> void:
	var track := course.track
	var angle := track.angle_of(rider.position)
	var lateral := track.lateral_of(rider.position)

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = difficulty.think_interval
		_think(angle, lateral)

	input.steer = _steer_towards(angle, lateral, _target_lateral)
	input.throttle = difficulty.max_throttle * (0.6 if _brake else 1.0)

	# Derrape (para tirar al de atrás).
	if _drift_timer > 0.0:
		_drift_timer -= delta
		input.drift = true

	# Turbo en línea recta cuando junta suficiente nitro.
	if difficulty.uses_turbo:
		if rider.nitro >= difficulty.turbo_threshold and absf(input.steer) < 0.35:
			_turbo_on = true
		if rider.nitro <= 0.0 or absf(input.steer) > 0.8:
			_turbo_on = false
		input.turbo = _turbo_on

	# Salto para hacer un truco.
	if _jump_hold > 0.0:
		input.trick = true
		if not _jump_started:
			input.jump_pressed = true
			input.mash_presses = 1
			_jump_started = true
		_jump_hold -= delta
	elif _drift_timer <= 0.0 and _clear_ahead(angle, lateral, 22.0):
		if _rng.randf() < difficulty.trick_jump_rate * delta:
			_start_jump()


func _start_jump() -> void:
	_jump_started = false
	if GameSettings.jump_mode == GameSettings.JumpMode.TAP:
		_jump_hold = 0.05
	else:
		# Mantener casi hasta el máximo: salta solo al llegar.
		_jump_hold = _rng.randf_range(0.6, 1.1)


## Decide a qué desvío lateral apuntar.
func _think(angle: float, lateral: float) -> void:
	var track := course.track
	var lane := track.half_width - 6.0
	_noise = _rng.randf_range(-1.0, 1.0) * difficulty.steer_noise * 4.0

	# Por defecto: el lado de adentro (vuelta más corta), sin pegarse a las boyas.
	var target := -lane + 3.0 + _noise

	# Círculo de velocidad próximo.
	var ring := _next_ring(angle)
	if ring:
		var id := ring.get_instance_id()
		if not _ring_choice.has(id):
			_ring_choice[id] = _rng.randf() < difficulty.ring_seek
		if _ring_choice[id]:
			target = track.lateral_of(ring.position)

	# Rival adelante y cerca: no quedarse justo detrás (puede derrapar).
	# Rival justo detrás: derraparle encima.
	for other in race.racers if race else []:
		if other == rider or other.is_fallen():
			continue
		var ahead := _arc_ahead(angle, track.angle_of(other.position), lateral)
		var dlat := track.lateral_of(other.position) - lateral
		if ahead > 0.0 and ahead < 10.0 and absf(dlat) < 2.5:
			target = lateral + (4.0 if dlat <= 0.0 else -4.0)
		elif ahead < 0.0 and ahead > -6.0 and absf(dlat) < 2.5:
			if rider.speed > rider.stats.drift_min_speed + 1.0 and _rng.randf() < difficulty.aggression:
				_drift_timer = 0.6

	# Rocas: la más cercana que quede en el camino (entre donde está y adonde
	# va) se esquiva por el lado elegido, y se mantiene ese lado hasta pasarla.
	_brake = false
	var nearest: Rock = null
	var nearest_ahead := 1e9
	for rock in course.rocks:
		var id := rock.get_instance_id()
		var ahead := _arc_ahead(angle, track.angle_of(rock.position), lateral)
		if ahead < -3.0:
			_rock_side.erase(id)
			continue
		if ahead <= 0.0 or ahead > difficulty.look_ahead:
			continue
		var rock_lat := track.lateral_of(rock.position)
		var clearance := rock.radius + 2.6
		var lo := minf(lateral, target) - clearance
		var hi := maxf(lateral, target) + clearance
		var in_path := rock_lat > lo and rock_lat < hi
		if (in_path or _rock_side.has(id)) and ahead < nearest_ahead:
			nearest = rock
			nearest_ahead = ahead
	if nearest:
		var id := nearest.get_instance_id()
		var rock_lat := track.lateral_of(nearest.position)
		var clearance := nearest.radius + 3.0
		if not _rock_side.has(id):
			var left := rock_lat - clearance
			var right := rock_lat + clearance
			var side := -1 if absf(left - lateral) < absf(right - lateral) else 1
			# Si de ese lado no hay lugar (borde de la pista), el otro.
			if side < 0 and left < -lane:
				side = 1
			elif side > 0 and right > lane:
				side = -1
			_rock_side[id] = side
		target = rock_lat + clearance * _rock_side[id]
		# Cerca y todavía no está al costado: aflojar para poder girar más cerrado.
		if nearest_ahead < 14.0 and absf(rock_lat - lateral) < clearance:
			_brake = true

	_target_lateral = clampf(target, -lane, lane)


## Metros por delante (siguiendo la pista) de un punto en otro ángulo. Negativo = detrás.
func _arc_ahead(from_angle: float, to_angle: float, lateral: float) -> float:
	var d := wrapf(to_angle - from_angle, -PI, PI)
	return d * (course.track.radius + lateral)


func _next_ring(angle: float) -> NitroRing:
	var best: NitroRing = null
	var best_d := 1e9
	for ring in course.rings:
		var d := _arc_ahead(angle, course.track.angle_of(ring.position), 0.0)
		if d > 4.0 and d < 70.0 and d < best_d:
			best_d = d
			best = ring
	return best


func _clear_ahead(angle: float, lateral: float, distance: float) -> bool:
	for rock in course.rocks:
		var ahead := _arc_ahead(angle, course.track.angle_of(rock.position), lateral)
		if ahead > 0.0 and ahead < distance:
			if absf(course.track.lateral_of(rock.position) - lateral) < rock.radius + 4.0:
				return false
	return true


## Volante hacia un punto de la pista unos metros adelante, en el desvío pedido.
func _steer_towards(angle: float, lateral: float, target_lateral: float) -> float:
	var track := course.track
	var look := 14.0
	var aim_angle := angle + look / maxf(track.radius + lateral, 10.0)
	var aim := track.position_at(aim_angle, target_lateral)
	var to_aim := aim - rider.position
	var desired := atan2(-to_aim.x, -to_aim.z)
	var err := wrapf(desired - rider.heading, -PI, PI)
	return clampf(-err * 2.5, -1.0, 1.0)


# --- En el aire --------------------------------------------------------------

func _air(_delta: float, input: RiderInput) -> void:
	var track := course.track
	var angle := track.angle_of(rider.position)
	var lateral := track.lateral_of(rider.position)
	input.steer = _steer_towards(angle, lateral, _target_lateral)
	_jump_hold = 0.0

	if not _was_airborne:
		_trick_will_fail = _rng.randf() < difficulty.trick_fail_chance

	var stats := rider.stats
	var spin := stats.trick_spin_speed
	var full_turn := TAU / spin
	var t_land := _time_to_land()
	if _trick_will_fail:
		input.trick = true
		return
	var a := rider.trick_angle
	if a <= 0.0:
		# ¿Le da el tiempo para empezar y completar una vuelta?
		input.trick = t_land > stats.trick_hold_delay + full_turn + 0.12
	else:
		var remaining := (ceilf(a / TAU - 0.001) * TAU - a) / spin
		# Seguir si alcanza para terminar esta vuelta y hacer otra completa.
		input.trick = t_land > remaining + full_turn + 0.1


## Estimación del tiempo hasta tocar el agua (tiro vertical).
func _time_to_land() -> float:
	var g := rider.stats.gravity
	var vy := rider.vertical_speed
	var h := rider.position.y - rider.water_height()
	var disc := vy * vy + 2.0 * g * maxf(h, 0.0)
	return (vy + sqrt(disc)) / g
