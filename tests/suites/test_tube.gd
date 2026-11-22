extends "res://tests/test_base.gd"
## Ola tubo: cuándo aparece en la carrera, entrar por la boca (varios), el
## equilibrio, caerse (pierde el nitro de adentro), salir con turbo, los
## obstáculos que desaparecen, el aviso del HUD y los bots.


func run() -> void:
	print("Ola tubo:")
	await _test_not_in_time_trial()
	var m := await _open_race()
	_race = m.get_node("RaceManager") as RaceManager
	_course = m.get_node("Course") as Course
	_water = m.get_node("Water") as Water
	_waves = m.get_node("WaveManager") as WaveManager
	_waves.enabled = false
	_water.clear_swells()
	_race.catchup_enabled = false
	_race.skip_countdown()
	await process_frame
	_rider = _race.racers[0]
	_check(_race.tubes != null, "en la carrera está el que decide las olas tubo")
	await _test_rules()
	await _test_wipe_out()
	await _test_two_inside()
	await _test_bot_rides_it()
	await _test_obstacles_hidden()
	await _test_bot_goes_to_mouth()
	await _test_director_spawns()
	m.queue_free()
	await process_frame


func _open_race(config: RaceConfig = null) -> Node:
	var m: Node = load("res://main.tscn").instantiate()
	for child in m.get_children():
		if child is GameSession:
			(child as GameSession).config = config if config else RaceConfig.create(1, 2, 1)
	root.add_child(m)
	await process_frame
	await process_frame
	return m


func _test_not_in_time_trial() -> void:
	var saved_players := GameSettings.player_count
	GameSettings.player_count = 1
	var m := await _open_race(RaceConfig.time_trial())
	var race := m.get_node("RaceManager") as RaceManager
	_check(race.tubes == null, "en la contrarreloj no hay olas tubo")
	m.queue_free()
	await process_frame
	m = await _open_race(RaceConfig.explore())
	race = m.get_node("RaceManager") as RaceManager
	_check(race.tubes == null, "en el modo libre no hay olas tubo (por ahora)")
	m.queue_free()
	await process_frame
	GameSettings.player_count = saved_players


## Mueve a un surfista a un punto de la pista (ángulo, desvío), mirando hacia adelante.
func _place(r: Rider, angle: float, lateral: float) -> void:
	var p := _course.track.position_at(angle, lateral)
	r.position = Vector3(p.x, _water.height_at(p.x, p.z), p.z)
	r.heading = _course.track.heading_at(angle)
	r.rotation.y = r.heading
	r.vertical_speed = 0.0
	r.shove = Vector3.ZERO
	if r.state_machine.current_name != &"riding":
		r.state_machine.transition_to(&"riding")
	r.speed = 10.0
	# Que el progreso de la carrera siga al lugar nuevo (sin contar una vuelta).
	_race._last_angle[r] = _course.track.angle_of(r.global_position)


## Una ola tubo puesta a mano (sin el director), con la boca en `angle`.
func _make_tube(angle: float, lateral: float, time: float, speed: float = 18.0, side: float = 1.0) -> TubeWave:
	var tw := TubeWave.new()
	_race.get_parent().add_child(tw)
	tw.setup(_course, angle, lateral, side, time, speed, null, 30.0)
	tw.age = TubeWave.RISE_TIME
	return tw


func _test_rules() -> void:
	var d := _race.tubes
	# Duración: entre 8 y 12 s, más larga cuanto más atrás.
	var near_t := []
	var far_t := []
	for i in 40:
		near_t.append(d.duration_for(TubeDirector.MIN_GAP))
		far_t.append(d.duration_for(TubeDirector.FULL_GAP + 50.0))
	_check(near_t.min() >= 8.0 and far_t.max() <= 12.0, "el tubo dura entre 8 y 12 s")
	_check(near_t.max() <= 9.01 and far_t.min() >= 10.99, "dura más cuanto más atrás estás (cerca %.1f-%.1f, lejos %.1f-%.1f)" % [near_t.min(), near_t.max(), far_t.min(), far_t.max()])
	_check(
		TubeDirector.speed_for(150.0, 10.0, 13.0) > TubeDirector.speed_for(60.0, 10.0, 13.0),
		"más lejos del primero, más rápido adentro (recupera más)"
	)
	var v := TubeDirector.speed_for(100.0, 10.0, 13.0)
	_check(absf((v - 13.0) * 10.0 - 70.0) < 0.5, "adentro recupera el 70%% de la distancia (%.1f m/s)" % v)
	# Quién la recibe: el último, si está lejos.
	var first := _race.racers[1]
	var last := _race.racers[0]
	_place(first, 1.0, 0.0)
	_place(last, 0.5, 0.0)
	var per_m := TAU / _course.track.length()
	_race._progress[first] = 1.0
	_race._progress[last] = 1.0 - 30.0 * per_m
	_race._progress[_race.racers[2]] = 1.0 - 10.0 * per_m
	_race.race_time = 20.0
	_check(d.candidate() == null, "a 30 m del primero no hay ola")
	_race._progress[last] = 1.0 - 120.0 * per_m
	_check(d.candidate() == last, "el último, a 120 m del primero, la recibe")
	_place(_race.racers[2], 0.4, 0.0)
	_race._progress[_race.racers[2]] = 1.0 - 130.0 * per_m
	_check(d.candidate() == _race.racers[2], "solo el último (no el anteúltimo)")
	_race._progress[_race.racers[2]] = 1.0 - 10.0 * per_m
	# Cerca de la meta no hay lugar.
	_race._progress[first] = _race.config.laps * TAU - 0.05
	_race._progress[_race.racers[2]] = _race.config.laps * TAU - 0.05 - 20.0 * per_m
	_race._progress[last] = _race.config.laps * TAU - 0.05 - 120.0 * per_m
	_check(d.candidate() == null, "si la meta está más cerca que el largo del tubo, no hay ola")
	_race._progress[first] = 1.0
	_race._progress[_race.racers[2]] = 1.0
	_race._progress[last] = 1.0 - 120.0 * per_m
	# Una vez por vuelta.
	d._lap_used[last] = _race.lap_of(last)
	_check(d.candidate() == null, "una sola ola por vuelta")
	d._lap_used.erase(last)
	# Ninguna para el primero ni con todos juntos.
	_race._progress[last] = 1.0
	_check(d.candidate() == null, "con todos juntos no hay ola")
	_race.race_time = 0.0


