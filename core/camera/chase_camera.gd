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
	_water = GameSession.find_in_scene(self, "water") as Water
	if target:
		global_position = _desired_position()
		look_at(_look_point(), Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	var follow_target := 0.6 if target.grounded else 1.0
	_follow_y = lerpf(_follow_y, follow_target, 1.0 - exp(-3.0 * delta))
	var w := 1.0 - exp(-follow_sharpness * minf(delta, 0.1))
	var boosting_now := boosting()
	_boost = move_toward(_boost, 1.0 if boosting_now else 0.0, delta * (2.5 if boosting_now else 1.5))
	var back := target.input != null and target.input.look_back and not target.is_fallen()
	var desired := _desired_position()
	if back != looking_back:
		# Corte directo (si no, la cámara atravesaría al personaje).
		looking_back = back
		desired = _desired_position()
		global_position = desired
	global_position = global_position.lerp(desired, w)
	# En el aire, la altura se sigue más rápido para que no se escape de cuadro.
	if not target.grounded:
		var wy := 1.0 - exp(-follow_sharpness * 2.0 * minf(delta, 0.1))
		global_position.y = lerpf(global_position.y, desired.y, wy)
	# Nunca debajo del agua (con olas grandes, la cámara podía quedar adentro).
	if _water:
		var h := _water.height_at(global_position.x, global_position.z) + MIN_ABOVE_WATER
		if global_position.y < h:
			global_position.y = h
	look_at(_look_point(), Vector3.UP)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		var s := _shake * _shake
		rotate_object_local(Vector3.RIGHT, randf_range(-1.0, 1.0) * 0.05 * s)
		rotate_object_local(Vector3.UP, randf_range(-1.0, 1.0) * 0.05 * s)
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.25 * s
	# Más ángulo de visión con turbo / motivación: sensación de velocidad.
	fov = lerpf(fov, BOOST_FOV if boosting_now else BASE_FOV, 1.0 - exp(-4.0 * delta))


## true con turbo o motivación.
func boosting() -> bool:
	return target.turbo_active or target.motivation_timer > 0.0


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
