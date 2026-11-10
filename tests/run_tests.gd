extends SceneTree
## Tests automáticos (sin pantalla). Se corren en GitHub Actions con:
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd
## Simulan pulsaciones de botones y revisan que el Rider se comporte bien.

const FPS := 60

var _failures: Array[String] = []
var _checks: int = 0
var _tricks_landed: int = 0
var _main: Node
var _rider: Rider
var _water: Water
var _waves: WaveManager
var _race: RaceManager
var _course: Course
var _pop_prompt_seen: bool = false
var _watch_camera: bool = false
var _camera_lost: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# En modo --script el autoload puede no estar: se crea a mano.
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	GameSettings.load_settings()
	GameSettings.player_count = 1
	GameSettings.bot_count = 0
	_check(GameSettings.auto_forward, "por defecto el avance es automático")
	# Los tests de movimiento usan el modo manual (W acelera); el automático
	# se prueba aparte.
	GameSettings.auto_forward = false
	_check(
		GameSettings.jump_style == GameSettings.JumpStyle.WAVES,
		"por defecto el salto es de olas (saltito + pop)"
	)
	_check(
		GameSettings.wave_mode == GameSettings.WaveMode.SURGES,
		"por defecto las olas son grandes que aparecen solas"
	)
	# Los tests de salto libre van primero; el modo olas se prueba aparte.
	GameSettings.jump_style = GameSettings.JumpStyle.FREE
	_test_avatar()
	await _test_menu()
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_race = _main.get_node("RaceManager") as RaceManager
	_course = _main.get_node("Course") as Course
	_water = _main.get_node("Water") as Water
	_waves = _main.get_node("WaveManager") as WaveManager
	_check(
		_race != null and _course != null and _water != null and _waves != null,
		"existen RaceManager, Course, Water y WaveManager"
	)
	if _race == null or _race.racers.is_empty():
		_finish()
		return
	_rider = _race.racers[0]
	# Sin olas grandes al azar durante los tests de movimiento.
	_waves.enabled = false
	_water.clear_swells()
	_rider.trick_landed.connect(func(_spins: int) -> void: _tricks_landed += 1)

	_test_pad_layouts()
	await _test_race_start()

	# Las mecánicas se prueban lejos del circuito, sin obstáculos.
	_course.hazards_enabled = false
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	await _test_get_up()
	await _test_throttle_and_steer()
	await _test_jump_and_tricks()
	await _test_drift()
	await _test_swells()
	await _test_wave_jump()
	await _test_constant_wave()
	await _test_course()
	await _test_turbo_and_wrong_way()
	await _test_laps()
	await _test_music()
	await _test_split_screen()
	_test_bot_paths()
	await _test_bot_race()
	await _test_demo()
	_finish()


func _test_demo() -> void:
	print("Demo (menú sin tocar nada):")
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	var started := [false]
	menu.start_requested.connect(func() -> void: started[0] = true)
	root.add_child(menu)
	await _wait(9.0)
	_check(not started[0], "a los 9 s sin tocar nada todavía no arranca")
	await _press(&"p1_down")
	await _wait(9.0)
	_check(not started[0], "tocar algo reinicia la espera")
	await _wait(1.5)
	_check(started[0] and GameSettings.demo_mode, "a los 10 s sin tocar nada arranca la demo")
	menu.queue_free()
	await process_frame

	var demo: Node = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	var race := demo.get_node("RaceManager") as RaceManager
	var split := demo.get_node("Views") as SplitScreen
	_check(race.racers.size() == 4, "la demo tiene 4 corredores")
	_check(race.humans().is_empty(), "son bots")
	var hard := true
	for r in race.racers:
		var ai := r.controller as AIController
		if ai == null or ai.difficulty.display_name != "Difícil":
			hard = false
	_check(hard, "en la dificultad máxima")
	_check(split.views.size() == 4, "con la pantalla en 4 (una vista por bot)")
	_check(split.get_child(0) is GridContainer, "en grilla de 2x2")
	var weights: Array[float] = []
	for r in race.racers:
		weights.append((r.get_node("Visual") as RiderVisual).character.weight)
	var spread := true
	for i in weights.size():
		for j in i:
			if absf(weights[i] - weights[j]) < 0.08:
				spread = false
	_check(spread, "los bots tienen pesos distintos %s" % str(weights))
	race.skip_countdown()
	await _wait(8.0)
	var moving := true
	for r in race.racers:
		if race.progress_of(r) < 0.3:
			moving = false
	_check(moving, "los bots arrancan solos")
	GameSettings.demo_mode = false
	demo.queue_free()
	await process_frame


func _test_avatar() -> void:
	print("Personaje:")
	var parts := AvatarCore.get_avatar(0.0)
	_check(parts.size() == 12, "el personaje tiene 12 piezas (%d)" % parts.size())
	_check(AvatarCore.stage_name(0.0) == "Musculoso", "t=0 es Musculoso")
	_check(AvatarCore.stage_name(1.0) == "Cervecero", "t=1 es Cervecero")
	_check(AvatarCore.stage_name(0.45) == "Delgado", "t=0.45 es Delgado")
	var fat := AvatarCore.get_avatar(1.0)
	var delt_hidden := false
	var belly_big := false
	for p in fat:
		var r: Vector3 = p.radii
		if p.id == "delt_L" and minf(r.x, minf(r.y, r.z)) < 0.05:
			delt_hidden = true
		if p.id == "belly" and r.z > 0.3:
			belly_big = true
	_check(delt_hidden, "Cervecero: los hombros desaparecen")
	_check(belly_big, "Cervecero: panza grande")
	var green := AvatarCore.get_avatar(0.5, CharacterData.SKIN_COLORS[5])
	_check(green[0].color == CharacterData.SKIN_COLORS[5], "se puede cambiar el color de piel")


