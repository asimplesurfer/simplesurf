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
## La altura del personaje que sigue la cámara: la suya, sin retraso (así
## va siempre igual respecto de él, con el mismo ángulo, abajo o arriba de
## una ola gigante, subiendo o bajando), salvo las olitas del mar de fondo,
## que se siguen suavizadas (si no, la cámara se mece y marea).
var _ride_y: float = 0.0
var _chop: float = 0.0
## 0 en el agua, 1 en el aire o en el borde de una ola: ahí sigue su altura
## exacta (sin descontar las olitas).
var _air_k: float = 0.0
## Qué tan rápido sigue las olitas del mar de fondo (1/s).
const CHOP_RATE := 1.5

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
		_ride_y = target.global_position.y
		if _water and _water.waves:
			_chop = _water.waves.height_at(target.global_position.x, target.global_position.z, _water.time)
		global_position = _desired_position()
		look_at(_look_point(), Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	# Se sigue desde donde iría sin agua en el medio (ver _occlude).
	if _has_free:
		global_position = _free_pos
	# La altura que sigue: la del personaje, con las olitas del mar de fondo
	# suavizadas en el agua; en el aire y en el borde de una ola (modo trucos),
	# la exacta.
	var on_water := target.grounded and not target.on_lip()
	var at := target.render_transform().origin
	var chop := _water.waves.height_at(at.x, at.z, _water.time) if _water and _water.waves else 0.0
	_chop = lerpf(_chop, chop, 1.0 - exp(-CHOP_RATE * minf(delta, 0.1)))
	_ride_y = at.y - chop + _chop
	_air_k = lerpf(_air_k, 0.0 if on_water else 1.0, 1.0 - exp(-3.0 * delta))
	var w := 1.0 - exp(-follow_sharpness * minf(delta, 0.1))
	var boosting_now := boosting()
	# Concentración (modo trucos): se aleja de a poco, según cuánto subió la
	# velocidad (al doble, todo).
	var boost_target := 1.0 if boosting_now else target.focus
	_boost = move_toward(_boost, boost_target, delta * (2.5 if boost_target > _boost else 1.5))
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
	# La altura, sin retraso (el mismo ángulo siempre; las olitas ya vienen
	# suavizadas en _ride_y).
	global_position.y = desired.y
	if _tube_blend > 0.0 and not _tube_frame.is_empty():
		# Adentro del tubo va pegada (sin el retraso de siempre: a esta velocidad
		# quedaría afuera del tubo).
		var k := smoothstep(0.0, 1.0, _tube_blend)
		global_position = global_position.lerp(_tube_frame[0], k)
	var look := _look_point()
	# Nunca debajo del agua ni con agua entre la cámara y el personaje (con
	# olas grandes y tubos): se acerca por la misma línea (mismo ángulo), suave.
	_has_free = false
	if _water and _tube_blend <= 0.0:
		_occlude(look, delta)
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
	fov = lerpf(fov, lerpf(BASE_FOV, BOOST_FOV, maxf(1.0 if boosting_now else 0.0, target.focus)), 1.0 - exp(-4.0 * delta))


## Agua entre la cámara y el personaje: la cámara va sobre la misma línea
## (mismo ángulo) hasta donde no hay agua en el medio. Se acerca rápido
## (BOOM_IN 1/s) pero no de golpe, y se vuelve a alejar despacio (BOOM_OUT).
## Si ni pegada al personaje alcanza, sube (como antes).
const SIGHT_STEPS := 8
const SIGHT_REFINE := 5
const BOOM_MIN := 0.15
const BOOM_IN := 7.0
const BOOM_OUT := 1.5
## Lo mínimo entre la cámara y el labio de un tubo, por encima (m).
const ROOF_MARGIN := 0.6
## Cuánto de la línea usa (1: toda) y dónde iría sin agua en el medio.
var _boom: float = 1.0
var _free_pos := Vector3.ZERO
var _has_free: bool = false


func _occlude(look: Vector3, delta: float) -> void:
	var free := global_position
	var k := _sight_fraction(free, look)
	if k < 0.0:
		var h := _water.height_below(free.x, free.z, free.y) + MIN_ABOVE_WATER
		global_position = Vector3(free.x, maxf(free.y, h), free.z)
		_boom = 1.0
		return
	_boom = move_toward(_boom, k, (BOOM_IN if k < _boom else BOOM_OUT) * delta)
	_free_pos = free
	_has_free = true
	global_position = look.lerp(free, _boom)


## Hasta qué parte de la línea (de `look` a `cam`, 0..1) no hay agua en el
## medio; -1 si ya hay agua pegada al personaje.
func _sight_fraction(cam: Vector3, look: Vector3) -> float:
	var prev := 0.0
	for i in range(1, SIGHT_STEPS + 1):
		var f := float(i) / SIGHT_STEPS
		if _clear_of_water(look.lerp(cam, f)):
			prev = f
			continue
		if prev <= 0.0:
			return -1.0
		var lo := prev
		var hi := f
		for j in SIGHT_REFINE:
			var mid := (lo + hi) * 0.5
			if _clear_of_water(look.lerp(cam, mid)):
				lo = mid
			else:
				hi = mid
		return maxf(lo, BOOM_MIN)
	return 1.0


func _clear_of_water(q: Vector3) -> bool:
	if q.y < _water.height_below(q.x, q.z, q.y) + MIN_ABOVE_WATER:
		return false
	# Adentro de un tubo: tampoco metida en el labio (ni pegada a él).
	return not _water.in_water(q.x, q.z, q.y + ROOF_MARGIN)


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
	return target.turbo_active or target.motivation_timer > 0.0 or target.in_tube()


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
	base.y = lerpf(_ride_y, base.y, _air_k)
	if looking_back:
		# Adelante del Rider, mirando hacia atrás (un poco más alta para ver a los de atrás).
		return base + fwd * maxf(dist, LOOK_BACK_DISTANCE) + Vector3.UP * (h + 0.4)
	return base - fwd * dist + Vector3.UP * h


func _look_point() -> Vector3:
	var xf := target.render_transform()
	var p := xf.origin
	p.y = lerpf(_ride_y, p.y, _air_k) + look_height
	if looking_back:
		# Mirando hacia atrás: hacia el horizonte (lejos, detrás del personaje),
		# así se ve bien quiénes vienen; el personaje queda abajo en la imagen.
		return p + xf.basis.z * LOOK_BACK_FAR + Vector3.UP * 0.6
	return p
