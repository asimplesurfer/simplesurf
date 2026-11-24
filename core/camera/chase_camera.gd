class_name ChaseCamera
extends Camera3D
## Cámara que sigue al Rider desde atrás. Una por jugador (player_index).

@export var target_path: NodePath
## Distancia andando. Quieto (o casi) va más lejos: STOPPED_DISTANCE.
@export var distance: float = 3.0
const STOPPED_DISTANCE := 4.5
## Desde esta velocidad (m/s) ya va a la distancia de andar.
const MOVING_SPEED := 5.0
@export var height: float = 2.7
@export var look_height: float = 1.0
## Cámara más cerca cuando está caído, para ver bien la animación.
@export var fallen_distance: float = 3.0
@export var fallen_height: float = 3.2
@export var follow_sharpness: float = 5.0

## Se puede asignar antes de agregar la cámara al árbol (lo hace SplitScreen).
var target: Rider
## Altura mínima de la cámara sobre el agua (para no quedar adentro de una ola grande).
const MIN_ABOVE_WATER := 1.5

var _water: Water
## Cuánto sigue la altura del personaje: poco en el agua (para no marear con
## cada ola) y todo en el aire (para no perderlo cuando sube mucho).
var _follow_y: float = 0.6

## Sacudón (al atravesar una ola): se va apagando solo.
var _shake: float = 0.0

## Mirando hacia atrás (gatillo izquierdo): la cámara pasa adelante del Rider.
var looking_back: bool = false

const BASE_FOV := 70.0
const BOOST_FOV := 82.0

## Con turbo o motivación la cámara se aleja hacia atrás (sensación de
## velocidad): TURBO_BASE + esto (8,3 m).
const BOOST_PULLBACK := 2.3
## Con turbo, la distancia es esta + el alejamiento (la cámara antes iba a 6 m).
const TURBO_BASE := 6.0
## Mirando hacia atrás va más lejos que de frente: al ir rápido la cámara se
## atrasa un poco, y desde cerca quedaría encima del personaje.
const LOOK_BACK_DISTANCE := 6.0
## Mirando hacia atrás, apunta a este punto detrás del personaje (m).
const LOOK_BACK_FAR := 22.0
## Adentro del tubo: distancia y altura de la cámara (m).
const TUBE_DISTANCE := 4.2
const TUBE_HEIGHT := 1.9
## Adentro del tubo la cámara va en el medio del tubo, detrás del surfista, y
## mira hacia la salida (la luz). Tarda esto en entrar y en salir (s).
const TUBE_BLEND_TIME := 0.2
const TUBE_CAM_BACK := 3.6
const TUBE_CAM_HEIGHT := 1.75
## Hacia la pared desde la línea del tubo (m): el medio del hueco.
const TUBE_CAM_U := 0.4
const TUBE_LOOK_AHEAD := 14.0
## Desde cuántos metros antes de la boca la cámara empieza a bajar y alinearse.
const TUBE_APPROACH := 16.0
var _tube_blend: float = 0.0
## Al salir del tubo, vuelve a la cámara de siempre en este tiempo (s).
const TUBE_EXIT_TIME := 0.7
var _exit_offsets: Array = []
## 0..1: qué tan cerca está de la boca de un tubo (la cámara baja de a poco).
var _tube_approach: float = 0.0
var _approach_smooth: float = 0.0
## [posición, a dónde mira] de la cámara del tubo (vacío si no hay).
var _tube_frame: Array = []
## 0..1: cuánto se alejó (se acerca y aleja suave).
var _boost: float = 0.0