func _test_menu() -> void:
	print("Menú de personaje:")
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	var started := [false]
	menu.start_requested.connect(func() -> void: started[0] = true)
	root.add_child(menu)
	await process_frame
	await process_frame
	var data := GameSettings.character_for(0)
	var w := data.weight
	await _press(&"p1_right")
	_check(data.weight > w, "derecha cambia el peso (%.2f -> %.2f)" % [w, data.weight])
	var skin := data.skin_index
	await _press(&"p1_down")
	await _press(&"p1_right")
	_check(data.skin_index != skin, "abajo y derecha cambian la piel")
	var avatar := menu._panels[0].avatar as Avatar
	var head := avatar.get_node("head") as MeshInstance3D
	var mat := head.material_override as StandardMaterial3D
	_check(mat.albedo_color == data.skin_color(), "el personaje del menú muestra la piel elegida")
	# Fila "Olas" (la última del jugador 1): cambia el modo de olas.
	for i in 5:
		await _press(&"p1_down")
	var mode_before := GameSettings.wave_mode
	await _press(&"p1_right")
	_check(GameSettings.wave_mode != mode_before, "en el menú, la fila Olas cambia el modo de olas")
	await _press(&"p1_right")
	_check(GameSettings.wave_mode == mode_before, "y vuelve al anterior")
	_check(not started[0], "todavía no empieza")
	await _press(&"p1_a")
	_check(started[0], "ESPACIO / A: listo y empieza la carrera")
	menu.queue_free()
	await process_frame


func _test_wave_jump() -> void:
	print("Salto de olas (saltito y pop):")
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	_water.clear_swells()
	_teleport(Vector3(400.0, 0.0, 900.0))
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	_set_action(&"p1_up", true)
	await _wait(2.0)
	await _press(&"p1_a")
	_check(_state() == &"airborne", "en agua plana, A hace un saltito")
	var hop := await _measure_air()
	_check(hop.x < 0.8, "el saltito es bajo (%.2f m)" % hop.x)
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.5)

	# Mantener A en el saltito no hace truco (así nadie se cae por no llegar).
	_set_action(&"p1_a", true)
	var spun := false
	for i in int(1.2 * FPS):
		if _rider.trick_angle > 0.0:
			spun = true
		await process_frame
	_set_action(&"p1_a", false)
	await _wait(0.3)
	_check(not spun, "en el saltito no se puede hacer truco")
	_check(not _rider.is_fallen(), "mantener A en el saltito no te tira")
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.5)

	var plain := await _ride_into_swell(false, Vector3(800.0, 0.0, 900.0))
	var popped := await _ride_into_swell(true, Vector3(1200.0, 0.0, 900.0))
	_check(plain > 0.5, "la ola lanza al aire (%.1f m)" % plain)
	_check(_pop_prompt_seen, "en la cresta aparece el botón del pop en pantalla")
	_check(
		popped > plain * 1.3,
		"A al subir la ola (pop) lanza mucho más alto (%.1f m contra %.1f m)" % [popped, plain]
	)
	_water.clear_swells()
	GameSettings.jump_style = GameSettings.JumpStyle.FREE


func _test_constant_wave() -> void:
	print("Ola constante a la izquierda:")
	# La fórmula de las derivadas coincide con la altura (diferencias finitas).
	var rw := RingWave.new()
	rw.settle()
	rw.phase = 0.7
	var grad_ok := true
	for p in [Vector2(94.0, 3.0), Vector2(-60.0, 70.0), Vector2(20.0, -97.0), Vector2(5.0, 91.5)]:
		var e := 0.01
		var num := Vector2(
			(rw.height_at(p + Vector2(e, 0.0)) - rw.height_at(p - Vector2(e, 0.0))) / (2.0 * e),
			(rw.height_at(p + Vector2(0.0, e)) - rw.height_at(p - Vector2(0.0, e))) / (2.0 * e)
		)
		if num.distance_to(rw.gradient_at(p)) > 0.01:
			grad_ok = false
			print("    gradiente %s: %s contra %s" % [p, num, rw.gradient_at(p)])
	_check(grad_ok, "la pendiente de la ola constante coincide con su altura")

	_waves.set_mode(GameSettings.WaveMode.CONSTANT_LEFT)
	_check(_water.ring_wave != null, "modo constante: hay una ola constante")
	_water.ring_wave.settle()
	var track := _course.track
	var angle := 2.0
	var pos := track.position_at(angle)
	_teleport(pos)
	_rider.heading = track.heading_at(angle)
	var left := -_rider.right()
	var lat := _water.ring_wave.radius - track.radius
	var on_left := _water.swell_height_at(pos.x + left.x * lat, pos.z + left.z * lat)
	var on_right := _water.swell_height_at(pos.x - left.x * lat, pos.z - left.z * lat)
	var at_center := _water.swell_height_at(pos.x, pos.z)
	_check(
		on_left > 1.5 and on_right < 0.05 and at_center < 0.5,
		"la ola está a la izquierda del que corre (izq %.2f m, centro %.2f m, der %.2f m)"
		% [on_left, at_center, on_right]
	)
	var inside := lat > 0.0 and lat < track.half_width
	_check(inside, "la cresta está dentro de la pista, del lado de afuera (%.1f m)" % lat)

	_waves.enabled = true
	await _wait(3.0)
	_check(_water.swells.is_empty(), "en modo constante no aparecen otras olas grandes")
	_waves.enabled = false

	# Los picos vienen de frente: andar por la cresta lo lanza al aire.
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var start_angle := 2.5
	_teleport(track.position_at(start_angle, lat - 0.5))
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	_set_action(&"p1_up", true)
	var launched := false
	var prompt := false
	var max_height := 0.0
	for i in int(10.0 * FPS):
		# Sigue la curva de la cresta.
		if _rider.grounded:
			_rider.heading = track.heading_at(track.angle_of(_rider.position))
		if _rider.pop_ready():
			prompt = true
		if _state() == &"airborne":
			launched = true
			max_height = maxf(max_height, _rider.global_position.y - _water_height_here())
		elif launched:
			break
		await process_frame
	_set_action(&"p1_up", false)
	_check(launched, "andando por la ola constante, un pico lo lanza al aire")
	_check(prompt, "en la ola constante también aparece el botón del pop")
	_check(max_height > 0.5, "salta alto (%.1f m)" % max_height)
	await _wait_until_state(&"riding", 3.0)
	await _wait(0.5)

	# El bot va a la cresta a buscar los picos.
	var ai := AIController.new()
	ai.course = _course
	ai._water = _water
	ai.difficulty = AIDifficulty.preset(2)
	ai.difficulty.wave_seek = 1.0
	var bot_targets := 0
	for i in 40:
		var t := ai._ring_wave_target(i * 0.15, 0.0)
		if not is_nan(t) and absf(t - lat) < 1.5:
			bot_targets += 1
	_check(bot_targets > 5, "el bot va a la cresta a usar los picos (%d de 40)" % bot_targets)
	ai.free()

	_waves.set_mode(GameSettings.WaveMode.SURGES)
	_check(_water.ring_wave == null, "modo olas grandes: sin ola constante")
	GameSettings.jump_style = GameSettings.JumpStyle.FREE


