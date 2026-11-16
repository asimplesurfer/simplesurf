extends "res://tests/test_base.gd"
## Modo libre dentro de un mapa: con 0 bots, "Modo libre" abre el mapa elegido
## para recorrerlo (sin carrera), con olas, tormenta y boyas que se pueden
## atravesar (F).


func run() -> void:
	await _test_menu_choice()
	await _test_explore()


func _test_menu_choice() -> void:
	print("Modo libre desde el menú:")
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	root.add_child(menu)
	await process_frame
	var saved := GameSettings.bot_count
	GameSettings.bot_count = 0
	menu.start_sandbox()
	_check(menu.started_config.mode == RaceConfig.Mode.EXPLORE, "con 0 bots: modo libre dentro del mapa elegido")
	_check(menu.started_config.layout == GameSettings.track_layout, "en el mapa del menú")
	GameSettings.bot_count = 2
	menu.start_sandbox()
	_check(menu.started_config.mode == RaceConfig.Mode.SANDBOX, "con bots: el modo libre de siempre (mar abierto)")
	GameSettings.bot_count = saved
	# Elegir un mapa en la lista deja exactamente ese (antes pasaba al siguiente).
	var saved_layout := GameSettings.track_layout
	for want in [TrackMap.count() - 1, 0, mini(2, TrackMap.count() - 1)]:
		GameSettings.track_layout = GameSettings.TrackLayout.ARCHIPELAGO
		menu.set_track_layout(want)
		_check(GameSettings.track_layout == want, "elegir el mapa %d en el menú deja ese mapa" % want)
	GameSettings.track_layout = saved_layout
	menu.queue_free()
	await process_frame


func _test_explore() -> void:
	print("Explorar un mapa:")
	GameSettings.track_layout = GameSettings.TrackLayout.ARCHIPELAGO
	var config := RaceConfig.explore()
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var explore := race.get_node_or_null("Explore") as ExploreMode
	_check(config.slots.size() == GameSettings.player_count and explore != null, "solo las personas, sin bots")
	_check(race.state == RaceManager.State.RACING, "arranca sin cuenta regresiva")
	_check(race.free_ride() and race.racers[0].free_ride, "se maneja como en el modo libre")
	_check(course.get_node_or_null("Markers") != null and course.bounds_enabled, "el mapa está normal, con sus boyas")
	# F: las boyas se pueden atravesar (y otra vez F, vuelven a frenar).
	var r: Rider = race.racers[0]
	var outside := course.track.position_at(1.0, course.half_width + 12.0)
	_tap_f()
	await process_frame
	r.position = Vector3(outside.x, r.position.y, outside.z)
	await process_frame
	await process_frame
	var lat := absf(course.track.lateral_of(r.position))
	_check(explore.buoys_open and lat > course.half_width + 5.0, "con F se puede pasar las boyas (%.0f m del centro)" % lat)
	_tap_f()
	await process_frame
	r.position = Vector3(outside.x, r.position.y, outside.z)
	await process_frame
	await process_frame
	lat = absf(course.track.lateral_of(r.position))
	_check(not explore.buoys_open and lat < course.half_width, "otra vez F: las boyas vuelven a frenar")
	# Olas: X sube, Z baja.
	var before := explore.wave_level
	explore.set_wave_level(before - 1)
	_check(explore.wave_level == maxi(before - 1, 0) and GameSettings.sandbox_wave_level == explore.wave_level, "las olas se pueden bajar y subir")
	explore.set_wave_level(before)
	explore.set_storm(true)
	_check(course.storm != null, "se puede prender la tormenta")
	explore.set_storm(false)
	await process_frame
	_check(course.storm == null, "y apagarla")
	# Nunca termina.
	_check(config.laps >= 99, "no hay final")
	m.queue_free()
	await process_frame
	GameSettings.track_layout = GameSettings.TrackLayout.CLASSIC


func _tap_f() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