## Entra, no toca el stick: la ola lo corre hasta que se cae. Pierde el nitro
## que sumó adentro.
func _test_wipe_out() -> void:
	# Los bots quietos (si no, alguno se mete por la boca: es un portal).
	_lock_bots(true)
	var angle := 1.2
	var tw := _make_tube(angle, 4.0, 11.0)
	_place(_rider, angle - 1.0 / _course.track.radius, 4.0)
	_rider.reset_nitro()
	_rider.add_nitro(0.2)
	var nitro_before := _rider.nitro
	var wiped := [false]
	_rider.tube_wiped_out.connect(func(_lip: bool) -> void: wiped[0] = true, CONNECT_ONE_SHOT)
	var max_nitro := 0.0
	var max_danger := 0.0
	var hud := (_main_of(tw).get_node("Views") as SplitScreen).huds[0]
	var warned := false
	var bumps := 0
	for i in int(12.0 * FPS):
		await process_frame
		if _rider.in_tube():
			max_nitro = maxf(max_nitro, _rider.nitro)
			max_danger = maxf(max_danger, _rider.tube_danger)
			if hud.tube_warning.visible:
				warned = true
		if _rider.is_fallen():
			break
	_check(tw.used.has(_rider), "pasar por la boca lo mete al tubo")
	_check(max_nitro > nitro_before + 0.02, "adentro va sumando nitro")
	_check(max_danger > 0.5 and warned, "al perder el equilibrio el borde de la pantalla avisa")
	_check(_rider.is_fallen() and wiped[0], "sin tocar el stick, la ola lo tira")
	_check(absf(_rider.nitro - nitro_before) < 0.001, "al caerse pierde el nitro que sumó adentro (%.2f)" % _rider.nitro)
	_check(not _rider.in_tube() and _rider.tube == null, "al caerse sale del tubo")
	# Sin nadie adentro, la ola se desarma.
	await _wait(TubeWave.ENTRY_WINDOW + TubeWave.COLLAPSE_TIME + 0.3)
	_check(not is_instance_valid(tw), "sin nadie adentro, la ola se desarma")
	_rider.state_machine.transition_to(&"riding")
	_lock_bots(false)


func _lock_bots(locked: bool) -> void:
	for r in _race.racers:
		if not r.is_human:
			r.controls_locked = locked


func _main_of(_n: Node) -> Node:
	return _race.get_parent()


## Dos entran por la boca: van a la misma velocidad y no se chocan.
func _test_two_inside() -> void:
	var angle := 2.0
	var bot := _race.racers[1]
	var tw := _make_tube(angle, -4.0, 3.0, 16.0, -1.0)
	var per_m := 1.0 / _course.track.radius
	_place(_rider, angle - 1.0 * per_m, -4.0)
	_place(bot, angle - 6.0 * per_m, -4.5)
	var both := false
	var same_speed := true
	var min_dist := INF
	for i in int(3.0 * FPS):
		await process_frame
		if _rider.in_tube() and bot.in_tube():
			# (El cuadro en que entra todavía trae su velocidad de antes.)
			if both and _rider.speed != bot.speed:
				same_speed = false
			both = true
			min_dist = minf(min_dist, _rider.position.distance_to(bot.position))
		elif both:
			break
	_check(both and same_speed, "dos pueden entrar por la misma boca y van a la misma velocidad")
	_check(min_dist > TubeWave.BALANCE_REACH * 0.5, "adentro no se chocan (%.1f m)" % min_dist)
	tw.dismiss()
	await _wait(TubeWave.COLLAPSE_TIME + 0.2)
	for r in [_rider, bot]:
		if r.is_fallen():
			r.state_machine.transition_to(&"riding")


