extends SceneTree
## Captura del agua que levanta la tabla (girando, o derrapando con "derrape")
## con una hora y un clima, para revisar sus colores a ojo.
##
## Uso (con pantalla, o con xvfb-run):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shot_spray.gd -- salida.png [dia|atardecer|noche] [sol|tormenta] [mapa] [costado] [derrape]
## Con "costado" la cámara mira al surfista de costado. WAIT=n (variable de
## entorno): cuadros de carrera antes de girar (si en la captura se cayó, cambiarlo).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://climate.png"
	var times := {"dia": GameSettings.TimeOfDay.DAY, "atardecer": GameSettings.TimeOfDay.SUNSET, "noche": GameSettings.TimeOfDay.NIGHT}
	GameSettings.load_settings()
	GameSettings.time_of_day = times.get(args[1] if args.size() > 1 else "atardecer", GameSettings.TimeOfDay.SUNSET)
	GameSettings.weather = GameSettings.Weather.STORM if args.size() > 2 and args[2] == "tormenta" else GameSettings.Weather.SUNNY
	if args.size() > 3:
		GameSettings.track_layout = TrackMap.index_of(args[3])
	var config := RaceConfig.create(1, 0, 1)
	config.time_of_day = GameSettings.time_of_day
	config.weather = GameSettings.weather
	config.layout = GameSettings.track_layout
	var slot := RacerSlot.new()
	slot.kind = RacerSlot.Kind.HUMAN
	slot.player_index = 0
	slot.character = CharacterData.random(RandomNumberGenerator.new())
	config.slots = [slot]
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("RaceManager") as RaceManager).config = config
	root.add_child(m)
	for i in 60:
		await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	(m.get_node("Course") as Course).hazards_enabled = false
	var r: Rider = race.humans()[0]
	for i in int(OS.get_environment("WAIT") if OS.get_environment("WAIT") != "" else "150"):
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	var views := m.get_node_or_null("Views") as SplitScreen
	if views and not views.cameras.is_empty():
		cam = views.cameras[0]
	var act := "p1_drift" if args.has("derrape") else "p1_right"
	if args.has("derrape"):
		Input.action_press("p1_right")
	Input.action_press(act)
	for i in 30:
		await process_frame
	if args.has("costado"):
		cam.set_process(false)
		cam.global_position = r.global_position + r.right() * 6.0 + r.forward() * 2.0 + Vector3.UP * 2.0
		cam.look_at(r.global_position + Vector3.UP * 0.6, Vector3.UP)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("Captura: ", out, " ", (r.get_node("Visual") as RiderVisual).water_colors())
	quit()
