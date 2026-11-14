extends Node
## Base de cada grupo de tests (tests/suites/*.gd): estado compartido y
## ayudas (comprobar, esperar, simular botones). Cada grupo hereda de acá y
## escribe su `run()`; tests/run_tests.gd los corre en orden y suma resultados.
##
## Para que los tests se lean igual que antes, acá están `root`,
## `process_frame` y `get_nodes_in_group` como en un SceneTree.

## Se emite en cada cuadro (reenvía el del árbol).
signal process_frame

const FPS := 60

var _failures: Array[String] = []
var _checks: int = 0
var root: Window
## Opciones con las que arrancó el juego (para comprobar los valores por defecto).
var defaults: Dictionary = {}
var _tricks_landed: int = 0
var _main: Node
var _rider: Rider
var _water: Water
var _waves: WaveManager
## Altura desde la que despegó el último salto (para medir saltos).
var _takeoff_y: float = 0.0
## Veces que atravesó una ola que rompía, y si se vieron sus efectos.
var _punches: int = 0
var _punch_without_face: bool = false
var _shake_seen: bool = false
## Si el último salto de ola fue con pop.
var _last_did_pop: bool = false
var _early_pressed: bool = false
var _splash_seen: bool = false
var _duck_seen: bool = false
var _race: RaceManager
var _course: Course
var _pop_prompt_seen: bool = false
var _watch_camera: bool = false
var _camera_lost: bool = false


func _enter_tree() -> void:
	root = get_tree().root
	get_tree().process_frame.connect(_forward_frame)


func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_forward_frame):
		get_tree().process_frame.disconnect(_forward_frame)


func _forward_frame() -> void:
	process_frame.emit()


func get_nodes_in_group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)


## Lo que hace cada grupo (se espera con await).
func run() -> void:
	pass


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if ok:
		print("  OK    ", description)
	else:
		print("  FALLA ", description)
		if _rider:
			print(
				"        estado=%s vel=%.1f vel_vert=%.2f en_agua=%s carga=%.2f a=%s"
				% [
					_state(),
					_rider.speed,
					_rider.vertical_speed,
					_rider.grounded,
					_rider.jump_charge,
					Input.is_action_pressed(&"p1_a"),
				]
			)
		_failures.append(description)


func _wait(seconds: float) -> void:
	for i in int(seconds * FPS):
		await process_frame


func _wait_until_state(state: StringName, max_seconds: float) -> void:
	for i in int(max_seconds * FPS):
		if _state() == state:
			return
		await process_frame


func _set_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _press(action: StringName) -> void:
	_set_action(action, true)
	await process_frame
	await process_frame
	_set_action(action, false)
	await process_frame
	await process_frame


