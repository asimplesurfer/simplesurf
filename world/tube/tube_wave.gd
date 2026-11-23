class_name TubeWave
extends Node3D
## La ola tubo: una ola grande que rompe a lo largo de la pista (sigue sus
## curvas) y forma un tubo. Funciona como un portal: aparece adelante, con la
## boca mirando hacia los que vienen, y el que pasa por la boca entra (pueden
## entrar varios: el que la provocó y los que vienen cerca). Adentro todos van a
## la misma velocidad (no se chocan entre ellos), cargan nitro y mantienen el
## equilibrio (ver el estado `tube` del surfista). Al terminar el tiempo, el
## tubo los escupe por adelante con un turbo.
##
## Es una pieza suelta: no sabe cuándo aparece (en la carrera lo decide
## TubeDirector; el modo libre puede tener su propia lógica). Mientras está, los
## aros y rocas de su tramo desaparecen.
##
## Coordenadas propias: `s` = metros a lo largo de la pista desde la boca, y
## `u` = metros de costado desde la línea del tubo, positivo hacia la pared.

signal rider_entered(rider: Rider)
## Terminó (por tiempo, o porque nadie entró o todos se cayeron).
signal finished

enum Phase { OPENING, RIDING, CLOSING }

## Largo del tubo mientras espera en la boca (m).
const OPEN_LENGTH := 30.0
## Tiempo que tarda en levantarse (s).
const RISE_TIME := 0.9
## Tiempo que tarda en desarmarse al final (s).
const COLLAPSE_TIME := 0.8
## Después del primero que entra, la boca sigue abierta este tiempo (los que
## vienen cerca pueden entrar).
const ENTRY_WINDOW := 2.2
## Ancho de la boca: cuánto se puede estar corrido de la línea del tubo para
## entrar (hacia el lado abierto y hacia la pared).
const MOUTH_OPEN_SIDE := 4.5
const MOUTH_WALL_SIDE := 3.2
## Para entrar hay que estar cerca del agua (no muy alto en un salto).
const MOUTH_MAX_AIR := 1.6
## Cuánto tubo hay delante del primero: al principio, y al final (la salida se
## acerca: es la luz del final).
const AHEAD_START := 34.0
const AHEAD_END := 5.0
## Detrás del último, la ola ya rompió (espuma) en estos metros.
const BEHIND := 10.0
## Separación entre los anillos de la malla (m).
const RING_STEP := 1.5
## Cuánto se mueve el surfista de costado con el equilibrio al máximo (m).
const BALANCE_REACH := 2.2
## Altura de la cara de la ola donde el surfista sube (m) y dónde empieza.
const FACE_HEIGHT := 2.6
const FACE_FROM := -1.5
const FACE_TO := 2.6

var course: Course
var track: TrackSpace
var water: Water
## Ángulo de pista de la boca.
var mouth_angle: float = 0.0
## Línea del tubo (desvío lateral de la pista).
var lateral: float = 0.0
## Hacia qué lado de la pista está la pared: +1 hacia el lateral positivo.
var side: float = 1.0
## Cuánto dura adentro (desde que entra el primero).
var duration: float = 10.0
## Velocidad adentro (m/s): la misma para todos.
var speed: float = 20.0
## Quién la provocó (puede no entrar).
var opener: Rider
## Hasta cuándo se espera que alguien entre (s desde que aparece).
var open_timeout: float = 6.0

var phase: Phase = Phase.OPENING
## Tiempo desde que apareció.
var age: float = 0.0
## Tiempo desde que entró el primero (-1 si nadie entró todavía).
var ride_time: float = -1.0
## Los que están adentro: rider -> s (metros desde la boca). Lo actualiza el
## estado `tube` de cada uno.
var inside: Dictionary = {}
## Los que ya usaron esta ola (entraron, aunque se hayan caído): no vuelven a entrar.
var used: Dictionary = {}

const SHADER := preload("res://world/tube/tube_wave.gdshader")

