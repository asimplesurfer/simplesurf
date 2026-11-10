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
##   6. Si no, seguir su "camino" (hay 5 distintos; cambia en cada vuelta).
## Llegando a la meta va derecho al punto de la línea que tiene más cerca.
## En el aire hace trucos: mantiene mientras le da el tiempo para completar el
## giro antes de tocar el agua (a veces se equivoca, según la dificultad).

## Caminos posibles: desvío = base + amplitud * sin(ondas * ángulo + fase).
## base se mide desde el borde de adentro de la pista (m).
const PATHS := [
	{"name": "pegado a la isla", "base": 3.0, "amp": 2.0, "waves": 3.0},
	{"name": "adentro ondulado", "base": 8.0, "amp": 6.0, "waves": 2.0},
	{"name": "por el medio", "base": 22.0, "amp": 8.0, "waves": 3.0},
	{"name": "curva abierta", "base": 14.0, "amp": 11.0, "waves": 1.0},
	{"name": "zigzag", "base": 11.0, "amp": 7.0, "waves": 5.0},
]
## Metros antes de la meta en los que va derecho al punto más cercano de la línea.
const FINISH_APPROACH := 35.0

var difficulty: AIDifficulty
## Camino actual (índice en PATHS).
var path_index: int = 0

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
var _path_phase: float = 0.0
## Modo olas: ya intentó el pop en esta subida.
var _pop_tried: bool = false
## Decisión de ir o no a cada ola grande.
var _wave_choice: Dictionary = {}
## Ola constante: pico al que está mirando y si decidió ir a usarlo.
var _ring_peak_angle: float = NAN
var _ring_peak_choice: bool = false
var _water: Water
var _last_lap: int = -1


func _ready() -> void:
	rider = get_parent() as Rider
	if difficulty == null:
		difficulty = AIDifficulty.preset(1)
	_rng.randomize()
	_pick_path()
	course = get_tree().get_first_node_in_group("course") as Course
	_water = get_tree().get_first_node_in_group("water") as Water
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
		if rider.nitro >= difficulty.turbo_threshold and absf(input.steer) < difficulty.turbo_steer_limit:
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
	elif GameSettings.jump_style == GameSettings.JumpStyle.WAVES:
		# Modo olas: no salta en las rectas; hace el pop al subir una ola.
		if rider.vertical_speed > rider.stats.pop_min_climb + 1.0 and not _pop_tried:
			_pop_tried = true
			if _rng.randf() < difficulty.pop_skill:
				input.jump_pressed = true
				input.mash_presses = 1
		elif rider.vertical_speed < 0.5:
			_pop_tried = false
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


func _pick_path() -> void:
	path_index = _rng.randi() % PATHS.size()
	_path_phase = _rng.randf_range(0.0, TAU)


## Desvío lateral del camino actual en ese ángulo.
func path_lateral(angle: float, lane: float) -> float:
	var p: Dictionary = PATHS[path_index]
	# Los valores de PATHS están pensados para una pista de 30 m de mitad útil.
	var k := lane / 30.0
	var lat: float = -lane + p.base * k + p.amp * k * sin(p.waves * angle + _path_phase)
	return clampf(lat, -lane + 2.0, lane - 2.0)


## Decide a qué desvío lateral apuntar.
func _think(angle: float, lateral: float) -> void:
	var track := course.track
	var lane := track.half_width - 3.0
	_noise = _rng.randf_range(-1.0, 1.0) * difficulty.steer_noise * 4.0

	# Cada vuelta, otro camino (así no van siempre por el mismo lado).
	if race:
		var lap := race.lap_of(rider)
		if lap != _last_lap:
			if _last_lap >= 0:
				_pick_path()
			_last_lap = lap

	var target := path_lateral(angle, lane) + _noise

	# Círculo de velocidad próximo.
	var ring := _next_ring(angle)
	if ring:
		var id := ring.get_instance_id()
		if not _ring_choice.has(id):
			_ring_choice[id] = _rng.randf() < difficulty.ring_seek
		if _ring_choice[id]:
			target = track.lateral_of(ring.position)

	# Modo olas: ir a buscar una ola grande que tiene adelante.
	if GameSettings.jump_style == GameSettings.JumpStyle.WAVES:
		var swell := _next_swell(angle, lateral)
		if swell:
			target = track.lateral_of(Vector3(swell.center.x, 0.0, swell.center.y))
		var ring_target := _ring_wave_target(angle, lateral)
		if not is_nan(ring_target):
			target = ring_target

	# Llegando a la meta: derecho al punto más cercano de la línea.
	var to_line := _arc_ahead(angle, 0.0, lateral)
	if to_line > 0.0 and to_line < FINISH_APPROACH:
		target = lateral

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


## Ola grande más cercana adelante que decidió ir a buscar (o null).
func _next_swell(angle: float, lateral: float) -> Swell:
	if _water == null:
		return null
	var best: Swell = null
	var best_d := 1e9
	for s in _water.swells:
		if s.amplitude < 1.5:
			continue
		var pos := Vector3(s.center.x, 0.0, s.center.y)
		if absf(course.track.lateral_of(pos)) > course.track.half_width:
			continue
		var d := _arc_ahead(angle, course.track.angle_of(pos), lateral)
		if d < 12.0 or d > 55.0 or d >= best_d:
			continue
		var id := s.get_instance_id()
		if not _wave_choice.has(id):
			_wave_choice[id] = _rng.randf() < difficulty.wave_seek
		if _wave_choice[id]:
			best = s
			best_d = d
	return best


## Ola constante: si decidió usar el próximo pico que viene de frente,
## el desvío lateral de la cresta; si no, NAN.
func _ring_wave_target(angle: float, lateral: float) -> float:
	if _water == null or _water.ring_wave == null:
		return NAN
	var rw := _water.ring_wave
	var peak := rw.next_peak_angle(angle)
	# Pico nuevo (el anterior ya pasó): decidir si va a buscarlo.
	if is_nan(_ring_peak_angle) or absf(wrapf(peak - _ring_peak_angle, -PI, PI)) > PI / rw.lobes:
		_ring_peak_choice = _rng.randf() < difficulty.wave_seek
	_ring_peak_angle = peak
	var d := _arc_ahead(angle, peak, lateral)
	if _ring_peak_choice and d > 4.0 and d < 45.0:
		return rw.radius - course.track.radius - 0.5
	return NAN


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
		# Con handicap se equivoca menos en los trucos.
		var fail_chance := difficulty.trick_fail_chance * (1.0 - 0.6 * rider.catchup)
		_trick_will_fail = _rng.randf() < fail_chance

	var stats := rider.stats
	var spin := stats.trick_spin_speed
	var full_turn := TAU / spin
	var t_land := _time_to_land()
	# Turbo en el aire para subir más y tener tiempo para más vueltas.
	if difficulty.uses_turbo and rider.nitro > difficulty.turbo_threshold and rider.vertical_speed > -2.0:
		input.turbo = true
		t_land += 0.5
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
