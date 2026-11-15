extends "res://tests/test_base.gd"
## Carrera y surfista: largada, levantarse, moverse, saltos y trucos, derrape, olas, pista, turbo, vueltas, música y pantalla dividida (todo sobre la misma carrera).


func run() -> void:
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
		return
	_rider = _race.racers[0]
	# Sin olas grandes al azar ni handicap durante los tests de movimiento.
	_waves.enabled = false
	_race.catchup_enabled = false
	_water.clear_swells()
	_rider.trick_landed.connect(func(_spins: int) -> void: _tricks_landed += 1)
	_rider.jumped.connect(func() -> void: _takeoff_y = _rider.global_position.y)
	_rider.wave_punched.connect(func() -> void:
		_punches += 1
		var v := _rider.get_node("Visual") as RiderVisual
		if not _water.face_in_wave(v.face_position()):
			_punch_without_face = true
	)

	var world_env := _main.get_node("WorldEnvironment") as WorldEnvironment
	var env := world_env.environment
	_check(
		env.background_mode == Environment.BG_SKY and env.sky != null
		and (env.sky.sky_material as ShaderMaterial).shader.resource_path.ends_with("tropical_sky.gdshader"),
		"el cielo es el tropical"
	)
	_check(env.fog_sky_affect == 0.0, "la niebla no tapa el cielo")

	# P muestra el contador de FPS.
	var hud0 := (_main.get_node("Views") as SplitScreen).huds[0]
	var pkey := InputEventKey.new()
	pkey.physical_keycode = KEY_P
	pkey.pressed = true
	Input.parse_input_event(pkey)
	await process_frame
	await process_frame
	_check(Hud.show_fps and hud0._fps_label.visible, "P muestra el contador de FPS")
	Input.parse_input_event(pkey)
	await process_frame
	await process_frame
	_check(not Hud.show_fps, "P lo vuelve a ocultar")

	_test_pad_layouts()
	await _test_race_start()

	# Las mecánicas se prueban lejos del circuito, sin obstáculos.
	_course.hazards_enabled = false
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	await _test_get_up()
	await _test_throttle_and_steer()
	await _test_jump_and_tricks()
	await _test_look_back()
	await _test_drift()
	await _test_swells()
	await _test_wave_jump()
	await _test_constant_wave()
	await _test_course()
	await _test_turbo_and_wrong_way()
	await _test_laps()
	await _test_music()
	await _test_split_screen()


func _test_pad_layouts() -> void:
	print("Mandos:")
	# Sin mando conectado no se registran botones (se asignan al ID real del
	# mando cuando se conecta): se simula uno conectado como el mando 0.
	InputSetup.set_player_device(0, 0)
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.GENERIC)
	_check(_has_button(&"p1_a", 2), "mando genérico: ✕ (botón 2) es A")
	_check(_has_button(&"p1_debug_fall", 0), "mando genérico: △ (botón 0) es caerse")
	_check(not _has_button(&"p1_a", JOY_BUTTON_A), "mando genérico: △ ya no es A")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.STANDARD)
	_check(_has_button(&"p1_a", JOY_BUTTON_A), "mando estándar: A es A")
	_check(_has_button(&"p1_drift", JOY_BUTTON_X), "mando estándar: X derrapa")
	_check(_has_button(&"p1_left", JOY_BUTTON_DPAD_LEFT), "la cruceta sigue funcionando")
	InputSetup.refresh_player_devices()


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
	_set_action(&"p1_down", false)
	await _mash(8.0, 1.0)
	_set_action(&"p1_down", true)
	_check(
		_state() == &"riding" and _rider.speed < 0.5,
		"durante la cuenta no se mueve ni salta"
	)
	_race.skip_countdown()
	await process_frame
	_check(_race.state == RaceManager.State.RACING, "después de la cuenta empieza la carrera")
	_check(not _rider.controls_locked, "ya se puede jugar")


