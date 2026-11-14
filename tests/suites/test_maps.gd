extends "res://tests/test_base.gd"
## Mapas: archipiélago y El Atolón (con tormenta).


func run() -> void:
	await _test_archipelago()
	await _test_atoll()


func _test_archipelago() -> void:
	print("Mapa archipiélago:")
	GameSettings.track_layout = GameSettings.TrackLayout.ARCHIPELAGO
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for level in [2, 2, 1]:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var track := course.track
	_check(track is PathTrack, "el recorrido no es un círculo")
	_check(course.islands.size() >= 12, "hay muchas islas (%d)" % course.islands.size())
	_check(
		track.length() > 700.0 and track.length() < 1000.0,
		"una vuelta mide %.0f m" % track.length()
	)
	_check(config.laps == 1 and GameSettings.laps_for(GameSettings.TrackLayout.ARCHIPELAGO) == 3, "en el archipiélago se corren 3 vueltas")

	# Ida y vuelta: posición <-> (ángulo, lateral).
	var roundtrip := true
	for i in 40:
		var a := -PI + TAU * i / 40.0
		var lat := -15.0 + 30.0 * (i % 7) / 6.0
		var p := track.position_at(a, lat)
		var back := track.locate(p)
		if absf(wrapf(back.x - a, -PI, PI)) > 0.02 or absf(back.y - lat) > 0.6:
			roundtrip = false
			print("    ida y vuelta: %.2f, %.1f -> %.2f, %.1f" % [a, lat, back.x, back.y])
	_check(roundtrip, "posiciones y coordenadas de pista coinciden")

	# Curvas a la izquierda y a la derecha.
	var lefts := 0
	var rights := 0
	for i in 200:
		var a := -PI + TAU * i / 200.0
		var t0 := track.tangent_at(a)
		var t1 := track.tangent_at(a + 0.05)
		var turn := t0.x * t1.z - t0.z * t1.x
		if turn > 0.01:
			lefts += 1
		elif turn < -0.01:
			rights += 1
	_check(lefts > 10 and rights > 10, "hay curvas a los dos lados (%d / %d)" % [lefts, rights])

	# Ninguna isla pisa la pista.
	var clear := true
	for isl in course.islands:
		var lat := absf(track.lateral_of(isl.position))
		if lat < track.half_width + isl.radius + 4.0:
			clear = false
			print("    isla en %s muy cerca (%.1f m)" % [isl.position, lat])
	_check(clear, "las islas no pisan la pista")
	# Desde cualquier lugar de la pista se ven islas cerca.
	var always_islands := true
	for i in 30:
		var p := track.position_at(-PI + TAU * i / 30.0)
		var near := 0
		for isl in course.islands:
			if Vector2(p.x - isl.position.x, p.z - isl.position.z).length() < 130.0:
				near += 1
		if near < 2:
			always_islands = false
	_check(always_islands, "siempre hay islas a la vista")

	# Los bots dan la vuelta sin chocar islas.
	var island_crashes := [0]
	for r in race.racers:
		r.crashed.connect(func() -> void:
			for isl in course.islands:
				if Vector2(r.position.x - isl.position.x, r.position.z - isl.position.z).length() < isl.radius + 8.0:
					island_crashes[0] += 1
		)
	var finished := false
	var waves := m.get_node("WaveManager") as WaveManager
	var lead: Rider = race.racers[0]
	var gap := 0.0
	var longest_gap := 0.0
	var racing_time := 0.0
	for i in int(150.0 * FPS):
		if race.state == RaceManager.State.FINISHED:
			finished = true
			break
		if race.state == RaceManager.State.RACING and not race.finished(lead):
			racing_time += 1.0 / FPS
			if waves.has_wave_ahead(lead):
				gap = 0.0
			else:
				gap += 1.0 / FPS
				longest_gap = maxf(longest_gap, gap)
		await process_frame
	_check(
		racing_time > 10.0 and longest_gap < 3.0,
		"siempre hay una ola grande viniendo (el rato más largo sin ola: %.1f s)" % longest_gap
	)
	var all_done := true
	for r in race.racers:
		if not race.finished(r):
			all_done = false
	_check(finished or all_done, "los bots completan la vuelta del archipiélago")
	_check(island_crashes[0] <= 1, "casi sin chocar islas (%d)" % island_crashes[0])
	m.queue_free()
	await process_frame
	GameSettings.track_layout = GameSettings.TrackLayout.CLASSIC


