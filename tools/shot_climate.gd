extends SceneTree
## Captura de una carrera con una hora y un clima, para revisar colores a ojo
## (agua, horizonte, arrecifes).
##
## Uso (con pantalla, o con xvfb-run):
##   godot --path . --rendering-driver opengl3 --script res://tools/shot_climate.gd -- salida.png [dia|atardecer|noche] [sol|tormenta] [mapa] [horizonte]
## Con "horizonte", la cámara mira al mar abierto desde la altura de siempre
## (para ver el agua lejana y la bruma).

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
		GameSettings.track_layout = TrackMap.index_of(args[3]) as GameSettings.TrackLayout
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
	for i in 240:
		await process_frame
	if args.has("horizonte"):
		var cam := root.get_viewport().get_camera_3d()
		var views := m.get_node_or_null("Views") as SplitScreen
		if views and not views.cameras.is_empty():
			cam = views.cameras[0]
		cam.set_process(false)
		var course := m.get_node("Course") as Course
		var p := course.track.position_at(0.0, course.half_width + 2.0)
		var out_dir := (p - course.track.position_at(0.0, 0.0)).normalized()
		cam.global_position = p + Vector3.UP * 3.0
		cam.look_at(cam.global_position + out_dir * 100.0 + Vector3.DOWN * 4.0, Vector3.UP)
		for i in 10:
			await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("Captura: ", out)
	quit()
