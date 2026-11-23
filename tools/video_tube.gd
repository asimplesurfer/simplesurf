extends SceneTree
## Graba un tubo de principio a fin con la cámara del juego: J1 (manejado por
## un bot) va por la pista, le aparece la ola (como con la tecla Y), entra, la
## surfea y sale. Guarda un PNG por cuadro (tiempo fijo: --fixed-fps).
##
## Uso:
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-driver opengl3 \
##     --resolution 960x540 --fixed-fps 30 --script res://tools/video_tube.gd -- carpeta [mapa]
## Después: ffmpeg -framerate 30 -i carpeta/f%04d.png tubo.mp4

var _cam: Camera3D
var _view_cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0]
	GameSettings.load_settings()
	var config := RaceConfig.create(1, 0, 1)
	if args.size() > 1 and args[1] != "":
		config.layout = TrackMap.index_of(args[1])
	config.time_of_day = GameSettings.TimeOfDay.DAY
	config.weather = GameSettings.Weather.SUNNY
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("RaceManager") as RaceManager).config = config
	root.add_child(m)
	for i in 10:
		await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	race.tubes.automatic = false
	var rider := race.humans()[0]
	# Lo maneja un bot bueno (entra a la boca y mantiene el equilibrio).
	var ai := AIController.new()
	ai.name = "AutoPilot"
	ai.difficulty = AIDifficulty.preset(3)
	ai.difficulty.trick_fail_chance = 0.0
	rider.add_child(ai)
	rider.controller = ai
	var views := m.get_node("Views") as SplitScreen
	_view_cam = views.cameras[0]
	views.visible = false
	# Una cámara en la ventana principal que copia la del juego.
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
	# Andar un poco antes (que agarre velocidad).
	for i in 90:
		await process_frame
	race.tubes.spawn_test(rider)
	var frame := 0
	var after_exit := -1
	var max_frames := int(args[2]) if args.size() > 2 else 30 * 30
	while frame < max_frames:
		_copy_camera()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("f%04d.png" % frame))
		frame += 1
		await process_frame
		var wave_gone := race.tubes.current == null or not is_instance_valid(race.tubes.current) or race.tubes.current.done
		if after_exit < 0 and frame > 30 and not rider.in_tube() and wave_gone:
			after_exit = frame
		if frame % 30 == 0:
			print("cuadro %d: %s" % [frame, rider.state_machine.current_name])
		# Dónde está la cámara respecto de la ola (para encontrar cuándo se mete adentro).
		var tw := race.tubes.current
		if tw != null and is_instance_valid(tw) and not tw.done:
			var cs := tw.locate(_view_cam.global_position)
			var rs := tw.locate(rider.global_position)
			var cf: Array = tw.frame_at(cs.x)
			var base := tw.base_height(cf[0])
			print("  %d cam s=%.1f u=%.1f y=%.2f | surf s=%.1f u=%.1f | %s fase=%d rango=%s" % [
				frame, cs.x, cs.y, _view_cam.global_position.y - base, rs.x, rs.y,
				rider.state_machine.current_name, tw.phase, tw.span()])
		if after_exit >= 0 and frame - after_exit > 60:
			break
	print("cuadros: ", frame, "  estado final: ", rider.state_machine.current_name)
	quit()


func _copy_camera() -> void:
	_cam.global_transform = _view_cam.global_transform
	_cam.fov = _view_cam.fov
