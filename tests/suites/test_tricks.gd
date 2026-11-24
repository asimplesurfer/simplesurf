extends "res://tests/test_base.gd"
## Modo trucos: isla en el medio, sin nitro, puntos por trucos, reloj para
## abajo, récords y menú.


func run() -> void:
	print("Modo trucos:")
	# No pisar los récords de quien juega.
	var saved := ""
	if FileAccess.file_exists(TrickAttack.SAVE_PATH):
		saved = FileAccess.get_file_as_string(TrickAttack.SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TrickAttack.SAVE_PATH))
	var saved_time := GameSettings.trick_time
	var saved_map := GameSettings.trick_map
	_set_action(&"p1_down", false)
	await process_frame

	_test_rules()
	await _test_match()
	await _test_menu()

	GameSettings.trick_time = saved_time
	GameSettings.trick_map = saved_map
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TrickAttack.SAVE_PATH))
	if saved != "":
		var f := FileAccess.open(TrickAttack.SAVE_PATH, FileAccess.WRITE)
		f.store_string(saved)


func _test_rules() -> void:
	_check(GameSettings.TRICK_TIMES[1] == 120, "por defecto la partida dura 2 minutos")
	GameSettings.trick_time = 1
	var config := RaceConfig.tricks()
	_check(config.mode == RaceConfig.Mode.TRICKS and config.trick_seconds == 120, "la configuración es del modo trucos, con el tiempo elegido")
	_check(config.slots.size() == 1 and config.slots[0].kind == RacerSlot.Kind.HUMAN, "por ahora, J1 solo (sin bots)")
	# Más combo vale más que proporcional.
	var p1 := TrickAttack.points_for(1, true)
	var p2 := TrickAttack.points_for(2, true)
	var p5 := TrickAttack.points_for(5, true)
	_check(p1 == 100 and p2 == 300 and p5 == 1500, "puntos: ×1 = 100, ×2 = 300, ×5 = 1500 (%d, %d, %d)" % [p1, p2, p5])
	_check(p2 > 2 * p1 and p5 > 5 * p1, "un combo vale más que los trucos sueltos")
	_check(TrickAttack.points_for(3, false) < TrickAttack.points_for(3, true), "caer justo da menos puntos que caer limpio")
	_check(TrickAttack.points_for(0, true) == 0, "sin trucos, sin puntos")
	_check(TrickAttack.format_score(12400) == "12.400" and TrickAttack.format_score(950) == "950", "puntos con separador de miles")
	_check(TrickAttack.format_clock(120.0) == "2:00" and TrickAttack.format_clock(65.3) == "1:06" and TrickAttack.format_clock(0.0) == "0:00",
		"el reloj en minutos y segundos")
	# Récords: los mejores 3, por mapa y duración.
	_check(TrickAttack.save_score("isla", 120, 500) == 0, "el primer puntaje es récord")
	_check(TrickAttack.save_score("isla", 120, 900) == 0, "uno mejor pasa a ser el récord")
	_check(TrickAttack.save_score("isla", 120, 700) == 1, "uno intermedio queda 2º")
	_check(TrickAttack.save_score("isla", 120, 100) == -1, "con 3 mejores, uno peor no entra")
	_check(TrickAttack.top_scores("isla", 120) == [900, 700, 500], "los mejores quedan ordenados")
	_check(TrickAttack.top_scores("isla", 60).is_empty(), "cada duración tiene sus propios récords")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TrickAttack.SAVE_PATH))


