class_name WaterFx
extends RefCounted
## Ayudas para los efectos de agua (partículas de bruma suaves).


## Prende o apaga un sistema de gotas. Hasta que suelta la primera gota queda
## invisible: las gotas que todavía nunca se usaron se dibujarían como un punto
## negro donde nace el efecto (en el renderer de compatibilidad).
static func emit(p: CPUParticles3D, on: bool) -> void:
	p.emitting = on
	if on:
		p.visible = true


## Partículas de bruma/gotas: cuadrados siempre de frente a la cámara con un
## círculo difuminado, que crecen y se desvanecen.
static func soft_particles(amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Las partículas que no están volando tienen escala 0: así no se dibujan
	# (si no, quedan como un punto negro donde nacen).
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = tex
	material.albedo_color = Color(0.92, 0.97, 1.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material

	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.85))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))

	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.visible = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.gravity = Vector3(0.0, -12.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = grow
	p.color_ramp = fade
	# Sin sombra: el agua que vuela no deja manchas negras en el mar.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.angle_min = 0.0
	p.angle_max = 360.0
	return p
