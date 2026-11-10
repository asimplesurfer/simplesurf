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

const BASE_FOV := 70.0
const BOOST_FOV := 82.0


func _ready() -> void:
	# Después del Rider, para seguir su posición de este frame.
	process_priority = 10
	if target == null:
		target = get_node_or_null(target_path) as Rider
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
	var desired := _desired_position()
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
	# Más ángulo de visión con turbo / motivación: sensación de velocidad.
	var boosting := target.turbo_active or target.motivation_timer > 0.0
	fov = lerpf(fov, BOOST_FOV if boosting else BASE_FOV, 1.0 - exp(-4.0 * delta))


func _desired_position() -> Vector3:
	var fallen := target.is_fallen()
	var dist := fallen_distance if fallen else distance
	var h := fallen_height if fallen else height
	var base := target.global_position
	base.y *= _follow_y
	return base - target.forward() * dist + Vector3.UP * h


func _look_point() -> Vector3:
	var p := target.global_position
	p.y = p.y * lerpf(0.5, 1.0, (_follow_y - 0.6) / 0.4) + look_height
	return p
