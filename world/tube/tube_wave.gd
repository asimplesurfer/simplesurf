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
const OPEN_LENGTH := 26.0
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
const BEHIND := 7.0
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

var _mesh_instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: Material
var _collapse: float = 0.0
## Aros y rocas que se escondieron (para volver a mostrarlos).
var _hidden: Array[Node3D] = []
## Último tramo dibujado [desde, hasta] (m): lo usan los tests y la cámara.
var drawn_from: float = 0.0
var drawn_to: float = 0.0

## Perfil del tubo cerrado (u, y): la cara (sale de face_y) y arriba el labio
## que se curva por encima y cae del lado abierto.
const LIP_CLOSED := [
	Vector2(3.2, 3.6), Vector2(3.5, 4.6), Vector2(3.3, 5.5), Vector2(2.6, 6.1),
	Vector2(1.5, 6.4), Vector2(0.2, 6.3), Vector2(-1.0, 5.8), Vector2(-2.0, 5.0),
	Vector2(-2.6, 4.1), Vector2(-2.8, 3.4), Vector2(-2.6, 3.0),
]
## El mismo labio sin cerrar (la ola recién se levanta / la punta de la salida):
## una cresta que cae hacia atrás.
const LIP_OPEN := [
	Vector2(3.2, 3.4), Vector2(3.6, 4.0), Vector2(4.1, 4.3), Vector2(4.6, 4.4),
	Vector2(5.2, 4.3), Vector2(5.8, 4.0), Vector2(6.3, 3.5), Vector2(6.8, 2.9),
	Vector2(7.2, 2.2), Vector2(7.6, 1.5), Vector2(8.0, 0.8),
]
## Puntos de la cara (u) antes del labio.
const FACE_US := [-6.0, -3.5, -1.5, -0.6, 0.3, 1.1, 1.9, 2.6]


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
	_build_visual()
	_hide_obstacles()
	_rebuild()


## Metros de pista que ocupa como mucho (desde la boca): para saber si entra
## antes de la meta y qué obstáculos esconder.
func max_length() -> float:
	return OPEN_LENGTH + speed * (duration + ENTRY_WINDOW) + AHEAD_START


## Metros por radián de ángulo de pista.
func meters_per_angle() -> float:
	return track.length() / TAU


func angle_at(s: float) -> float:
	return mouth_angle + s / meters_per_angle()


## Metros desde la boca de un punto (negativo: antes de la boca).
func s_of(p: Vector3) -> float:
	return wrapf(track.angle_of(p) - mouth_angle, -PI, PI) * meters_per_angle()


## Desvío de costado (u) de un punto respecto de la línea del tubo.
func u_of(p: Vector3) -> float:
	return (track.lateral_of(p) - lateral) * side


## Punto de la línea del tubo en `s`, la dirección hacia la pared y la de avance.
## Devuelve [origen (y = 0), hacia la pared, hacia adelante].
func frame_at(s: float) -> Array:
	var a := angle_at(s)
	var o := track.position_at(a, lateral)
	var w := (track.position_at(a, lateral + side) - o).normalized()
	return [o, w, track.tangent_at(a)]


## Rumbo (rotación en Y de un Rider) que sigue el tubo en `s`.
func heading_at(s: float) -> float:
	return track.heading_at(angle_at(s))


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
	if phase == Phase.OPENING:
		phase = Phase.RIDING
		ride_time = 0.0
	rider.enter_tube(self)
	rider_entered.emit(rider)


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
		var s := s_of(item.global_position)
		if s >= from and s <= to:
			item.visible = false
			_hidden.append(item)


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
	_mesh_instance.global_transform = Transform3D.IDENTITY
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material = mat
	add_child(_mesh_instance)


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


## Perfil (u, y) del corte del tubo con el labio cerrado en `closed` (0..1).
func profile(closed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for u in FACE_US:
		pts.append(Vector2(u, face_y(u)))
	for i in LIP_CLOSED.size():
		pts.append((LIP_OPEN[i] as Vector2).lerp(LIP_CLOSED[i], closed))
	return pts


func _rebuild() -> void:
	if _mesh == null:
		return
	var sp := span()
	drawn_from = sp.x
	drawn_to = sp.y
	var hs := _height_scale()
	_mesh.clear_surfaces()
	if hs <= 0.001:
		return
	var rings := maxi(int(ceil((sp.y - sp.x) / RING_STEP)), 2)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := 0
	for i in rings + 1:
		var s := lerpf(sp.x, sp.y, float(i) / rings)
		# Las puntas: adelante el labio se abre (la salida) y atrás la ola ya
		# rompió (baja). En el medio, el tubo cerrado.
		var front := smoothstep(sp.y, sp.y - 6.0, s)
		var back_k := smoothstep(sp.x, sp.x + 4.0, s)
		var closed := front
		var h := hs * lerpf(0.35, 1.0, back_k)
		var f := frame_at(s)
		var o: Vector3 = f[0]
		var w: Vector3 = f[1]
		var pts := profile(closed)
		count = pts.size()
		var base := base_height(o)
		for k in count:
			var p: Vector2 = pts[k]
			var pos := o + w * p.x + Vector3.UP * (base + p.y * h)
			verts.append(pos)
			colors.append(_color_for(k, count))
	for i in rings:
		for k in count - 1:
			var a := i * count + k
			var b := a + count
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, _material)


## Color de cada punto del perfil: abajo oscuro, la cara turquesa y el labio blanco.
func _color_for(k: int, count: int) -> Color:
	var t := float(k) / float(count - 1)
	var deep := Color(0.05, 0.35, 0.5)
	var face := Color(0.2, 0.75, 0.8)
	var lip := Color(0.92, 0.98, 1.0)
	if t < 0.4:
		return deep.lerp(face, t / 0.4)
	return face.lerp(lip, smoothstep(0.55, 1.0, t))