## Pulsa A `rate` veces por segundo durante `seconds`.
func _mash(rate: float, seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(seconds * FPS):
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame


## Spamea hasta que se pone de pie (o se acaba el tiempo).
func _mash_until_standing(rate: float, max_seconds: float) -> void:
	var interval := maxi(2, roundi(FPS / rate))
	for i in int(max_seconds * FPS):
		if not _rider.is_fallen():
			break
		if i % interval == 0:
			_set_action(&"p1_a", true)
		elif i % interval == 1:
			_set_action(&"p1_a", false)
		await process_frame
	_set_action(&"p1_a", false)
	await process_frame


func _hold(action: StringName, seconds: float) -> void:
	_set_action(action, true)
	await _wait(seconds)
	_set_action(action, false)
	await process_frame


func _state() -> StringName:
	return _rider.state_machine.current_name


func _water_height_here() -> float:
	return _water.height_at(_rider.global_position.x, _rider.global_position.z)


func _teleport(pos: Vector3) -> void:
	_rider.position = Vector3(pos.x, _water.height_at(pos.x, pos.z), pos.z)
	_rider.vertical_speed = 0.0


## Toca una tecla (por código físico).
func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _has_key(action: StringName, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == key:
			return true
	return false


func _has_button(action: StringName, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return true
	return false


## Toca un botón. Los eventos simulados llegan al juego un frame después,
## por eso se espera un frame extra tras soltar.
## Color de un material del cuerpo del personaje (por nombre), o negro si no está.
func _kit_color(avatar: Avatar, mat_name: String) -> Color:
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as BaseMaterial3D
			if m and m.resource_name == mat_name:
				return m.albedo_color
	return Color.BLACK


func _kit_has(avatar: Avatar, mat_name: String) -> bool:
	return _kit_color(avatar, mat_name) != Color.BLACK


## Mantiene A `seconds` en el agua y suelta (salto cargado).
func _charged_jump(seconds: float) -> void:
	_set_action(&"p1_a", true)
	await _wait(seconds)
	_set_action(&"p1_a", false)
	await process_frame
	await process_frame


## (altura máxima, segundos en el aire) hasta aterrizar.
func _measure_air() -> Vector2:
	var max_height := 0.0
	var frames := 0
	for i in int(6.0 * FPS):
		var h := _rider.global_position.y - _water_height_here()
		max_height = maxf(max_height, h)
		if _watch_camera:
			var cam := (_main.get_node("Views") as SplitScreen).cameras[0]
			var body := _rider.global_position + Vector3.UP * 0.9
			if not cam.is_position_in_frustum(body):
				_camera_lost = true
		if _state() != &"airborne":
			break
		frames += 1
		await process_frame
	return Vector2(max_height, frames / float(FPS))


## Altura máxima sobre el agua hasta aterrizar.
## Se mide desde donde despegó (las olitas de fondo suben y bajan casi un
## metro: medir contra el agua de abajo daba números al azar).
func _measure_jump_height() -> float:
	var max_height := 0.0
	for i in int(2.5 * FPS):
		var h := _rider.global_position.y - _takeoff_y
		max_height = maxf(max_height, h)
		if _state() != &"airborne":
			break
		await process_frame
	return max_height


## Anda hacia una ola grande y devuelve la altura máxima del salto.
## Con press = true, aprieta A apenas la ola lo lanza (pop tardío).
## El chapuzón cuenta solo si la cara queda adentro del agua tal como se ve.
func _check_face_geometry() -> void:
	_water.clear_swells()
	var o := Vector2(5000.0, 5000.0)
	var s := Swell.new()
	s.center = o
	s.direction = Vector2.RIGHT
	s.max_amplitude = 3.0
	s.amplitude = 3.0
	s.width = 5.5
	s.half_length = 20.0
	s.breaking = 1.0
	s.lifetime = 1000.0
	_water.add_swell(s)
	var amb := _water.waves.max_height()
	var at := func(u: float, y: float, w: float = 0.0) -> Vector3:
		return Vector3(o.x + u, y, o.y + w)
	# Arriba de la cresta física no hay agua: el labio está corrido adelante.
	_check(_water.drawn_depth(at.call(0.0, 3.0 + amb + 0.3)) == 0.0, "cara arriba de la cresta: no atraviesa")
	_check(_water.drawn_depth(at.call(s.lean() * 0.9, 2.2)) > 0.0, "cara metida en el labio: atraviesa")
	_check(_water.drawn_depth(at.call(-2.0, 1.0)) > 0.0, "cara adentro del cuerpo de la ola: atraviesa")
	# De costado: la ola lo tapa igual (no importa hacia dónde mire).
	_check(_water.drawn_depth(at.call(-2.0, 1.0, 12.0)) > 0.0, "de costado, tapado por la ola: atraviesa")
	# Pies en el agua pero la cara afuera: no cuenta.
	var surface := _water.drawn_vertex(Vector2(o.x - 5.0, o.y)).y
	_check(_water.drawn_depth(at.call(-5.0, surface + 1.0)) == 0.0, "cara afuera aunque los pies toquen: no atraviesa")
	# Cualquier agua cuenta, también el mar sin ola.
	_check(_water.drawn_depth(at.call(40.0, -amb - 0.5)) > 0.0, "cara debajo del mar: cuenta")
	_check(_water.drawn_depth(at.call(0.0, amb + 0.3, 25.0)) == 0.0, "fuera del largo de la ola y arriba del mar: no cuenta")
	# Debe coincidir con la malla completa (sin atajos) en muchos puntos.
	var mismatches := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 300:
		var q: Vector3 = at.call(rng.randf_range(-14.0, 14.0), rng.randf_range(-0.5, 3.5), rng.randf_range(-24.0, 24.0))
		if (_water.drawn_depth(q) > 0.0) != (_full_mesh_depth(q) > 0.0):
			mismatches += 1
	_check(mismatches == 0, "el chequeo rápido coincide con la malla completa (%d diferencias en 300)" % mismatches)
	# La malla con menos detalle lejos: cerca del jugador, los vértices están en
	# la grilla fina del mundo (lo que supone drawn_depth) y son muchos menos.
	var mi := _water.get_child(0) as MeshInstance3D
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var step := _water.grid_step()
	var on_grid := true
	var fine := 0
	for v in verts:
		var w := mi.global_position + v
		if absf(v.x) < 30.0 and absf(v.z) < 30.0:
			fine += 1
			var fx := w.x / step - 0.5
			var fz := w.z / step - 0.5
			if absf(fx - roundf(fx)) > 0.001 or absf(fz - roundf(fz)) > 0.001:
				on_grid = false
	_check(on_grid and fine > 1000, "cerca del jugador la malla es la grilla fina del mundo (%d vértices)" % fine)
	_check(verts.size() < 12000, "la malla del agua tiene muchos menos vértices (%d, antes 29584)" % verts.size())
	_water.clear_swells()


## Profundidad bajo la malla del agua revisando TODOS los triángulos cercanos
## (lento, solo para comparar con Water.drawn_depth).
func _full_mesh_depth(q: Vector3) -> float:
	var step := _water.size / float(_water.subdivisions + 1)
	var above: Array[float] = []
	var p := Vector2(q.x, q.z)
	for j in range(floori((q.z - 9.0) / step), ceili((q.z + 9.0) / step) + 1):
		for i in range(floori((q.x - 9.0) / step), ceili((q.x + 9.0) / step) + 1):
			var a := _water.drawn_vertex(Vector2((i - 0.5) * step, (j - 0.5) * step))
			var b := _water.drawn_vertex(Vector2((i + 0.5) * step, (j - 0.5) * step))
			var c := _water.drawn_vertex(Vector2((i - 0.5) * step, (j + 0.5) * step))
			var e := _water.drawn_vertex(Vector2((i + 0.5) * step, (j + 0.5) * step))
			for y in [Water._tri_height(p, a, b, c), Water._tri_height(p, b, e, c)]:
				if not is_nan(y) and y > q.y:
					above.append(y)
	if above.size() % 2 == 0:
		return 0.0
	return above.min() - q.y


func _ride_into_swell(
	press: bool, at: Vector3, early: bool = false, turbo: bool = false,
	amp: float = 3.0, width: float = 5.5
) -> float:
	_water.clear_swells()
	_teleport(at)
	_rider.heading = 0.0
	await _wait(1.5)
	var s := Swell.new()
	var f := _rider.forward()
	var ahead := _rider.global_position + f * 25.0
	s.center = Vector2(ahead.x, ahead.z)
	s.direction = -Vector2(f.x, f.z)
	# Viene de frente, como las olas del juego (quieta queda justo en el límite).
	s.speed = 4.0
	s.max_amplitude = amp
	s.width = width
	s.half_length = 20.0
	s.lifetime = 100.0
	s.grow_time = 0.01
	_water.add_swell(s)
	var pressed := false
	var early_done := false
	var turbo_done := false
	var early_frame := -1
	_early_pressed = false
	_last_did_pop = false
	var release_next := false
	var max_height := 0.0
	var was_airborne := false
	var hud := (_main.get_node("Views") as SplitScreen).huds[0]
	var max_climb := 0.0
	var visual := _rider.get_node("Visual") as RiderVisual
	for i in int(5.0 * FPS):
		if _rider.grounded:
			max_climb = maxf(max_climb, _rider.vertical_speed)
		if hud._pop_box.visible:
			_pop_prompt_seen = true
		if hud.splash_overlay.visible:
			_splash_seen = true
		if visual.duck_time > 0.0:
			_duck_seen = true
		if visual._body._shake > 0.0:
			_shake_seen = true
		if release_next:
			_set_action(&"p1_a", false)
			release_next = false
		# Turbo justo antes de que la ola lo lance.
		if turbo and not turbo_done and _rider.grounded and _rider.on_big_wave(0.5):
			_rider.add_nitro(Rider.TURBO_CHARGE)
			_rider.fire_turbo()
			turbo_done = true
		# Antes de tiempo: apenas empieza a subir la ola, lejos de la cresta.
		var low_on_wave := (
			_rider.on_big_wave(0.3)
			and _water.swell_height_at(_rider.position.x, _rider.position.z) < 1.2
		)
		if early and not early_done and _rider.grounded and low_on_wave:
			_set_action(&"p1_a", true)
			early_done = true
			release_next = true
			early_frame = i
			_early_pressed = true
		if early and early_frame >= 0 and i == early_frame + 3:
			print("    pop antes de tiempo: bloqueado=%s, buffer=%.2f, en el aire=%s, estado=%s, ola=%.2f" % [
				_rider.pop_locked, _rider.pop_buffer, not _rider.grounded, _state(),
				_water.swell_height_at(_rider.position.x, _rider.position.z)])
		elif press and not pressed and _state() == &"airborne" and not release_next:
			_set_action(&"p1_a", true)
			pressed = true
			release_next = true
		if _state() == &"airborne":
			_last_did_pop = _last_did_pop or _rider.did_pop
		if _state() == &"airborne":
			was_airborne = true
			max_height = maxf(max_height, _rider.global_position.y - _water_height_here())
		elif was_airborne:
			break
		await process_frame
	_set_action(&"p1_a", false)
	print(
		"    ola: subida máx %.2f m/s (mín %.1f), amplitud %.2f, vel %.1f, catchup %.2f, turbo %s, nitro %.2f, ola en %s, rider en %s"
		% [max_climb, _rider.stats.min_launch_speed, s.amplitude, _rider.speed, _rider.catchup,
			_rider.turbo_active, _rider.nitro, s.center, _rider.global_position]
	)
	await _wait(0.5)
	return max_height
