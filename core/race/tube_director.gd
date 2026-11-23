class_name TubeDirector
extends Node
## Carrera: cuándo aparece una ola tubo (ver TubeWave). Es el handicap
## "elegante": al que va último y lejos del primero le sale una ola grande
## adelante; si entra al tubo, va más rápido, carga nitro y sale con turbo.
## Como la ola es un portal, los que vienen cerca también pueden entrar.
##
## Reglas:
##   - solo al último (de los que no llegaron), y si está lejos del primero;
##   - como mucho una vez por vuelta para cada uno;
##   - nunca en la largada, ni si la meta está más cerca que el largo del tubo;
##   - una ola a la vez.
## No está en la contrarreloj. En el modo libre no aparece sola (`automatic`
## en false), solo con la tecla de prueba (Y).

## Distancia mínima al primero para que aparezca (m).
const MIN_GAP := 55.0
## Desde esta distancia el tubo dura lo máximo (m).
const FULL_GAP := 200.0
## Duración: entre estos segundos según qué tan atrás esté (más lejos, más
## largo), con algo de azar, y nunca fuera de este rango.
const MIN_TIME := 8.0
const MAX_TIME := 12.0
const TIME_JITTER := 1.0
## Parte de la distancia con el primero que se recupera adentro del tubo.
const RECOVER := 0.7
## Velocidad adentro: entre estas veces la velocidad máxima.
const MIN_SPEED_MULT := 1.3
const MAX_SPEED_MULT := 2.0
## Segundos de carrera antes de que pueda aparecer la primera.
const START_GRACE := 10.0
## Segundos entre que termina una ola y puede aparecer otra.
const COOLDOWN := 4.0
## A cuántos metros adelante del último aparece la boca (según su velocidad).
## (Aparece más adelante que lo que tarda en nacer: se la ve venir y formarse.)
const AHEAD_TIME := 3.4
const AHEAD_MIN := 38.0
const AHEAD_MAX := 70.0
## La línea del tubo queda a esta distancia del borde de la pista, como mínimo (m).
const EDGE_MARGIN := 7.0

var race: RaceManager
## Si aparece sola (en carrera). En el modo libre solo con la tecla de prueba.
var automatic: bool = true
## La ola que está ahora (null si no hay).
var current: TubeWave = null
## Vuelta en la que cada uno ya tuvo su ola (rider -> vuelta).
var _lap_used: Dictionary = {}
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_race: RaceManager) -> void:
	race = p_race
	_rng.randomize()


func _physics_process(delta: float) -> void:
	if race == null or not automatic or race.state != RaceManager.State.RACING:
		return
	if current != null and is_instance_valid(current) and not current.done:
		return
	current = null
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0 or race.race_time < START_GRACE:
		return
	var who := candidate()
	if who != null:
		spawn_for(who)


## El que podría recibir una ola ahora (null si nadie): el último, lejos del primero.
func candidate() -> Rider:
	var ranking := race.ranking()
	var leader: Rider = null
	var last: Rider = null
	for r in ranking:
		if race.finished(r):
			continue
		if leader == null:
			leader = r
		last = r
	if last == null or last == leader:
		return null
	if gap_of(last) < MIN_GAP:
		return null
	if int(_lap_used.get(last, -1)) == race.lap_of(last):
		return null
	if last.is_fallen() or last.in_tube() or not last.grounded or last.state_machine.current_name != &"riding":
		return null
	if last.speed < 5.0:
		return null
	if remaining_of(last) < needed_length(last):
		return null
	return last


## Metros entre el primero (de los que no llegaron) y este.
func gap_of(r: Rider) -> float:
	var lead := -INF
	for o in race.racers:
		if not race.finished(o):
			lead = maxf(lead, race.progress_of(o))
	return (lead - race.progress_of(r)) / TAU * race.course.track.length()


## Metros que le faltan para llegar a la meta.
func remaining_of(r: Rider) -> float:
	return (race.config.laps * TAU - race.progress_of(r)) / TAU * race.course.track.length()


## Duración del tubo según la distancia al primero.
func duration_for(gap: float) -> float:
	var k := clampf(inverse_lerp(MIN_GAP, FULL_GAP, gap), 0.0, 1.0)
	var t := lerpf(MIN_TIME, MAX_TIME, k) + _rng.randf_range(-TIME_JITTER, TIME_JITTER)
	return clampf(t, MIN_TIME, MAX_TIME)


## Velocidad adentro: la del primero más lo justo para recuperar buena parte
## de la distancia en ese tiempo.
static func speed_for(gap: float, time: float, max_speed: float) -> float:
	var v := max_speed + RECOVER * gap / maxf(time, 1.0)
	return clampf(v, max_speed * MIN_SPEED_MULT, max_speed * MAX_SPEED_MULT)


