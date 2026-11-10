class_name RaceManager
extends Node
## Maneja la carrera: crea los corredores según RaceConfig, cuenta regresiva,
## vueltas, posiciones, llegada y reinicio. Es un nodo de la escena de carrera
## (no un autoload): reiniciar es recargar la escena.
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

const RIDER_SCENE := preload("res://core/rider/rider.tscn")
## Un poco antes de la meta, para que la largada cuente como el inicio de la vuelta 1.
const START_ANGLE := -0.03
## Separación lateral entre corredores en la largada (m).
const GRID_SPACING := 7.0

@export var config: RaceConfig
@export var countdown_time: float = 3.0
@export var course_path: NodePath
@export var riders_path: NodePath

var state: State = State.COUNTDOWN
var racers: Array[Rider] = []
var course: Course
var race_time: float = 0.0
var finish_times: Dictionary = {}

var _progress: Dictionary = {}
var _last_angle: Dictionary = {}
var _wrong_way_time: Dictionary = {}
var _finish_order: Array[Rider] = []
var _countdown: float = 0.0
var _last_tick: int = -1


func _ready() -> void:
	add_to_group("race_manager")
	GameSettings.load_settings()
	if config == null:
		config = RaceConfig.from_settings()
	course = get_node(course_path) as Course

	var humans := 0
	for slot in config.slots:
		if slot.kind == RacerSlot.Kind.HUMAN:
			InputSetup.ensure_player_actions(slot.player_index)
			humans += 1
	InputSetup.apply_keyboard_layout(humans)

	_spawn_racers()
	_countdown = countdown_time
	for r in racers:
		r.controls_locked = true


func _spawn_racers() -> void:
	var parent := get_node_or_null(riders_path)
	if parent == null:
		parent = self
	var n := config.slots.size()
	for i in n:
		var slot := config.slots[i]
		var rider: Rider = RIDER_SCENE.instantiate()
		rider.name = slot.display_name
		rider.player_index = slot.player_index
		rider.display_name = slot.display_name
		rider.is_human = slot.kind == RacerSlot.Kind.HUMAN
		var visual := rider.get_node("Visual") as RiderVisual
		visual.character = slot.character
		if slot.kind == RacerSlot.Kind.BOT:
			# El bot reemplaza al control de mando/teclado.
			var old := rider.get_node("Controller")
			rider.remove_child(old)
			old.free()
			var ai := AIController.new()
			ai.name = "Controller"
			ai.difficulty = slot.difficulty
			rider.add_child(ai)
		var lateral := (i - (n - 1) * 0.5) * GRID_SPACING
		rider.position = course.track.position_at(START_ANGLE, lateral)
		rider.rotation.y = course.track.heading_at(START_ANGLE)
		parent.add_child(rider)
		racers.append(rider)
		_progress[rider] = START_ANGLE
		_last_angle[rider] = START_ANGLE
		_wrong_way_time[rider] = 0.0


func humans() -> Array[Rider]:
	var result: Array[Rider] = []
	for r in racers:
		if r.is_human:
			result.append(r)
	return result


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


func _process(delta: float) -> void:
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


func _finish(r: Rider) -> void:
	_finish_order.append(r)
	finish_times[r] = race_time
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


func restart() -> void:
	get_tree().reload_current_scene()


func back_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/menus/character_select.tscn")


func set_player_count(count: int) -> void:
	count = clampi(count, 1, 2)
	if count == GameSettings.player_count:
		return
	GameSettings.player_count = count
	GameSettings.save_settings()
	restart()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1:
				set_player_count(1)
			KEY_2:
				set_player_count(2)
			KEY_R:
				if state == State.FINISHED:
					restart()
			KEY_C, KEY_ESCAPE:
				back_to_menu()
		return
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if not InputMap.has_action(p + "start"):
			continue
		if event.is_action_pressed(p + "start") and state == State.FINISHED:
			restart()
		elif event.is_action_pressed(p + "select"):
			set_player_count(2 if GameSettings.player_count == 1 else 1)
