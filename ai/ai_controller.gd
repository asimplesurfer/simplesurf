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
## Con bifurcaciones, en cada vuelta elige un camino en cada tramo (según su
## estilo: los más agresivos y los que mejor juegan van más por el más corto)
## y ve la pista como esa vuelta (ver PathTrack.variant).
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
## La pista como la ve: la vuelta por los caminos que eligió (sin
## bifurcaciones, la pista de siempre).
var _track: TrackSpace:
	get:
		return _view if _view else (course.track if course else null)
	set(value):
		_view = value
var _view: TrackSpace
## Caminos alternativos que va a tomar en esta vuelta (rutas, en orden; ver
## PathTrack.variant). Vacío: toda la vuelta por la principal.
var route_choices: Array = []
var _routes_picked: bool = false

var _rng := RandomNumberGenerator.new()
var _think_timer: float = 0.0
var _target_lateral: float = 0.0
var _noise: float = 0.0
var _mash_timer: float = 0.0
## Ritmo de spam de esta caída (se sortea al caer).
var _mash_rate: float = 0.0
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
## Sombra del derrape: por cada rival de adelante, si decidió no quedarse
## detrás (id -> bool) y de qué lado lo pasa (id -> -1 / 1).
var _shadow_choice: Dictionary = {}
var _shadow_side: Dictionary = {}
## Hasta cuántos metros más allá del alcance del derrape mira la sombra, y
## cuánto margen deja al costado del cono.
const SHADOW_EXTRA := 6.0
const SHADOW_MARGIN := 1.4
## Rivales que lo tiraron con un derrape: id -> hasta cuándo (race_time) les
## da más espacio (los mira desde más lejos y se abre más).
var _wary_until: Dictionary = {}
var _rivals_watched: bool = false
## Segundos para alcanzarlo en los que ya se va a su paralela.
const SHADOW_PLAN_TIME := 3.0
## Metros que tiene que dejarlo atrás para volver a su línea.
const PASS_CLEAR := 4.0
const WARY_TIME := 25.0
const WARY_EXTRA := 10.0
const WARY_MARGIN := 1.5
## Por qué no va por su línea ahora (para medir; ver tools/bot_race.gd).
var debug_reason: String = ""
## El destino de ahora es su línea (no una ola, un aro, una roca o un rival).
var _on_line: bool = false
## Para ir a un aro: metros de costado que puede moverse por metro de avance.
const RING_REACH_SLOPE := 0.45
## Metros de más que vale la pena hacer para agarrar un aro (nitro y sprint).
const RING_WORTH := 5.0
const RING_LEG := 25.0
## Olas: altura (m) con la que una ola ya lo lanza bien, cada cuántos metros
## de costado prueba por dónde cruzarla y cuántos metros de más vale un salto.
const WAVE_GOOD_HEIGHT := 1.6
const WAVE_STEP := 2.0
const WAVE_WORTH := 7.0
## Siguiendo su línea, apunta a este punto más adelante (m).
const AIM_DISTANCE := 14.0
## Largada: segundos que sigue por su carril antes de ir a su línea (y lo que
## tarda en pasar de uno a otra). Ver AIDifficulty.keeps_start_lane.
const START_LANE_TIME := 4.0
const START_LANE_BLEND := 2.5
var _start_lane: float = NAN


func _ready() -> void:
	rider = get_parent() as Rider
	if difficulty == null:
		difficulty = AIDifficulty.preset(1)
	_rng.randomize()
	_pick_path()
	course = GameSession.find_in_scene(self, "course") as Course
	_water = GameSession.find_in_scene(self, "water") as Water
	race = GameSession.find_in_scene(self, "race_manager") as RaceManager


func get_input(delta: float) -> RiderInput:
	var input := RiderInput.new()
	if rider == null or course == null or rider.controls_locked:
		return input
	if not _routes_picked:
		pick_routes()
	_track = course.track.variant(route_choices)
	var state := rider.state_machine.current_name
	if state != &"tube":
		_in_tube_before = false
	if state == &"fallen":
		_jump_hold = 0.0
		_turbo_on = false
		return _mash(delta, input)
	_mash_rate = 0.0
	if state == &"tube":
		_tube(delta, input)
	elif state == &"airborne":
		_air(delta, input)
	else:
		_drive(delta, input)
	_was_airborne = state == &"airborne"
	return input


func _mash(delta: float, input: RiderInput) -> RiderInput:
	if _mash_rate <= 0.0:
		# Recién se cayó: cada caída a un ritmo algo distinto (nunca más rápido
		# que el de su dificultad).
		_mash_rate = difficulty.mash_rate * _rng.randf_range(AIDifficulty.MASH_SPREAD, 1.0)
		_mash_timer = 1.0 / _mash_rate
	_mash_timer -= delta
	if _mash_timer <= 0.0:
		_mash_timer = 1.0 / _mash_rate
		input.mash_presses = 1
	return input


