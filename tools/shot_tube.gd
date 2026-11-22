extends SceneTree
## Capturas de la ola tubo para revisarla a ojo: llegando a la boca, adentro
## (cámara de siempre), de costado, de frente y la salida.
##
## Uso (con pantalla, o con xvfb-run):
##   godot --path . --rendering-driver opengl3 --script res://tools/shot_tube.gd -- carpeta [mapa]
## Deja tube_1_boca.png, tube_2_adentro.png, ... en la carpeta.

var _dir := "user://"
var _rider: Rider
var _hold_balance: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	GameSettings.load_settings()
	var config := RaceConfig.create(1, 1, 1)
	if args.size() > 1:
		config.layout = TrackMap.index_of(args[1])
	config.time_of_day = GameSettings.TimeOfDay.DAY
	config.weather = GameSettings.Weather.SUNNY
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("RaceManager") as RaceManager).config = config
	root.add_child(m)
	# Que termine de cargar (sombras, materiales) antes de empezar.
	for i in 120:
		await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	var course := m.get_node("Course") as Course
	(m.get_node("WaveManager") as WaveManager).enabled = false
	(m.get_node("Water") as Water).clear_swells()
	race.skip_countdown()
	race.tubes.set_physics_process(false)
	_rider = race.humans()[0]
	for r in race.racers:
		if r != _rider:
			r.controls_locked = true
	var track := course.track
	var angle := 1.0
	var lateral := 6.0
	var tw := TubeWave.new()
	m.add_child(tw)
	tw.setup(course, angle, lateral, 1.0, 6.0, 18.0, _rider, 30.0)
	# Llegando: 20 m antes de la boca.
	var p := track.position_at(angle - 20.0 / track.radius, lateral - 1.0)
	_rider.position = Vector3(p.x, 0.0, p.z)
	_rider.heading = track.heading_at(angle - 20.0 / track.radius)
	race._last_angle[_rider] = track.angle_of(_rider.position)
	_rider.speed = 9.0
	_rider.controls_locked = true
	for i in 50:
		await process_frame
	await _shot("tube_1_boca.png")
	_rider.controls_locked = false
	# Que siga derecho hasta entrar.
	for i in 200:
		_rider.speed = maxf(_rider.speed, 9.0)
		await process_frame
		if _rider.in_tube():
			break
	physics_frame.connect(_keep_balance)
	for i in 120:
		await process_frame
	await _shot("tube_2_adentro.png")
	_hold_balance = 0.75
	for i in 30:
		await process_frame
	await _shot("tube_3_arriba.png")
	_hold_balance = -0.75
	for i in 30:
		await process_frame
	await _shot("tube_4_abajo.png")
	_hold_balance = 0.0
	# De costado (desde el lado abierto) y de frente.
	var cam := root.get_viewport().get_camera_3d()
	var views := m.get_node_or_null("Views") as SplitScreen
	if views and not views.cameras.is_empty():
		cam = views.cameras[0]
	cam.set_process(false)
	if not is_instance_valid(tw):
		print("La ola ya no está")
		quit()
		return
	var s: float = tw.inside.get(_rider, 0.0)
	var f := tw.frame_at(s)
	var o: Vector3 = f[0]
	var w: Vector3 = f[1]
	var fwd: Vector3 = f[2]
	cam.global_position = o - w * 16.0 + Vector3.UP * 3.0 - fwd * 4.0
	cam.look_at(o + Vector3.UP * 2.5, Vector3.UP)
	await _shot("tube_5_costado.png")
	cam.global_position = o + fwd * 14.0 + Vector3.UP * 3.0 - w * 1.0
	cam.look_at(o + Vector3.UP * 2.0, Vector3.UP)
	await _shot("tube_6_frente.png")
	cam.set_process(true)
	# La salida.
	for i in 400:
		await process_frame
		if not _rider.in_tube():
			break
	for i in 6:
		await process_frame
	await _shot("tube_7_salida.png")
	quit()


## Mantiene el equilibrio donde se pide (para sacar fotos sin caerse).
func _keep_balance() -> void:
	if _rider and _rider.in_tube():
		var st := _rider.state_machine.current
		st.set("balance", _hold_balance)
		st.set("_push", 0.0)
		st.set("_push_target", 0.0)


func _shot(name: String) -> void:
	# Con el juego quieto unos cuadros (el dibujo puede ir atrasado).
	Engine.time_scale = 0.0
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _dir.path_join(name)
	img.save_png(path)
	var cam := root.get_viewport().get_camera_3d()
	print("Captura: %s  surfista %s (%s)  cámara %s" % [path, _rider.global_position, _rider.state_machine.current_name, cam.global_position if cam else Vector3.ZERO])
	Engine.time_scale = 1.0
