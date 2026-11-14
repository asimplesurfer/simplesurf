class_name ChaseCamera
extends Camera3D
## Cámara que sigue al Rider desde atrás. Una por jugador (player_index).

@export var target_path: NodePath
@export var distance: float = 6.0
@export var height: float = 2.7
@export var look_height: float = 1.0
## Cámara más cerca cuando está caído, para ver bien la animación.
@export var fallen_distance: float = 4.5
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

## Con turbo o motivación la cámara se aleja un poco hacia atrás (sensación de
## velocidad). Tres distancias para probar: la tecla B pasa a la siguiente y
## hace un alejamiento de muestra.
const BOOST_PULLBACKS: Array[float] = [0.7, 1.4, 2.3]
static var boost_option: int = 1
## Muestra del alejamiento (s que quedan), al apretar B.
const PREVIEW_TIME := 1.6
var _preview: float = 0.0
## 0..1: cuánto se alejó (se acerca y aleja suave).
var _boost: float = 0.0
## Cuadro en que se cambió la opción (con pantalla dividida hay varias cámaras
## y todas reciben la tecla: cambia una sola vez).
static var _cycled_frame: int = -1


func _ready() -> void:
	# Después del Rider, para seguir su posición de este frame.
	process_priority = 10
	if target == null:
		target = get_node_or_null(target_path) as Rider
	if target:
		target.wave_punched.connect(func() -> void: shake(0.6))
	_water = get_tree().get_first_node_in_group("water") as Water
	if target:
		global_position = _desired_position()
		look_at(_look_point(), Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	var follow_target := 0.6 if target.grounded else 1.0
	_follow_y = lerpf(_follow_y, follow_target, 1.0 - exp(-3.0 * delta))
	var w := 1.0 - exp(-follow_sharpness * minf(delta, 0.1))
	_preview = maxf(_preview - delta, 0.0)
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


## true con turbo o motivación (o la muestra de la tecla B).
func boosting() -> bool:
	return target.turbo_active or target.motivation_timer > 0.0 or _preview > 0.0


## Cuántos metros se aleja con turbo, según la opción elegida.
static func boost_pullback() -> float:
	return BOOST_PULLBACKS[boost_option]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_B:
		var frame := Engine.get_process_frames()
		if _cycled_frame != frame:
			_cycled_frame = frame
			boost_option = (boost_option + 1) % BOOST_PULLBACKS.size()
		_preview = PREVIEW_TIME


## Sacude la cámara (0..1).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _desired_position() -> Vector3:
	var fallen := target.is_fallen()
	var dist := fallen_distance if fallen else distance + boost_pullback() * _boost * _boost * (3.0 - 2.0 * _boost)
	var h := fallen_height if fallen else height
	var base := target.global_position
	base.y *= _follow_y
	if looking_back:
		# Adelante del Rider, mirando hacia atrás (un poco más alta para ver a los de atrás).
		return base + target.forward() * dist + Vector3.UP * (h + 0.4)
	return base - target.forward() * dist + Vector3.UP * h


func _look_point() -> Vector3:
	var p := target.global_position
	p.y = p.y * lerpf(0.5, 1.0, (_follow_y - 0.6) / 0.4) + look_height
	return p