func _test_match() -> void:
	var config := RaceConfig.tricks()
	config.trick_seconds = 6
	var m: Node = load("res://tricks.tscn").instantiate()
	(m.get_node("Session") as GameSession).config = config
	root.add_child(m)
	await process_frame
	await process_frame
	var session := m.get_node("Session") as TrickAttack
	var world := m.get_node("World") as TrickWorld
	_check(session != null and world != null, "abre la escena del modo trucos")
	_check(get_nodes_in_group("island").size() == 1 and world.island_radius > 20.0, "hay una isla en el medio")
	_check(world.covers(0.0, 0.0) and not world.covers(world.island_radius + 10.0, 0.0), "la isla está en el centro y alrededor es mar")
	var r := session.racers[0]
	_rider = r
	_water = m.get_node("Water") as Water
	_check(session.racers.size() == 1 and r.is_human, "J1 solo")
	_check(not world.covers(r.position.x, r.position.z), "arranca en el agua")
	_check(not r.free_ride, "avanza solo, como en una carrera")
	var hud := (m.get_node("Views") as SplitScreen).huds[0]
	_check(hud._tricks_box.visible and not hud._nitro_box.visible, "el HUD muestra reloj y puntos, sin nitro")

	# Cuenta regresiva: quieto y el reloj no corre.
	_check(session.state == TrickAttack.State.COUNTDOWN and r.controls_locked, "arranca con cuenta regresiva")
	await _wait(0.5)
	_check(hud._center_label.visible and hud._center_label.text == "3", "se ve la cuenta regresiva (%s)" % hud._center_label.text)
	await _wait(0.5)
	_check(is_equal_approx(session.time_left, 6.0), "durante la cuenta el reloj no corre")
	await _wait(2.3)
	_check(session.state == TrickAttack.State.PLAYING and not r.controls_locked, "después de la cuenta se juega")
	await _wait(1.0)
	_check(session.time_left < 5.5 and session.time_left > 4.0, "el reloj cuenta para abajo (%.1f)" % session.time_left)
	_check(hud._clock_label.text == TrickAttack.format_clock(session.time_left), "el HUD muestra el reloj")

	# Sin nitro: los trucos no cargan y el turbo no sale.
	r.add_nitro(0.6)
	_check(r.nitro == 0.0, "los trucos no cargan nitro")
	await _press(&"p1_b")
	_check(not r.turbo_active and r.turbo_time <= 0.0, "no hay turbo")
	# La motivación sí.
	r.trigger_motivation()
	_check(r.motivation_timer > 0.0, "la motivación sigue (derrapar y tirar al de atrás)")

	# Puntos: limpio todo, justo la mitad, caerse nada.
	r.last_landing_clean = true
	r.trick_landed.emit(3)
	_check(session.score_of(r) == 600, "un ×3 limpio suma 600 (%d)" % session.score_of(r))
	r.last_landing_clean = false
	r.trick_landed.emit(2)
	_check(session.score_of(r) == 750, "un ×2 justo suma la mitad (%d)" % session.score_of(r))
	r.trick_failed.emit()
	_check(session.score_of(r) == 750, "caerse no suma")
	await process_frame
	_check(hud._score_label.text == "750 pts", "el HUD muestra los puntos (%s)" % hud._score_label.text)

	# La isla se choca: subirse a la arena tira al surfista afuera, en el agua.
	_teleport(Vector3(world.island_radius - 0.5, r.position.y, 0.0))
	await _wait(0.1)
	_check(r.is_fallen() and not world.covers(r.position.x, r.position.z), "subirse a la isla lo tira al agua, afuera")

	# Se termina el tiempo: quietos, resultados y récord.
	await _wait(session.time_left + 0.3)
	_check(session.state == TrickAttack.State.FINISHED and r.controls_locked, "al terminar el tiempo se frena todo")
	_check(session.time_left == 0.0 and hud._clock_label.text == "0:00", "el reloj queda en 0:00")
	var results := m.get_node("Results") as TrickResults
	_check(results._panel.visible, "aparecen los resultados")
	_check(results._list.text.contains("750"), "con el puntaje")
	_check(TrickAttack.top_scores("isla", 6) == [750], "se guarda el récord del mapa con ese tiempo")
	r.last_landing_clean = true
	r.trick_landed.emit(5)
	_check(session.score_of(r) == 750, "después del tiempo no suma más")
	m.queue_free()
	await process_frame


func _test_menu() -> void:
	var menu := CharacterSelect.new()
	menu.auto_start = false
	root.add_child(menu)
	await process_frame
	menu.go_setup()
	await process_frame
	var found := false
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Modo trucos":
			found = true
	_check(found, "en Armá la partida hay un botón Modo trucos")
	menu.go_tricks()
	await process_frame
	_check(menu.screen == "tricks", "Modo trucos abre su pantalla")
	var labels: Array[String] = []
	for b in menu.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	_check("Isla" in labels and "2 minutos" in labels, "se elige el mapa y el tiempo (%s)" % str(labels))
	var asked := [false]
	menu.tricks_requested.connect(func() -> void: asked[0] = true)
	menu.start_tricks()
	_check(asked[0] and menu.started_config.mode == RaceConfig.Mode.TRICKS, "¡A surfear! arranca el modo trucos")
	menu.queue_free()
	await process_frame
