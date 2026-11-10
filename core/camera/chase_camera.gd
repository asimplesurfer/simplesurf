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

var target: Rider


func _ready() -> void:
	# Después del Rider, para seguir su posición de este frame.
	process_priority = 10
	target = get_node_or_null(target_path) as Rider
	if target:
		global_position = _desired_position()
		look_at(_look_point(), Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	var w := 1.0 - exp(-follow_sharpness * minf(delta, 0.1))
	global_position = global_position.lerp(_desired_position(), w)
	look_at(_look_point(), Vector3.UP)


func _desired_position() -> Vector3:
	var fallen := target.is_fallen()
	var dist := fallen_distance if fallen else distance
	var h := fallen_height if fallen else height
	var base := target.global_position
	base.y = 0.0  # no seguir el sube y baja de las olas (marea)
	return base - target.forward() * dist + Vector3.UP * h


func _look_point() -> Vector3:
	var p := target.global_position
	p.y = p.y * 0.5 + look_height
	return p