func _test_atoll() -> void:
	print("Mapa el atolón (con tormenta):")
	GameSettings.track_layout = GameSettings.TrackLayout.ATOLL
	GameSettings.weather = GameSettings.Weather.STORM
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for level in [2, 2, 1]:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var track := course.track
	_check(track is PathTrack, "el atolón tiene recorrido propio")
	_check(
		track.length() > 1000.0 and track.length() < 1300.0,
		"una vuelta mide %.0f m" % track.length()
	)
	var volcano := false
	for isl in course.islands:
		if isl.volcano:
			volcano = true
	_check(volcano, "hay un volcán en el medio")
	_check(course.get_node_or_null("RockArch") != null, "hay un arco de roca sobre el paso norte")
	_check(course.get_node_or_null("Shipwreck") != null, "hay un barco hundido en la laguna")
	var clear := true
	for isl in course.islands:
		var lat := absf(track.lateral_of(isl.position))
		if lat < track.half_width + isl.radius + 0.5:
			clear = false
			print("    isla en %s muy cerca (%.1f m)" % [isl.position, lat])
	_check(clear, "las islas no pisan la pista")
	_check(course.geysers.size() >= 3, "hay géiseres en la laguna (%d)" % course.geysers.size())
	# Tormenta: cielo gris, poca luz, mar picado, rayos con trueno.
	var storm := course.storm
	_check(storm != null, "con clima tormenta hay tormenta")
	var env := (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var zenith: Color = env.sky.sky_material.get_shader_parameter("zenith_color")
	_check(zenith.s < 0.3 and zenith.v < 0.35, "el cielo está gris y oscuro")
	_check((m.get_node("Sun") as DirectionalLight3D).light_energy < 0.7, "hay menos luz de sol")
	var water := m.get_node("Water") as Water
	_check(water.waves.max_height() > 1.4, "el mar está mucho más picado (%.1f m)" % water.waves.max_height())
	var wm := water.shader_material()
	_check(
		wm.get_shader_parameter("deep_color") == Color(0.05, 0.15, 0.23)
		and wm.get_shader_parameter("sky_tint") == Color(0.5, 0.55, 0.62)
		and is_equal_approx(wm.get_shader_parameter("sky_reflect"), 0.6),
		"el agua de la tormenta tiene sus colores propios (no depende del día)"
	)
	storm.strike()
	var flashed := false
	var thunder := false
	for i in int(3.0 * FPS):
		if storm.flash > 0.3:
			flashed = true
		if root.get_node("AudioManager").recent_sfx.has("thunder"):
			thunder = true
		await process_frame
	_check(flashed, "un rayo ilumina todo")
	_check(thunder, "y después suena el trueno")
	_check(storm.last_strike.length() > 400.0, "los rayos caen lejos")
	_check(storm.rain.size() == (m.get_node("Views") as SplitScreen).views.size(), "llueve en cada pantalla")
	var drops := storm.rain[0].get_node("Drops") as CPUParticles3D
	_check(drops.emitting and not drops.local_coords, "la lluvia son gotas 3D que caen en el mundo")
	# Si una vista pierde la lluvia, vuelve sola.
	var lost := storm.rain[0]
	lost.get_parent().remove_child(lost)
	lost.free()
	await process_frame
	await process_frame
	_check(
		storm.rain.size() == (m.get_node("Views") as SplitScreen).views.size()
		and storm.rain[0].get_node_or_null("Drops") != null,
		"si se pierde la lluvia de una vista, vuelve"
	)
	_check(storm._rain_clock >= 0.0 and storm._rain_clock < 1.0, "el reloj de la lluvia no crece sin parar")
	_check(storm._rain_sound.playing, "se escucha la lluvia")
	var on_track := true
	for g in course.geysers:
		if absf(track.lateral_of(g.position)) > track.half_width - 2.0:
			on_track = false
	_check(on_track, "los géiseres están sobre la pista")

	# Un géiser que explota lanza al que pasa por arriba.
	var g0: Geyser = course.geysers[0]
	var r0: Rider = race.racers[0]
	race.skip_countdown()
	await process_frame
	g0._t = Geyser.CALM - 0.05
	var launched := [false]
	r0.geyser_launched.connect(func() -> void: launched[0] = true)
	var max_y := -100.0
	for i in int(2.5 * FPS):
		if not launched[0]:
			r0.position = Vector3(g0.position.x, r0.position.y, g0.position.z)
		max_y = maxf(max_y, r0.position.y)
		await process_frame
	_check(launched[0], "el géiser lanza al que está arriba cuando explota")
	_check(max_y > 4.0, "y lo manda alto (%.1f m)" % max_y)

	# Los bots dan la vuelta sin chocar islas.
	var island_crashes := [0]
	for r in race.racers:
		r.crashed.connect(func() -> void:
			for isl in course.islands:
				if Vector2(r.position.x - isl.position.x, r.position.z - isl.position.z).length() < isl.radius + 8.0:
					island_crashes[0] += 1
		)
	var finished := false
	for i in int(200.0 * FPS):
		if race.state == RaceManager.State.FINISHED:
			finished = true
			break
		await process_frame
	var all_done := true
	for r in race.racers:
		if not race.finished(r):
			all_done = false
	_check(finished or all_done, "los bots completan la vuelta del atolón")
	_check(island_crashes[0] <= 1, "casi sin chocar islas (%d)" % island_crashes[0])
	m.queue_free()
	await process_frame
	# La próxima carrera con sol arranca limpia.
	GameSettings.weather = GameSettings.Weather.SUNNY
	var sunny: Node = load("res://main.tscn").instantiate()
	root.add_child(sunny)
	await process_frame
	var sunny_env := (sunny.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(
		(sunny.get_node("Course") as Course).storm == null and sunny_env.sky.sky_material.get_shader_parameter("zenith_color") == null
		and absf(sunny_env.ambient_light_energy - 0.45) < 0.01
		and (sunny.get_node("Water") as Water).waves.max_height() < 1.0,
		"con sol, sin tormenta (cielo azul y mar normal)"
	)
	sunny.queue_free()
	await process_frame
	GameSettings.track_layout = GameSettings.TrackLayout.CLASSIC