func _test_get_up() -> void:
	print("Levantarse:")
	var punches_before := _punches
	await _press(&"p1_debug_fall")
	_check(_rider.is_fallen(), "F tira al jugador al agua")
	_check(_rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "cae al agua")

	await _wait(1.0)
	_check(_rider.is_fallen(), "sin pulsar nada sigue caído")
	_check(_punches == punches_before, "caerse al agua no hace el chapuzón (solo atravesar una ola)")

	# Una sola barra que se llena con una cantidad fija de pulsaciones y no baja.
	var hud := (_main.get_node("Views") as SplitScreen).huds[0]
	await _press(&"p1_a")
	await _press(&"p1_a")
	await process_frame
	var after_two: float = hud._mash_bar.value
	await _wait(2.0)
	_check(
		after_two > 0.25 and is_equal_approx(hud._mash_bar.value, after_two),
		"la barra no baja si dejás de spamear (%.2f -> %.2f)" % [after_two, hud._mash_bar.value]
	)
	_check(_rider.recovery_stage == Rider.RecoveryStage.IN_WATER, "con 2 pulsaciones sigue en el agua")

	await _press(&"p1_a")
	await process_frame
	_check(_rider.recovery_stage == Rider.RecoveryStage.PRONE, "con 3 pulsaciones se sube a la tabla")
	_check(_rider.is_fallen(), "acostado todavía no está parado")
	_check(
		hud._mash_bar.value >= 0.5 and hud._mash_bar.value < 1.0,
		"una sola barra: acostado ya está por la mitad (%.2f)" % hud._mash_bar.value
	)
	# Sin pausa: se puede seguir spameando enseguida, mientras se sube.
	await _press(&"p1_a")
	await process_frame
	_check(hud._mash_bar.value > 0.6, "sigue sumando mientras se sube, sin pausa (%.2f)" % hud._mash_bar.value)

	await _wait(3.0)
	_check(_rider.is_fallen(), "si deja de spamear se queda acostado")

	var frames_before := Engine.get_process_frames()
	await _press(&"p1_a")
	await _press(&"p1_a")
	await _wait(0.6)
	var seconds := float(Engine.get_process_frames() - frames_before) / FPS
	_check(not _rider.is_fallen(), "6 pulsaciones en total: de pie")
	_check(seconds < 1.0, "pararse tarda poco (%.2f s)" % seconds)
	_check(_rider.recovery_stage == Rider.RecoveryStage.STANDING, "etapa = parado")


func _test_throttle_and_steer() -> void:
	print("Acelerar y girar:")
	await _wait(2.5)
	_check(_rider.speed < 1.0, "frenando no avanza (velocidad %.1f)" % _rider.speed)

	_set_action(&"p1_down", false)
	await _wait(3.0)
	_check(_rider.speed > 10.0, "sin tocar nada avanza solo (velocidad %.1f)" % _rider.speed)

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

	_set_action(&"p1_down", true)
	await _wait(1.5)
	_check(_rider.speed < 3.0, "atrás frena (%.1f)" % _rider.speed)
	_set_action(&"p1_down", false)
	await _wait(2.5)
	_check(_rider.speed > 10.0, "al soltar vuelve a avanzar (%.1f)" % _rider.speed)

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
	# Contra la altura teórica del toque (la medida depende de las olitas).
	var tap_theory := pow(_rider.stats.jump_speed_min, 2.0) / (2.0 * _rider.stats.gravity)
	_check(
		charged_height > tap_theory * 2.0,
		"el salto cargado sube mucho más (%.2f m contra %.2f m de un toque)" % [charged_height, tap_theory]
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

	# Turbo en el aire: un empujón hacia arriba (sube más y queda más tiempo).
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
		boosted.y > plain.y + 0.3,
		"turbo en el aire: más tiempo para trucos (%.1f s contra %.1f s)" % [boosted.y, plain.y]
	)
	_check(_rider.nitro < 1.0, "el turbo en el aire gasta nitro")
	await _wait_until_state(&"riding", 4.0)
	await _wait(0.5)

	# Truco + turbo en el aire: el nitro del truco no se cobra en el aire
	# (si no, el turbo sería infinito).
	_rider.reset_nitro()
	_rider.add_nitro(1.0)
	await _press(&"p1_a")
	_set_action(&"p1_a", true)
	_set_action(&"p1_b", true)
	var prev_nitro := _rider.nitro
	var nitro_rose := false
	var spun := false
	for i in int(6.0 * FPS):
		if _state() != &"airborne":
			break
		if _rider.trick_angle > 0.0:
			spun = true
		if _rider.nitro > prev_nitro + 0.0001:
			nitro_rose = true
		prev_nitro = _rider.nitro
		await process_frame
	_set_action(&"p1_a", false)
	_set_action(&"p1_b", false)
	_check(spun and not nitro_rose, "girando con turbo en el aire, el nitro no sube")
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 5.0)
	await _wait(1.0)

	# Turbo en el aire sin flotar: aunque se disparen ráfagas sin parar, solo
	# la primera empuja; después la gravedad es siempre la normal (parábola).
	await _press(&"p1_a")
	var top := 0.0
	var worst_g := 0.0
	var prev_vs := _rider.vertical_speed
	var landed := false
	var g := _rider.stats.gravity
	var frames := 0
	for i in int(8.0 * FPS):
		if _state() != &"airborne":
			landed = true
			break
		if i % 10 == 0:
			_rider.add_nitro(1.0)
			_rider.fire_turbo()
		await process_frame
		frames += 1
		top = maxf(top, _rider.global_position.y - _water_height_here())
		# Aceleración vertical de este frame (sin contar el frame del empujón
		# ni el aire fino, que frena la subida más que la gravedad).
		var acc := (_rider.vertical_speed - prev_vs) * FPS
		var kicked := _rider.vertical_speed > prev_vs
		if frames > 2 and not kicked and _rider.vertical_speed <= 0.0:
			worst_g = maxf(worst_g, absf(acc + g))
		prev_vs = _rider.vertical_speed
	var cap := _rider.stats.air_max_height
	_check(top < cap, "con turbo sin parar no vuela sin fin (%.1f m)" % top)
	_check(worst_g < 0.5, "al caer con turbo, la gravedad es la normal (desvío %.2f m/s²)" % worst_g)
	_check(landed, "después baja y aterriza aunque siga con turbo")
	await _wait_until_state(&"riding", 8.0)
	# Volver a la velocidad normal antes del próximo test.
	_rider.reset_nitro()
	await _wait(4.0)


