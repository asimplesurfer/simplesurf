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
	await _test_launches()
	await _test_waves_and_lip()
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


## Olas de tamaños mezclados alrededor (no hacia el surfista), sin techo en
## los saltos (y la cámara lo sigue) y la ola de borde.
func _test_waves_and_lip() -> void:
	# Tamaños: chicas 4-5 m (ya más altas que las de antes), medianas 6-8, gigantes 10-13.
	_check(WaveManager.trick_amplitude(0.1, 0.0) >= 4.0 and WaveManager.trick_amplitude(0.1, 1.0) <= 5.0, "olas chicas de 4 a 5 m")
	_check(WaveManager.trick_amplitude(0.7, 0.5) >= 6.0 and WaveManager.trick_amplitude(0.7, 0.5) <= 8.0, "olas medianas de 6 a 8 m")
	_check(WaveManager.trick_amplitude(0.95, 1.0) >= 12.0, "olas gigantes de hasta 13 m")
	var config := RaceConfig.tricks()
	config.trick_seconds = 300
	var m: Node = load("res://tricks.tscn").instantiate()
	(m.get_node("Session") as GameSession).config = config
	root.add_child(m)
	await process_frame
	await process_frame
	var session := m.get_node("Session") as TrickAttack
	var waves := m.get_node("WaveManager") as WaveManager
	var water := m.get_node("Water") as Water
	_water = water
	var r := session.racers[0]
	_rider = r
	session._lip_timer = 1e9
	session.start()
	_check(waves.trick_mode and is_equal_approx(waves.amplitude_scale, 1.0), "las olas son las del modo trucos")
	# Que salgan varias y mirar tamaños y direcciones.
	await _wait(12.0)
	var away := false
	for sw in water.swells:
		var to_rider := Vector2(r.position.x, r.position.z) - sw.center
		if sw.direction.dot(to_rider.normalized()) < 0.0:
			away = true
	_check(water.swells.size() >= 3, "salen varias olas a la vez (%d)" % water.swells.size())
	# Los tamaños se sortean: además de las que hay, se arman varias más (sin
	# agregarlas) para no depender de la suerte.
	var tiers := {}
	for sw in water.swells:
		tiers[0 if sw.max_amplitude < 5.5 else (1 if sw.max_amplitude < 9.0 else 2)] = true
	for k in 40:
		var extra := waves._make_trick_swell()
		if extra:
			tiers[0 if extra.max_amplitude < 5.5 else (1 if extra.max_amplitude < 9.0 else 2)] = true
	_check(tiers.size() >= 2, "salen de distintos tamaños mezclados (%s)" % str(tiers.keys()))
	var smallest := 99.0
	for sw in water.swells:
		smallest = minf(smallest, sw.max_amplitude)
	_check(smallest >= 4.0, "ni las más chicas bajan de 4 m (%.1f)" % smallest)
	_check(away, "no todas vienen hacia el surfista")
	_check(not r.air_ceiling, "sin techo invisible en los saltos")

	# Lo que se siente es lo que se ve: con una ola de 12 m rompiendo (el labio
	# corre la cresta muchos metros hacia adelante), la altura de la física es
	# la del agua dibujada.
	var big := Swell.new()
	big.match_drawn = true
	big.center = Vector2(r.position.x + 300.0, r.position.z)
	big.direction = Vector2.RIGHT
	big.max_amplitude = 12.0
	big.width = 12.0 * 1.8
	big.half_length = 40.0
	big.lifetime = 100.0
	big.age = 50.0
	big.update(0.0)
	# La superficie dibujada de arriba: cada punto de la loma corrido hacia
	# adelante (como en el shader), y en cada franja de 0,5 m lo más alto.
	var top_h := {}
	for k in 3000:
		var u0 := -big.width * 4.0 + k * big.width * 8.0 / 3000.0
		var n := exp(-pow(u0 / big.width, 2.0))
		var x := u0 + big.lean() * n * n * n
		var bin := int(floor(x / 0.5))
		if big.amplitude * n > float((top_h.get(bin, [0.0, -1.0]) as Array)[1]):
			top_h[bin] = [x, big.amplitude * n]
	var worst := 0.0
	var worst_plain := 0.0
	for bin in top_h:
		var pick: Array = top_h[bin]
		var at: Vector2 = big.center + big.direction * float(pick[0])
		worst = maxf(worst, absf(big.height_at(at) - float(pick[1])))
		big.match_drawn = false
		worst_plain = maxf(worst_plain, absf(big.height_at(at) - float(pick[1])))
		big.match_drawn = true
	_check(worst < 0.25, "la ola que se siente es la que se ve (diferencia: %.2f m; sin esto: %.1f m)" % [worst, worst_plain])
	# (Si justo no hay lugar libre no sale ninguna: se prueba varias veces.)
	var sample: Swell = null
	for k in 40:
		sample = waves._make_trick_swell()
		if sample:
			break
	_check(sample != null and sample.match_drawn, "todas las olas del modo trucos son así")

	# Sin techo: un salto muy fuerte sube mucho más que el techo de carrera, y
	# la cámara lo sigue siempre.
	water.clear_swells()
	waves.enabled = false
	await _wait(0.5)
	r.vertical_speed = 26.0
	r.grounded = false
	r.state_machine.transition_to(&"airborne")
	var cam := (m.get_node("Views") as SplitScreen).cameras[0]
	var top := 0.0
	var always_seen := true
	for i in 200:
		await process_frame
		top = maxf(top, r.position.y - water.height_at(r.position.x, r.position.z))
		if not cam.is_position_in_frustum(r.global_position + Vector3.UP * 0.8):
			always_seen = false
		if r.grounded:
			break
	# Sin freno, la altura es la de la parábola (v² / 2g): con techo no pasaría
	# de air_max_height.
	var free_top := 26.0 * 26.0 / (2.0 * r.stats.gravity)
	_check(top > free_top * 0.85 and top > r.stats.air_max_height * 2.0, "sube sin techo (%.0f m; sin freno: %.0f)" % [top, free_top])
	_check(always_seen, "la cámara lo tiene en cuadro todo el salto")
	_rider = r
	await _wait_until_state(&"riding", 6.0)

	# Toda ola alta (de LIP_MIN_HEIGHT m o más) se engancha si se llega a su
	# cresta desde atrás; las chicas no (esas lanzan).
	var vis := r.get_node("Visual") as RiderVisual
	var hud := (m.get_node("Views") as SplitScreen).huds[0]
	var audio := root.get_node_or_null("AudioManager")
	var tall := _tall_wave(r, 8.0)
	await _wait(0.2)
	_place_on(tall, 3.0, 0.0)
	_check(not session.try_catch_lip(r, tall), "desde adelante no engancha")
	var limit := tall.half_length - tall.edge - 2.0
	_place_on(tall, -1.0, -(limit - 3.0))
	await _wait(0.1)
	_check(r.on_lip() and r.state_machine.current_name == &"lip", "una ola alta cualquiera, desde atrás, en la cresta, lo engancha sola")
	var expected := r.lip_time_left
	_check(expected > 8.0, "dura lo que le queda de cresta por recorrer (%.1f s)" % expected)
	var start_w := tall.local_coords(Vector2(r.position.x, r.position.z)).y
	await _wait(1.0)
	_check(r.position.y > 6.0, "va arriba, en el borde (%.1f m)" % r.position.y)
	_check(absf(tall.local_coords(Vector2(r.position.x, r.position.z)).y - start_w) > 8.0, "lo lleva a lo largo de la cresta")
	_check(r.drift_side != 0, "con la tabla de costado, raspando")
	_check(vis._body.anim == &"lip", "con la pose del borde (%s)" % vis._body.anim)
	_check(absf(vis._drift_yaw) > 0.3, "la tabla va en diagonal (%.2f rad)" % vis._drift_yaw)
	var fwd := r.forward()
	var along := Vector2(fwd.x, fwd.z).dot(Vector2(-tall.direction.y, tall.direction.x))
	_check(absf(along) > 0.99, "mira derecho a lo largo de la cresta")
	_check(hud._lip_meter.visible, "el HUD muestra la barra de equilibrio")
	# Mantiene el equilibrio con el stick hasta el final de la cresta. A mitad
	# de camino la cámara está dando la vuelta y la música subió.
	var before := session.score_of(r)
	var clock := session.time_left + 1.1
	var t := 0.0
	var cam_around := false
	var music_up := false
	while r.on_lip() and t < 20.0:
		var b := r.lip_balance
		_set_action(&"p1_left", b > 0.05)
		_set_action(&"p1_right", b < -0.05)
		await get_tree().physics_frame
		t = clock - session.time_left
		if r.lip_progress > 0.4 and r.lip_progress < 0.6:
			var cd := r.global_position - cam.global_position
			if Vector2(cd.x, cd.z).normalized().dot(Vector2(r.forward().x, r.forward().z)) < 0.0:
				cam_around = true
			if audio and float(audio.get("target_db")) > -4.0:
				music_up = true
	_set_action(&"p1_left", false)
	_set_action(&"p1_right", false)
	_check(absf(t - expected) < 0.6, "termina al llegar a la punta de la cresta (%.1f s; esperado %.1f)" % [t, expected])
	_check(not r.is_fallen(), "aguantando el equilibrio no se cae")
	_check(cam_around, "mientras tanto la cámara da la vuelta alrededor")
	_check(music_up, "y la música sube")
	var gained := session.score_of(r) - before
	_check(gained >= TrickAttack.LIP_BONUS + 1000, "puntos por recorrerla y el bonus (%d)" % gained)
	_check(r.motivation_timer > 0.0 and not r.grounded, "al completarla sale disparado, con motivación")
	await _wait(0.3)
	var cd2 := r.global_position - cam.global_position
	_check(Vector2(cd2.x, cd2.z).normalized().dot(Vector2(r.forward().x, r.forward().z)) > 0.8, "al soltarlo, la cámara ya volvió detrás")

	# Una chica desde atrás no engancha.
	await _wait_until_state(&"riding", 8.0)
	var small_w := _tall_wave(r, 4.5)
	await _wait(0.2)
	_place_on(small_w, -1.0, 0.0)
	_check(not session.try_catch_lip(r, small_w), "una ola chica no engancha (esa lanza)")

	# Otra alta: sin tocar el stick se cae, pero se queda con lo que hizo.
	await _wait_until_state(&"riding", 8.0)
	await _wait(1.0)
	var other := _tall_wave(r, 9.0)
	await _wait(0.2)
	_place_on(other, -1.0, -(other.half_length - other.edge - 5.0))
	await _wait(0.1)
	_check(r.on_lip(), "engancha otra")
	before = session.score_of(r)
	await _wait(9.0)
	_check(r.is_fallen(), "sin corregir con el stick pierde el equilibrio y se cae")
	_check(session.score_of(r) > before and session.score_of(r) - before < TrickAttack.LIP_BONUS, "se queda con los puntos que hizo, sin bonus (%d)" % (session.score_of(r) - before))
	_check(not other.keep and other.lip_used, "cada ola se usa una sola vez")

	# La ola de borde especial (apagada por ahora: LIP_SPECIAL_WAVES) sigue
	# andando: rocío en la cresta y flecha en pantalla.
	await _wait_until_state(&"riding", 8.0)
	var nl := waves.spawn_lip_wave(Vector2(r.position.x, r.position.z))
	_check(nl != null and nl.lip and nl.half_length > 60.0, "la ola de borde especial: larga")
	session.lip_wave = nl
	var spray := session.add_lip_spray(nl) if nl else null
	await _wait(3.5)
	if spray and nl:
		var on_top := nl.local_coords(Vector2(spray.global_position.x, spray.global_position.z))
		_check(spray._particles.emitting and absf(on_top.y) < 1.0 and spray.global_position.y > nl.amplitude * 0.8,
			"con rocío que sale de la cresta, de punta a punta")
		var from_wave := r.global_position - Vector3(nl.center.x, 0.0, nl.center.y)
		r.heading = atan2(-from_wave.x, -from_wave.z)
		await _wait(1.0)
		_check(hud._lip_pointer.visible, "si no se la ve, una flecha apunta hacia ella")
	m.queue_free()
	await process_frame


