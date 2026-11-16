class_name GeyserPiece
extends MapPiece
## Un géiser sobre el agua: burbujea, avisa y explota cada tanto. Si un
## surfista pasa por arriba justo cuando explota, sale volando.
## Se repite en el mapa una vez por géiser (cada uno con su lugar y su desfase).

const REQUIRED := ["x", "z"]

var x: float = 0.0
var z: float = 0.0
## Desfase del ciclo (s), para que no exploten todos juntos.
var phase: float = 0.0
## Cuánto está tranquilo, cuánto avisa y cuánto dura el chorro (s).
var calm: float = Geyser.CALM
var warn: float = Geyser.WARN
var erupt: float = Geyser.ERUPT
## Con qué velocidad tira para arriba (m/s).
var launch_speed: float = Geyser.LAUNCH_SPEED

var _geyser: Geyser


func build(course: Course) -> void:
	_geyser = Geyser.new()
	_geyser.name = "Geyser"
	_geyser.phase = phase
	_geyser.calm = calm
	_geyser.warn = warn
	_geyser.erupt = erupt
	_geyser.launch_speed = launch_speed
	_geyser.position = Vector3(x, 0.0, z)
	course.add_child(_geyser, true)


func affect_rider(course: Course, rider: Rider) -> bool:
	if not course.hazards_enabled or not rider.grounded or rider.is_fallen():
		return false
	if _geyser.erupting() and _geyser.covers(rider.position.x, rider.position.z):
		rider.geyser_launch(_geyser.launch_speed)
	return false
