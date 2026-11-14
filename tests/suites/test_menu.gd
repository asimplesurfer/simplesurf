extends "res://tests/test_base.gd"
## Opciones por defecto y menú (creador de personaje, armado de partida).


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
	await _test_menu()


func _test_menu() -> void:
	print("Menú de personaje:")
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	var started := [false]
	menu.start_requested.connect(func() -> void: started[0] = true)
	_set_action(&"p1_down", false)
	root.add_child(menu)
	await process_frame
	await process_frame
	var data := GameSettings.character_for(0)
	_check(menu.screen == "creator", "arranca en la pantalla de crear el surfista")
	_check(menu._category_buttons.size() == 8, "con 8 categorías")
	var presets: Array = menu._tiles.get("preset", [])
	_check(presets.size() == 6, "Estilos: un cuadrado por estilo armado (%d)" % presets.size())
	# Elegir un cuadrado con el teclado (foco + ESPACIO).
	(presets[1] as Button).grab_focus()
	await process_frame
	await _press(&"ui_accept")
	_check(menu.preset == 1 and data.weight > 0.8, "ESPACIO sobre un cuadrado lo elige (Abuelo playero)")
	_check((presets[1] as Button).get_meta("selected"), "el cuadrado elegido queda marcado")
	# El surfista original: melena, anteojos, sonrisa, perlas y flores del modelo.
	menu.choose("preset", 0)
	var avatar := menu._avatar
	_check(data.get_option("hair") == 2 and data.get_option("glasses") == 1, "estilo Surfista rubio: melena y anteojos de sol")
	_check(_kit_has(avatar, "hair") and _kit_has(avatar, "lens"), "el surfista rubio usa la melena y los anteojos del modelo")
	_check(_kit_has(avatar, "pearl") and _kit_has(avatar, "flower"), "con el collar de perlas y las flores del short")
	var kit_head := avatar.find_child("Head", true, false) as Node3D
	_check(kit_head.get_child_count() <= 3, "cada parte se dibuja junta (pocas mallas)")
	# Colores en cuadrados: piel.
	menu._show_category("Piel")
	_check((menu._tiles.get("skin", []) as Array).size() == CharacterData.SKIN_COLORS.size(), "Piel: un cuadrado por color")
	menu.choose("skin", 7)
	_check(data.skin_index == 7 and _kit_color(avatar, "skin") == data.skin_color(), "elegir un color de piel cambia el personaje")
	# Barras.
	menu._show_category("Cuerpo")
	_check(menu._sliders.size() == 3, "Cuerpo: barras de panza, músculos y cabeza")
	menu.set_slider("weight", 1.0)
	_check(is_equal_approx(data.weight, 1.0) and menu.preset == -1, "la barra de panza cambia el cuerpo (queda a tu gusto)")
	# Cara: la cámara se acerca.
	menu._show_category("Cara")
	await _wait(0.6)
	_check(menu.zoom() > 0.9, "en la cara, la cámara se acerca")
	var eyes := data.get_option("eyes")
	menu.choose("eyes", (eyes + 1) % CharacterData.EYES.size())
	_check(data.get_option("eyes") != eyes, "elegir ojos cambia los ojos")
	menu._show_category("Short")
	await _wait(0.6)
	_check(menu.zoom() < 0.1, "fuera de la cara, la cámara se aleja")
	var before := data.to_dict()
	menu.randomize_character()
	_check(data.to_dict() != before, "Al azar arma uno nuevo")
	menu.choose("preset", 0)
	# ENTER: a la pantalla de la partida.
	await _key(KEY_ENTER)
	_check(menu.screen == "setup", "ENTER pasa a armar la partida")
	var mode_before := GameSettings.wave_mode
	menu.set_wave_mode(1 - mode_before)
	_check(GameSettings.wave_mode != mode_before, "en la partida se elige el modo de olas")
	menu.set_wave_mode(mode_before)
	_check(GameSettings.wave_mode == mode_before, "y se vuelve al anterior")
	await _press(&"ui_cancel")
	_check(menu.screen == "creator", "ESC vuelve al personaje")
	await _key(KEY_ENTER)
	_check(not started[0], "todavía no empieza")
	await _key(KEY_ENTER)
	_check(started[0], "ENTER en la partida: ¡a surfear!")
	menu.queue_free()
	await process_frame