## Las olas lanzan según su tamaño (una chica, poco; una gigante, mucho) y
## también pasándolas por arriba desde atrás.
func _test_launches() -> void:
	var config := RaceConfig.tricks()
	config.trick_seconds = 300
	var m: Node = load("res://tricks.tscn").instantiate()
	(m.get_node("Session") as GameSession).config = config
	root.add_child(m)
	await process_frame
	await process_frame
	var session := m.get_node("Session") as TrickAttack
	var waves := m.get_node("WaveManager") as WaveManager
	_water = m.get_node("Water") as Water
	var r := session.racers[0]
	_rider = r
	session._lip_timer = 1e9
	waves.enabled = false
	session.start()
	_check(r.wave_sized_launch, "en el modo trucos las olas lanzan según su tamaño")
	var small := await _launch_apex(r, 4.5, false)
	var big := await _launch_apex(r, 12.0, false)
	_check(small > 0.5 and small < 4.5, "una ola chica (4,5 m) de frente levanta poco (%.1f m)" % small)
	_check(big > small * 2.0, "una gigante (12 m) levanta mucho más (%.1f m)" % big)
	var back_small := await _launch_apex(r, 4.5, true)
	var back_big := await _launch_apex(r, 12.0, true)
	_check(back_small > 0.8, "pasando una ola chica por arriba desde atrás, sale volando (%.1f m)" % back_small)
	_check(back_big > back_small * 1.8, "desde atrás, la gigante también levanta más (%.1f m)" % back_big)
	m.queue_free()
	await process_frame