func _ready() -> void:
	# Después del Rider, para seguir su posición de este frame.
	process_priority = 10
	if target == null:
		target = get_node_or_null(target_path) as Rider
	if target:
		# Atravesar una ola no sacude la cámara (mareaba y no sumaba nada).
		# Lo chocaron: un sacudón según la fuerza del golpe.
		target.bumped.connect(func(_dir: Vector3, strength: float) -> void: shake(0.2 + 0.4 * strength))
		# Chocó a otro: un sacudón chico. Cayó de un salto alto: según la altura.
		target.bumped_other.connect(func(_victim: Rider) -> void: shake(0.25))
		target.hard_landed.connect(func(strength: float) -> void: shake(0.15 + 0.35 * strength))
		# El tubo lo escupe: un golpe de cámara.
		target.tube_exited.connect(func(success: bool) -> void: shake(0.45 if success else 0.3))
	_water = GameSession.find_in_scene(self, "water") as Water
	if target:
		global_position = _desired_position()
		look_at(_look_point(), Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	# En el borde de una ola (modo trucos) va alto: se sigue toda la altura.
	var follow_target := 0.6 if target.grounded and not target.on_lip() else 1.0
	_follow_y = lerpf(_follow_y, follow_target, 1.0 - exp(-3.0 * delta))
	var w := 1.0 - exp(-follow_sharpness * minf(delta, 0.1))
	var boosting_now := boosting()
	_boost = move_toward(_boost, 1.0 if boosting_now else 0.0, delta * (2.5 if boosting_now else 1.5))
	var back := target.input != null and target.input.look_back and not target.is_fallen()
	# Adentro del tubo (y llegando a la boca): la cámara va baja y en el medio
	# del tubo. Llegando se mezcla de a poco según lo cerca de la boca; al salir
	# vuelve de una a la cámara de siempre (que ya está justo detrás).
	var tube_target := 0.0
	_tube_frame = []
	if target.in_tube() and target.tube != null:
		_tube_frame = _tube_view(target.tube, INF)
		tube_target = 1.0
	_tube_approach = 0.0
	if tube_target <= 0.0 and not target.is_fallen():
		# Llegando a la boca: la cámara de siempre, pero más baja y más cerca
		# (así pasa por abajo del labio al entrar).
		for node in target.get_tree().get_nodes_in_group("tube_waves"):
			var tw := node as TubeWave
			if tw == null or not tw.accepting() or tw.used.has(target):
				continue
			var s_here := tw.s_of(target.global_position)
			if s_here > -TUBE_APPROACH and s_here < 2.0 and absf(tw.u_of(target.global_position)) < 9.0:
				_tube_approach = smoothstep(-TUBE_APPROACH, -TUBE_APPROACH * 0.35, s_here)
				break
	_approach_smooth = move_toward(_approach_smooth, _tube_approach, delta * 3.0)
	if tube_target > 0.0:
		_tube_blend = move_toward(_tube_blend, tube_target, delta / TUBE_BLEND_TIME)
		# Dónde queda respecto del surfista (para salir suave).
		if not _tube_frame.is_empty():
			var rp := target.render_transform().origin
			_exit_offsets = [_tube_frame[0] - rp, _tube_frame[1] - rp]
	elif _tube_blend > 0.0 and not _exit_offsets.is_empty():
		# Recién salió: sigue un ratito igual de baja, pegada detrás, y vuelve
		# de a poco a la de siempre.
		_tube_blend = move_toward(_tube_blend, 0.0, delta / TUBE_EXIT_TIME)
		var rp := target.render_transform().origin
		_tube_frame = [rp + _exit_offsets[0], rp + _exit_offsets[1]]
	else:
		_tube_blend = 0.0
	var desired := _desired_position()
	# En el borde de una ola (modo trucos): la cámara da una vuelta alrededor
	# del surfista, subiendo y bajando; termina detrás, como siempre.
	if target.on_lip() and not back:
		var orbit := _lip_orbit()
		desired = desired.lerp(orbit[0], orbit[1])
	if back != looking_back:
		# Corte directo (si no, la cámara atravesaría al personaje).
		looking_back = back
		desired = _desired_position()
		global_position = desired
	global_position = global_position.lerp(desired, w)
	if _tube_blend > 0.0 and not _tube_frame.is_empty():
		# Adentro del tubo va pegada (sin el retraso de siempre: a esta velocidad
		# quedaría afuera del tubo).
		var k := smoothstep(0.0, 1.0, _tube_blend)
		global_position = global_position.lerp(_tube_frame[0], k)
	# En el aire, la altura se sigue más rápido para que no se escape de cuadro.
	if not target.grounded:
		var wy := 1.0 - exp(-follow_sharpness * 2.0 * minf(delta, 0.1))
		global_position.y = lerpf(global_position.y, desired.y, wy)
	# Nunca debajo del agua (con olas grandes, la cámara podía quedar adentro).
	if _water and _tube_blend <= 0.0:
		var h := _water.height_at(global_position.x, global_position.z) + MIN_ABOVE_WATER
		if global_position.y < h:
			global_position.y = h
	var look := _look_point()
	if _tube_blend > 0.0 and not _tube_frame.is_empty():
		look = look.lerp(_tube_frame[1], smoothstep(0.0, 1.0, _tube_blend))
	look_at(look, Vector3.UP)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		var s := _shake * _shake
		rotate_object_local(Vector3.RIGHT, randf_range(-1.0, 1.0) * 0.05 * s)
		rotate_object_local(Vector3.UP, randf_range(-1.0, 1.0) * 0.05 * s)
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.25 * s
	# Más ángulo de visión con turbo / motivación: sensación de velocidad.
	fov = lerpf(fov, BOOST_FOV if boosting_now else BASE_FOV, 1.0 - exp(-4.0 * delta))


## Dónde va la cámara adentro del tubo: [posición, a dónde mira].
func _tube_view(tw: TubeWave, s_now: float) -> Array:
	if tw == null or not is_instance_valid(tw):
		return []
	var p := target.render_transform().origin
	# INF: está adentro (su lugar lo lleva el tubo). Si no, está llegando a la boca.
	var s := s_now
	if is_inf(s):
		if not tw.inside.has(target):
			return []
		s = float(tw.inside[target])
	var f := tw.frame_at(s)
	var o: Vector3 = f[0]
	var w: Vector3 = f[1]
	# El lugar del surfista de costado (u), para seguirlo a medias.
	var u := (p - o).dot(w)
	var cu := lerpf(TUBE_CAM_U, u, 0.35)
	var back := tw.frame_at(s - TUBE_CAM_BACK)
	var bo: Vector3 = back[0]
	var bw: Vector3 = back[1]
	var pos := bo + bw * cu
	pos.y = tw.base_height(bo) + TUBE_CAM_HEIGHT + TubeWave.face_y(cu) * 0.5
	var ahead := tw.frame_at(s + TUBE_LOOK_AHEAD)
	var ao: Vector3 = ahead[0]
	var aw: Vector3 = ahead[1]
	var look := ao + aw * TUBE_CAM_U
	look.y = tw.base_height(ao) + 1.5
	return [pos, look]


## Cámara que gira alrededor del surfista en la ola de borde: [posición,
## cuánto se usa (0..1)]. Da una vuelta entera mientras dura (así al final ya
## está detrás) y entra y sale suave.
const LIP_ORBIT_DISTANCE := 6.5
const LIP_ORBIT_HEIGHT := 2.0
const LIP_ORBIT_RISE := 2.5


func _lip_orbit() -> Array:
	var p := clampf(target.lip_progress, 0.0, 1.0)
	var angle := TAU * smoothstep(0.0, 1.0, p)
	var use := smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.85, 1.0, p))
	var xf := target.render_transform()
	var back_dir := Basis(Vector3.UP, angle) * xf.basis.z
	back_dir.y = 0.0
	var h := LIP_ORBIT_HEIGHT + LIP_ORBIT_RISE * sin(PI * p) + 0.8 * sin(2.0 * TAU * p)
	return [xf.origin + back_dir.normalized() * LIP_ORBIT_DISTANCE + Vector3.UP * h, use]


