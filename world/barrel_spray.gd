class_name BarrelSpray
extends Node3D
## Modo trucos: la espuma que salta de una ola que rompe en tubo (ver
## Swell.peel_w). Sigue al punto de rotura:
##   - detrás del tubo, donde el labio pega contra el agua y el tubo se cae:
##     la explosión de espuma hacia arriba y hacia adelante;
##   - en la garganta, la bruma que se desprende del labio recién tirado.
## Cuando la ola se va, deja de soltar y se borra.

## Gotas por metro y cuánto dura cada una (s).
const LAND_PER_METER := 6.0
const LIP_PER_METER := 2.0
const LIFETIME := 1.1
## Qué parte del tramo donde se cae el tubo (Swell.BARREL_COLLAPSE) explota.
const LAND_SPAN := 0.6

var wave: Swell
var water: Water
var _land: CPUParticles3D
var _lip: CPUParticles3D
var _ending: float = -1.0


func setup(p_wave: Swell, p_water: Water) -> void:
	wave = p_wave
	water = p_water
	var foam: Color = water.fx_colors().foam if water else Color.WHITE
	var span := Swell.BARREL_COLLAPSE * LAND_SPAN
	_land = WaterFx.soft_particles(int(span * LAND_PER_METER), LIFETIME, 4.0)
	_land.name = "Land"
	_land.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_land.emission_box_extents = Vector3(span * 0.5, 0.5, 1.5)
	_land.direction = Vector3(0.0, 1.0, -0.5)
	_land.spread = 30.0
	_land.initial_velocity_min = 7.0
	_land.initial_velocity_max = 14.0
	_land.gravity = Vector3(0.0, -9.0, 0.0)
	_land.damping_min = 1.0
	_land.damping_max = 2.5
	add_child(_land)
	_lip = WaterFx.soft_particles(int(Swell.BARREL_THROAT * LIP_PER_METER), LIFETIME * 1.4, 3.2)
	_lip.name = "Lip"
	_lip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_lip.emission_box_extents = Vector3(Swell.BARREL_THROAT * 0.5, 0.4, 0.6)
	_lip.direction = Vector3(0.0, 0.7, 1.0)
	_lip.spread = 20.0
	_lip.initial_velocity_min = 2.0
	_lip.initial_velocity_max = 4.5
	_lip.gravity = Vector3(0.0, -2.5, 0.0)
	add_child(_lip)
	for p in [_land, _lip]:
		WaterFx.tint(p, foam)
	_follow()


func _physics_process(delta: float) -> void:
	if wave == null:
		return
	if _ending >= 0.0:
		_ending -= delta
		if _ending <= 0.0:
			queue_free()
		return
	var gone := wave.is_dead() or (water != null and not water.swells.has(wave))
	if gone or wave.curl <= 0.0 or wave.lifetime - wave.age < wave.fade_time:
		_land.emitting = false
		_lip.emitting = false
		_ending = LIFETIME * 1.5
		return
	_follow()
	# Solo donde la ola existe (no más allá de las puntas).
	var crash := absf(_crash_w())
	WaterFx.emit(_land, crash < wave.half_length - wave.edge and wave.curl > 0.8)
	WaterFx.emit(_lip, absf(wave.peel_w) < wave.half_length - wave.edge and wave.curl > 0.5)


## Dónde explota (a lo ancho de la ola): al principio del tramo donde se cae.
func _crash_w() -> float:
	var back := wave.barrel_len + Swell.BARREL_COLLAPSE * LAND_SPAN * 0.5
	return wave.peel_w - wave.peel_dir * back


## Se pone en la ola: la explosión donde el tubo se cae (donde pegó el labio,
## al pie de la ola); la bruma en la garganta, arriba del labio.
func _follow() -> void:
	var a := wave.max_amplitude
	var perp := Vector2(-wave.direction.y, wave.direction.x)
	# Ejes de cada emisor: X a lo largo de la cresta, -Z hacia adelante de la ola.
	var x := Vector3(perp.x, 0.0, perp.y) * wave.peel_dir
	var fwd := Vector3(wave.direction.x, 0.0, wave.direction.y)
	var basis := Basis(x, Vector3.UP, -fwd)
	var land_p := wave.center + wave.direction * (1.6 * a) + perp * _crash_w()
	_land.global_transform = Transform3D(basis, Vector3(land_p.x, a * 0.2, land_p.y))
	var lip_w := wave.peel_w + wave.peel_dir * (Swell.BARREL_THROAT * 0.4)
	var lip_p := wave.center + wave.direction * (1.35 * a) + perp * lip_w
	_lip.global_transform = Transform3D(basis, Vector3(lip_p.x, a * 0.95, lip_p.y))