## Surfea una ola de `amp` metros, de frente (viene hacia él) o desde atrás
## (va para el mismo lado, más lenta). Devuelve cuánto subió desde donde
## despegó (0 si no despegó).
func _launch_apex(r: Rider, amp: float, from_behind: bool) -> float:
	_water.clear_swells()
	var base := Vector2(600.0 + randf() * 50.0, 300.0)
	r.position = Vector3(base.x, _water.height_at(base.x, base.y), base.y)
	r.set_recovery_stage(Rider.RecoveryStage.STANDING)
	r.state_machine.transition_to(&"riding")
	r.heading = 0.0
	r.vertical_speed = 0.0
	r.speed = r.stats.max_speed
	var fwd := Vector2(r.forward().x, r.forward().z)
	var sw := Swell.new()
	sw.match_drawn = true
	sw.max_amplitude = amp
	sw.width = amp * 1.8
	sw.half_length = 40.0
	sw.lifetime = 60.0
	sw.grow_time = 0.1
	sw.age = 0.1
	if from_behind:
		sw.center = base + fwd * (amp * 1.8 * 2.5)
		sw.direction = fwd
		sw.speed = 3.0
	else:
		sw.center = base + fwd * (amp * 1.8 * 3.0 + 10.0)
		sw.direction = -fwd
		sw.speed = 4.0
	sw.update(0.0)
	_water.add_swell(sw)
	var top := 0.0
	var flew := false
	var takeoff := 0.0
	for i in 600:
		var y_before := r.position.y
		await get_tree().physics_frame
		if not r.grounded:
			if not flew:
				takeoff = y_before
			flew = true
			top = maxf(top, r.position.y - takeoff)
		elif flew:
			break
	_water.clear_swells()
	return top