## Un bot que no se equivoca aguanta hasta el final y sale con turbo y el nitro lleno.
func _test_bot_rides_it() -> void:
	var angle := 3.0
	var bot := _race.racers[1]
	var ai := bot.controller as AIController
	var saved := ai.difficulty
	ai.difficulty = AIDifficulty.preset(4)
	ai.difficulty.trick_fail_chance = 0.0
	var tw := _make_tube(angle, 3.0, 4.0, 20.0)
	_place(bot, angle - 0.5 / _course.track.radius, 3.0)
	bot.reset_nitro()
	var results := []
	bot.tube_exited.connect(func(ok: bool) -> void: results.append(ok), CONNECT_ONE_SHOT)
	var start_angle := 0.0
	var entered := false
	for i in int(6.0 * FPS):
		await process_frame
		if bot.in_tube() and not entered:
			entered = true
			start_angle = _course.track.angle_of(bot.position)
		if not results.is_empty():
			break
	_check(entered and results == [true], "un bot bueno aguanta el equilibrio hasta el final")
	var moved := wrapf(_course.track.angle_of(bot.position) - start_angle, -PI, PI) * _course.track.length() / TAU
	_check(absf(moved - 20.0 * 4.0) < 12.0, "adentro avanza a la velocidad del tubo (%.0f m en 4 s)" % moved)
	_check(bot.nitro >= Rider.NITRO_MAX - 0.001, "sale con el nitro lleno")
	_check(bot.turbo_time > 0.0 and bot.state_machine.current_name == &"riding", "sale por adelante con turbo")
	ai.difficulty = saved
	await _wait(TubeWave.COLLAPSE_TIME + 0.3)
	_check(not is_instance_valid(tw), "al terminar la ola se desarma")


## Los aros y rocas del tramo desaparecen mientras está la ola, y vuelven después.
func _test_obstacles_hidden() -> void:
	var items: Array[Node3D] = []
	for ring in _course.rings:
		items.append(ring)
	for rock in _course.rocks:
		items.append(rock)
	if items.is_empty():
		_check(false, "el mapa tiene aros o rocas para probar")
		return
	var target: Node3D = items[0]
	var angle := _course.track.angle_of(target.global_position) - 20.0 / _course.track.radius
	var tw := _make_tube(angle, 0.0, 8.0)
	_check(not target.visible, "un aro o roca en el tramo del tubo desaparece")
	tw.dismiss()
	await _wait(TubeWave.COLLAPSE_TIME + 0.3)
	_check(target.visible, "y vuelve cuando la ola se va")


## Un bot con una ola adelante va a la boca y entra.
func _test_bot_goes_to_mouth() -> void:
	var angle := 4.0
	var bot := _race.racers[2]
	var tw := _make_tube(angle, 6.0, 3.0)
	tw.opener = bot
	_place(bot, angle - 45.0 / _course.track.radius, -6.0)
	bot.speed = 12.0
	var entered := false
	for i in int(7.0 * FPS):
		await process_frame
		if tw.used.has(bot) if is_instance_valid(tw) else false:
			entered = true
			break
	_check(entered, "el bot va hacia la boca y entra al tubo")
	if is_instance_valid(tw):
		tw.dismiss()
	await _wait(TubeWave.COLLAPSE_TIME + 0.3)
	if bot.is_fallen():
		bot.state_machine.transition_to(&"riding")


## En carrera, al último lejos del primero le aparece la ola adelante.
func _test_director_spawns() -> void:
	var d := _race.tubes
	d._cooldown = 0.0
	d._lap_used.clear()
	var first := _race.racers[1]
	var last := _race.racers[0]
	var per_m := TAU / _course.track.length()
	_place(last, 0.6, 0.0)
	_race._progress[first] = 0.6 + 140.0 * per_m
	_race._progress[_race.racers[2]] = 0.6 + 100.0 * per_m
	_race._progress[last] = 0.6
	_race.race_time = 30.0
	await process_frame
	await process_frame
	var tw := d.current
	_check(tw != null and is_instance_valid(tw) and tw.opener == last, "al último, lejos del primero, le aparece una ola tubo")
	if tw and is_instance_valid(tw):
		var ahead := tw.s_of(last.position)
		_check(ahead < -15.0 and ahead > -45.0, "la boca aparece adelante (%.0f m)" % -ahead)
		_check(tw.duration >= 8.0 and tw.duration <= 12.0, "dura entre 8 y 12 s (%.1f)" % tw.duration)
		tw.dismiss()
	await _wait(TubeWave.COLLAPSE_TIME + 0.3)
