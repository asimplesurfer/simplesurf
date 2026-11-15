extends "res://tests/test_base.gd"
## Bots: caminos, carrera de bots y demo.


func run() -> void:
	_test_bot_paths()
	await _test_bot_race()
	await _test_demo()


func _test_bot_paths() -> void:
	# Levantarse escala con la dificultad; el más rápido es el 75 % de antes (10/s).
	var easy_m := AIDifficulty.preset(0).mash_rate
	var normal_m := AIDifficulty.preset(1).mash_rate
	var hard_m := AIDifficulty.preset(2).mash_rate
	_check(
		easy_m < normal_m and normal_m < hard_m,
		"los bots se levantan más rápido cuanto más difíciles (%.1f / %.1f / %.1f)" % [easy_m, normal_m, hard_m]
	)
	_check(is_equal_approx(hard_m, 7.5), "Difícil spamea al 75 %% de antes (%.1f/s)" % hard_m)
	# Niveles extra: Profesional (perfecto) e Imposible (perfecto y con ventaja).
	_check(AIDifficulty.NAMES.size() == 5, "hay 5 dificultades: %s" % str(AIDifficulty.NAMES))
	var pro := AIDifficulty.preset(3)
	var imp := AIDifficulty.preset(4)
	_check(pro.display_name == "Profesional" and pro.trick_fail_chance < 0.05, "Profesional casi no se equivoca")
	_check(imp.trick_fail_chance == 0.0 and imp.line_skill > pro.line_skill and imp.evade_skill > pro.evade_skill,
		"Imposible no se equivoca y juega mejor (línea, esquivar derrapes)")
	# La dificultad sale de jugar mejor: nadie tiene más velocidad ni más nitro.
	_check(not "speed_bonus" in imp and not "nitro_bonus" in imp, "Imposible no tiene ventajas físicas")
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


func _test_demo() -> void:
	print("Demo (menú sin tocar nada):")
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	var started := [false]
	menu.start_requested.connect(func() -> void: started[0] = true)
	root.add_child(menu)
	await _wait(9.0)
	_check(not started[0], "a los 9 s sin tocar nada todavía no arranca")
	_set_action(&"p1_down", false)
	await process_frame
	await _press(&"p1_down")
	await _wait(9.0)
	_check(not started[0], "tocar algo reinicia la espera")
	await _wait(1.5)
	var demo_config := menu.started_config
	_check(
		started[0] and demo_config != null and demo_config.mode == RaceConfig.Mode.DEMO,
		"a los 10 s sin tocar nada arranca la demo"
	)
	menu.queue_free()
	await process_frame

	# La demo es siempre igual, elija lo que elija el menú: dos bots en
	# Imposible, en El Atolón con tormenta (y no cambia lo elegido).
	var saved := [GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level,
		GameSettings.track_layout, GameSettings.weather]
	GameSettings.player_count = 1
	GameSettings.bot_count = 3
	GameSettings.bot_level = 0
	GameSettings.track_layout = GameSettings.TrackLayout.CLASSIC
	GameSettings.weather = GameSettings.Weather.SUNNY
	var demo: Node = load("res://main.tscn").instantiate()
	# La configuración viaja con la escena (como hace el menú al abrirla).
	(demo.get_node("RaceManager") as RaceManager).config = demo_config
	root.add_child(demo)
	await process_frame
	await process_frame
	var race := demo.get_node("RaceManager") as RaceManager
	var split := demo.get_node("Views") as SplitScreen
	var demo_course := demo.get_node("Course") as Course
	_check(race.racers.size() == 2 and race.humans().is_empty(), "la demo es un mano a mano de 2 bots")
	var impossible := true
	for r in race.racers:
		var ai := r.controller as AIController
		if ai == null or ai.difficulty.display_name != "Imposible":
			impossible = false
	_check(impossible, "los dos en Imposible")
	_check(demo_course.is_atoll() and demo_course.storm != null, "en El Atolón con tormenta")
	_check(race.config.laps == 3, "a 3 vueltas")
	_check(
		GameSettings.track_layout == GameSettings.TrackLayout.CLASSIC and GameSettings.weather == GameSettings.Weather.SUNNY,
		"sin cambiar el mapa ni el clima elegidos"
	)
	_check(split.views.size() == 2, "con la pantalla en 2 (una vista por bot)")
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
	var progress: Array[String] = []
	for r in race.racers:
		progress.append("%s %.2f%s" % [r.name, race.progress_of(r), " (caído)" if r.is_fallen() else ""])
		# Arrancar = avanzar algo (unos 20 m en el Atolón). Con tormenta y trucos al azar
		# alguno puede caerse en los primeros segundos y quedar más atrás.
		if race.progress_of(r) < 0.12:
			moving = false
	_check(moving, "los bots arrancan solos (%s)" % ", ".join(progress))
	# Su vista muestra lo mismo que la de un jugador: al caerse, el cartel de
	# levantarse con el ícono del botón.
	var bot0 := race.racers[0]
	var hud0 := split.huds[0]
	_check(hud0.rider == bot0, "la primera vista sigue al primer bot")
	bot0.fall()
	await _wait(0.3)
	_check(hud0._mash_box.visible, "en la demo, la vista del bot muestra el cartel de levantarse")
	_check(
		hud0._mash_prompt.kind == ButtonPrompt.Kind.FACE_BOTTOM,
		"con el ícono de los botones del mando"
	)
	GameSettings.player_count = saved[0]
	GameSettings.bot_count = saved[1]
	GameSettings.bot_level = saved[2]
	GameSettings.track_layout = saved[3]
	GameSettings.weather = saved[4]
	demo.queue_free()
	await process_frame
