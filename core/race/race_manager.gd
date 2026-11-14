class_name RaceManager
extends GameSession
## La carrera (y la demo): cuenta regresiva, vueltas, posiciones, handicap,
## llegada y reinicio. Crea los corredores en la largada según su RaceConfig
## (lo común con el modo libre está en GameSession).
##
## El progreso de cada corredor es el ángulo recorrido alrededor de la isla,
## acumulado (si va para atrás, resta). Así no se puede hacer trampa dando la
## vuelta al revés, y el orden de carrera sale de comparar ese número.

signal countdown_tick(value: int)
signal race_started
signal lap_started(rider: Rider, lap: int)
signal racer_finished(rider: Rider, place: int)
signal race_finished(ranking: Array[Rider])

enum State { COUNTDOWN, RACING, FINISHED }

## Un poco antes de la meta, para que la largada cuente como el inicio de la vuelta 1.
const START_ANGLE := -0.03
## Demo: segundos entre que termina una carrera y empieza la siguiente.
const DEMO_RESTART_DELAY := 6.0
## Separación lateral entre corredores en la largada (m).
const GRID_SPACING := 7.0

@export var countdown_time: float = 3.0
@export var course_path: NodePath

var state: State = State.COUNTDOWN
## Handicap para los que van atrás (se puede apagar para comparar).
var catchup_enabled: bool = true
var course: Course
var race_time: float = 0.0
var finish_times: Dictionary = {}

var _progress: Dictionary = {}
var _last_angle: Dictionary = {}
var _wrong_way_time: Dictionary = {}
var _finish_order: Array[Rider] = []
var _countdown: float = 0.0
var _demo_restart_timer: float = -1.0
var _last_tick: int = -1


func _ready() -> void:
	add_to_group("race_manager")
	course = get_node(course_path) as Course
	_setup_input()
	_spawn_racers()
	_countdown = countdown_time
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.race_started()
		audio.connect_race(self)
	for r in racers:
		r.controls_locked = true


func is_demo() -> bool:
	return config.mode == RaceConfig.Mode.DEMO


func config_for_players() -> RaceConfig:
	return RaceConfig.demo() if is_demo() else RaceConfig.from_settings()


func _spawn_racers() -> void:
	var n := config.slots.size()
	for i in n:
		var lateral := (i - (n - 1) * 0.5) * GRID_SPACING
		# La carrera empieza con todos parados en la tabla.
		var rider := spawn_rider(
			config.slots[i], course.track.position_at(START_ANGLE, lateral),
			course.track.heading_at(START_ANGLE), &"riding"
		)
		_progress[rider] = START_ANGLE
		_last_angle[rider] = START_ANGLE
		_wrong_way_time[rider] = 0.0


## Termina la cuenta regresiva ya (para tests).
func skip_countdown() -> void:
	if state == State.COUNTDOWN:
		_start_race()


func _start_race() -> void:
	state = State.RACING
	for r in racers:
		r.controls_locked = false
	countdown_tick.emit(0)
	race_started.emit()


## En pasos fijos (cuenta regresiva, progreso, tiempos): igual con cualquier FPS.
func _physics_process(delta: float) -> void:
	if state == State.COUNTDOWN:
		_countdown -= delta
		var tick := ceili(_countdown)
		if tick != _last_tick and tick > 0:
			_last_tick = tick
			countdown_tick.emit(tick)
		if _countdown <= 0.0:
			_start_race()
		return

	race_time += delta
	for r in racers:
		_update_progress(r, delta)
	_update_catchup()

	if is_demo() and state == State.FINISHED:
		if _demo_restart_timer < 0.0:
			_demo_restart_timer = DEMO_RESTART_DELAY
		_demo_restart_timer -= delta
		if _demo_restart_timer <= 0.0:
			restart()


func _update_progress(r: Rider, delta: float) -> void:
	var angle := course.track.angle_of(r.global_position)
	var d := wrapf(angle - float(_last_angle[r]), -PI, PI)
	_last_angle[r] = angle
	if finished(r):
		return
	var before: float = _progress[r]
	var now := before + d
	_progress[r] = now

	var lap_before := lap_from_progress(before)
	var lap_now := lap_from_progress(now)
	if lap_now > lap_before and lap_now <= config.laps:
		lap_started.emit(r, lap_now)

	# Al revés: mirando contra el sentido de la carrera y avanzando.
	var tangent := course.track.tangent_at(angle)
	if r.speed > 2.0 and r.forward().dot(tangent) < -0.3 and not r.is_fallen():
		_wrong_way_time[r] = float(_wrong_way_time[r]) + delta
	else:
		_wrong_way_time[r] = 0.0

	if now >= config.laps * TAU:
		_finish(r)


## Handicap: cuanto más lejos del primero, más ayuda (hasta un tope).
func _update_catchup() -> void:
	var leader := -1e9
	for r in racers:
		if not finished(r):
			leader = maxf(leader, progress_of(r))
	for r in racers:
		# Solo las personas reciben handicap: los bots corren a su nivel real.
		if finished(r) or leader <= -1e8 or not catchup_enabled or not r.is_human:
			r.catchup = 0.0
			continue
		var gap_m := (leader - progress_of(r)) * course.track.radius
		r.catchup = clampf(gap_m / r.stats.catchup_full_gap, 0.0, 1.0)


func _finish(r: Rider) -> void:
	_finish_order.append(r)
	finish_times[r] = race_time
	r.race_finished = true
	racer_finished.emit(r, _finish_order.size())
	# Termina cuando llegan todas las personas (o todos, si solo hay bots).
	var waiting := humans()
	if waiting.is_empty():
		waiting = racers
	var all_done := true
	for h in waiting:
		if not finished(h):
			all_done = false
	if all_done and state != State.FINISHED:
		state = State.FINISHED
		race_finished.emit(ranking())


func lap_from_progress(p: float) -> int:
	return int(floor(p / TAU)) + 1


## Vuelta actual (1..laps).
func lap_of(r: Rider) -> int:
	if finished(r):
		return config.laps
	return clampi(lap_from_progress(_progress.get(r, 0.0)), 1, config.laps)


func progress_of(r: Rider) -> float:
	return _progress.get(r, 0.0)


func finished(r: Rider) -> bool:
	return r in _finish_order


## Orden de carrera: primero los que llegaron (en orden), después por progreso.
func ranking() -> Array[Rider]:
	var result: Array[Rider] = _finish_order.duplicate()
	var rest: Array[Rider] = []
	for r in racers:
		if not finished(r):
			rest.append(r)
	rest.sort_custom(func(a: Rider, b: Rider) -> bool: return progress_of(a) > progress_of(b))
	result.append_array(rest)
	return result


func place_of(r: Rider) -> int:
	return ranking().find(r) + 1


func is_wrong_way(r: Rider) -> bool:
	return float(_wrong_way_time.get(r, 0.0)) > 1.0


func _input(event: InputEvent) -> void:
	# En la demo, cualquier tecla, botón o toque vuelve al menú.
	if is_demo() and is_any_press(event):
		get_viewport().set_input_as_handled()
		back_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		if state == State.FINISHED:
			restart()
		return
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if InputMap.has_action(p + "start") and event.is_action_pressed(p + "start") and state == State.FINISHED:
			restart()
			return
	super(event)
