extends SceneTree
## Comprueba que el agua que se VE (shader, en la placa de video) y la que
## SIENTE la física (GDScript: WaveDefinition, Swell, RingWave, Water) son la
## misma: arma olas de fondo, olas grandes (una rompiendo), la ola constante y
## una isla, en un momento avanzado de la partida, y compara la superficie en
## una grilla de puntos. Después, una ola que rompe en tubo (modo trucos). Necesita pantalla (en el CI, una virtual):
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/water_match.gd
## Imprime "WATER_MATCH OK" o los puntos donde no coinciden (y sale con 1).

const COLS := 48
const ROWS := 16
const RANGE := 16.0
## Diferencia máxima aceptada (m): la placa de video calcula con floats de 32 bits.
const TOLERANCE := 0.02


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var water := Water.new()
	water.name = "Water"
	root.add_child(water)
	await process_frame
	# Quieto: el agua no avanza sola mientras se compara.
	water.set_physics_process(false)
	water.set_process(false)
	# Un rato largo de partida (las fases deben seguir coincidiendo).
	water.time = 5432.1

	var specs := [
		[Vector2(-10, 4), Vector2(1, 0.3), 3.2, 4.0, 22.0, 0.0],
		[Vector2(18, -6), Vector2(-0.4, 1), 2.6, 5.0, 18.0, 1.0],
		[Vector2(30, 10), Vector2(-1, -0.5), 1.4, 3.5, 12.0, 0.5],
	]
	for sp in specs:
		var s := Swell.new()
		s.center = sp[0]
		s.direction = (sp[1] as Vector2).normalized()
		s.speed = 0.0
		s.max_amplitude = sp[2]
		s.width = sp[3]
		s.half_length = sp[4]
		s.lifetime = 1000.0
		s.grow_time = 1.0
		# Crecida, y con la rompiente que pide la prueba.
		s.update(1.0 + float(sp[5]) * Swell.BREAK_TIME)
		water.add_swell(s)
	var ring := RingWave.new()
	ring.center = Vector2(10, 60)
	ring.radius = 40.0
	ring.settle()
	ring.phase = 1.3
	water.set_ring_wave(ring)
	# Una isla redonda de 10 m (la tierra va como figura).
	var circle := PackedVector2Array()
	for k in 32:
		circle.append(Vector2(42, 2) + Vector2.from_angle(TAU * k / 32.0) * 10.0)
	var land: Array[PackedVector2Array] = [circle]
	water.set_land(land)
	water._push_time()
	water._push_swells()

	var origin := Vector2(-30, -14)
	var spacing := Vector2(1.7, 1.9)
	var res := await _compare(water, origin, spacing, true)
	if res.is_empty():
		return
	print("Puntos: %d (sobre olas grandes: %d) · diferencia máxima: %.4f m" % [COLS * ROWS, res[2], res[1]])
	if res[2] < 50:
		print("WATER_MATCH MAL ARMADA: casi no hay puntos sobre olas grandes")
		quit(1)
		return
	var bad: Array = res[0]
	if bad.is_empty():
		# Modo trucos: una ola que rompe en tubo de a poco (hombro, tubo abierto
		# y la parte que se cayó). Lo que se dibuja (corrido y dado vuelta) es lo
		# mismo en el shader y en GDScript (Water.drawn_vertex: con eso se sabe
		# si algo quedó debajo del agua dibujada).
		water.clear_swells()
		water.set_ring_wave(null)
		var b := Swell.new()
		b.match_drawn = true
		# Lejos de la isla (cerca, el apagado de las olas usa una textura en el
		# shader y en GDScript la figura exacta: con el labio corrido varios
		# metros, la diferencia se nota).
		b.center = Vector2(-50, -2)
		b.direction = Vector2(0, 1)
		b.speed = 0.0
		b.max_amplitude = 3.0
		b.width = 5.0
		b.half_length = 34.0
		b.lifetime = 1000.0
		b.grow_time = 1.0
		b.update(1.0 + Swell.BREAK_TIME)
		b.curl = 1.0
		b.peel_dir = 1.0
		b.peel_w = 12.0
		b.barrel_len = 12.0
		water.add_swell(b)
		water._push_swells()
		var res2 := await _compare(water, Vector2(-90, -8), Vector2(1.7, 1.3), false)
		if res2.is_empty():
			return
		print("Tubo: %d puntos (en el tubo: %d) · diferencia máxima: %.4f m" % [COLS * ROWS, res2[3], res2[1]])
		if res2[3] < 100:
			print("WATER_MATCH MAL ARMADA: casi no hay puntos en el tubo")
			quit(1)
			return
		bad = res2[0]
	if bad.is_empty():
		print("WATER_MATCH OK")
		quit(0)
	else:
		print("WATER_MATCH NO COINCIDEN:")
		for line in bad:
			print(line)
		quit(1)