## Anda hacia una ola grande y devuelve la altura máxima del salto.
## Con press = true, aprieta A mientras sube la ola (pop).
func _ride_into_swell(press: bool, at: Vector3) -> float:
	_water.clear_swells()
	_teleport(at)
	_rider.heading = 0.0
	await _wait(1.5)
	var s := Swell.new()
	var f := _rider.forward()
	var ahead := _rider.global_position + f * 25.0
	s.center = Vector2(ahead.x, ahead.z)
	s.direction = -Vector2(f.x, f.z)
	s.speed = 0.0
	s.max_amplitude = 3.0
	s.width = 5.5
	s.half_length = 20.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	_water.add_swell(s)
	var pressed := false
	var release_next := false
	var max_height := 0.0
	var was_airborne := false
	var hud := (_main.get_node("Views") as SplitScreen).huds[0]
	for i in int(5.0 * FPS):
		if hud._pop_label.visible:
			_pop_prompt_seen = true
		if release_next:
			_set_action(&"p1_a", false)
			release_next = false
		if press and not pressed and _rider.grounded and _rider.vertical_speed > 2.5:
			_set_action(&"p1_a", true)
			pressed = true
			release_next = true
		if _state() == &"airborne":
			was_airborne = true
			max_height = maxf(max_height, _rider.global_position.y - _water_height_here())
		elif was_airborne:
			break
		await process_frame
	_set_action(&"p1_a", false)
	await _wait(0.5)
	return max_height


func _test_bot_paths() -> void:
	print("Caminos de los bots:")
	var ai := AIController.new()
	var values: Array[float] = []
	for i in AIController.PATHS.size():
		ai.path_index = i
		values.append(ai.path_lateral(1.0, 30.0))
	var distinct := 0
	for i in values.size():
		var unique := true
		for j in i:
			if absf(values[i] - values[j]) < 1.0:
				unique = false
		if unique:
			distinct += 1
	_check(AIController.PATHS.size() == 5, "hay 5 caminos")
	_check(distinct >= 4, "los caminos van por lugares distintos (%d distintos)" % distinct)
	ai.free()


func _test_bot_race() -> void:
	print("Carrera de bots (Fácil, Normal y Difícil):")
	var config := RaceConfig.new()
	config.laps = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for level in 3:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = AIDifficulty.NAMES[level]
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	# Los bots juegan con el salto de olas (por defecto).
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var main3: Node = load("res://main.tscn").instantiate()
	var race := main3.get_node("RaceManager") as RaceManager
	race.config = config
	# Sin handicap, para comparar las dificultades entre sí (con handicap
	# llegan casi juntos y el orden es casi azar).
	race.catchup_enabled = false
	root.add_child(main3)
	await process_frame
	await process_frame
	var falls := {}
	var tricks := {}
	var crashes := {}
	var failed := {}
	var hits := {}
	var air := {}
	for r in race.racers:
		falls[r] = 0
		tricks[r] = 0
		crashes[r] = 0
		failed[r] = 0
		hits[r] = 0
		air[r] = 0.0
		r.fell.connect(func() -> void: falls[r] += 1)
		r.trick_landed.connect(func(_s: int) -> void: tricks[r] += 1)
		r.crashed.connect(func() -> void: crashes[r] += 1)
		r.trick_failed.connect(func() -> void: failed[r] += 1)
		r.drift_hit.connect(func(_v: Rider) -> void: hits[r] += 1)
	_check(race.racers.size() == 3 and not race.racers[0].is_human, "3 bots en la carrera")
	_check(RaceConfig.new().laps == 5, "las carreras son de 5 vueltas")
	race.skip_countdown()

	var max_seconds := 300.0
	var frames := 0
	var stood_up_by := -1.0
	while race.state != RaceManager.State.FINISHED and frames < int(max_seconds * FPS):
		await process_frame
		frames += 1
		if stood_up_by < 0.0 and not race.racers[0].is_fallen():
			stood_up_by = (frames - 1) / float(FPS)
		for r in race.racers:
			if not r.grounded:
				air[r] += 1.0 / FPS
	var t := frames / float(FPS)
	_check(stood_up_by == 0.0, "los bots largan parados en la tabla")
	_check(race.state == RaceManager.State.FINISHED, "los bots terminan la carrera (%.0f s)" % t)
	for r in race.ranking():
		var time_text := "no llegó"
		if race.finish_times.has(r):
			time_text = "%.1f s" % race.finish_times[r]
		print(
			(
				"        %dº %-8s %-9s caídas: %d (choques %d, trucos fallidos %d)"
				+ "  trucos: %d  derribó: %d  aire: %.1f s"
			)
			% [
				race.place_of(r), r.display_name, time_text, falls[r], crashes[r], failed[r],
				tricks[r], hits[r], air[r]
			]
		)
	var easy: Rider = race.racers[0]
	var hard: Rider = race.racers[2]
	if race.finish_times.has(easy) and race.finish_times.has(hard):
		_check(
			race.finish_times[hard] < race.finish_times[easy],
			"Difícil le gana a Fácil"
		)
	var total_tricks := 0
	for r in tricks:
		total_tricks += tricks[r]
	_check(total_tricks > 0, "los bots hacen trucos (%d)" % total_tricks)
	main3.queue_free()
	await process_frame


