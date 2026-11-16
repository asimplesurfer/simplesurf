extends "res://tests/test_base.gd"
## Contrarreloj: solo J1, olas siempre iguales, mejores tiempos y fantasma.


func run() -> void:
	print("Contrarreloj:")
	# No pisar los récords guardados de quien juega.
	var saved: Variant = null
	if FileAccess.file_exists(TimeTrial.SAVE_PATH):
		saved = TimeTrial.load_data()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.SAVE_PATH))
	var saved_players := GameSettings.player_count
	GameSettings.player_count = 1

	var config := RaceConfig.time_trial()
	_check(config.slots.size() == 1 and config.slots[0].kind == RacerSlot.Kind.HUMAN, "solo J1, sin bots")
	# Primer intento: con un personaje; lo termina enseguida.
	var first_char := GameSettings.character_for(0).to_dict()
	var c := GameSettings.character_for(0)
	c.hair_index = 14
	c.hat_index = 9
	var run1 := await _run_trial(3.0)
	var waves1: Array = run1[1]
	var data := TimeTrial.load_data()
	var entry: Dictionary = data.get(str(config.layout), {})
	_check((entry.get("top", []) as Array).size() == 1, "guarda el tiempo")
	_check(entry.has("ghost") and int(entry.ghost.character.hair) == 14, "guarda el fantasma con el personaje que hizo el récord")
	# Segundo intento con otro personaje: el fantasma sigue siendo el del récord.
	c.hair_index = 2
	c.hat_index = 0
	var run2 := await _run_trial(3.0, true)
	var waves2: Array = run2[1]
	_check(waves1.size() >= 1 and waves1 == waves2, "las olas salen en los mismos lugares en cada intento (%d)" % waves1.size())
	_check(run2[2], "aparece el fantasma, se mueve y no choca con nadie")
	_check(run2[3] == 14, "el fantasma tiene el personaje del récord, aunque se haya cambiado")
	_check(run2[4], "el HUD muestra el tiempo y el récord")
	var top := TimeTrial.top_times(config.layout)
	_check(top.size() == 2 and float(top[0].time) <= float(top[1].time), "los mejores tiempos quedan ordenados")
	# El menú tiene el modo.
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	root.add_child(menu)
	await process_frame
	menu.start_time_trial()
	_check(menu.started_config != null and menu.started_config.is_time_trial(), "el menú arranca la contrarreloj")
	menu.queue_free()
	await process_frame

	# Volver a dejar todo como estaba.
	GameSettings.characters[0] = CharacterData.from_dict(first_char)
	GameSettings.player_count = saved_players
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.SAVE_PATH))
	if saved is Dictionary and not (saved as Dictionary).is_empty():
		TimeTrial.save_data(saved)


## Un intento de `seconds` segundos, terminado a la fuerza. Devuelve
## [tiempo, centros de las primeras olas, fantasma ok, pelo del fantasma, hud ok].
func _run_trial(seconds: float, check_ghost: bool = false) -> Array:
	var m: Node = load("res://main.tscn").instantiate()
	for child in m.get_children():
		if child is GameSession:
			(child as GameSession).config = RaceConfig.time_trial()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	_set_action(&"p1_down", false)
	race.skip_countdown()
	var waves: Array = []
	var ghost_ok := false
	var start_pos := Vector3.ZERO
	var t := 0.0
	while t < seconds:
		await process_frame
		t += 1.0 / 60.0
		if check_ghost and race.time_trial.ghost and start_pos == Vector3.ZERO and race.time_trial.ghost.is_inside_tree():
			start_pos = race.time_trial.ghost.position
	waves = (m.get_node("WaveManager") as WaveManager).fixed_spawned.slice(0, 3)
	var hair := -1
	var hud_ok := false
	if check_ghost:
		var g := race.time_trial.ghost
		ghost_ok = g != null and not g.is_in_group("riders") and g.position.distance_to(start_pos) > 5.0
		if g:
			hair = (g.get_node("Visual") as RiderVisual).character.hair_index
		var hud := (m.get_node("Views") as SplitScreen).huds[0]
		hud_ok = hud._place_label.text.begins_with("0:0") and hud._lap_label.text.contains("Récord 0:0")
	race._finish(race.racers[0])
	await process_frame
	var time: float = race.finish_times.get(race.racers[0], 0.0)
	m.queue_free()
	await process_frame
	await process_frame
	return [time, waves, ghost_ok, hair, hud_ok]