# --- Ola tubo ---------------------------------------------------------------

## Decisión de ir o no a cada ola tubo (id -> bool).
var _tube_choice: Dictionary = {}
## En este tubo se va a caer (según la dificultad), y cuándo deja de corregir.
var _tube_will_fail: bool = false
var _tube_fail_at: float = 0.0
var _tube_time: float = 0.0
var _tube_steer: float = 0.0
var _tube_think: float = 0.0
var _in_tube_before: bool = false


## Desvío lateral de la boca de una ola tubo que tiene adelante y a la que
## decidió ir (NAN si no hay).
func _tube_target(angle: float) -> float:
	for node in rider.get_tree().get_nodes_in_group("tube_waves"):
		var tw := node as TubeWave
		if tw == null or tw.course != course or not tw.accepting() or tw.used.has(rider):
			continue
		var ahead := -tw.s_of(rider.position)
		if ahead < -1.0 or ahead > 90.0:
			continue
		var id := tw.get_instance_id()
		if not _tube_choice.has(id):
			# El que la provocó va siempre; los demás según cuánto buscan las olas.
			_tube_choice[id] = tw.opener == rider or _rng.randf() < 0.5 + 0.5 * difficulty.wave_seek
		if _tube_choice[id]:
			# Un poco hacia el lado abierto (la boca es más ancha de ese lado).
			return tw.mouth_lateral()
	return NAN


## Adentro del tubo: corrige el equilibrio con algo de demora y ruido (según
## la dificultad). A veces (más en fácil) se le escapa y se cae.
func _tube(delta: float, input: RiderInput) -> void:
	var state := rider.state_machine.current as RiderState
	if not _in_tube_before:
		_in_tube_before = true
		_tube_time = 0.0
		_tube_steer = 0.0
		_tube_think = 0.0
		_tube_will_fail = _rng.randf() < difficulty.trick_fail_chance * 1.2
		var total := rider.tube.time_left() if rider.tube else 8.0
		_tube_fail_at = _rng.randf_range(0.25, 0.85) * total
	_tube_time += delta
	_tube_think -= delta
	if _tube_think <= 0.0:
		_tube_think = maxf(difficulty.think_interval, 0.05)
		var bal := rider.tube_balance
		# Hacia la pared (+) o hacia el lado abierto (-): lo contrario de donde está.
		var toward_wall := clampf(-bal * 2.6, -1.0, 1.0)
		toward_wall += _rng.randf_range(-1.0, 1.0) * difficulty.steer_noise
		if _tube_will_fail and _tube_time > _tube_fail_at:
			# Se le fue: corrige para el lado equivocado.
			toward_wall = signf(bal) if bal != 0.0 else 1.0
		var wall_sign: float = state.call("wall_on_right_sign") if state and state.has_method("wall_on_right_sign") else 1.0
		_tube_steer = clampf(toward_wall, -1.0, 1.0) * wall_sign
	input.steer = _tube_steer
	input.throttle = 1.0


# --- En el agua -------------------------------------------------------------