func _test_look_back() -> void:
	print("Mirar atrás:")
	var cam := (_main.get_node("Views") as SplitScreen).cameras[0]
	await _wait(0.5)
	var f := _rider.forward()
	var behind := (cam.global_position - _rider.global_position).dot(f) < 0.0
	_check(behind, "la cámara va detrás del personaje")
	_set_action(&"p1_look_back", true)
	await _wait(0.3)
	f = _rider.forward()
	var ahead_m := (cam.global_position - _rider.global_position).dot(f)
	_check(ahead_m > 2.0 and cam.looking_back, "con el gatillo izquierdo / Q la cámara mira hacia atrás (%.1f m adelante)" % ahead_m)
	_set_action(&"p1_look_back", false)
	await _wait(0.3)
	f = _rider.forward()
	_check(
		(cam.global_position - _rider.global_position).dot(f) < 0.0 and not cam.looking_back,
		"al soltar vuelve a mirar hacia adelante"
	)
	_check(InputMap.has_action(&"p1_look_back"), "existe la acción de mirar atrás")
	var has_trigger := false
	# Con un mando conectado (simulado), el gatillo izquierdo mira atrás.
	InputSetup.set_player_device(0, 0)
	for ev in InputMap.action_get_events(&"p1_look_back"):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_LEFT:
			has_trigger = true
	InputSetup.refresh_player_devices()
	_check(has_trigger, "el gatillo izquierdo del mando mira atrás")


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
	# Sin tocar el stick, derrapar no gira solo ni pone la tabla de costado.
	_set_action(&"p1_right", false)
	var heading_before := _rider.heading
	var speed_before := _rider.speed
	victim.global_position = _rider.global_position - _rider.forward() * 3.0
	victim.position.y = _water_height_here()
	await _wait(0.3)
	_check(_rider.speed < speed_before, "derrapar frena")
	_check(
		absf(wrapf(_rider.heading - heading_before, -PI, PI)) < 0.12,
		"derrapar no gira solo (giró %.2f rad)" % wrapf(_rider.heading - heading_before, -PI, PI)
	)
	var vis := _rider.get_node("Visual") as RiderVisual
	_check(absf(vis._drift_yaw) < 0.05, "derrapando la tabla sigue derecha (no de costado)")
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
	# Bien empinada: que la lance aunque el oleaje de fondo esté bajando justo
	# ahí (si no, el test depende de en qué momento llega).
	s.width = 4.5
	s.half_length = 20.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	_water.add_swell(s)
	_set_action(&"p1_down", false)
	var launched := false
	for i in int(4.0 * FPS):
		if _state() == &"airborne":
			launched = true
			break
		await process_frame
	_check(launched, "subir una ola grande con velocidad lo lanza al aire")
	_set_action(&"p1_down", true)
	await _wait_until_state(&"riding", 3.0)
	await _wait(0.5)

	# Ciclo de la ola: crece ("se viene"), llega al máximo y rompe.
	_water.clear_swells()
	var w := Swell.new()
	var fw := _rider.forward()
	var spot := _rider.global_position + fw * 45.0
	w.center = Vector2(spot.x, spot.z)
	w.direction = -Vector2(fw.x, fw.z).normalized()
	w.speed = 0.0
	w.max_amplitude = 3.0
	w.width = 5.5
	w.half_length = 20.0
	w.lifetime = 100.0
	w.grow_time = 2.0
	_water.add_swell(w)
	_rider.speed = 0.0
	await _wait(1.0)
	_check(w.breaking == 0.0 and w.amplitude < w.max_amplitude, "mientras crece todavía no rompe")
	await _wait(2.5)
	_check(w.breaking > 0.9, "al llegar a su máximo rompe (%.2f)" % w.breaking)
	_check(is_equal_approx(w.shader_b().w, w.breaking), "el shader recibe cuánto rompió la ola")
	w.retire()
	await _wait(w.fade_time + 0.2)
	_check(_water.swells.is_empty(), "una ola retirada se desvanece y desaparece")