func _teleport(pos: Vector3) -> void:
	_rider.position = Vector3(pos.x, _water.height_at(pos.x, pos.z), pos.z)
	_rider.vertical_speed = 0.0


func _test_race_start() -> void:
	print("Largada:")
	_check(_race.state == RaceManager.State.COUNTDOWN, "empieza con cuenta regresiva")
	_check(_rider.controls_locked, "durante la cuenta no se puede jugar")
	_check(
		not _rider.is_fallen() and _state() == &"riding", "en la largada está parado en la tabla"
	)
	var split := _main.get_node("Views") as SplitScreen
	_check(split != null and split.views.size() == 1, "1 jugador: una sola pantalla")
	var start_angle := _course.track.angle_of(_rider.global_position)
	_check(absf(start_angle) < 0.1, "larga en la meta (ángulo %.2f)" % start_angle)
	_set_action(&"p1_up", true)
	await _mash(8.0, 1.0)
	_set_action(&"p1_up", false)
	_check(
		_state() == &"riding" and _rider.speed < 0.5,
		"durante la cuenta no se mueve ni salta"
	)
	_race.skip_countdown()
	await process_frame
	_check(_race.state == RaceManager.State.RACING, "después de la cuenta empieza la carrera")
	_check(not _rider.controls_locked, "ya se puede jugar")


func _test_course() -> void:
	print("Circuito:")
	_check(_course.rings.size() > 5, "hay círculos de velocidad (%d)" % _course.rings.size())
	_check(_course.rocks.size() > 5, "hay rocas (%d)" % _course.rocks.size())
	_course.hazards_enabled = true
	_course.bounds_enabled = true
	_set_action(&"p1_up", true)
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)

	# Círculo de velocidad: nitro + motivación.
	var ring := _course.rings[0]
	var nitro_before := _rider.nitro
	_teleport(ring.position)
	await process_frame
	await process_frame
	_check(_rider.nitro > nitro_before + 0.2, "pasar por un círculo carga nitro")
	_check(_rider.motivation_timer > 0.0, "pasar por un círculo da motivación")
	await _wait(0.4)
	_check(
		_rider.speed > _rider.stats.max_speed + 0.5,
		"la motivación da un mini sprint (%.1f m/s)" % _rider.speed
	)

	# Roca: chocar tira al agua y deja fuera de la roca.
	var rock := _course.rocks[0]
	for r in _course.rocks:
		if r.height > rock.height:
			rock = r
	_teleport(rock.position)
	await process_frame
	await process_frame
	_check(_rider.is_fallen(), "chocar una roca tira de la tabla")
	var d := Vector2(_rider.position.x - rock.position.x, _rider.position.z - rock.position.z).length()
	_check(d > rock.radius, "después del choque queda fuera de la roca")
	var tangent := _course.track.heading_at(_course.track.angle_of(_rider.position))
	_check(
		absf(wrapf(_rider.heading - tangent, -PI, PI)) < 0.01,
		"después del choque mira en el sentido de la carrera"
	)
	await _mash_until_standing(8.0, 4.0)
	_check(not _rider.is_fallen(), "se levanta después del choque")

	# Isla: chocar la orilla también tira y saca afuera.
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	_teleport(_course.track.position_at(1.0, -(_course.track_radius - _course.island_radius) + 0.5))
	await process_frame
	await process_frame
	_check(_rider.is_fallen(), "chocar la isla tira de la tabla")
	var r_center := Vector2(_rider.position.x, _rider.position.z).length()
	_check(r_center >= _course.island_crash_radius(), "y queda fuera de la isla")

	# Límite de afuera: no deja salir del circuito.
	_teleport(_course.track.position_at(2.0, _course.half_width + 20.0))
	await process_frame
	await process_frame
	r_center = Vector2(_rider.position.x, _rider.position.z).length()
	_check(r_center <= _course.outer_limit() + 0.5, "no se puede salir del circuito por afuera")
	await _mash_until_standing(8.0, 4.0)
	_course.hazards_enabled = false


func _test_turbo_and_wrong_way() -> void:
	print("Turbo:")
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	_set_action(&"p1_up", true)
	await _wait(2.5)
	_rider.reset_nitro()
	_rider.add_nitro(1.0)
	_set_action(&"p1_b", true)
	await _wait(0.8)
	_check(
		_rider.speed > _rider.stats.max_speed * 1.3,
		"el turbo acelera mucho (%.1f m/s)" % _rider.speed
	)
	_check(_rider.nitro < 0.8, "el turbo gasta nitro (%.2f)" % _rider.nitro)
	await _wait(3.0)
	_check(_rider.nitro == 0.0, "el turbo se acaba con el nitro")
	_check(not _rider.turbo_active, "sin nitro no hay turbo")
	_set_action(&"p1_b", false)

	print("Al revés:")
	_course.bounds_enabled = true
	var a := 1.5
	_teleport(_course.track.position_at(a))
	_rider.heading = _course.track.heading_at(a) + PI
	await _wait(2.0)
	_check(_race.is_wrong_way(_rider), "ir al revés se detecta")
	_rider.heading = _course.track.heading_at(_course.track.angle_of(_rider.position))
	await _wait(0.5)
	_check(not _race.is_wrong_way(_rider), "al enderezar se va el aviso")


