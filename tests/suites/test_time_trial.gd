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
	var entry := TimeTrial.records_of(TrackMap.for_layout(config.layout))
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
	# R (o Select) reinicia en cualquier momento: otro intento enseguida.
	var m: Node = load("res://main.tscn").instantiate()
	for child in m.get_children():
		if child is GameSession:
			(child as GameSession).config = RaceConfig.time_trial()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	await _wait(0.5)
	var count_before := root.get_child_count()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_R
	ev.pressed = true
	race._unhandled_input(ev)
	await process_frame
	await process_frame
	var fresh: Node = root.get_child(root.get_child_count() - 1)
	_check(fresh != m and fresh.get_node_or_null("RaceManager") != null and not is_instance_valid(m) or (fresh != m and m.is_queued_for_deletion()),
		"R reinicia la contrarreloj en plena carrera")
	if is_instance_valid(fresh) and fresh != m:
		fresh.queue_free()
	if is_instance_valid(m):
		m.queue_free()
	await process_frame
	# El menú tiene el modo.
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	root.add_child(menu)
	await process_frame
	menu.start_time_trial()
	_check(menu.started_config != null and menu.started_config.is_time_trial(), "el menú arranca la contrarreloj")
	menu.queue_free()
	await process_frame

	_test_fixed_sets()
	_test_identity()
	_test_shape()
	_test_settings()

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
	# A mitad de camino, la diferencia con el récord (la misma carrera: casi 0).
	var mid_gap := NAN
	while t < seconds:
		await process_frame
		t += 1.0 / 60.0
		if check_ghost and race.time_trial.ghost and start_pos == Vector3.ZERO and race.time_trial.ghost.is_inside_tree():
			start_pos = race.time_trial.ghost.position
		if check_ghost and is_nan(mid_gap) and t > 1.5:
			mid_gap = race.time_trial.gap()
	waves = (m.get_node("WaveManager") as WaveManager).fixed_spawned.slice(0, 3)
	var hair := -1
	var hud_ok := false
	if check_ghost:
		var g := race.time_trial.ghost
		ghost_ok = g != null and not g.is_in_group("riders") and g.position.distance_to(start_pos) > 5.0
		if g:
			hair = (g.get_node("Visual") as RiderVisual).character.hair_index
		var hud := (m.get_node("Views") as SplitScreen).huds[0]
		# El récord, chico arriba de nuestro reloj (sin decir "Récord"), en
		# verde o rojo según vayamos mejor o peor.
		var rec: Label = hud._record_label
		var col: Color = rec.get_theme_color("font_color")
		hud_ok = (
			hud._place_label.text.begins_with("0:0") and rec.visible and rec.text.begins_with("0:0")
			and not hud._lap_label.text.contains("Récord")
			and (col == hud.AHEAD_COLOR or col == hud.BEHIND_COLOR or col == Color.WHITE)
			and not is_nan(mid_gap) and absf(mid_gap) < 0.6
		)
	race._finish(race.racers[0])
	await process_frame
	var time: float = race.finish_times.get(race.racers[0], 0.0)
	m.queue_free()
	await process_frame
	await process_frame
	return [time, waves, ghost_ok, hair, hud_ok]


## Olas fijas en series: más olas y más grandes que en la carrera, siempre iguales.
func _test_fixed_sets() -> void:
	var course := Course.new()
	course.map = TrackMap.for_layout(0)
	var a := WaveManager.new()
	var b := WaveManager.new()
	a._build_fixed(course, 1000.0)
	b._build_fixed(course, 1000.0)
	_check(a._fixed == b._fixed, "las olas fijas son siempre las mismas")
	var big := 0
	var total_amp := 0.0
	for f in a._fixed:
		total_amp += float(f[3])
		if float(f[3]) >= WaveManager.FIXED_LAST_AMP.x:
			big += 1
	var avg := total_amp / maxf(a._fixed.size(), 1)
	_check(a._fixed.size() >= 25, "hay muchas olas (%d en 1 km)" % a._fixed.size())
	_check(avg > 4.0 and big >= 8, "y son grandes (promedio %.1f m, %d de las grandes)" % [avg, big])
	course.free()
	a.free()
	b.free()


func _record(time: float) -> Dictionary:
	return {"time": time, "date": "", "character": {}}