func _test_wave_jump() -> void:
	print("Salto de olas (saltito y pop):")
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	_water.clear_swells()
	_teleport(Vector3(400.0, 0.0, 900.0))
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	_set_action(&"p1_down", false)
	await _wait(2.0)
	await _press(&"p1_a")
	_check(_state() == &"airborne", "en agua plana, A hace un saltito")
	# Medido desde donde despegó (sobre el agua cambia con las olitas de fondo).
	var hop := await _measure_jump_height()
	_check(hop < 1.0, "el saltito es bajo (%.2f m)" % hop)
	await _wait_until_state(&"riding", 2.0)
	await _wait(0.5)
	# La palanca hacia arriba no salta (solo A).
	await _press(&"p1_up")
	await process_frame
	_check(_state() != &"airborne", "la palanca hacia arriba no salta (solo A)")
	await _wait(0.3)

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
	var hud_node: Node = (_main.get_node("Views") as SplitScreen).huds[0]
	_check(not "_pop_box" in hud_node, "no hay ícono del pop en pantalla (se descubre jugando)")
	_check(
		popped > plain * 1.3,
		"A al subir la ola (pop) lanza mucho más alto (%.1f m contra %.1f m)" % [popped, plain]
	)
	_check(_last_did_pop, "apretar justo al salir de la ola hace el pop")
	await _test_pop_rules()
	# Turbo al subir la ola: sale mucho más alto que sin turbo.
	var with_turbo := await _ride_into_swell(false, Vector3(2000.0, 0.0, 900.0), false, true)
	_check(
		with_turbo > plain * 1.3,
		"con turbo la ola lanza mucho más alto (%.1f m contra %.1f m)" % [with_turbo, plain]
	)
	_rider.reset_nitro()
	# Apretar antes de tiempo (lejos de la cresta) pierde el pop de esa ola,
	# aunque después se vuelva a apretar justo.
	await _ride_into_swell(true, Vector3(1600.0, 0.0, 900.0), true)
	_check(_early_pressed and not _last_did_pop, "apretar antes de tiempo pierde el pop de esa ola")
	# Una ola grande (4 m) rompiendo sí: el labio cae sobre la cara.
	await _ride_into_swell(false, Vector3(2400.0, 0.0, 900.0), false, false, 4.0, 6.4)
	_check(not _punch_without_face, "el chapuzón solo salta con la cara adentro del agua")
	_check(_punches > 0, "atravesar una ola que rompe se detecta (%d veces)" % _punches)
	_check_face_geometry()
	_check(_duck_seen, "al atravesarla el personaje se agacha y se cubre")
	_check(_shake_seen, "y después sacude la cabeza y se seca la cara")
	_check(_splash_seen, "y la cámara queda mojada medio segundo")
	await _wait(1.0)
	var hud2 := (_main.get_node("Views") as SplitScreen).huds[0]
	_check(not hud2.splash_overlay.visible, "después la cámara se aclara")
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
	_set_action(&"p1_down", false)
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
		await process_frame
	_set_action(&"p1_down", true)
	_check(launched, "andando por la ola constante, los picos lo lanzan al aire")
	_check(prompt, "en la ola constante también aparece el botón del pop")
	_check(max_height > 0.15, "salta (%.1f m el más alto en 10 s)" % max_height)
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