func _test_laps() -> void:
	print("Vueltas y meta:")
	_course.hazards_enabled = false
	var start := RaceManager.START_ANGLE
	_race._progress[_rider] = start
	_race._last_angle[_rider] = start
	var laps := _race.config.laps
	var seen_lap_2 := false
	var a := start
	while a < laps * TAU + 0.2:
		_teleport(_course.track.position_at(a))
		await process_frame
		if _race.lap_of(_rider) == 2:
			seen_lap_2 = true
		a += 0.2
	await process_frame
	_check(seen_lap_2, "al dar una vuelta pasa a la vuelta 2")
	_check(_race.finished(_rider), "al completar %d vueltas llega a la meta" % laps)
	_check(_race.place_of(_rider) == 1, "llega 1º")
	_check(_race.state == RaceManager.State.FINISHED, "termina la carrera")
	var results := _main.get_node("Results") as ResultsPanel
	_check(results != null and results._panel.visible, "se muestran los resultados")


func _test_music() -> void:
	print("Música:")
	var audio := root.get_node("AudioManager")
	var player: AudioStreamPlayer = audio.player
	_check(player.stream != null and player.playing, "suena la música durante la carrera")
	_check((player.stream as AudioStreamOggVorbis).loop, "la música está en bucle")
	_course.hazards_enabled = false
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	await _wait(1.0)
	_check(not audio.epic, "en el agua, volumen normal")
	# Salto cargado al máximo: mucho tiempo en el aire.
	GameSettings.jump_mode = GameSettings.JumpMode.CHARGE
	_set_action(&"p1_a", true)
	await _wait(1.05)
	_set_action(&"p1_a", false)
	GameSettings.jump_mode = GameSettings.JumpMode.TAP
	await _wait(0.6)
	_check(not _rider.grounded and audio.epic, "mucho tiempo en el aire: música épica")
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.1)
	_check(not audio.epic, "al volver al agua, vuelve a la normalidad")


func _test_split_screen() -> void:
	print("Pantalla dividida:")
	_main.queue_free()
	await process_frame
	await process_frame
	GameSettings.player_count = 2
	GameSettings.bot_count = 1
	var main2: Node = load("res://main.tscn").instantiate()
	root.add_child(main2)
	await process_frame
	await process_frame
	var race := main2.get_node("RaceManager") as RaceManager
	var split := main2.get_node("Views") as SplitScreen
	_check(race.racers.size() == 3, "2 jugadores + 1 bot: 3 corredores")
	_check(race.humans().size() == 2, "2 personas")
	_check(split.views.size() == 2, "2 jugadores: 2 pantallas")
	_check(split.get_child(0) is HBoxContainer, "por defecto la pantalla se divide lado a lado")
	# La cámara nunca queda debajo del agua (olas grandes).
	var water2 := main2.get_node("Water") as Water
	var s := Swell.new()
	var p0r := race.racers[0].position
	s.center = Vector2(p0r.x, p0r.z) - Vector2(race.racers[0].forward().x, race.racers[0].forward().z) * 7.0
	s.direction = Vector2.RIGHT
	s.speed = 0.0
	s.max_amplitude = 4.0
	s.width = 6.0
	s.half_length = 30.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	water2.add_swell(s)
	await _wait(1.0)
	var cam := split.cameras[0]
	var under := cam.global_position.y - water2.height_at(cam.global_position.x, cam.global_position.z)
	_check(under >= 1.4, "la cámara queda arriba del agua aunque haya una ola grande (%.1f m)" % under)
	var bit0 := 1 << Water.FOLLOWER_LAYER_BASE
	var bit1 := 1 << (Water.FOLLOWER_LAYER_BASE + 1)
	var m0 := split.cameras[0].cull_mask
	var m1 := split.cameras[1].cull_mask
	_check(m0 & bit0 and not m0 & bit1, "cámara 1 ve solo su agua")
	_check(m1 & bit1 and not m1 & bit0, "cámara 2 ve solo su agua")
	_check(_has_key(&"p2_left", KEY_LEFT), "J2 usa las flechas")
	_check(not _has_key(&"p1_left", KEY_LEFT), "J1 ya no usa las flechas")
	var p0 := race.racers[0].position
	var p1 := race.racers[1].position
	_check(p0.distance_to(p1) > 4.0, "largan uno al lado del otro")

	# Handicap: el de atrás carga más nitro y salta más alto; el primero no.
	race.skip_countdown()
	var first := race.racers[0]
	var last := race.racers[1]
	race._progress[last] = race.progress_of(first) - 200.0 / race.course.track.radius
	await process_frame
	await process_frame
	_check(first.catchup < 0.05, "el que va adelante casi no tiene handicap (%.3f)" % first.catchup)
	_check(last.catchup > 0.99, "el que va 200 m atrás tiene el handicap al máximo")
	last.reset_nitro()
	last.add_nitro(0.1)
	_check(last.nitro > 0.2, "con handicap, el nitro que gana rinde más (%.2f)" % last.nitro)
	first.reset_nitro()
	first.add_nitro(0.1)
	_check(absf(first.nitro - 0.1) < 0.02, "sin handicap, el nitro rinde normal")
	_check(last.jump_mult() > 1.3 and first.jump_mult() < 1.02, "con handicap salta más alto")
	_check(last.speed_mult() > 1.19 and first.speed_mult() < 1.01, "con handicap va hasta 20% más rápido")
	# Una vuelta de atraso: handicap al máximo.
	race._progress[last] = race.progress_of(first) - TAU
	await process_frame
	_check(last.catchup > 0.99, "con una vuelta de atraso el handicap es el máximo")
	_check(last.trick_grace() > 1.0, "con handicap hay tolerancia al caer de un truco")
	_check(
		split.huds[1]._nitro_label.text.begins_with("NITRO ×"),
		"el HUD muestra el multiplicador de nitro"
	)
	main2.queue_free()
	GameSettings.player_count = 1
	GameSettings.bot_count = 0
	await process_frame


