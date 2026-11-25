extends SceneTree
## Capturas del menú de pausa (fondo desenfocado), para revisarlo a ojo: la
## carrera sin pausa, la transición al abrir y el menú abierto.
##
## Uso (con pantalla, o con xvfb-run):
##   godot --path . --rendering-driver opengl3 --script res://tools/shot_pause.gd -- carpeta [dia|atardecer|noche] [sol|tormenta] [mapa] [jugadores] [video]
## Deja en la carpeta: pausa_0_juego.png, pausa_1_abriendo.png,
## pausa_2_abierta.png, pausa_3_fondo.png (sin el panel) y pausa_4_cerrando.png.
##
## Con "video" (y --fixed-fps 30), guarda cuadro por cuadro ~9 s: el juego,
## abrir la pausa, el fondo moviéndose (sin el panel a la mitad) y cerrarla.
## Con ffmpeg se arma el video:
##   ffmpeg -framerate 30 -i carpeta/cuadro_%04d.png -pix_fmt yuv420p pausa.mp4
##
## Con "medir" (en vez de "video"): cuánto tarda cada cuadro jugando y con la
## pausa abierta (con OpenGL por software cuenta todo lo que dibuja la placa).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var times := {"dia": GameSettings.TimeOfDay.DAY, "atardecer": GameSettings.TimeOfDay.SUNSET, "noche": GameSettings.TimeOfDay.NIGHT}
	GameSettings.load_settings()
	GameSettings.time_of_day = times.get(args[1] if args.size() > 1 else "atardecer", GameSettings.TimeOfDay.SUNSET)
	GameSettings.weather = GameSettings.Weather.STORM if args.size() > 2 and args[2] == "tormenta" else GameSettings.Weather.SUNNY
	if args.size() > 3 and args[3] != "-":
		GameSettings.track_layout = TrackMap.index_of(args[3])
	var players := int(args[4]) if args.size() > 4 else 1
	var config := RaceConfig.create(players, 4, 1)
	config.time_of_day = GameSettings.time_of_day
	config.weather = GameSettings.weather
	config.layout = GameSettings.track_layout
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	root.add_child(m)
	for i in 420:
		await process_frame
	if args.size() > 5 and args[5] == "medir":
		await _measure(race)
		quit()
		return
	if args.size() > 5 and args[5] == "video":
		await _video(out, race)
		quit()
		return
	await _shot(out.path_join("pausa_0_juego.png"))
	race.toggle_pause()
	var menu := race.pause_menu
	while menu.blur_amount() < 0.45:
		await process_frame
	await _shot(out.path_join("pausa_1_abriendo.png"))
	while menu.blur_amount() < 1.0:
		await process_frame
	for i in 20:
		await process_frame
	await _shot(out.path_join("pausa_2_abierta.png"))
	(menu.get_node("Menu") as Control).visible = false
	await _shot(out.path_join("pausa_3_fondo.png"))
	(menu.get_node("Menu") as Control).visible = true
	menu.close()
	while menu.blur_amount() > 0.5:
		await process_frame
	await _shot(out.path_join("pausa_4_cerrando.png"))
	quit()


func _measure(race: Node) -> void:
	var playing := await _frame_ms(90)
	race.toggle_pause()
	for i in 60:
		await process_frame
	var paused := await _frame_ms(90)
	print("MEDIDA jugando: %.1f ms por cuadro, con la pausa: %.1f ms por cuadro" % [playing, paused])


## Promedio de milisegundos por cuadro durante `frames` cuadros.
func _frame_ms(frames: int) -> float:
	await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - start) / 1000.0 / frames


func _video(out: String, race: Node) -> void:
	var frame := 0
	# [cuadros, qué hacer antes]: 1 s de juego, abrir, 4 s con el menú, 3 s
	# solo el fondo (para ver cómo se mueven las luces), cerrar y 1 s de juego.
	var plan := [[30, "-"], [120, "abrir"], [90, "sin_panel"], [40, "cerrar"]]
	for step in plan:
		match step[1]:
			"abrir":
				race.toggle_pause()
			"sin_panel":
				(race.pause_menu.get_node("Menu") as Control).visible = false
			"cerrar":
				(race.pause_menu.get_node("Menu") as Control).visible = true
				race.pause_menu.close()
		for i in int(step[0]):
			await _shot(out.path_join("cuadro_%04d.png" % frame), false)
			frame += 1
			await process_frame


func _shot(path: String, log_it := true) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	if log_it:
		print("Captura: ", path)
