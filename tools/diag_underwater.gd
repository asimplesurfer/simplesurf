extends SceneTree
## Diagnóstico: corre una demo de bots y, cuadro por cuadro, mira si la cabeza
## de cada uno queda debajo del agua TAL COMO SE DIBUJA (la malla real: vértices
## cada ~1,5 m, corridos por el labio de la ola, triángulos como los arma
## PlaneMesh) y si en ese momento salta el chapuzón.
##
## Uso:
##   godot --headless --path . --fixed-fps 60 --script res://tools/diag_underwater.gd -- [segundos] [capturas]
## Con "capturas" (y sin --headless, con pantalla) guarda imágenes de los casos.

const SECONDS_DEFAULT := 120.0
const SHOT_DIR := "user://diag"

var _race: RaceManager
var _water: Water
var _step: float
var _punch_frame: Dictionary = {}
## Por corredor: cuadros seguidos con la cara bajo el agua dibujada.
var _under_run: Dictionary = {}
var _under_had_punch: Dictionary = {}
var _frame: int = 0
var _shots: bool = false
var _shots_taken: int = 0
var _shot_at: Dictionary = {}
var _punch_states: Dictionary = {}

# Estadísticas.
var _frames_checked: int = 0
var _face_gt := 0
var _face_calc := 0
var _gt_not_calc := 0
var _calc_not_gt := 0
var _head_gt := 0
var _misses: Array[String] = []
var _episodes := 0
var _episodes_missed := 0
var _episodes_cooldown := 0
var _worst_depth := 0.0
var _calc_usec := 0
var _calc_max := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := SECONDS_DEFAULT
	if args.size() > 0:
		seconds = float(args[0])
	_shots = args.has("capturas")
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	GameSettings.load_settings()
	GameSettings.player_count = 1
	GameSettings.bot_count = 3
	GameSettings.bot_level = 2
	GameSettings.demo_mode = true
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_race = main.get_node("RaceManager") as RaceManager
	_water = main.get_node("Water") as Water
	_step = _water.size / float(_water.subdivisions + 1)
	_race.skip_countdown()
	for r in _race.racers:
		var rr: Rider = r
		_punch_frame[rr] = -100000
		_under_run[rr] = 0
		_under_had_punch[rr] = false
		rr.wave_punched.connect(func() -> void:
			_punch_frame[rr] = _frame
			var st := String(rr.state_machine.current_name)
			_punch_states[st] = int(_punch_states.get(st, 0)) + 1
			if _shots and _shots_taken < 10:
				_shots_taken += 1
				_shot_at[_frame + 1] = "golpe_%s" % rr.display_name.replace(" ", "")
				_shot_at[_frame + 10] = "despues_%s" % rr.display_name.replace(" ", "")
		)
	if _shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	print("Diagnóstico: %d bots, %.0f s, paso de malla %.2f m" % [_race.racers.size(), seconds, _step])
	for i in int(seconds * 60.0):
		await process_frame
		_frame += 1
		if _shot_at.has(_frame):
			var img := root.get_texture().get_image()
			img.save_png("%s/f%05d_%s.png" % [ProjectSettings.globalize_path(SHOT_DIR), _frame, _shot_at[_frame]])
		for r in _race.racers:
			_check_rider(r)
	_report()
	quit()


var _falls: Dictionary = {}
var _was_fallen: Dictionary = {}


func _check_rider(r: Rider) -> void:
	var fallen := r.is_fallen()
	if fallen and not _was_fallen.get(r, false):
		_falls[r] = int(_falls.get(r, 0)) + 1
	_was_fallen[r] = fallen
	var visual := r.get_node("Visual") as RiderVisual
	var face := visual.face_position()
	var avatar: Avatar = visual._body
	var head := avatar.find_child("Head", true, false) as Node3D
	var head_c := head.global_position if head else face
	_frames_checked += 1
	var gt := _rendered_under(face)
	var t0 := Time.get_ticks_usec()
	var calc := _water.face_in_wave(face)
	var dt := Time.get_ticks_usec() - t0
	_calc_usec += dt
	_calc_max = maxi(_calc_max, dt)
	if gt > 0.0:
		_face_gt += 1
		_worst_depth = maxf(_worst_depth, gt)
	if calc:
		_face_calc += 1
	if _rendered_under(head_c) > 0.0:
		_head_gt += 1
	if gt > 0.1 and not calc:
		Water.debug_exact = true
		var exact := _water.drawn_depth(face)
		Water.debug_exact = false
		print("  DEBUG f%d gt=%.2f exact=%.2f face=%s swells=%d" % [_frame, gt, exact, face, _water.swells.size()])
	if gt > 0.0 and not calc:
		_gt_not_calc += 1
		if _misses.size() < 40:
			_misses.append(
				"  f%d %s: cara %.2f m bajo el agua dibujada y el cálculo dice que no (%s)"
				% [_frame, r.display_name, gt, _describe(r, face)]
			)
	elif calc and gt <= 0.0:
		_calc_not_gt += 1
	# Episodios: cara bajo el agua dibujada >= 3 cuadros seguidos.
	if gt > 0.02:
		_under_run[r] += 1
		if _frame - int(_punch_frame[r]) <= 2:
			_under_had_punch[r] = true
	else:
		_end_episode(r)


func _end_episode(r: Rider) -> void:
	var run: int = _under_run[r]
	if run >= 3:
		_episodes += 1
		var start := _frame - run
		var punched: bool = _under_had_punch[r]
		if not punched:
			# Si hubo chapuzón poco antes, el enfriamiento lo tapó.
			if start - int(_punch_frame[r]) < 72:
				_episodes_cooldown += 1
			else:
				_episodes_missed += 1
				_misses.append("  pasada SIN chapuzón: %s f%d-%d (%s)" % [
					r.display_name, start, _frame, r.state_machine.current_name])
	_under_run[r] = 0
	_under_had_punch[r] = false