func _ahead_of(r: Rider) -> float:
	return clampf(r.speed * AHEAD_TIME, AHEAD_MIN, AHEAD_MAX)


## Metros de pista que necesita el tubo (desde donde está el surfista).
func needed_length(r: Rider) -> float:
	var v := speed_for(FULL_GAP, MAX_TIME, r.stats.max_speed)
	return _ahead_of(r) + TubeWave.OPEN_LENGTH + v * (MAX_TIME + TubeWave.ENTRY_WINDOW) + 40.0


## Tecla de prueba: una ola ya mismo adelante de `r` (como si fuera 120 m atrás).
## Si hay una, la saca primero.
func spawn_test(r: Rider) -> TubeWave:
	if current != null and is_instance_valid(current):
		current.dismiss()
		current.queue_free()
		current = null
	if r.is_fallen() or r.in_tube():
		return null
	return spawn_for(r, 120.0)


## Hace aparecer una ola adelante de `r`. Devuelve la ola (o null si no hay lugar).
## `forced_gap`: distancia al primero a usar (si no, la de verdad).
func spawn_for(r: Rider, forced_gap: float = -1.0) -> TubeWave:
	var track := race.course.track
	var gap := gap_of(r) if forced_gap < 0.0 else forced_gap
	var time := duration_for(gap)
	var speed := speed_for(gap, time, r.stats.max_speed)
	var ahead := _ahead_of(r)
	var loc := track.locate(r.position)
	var mouth := loc.x + ahead / track.length() * TAU
	var length := TubeWave.OPEN_LENGTH + speed * (time + TubeWave.ENTRY_WINDOW) + TubeWave.AHEAD_START
	var lane := pick_lateral(mouth, 0.0, length)
	if is_nan(lane):
		# No hay una línea libre (tierra en el medio): se prueba más adelante.
		_cooldown = 1.0
		return null
	_lap_used[r] = race.lap_of(r)
	var wave := TubeWave.new()
	wave.name = "TubeWave"
	race.get_parent().add_child(wave)
	# La pared hacia el borde más cercano: el lado abierto mira al medio de la pista.
	var side := 1.0 if lane >= 0.0 else -1.0
	# Cuánto puede ir y venir a lo ancho sin pisar tierra ni salirse.
	var reach := pick_sway(mouth, lane, length)
	wave.setup(race.course, mouth, lane, side, time, speed, r, ahead / maxf(r.speed, 4.0) + TubeWave.SWAY_PERIOD, reach)
	wave.finished.connect(func() -> void: _cooldown = COOLDOWN)
	current = wave
	return wave


## Cuánto se puede mover la ola a cada lado de `lane` (m) con todo el tubo libre.
func pick_sway(mouth: float, lane: float, length: float) -> float:
	var track := race.course.track
	var limit := maxf(track.half_width - EDGE_MARGIN, 0.0)
	var water := GameSession.find_in_scene(race, "water") as Water
	var reach := minf(limit - lane, limit + lane)
	while reach > 0.5:
		var ok := true
		for lat in [lane - reach, lane - reach * 0.5, lane + reach * 0.5, lane + reach]:
			if not _clear(track, water, mouth, lat, length):
				ok = false
				break
		if ok:
			return reach
		reach -= 3.0
	return 0.0


## Línea del tubo: lo más cerca posible de donde va el surfista, dentro de la
## pista y sin pasar por tierra en todo el largo. NAN si no hay ninguna.
func pick_lateral(mouth: float, near: float, length: float) -> float:
	var track := race.course.track
	var limit := maxf(track.half_width - EDGE_MARGIN, 0.0)
	var water := GameSession.find_in_scene(race, "water") as Water
	var start := clampf(near, -limit, limit)
	var options: Array[float] = [start]
	for k in range(1, 9):
		for sgn in [-1.0, 1.0]:
			var lat: float = start + sgn * k * 3.0
			if absf(lat) <= limit:
				options.append(lat)
	for lat in options:
		if _clear(track, water, mouth, lat, length):
			return lat
	return NAN


## true si a lo largo del tubo (con su ancho) no hay tierra y no se sale de la
## pista (el recorrido del tubo está suavizado: en las curvas se corre).
func _clear(track: TrackSpace, water: Water, mouth: float, lat: float, length: float) -> bool:
	var side := 1.0 if lat >= 0.0 else -1.0
	var pts := TubeWave.make_spine(track, mouth, lat, length)
	var dirs := TubeWave.spine_wall_dirs(track, mouth, lat, side, pts)
	var limit := track.half_width - 3.0
	for i in range(0, pts.size(), 2):
		var p := pts[i]
		if absf(track.lateral_of(p)) > limit:
			return false
		for off in [-6.0, 0.0, 4.5]:
			var q: Vector3 = p + dirs[i] * off
			if water and water.land_fade(Vector2(q.x, q.z)) < 0.95:
				return false
	return true