## Dibuja la superficie en la placa de video (tests/water_probe.gdshader) y la
## compara con GDScript en una grilla. Devuelve [diferencias, la peor, puntos
## sobre olas grandes, puntos en un tubo], o [] si no se pudo leer.
## `physics`: también compara con la altura que siente la física (en un tubo
## no: ahí hay más de una superficie en el mismo lugar).
func _compare(water: Water, origin: Vector2, spacing: Vector2, physics: bool) -> Array:
	var probe := ShaderMaterial.new()
	probe.shader = load("res://tests/water_probe.gdshader")
	var src := water.shader_material()
	for u in probe.shader.get_shader_uniform_list():
		var n: String = u.name
		var v = src.get_shader_parameter(n)
		if v != null:
			probe.set_shader_parameter(n, v)
	probe.set_shader_parameter("origin", origin)
	probe.set_shader_parameter("spacing", spacing)
	probe.set_shader_parameter("cols", COLS)
	probe.set_shader_parameter("rows", ROWS)

	var vp := SubViewport.new()
	vp.size = Vector2i(COLS, ROWS * 3 + 1)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	rect.material = probe
	vp.add_child(rect)
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()

	# La lectura funciona: la última fila tiene valores conocidos.
	for x in COLS:
		var want := 3.25 - x * 0.1
		var got := _decode(img, x, ROWS * 3)
		if absf(got - want) > 0.002:
			print("WATER_MATCH LECTURA MAL: x=%d %.4f en vez de %.4f" % [x, got, want])
			quit(1)
			return []

	var bad: Array[String] = []
	var worst := 0.0
	var big := 0
	var in_tube := 0
	for r in ROWS:
		for x in COLS:
			var p := origin + Vector2(x * spacing.x, r * spacing.y)
			var gpu_h := _decode(img, x, r)
			var gpu_dx := _decode(img, x, ROWS + r)
			var gpu_dz := _decode(img, x, ROWS * 2 + r)
			var drawn := water.drawn_vertex(p)
			if water.swell_height_at(p.x, p.y) > 0.5:
				big += 1
			for s in water.swells:
				var uw := s.local_coords(p)
				if s.curl > 0.0 and uw.x > 0.0 and uw.x < Swell.TUBE_REACH * s.width and absf(uw.y) < s.half_length:
					in_tube += 1
			var diffs := [
				["altura (dibujada en CPU)", gpu_h, drawn.y],
				["corrimiento x", gpu_dx, drawn.x - p.x],
				["corrimiento z", gpu_dz, drawn.z - p.y],
			]
			if physics:
				diffs.append(["altura (física)", gpu_h, water.height_at(p.x, p.y)])
			for d in diffs:
				var e := absf(float(d[1]) - float(d[2]))
				worst = maxf(worst, e)
				if e > TOLERANCE and bad.size() < 20:
					bad.append("  (%.1f, %.1f) %s: shader %.3f · GDScript %.3f" % [p.x, p.y, d[0], d[1], d[2]])
	return [bad, worst, big, in_tube]


func _decode(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(x, y)
	var q := roundi(c.r * 255.0) * 256 + roundi(c.g * 255.0)
	return q / 65535.0 * (2.0 * RANGE) - RANGE