func _drive(delta: float, input: RiderInput) -> void:
	var track := _track
	var angle := track.angle_of(rider.position)
	var lateral := track.lateral_of(rider.position)

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = difficulty.think_interval
		_think(angle, lateral)

	# Siguiendo su línea, apunta a donde va la línea más adelante (no a la de acá).
	var aim_lateral := _target_lateral
	if _on_line and difficulty.line_skill > 0.0:
		var lane := track.half_width - difficulty.edge_margin
		aim_lateral = _line_target(angle + AIM_DISTANCE / maxf(track.radius + lateral, 10.0), lane) + _noise
	input.steer = _steer_towards(angle, lateral, aim_lateral)
	input.throttle = difficulty.max_throttle * (difficulty.rock_throttle if _brake else 1.0)

	# Derrape (para tirar al de atrás).
	if _drift_timer > 0.0:
		_drift_timer -= delta
		input.drift = true

	# Turbo en ráfagas: lo mejor es justo antes de que una ola lo lance; si no,
	# en una recta cuando junta suficiente nitro.
	if difficulty.saves_turbo_for_waves and rider.turbo_time <= 0.0 and rider.turbo_charges() >= 1:
		# Como juegan los mejores: en el aire la velocidad no baja, así que el
		# turbo rinde en el agua. Lo tienen andando todo el tiempo que están
		# en el agua (y así también cuando la ola los lanza: salen el doble
		# de alto, con más vueltas y más nitro).
		input.turbo_pressed = true
	elif difficulty.eager_turbo and rider.turbo_time <= 0.0 and rider.turbo_charges() >= 1:
		# Turbo apenas hay una carga (salvo en una curva cerrada o frenando
		# por una roca).
		if absf(input.steer) < 0.8 and not _brake:
			input.turbo_pressed = true
	elif difficulty.uses_turbo and rider.turbo_time <= 0.0 and rider.turbo_charges() >= 1:
		var before_wave := rider.pop_ready() and _rng.randf() < difficulty.pop_skill
		var straight := (
			rider.nitro >= maxf(difficulty.turbo_threshold, Rider.TURBO_CHARGE)
			and absf(input.steer) < difficulty.turbo_steer_limit
		)
		# Los mejores guardan una carga para la próxima ola (salir volando).
		if difficulty.saves_turbo_for_waves and _next_swell(angle, lateral) != null:
			straight = straight and rider.turbo_charges() >= 2
		if before_wave or straight:
			input.turbo_pressed = true

	# Salto para hacer un truco.
	if _jump_hold > 0.0:
		input.trick = true
		if not _jump_started:
			input.jump_pressed = true
			input.mash_presses = 1
			_jump_started = true
		_jump_hold -= delta
	elif GameSettings.jump_style == GameSettings.JumpStyle.WAVES:
		# Modo olas: no salta en las rectas; hace el pop justo antes de la cresta.
		if rider.pop_ready() and not _pop_tried:
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


## Elige los caminos de la vuelta: recorre la pista desde la meta y en cada
## punto donde salen caminos alternativos decide por dónde ir. Muchas veces el
## más corto (más cuanto más agresivo y mejor juega); si no, uno cualquiera.
func pick_routes() -> void:
	_routes_picked = true
	route_choices.clear()
	var track := course.track as PathTrack
	if track == null or track.branches.is_empty():
		_track = course.track
		return
	var prefer := clampf(0.3 + 0.35 * difficulty.aggression + 0.35 * difficulty.line_skill, 0.0, 0.9)
	var s := 0.0
	for guard in 64:
		var options := track.next_departures(s)
		if options.is_empty():
			break
		var here := track.branches[options[0] - 1].s_from
		# Opciones: seguir por la principal (0) o tomar uno de los que salen acá.
		var all: Array[int] = [0]
		all.append_array(options)
		var shortest := 0
		for r in options:
			if track.route_extra(r) < (track.route_extra(shortest) if shortest > 0 else 0.0):
				shortest = r
		var pick: int = shortest if _rng.randf() < prefer else all[_rng.randi() % all.size()]
		if pick == 0:
			s = here + 1.0
		else:
			route_choices.append(pick)
			s = track.branches[pick - 1].s_to
	_track = track.variant(route_choices)


## Si terminó en otro camino (lo empujaron, no llegó a doblar), sigue por ese:
## no intenta volver cruzando la tierra que los separa.
func _stay_on_route(lateral: float) -> void:
	var track := course.track as PathTrack
	if track == null or track.branches.is_empty() or absf(lateral) < track.half_width + 2.0:
		return
	var loc := track.locate_route(rider.position)
	var route := int(loc.z)
	var s := wrapf(loc.x, 0.0, TAU) / TAU * track.length()
	var keep: Array = []
	for r in route_choices:
		var b := track.branches[int(r) - 1]
		# Fuera: el que debía estar tomando acá (no está en él) y los que se
		# pisan con el camino donde está.
		var here := s > b.s_from and s < b.s_to
		if (here and int(r) != route) or (route > 0 and int(r) != route
				and b.s_from < track.branches[route - 1].s_to and track.branches[route - 1].s_from < b.s_to):
			continue
		keep.append(r)
	if route > 0 and not keep.has(route):
		keep.append(route)
	keep.sort_custom(func(a: int, b: int) -> bool: return track.branches[a - 1].s_from < track.branches[b - 1].s_from)
	if keep != route_choices:
		route_choices = keep
		_track = track.variant(route_choices)


## Desvío lateral del camino actual en ese ángulo.
func path_lateral(angle: float, lane: float) -> float:
	var p: Dictionary = PATHS[path_index]
	# Los valores de PATHS están pensados para una pista de 30 m de mitad útil.
	var k := lane / 30.0
	var lat: float = -lane + p.base * k + p.amp * k * sin(p.waves * angle + _path_phase)
	return clampf(lat, -lane + 2.0, lane - 2.0)


