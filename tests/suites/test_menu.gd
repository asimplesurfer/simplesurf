extends "res://tests/test_base.gd"
## Opciones por defecto y menú: título (JUGAR y cuántos juegan), tarjetas de
## cada jugador (cada uno se une con su dispositivo y arma su surfista) y
## armado de partida.


func run() -> void:
	_check(
		defaults.jump_style == GameSettings.JumpStyle.WAVES,
		"por defecto el salto es de olas (saltito + pop)"
	)
	_check(
		defaults.wave_mode == GameSettings.WaveMode.SURGES,
		"por defecto las olas son grandes que aparecen solas"
	)
	_check(
		defaults.track_layout == GameSettings.TrackLayout.ARCHIPELAGO,
		"por defecto el mapa es el archipiélago"
	)
	_test_glyphs()
	await _test_menu()


## Los textos del juego solo usan letras comunes (hasta Latin-1: tildes, ñ, ¡,
## º, ×...). Símbolos como ◀ ▶ ▲ ▼ ← no están en la letra del navegador y se
## ven como cajitas con el código.
func _test_glyphs() -> void:
	var bad: Array[String] = []
	var dirs := ["res://ui", "res://core", "res://world", "res://characters", "res://effects"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var lines := FileAccess.get_file_as_string(dir.path_join(f)).split("\n")
			for n in lines.size():
				var line := lines[n].strip_edges()
				if line.begins_with("#"):
					continue
				var in_str := false
				for ch in line:
					if ch == "\"":
						in_str = not in_str
					elif in_str and ch.unicode_at(0) > 0xFF:
						bad.append("%s:%d %s" % [f, n + 1, ch])
						break
	_check(bad.is_empty(), "los textos no usan símbolos que el navegador no tiene %s" % str(bad))


## Botón del mando `button` del dispositivo `device`.
func _pad(device: int, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _test_menu() -> void:
	print("Menú:")
	var saved_count := GameSettings.player_count
	GameSettings.player_count = 1
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	var started := [false]
	menu.start_requested.connect(func() -> void: started[0] = true)
	_set_action(&"p1_down", false)
	root.add_child(menu)
	await process_frame
	await process_frame
	_check(menu.screen == "title" and not menu.choosing_count, "arranca en el título con JUGAR")
	await _key(KEY_SPACE)
	_check(menu.choosing_count, "JUGAR muestra cuántos juegan")
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	_check(GameSettings.player_count == 3, "con ▶ sube la cantidad (%d)" % GameSettings.player_count)
	for i in 3:
		await _key(KEY_RIGHT)
	_check(GameSettings.player_count == 4, "hasta 4 jugadores")
	for i in 5:
		await _key(KEY_LEFT)
	_check(GameSettings.player_count == 1, "y como mínimo 1")
	await _key(KEY_RIGHT)
	await _key(KEY_SPACE)
	_check(menu.screen == "players" and menu.cards.size() == 2, "con 2 jugadores hay 2 tarjetas")
	_check(not menu.cards[0].joined() and not menu.cards[1].joined(), "las tarjetas empiezan libres")

	# Se une el teclado (J1) y un mando (J2).
	await _key(KEY_SPACE)
	_check(menu.cards[0].device == InputSetup.KEYBOARD, "ESPACIO une el teclado a la primera tarjeta")
	_check(menu._join(InputSetup.KEYBOARD) == null and not menu.cards[1].joined(), "el teclado es de una sola persona")
	await _pad(7, JOY_BUTTON_A)
	_check(menu.cards[1].device == 7, "el botón de abajo de un mando lo une a la siguiente")

	# J1 (teclado) va al pelo y cambia el peinado; J2 (mando) cambia la tabla, a la vez.
	var c1 := menu.cards[0]
	var c2 := menu.cards[1]
	var d1 := GameSettings.character_for(0)
	var d2 := GameSettings.character_for(1)
	for i in 3:
		await _key(KEY_RIGHT)
	_check(c1.cat_index == 3 and PlayerCard.ICONS[3][0] == "Pelo", "◀ ▶ se mueve entre los íconos (Pelo) (%d)" % c1.cat_index)
	await _key(KEY_SPACE)
	_check(c1.in_category, "ESPACIO entra a la categoría")
	var hair := d1.get_option("hair")
	await _key(KEY_RIGHT)
	_check(d1.get_option("hair") != hair, "adentro, ▶ cambia el peinado")
	var hair_color := d1.get_option("hair_color")
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	_check(c1.row == 1 and d1.get_option("hair_color") != hair_color, "▼ pasa a la fila del color y ▶ lo cambia")
	await _wait(0.6)
	_check(c1.zoom() > 0.9, "en el pelo, la cámara de la tarjeta se acerca a la cara")
	await _key(KEY_ESCAPE)
	_check(not c1.in_category and c1.joined(), "ESC vuelve a los íconos")
	var board1 := d1.get_option("board")
	for i in 7:
		await _pad(7, JOY_BUTTON_DPAD_RIGHT)
	await _pad(7, JOY_BUTTON_A)
	var board := d2.get_option("board")
	await _pad(7, JOY_BUTTON_DPAD_RIGHT)
	_check(c2.cat_index == 7 and d2.get_option("board") != board, "el mando de J2 cambia su tabla al mismo tiempo")
	_check(d1.get_option("board") == board1 and c1.cat_index == 3, "sin tocar la de J1")
	# Cuerpo: barras.
	await _key(KEY_LEFT)  # J1 está afuera: mueve entre íconos (Pelo -> Piel)
	_check(c1.cat_index == 2, "J1 sigue en sus íconos")
	c1.cat_index = 1
	await _key(KEY_SPACE)
	var w := d1.weight
	await _key(KEY_RIGHT if w < 1.0 else KEY_LEFT)
	_check(not is_equal_approx(d1.weight, w), "la barra de cuerpo se mueve con < >")
	await _key(KEY_ESCAPE)
	var before := d1.to_dict()
	await _key(KEY_R)
	_check(d1.to_dict() == before, "ya no hay botón de personaje al azar (R no cambia nada)")

	# Listos: cuando todos están listos, sigue.
	await _key(KEY_ENTER)
	_check(c1.is_ready and menu.screen == "players", "ENTER: J1 listo (falta J2)")
	await _pad(7, JOY_BUTTON_B)
	await _pad(7, JOY_BUTTON_START)
	_check(menu.screen == "setup", "con todos listos pasa a armar la partida")
	_check(
		InputSetup.assigned_device(0) == InputSetup.KEYBOARD and InputSetup.assigned_device(1) == 7,
		"cada jugador queda con su dispositivo (J1 teclado, J2 mando)"
	)
	_check(
		InputSetup.device_for_player(1) == 7 and InputSetup.device_for_player(0) == -1,
		"el mando de J2 no maneja a J1"
	)
	var mode_before := GameSettings.wave_mode
	menu.set_wave_mode(1 - mode_before)
	_check(GameSettings.wave_mode != mode_before, "en la partida se elige el modo de olas")
	menu.set_wave_mode(mode_before)
	await _key(KEY_ESCAPE)
	_check(menu.screen == "players", "ESC vuelve a los personajes")
	_check(menu.cards[0].device == InputSetup.KEYBOARD and menu.cards[1].device == 7, "y siguen unidos")
	await _key(KEY_ENTER)
	await _pad(7, JOY_BUTTON_START)
	_check(menu.screen == "setup" and not started[0], "todavía no empieza")
	await _key(KEY_ENTER)
	_check(started[0] and menu.started_config.slots.size() >= 2, "ENTER en la partida: ¡a surfear!")
	menu.queue_free()
	await process_frame
	InputSetup.clear_assignments()
	GameSettings.player_count = saved_count