## Una ola alta del modo trucos, ya crecida, a un costado del surfista (lejos
## de la isla), larga y que dura (para recorrerla).
func _tall_wave(r: Rider, amp: float) -> Swell:
	_water.clear_swells()
	var base := Vector2(r.position.x, r.position.z)
	if base.length() < 200.0:
		base = base.normalized() * 260.0 if base.length() > 1.0 else Vector2(260.0, 0.0)
	var sw := Swell.new()
	sw.match_drawn = true
	sw.max_amplitude = amp
	sw.width = amp * 1.8
	sw.half_length = 70.0
	sw.lifetime = 120.0
	sw.grow_time = 0.1
	sw.age = 0.1
	sw.speed = 4.0
	sw.direction = Vector2.RIGHT.rotated(randf() * TAU)
	sw.center = base
	sw.update(0.0)
	_water.add_swell(sw)
	# Lejos, atrás de la ola (que no lo enganche antes de tiempo).
	var away: Vector2 = base - sw.direction * (sw.width * 5.0)
	r.position = Vector3(away.x, _water.height_at(away.x, away.y), away.y)
	r.heading = atan2(sw.direction.x, sw.direction.y)
	return sw


## Pone al surfista sobre la ola `s`: `u` metros hacia adelante de la cresta
## (negativo: atrás) y `w` a lo largo, apoyado en el agua y yendo con la ola.
func _place_on(s: Swell, u: float, w: float) -> void:
	var p := s.center + s.direction * (s.crest_u() + u) + Vector2(-s.direction.y, s.direction.x) * w
	_rider.position = Vector3(p.x, _water.height_at(p.x, p.y), p.y)
	_rider.vertical_speed = 0.0
	_rider.heading = atan2(-s.direction.x, -s.direction.y)


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
