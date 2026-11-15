class_name NitroRing
extends Node3D
## Círculo de velocidad: pasar por adentro carga nitro y da motivación
## (un mini sprint automático). Flota sobre el agua de frente a la carrera.

@export var radius: float = 1.9
## Segundos antes de que el mismo Rider pueda volver a agarrarlo.
@export var cooldown: float = 2.0

const COLOR := Color(0.25, 0.9, 1.0)

var _ring: MeshInstance3D
var _cooldowns: Dictionary = {}
var _pulse: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.22
	torus.outer_radius = radius + 0.22
	torus.rings = 32
	torus.ring_segments = 10
	var mat := ToonMaterial.make(COLOR, 0.05)
	mat.emission_enabled = true
	mat.emission = COLOR * 0.6
	torus.material = mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	# El toro viene acostado; se para de frente al sentido de la carrera.
	_ring.rotation.x = PI / 2.0
	add_child(_ring)


## Llamado por Course cada frame. Devuelve true si el Rider lo agarró.
func try_collect(rider: Rider, now: float) -> bool:
	var id := rider.get_instance_id()
	if _cooldowns.get(id, -100.0) > now:
		return false
	var d := Vector2(rider.position.x - position.x, rider.position.z - position.z).length()
	var body_y := rider.position.y + 0.9
	if d > radius * 0.95 or absf(body_y - position.y) > radius + 0.6:
		return false
	_cooldowns[id] = now + cooldown
	_pulse = 1.0
	rider.add_nitro(rider.stats.ring_nitro)
	rider.trigger_motivation()
	rider.ring_collected.emit()
	return true


func _process(delta: float) -> void:
	_time += delta
	_pulse = move_toward(_pulse, 0.0, delta * 2.5)
	_ring.scale = Vector3.ONE * (1.0 + 0.25 * _pulse + 0.03 * sin(_time * 3.0))