func _describe(r: Rider, face: Vector3) -> String:
	var dir := ""
	for s in _water.swells:
		var uw := s.local_coords(Vector2(face.x, face.z))
		if absf(uw.y) < s.half_length and absf(uw.x) < s.width * 4.0 + 6.0:
			var heading := r.forward()
			var cosang := Vector2(heading.x, heading.z).dot(s.direction)
			dir = "ola %.1f m rompe %.1f u=%.1f w=%.1f; rumbo vs ola %.0f°; %s" % [
				s.amplitude, s.breaking, uw.x, uw.y,
				rad_to_deg(acos(clampf(cosang, -1.0, 1.0))), r.state_machine.current_name,
			]
	return dir


func _near_swell(q: Vector3) -> bool:
	var p := Vector2(q.x, q.z)
	for s in _water.swells:
		if s.amplitude < 0.2:
			continue
		var uw := s.local_coords(p)
		if absf(uw.y) < s.half_length + 2.0 and absf(uw.x) < s.width * 4.0 + 8.0:
			return true
	return _water.ring_wave != null


## Vértice de la malla del agua tal como lo mueve water.gdshader.
func _vertex(p: Vector2) -> Vector3:
	var h := _water.waves.height_at(p.x, p.y, _water.time)
	var sh := 0.0
	var disp := Vector2.ZERO
	for s in _water.swells:
		if s.width <= 0.0:
			continue
		var uw := s.local_coords(p)
		var aw := absf(uw.y)
		if aw >= s.half_length or absf(uw.x) > s.width * 4.0:
			continue
		var t := clampf((aw - (s.half_length - 8.0)) / 8.0, 0.0, 1.0)
		var e := 1.0 - t * t * (3.0 - 2.0 * t)
		var n := exp(-(uw.x * uw.x) / (s.width * s.width)) * e
		sh += s.amplitude * n
		var lean := (0.35 + 0.95 * s.breaking) * s.amplitude
		disp += s.direction * (lean * n * n * n)
	if _water.ring_wave:
		sh += _water.ring_wave.height_at(p)
	var fade := _water._island_fade(p)
	h += sh * fade
	disp *= fade
	return Vector3(p.x + disp.x, h, p.y + disp.y)


## Cuánto está el punto debajo del agua dibujada (0 si está afuera): cuenta
## las capas de la malla que hay arriba (impar = adentro).
func _rendered_under(q: Vector3) -> float:
	var reach := 14.0
	var i0 := floori((q.x - reach) / _step - 0.5)
	var i1 := ceili((q.x + reach) / _step - 0.5)
	var j0 := floori((q.z - reach) / _step - 0.5)
	var j1 := ceili((q.z + reach) / _step - 0.5)
	var nx := i1 - i0 + 1
	var verts: Array[Vector3] = []
	verts.resize(nx * (j1 - j0 + 1))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			verts[(j - j0) * nx + (i - i0)] = _vertex(Vector2((i + 0.5) * _step, (j + 0.5) * _step))
	var above: Array[float] = []
	var p := Vector2(q.x, q.z)
	for j in range(1, j1 - j0 + 1):
		for i in range(1, nx):
			# Igual que PlaneMesh: (i-1,j-1)(i,j-1)(i-1,j) y (i,j-1)(i,j)(i-1,j).
			var a := verts[(j - 1) * nx + i - 1]
			var b := verts[(j - 1) * nx + i]
			var c := verts[j * nx + i - 1]
			var d := verts[j * nx + i]
			for tri in [[a, b, c], [b, d, c]]:
				var y := _tri_height(p, tri[0], tri[1], tri[2])
				if not is_nan(y) and y > q.y:
					above.append(y)
	if above.size() % 2 == 1:
		above.sort()
		return above[0] - q.y
	return 0.0


func _tri_height(p: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var v0 := Vector2(b.x, b.z) - a2
	var v1 := Vector2(c.x, c.z) - a2
	var v2 := p - a2
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return NAN
	var u := (v2.x * v1.y - v1.x * v2.y) / den
	var v := (v0.x * v2.y - v2.x * v0.y) / den
	if u < 0.0 or v < 0.0 or u + v > 1.0:
		return NAN
	return a.y + u * (b.y - a.y) + v * (c.y - a.y)


func _report() -> void:
	print("Cuadros revisados cerca de olas grandes: %d" % _frames_checked)
	print("Cara bajo el agua dibujada: %d cuadros (máx %.2f m)  ·  según el cálculo del juego: %d" % [
		_face_gt, _worst_depth, _face_calc])
	print("Cabeza (centro) bajo el agua dibujada: %d cuadros" % _head_gt)
	print("Dibujada sí / cálculo no: %d  ·  cálculo sí / dibujada no: %d" % [_gt_not_calc, _calc_not_gt])
	print("Pasadas con la cara bajo el agua (>= 3 cuadros): %d" % _episodes)
	print("  sin chapuzón: %d  ·  tapadas por el enfriamiento: %d" % [_episodes_missed, _episodes_cooldown])
	print("Costo del chequeo del juego: %.0f µs promedio, %d µs máximo (por corredor y cuadro)" % [
		float(_calc_usec) / maxf(_frames_checked, 1.0), _calc_max])
	print("Chapuzones por estado: %s" % str(_punch_states))
	var falls := 0
	for r in _race.racers:
		falls += _falls.get(r, 0)
	print("Caídas: %d" % falls)
	for m in _misses:
		print(m)