## Los récords van por nombre de mapa, con su número como salvavidas.
func _test_identity() -> void:
	var maps := TrackMap.all()
	var atoll := maps[TrackMap.index_of("atoll")]
	# Formato de antes: por lugar en la lista. Pasa al mapa de ese lugar.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.SAVE_PATH))
	TimeTrial.save_data({str(TrackMap.index_of("atoll")): {"top": [_record(90.0)], "ghost": {"time": 90.0}}})
	var data := TimeTrial.load_data()
	_check(int(data.get("format", 0)) == TimeTrial.SAVE_FORMAT and (data.maps as Dictionary).has("atoll"),
		"los récords del formato de antes pasan al mapa por su nombre")
	var migrated: Dictionary = data.maps.atoll.versions[0]
	_check(float(migrated.top[0].time) == 90.0 and migrated.has("ghost"), "y quedan guardados (con su fantasma)")
	_check(TimeTrial.records_of(atoll).is_empty(),
		"pero hechos con las olas de antes de las series, quedan archivados (no se comparan)")
	# Los que siguen hacen de cuenta que son de las olas de ahora.
	migrated["waves"] = WaveManager.FIXED_VERSION
	_check(int(TimeTrial._read().get("format", 0)) == TimeTrial.SAVE_FORMAT, "el archivo queda guardado en el formato nuevo")
	# Reordenar: el mapa se encuentra por nombre y el número se actualiza.
	data.maps.atoll.order = 77
	_check(not TimeTrial._version(data, atoll, false).is_empty() and int(data.maps.atoll.order) == atoll.order,
		"si el mapa cambió de número, sus récords se encuentran por el nombre y el número se actualiza")
	# Renombrar el archivo: se encuentra por el número y pasa al nombre nuevo.
	data.maps["atolon_viejo"] = data.maps.atoll
	data.maps.erase("atoll")
	var v := TimeTrial._version(data, atoll, false)
	_check(not v.is_empty() and (data.maps as Dictionary).has("atoll") and not (data.maps as Dictionary).has("atolon_viejo"),
		"si el mapa cambió de nombre, sus récords se encuentran por el número y pasan al nombre nuevo")
	# Un mapa borrado con otro número: sus récords quedan guardados, nadie los adopta.
	data.maps["borrado"] = {"order": 999, "versions": [{"shape": {}, "top": [_record(10.0)]}]}
	TimeTrial._version(data, atoll, false)
	_check((data.maps as Dictionary).has("borrado"), "los récords de un mapa que ya no está quedan guardados")
	# El número de un mapa que existe nunca se adopta (cada uno tiene los suyos).
	var other := maps[TrackMap.index_of("classic")]
	data.maps["otro"] = {"order": other.order, "versions": []}
	data.maps.erase("classic")
	var mine := TimeTrial._map_entry(data, atoll, false)
	_check(not mine.is_empty() and (data.maps as Dictionary).has("otro"), "no se adoptan récords con el número de otro mapa")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TimeTrial.SAVE_PATH))


## La huella: un récord vale solo en la pista donde se hizo.
func _test_shape() -> void:
	var atoll := TrackMap.all()[TrackMap.index_of("atoll")]
	var shape := atoll.track_shape()
	_check(TrackMap.same_shape(shape, shape), "una pista es igual a sí misma")
	# Un retoque chiquito (un punto movido 1 m) sigue siendo la misma pista.
	var nudged := TrackMap.from_dict(atoll.to_dict())
	nudged.path[3] += Vector2(1.0, 0.0)
	_check(TrackMap.same_shape(shape, nudged.track_shape()), "mover un punto 1 m no cambia la pista para los récords")
	var moved := TrackMap.from_dict(atoll.to_dict())
	moved.path[3] += Vector2(40.0, 25.0)
	_check(not TrackMap.same_shape(shape, moved.track_shape()), "cambiar el recorrido sí")
	var laps := TrackMap.from_dict(atoll.to_dict())
	laps.laps += 1
	_check(not TrackMap.same_shape(shape, laps.track_shape()), "cambiar las vueltas también")
	var wide := TrackMap.from_dict(atoll.to_dict())
	wide.half_width += 4.0
	_check(not TrackMap.same_shape(shape, wide.track_shape()), "y cambiar el ancho")
	var rocks := TrackMap.from_dict(atoll.to_dict())
	rocks.rock_count += 5
	rocks.ring_count += 5
	_check(TrackMap.same_shape(shape, rocks.track_shape()), "las rocas y los aros no cuentan")
	# Pista cambiada: los récords viejos quedan archivados; si vuelve, vuelven.
	moved.id = atoll.id
	moved.order = atoll.order
	var data := {"format": TimeTrial.SAVE_FORMAT, "maps": {}}
	TimeTrial._version(data, atoll, true)["top"] = [_record(80.0)]
	_check(TimeTrial._version(data, moved, false).is_empty(), "con la pista cambiada no aparecen los récords viejos")
	TimeTrial._version(data, moved, true)["top"] = [_record(95.0)]
	_check((data.maps.atoll.versions as Array).size() == 2, "los viejos quedan archivados, no se borran")
	_check(float(TimeTrial._version(data, atoll, false).top[0].time) == 80.0, "si la pista vuelve a ser la de antes, vuelven sus récords")
	# El anillo también tiene huella.
	var ring := TrackMap.all()[TrackMap.index_of("classic")]
	_check(TrackMap.same_shape(ring.track_shape(), ring.track_shape()) and not TrackMap.same_shape(ring.track_shape(), shape),
		"el anillo tiene su propia huella")


## El mapa elegido se guarda por nombre y número.
func _test_settings() -> void:
	var saved := GameSettings.track_layout
	# No pisar la configuración de quien juega (ni la que miran otros tests).
	var saved_file := FileAccess.get_file_as_string(GameSettings.PATH) if FileAccess.file_exists(GameSettings.PATH) else ""
	var atoll := TrackMap.all()[TrackMap.index_of("atoll")]
	_check(TrackMap.find("atoll", 999) == TrackMap.index_of("atoll"), "un mapa se encuentra por su nombre")
	_check(TrackMap.find("no_existe", atoll.order) == TrackMap.index_of("atoll"), "o por su número si el nombre ya no está")
	_check(TrackMap.find("no_existe", 999) == TrackMap.default_index(), "si no está ninguno, el mapa por defecto")
	GameSettings.track_layout = TrackMap.index_of("atoll")
	GameSettings.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.PATH)
	_check(cfg.get_value("gameplay", "map", "") == "atoll" and int(cfg.get_value("gameplay", "map_order", -1)) == atoll.order
		and not cfg.has_section_key("gameplay", "track_layout"),
		"la configuración guarda el mapa por nombre y número")
	GameSettings.track_layout = saved
	if saved_file.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	else:
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_string(saved_file)
		f.close()
