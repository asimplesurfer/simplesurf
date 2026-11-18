extends "res://tests/test_base.gd"
## Sensación de juego: contador de trucos, cámara con turbo, agua al girar.


func run() -> void:
	await _test_trick_counter()
	await _test_boost_camera()
	await _test_carve_spray()
	await _test_trick_preview()


## El HUD cuenta las vueltas del truco mientras está en el aire.
func _test_trick_counter() -> void:
	print("Contador de trucos:")
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	var r := race.humans()[0]
	var hud := (m.get_node("Views") as SplitScreen).huds[0]
	await _wait(0.5)
	# Lo tiramos bien alto para que dé el tiempo de varias vueltas.
	r.position.y += 1.0
	r.vertical_speed = 22.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	var seen: Array[int] = []
	var colors: Array[Color] = []
	for i in int(4.0 * FPS):
		if r.grounded:
			break
		if hud._trick_label.visible and not hud._trick_label.text in seen.map(func(n: int) -> String: return "×%d" % n):
			seen.append(r.live_spins)
			colors.append(hud._trick_label.get_theme_color("font_color"))
		await process_frame
	_set_action(&"p1_a", false)
	_check(seen.size() >= 2 and seen[0] == 1 and seen[1] == 2, "muestra x1, x2... mientras gira (%s)" % str(seen))
	_check(colors.size() >= 2 and colors[0] != colors[1], "y cambia de color al subir")
	await _wait(3.0)
	_check(not hud._trick_label.visible, "al caer se va")
	m.queue_free()
	await process_frame


## Con turbo la cámara se aleja (siempre a la misma distancia).
func _test_boost_camera() -> void:
	print("Cámara con turbo:")
	var saved_players := GameSettings.player_count
	GameSettings.player_count = 2
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	var cam := (m.get_node("Views") as SplitScreen).cameras[0]
	var r := cam.target
	await _wait(3.0)
	# Distancia real antes (a toda velocidad la cámara va un poco más atrás).
	var base := Vector2(cam.global_position.x - r.global_position.x, cam.global_position.z - r.global_position.z).length()
	# Con turbo también se aleja.
	r.add_nitro(Rider.NITRO_MAX)
	r.fire_turbo()
	await _wait(0.3)
	_check(cam.boosting() and cam._boost > 0.3, "con turbo la cámara se aleja")
	await _wait(1.0)
	var far := Vector2(cam.global_position.x - r.global_position.x, cam.global_position.z - r.global_position.z).length()
	_check(far > base + ChaseCamera.boost_pullback() * 0.7, "a la distancia de turbo (%.1f m, antes %.1f m)" % [far, base])
	m.queue_free()
	await process_frame
	GameSettings.player_count = saved_players


## Girar rápido levanta una pared de agua hacia afuera de la curva (solo se
## ve: no tumba a nadie).
func _test_carve_spray() -> void:
	print("Agua al girar:")
	var saved := [GameSettings.player_count, GameSettings.bot_count]
	GameSettings.player_count = 1
	GameSettings.bot_count = 1
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	var course := m.get_node("Course") as Course
	course.hazards_enabled = false
	course.bounds_enabled = false
	(m.get_node("WaveManager") as WaveManager).enabled = false
	(m.get_node("Water") as Water).clear_swells()
	var r: Rider = race.humans()[0]
	var bot: Rider = race.racers[1]
	bot.controls_locked = true
	var carve := (r.get_node("Visual") as RiderVisual)._carve
	await _wait(2.0)
	_set_action(&"p1_right", true)
	var shown := false
	var bot_fell := false
	for i in int(1.5 * FPS):
		# El rival, justo donde vuela el agua (afuera de la curva, atrás).
		bot.position = r.position - r.right() * 2.0 + r.forward() * -1.5
		if carve._sheet.visible:
			shown = true
		if bot.is_fallen():
			bot_fell = true
		await process_frame
	_set_action(&"p1_right", false)
	_check(shown, "girando rápido levanta agua hacia afuera de la curva")
	_check(not bot_fell, "y no tumba a nadie (solo se ve)")
	# Despacio, no.
	_set_action(&"p1_down", true)
	await _wait(3.0)
	_set_action(&"p1_right", true)
	await _wait(0.8)
	_check(not carve._sheet.visible or r.speed > 6.0, "despacio no levanta agua (%.1f m/s)" % r.speed)
	_set_action(&"p1_right", false)
	_set_action(&"p1_down", false)
	m.queue_free()
	await process_frame
	GameSettings.player_count = saved[0]
	GameSettings.bot_count = saved[1]


## Visor de trucos (tecla G): salta, hace el siguiente truco solo, en cámara
## lenta y con su nombre; al aterrizar todo vuelve a la normalidad.
func _test_trick_preview() -> void:
	print("Visor de trucos:")
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	var r := race.humans()[0]
	var hud := (m.get_node("Views") as SplitScreen).huds[0]
	await _wait(0.5)
	GameSession._preview_index = 0
	# En carrera la tecla G no anda (es de prueba): se llama directo.
	race.preview_next_trick()
	await process_frame
	_check(r.trick_preview and not r.grounded and Engine.time_scale < 1.0, "G hace saltar y pone cámara lenta")
	_check(hud._message.visible and "Giro de tabla" in hud._message.text, "muestra el nombre del truco (%s)" % hud._message.text)
	var kinds_seen := {}
	var max_units := 0.0
	for i in 600:
		await process_frame
		max_units = maxf(max_units, r.trick_units_now())
		if r.current_trick() >= 0:
			kinds_seen[r.current_trick()] = true
		if r.grounded and not r.trick_preview:
			break
	_check(kinds_seen.has(Rider.Trick.SPIN) and kinds_seen.size() == 1, "hace ese truco y solo ese (%s, %.2f tiempos)" % [str(kinds_seen.keys()), max_units])
	_check(not r.is_fallen() and is_equal_approx(Engine.time_scale, 1.0), "aterriza bien y vuelve la velocidad normal")
	await _wait(0.3)
	# En carrera la tecla G no anda (es de prueba): se llama directo.
	race.preview_next_trick()
	await process_frame
	_check(r.trick_kinds.size() == 1 and r.trick_kinds[0] == 1, "la próxima vez muestra el siguiente truco")
	for i in 600:
		await process_frame
		if r.grounded and not r.trick_preview:
			break
	Engine.time_scale = 1.0
	m.queue_free()
	await process_frame