## Decide a qué desvío lateral apuntar.
func _think(angle: float, lateral: float) -> void:
	var track := _track
	var lane := track.half_width - difficulty.edge_margin
	_noise = _rng.randf_range(-1.0, 1.0) * difficulty.steer_noise * 4.0
	_stay_on_route(lateral)

	# Cada vuelta, otro camino (así no van siempre por el mismo lado).
	if race:
		var lap := race.lap_of(rider)
		if lap != _last_lap:
			if _last_lap >= 0:
				_pick_path()
				pick_routes()
			_last_lap = lap

	var target := _line_target(angle, lane) + _noise
	var line_here := target
	_on_line = true
	debug_reason = "linea"

	# Círculo de velocidad próximo.
	var ring := _next_ring(angle)
	if ring:
		var id := ring.get_instance_id()
		if not _ring_choice.has(id):
			_ring_choice[id] = _rng.randf() < difficulty.ring_seek
		var ring_lat := track.lateral_of(ring.position)
		var ring_ahead := _arc_ahead(angle, track.angle_of(ring.position), lateral)
		# Un aro da nitro y un sprint: los mejores se desvían bastante para
		# agarrarlo, si les da el giro para llegar.
		var reach := maxf(difficulty.detour, difficulty.ring_detour)
		var can_reach := absf(ring_lat - lateral) < ring_ahead * RING_REACH_SLOPE + 2.0
		# Los que lo calculan van solo si el desvío (ir y volver a la línea)
		# cuesta menos de lo que da el aro.
		var off := absf(ring_lat - line_here)
		# Ir y volver a la línea (la vuelta, en unos RING_LEG metros). Con
		# nitro de sobra un aro rinde poco (ya va con turbo casi siempre).
		var extra := _ring_detour_cost(ring, lane)
		var value := RING_WORTH if rider.nitro < Rider.TURBO_CHARGE * 1.5 else RING_WORTH * 0.3
		var worth := difficulty.ring_detour <= 0.0 or extra < value
		if _ring_choice[id] and off < reach and can_reach and worth:
			target = ring_lat
			_on_line = false
			debug_reason = "aro"

	# Modo olas: ir a buscar una ola grande que tiene adelante.
	if GameSettings.jump_style == GameSettings.JumpStyle.WAVES:
		var swell := _next_swell(angle, lateral)
		if swell and difficulty.reads_waves:
			# Los mejores eligen por dónde cruzarla: si por su línea la ola
			# llega baja (se apaga cerca de las islas o en las puntas), van al
			# punto alto más cercano, si el desvío vale lo que da el salto.
			var cross := _wave_crossing(swell, angle, lateral, line_here, lane)
			if not is_nan(cross):
				target = cross
				_on_line = false
				debug_reason = "ola"
		elif swell:
			var swell_lat := track.lateral_of(Vector3(swell.center.x, 0.0, swell.center.y))
			if absf(swell_lat - line_here) < difficulty.detour:
				target = swell_lat
				_on_line = false
				debug_reason = "ola"
		var ring_target := _ring_wave_target(angle, lateral)
		if not is_nan(ring_target):
			target = ring_target

	# Largada: por su carril, y de a poco hacia su línea.
	if race and difficulty.keeps_start_lane and race.lap_of(rider) <= 1:
		var t := race.race_time
		if is_nan(_start_lane):
			_start_lane = lateral
		if t < START_LANE_TIME + START_LANE_BLEND:
			target = lerpf(_start_lane, target, smoothstep(START_LANE_TIME, START_LANE_TIME + START_LANE_BLEND, t))
			_on_line = false
			debug_reason = "largada"

	# Llegando a la meta: derecho al punto más cercano de la línea.
	var to_line := _arc_ahead(angle, 0.0, lateral)
	if to_line > 0.0 and to_line < FINISH_APPROACH:
		target = lateral
		_on_line = false
		debug_reason = "meta"

	# Rivales. Adelante: no quedarse en la "sombra" de su derrape (el cono de
	# agua que barre hacia atrás), aunque esa sea la línea más corta: se va al
	# borde del cono que menos lo aparta de donde quería ir, y lo mantiene hasta
	# pasarlo. Cada rival se decide una vez (los mejores casi siempre lo
	# esquivan). Atrás y cerca: derraparle encima (a quien sea, bot o persona).
	var close_range := rider.stats.drift_range + SHADOW_EXTRA
	var tan_cone := tan(deg_to_rad(rider.stats.drift_cone_half_angle))
	_watch_rivals()
	for other in race.racers if race else []:
		if other == rider or other.is_fallen():
			continue
		var id := other.get_instance_id()
		var ahead := _arc_ahead(angle, track.angle_of(other.position), lateral)
		var other_lat := track.lateral_of(other.position)
		var dlat := other_lat - lateral
		# Los que planean ven de lejos que la línea buena ya está ocupada y van
		# por una paralela; más lejos todavía de quien ya los tiró.
		var wary: bool = race.race_time < float(_wary_until.get(id, -1.0))
		var range_back := close_range + difficulty.shadow_look + (WARY_EXTRA if wary else 0.0)
		# Pasándolo, sigue por su paralela hasta dejarlo atrás (si se cierra
		# a mitad de la pasada, le queda justo en el derrape).
		var passed := -PASS_CLEAR if difficulty.shadow_look > 0.0 else 0.0
		# De lejos, solo si lo está alcanzando (ir detrás a la misma velocidad,
		# fuera del alcance del derrape, no tiene riesgo y es la mejor línea).
		var closing := rider.speed - other.speed
		var catching := ahead < close_range or (closing > 0.5 and ahead / closing < SHADOW_PLAN_TIME)
		if ahead > passed and ahead < range_back and (catching or _shadow_side.has(id)):
			if not _shadow_choice.has(id):
				_shadow_choice[id] = wary or _rng.randf() < difficulty.evade_skill
			# El ancho del cono cuando lo alcance (no el de ahora, que de lejos
			# es enorme): una línea paralela, al costado de su derrape.
			var reach := minf(ahead, rider.stats.drift_range)
			if difficulty.shadow_look > 0.0:
				reach = rider.stats.drift_range
			var cone := 0.8 + reach * tan_cone + SHADOW_MARGIN
			if wary:
				cone += WARY_MARGIN
			if _shadow_choice[id] and absf(target - other_lat) < cone:
				var left := other_lat - cone
				var right := other_lat + cone
				if not _shadow_side.has(id):
					var side := -1 if absf(left - target) < absf(right - target) else 1
					if side < 0 and left < -lane:
						side = 1
					elif side > 0 and right > lane:
						side = -1
					_shadow_side[id] = side
				target = other_lat + cone * _shadow_side[id]
				_on_line = false
				debug_reason = "sombra"
			elif not _shadow_choice[id] and ahead < 10.0 and absf(dlat) < 2.5:
				# Sin esquivar la sombra, al menos no chocarlo de atrás.
				target = lateral + (4.0 if dlat <= 0.0 else -4.0)
				_on_line = false
				debug_reason = "atras"
		else:
			_shadow_choice.erase(id)
			_shadow_side.erase(id)
		if ahead < 0.0 and ahead > -6.0 and absf(dlat) < 2.5:
			if rider.speed > rider.stats.drift_min_speed + 1.0 and _rng.randf() < difficulty.aggression:
				_drift_timer = 0.6


	# Rocas: la más cercana que quede en el camino (entre donde está y adonde
	# va) se esquiva por el lado elegido, y se mantiene ese lado hasta pasarla.
	_brake = false
	var nearest: Rock = null
	var nearest_ahead := 1e9
	for rock in course.rocks:
		var id := rock.get_instance_id()
		# Las que esconde un tubo no están.
		if not rock.visible:
			_rock_side.erase(id)
			continue
		var ahead := _arc_ahead(angle, track.angle_of(rock.position), lateral)
		if ahead < -3.0:
			_rock_side.erase(id)
			continue
		if ahead <= 0.0 or ahead > difficulty.look_ahead:
			continue
		# Volando bien por arriba: no hace falta esquivarla.
		if _clears_rock(rock, ahead):
			continue
		var rock_lat := track.lateral_of(rock.position)
		var clearance := rock.radius + 2.6 + difficulty.rock_margin
		var lo := minf(lateral, target) - clearance
		var hi := maxf(lateral, target) + clearance
		var in_path := rock_lat > lo and rock_lat < hi
		if (in_path or _rock_side.has(id)) and ahead < nearest_ahead:
			nearest = rock
			nearest_ahead = ahead
	if nearest:
		var id := nearest.get_instance_id()
		var rock_lat := track.lateral_of(nearest.position)
		var clearance := nearest.radius + 3.0 + difficulty.rock_margin
		if not _rock_side.has(id):
			var left := rock_lat - clearance
			var right := rock_lat + clearance
			# Los que siguen la línea la pasan del lado que menos los aparta de
			# su línea (allá, en la roca); los demás, del lado que tienen más cerca.
			var ref := lateral
			if difficulty.line_skill > 0.0:
				ref = _line_target(track.angle_of(nearest.position), lane)
			var side := -1 if absf(left - ref) < absf(right - ref) else 1
			# Si de ese lado no hay lugar (borde de la pista), el otro.
			if side < 0 and left < -lane:
				side = 1
			elif side > 0 and right > lane:
				side = -1
			_rock_side[id] = side
		target = rock_lat + clearance * _rock_side[id]
		_on_line = false
		debug_reason = "roca"
		# Cerca y todavía no está al costado: aflojar para poder girar más cerrado.
		if nearest_ahead < 14.0 and absf(rock_lat - lateral) < clearance:
			_brake = true

	# Una ola tubo adelante con la boca abierta: ir a meterse (casi siempre).
	var tube_lat := _tube_target(angle)
	if not is_nan(tube_lat):
		target = tube_lat
		_on_line = false
		debug_reason = "tubo"
		_brake = false

	_target_lateral = clampf(target, -lane, lane)