var _mesh_instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial
## La luz del final del tubo (un brillo que se acerca).
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
## Espuma donde la ola ya rompió (atrás), gotas que caen del labio y la
## escupida de la salida.
var _back_foam: CPUParticles3D
var _lip_drops: CPUParticles3D
var _spit: CPUParticles3D
var _spit_mist: CPUParticles3D
var _collapse: float = 0.0
## Aros y rocas que se escondieron (para volver a mostrarlos).
var _hidden: Array[Node3D] = []
## Último tramo dibujado [desde, hasta] (m): lo usan los tests y la cámara.
var drawn_from: float = 0.0
var drawn_to: float = 0.0

## Perfil del tubo (u, y), de punta a punta: la cara (del lado abierto, sale de
## face_y), la pared, el techo, la punta del labio, el lomo del labio y la
## espalda de la ola que baja hasta el agua. Las puntas quedan bajo el agua.
const FACE_US := [-11.0, -7.5, -4.5, -2.6, -1.5, -0.6, 0.3, 1.1, 1.9, 2.6]
## Desde la pared hasta el final de la espalda: cerrado (tubo)...
const REST_CLOSED := [
	Vector2(3.2, 3.6), Vector2(3.5, 4.6), Vector2(3.3, 5.5), Vector2(2.6, 6.1),
	Vector2(1.5, 6.4), Vector2(0.2, 6.3), Vector2(-1.0, 5.8), Vector2(-2.0, 5.0),
	Vector2(-2.6, 4.1), Vector2(-2.8, 3.4),
	Vector2(-2.5, 3.0),
	Vector2(-2.1, 3.6), Vector2(-1.7, 4.6), Vector2(-0.9, 5.7), Vector2(0.2, 6.6),
	Vector2(1.6, 7.1), Vector2(3.0, 7.1), Vector2(4.2, 6.6),
	Vector2(5.6, 5.4), Vector2(7.4, 3.9), Vector2(9.6, 2.5), Vector2(12.5, 1.3),
	Vector2(16.0, 0.4), Vector2(20.0, -0.6),
]
## ...y abierto (la ola que recién se levanta: una cresta en punta).
const REST_OPEN := [
	Vector2(3.3, 3.9), Vector2(3.5, 4.3), Vector2(3.7, 4.7), Vector2(3.9, 5.0),
	Vector2(4.1, 5.3), Vector2(4.3, 5.5), Vector2(4.5, 5.65), Vector2(4.7, 5.75),
	Vector2(4.9, 5.8), Vector2(5.1, 5.82),
	Vector2(5.3, 5.8),
	Vector2(5.32, 5.75), Vector2(5.34, 5.7), Vector2(5.36, 5.65), Vector2(5.38, 5.6),
	Vector2(5.42, 5.55), Vector2(5.46, 5.5), Vector2(5.5, 5.45),
	Vector2(5.6, 5.4), Vector2(7.4, 3.9), Vector2(9.6, 2.5), Vector2(12.5, 1.3),
	Vector2(16.0, 0.4), Vector2(20.0, -0.6),
]
## Índice (en REST_*) de la punta del labio.
const TIP_INDEX := 10
## Adelante: en cuántos metros la ola se abre (deja de ser tubo) y en cuántos baja
## hasta el agua. Atrás: en cuántos metros se desarma.
const FRONT_OPEN := 14.0
const FRONT_DROP := 22.0
const BACK_DROP := 9.0
## Cuánto queda bajo el agua donde la ola termina (m), y la parte plana de la cara.
const SINK := 0.6
const FLAT_SINK := 0.2


func _ready() -> void:
	add_to_group("tube_waves")


## Prepara la ola. `mouth_angle`/`p_lateral`: dónde está la boca; `p_side`:
## hacia qué lado está la pared (+1 hacia el lateral positivo).
func setup(
	p_course: Course, p_mouth_angle: float, p_lateral: float, p_side: float,
	p_duration: float, p_speed: float, p_opener: Rider = null, p_open_timeout: float = 6.0
) -> void:
	course = p_course
	track = course.track
	water = GameSession.find_in_scene(course, "water") as Water
	mouth_angle = p_mouth_angle
	lateral = p_lateral
	side = 1.0 if p_side >= 0.0 else -1.0
	duration = p_duration
	speed = p_speed
	opener = p_opener
	open_timeout = p_open_timeout
	_build_spine()
	_clear_swells()
	_build_visual()
	_hide_obstacles()
	_rebuild()