func _test_course() -> void:
	print("Circuito:")
	_check(_course.rings.size() > 5, "hay círculos de velocidad (%d)" % _course.rings.size())
	_check(_course.rocks.size() > 5, "hay rocas (%d)" % _course.rocks.size())
	_course.hazards_enabled = true
	_course.bounds_enabled = true
	_set_action(&"p1_down", false)
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
	# Tapada por una ola grande no cuenta: no se ve y se pasa por encima.
	var cover := Swell.new()
	cover.center = Vector2(rock.position.x, rock.position.z)
	cover.direction = Vector2(1.0, 0.0)
	cover.speed = 0.0
	cover.max_amplitude = rock.height * 1.3
	cover.width = 5.0
	cover.half_length = 15.0
	cover.lifetime = 100.0
	cover.grow_time = 0.01
	cover.update(0.05)
	_water.add_swell(cover)
	_check(rock.is_covered(_water), "una ola grande puede tapar la roca")
	var probe := Vector3(rock.position.x + rock.radius * 0.5, rock.position.y + rock.height * 0.5, rock.position.z)
	var fake := Rider.new()
	fake.position = probe
	_check(not rock.is_hitting(fake, _water), "tapada por una ola, la roca no te tira")
	_check(rock.is_hitting(fake, null), "sin la ola, en ese lugar sí chocaría")
	fake.free()
	_water.clear_swells()
	_check(not rock.is_covered(_water), "sin ola, la roca se ve y choca")
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

	# Contra la corchera (también en el aire): se desliza a lo largo de ella,
	# sin frenarse de golpe ni ser empujado hacia atrás.
	var a0 := 2.0
	_teleport(_course.track.position_at(a0, _course.half_width - 3.0))
	_rider.heading = _course.track.heading_at(a0) + 0.7
	_rider.speed = 13.0
	_set_action(&"p1_down", false)
	var min_speed := 99.0
	for i in int(1.5 * FPS):
		# A mitad de camino salta (el bug pasaba sobre todo en el aire).
		if i == 20:
			_set_action(&"p1_a", true)
		elif i == 23:
			_set_action(&"p1_a", false)
		min_speed = minf(min_speed, _rider.speed)
		await process_frame
	_set_action(&"p1_down", true)
	var moved := wrapf(_course.track.angle_of(_rider.position) - a0, -PI, PI)
	var lat := absf(_course.track.lateral_of(_rider.position))
	_check(min_speed > 8.0, "contra la corchera no pierde casi velocidad (mín %.1f m/s)" % min_speed)
	_check(moved > 0.1, "y sigue avanzando a lo largo de ella (%.2f rad)" % moved)
	_check(lat <= _course.half_width, "sin salirse de la pista (%.1f m)" % lat)
	await _wait_until_state(&"riding", 3.0)