## true con turbo o motivación (y adentro del tubo: se siente la velocidad).
func boosting() -> bool:
	return target.turbo_active or target.motivation_timer > 0.0 or target.in_tube() or target.focus > 0.2


## Cuántos metros se aleja con turbo.
static func boost_pullback() -> float:
	return BOOST_PULLBACK


## Sacude la cámara (0..1).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _desired_position() -> Vector3:
	var fallen := target.is_fallen()
	# Con turbo se aleja hasta TURBO_BASE + el alejamiento elegido (8,3 m), sin
	# importar cuán cerca vaya normalmente.
	var turbo := maxf(TURBO_BASE + boost_pullback(), distance)
	var normal := lerpf(STOPPED_DISTANCE, distance, smoothstep(0.0, MOVING_SPEED, target.speed))
	var dist := fallen_distance if fallen else lerpf(normal, turbo, _boost * _boost * (3.0 - 2.0 * _boost))
	var h := fallen_height if fallen else height
	# Llegando a la boca de un tubo: más baja y más cerca (pasa abajo del labio).
	if _approach_smooth > 0.0 and not fallen:
		dist = lerpf(dist, TUBE_CAM_BACK, _approach_smooth)
		h = lerpf(h, TUBE_CAM_HEIGHT - 0.2, _approach_smooth)
	# Sigue al personaje como se dibuja (entre pasos de física): si siguiera la
	# posición de la física, con menos cuadros por segundo iría a saltos.
	var xf := target.render_transform()
	var base := xf.origin
	var fwd := -xf.basis.z
	base.y *= _follow_y
	if looking_back:
		# Adelante del Rider, mirando hacia atrás (un poco más alta para ver a los de atrás).
		return base + fwd * maxf(dist, LOOK_BACK_DISTANCE) + Vector3.UP * (h + 0.4)
	return base - fwd * dist + Vector3.UP * h


func _look_point() -> Vector3:
	var xf := target.render_transform()
	var p := xf.origin
	p.y = p.y * lerpf(0.5, 1.0, (_follow_y - 0.6) / 0.4) + look_height
	if looking_back:
		# Mirando hacia atrás: hacia el horizonte (lejos, detrás del personaje),
		# así se ve bien quiénes vienen; el personaje queda abajo en la imagen.
		return p + xf.basis.z * LOOK_BACK_FAR + Vector3.UP * 0.6
	return p
