class_name LipWaveSpray
extends Node3D
## Modo trucos: el rocío que vuela de la cresta de la ola de borde (como cuando
## el viento le pega a la ola de frente), de punta a punta. Así se reconoce
## cuál es la ola de borde sin cambiar los colores del agua: ninguna otra lo
## tiene. Sigue a su ola; cuando la ola se va, deja de soltar rocío y se borra.

## Rocío por metro de cresta (gotas vivas) y cuánto dura cada gota (s).
const PER_METER := 2.4
const LIFETIME := 1.8
## Tamaño de cada gota de bruma (m).
const SIZE := 3.0
## Velocidad con que sale volando hacia atrás de la ola y hacia arriba (m/s).
const BACK_SPEED := 5.0
const UP_SPEED := 5.5

var wave: Swell
var water: Water
var _particles: CPUParticles3D
var _ending: float = -1.0


func setup(p_wave: Swell, p_water: Water) -> void:
	wave = p_wave
	water = p_water
	var length := maxf(wave.half_length - wave.edge, 4.0)
	_particles = WaterFx.soft_particles(int(length * 2.0 * PER_METER), LIFETIME, SIZE)
	_particles.name = "Spray"
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.emission_box_extents = Vector3(length, 0.3, 0.6)
	_particles.gravity = Vector3(0.0, -3.0, 0.0)
	_particles.spread = 18.0
	_particles.initial_velocity_min = Vector3(BACK_SPEED, UP_SPEED, 0.0).length() * 0.7
	_particles.initial_velocity_max = Vector3(BACK_SPEED, UP_SPEED, 0.0).length() * 1.2
	_particles.damping_min = 1.0
	_particles.damping_max = 2.0
	add_child(_particles)
	if water:
		WaterFx.tint(_particles, water.fx_colors().foam)
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
	var leaving := wave.lifetime - wave.age < wave.fade_time
	if gone or leaving:
		# La ola se va: deja de soltar rocío y se borra cuando cae la última gota.
		_particles.emitting = false
		_ending = LIFETIME + 0.2
		return
	_follow()
	WaterFx.emit(_particles, wave.amplitude > wave.max_amplitude * 0.6)


## Se pone sobre la cresta (tal como se dibuja), con X a lo largo de la cresta;
## el rocío sale hacia atrás de la ola y hacia arriba.
func _follow() -> void:
	var perp := Vector2(-wave.direction.y, wave.direction.x)
	var top := wave.center + wave.direction * wave.crest_u()
	var h := water.height_at(top.x, top.y) if water else wave.amplitude
	var x := Vector3(perp.x, 0.0, perp.y)
	var y := Vector3.UP
	global_transform = Transform3D(Basis(x, y, x.cross(y)), Vector3(top.x, h + 0.3, top.y))
	var back := Vector3(-wave.direction.x, 0.0, -wave.direction.y) * BACK_SPEED + Vector3.UP * UP_SPEED
	_particles.direction = (global_transform.basis.inverse() * back).normalized()