func _has_key(action: StringName, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == key:
			return true
	return false


func _test_pad_layouts() -> void:
	print("Mandos:")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.GENERIC)
	_check(_has_button(&"p1_a", 2), "mando genérico: ✕ (botón 2) es A")
	_check(_has_button(&"p1_debug_fall", 0), "mando genérico: △ (botón 0) es caerse")
	_check(not _has_button(&"p1_a", JOY_BUTTON_A), "mando genérico: △ ya no es A")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.STANDARD)
	_check(_has_button(&"p1_a", JOY_BUTTON_A), "mando estándar: A es A")
	_check(_has_button(&"p1_drift", JOY_BUTTON_X), "mando estándar: X derrapa")
	_check(_has_button(&"p1_left", JOY_BUTTON_DPAD_LEFT), "la cruceta sigue funcionando")


func _has_button(action: StringName, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return true
	return false


func _test_get_up() -> void:
	print("Levantarse:")
	await _press(&"p1_debug_fall")
	_check(_rider.is_fallen(), "F tira al jugador al agua")
	_check(_rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "cae al agua")

	await _wait(1.0)
	_check(_rider.is_fallen(), "sin pulsar nada sigue caído")

	await _mash(2.0, 3.0)
	_check(
		_rider.recovery_stage == Rider.RecoveryStage.IN_WATER,
		"spamear lento (2 por segundo) no alcanza para subirse"
	)

	await _mash(8.0, 1.0)
	_check(
		_rider.recovery_stage == Rider.RecoveryStage.PRONE,
		"spamear rápido lo sube acostado a la tabla en ~1 s"
	)
	_check(_rider.is_fallen(), "acostado todavía no está parado")
	var hud := (_main.get_node("Views") as SplitScreen).huds[0]
	await process_frame
	_check(
		hud._mash_bar.value >= 0.5 and hud._mash_bar.value < 1.0,
		"una sola barra: acostado ya está por la mitad (%.2f)" % hud._mash_bar.value
	)

	await _wait(3.0)
	_check(_rider.is_fallen(), "si deja de spamear se queda acostado")

	var frames_before := Engine.get_process_frames()
	await _mash_until_standing(8.0, 4.0)
	var seconds := float(Engine.get_process_frames() - frames_before) / FPS
	_check(not _rider.is_fallen(), "seguir spameando lo pone de pie")
	_check(seconds < 1.3, "pararse desde acostado tarda poco (%.2f s)" % seconds)
	_check(_rider.recovery_stage == Rider.RecoveryStage.STANDING, "etapa = parado")


func _test_throttle_and_steer() -> void:
	print("Acelerar y girar:")
	await _wait(2.5)
	_check(_rider.speed < 1.0, "parado sin acelerar no avanza solo (velocidad %.1f)" % _rider.speed)

	_set_action(&"p1_up", true)
	await _wait(3.0)
	_check(_rider.speed > 10.0, "W acelera (velocidad %.1f)" % _rider.speed)

	var start_heading := _rider.heading
	var start_pos := _rider.global_position
	await _hold(&"p1_right", 1.0)
	var turned := start_heading - _rider.heading
	_check(turned > 0.4, "derecha gira a la derecha (%.2f rad)" % turned)
	_check(turned < 1.3, "girar cuesta más que antes (%.2f rad en 1 s)" % turned)
	_check(start_pos.distance_to(_rider.global_position) > 8.0, "se desplaza por el agua")
	var trail := _rider.get_node("Visual/Trail") as BoardTrail
	_check(trail != null and trail._points.size() > 5, "la tabla deja estela")
	_check(trail != null and trail.mesh.get_surface_count() > 0, "la estela se dibuja")

	var expected_y := _water.height_at(_rider.global_position.x, _rider.global_position.z)
	_check(absf(_rider.global_position.y - expected_y) < 0.001, "flota a la altura de la ola")

	_set_action(&"p1_up", false)
	await _wait(1.0)
	_check(_rider.speed < 11.5, "al soltar W frena de a poco (velocidad %.1f)" % _rider.speed)

	# Modo automático: avanza solo y atrás frena.
	GameSettings.auto_forward = true
	await _wait(2.5)
	_check(_rider.speed > 12.0, "automático: avanza solo sin tocar nada (%.1f)" % _rider.speed)
	_set_action(&"p1_down", true)
	await _wait(1.5)
	_check(_rider.speed < 3.0, "automático: atrás frena (%.1f)" % _rider.speed)
	_set_action(&"p1_down", false)
	await _wait(2.5)
	_check(_rider.speed > 10.0, "automático: al soltar vuelve a avanzar (%.1f)" % _rider.speed)
	GameSettings.auto_forward = false
	_set_action(&"p1_up", true)
	await _wait(1.5)

	var launched := false
	for i in int(8.0 * FPS):
		if _state() != &"riding":
			launched = true
		await process_frame
	_check(not launched, "las olas chicas de fondo no lo lanzan al aire")


func _test_jump_and_tricks() -> void:
	print("Salto y trucos:")
	_check(GameSettings.jump_mode == GameSettings.JumpMode.TAP, "por defecto el salto es tocar")
	# El salto cargado sigue en el código: se prueba igual.
	GameSettings.jump_mode = GameSettings.JumpMode.CHARGE
	# Salto simple: toca y suelta.
	await _press(&"p1_a")
	_check(_state() == &"airborne", "ESPACIO salta")
	var tap_height := await _measure_jump_height()
	_check(tap_height > 0.2, "sube en el aire (%.2f m)" % tap_height)
	_check(_state() == &"riding", "aterriza y sigue andando")
	await _wait(0.3)

	# Salto cargado: mantener sin soltar; al llegar al máximo salta solo.
	_set_action(&"p1_a", true)
	await _wait(0.5)
	_check(_state() == &"riding", "mantener ESPACIO en el agua no salta todavía")
	_check(_rider.jump_charge > 0.3, "mantener ESPACIO carga el salto (%.2f)" % _rider.jump_charge)
	await _wait(0.6)
	_check(_state() == &"airborne", "al llegar a la carga máxima salta solo")
	# Soltar enseguida: si se sigue manteniendo en el aire, empieza un truco.
	_set_action(&"p1_a", false)
	var charged_height := await _measure_jump_height()
	_check(
		charged_height > tap_height * 2.0,
		"el salto cargado sube mucho más (%.2f m contra %.2f m)" % [charged_height, tap_height]
	)
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# Modo "tocar para saltar": salta enseguida al apretar.
	GameSettings.jump_mode = GameSettings.JumpMode.TAP
	_set_action(&"p1_a", true)
	await process_frame
	await process_frame
	_check(_state() == &"airborne", "modo tocar: salta al apretar, sin soltar")
	_set_action(&"p1_a", false)
	var tap_mode_height := await _measure_jump_height()
	_check(tap_mode_height > 1.0, "modo tocar: salto alto fijo (%.2f m)" % tap_mode_height)
	GameSettings.jump_mode = GameSettings.JumpMode.CHARGE
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# En el aire no se puede volver a saltar.
	await _press(&"p1_a")
	await _wait(0.2)
	var vs := _rider.vertical_speed
	await _press(&"p1_a")
	_check(_rider.vertical_speed < vs, "en el aire no hay doble salto")
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.3)

	# Truco bien hecho: salto cargado, en el aire mantener un poco y soltar a tiempo.
	var tricks_before := _tricks_landed
	var nitro_before := _rider.nitro
	await _charged_jump(0.6)
	_set_action(&"p1_a", true)
	await _wait(0.3)
	_check(_rider.trick_angle > 0.0, "mantener ESPACIO en el aire gira la tabla")
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 2.0)
	_check(not _rider.is_fallen(), "soltar a tiempo: aterriza bien")
	_check(_tricks_landed == tricks_before + 1, "cuenta como truco")
	_check(_rider.nitro > nitro_before, "el truco carga nitro (%.2f)" % _rider.nitro)
	await _wait(0.3)

	# Truco fallido: mantener hasta tocar el agua.
	await _charged_jump(0.6)
	_set_action(&"p1_a", true)
	await _wait(1.5)
	_set_action(&"p1_a", false)
	_check(_rider.is_fallen(), "tocar el agua girando: se cae")
	_check(_rider.nitro == 0.0, "truco fallido: nitro a 0")

	await _mash_until_standing(8.0, 5.0)
	_check(not _rider.is_fallen(), "se vuelve a levantar")
	await _wait(3.0)
	GameSettings.jump_mode = GameSettings.JumpMode.TAP

	# Turbo en el aire: sigue subiendo y queda más tiempo en el aire.
	await _press(&"p1_a")
	var plain := await _measure_air()
	await _wait(0.5)
	_rider.reset_nitro()
	_rider.add_nitro(1.0)
	await _press(&"p1_a")
	_set_action(&"p1_b", true)
	_camera_lost = false
	_watch_camera = true
	var boosted := await _measure_air()
	_watch_camera = false
	_set_action(&"p1_b", false)
	_check(not _camera_lost, "la cámara no pierde al personaje aunque suba mucho")
	_check(
		boosted.x > plain.x * 2.0,
		"turbo en el aire: sube mucho más (%.1f m contra %.1f m)" % [boosted.x, plain.x]
	)
	_check(
		boosted.y > plain.y + 0.5,
		"turbo en el aire: más tiempo para trucos (%.1f s contra %.1f s)" % [boosted.y, plain.y]
	)
	_check(_rider.nitro < 1.0, "el turbo en el aire gasta nitro")
	await _wait_until_state(&"riding", 4.0)
	# Volver a la velocidad normal antes del próximo test.
	_rider.reset_nitro()
	await _wait(4.0)