## true si va en el aire y pasa por encima de la roca sin tocarla (los
## que calculan el vuelo; los demás la esquivan igual).
func _clears_rock(rock: Rock, ahead: float) -> bool:
	if not difficulty.reads_landing or rider.grounded or rider.speed < 1.0:
		return false
	var t := ahead / rider.speed
	if t > _simulate_landing(3.0):
		return false
	var g := rider.stats.gravity
	var y := rider.position.y + rider.vertical_speed * t - 0.5 * g * t * t
	return y > rock.position.y + rock.height + 0.6


## Metros de más que hace yendo por el aro y volviendo a su línea (en el
## mundo, así cuenta bien las curvas: un aro por afuera de una curva cerrada
## cuesta mucho más que en una recta).
func _ring_detour_cost(ring: NitroRing, lane: float) -> float:
	return _detour_cost(ring.position, lane)


## Desvío lateral por donde cruzar la ola que viene: NAN si por su línea ya
## la agarra alta (o si ningún punto alto vale el desvío). Mira la ola donde
## va a estar cuando llegue (avanza hacia él) y cuánto la apaga la costa.
func _wave_crossing(swell: Swell, angle: float, lateral: float, line_lat: float, lane: float) -> float:
	var track := _track
	var c := Vector3(swell.center.x, 0.0, swell.center.y)
	var dist := _arc_ahead(angle, track.angle_of(c), lateral)
	if dist <= 0.0:
		return NAN
	var t := dist / maxf(rider.speed + swell.speed, 1.0)
	var meet := angle + rider.speed * t / maxf(track.radius + lateral, 10.0)
	var best := NAN
	var best_cost := INF
	var lat := -lane
	while lat <= lane + 0.01:
		var p := track.position_at(meet, lat)
		var h := _swell_height_then(swell, p, t)
		if absf(lat - line_lat) < WAVE_STEP * 0.5 and h >= WAVE_GOOD_HEIGHT:
			return NAN
		if h >= WAVE_GOOD_HEIGHT:
			var cost := _detour_cost(p, lane)
			if cost < best_cost:
				best_cost = cost
				best = lat
		lat += WAVE_STEP
	if best_cost < WAVE_WORTH:
		return best
	return NAN


