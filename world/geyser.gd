class_name Geyser
extends Node3D
## Géiser volcánico (laguna del Atolón): burbujea, avisa con espuma y explota en
## un chorro de agua. Si alguien pasa por encima justo cuando explota, sale
## volando (Course lo lanza con Rider.geyser_launch).
##
## Ciclo: tranquilo -> aviso (burbujea fuerte, la espuma crece) -> explota.

const RADIUS := 4.0
## Duraciones (s).
const CALM := 3.6
const WARN := 1.4
const ERUPT := 1.3
const CYCLE := CALM + WARN + ERUPT
## Velocidad hacia arriba con la que lanza (m/s).
const LAUNCH_SPEED := 17.0

## Desfase del ciclo (para que no exploten todos juntos).
@export var phase: float = 0.0

var _t: float = 0.0
var _foam: MeshInstance3D
var _foam_mat: StandardMaterial3D
var _column: MeshInstance3D
var _bubbles: CPUParticles3D
var _spray: CPUParticles3D


func _ready() -> void:
	add_to_group("geyser")
	_t = fmod(phase, CYCLE)
	var water_mat := StandardMaterial3D.new()
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color = Color(0.85, 0.97, 1.0, 0.75)
	# Espuma: un disco blanco en la superficie que crece con el aviso.
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.08
	disc.radial_segments = 28
	_foam_mat = StandardMaterial3D.new()
	_foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foam_mat.albedo_color = Color(1, 1, 1, 0.5)
	disc.material = _foam_mat
	_foam = MeshInstance3D.new()
	_foam.mesh = disc
	_foam.position.y = 0.15
	add_child(_foam)
	# Columna de agua (se estira al explotar).
	var col := CylinderMesh.new()
	col.top_radius = 1.2
	col.bottom_radius = 2.2
	col.height = 1.0
	col.radial_segments = 16
	col.material = water_mat
	_column = MeshInstance3D.new()
	_column.mesh = col
	_column.visible = false
	add_child(_column)
	_bubbles = _particles(18, 0.9, 1.2, Vector3(0, 2.0, 0), 0.35, Color(1, 1, 1, 0.9))
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = RADIUS * 0.7
	_spray = _particles(60, 1.6, 2.2, Vector3(0, -18.0, 0), 0.6, Color(0.9, 0.98, 1.0, 0.95))
	_spray.direction = Vector3.UP
	_spray.spread = 14.0
	_spray.initial_velocity_min = 14.0
	_spray.initial_velocity_max = 21.0
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spray.emission_sphere_radius = 1.2


func _particles(amount: int, lifetime: float, size: float, gravity: Vector3, sz: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = sz
	m.height = sz * 2.0
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material = mat
	p.mesh = m
	p.amount = amount
	p.lifetime = lifetime
	p.gravity = gravity
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.emitting = false
	add_child(p)
	return p


## 0 tranquilo, 1 avisando, 2 explotando.
func stage() -> int:
	if _t < CALM:
		return 0
	if _t < CALM + WARN:
		return 1
	return 2


func erupting() -> bool:
	return stage() == 2


## true si (x, z) está sobre el géiser.
func covers(x: float, z: float) -> bool:
	return Vector2(x - global_position.x, z - global_position.z).length() < RADIUS


## En pasos fijos: el momento en que explota no depende de los FPS.
func _physics_process(delta: float) -> void:
	_t = fmod(_t + delta, CYCLE)
	var st := stage()
	var warn := clampf((_t - CALM) / WARN, 0.0, 1.0) if st >= 1 else 0.0
	_bubbles.emitting = st >= 1
	_spray.emitting = st == 2
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.02) * 0.06 * warn
	_foam.scale = Vector3.ONE * (0.45 + 0.55 * warn) * pulse
	_foam_mat.albedo_color.a = 0.25 + 0.6 * warn if st < 2 else 0.9
	_column.visible = st == 2
	if st == 2:
		# Sube rápido y baja al final.
		var k := (_t - CALM - WARN) / ERUPT
		var h := 18.0 * sin(clampf(k, 0.0, 1.0) * PI) + 1.0
		_column.scale = Vector3(1.0, h, 1.0)
		_column.position.y = h * 0.5