func _test_drift() -> void:
	print("Derrape:")
	_check(_rider.speed > 6.0, "va rápido antes de derrapar (%.1f)" % _rider.speed)

	# Un rival quieto que va a quedar detrás.
	var victim: Rider = load("res://core/rider/rider.tscn").instantiate()
	victim.player_index = 1
	_main.add_child(victim)
	await process_frame
	victim.state_machine.transition_to(&"riding")

	_set_action(&"p1_right", true)
	await _wait(0.2)
	_set_action(&"p1_drift", true)
	await process_frame
	await process_frame
	_check(_state() == &"drifting", "SHIFT derrapa")
	_check(_rider.drift_side == 1, "derrapa hacia el lado del giro")
	var speed_before := _rider.speed
	victim.global_position = _rider.global_position - _rider.forward() * 3.0
	victim.position.y = _water_height_here()
	await _wait(0.3)
	_check(_rider.speed < speed_before, "derrapar frena")
	var sheet := _rider.get_node("Visual/Spray/Sheet") as MeshInstance3D
	_check(sheet != null and sheet.visible, "derrapar levanta la cortina de agua")
	if sheet:
		var box := sheet.get_aabb()
		var center_x := box.position.x + box.size.x * 0.5
		_check(
			absf(center_x) < 0.3 and box.end.z > 5.0,
			"la cortina sale recta hacia atrás (centro x %.2f, largo %.1f m)" % [center_x, box.end.z]
		)
	_check(victim.is_fallen(), "el agua del derrape tira al rival que está detrás")

	_set_action(&"p1_drift", false)
	_set_action(&"p1_right", false)
	await _wait(0.1)
	_check(_state() == &"riding", "soltar SHIFT termina el derrape")
	victim.queue_free()
	await _wait(1.0)