## Altura de esa ola en p dentro de t segundos (lo que avanza; la costa la apaga).
func _swell_height_then(swell: Swell, p: Vector3, t: float) -> float:
	var q := Vector2(p.x, p.z)
	return swell.height_at(q - swell.direction * swell.speed * t) * _water.land_fade(q)


## Metros de más que hace pasando por ese punto y volviendo a su línea.
func _detour_cost(point: Vector3, lane: float) -> float:
	var track := _track
	var pa := track.angle_of(point)
	var after := pa + RING_LEG / maxf(track.radius, 10.0)
	var a := Vector2(rider.position.x, rider.position.z)
	var q := Vector2(point.x, point.z)
	var mid3 := track.position_at(pa, _line_target(pa, lane))
	var end3 := track.position_at(after, _line_target(after, lane))
	var mid := Vector2(mid3.x, mid3.z)
	var end := Vector2(end3.x, end3.z)
	return a.distance_to(q) + q.distance_to(end) - a.distance_to(mid) - mid.distance_to(end)


## Se entera cuando un rival lo tira con un derrape (para cuidarse de él).
func _watch_rivals() -> void:
	if _rivals_watched or race == null or race.racers.is_empty():
		return
	_rivals_watched = true
	for other in race.racers:
		if other == rider:
			continue
		var id := other.get_instance_id()
		other.drift_hit.connect(func(victim: Rider) -> void:
			if victim == rider and race:
				_wary_until[id] = race.race_time + WARY_TIME
				_shadow_choice.erase(id)
		)


## Desvío lateral al que va según su habilidad: entre su camino (que cambia
## cada vuelta) y la línea más corta de la pista (RacingLine).
func _line_target(angle: float, lane: float) -> float:
	var base := path_lateral(angle, lane)
	if difficulty.line_skill <= 0.0:
		return base
	var line := RacingLine.for_track(_track, lane).lateral_at(angle)
	return lerpf(base, line, difficulty.line_skill)