## Metros de pista que ocupa como mucho (desde la boca): para saber si entra
## antes de la meta y qué obstáculos esconder.
func max_length() -> float:
	return OPEN_LENGTH + speed * (duration + ENTRY_WINDOW) + AHEAD_START + 20.0


## Metros por radián de ángulo de pista.
func meters_per_angle() -> float:
	return track.length() / TAU


# --- El recorrido del tubo ----------------------------------------------------
# Sigue la pista, pero suavizado: sin curvas cerradas (corta un poco las curvas).
# `s` se mide sobre este recorrido, desde la boca.

## Separación de los puntos del recorrido (m), cuántos metros antes de la boca
## empieza, y el suavizado (promedio de ±SMOOTH_REACH puntos, SMOOTH_PASSES veces).
const SPINE_STEP := 2.0
const SPINE_BEFORE := 14.0
const SMOOTH_REACH := 7
const SMOOTH_PASSES := 4

var _spine := PackedVector3Array()
var _arc := PackedFloat32Array()
## Hacia dónde queda "lateral +" de la pista, girando la dirección de avance (±1).
var _turn: float = 1.0


## Puntos del recorrido suavizado (y = 0), desde SPINE_BEFORE m antes de la boca.
static func make_spine(p_track: TrackSpace, p_mouth: float, p_lateral: float, length: float) -> PackedVector3Array:
	var per_m := TAU / p_track.length()
	var n := int((length + SPINE_BEFORE) / SPINE_STEP) + 2
	var pts := PackedVector3Array()
	for i in n:
		var sm := -SPINE_BEFORE + i * SPINE_STEP
		pts.append(p_track.position_at(p_mouth + sm * per_m, p_lateral))
	for pass_i in SMOOTH_PASSES:
		var out := PackedVector3Array()
		out.resize(n)
		for i in n:
			var acc := Vector3.ZERO
			var count := 0
			for k in range(-SMOOTH_REACH, SMOOTH_REACH + 1):
				acc += pts[clampi(i + k, 0, n - 1)]
				count += 1
			out[i] = acc / count
		pts = out
	return pts


## Dirección "hacia la pared" en cada punto del recorrido (para chequear el lugar).
static func spine_wall_dirs(p_track: TrackSpace, p_mouth: float, p_lateral: float, p_side: float, pts: PackedVector3Array) -> PackedVector3Array:
	var turn := _turn_sign(p_track, p_mouth, p_lateral, pts)
	var dirs := PackedVector3Array()
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		dirs.append(Vector3(-t.z, 0.0, t.x) * turn * p_side)
	return dirs


static func _turn_sign(p_track: TrackSpace, p_mouth: float, p_lateral: float, pts: PackedVector3Array) -> float:
	var lat_dir := p_track.position_at(p_mouth, p_lateral + 1.0) - p_track.position_at(p_mouth, p_lateral)
	var i0 := int(SPINE_BEFORE / SPINE_STEP)
	var t := (pts[i0 + 1] - pts[i0]).normalized()
	return 1.0 if Vector3(-t.z, 0.0, t.x).dot(lat_dir) >= 0.0 else -1.0


func _build_spine() -> void:
	_spine = make_spine(track, mouth_angle, lateral, max_length() + 40.0)
	_turn = _turn_sign(track, mouth_angle, lateral, _spine)
	_arc = PackedFloat32Array()
	_arc.resize(_spine.size())
	var acc := 0.0
	for i in _spine.size():
		if i > 0:
			acc += _spine[i].distance_to(_spine[i - 1])
		_arc[i] = acc
	# s = 0 en la boca.
	var zero := _arc[int(SPINE_BEFORE / SPINE_STEP)]
	for i in _arc.size():
		_arc[i] -= zero


