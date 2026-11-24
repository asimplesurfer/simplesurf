class_name LineTrack
extends TrackSpace
## Una "pista" recta: para usar la ola tubo (TubeWave) fuera de una carrera
## (modo trucos: a lo largo de la cresta de una ola gigante).
## - ángulo: cuánto avanzó por la recta (LENGTH metros = una vuelta, TAU).
## - lateral: cuánto se corrió de la recta hacia `side_dir`.

## Largo de la "vuelta" (m): mucho más que cualquier tubo, para que nunca dé
## la vuelta.
const LENGTH := 4000.0

var origin := Vector2.ZERO
var dir := Vector2.RIGHT
var side_dir := Vector2.DOWN


func _init(p_origin: Vector2 = Vector2.ZERO, p_dir: Vector2 = Vector2.RIGHT, p_side: Vector2 = Vector2.DOWN, p_half_width: float = 12.0) -> void:
	super(LENGTH / TAU, p_half_width)
	origin = p_origin
	dir = p_dir.normalized()
	side_dir = p_side.normalized()


func angle_of(p: Vector3) -> float:
	return (Vector2(p.x, p.z) - origin).dot(dir) / LENGTH * TAU


func lateral_of(p: Vector3) -> float:
	return (Vector2(p.x, p.z) - origin).dot(side_dir)


func position_at(angle: float, lateral: float = 0.0) -> Vector3:
	var q := origin + dir * (angle / TAU * LENGTH) + side_dir * lateral
	return Vector3(q.x, 0.0, q.y)


func tangent_at(_angle: float) -> Vector3:
	return Vector3(dir.x, 0.0, dir.y)


func length() -> float:
	return LENGTH