## Desvío lateral que va por adentro de la curva que viene (0 si es recta):
## compara el largo de ir por un borde o por el otro en los próximos metros.
func _inside_line(angle: float, lane: float) -> float:
	var track := _track
	var step := 18.0 / maxf(track.radius, 10.0)
	var left := 0.0
	var right := 0.0
	var prev_l := track.position_at(angle, lane)
	var prev_r := track.position_at(angle, -lane)
	for i in range(1, 4):
		var a := angle + step * i
		var l := track.position_at(a, lane)
		var r := track.position_at(a, -lane)
		left += prev_l.distance_to(l)
		right += prev_r.distance_to(r)
		prev_l = l
		prev_r = r
	var bend := (right - left) / maxf(right + left, 0.01)
	# Cuánto se nota la curva (0 = recta, 1 = curva cerrada).
	var amount := clampf(absf(bend) * 12.0, 0.0, 1.0)
	return signf(bend) * lane * 0.85 * amount


## Metros por delante (siguiendo la pista) de un punto en otro ángulo. Negativo = detrás.
func _arc_ahead(from_angle: float, to_angle: float, lateral: float) -> float:
	var d := wrapf(to_angle - from_angle, -PI, PI)
	return d * (_track.radius + lateral)


func _next_ring(angle: float) -> NitroRing:
	var best: NitroRing = null
	var best_d := 1e9
	for ring in course.rings:
		if not ring.visible:
			continue
		var d := _arc_ahead(angle, _track.angle_of(ring.position), 0.0)
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
		if absf(_track.lateral_of(pos)) > _track.half_width:
			continue
		var d := _arc_ahead(angle, _track.angle_of(pos), lateral)
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
		return rw.radius - _track.radius - 0.5
	return NAN


func _clear_ahead(angle: float, lateral: float, distance: float) -> bool:
	for rock in course.rocks:
		var ahead := _arc_ahead(angle, _track.angle_of(rock.position), lateral)
		if ahead > 0.0 and ahead < distance:
			if absf(_track.lateral_of(rock.position) - lateral) < rock.radius + 4.0:
				return false
	return true


## Metros adelante a los que apunta el volante (y para los mejores, cuántos
## segundos de camino, hasta STEER_LOOK_MAX).
const STEER_LOOK := 14.0
const STEER_LOOK_TIME := 1.15
const STEER_LOOK_MAX := 21.0


## Volante hacia un punto de la pista unos metros adelante, en el desvío pedido.
func _steer_towards(angle: float, lateral: float, target_lateral: float) -> float:
	var track := _track
	var look := STEER_LOOK
	if difficulty.reads_landing:
		# Los mejores miran más lejos cuanto más rápido van: empiezan a doblar
		# antes (en el aire se gira la mitad y una curva cerrada no da).
		look = clampf(rider.speed * STEER_LOOK_TIME, STEER_LOOK, STEER_LOOK_MAX)
	var aim_angle := angle + look / maxf(track.radius + lateral, 10.0)
	var aim := track.position_at(aim_angle, target_lateral)
	var to_aim := aim - rider.position
	var desired := atan2(-to_aim.x, -to_aim.z)
	var err := wrapf(desired - rider.heading, -PI, PI)
	return clampf(-err * 2.5, -1.0, 1.0)


# --- En el aire --------------------------------------------------------------