func _segment_at(s: float) -> int:
	var lo := 0
	var hi := _arc.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _arc[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Punto del recorrido en `s`, la dirección hacia la pared y la de avance.
## Devuelve [origen (y = 0), hacia la pared, hacia adelante].
func frame_at(s: float) -> Array:
	var i := _segment_at(s)
	var a := _spine[i]
	var b := _spine[i + 1]
	var len_ab := maxf(_arc[i + 1] - _arc[i], 0.001)
	var t := (s - _arc[i]) / len_ab
	var o := a.lerp(b, t)
	# Dirección suave (mezcla con la del tramo siguiente).
	var d0 := (b - a).normalized()
	var d1 := (_spine[mini(i + 2, _spine.size() - 1)] - b).normalized()
	if d1 == Vector3.ZERO:
		d1 = d0
	var fwd := d0.lerp(d1, clampf(t, 0.0, 1.0)).normalized()
	var w := Vector3(-fwd.z, 0.0, fwd.x) * _turn * side
	return [o, w, fwd]


## Rumbo (rotación en Y de un Rider) que sigue el tubo en `s`.
func heading_at(s: float) -> float:
	var f: Vector3 = frame_at(s)[2]
	return atan2(-f.x, -f.z)


## [s, u] de un punto respecto del recorrido (el tramo más cercano).
func locate(p: Vector3) -> Vector2:
	var best := INF
	var best_s := 0.0
	var best_u := 0.0
	var q := Vector3(p.x, 0.0, p.z)
	for i in _spine.size() - 1:
		var a := _spine[i]
		var ab := _spine[i + 1] - a
		var k := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * k
		var d := q.distance_squared_to(c)
		if d < best:
			best = d
			best_s = _arc[i] + k * (_arc[i + 1] - _arc[i])
			var w := Vector3(-ab.z, 0.0, ab.x).normalized() * _turn * side
			best_u = (q - c).dot(w)
	return Vector2(best_s, best_u)


## Metros desde la boca de un punto (negativo: antes de la boca).
func s_of(p: Vector3) -> float:
	var st := wrapf(track.angle_of(p) - mouth_angle, -PI, PI) * meters_per_angle()
	if st < -SPINE_BEFORE + 2.0:
		return st
	return locate(p).x


## Desvío de costado (u) de un punto respecto de la línea del tubo.
func u_of(p: Vector3) -> float:
	return locate(p).y


## Desvío lateral de la pista donde está la boca (adonde ir para entrar).
func mouth_lateral() -> float:
	return track.lateral_of(frame_at(0.0)[0])


## Altura de la cara de la ola en `u` (sobre el agua de abajo).
static func face_y(u: float) -> float:
	var k := clampf((u - FACE_FROM) / (FACE_TO - FACE_FROM), 0.0, 1.0)
	return FACE_HEIGHT * k * k


## Pendiente de la cara en `u` (cuánto sube por metro hacia la pared).
static func face_slope(u: float) -> float:
	var k := clampf((u - FACE_FROM) / (FACE_TO - FACE_FROM), 0.0, 1.0)
	return 2.0 * FACE_HEIGHT * k / (FACE_TO - FACE_FROM)


## Altura del agua de abajo (con las olas) en un punto.
func base_height(p: Vector3) -> float:
	return water.height_at(p.x, p.z) if water else 0.0


## true mientras se puede entrar por la boca.
func accepting() -> bool:
	if phase == Phase.OPENING:
		return age >= RISE_TIME * 0.5
	return phase == Phase.RIDING and ride_time < ENTRY_WINDOW


## Segundos que le quedan adentro (para todos los que están).
func time_left() -> float:
	if ride_time < 0.0:
		return duration
	return maxf(duration - ride_time, 0.0)


## 0..1: cuánto del tubo ya pasó (la luz del final se acerca).
func progress() -> float:
	return clampf(ride_time / duration, 0.0, 1.0) if ride_time >= 0.0 else 0.0


## Entra un surfista (lo llama la ola cuando pasa por la boca, o un test).
func enter(rider: Rider, s: float = 0.0) -> void:
	if rider in inside or used.has(rider):
		return
	used[rider] = true
	inside[rider] = s
	rider.tube_exited.connect(_on_rider_exited.bind(rider), CONNECT_ONE_SHOT)
	if phase == Phase.OPENING:
		phase = Phase.RIDING
		ride_time = 0.0
	rider.enter_tube(self)
	rider_entered.emit(rider)


## Salió por adelante: la ola lo escupe (chorro de espuma).
func _on_rider_exited(success: bool, rider: Rider) -> void:
	if success and is_instance_valid(rider):
		spit_at(rider)


## Chorro de espuma y gotas saliendo de la boca de adelante, detrás del surfista.
func spit_at(rider: Rider) -> void:
	if _spit == null:
		return
	var fwd := rider.forward()
	var xf := Transform3D(Basis.looking_at(fwd, Vector3.UP), rider.global_position + Vector3.UP * 1.2 - fwd * 1.5)
	for p in [_spit, _spit_mist]:
		var part := p as CPUParticles3D
		part.global_transform = xf
		part.restart()
		part.emitting = true


## El estado del surfista avisa que salió (terminó o se cayó).
func leave(rider: Rider) -> void:
	inside.erase(rider)
	# Nadie más adentro y ya no se puede entrar: se desarma.
	if inside.is_empty() and phase == Phase.RIDING and not accepting():
		_start_collapse()


## Se termina ya (al reiniciar, o si hay que sacarla).
func dismiss() -> void:
	for r in inside.keys():
		var rider := r as Rider
		if is_instance_valid(rider) and rider.tube == self:
			rider.state_machine.transition_to(&"riding")
	inside.clear()
	_start_collapse()


func _physics_process(delta: float) -> void:
	age += delta
	match phase:
		Phase.OPENING:
			_check_entries()
			if age > open_timeout:
				_start_collapse()
		Phase.RIDING:
			ride_time += delta
			if accepting():
				_check_entries()
			# Los que se fueron de la partida (reinicio) se olvidan.
			for r in inside.keys():
				if not is_instance_valid(r):
					inside.erase(r)
			if inside.is_empty() and not accepting():
				_start_collapse()
			elif ride_time >= duration + 0.5:
				# Seguro: el estado de cada uno sale solo al terminar el tiempo.
				_start_collapse()
		Phase.CLOSING:
			_collapse += delta / COLLAPSE_TIME
			if _collapse >= 1.0:
				_finish()


func _process(_delta: float) -> void:
	_rebuild()


## Los que pasan por la boca (cerca de la línea y del agua) entran.
func _check_entries() -> void:
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r == null or r.water != water or used.has(r) or r.in_tube():
			continue
		if r.is_fallen() or r.race_finished or r.controls_locked:
			continue
		var s := s_of(r.position)
		if s < -0.5 or s > 3.0:
			continue
		var u := u_of(r.position)
		if u < -MOUTH_OPEN_SIDE or u > MOUTH_WALL_SIDE:
			continue
		if r.position.y - base_height(r.position) > MOUTH_MAX_AIR:
			continue
		enter(r, maxf(s, 0.0))


func _start_collapse() -> void:
	if phase == Phase.CLOSING:
		return
	phase = Phase.CLOSING
	_collapse = 0.0


func _finish() -> void:
	set_physics_process(false)
	set_process(false)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	_show_obstacles()


# --- Obstáculos ---------------------------------------------------------------

## Los aros y rocas del tramo del tubo desaparecen mientras está.
func _hide_obstacles() -> void:
	var from := -6.0
	var to := max_length() + 20.0
	var items: Array[Node3D] = []
	for ring in course.rings:
		items.append(ring)
	for rock in course.rocks:
		items.append(rock)
	for item in items:
		if not item.visible:
			continue
		var su := locate(item.global_position)
		if su.x >= from and su.x <= to and absf(su.y) < 30.0:
			item.visible = false
			_hidden.append(item)


## Las olas grandes que andan por el tramo del tubo se van (se mezclarían con él).
func _clear_swells() -> void:
	if water == null or water.swells.is_empty():
		return
	var keep: Array[Swell] = []
	for sw in water.swells:
		var c := Vector3(sw.center.x, 0.0, sw.center.y)
		var near := false
		var i := 0
		while i < _spine.size():
			if _spine[i].distance_to(c) < SWELL_CLEARANCE:
				near = true
				break
			i += 5
		if not near:
			keep.append(sw)
	if keep.size() != water.swells.size():
		water.swells = keep
		water.clear_swells() if keep.is_empty() else water._push_swells()


## Distancia (m) al tubo dentro de la que se sacan las olas grandes.
const SWELL_CLEARANCE := 45.0


func _show_obstacles() -> void:
	for item in _hidden:
		if is_instance_valid(item):
			item.visible = true
	_hidden.clear()


# --- Dibujo ---------------------------------------------------------------------

func _build_visual() -> void:
	_mesh = ArrayMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Wave"
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La malla se arma en coordenadas del mundo.
	_mesh_instance.top_level = true
	add_child(_mesh_instance)
	_mesh_instance.global_transform = Transform3D.IDENTITY
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("flow", speed)
	if course and DayTime.is_night(course):
		_material.set_shader_parameter("brightness", 0.55)
	elif course and course.time_of_day == GameSettings.TimeOfDay.SUNSET:
		_material.set_shader_parameter("brightness", 0.85)

	# La luz del final: un brillo redondo que siempre mira a la cámara.
	_glow_mat = glow_material()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_glow = MeshInstance3D.new()
	_glow.name = "ExitLight"
	_glow.mesh = quad
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.top_level = true
	add_child(_glow)

	_back_foam = _particles(48, 0.9, 0.55, Color(0.96, 0.99, 1.0))
	_back_foam.name = "BackFoam"
	_back_foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_back_foam.emission_box_extents = Vector3(3.2, 1.2, 0.6)
	_back_foam.direction = Vector3(0.0, 1.0, -0.6)
	_back_foam.spread = 35.0
	_back_foam.initial_velocity_min = 3.0
	_back_foam.initial_velocity_max = 7.0
	_back_foam.gravity = Vector3(0.0, -9.0, 0.0)
	_back_foam.emitting = false

	_lip_drops = _particles(40, 0.8, 0.18, Color(0.85, 0.97, 1.0))
	_lip_drops.name = "LipDrops"
	_lip_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_lip_drops.emission_box_extents = Vector3(0.4, 0.1, 9.0)
	_lip_drops.direction = Vector3(0.0, -1.0, 0.0)
	_lip_drops.spread = 15.0
	_lip_drops.initial_velocity_min = 0.5
	_lip_drops.initial_velocity_max = 1.5
	_lip_drops.gravity = Vector3(0.0, -12.0, 0.0)
	_lip_drops.emitting = false

	_spit = _particles(70, 0.9, 0.4, Color(0.97, 1.0, 1.0))
	_spit.name = "Spit"
	_spit.one_shot = true
	_spit.explosiveness = 0.85
	_spit.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spit.emission_sphere_radius = 1.0
	# Hacia adelante (el -Z del nodo, que se orienta como el surfista).
	_spit.direction = Vector3(0.0, 0.25, -1.0)
	_spit.spread = 22.0
	_spit.initial_velocity_min = 14.0
	_spit.initial_velocity_max = 26.0
	_spit.gravity = Vector3(0.0, -9.0, 0.0)
	_spit.damping_min = 6.0
	_spit.damping_max = 10.0
	_spit.emitting = false

	_spit_mist = _particles(24, 1.3, 1.1, Color(0.9, 0.97, 1.0, 0.6))
	_spit_mist.name = "SpitMist"
	_spit_mist.one_shot = true
	_spit_mist.explosiveness = 0.9
	_spit_mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spit_mist.emission_sphere_radius = 1.5
	_spit_mist.direction = Vector3(0.0, 0.2, -1.0)
	_spit_mist.spread = 30.0
	_spit_mist.initial_velocity_min = 6.0
	_spit_mist.initial_velocity_max = 12.0
	_spit_mist.damping_min = 5.0
	_spit_mist.damping_max = 8.0
	_spit_mist.emitting = false


## Material del brillo de la salida.
static func glow_material() -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 0.95, 1.0))
	grad.set_color(1, Color(1.0, 0.95, 0.7, 0.0))
	grad.add_point(0.35, Color(1.0, 0.98, 0.85, 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	return mat


## Materiales de la ola (para prepararlos antes de que aparezca: sin tirones).
static func warmup_materials() -> Array[Material]:
	var wave := ShaderMaterial.new()
	wave.shader = SHADER
	return [wave, glow_material()]


## Partículas blancas simples (bolitas de espuma que se achican al final).
func _particles(amount: int, lifetime: float, size: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.top_level = true
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.mesh = mesh
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	add_child(p)
	return p


## Tramo que se dibuja ahora [desde, hasta] (m desde la boca).
func span() -> Vector2:
	if phase == Phase.OPENING or ride_time < 0.0:
		return Vector2(0.0, OPEN_LENGTH)
	var lo := INF
	var hi := -INF
	for r in inside:
		var s: float = inside[r]
		lo = minf(lo, s)
		hi = maxf(hi, s)
	if inside.is_empty():
		lo = drawn_from + BEHIND
		hi = drawn_to - lerpf(AHEAD_START, AHEAD_END, progress())
	var ahead := lerpf(AHEAD_START, AHEAD_END, progress())
	var back := lo - BEHIND
	# Mientras la boca sigue abierta, el tubo empieza en la boca.
	if accepting():
		back = minf(back, 0.0)
	return Vector2(maxf(back, -2.0), maxf(hi + ahead, back + 4.0))


## Altura general (0..1): se levanta al aparecer y se desarma al final.
func _height_scale() -> float:
	var rise := smoothstep(0.0, RISE_TIME, age)
	if phase == Phase.CLOSING:
		rise *= 1.0 - smoothstep(0.0, 1.0, _collapse)
	return rise


## Perfil (u, y) del corte con el labio cerrado en `closed` (0..1).
func profile(closed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for u in FACE_US:
		# La parte plana queda apenas bajo el agua (la cara sale del agua).
		var y := face_y(u) - FLAT_SINK * (1.0 - smoothstep(-1.5, 0.6, u))
		if u < -6.0:
			y = lerpf(-SINK, -FLAT_SINK, inverse_lerp(-11.0, -6.0, u))
		pts.append(Vector2(u, y))
	for i in REST_CLOSED.size():
		pts.append((REST_OPEN[i] as Vector2).lerp(REST_CLOSED[i], closed))
	return pts


## Zona de cada punto del perfil para el shader: 0 (cara, lejos) .. 1 (punta del
## labio) .. 2 (fin de la espalda).
func _zone(k: int) -> float:
	var tip := FACE_US.size() + TIP_INDEX
	var last := FACE_US.size() + REST_CLOSED.size() - 1
	if k <= tip:
		return float(k) / float(tip)
	return 1.0 + float(k - tip) / float(last - tip)


func _rebuild() -> void:
	if _mesh == null:
		return
	var sp := span()
	drawn_from = sp.x
	drawn_to = sp.y
	var hs := _height_scale()
	_mesh.clear_surfaces()
	if hs <= 0.001:
		_place_effects(sp, hs)
		return
	# Más allá de la parte "llena", la ola baja hasta el agua de los dos lados.
	var lo := sp.x - BACK_DROP
	var hi := sp.y + FRONT_DROP
	var rings := maxi(int(ceil((hi - lo) / RING_STEP)), 2)
	var count := FACE_US.size() + REST_CLOSED.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize((rings + 1) * count)
	uvs.resize(verts.size())
	uv2s.resize(verts.size())
	var zones := PackedFloat32Array()
	for k in count:
		zones.append(_zone(k))
	for i in rings + 1:
		var s := lerpf(lo, hi, float(i) / rings)
		# Adelante se abre y baja; atrás se desarma (baja).
		var to_front := sp.y + FRONT_DROP - s
		var from_back := s - lo
		# Atrás el labio se cae (se abre) mientras baja: espuma, no una aleta.
		var closed := smoothstep(FRONT_DROP, FRONT_DROP + FRONT_OPEN, to_front) * smoothstep(0.0, BACK_DROP, from_back)
		var h := hs * sqrt(smoothstep(0.0, FRONT_DROP, to_front)) * smoothstep(0.0, BACK_DROP, from_back)
		var f := frame_at(s)
		var o: Vector3 = f[0]
		var w: Vector3 = f[1]
		var pts := profile(closed)
		var base := base_height(o)
		for k in count:
			var p: Vector2 = pts[k]
			var y := p.y * h - SINK * (1.0 - h)
			var idx := i * count + k
			verts[idx] = o + w * p.x + Vector3.UP * (base + y)
			uvs[idx] = Vector2(zones[k], s)
			uv2s[idx] = Vector2(maxf(p.y, 0.0) * h, closed)
	for i in rings:
		for k in count - 1:
			var a := i * count + k
			var b := a + count
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	# Normales (para la luz falsa del shader): a lo largo y a lo ancho.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in rings + 1:
		for k in count:
			var along := verts[mini(i + 1, rings) * count + k] - verts[maxi(i - 1, 0) * count + k]
			var across := verts[i * count + mini(k + 1, count - 1)] - verts[i * count + maxi(k - 1, 0)]
			normals[i * count + k] = across.cross(along).normalized()
	# Que la cara (abajo, del lado abierto) mire hacia arriba.
	if normals[int(rings / 2.0) * count + 2].y < 0.0:
		for n in normals.size():
			normals[n] = -normals[n]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, _material)
	# Mientras espera en la boca, todavía no rompió (sin espuma atrás).
	_material.set_shader_parameter("back_s", sp.x if phase != Phase.OPENING else -1000.0)
	_material.set_shader_parameter("front_s", sp.y)
	_material.set_shader_parameter("exit_light", progress())
	_place_effects(sp, hs)


## La luz de la salida, la espuma de atrás y las gotas del labio siguen al tubo.
func _place_effects(sp: Vector2, hs: float) -> void:
	var riding := phase == Phase.RIDING and not inside.is_empty()
	# La luz: en la boca de adelante, adentro del tubo. Más grande y fuerte
	# cuanto más cerca está la salida.
	var f := frame_at(sp.y - FRONT_OPEN * 0.55)
	var o: Vector3 = f[0]
	var w: Vector3 = f[1]
	var k := progress() if riding else 0.15
	_glow.global_position = o + w * 0.3 + Vector3.UP * (base_height(o) + 2.6 * hs)
	var size := lerpf(4.0, 7.5, k) * hs
	_glow.scale = Vector3(size, size, size)
	_glow_mat.albedo_color = Color(1.0, 1.0, 1.0, lerpf(0.45, 1.0, k) * hs)
	_glow.visible = hs > 0.05 and phase != Phase.CLOSING
	# La espuma: donde la ola ya rompió, atrás.
	_back_foam.emitting = riding
	if riding:
		var b := frame_at(sp.x - 2.0)
		var bo: Vector3 = b[0]
		var bw: Vector3 = b[1]
		var bf: Vector3 = b[2]
		_back_foam.global_transform = Transform3D(
			Basis.looking_at(bf, Vector3.UP), bo + bw * 0.5 + Vector3.UP * (base_height(bo) + 1.5)
		)
	# Gotas que caen de la punta del labio, alrededor del primero.
	_lip_drops.emitting = riding
	if riding:
		var lead := -INF
		for r in inside:
			lead = maxf(lead, float(inside[r]))
		var l := frame_at(lead + 3.0)
		var lo: Vector3 = l[0]
		var lw: Vector3 = l[1]
		var lf: Vector3 = l[2]
		var tip: Vector2 = REST_CLOSED[TIP_INDEX]
		_lip_drops.global_transform = Transform3D(
			Basis.looking_at(lf, Vector3.UP), lo + lw * tip.x + Vector3.UP * (base_height(lo) + tip.y * hs)
		)