func _test_turbo_and_wrong_way() -> void:
	print("Turbo:")
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	_set_action(&"p1_down", false)
	await _wait(2.5)
	_rider.reset_nitro()
	_rider.add_nitro(1.0)
	_check(_rider.turbo_charges() == 3, "la barra llena son 3 cargas de turbo")
	# Un toque: una ráfaga que gasta una carga.
	await _press(&"p1_b")
	await _wait(0.6)
	_check(_rider.turbo_active, "un toque de turbo dispara una ráfaga")
	_check(
		_rider.speed > _rider.stats.max_speed * 1.15,
		"el turbo acelera (%.1f m/s)" % _rider.speed
	)
	_check(_rider.turbo_charges() == 2, "y gasta una carga (quedan %d)" % _rider.turbo_charges())
	await _wait(1.2)
	_check(not _rider.turbo_active, "la ráfaga dura un rato y se termina")
	# Mantener apretado no hace nada extra: solo cuenta el toque.
	_set_action(&"p1_b", true)
	await _wait(2.5)
	_check(_rider.turbo_charges() == 1, "mantener apretado gasta una sola carga")
	_check(not _rider.turbo_active, "mantener no sostiene el turbo")
	_set_action(&"p1_b", false)
	await _wait(0.1)
	# Dos toques seguidos: el segundo no hace nada mientras dura la ráfaga.
	_rider.reset_nitro()
	_rider.add_nitro(1.0)
	var hud_full := (_main.get_node("Views") as SplitScreen).huds[0]
	await _wait(0.4)
	var full_fill: Color = hud_full._nitro_fill.bg_color
	_check(
		full_fill.r > 0.9 and full_fill.g < 0.8 and full_fill.b < 0.7 and hud_full._fire.visible,
		"con las 3 cargas la barra se pone roja y vibra"
	)
	await _press(&"p1_b")
	await _press(&"p1_b")
	var hud_t := (_main.get_node("Views") as SplitScreen).huds[0]
	await process_frame
	_check(
		hud_t._burn_bar.value > hud_t._nitro_bar.value + 0.05 and hud_t._fire.visible
		and hud_t._nitro_fill.bg_color.is_equal_approx(Hud.BURN_COLOR),
		"con turbo en curso, la barra se pone naranja y se ve consumiéndose con fuego"
	)
	var blocked := [false]
	_rider.turbo_blocked.connect(func() -> void: blocked[0] = true, CONNECT_ONE_SHOT)
	await _press(&"p1_b")
	_check(blocked[0] and hud_t._blocked > 0.0, "apretar turbo mientras dura avisa (la barra tiembla)")
	_check(
		_rider.turbo_charges() == 2 and _rider.turbo_time <= _rider.stats.turbo_burst_time,
		"no se puede volver a tirar turbo hasta que termina el actual (quedan %d cargas)" % _rider.turbo_charges()
	)
	await _wait(_rider.stats.turbo_burst_time + 0.2)
	await _press(&"p1_b")
	_check(_rider.turbo_active and _rider.turbo_charges() == 1, "terminada la ráfaga, otro toque dispara la siguiente")
	await _wait(3.5)
	# Primera barra casi llena: se completa sola (solo la primera, y ahí queda).
	_rider.reset_nitro()
	_rider.nitro = Rider.TURBO_CHARGE * 0.7
	await _wait(3.5)
	_check(
		is_equal_approx(_rider.nitro, Rider.TURBO_CHARGE),
		"pasado el 65 %% la primera barra se llena sola hasta completarse (%.2f)" % (_rider.nitro / Rider.TURBO_CHARGE)
	)
	_rider.nitro = Rider.TURBO_CHARGE * 0.6
	await _wait(1.0)
	_check(is_equal_approx(_rider.nitro, Rider.TURBO_CHARGE * 0.6), "por debajo del 65 % no se llena sola")
	_rider.nitro = Rider.TURBO_CHARGE * 1.8
	await _wait(1.0)
	_check(is_equal_approx(_rider.nitro, Rider.TURBO_CHARGE * 1.8), "la segunda barra no se llena sola")
	# Sin una carga completa no sale.
	_rider.reset_nitro()
	_rider.add_nitro(0.2)
	await _press(&"p1_b")
	_check(not _rider.turbo_active, "sin una carga completa el turbo no sale")
	_rider.reset_nitro()

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
	# Efectos de sonido.
	_check(audio._sfx.size() == audio.SFX_NAMES.size(), "están todos los efectos de sonido (%d)" % audio._sfx.size())
	_check(audio.ocean.stream != null and audio.ocean.playing, "suena el mar de fondo")
	_check((audio.ocean.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "el mar está en bucle")
	audio.last_sfx = ""
	await _press(&"p1_debug_fall")
	_check(audio.last_sfx == "splash", "caer al agua suena (%s)" % audio.last_sfx)
	audio.recent_sfx.clear()
	await _mash_until_standing(8.0, 4.0)
	# (Puede sonar otra cosa después, como el chapuzón si la cara toca el agua.)
	_check("mash" in audio.recent_sfx, "spamear para subirse suena")
	_rider.add_nitro(1.0)
	await _press(&"p1_b")
	_check(audio.last_sfx == "turbo", "el turbo suena")
	await _wait(2.0)
	_course.hazards_enabled = false
	_course.bounds_enabled = false
	_teleport(Vector3(0.0, 0.0, 900.0))
	if _rider.is_fallen():
		await _mash_until_standing(8.0, 4.0)
	await _wait(1.0)
	_check(not audio.epic, "en el agua, volumen normal")
	# Un salto largo (más de 1 s en el aire): la música se pone épica.
	await _press(&"p1_a")
	_rider.vertical_speed = 12.0
	await _wait(0.8)
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
	_check(last.nitro > 0.14, "con handicap, el nitro que gana rinde más (%.2f)" % last.nitro)
	first.reset_nitro()
	first.add_nitro(0.1)
	_check(absf(first.nitro - 0.1) < 0.02, "sin handicap, el nitro rinde normal")
	_check(last.jump_mult() > 1.13 and first.jump_mult() < 1.02, "con handicap salta un poco más alto")
	_check(last.speed_mult() > 1.07 and last.speed_mult() < 1.09 and first.speed_mult() < 1.01, "con handicap va hasta 8% más rápido")
	# Los bots nunca reciben handicap.
	var bot := race.racers[2]
	race._progress[bot] = race.progress_of(first) - 200.0 / race.course.track.radius
	await process_frame
	_check(not bot.is_human and bot.catchup == 0.0, "los bots no reciben handicap aunque vayan atrás")
	# Se mide contra la persona que va primera (un bot adelante no cuenta).
	race._progress[bot] = race.progress_of(first) + 300.0 / race.course.track.radius
	await process_frame
	_check(first.catchup < 0.05, "con un bot adelante, la persona que va primera sigue sin handicap")
	# Una sola persona (contra bots): nadie tiene handicap.
	last.is_human = false
	await process_frame
	_check(first.catchup == 0.0 and last.catchup == 0.0, "con una sola persona contra bots no hay handicap")
	last.is_human = true
	race._progress[bot] = race.progress_of(first) - 200.0 / race.course.track.radius
	race._progress[last] = race.progress_of(first) - 200.0 / race.course.track.radius
	await process_frame
	# Una vuelta de atraso: handicap al máximo.
	race._progress[last] = race.progress_of(first) - TAU
	await process_frame
	_check(last.catchup > 0.99, "con una vuelta de atraso el handicap es el máximo")
	_check(last.trick_grace() > 0.5, "con handicap hay tolerancia al caer de un truco")
	_check(
		split.huds[1]._nitro_label.text.begins_with("NITRO ×"),
		"el HUD muestra el multiplicador de nitro"
	)
	main2.queue_free()
	GameSettings.player_count = 1
	GameSettings.bot_count = 0
	await process_frame


## Pop: coyote time (vale un rato después de despegar, y sale igual que a
## tiempo) y en los saltos enormes (con turbo) suma menos.
func _test_pop_rules() -> void:
	var r: Rider = load("res://core/rider/rider.tscn").instantiate()
	var st := r.stats
	var g := st.gravity
	# Pop tardío dentro del coyote time: misma subida que a tiempo, menos lo que ya frenó.
	r.grounded = false
	r.did_pop = false
	r.pop_locked = false
	r.launch_speed = 10.0
	r.wave_air_time = 0.2
	r.vertical_speed = 10.0 - g * 0.2
	r.try_pop_press()
	_check(r.did_pop, "el pop vale un ratito después de salir de la ola (coyote time)")
	_check(
		absf(r.vertical_speed - (r.pop_speed(10.0) - g * 0.2)) < 0.001,
		"el pop tardío sale igual de alto que a tiempo"
	)
	# Pasado el coyote time ya no.
	r.did_pop = false
	r.pop_locked = false
	r.wave_air_time = st.pop_coyote + 0.05
	r.try_pop_press()
	_check(not r.did_pop, "pasado el coyote time ya no hay pop")
	# Saltos normales: el pop suma lo de siempre; los enormes (con turbo), el 75 %.
	var normal_gain := 9.0 * (st.pop_mult - 1.0) + st.pop_extra
	_check(is_equal_approx(r.pop_speed(9.0), 9.0 + normal_gain), "en un salto normal el pop suma lo de siempre")
	var big_gain := 30.0 * (st.pop_mult - 1.0) + st.pop_extra
	_check(
		is_equal_approx(r.pop_speed(30.0), 30.0 + big_gain * 0.75),
		"en un salto enorme el pop suma el 75 %% (%.1f en vez de %.1f m/s)" % [r.pop_speed(30.0) - 30.0, big_gain]
	)
	r.free()