func _air(delta: float, input: RiderInput) -> void:
	var track := _track
	var angle := track.angle_of(rider.position)
	var lateral := track.lateral_of(rider.position)
	# Los mejores siguen mirando en el aire (aros, rocas, rivales): casi la
	# mitad de la carrera va volando.
	if difficulty.reads_landing:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer = difficulty.think_interval
			_think(angle, lateral)
	# En el aire también sigue su línea (más de la mitad del tiempo va volando).
	var aim_lateral := _target_lateral
	if _on_line and difficulty.line_skill > 0.0:
		aim_lateral = _line_target(angle + AIM_DISTANCE / maxf(track.radius + lateral, 10.0), track.half_width - difficulty.edge_margin) + _noise
	input.steer = _steer_towards(angle, lateral, aim_lateral)
	_jump_hold = 0.0

	if not _was_airborne:
		_air_spin = 0.0
		# Con handicap se equivoca menos en los trucos.
		var fail_chance := difficulty.trick_fail_chance * (1.0 - 0.6 * rider.catchup)
		_trick_will_fail = _rng.randf() < fail_chance

	var stats := rider.stats
	var spin := stats.trick_spin_speed
	var full_turn := TAU / spin
	var t_land := _time_to_land()
	if rider.trick_angle > 0.0:
		_air_spin += delta
	# Pop tardío: apenas la ola lo lanzó todavía vale (sale igual de alto).
	if GameSettings.jump_style == GameSettings.JumpStyle.WAVES and rider.pop_ready() and not _pop_tried:
		_pop_tried = true
		if _rng.randf() < difficulty.pop_skill:
			input.jump_pressed = true
	# Turbo en el aire para subir más y tener tiempo para más vueltas.
	if difficulty.saves_turbo_for_waves:
		# Volando no frena: el turbo se tira justo antes de tocar el agua, así
		# está andando todo el tramo hasta la próxima ola.
		if rider.turbo_time <= 0.0 and rider.turbo_charges() >= 1 and rider.vertical_speed < 0.0 \
				and t_land < LAND_TURBO_TIME:
			input.turbo_pressed = true
		# Lo que suman los trucos llega al aterrizar: si con eso (y después
		# de la carga que tira al caer) se pasa del tope, lo perdería. Mejor
		# gastar una carga ahora.
		var landing_nitro := rider.nitro + stats.trick_nitro_rate * rider.nitro_gain_mult() * (_air_spin + t_land)
		if rider.turbo_time <= 0.0 and rider.turbo_charges() >= 1 \
				and landing_nitro - Rider.TURBO_CHARGE > Rider.NITRO_MAX:
			input.turbo_pressed = true
	elif difficulty.uses_turbo and rider.vertical_speed > -2.0:
		var ready := rider.turbo_charges() >= 1 if difficulty.eager_turbo else rider.nitro > maxf(difficulty.turbo_threshold, Rider.TURBO_CHARGE)
		if rider.turbo_time <= 0.0 and ready:
			input.turbo_pressed = true
		if rider.turbo_time > 0.0:
			t_land += 0.5
	if _trick_will_fail:
		input.trick = true
		return
	if rider.trick_releasing:
		# Ya soltó: la tabla vuelve sola a su lugar.
		input.trick = false
		return
	var a := rider.trick_angle
	if a <= 0.0:
		# ¿Le da el tiempo para empezar y completar una vuelta antes de soltar?
		input.trick = t_land > stats.trick_hold_delay + full_turn + difficulty.trick_margin
	else:
		# Cuenta lo completado al soltar: sigue si le da para completar otro
		# tiempo y soltar con margen antes de tocar el agua.
		var u := rider.trick_units_now()
		var to_next: float = (floorf(u + 0.0001) + 1.0 - u) * full_turn
		input.trick = t_land > to_next + difficulty.trick_margin
		# El nitro se carga mientras se mantiene el botón: los mejores no
		# sueltan hasta el último momento seguro (aunque no sume otro tiempo).
		if not input.trick and difficulty.holds_to_trick_end:
			input.trick = t_land > difficulty.trick_margin


## Segundos girando en este salto (el nitro que va a sumar al aterrizar).
var _air_spin: float = 0.0
## Tira el turbo cuando le falta esto para tocar el agua (s).
const LAND_TURBO_TIME := 0.12


## Estimación del tiempo hasta tocar el agua (tiro vertical). Los buenos
## miran el agua donde van a caer (una ola que se levanta adelante los
## alcanza antes).
func _time_to_land() -> float:
	var g := rider.stats.gravity
	var vy := rider.vertical_speed
	var water_y := rider.water_height()
	if difficulty.reads_landing and _water:
		return _simulate_landing()
	return _fall_time(vy, rider.position.y - water_y, g)


## Sigue el vuelo paso a paso como lo mueve el juego (gravedad y el aire fino
## que frena la subida en los saltos altos) contra el agua que se mueve: así
## ven cuánto tiempo tienen de verdad antes de tocar el agua.
func _simulate_landing(max_t: float = 4.0) -> float:
	var stats := rider.stats
	var dt := 1.0 / 30.0
	var span := maxf(stats.air_max_height - stats.air_soft_height, 0.1)
	var y := rider.position.y
	var vy := rider.vertical_speed
	var f := rider.forward() * rider.speed
	var t := 0.0
	while t < max_t:
		t += dt
		var p := rider.position + f * t
		var water_y := _water.height_ahead(p.x, p.z, t)
		var thin := clampf((y - water_y - stats.air_soft_height) / span, 0.0, 1.5)
		if thin > 0.0 and vy > 0.0:
			vy = maxf(vy - (stats.gravity * stats.air_thin_gravity + vy * stats.air_thin_drag) * thin * dt, 0.0)
		vy -= stats.gravity * dt
		y += vy * dt
		if y <= water_y + Rider.BODY_IN_WATER:
			return t
	return max_t


func _fall_time(vy: float, h: float, g: float) -> float:
	var disc := vy * vy + 2.0 * g * maxf(h, 0.0)
	return (vy + sqrt(disc)) / g
