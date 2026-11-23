extends SceneTree
## Capturas de la ola tubo desde varios ángulos, con una cámara propia (sin la
## pantalla dividida): de costado, con la cámara del juego, de frente, de
## arriba, de espaldas, de lejos y llegando a la boca.
##
## Uso (con pantalla, o con xvfb-run):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/shot_tube.gd -- carpeta
## (Con render por software tarda un par de minutos.)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var dir := OS.get_cmdline_user_args()[0]
	GameSettings.load_settings()
	var config := RaceConfig.create(1, 0, 1)
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("RaceManager") as RaceManager).config = config
	root.add_child(m)
	for i in 20:
		await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	var course := m.get_node("Course") as Course
	(m.get_node("WaveManager") as WaveManager).enabled = false
	race.skip_countdown()
	race.tubes.automatic = false
	(m.get_node("Views") as CanvasItem).visible = false
	var rider := race.humans()[0]
	var tw := TubeWave.new()
	m.add_child(tw)
	tw.setup(course, 1.0, 0.0, 1.0, 30.0, 14.0, null, 60.0)
	tw.enter(rider, 20.0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	var hold := func() -> void:
		var st := rider.state_machine.current
		if rider.in_tube():
			st.set("balance", 0.0)
			st.set("_push", 0.0)
			st.set("_push_target", 0.0)
	physics_frame.connect(hold)
	var shots := {
		"1_costado": Vector3(-24.0, 5.0, 0.0),
		"2_camara_juego": Vector3(0.0, 1.9, -4.2),
		"3_frente": Vector3(-2.0, 3.0, 26.0),
		"4_arriba": Vector3(-12.0, 22.0, -10.0),
		"5_espalda": Vector3(26.0, 8.0, 4.0),
		"6_boca_lejos": Vector3(-4.0, 4.0, -45.0),
	}
	for name in shots:
		var s: float = tw.inside.get(rider, 20.0)
		var f := tw.frame_at(s)
		var o: Vector3 = f[0]
		var w: Vector3 = f[1]
		var fwd: Vector3 = f[2]
		var off: Vector3 = shots[name]
		cam.global_position = o + w * off.x + Vector3.UP * off.y + fwd * off.z
		var look := rider.global_position + Vector3.UP * 1.5
		if name == "2_camara_juego":
			# Como la cámara del juego: detrás y un poco arriba del surfista.
			cam.global_position = rider.global_position - fwd * 4.2 + Vector3.UP * (1.9 + 0.0)
			look = rider.global_position + Vector3.UP * 1.0
		cam.look_at(look, Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
		print("captura ", name)
	# Llegando a una ola que espera en la boca (lo que ve el jugador antes de entrar).
	# (Una ola por vez, como en el juego: la de recién es muy larga y pasaría por acá.)
	tw.dismiss()
	tw.queue_free()
	for i in 3:
		await process_frame
	var tw2 := TubeWave.new()
	m.add_child(tw2)
	tw2.setup(course, 3.0, 0.0, 1.0, 10.0, 18.0, null, 60.0)
	for i in 40:
		await process_frame
	for d in [30.0, 12.0]:
		var f2 := tw2.frame_at(0.0)
		var o2: Vector3 = f2[0]
		var fw2: Vector3 = f2[2]
		cam.global_position = o2 - fw2 * d + Vector3.UP * 2.8
		cam.look_at(o2 + fw2 * 10.0 + Vector3.UP * 1.5, Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("7_llegando_%d.png" % int(d)))
		print("captura llegando ", d)
	quit()
