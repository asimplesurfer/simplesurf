extends "res://tests/test_base.gd"
## Modo libre: remar, olas regulables, tormenta en el momento, circuitos.


func run() -> void:
	# En el modo libre no hay avance automático: arranca sin nada apretado.
	_set_action(&"p1_down", false)
	await process_frame
	await _test_sandbox()


func _test_sandbox() -> void:
	print("Modo libre:")
	var saved_weather := GameSettings.weather
	var saved_players := GameSettings.player_count
	GameSettings.weather = GameSettings.Weather.SUNNY
	GameSettings.player_count = 1
	# Mar calmo para probar el remo (una ola al azar podría llevarlo).
	GameSettings.sandbox_wave_level = 0
	var m: Node = load("res://sandbox.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var sb := m.get_node("Session") as Sandbox
	var world := m.get_node("World") as SandboxWorld
	var waves := m.get_node("WaveManager") as WaveManager
	var water := m.get_node("Water") as Water
	_check(sb.free_ride() and sb.config.mode == RaceConfig.Mode.SANDBOX, "es el modo libre")
	_check(sb.racers.size() == 1 and sb.humans().size() == 1, "sin bots: solo el jugador")
	# Arranca sin olas grandes (nivel 0): la escala se pone de una.
	waves.amplitude_scale = 0.0
	_check(get_nodes_in_group("island").is_empty(), "en mar abierto (sin islas)")
	_check(world.rings.size() >= 10 and world.geysers.size() >= 5, "con circuitos de práctica (círculos y géiseres)")
	var far := true
	for f in world.floaters:
		if Vector2(f.position.x, f.position.z).length() < 90.0:
			far = false
	_check(far, "los circuitos están lejos de la largada")
	var r := sb.racers[0]
	_rider = r
	await _wait(0.3)
	_check(r.state_machine.current_name == &"paddling" and r.speed < 0.2, "arranca quieto, acostado en la tabla")
	await _wait(2.0)
	_check(r.speed < 0.2, "sin aceleración automática: sin tocar nada no avanza")
	# Empuja el stick: rema, toma impulso y se para.
	_set_action(&"p1_up", true)
	await _wait(0.6)
	_check(r.state_machine.current_name == &"paddling" and r.speed > 0.3, "empujando, rema acostado")
	var anim := (r.get_node("Visual") as RiderVisual)._body.anim
	_check(anim == &"paddle", "con la animación de remar con los brazos (%s)" % anim)
	await _wait_until_state(&"riding", 5.0)
	_check(r.state_machine.current_name == &"riding", "con impulso se para en la tabla")
	await _wait(2.0)
	_check(r.speed > 7.0, "parado y empujando, va rápido (%.1f m/s)" % r.speed)
	# Suelta el stick: se frena y vuelve a remar.
	_set_action(&"p1_up", false)
	await _wait_until_state(&"paddling", 8.0)
	_check(r.state_machine.current_name == &"paddling", "al soltar se frena y se acuesta a remar")
	# Sin derrape.
	_set_action(&"p1_drift", true)
	await process_frame
	await process_frame
	_check(not r.input.drift, "no hay derrape en el modo libre")
	_set_action(&"p1_drift", false)

	# Olas: con el nivel al máximo son como en una carrera; con 0 no hay.
	for i in 6:
		await _press(&"p1_waves_up")
	_check(sb.wave_level == GameSettings.SANDBOX_WAVE_LEVELS, "las olas suben hasta el máximo")
	await _wait(4.0)
	_check(is_equal_approx(waves.amplitude_scale, 1.0), "al máximo, olas de la altura de una carrera")
	var max_amp := 0.0
	await _wait(6.0)
	for sw in water.swells:
		max_amp = maxf(max_amp, sw.max_amplitude)
	_check(max_amp > 0.0 and max_amp <= waves.amplitude_max + 0.01, "nunca más altas que en una carrera (%.1f m)" % max_amp)
	for i in 6:
		await _press(&"p1_waves_down")
	_check(sb.wave_level == 0, "y bajan hasta 0")
	await _wait(8.0)
	var big := 0
	for sw in water.swells:
		if sw.amplitude > 0.3:
			big += 1
	_check(big == 0, "con 0 no quedan olas grandes")
	await _press(&"p1_waves_up")
	_check(sb.wave_level == 1 and GameSettings.sandbox_wave_level == 1, "el nivel se recuerda")

	# Tormenta en el momento: se prende y se apaga dejando todo como estaba.
	var env_before := (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := m.get_node("Sun") as DirectionalLight3D
	var sun_before := sun.light_energy
	var waves_before := water.waves
	var amp_before := waves.amplitude_max
	await _press(&"p1_storm")
	_check(sb.storm_on() and sb.storm != null, "T prende la tormenta")
	await process_frame
	await process_frame
	_check(sb.storm.rain.size() == 1 and water.waves.max_height() > 1.4, "llueve y el mar se pica")
	await _press(&"p1_storm")
	await process_frame
	_check(not sb.storm_on(), "T la apaga")
	_check(
		(m.get_node("WorldEnvironment") as WorldEnvironment).environment == env_before
		and is_equal_approx(sun.light_energy, sun_before)
		and water.waves == waves_before
		and is_equal_approx(waves.amplitude_max, amp_before)
		and water.shader_material().get_shader_parameter("deep_color") == null,
		"y queda todo como estaba (cielo, luz, agua y olas)"
	)
	var cam := (m.get_node("Views") as SplitScreen).cameras[0]
	_check(cam.get_node_or_null("Rain") == null, "sin lluvia")

	# Un círculo de práctica da nitro.
	r.position = world.rings[0].position
	r.position.y = world.rings[0].position.y - 0.9
	r.reset_nitro()
	await process_frame
	await process_frame
	_check(r.nitro > 0.0, "pasar por un círculo de práctica da nitro")
	var as_node: Node = sb
	_check(
		as_node is GameSession and not as_node is RaceManager,
		"el modo libre no es una carrera (base común: GameSession)"
	)
	m.queue_free()
	await process_frame
	await process_frame
	for c in root.get_children():
		if c is CharacterSelect:
			c.queue_free()
	await process_frame
	GameSettings.weather = saved_weather
	GameSettings.player_count = saved_players