func _test_swells() -> void:
	print("Olas grandes:")
	var player := Vector2(_rider.global_position.x, _rider.global_position.z)
	var all_clear := true
	for i in 60:
		var s := _waves.make_swell()
		if s and not _waves.is_clear_of(s, player):
			all_clear = false
	_check(all_clear, "las olas nunca nacen encima del jugador")

	# Olas de frente: adelante (por la pista) y viniendo hacia el jugador.
	_course.bounds_enabled = false
	var saved_pos := _rider.position
	var saved_heading := _rider.heading
	_teleport(_course.track.position_at(1.0))
	_rider.heading = _course.track.heading_at(1.0)
	_waves.incoming_chance = 1.0
	var incoming_ok := 0
	var me := Vector2(_rider.position.x, _rider.position.z)
	var fwd := Vector2(_rider.forward().x, _rider.forward().z)
	for i in 20:
		var s := _waves.make_swell()
		if s == null:
			continue
		var to_me := (me - s.center).normalized()
		var ahead := (s.center - me).dot(fwd)
		if s.direction.dot(to_me) > 0.75 and ahead > 30.0:
			incoming_ok += 1
	_check(incoming_ok >= 18, "las olas nacen adelante y vienen de frente (%d de 20)" % incoming_ok)
	_waves.incoming_chance = 0.75
	_rider.position = saved_pos
	_rider.heading = saved_heading

	_waves.random_seed = 1234
	_waves._ready()
	_waves.enabled = true
	await _wait(6.0)
	_check(_water.swells.size() > 0, "aparecen olas grandes solas (%d)" % _water.swells.size())
	_waves.enabled = false
	_water.clear_swells()

	# Una ola quieta adelante: ir rápido hacia ella debe lanzarlo al aire.
	var s := Swell.new()
	var f := _rider.forward()
	var ahead := _rider.global_position + f * 25.0
	s.center = Vector2(ahead.x, ahead.z)
	s.direction = -Vector2(f.x, f.z)
	s.speed = 0.0
	s.max_amplitude = 3.0
	s.width = 5.5
	s.half_length = 20.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	_water.add_swell(s)
	_set_action(&"p1_up", true)
	var launched := false
	for i in int(4.0 * FPS):
		if _state() == &"airborne":
			launched = true
			break
		await process_frame
	_check(launched, "subir una ola grande con velocidad lo lanza al aire")


## Mantiene A `seconds` en el agua y suelta (salto cargado).
func _charged_jump(seconds: float) -> void:
	_set_action(&"p1_a", true)
	await _wait(seconds)
	_set_action(&"p1_a", false)
	await process_frame
	await process_frame


## (altura máxima, segundos en el aire) hasta aterrizar.
func _measure_air() -> Vector2:
	var max_height := 0.0
	var frames := 0
	for i in int(6.0 * FPS):
		var h := _rider.global_position.y - _water_height_here()
		max_height = maxf(max_height, h)
		if _watch_camera:
			var cam := (_main.get_node("Views") as SplitScreen).cameras[0]
			var body := _rider.global_position + Vector3.UP * 0.9
			if not cam.is_position_in_frustum(body):
				_camera_lost = true
		if _state() != &"airborne":
			break
		frames += 1
		await process_frame
	return Vector2(max_height, frames / float(FPS))


## Altura máxima sobre el agua hasta aterrizar.
func _measure_jump_height() -> float:
	var max_height := 0.0
	for i in int(2.5 * FPS):
		var h := _rider.global_position.y - _water_height_here()
		max_height = maxf(max_height, h)
		if _state() != &"airborne":
			break
		await process_frame
	return max_height


func _state() -> StringName:
	return _rider.state_machine.current_name


func _water_height_here() -> float:
	return _water.height_at(_rider.global_position.x, _rider.global_position.z)


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if ok:
		print("  OK    ", description)
	else:
		print("  FALLA ", description)
		if _rider:
			print(
				"        estado=%s vel=%.1f vel_vert=%.2f en_agua=%s carga=%.2f a=%s"
				% [
					_state(),
					_rider.speed,
					_rider.vertical_speed,
					_rider.grounded,
					_rider.jump_charge,
					Input.is_action_pressed(&"p1_a"),
				]
			)
		_failures.append(description)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("TESTS OK (%d comprobaciones)" % _checks)
		quit(0)
	else:
		print("TESTS FALLIDOS: %d de %d" % [_failures.size(), _checks])
		quit(1)


func _wait(seconds: float) -> void:
	for i in int(seconds * FPS):
		await process_frame


func _wait_until_state(state: StringName, max_seconds: float) -> void:
	for i in int(max_seconds * FPS):
		if _state() == state:
			return
		await process_frame


func _set_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


## Toca un botón. Los eventos simulados llegan al juego un frame después,
## por eso se espera un frame extra tras soltar.
func _press(action: StringName) -> void:
	_set_action(action, true)
	await process_frame
	await process_frame
	_set_action(action, false)
	await process_frame
	await process_frame


## Pulsa A `rate` veces por segundo durante `seconds`.
func _mash(rate: float, seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(seconds * FPS):
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame


## Spamea hasta que se pone de pie (o se acaba el tiempo).
func _mash_until_standing(rate: float, max_seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(max_seconds * FPS):
		if not _rider.is_fallen():
			break
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame
	_set_action(&"p1_a", false)
	await process_frame


func _hold(action: StringName, seconds: float) -> void:
	_set_action(action, true)
	await _wait(seconds)
	_set_action(action, false)
	await process_frame
