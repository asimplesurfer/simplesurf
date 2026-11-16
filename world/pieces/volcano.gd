class_name VolcanoPiece
extends MapPiece
## Una isla volcán: playa, falda verde con palmeras, cono de roca, lava en el
## cráter y una columna de humo. Se choca igual que cualquier isla.

const REQUIRED := ["x", "z", "radius"]

var x: float = 0.0
var z: float = 0.0
var radius: float = 40.0
## Semilla de las palmeras (-1: sale del lugar de la isla).
var island_seed: int = -1


func build(course: Course) -> void:
	var isl := VolcanoIsland.new()
	isl.name = "Volcano"
	isl.radius = radius
	isl.island_seed = island_seed if island_seed >= 0 else Course.seed_for(Vector2(x, z))
	isl.lighthouse = false
	isl.position = Vector3(x, 0.0, z)
	course.add_island(isl)


class VolcanoIsland extends Island:
	## Volcán: falda verde con palmeras, cono de roca, lava en el cráter y una
	## columna de humo que sube despacio.
	func _build_top() -> void:
		var skirt := SphereMesh.new()
		skirt.radius = radius * 0.95
		skirt.height = radius * 0.95 * 0.32
		skirt.radial_segments = 40
		skirt.rings = 10
		skirt.material = ToonMaterial.make(GRASS, 0.0)
		_add_mesh(skirt, Vector3(0.0, 0.4, 0.0))
		var cone := CylinderMesh.new()
		cone.top_radius = radius * 0.2
		cone.bottom_radius = radius * 0.78
		cone.height = radius * 0.95
		cone.radial_segments = 32
		cone.material = ToonMaterial.make(Color(0.42, 0.34, 0.3), 0.0)
		var top_y := 0.6 + cone.height
		_add_mesh(cone, Vector3(0.0, 0.6 + cone.height * 0.5, 0.0))
		# Lava en el cráter (brilla aunque sea de noche).
		var lava := CylinderMesh.new()
		lava.top_radius = radius * 0.16
		lava.bottom_radius = radius * 0.16
		lava.height = 0.6
		var lava_mat := StandardMaterial3D.new()
		lava_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lava_mat.albedo_color = Color(1.0, 0.45, 0.1)
		lava.material = lava_mat
		_add_mesh(lava, Vector3(0.0, top_y - 0.1, 0.0))
		# Chorros de lava bajando por la ladera.
		for i in 3:
			var a := TAU * i / 3.0 + 0.4
			var flow := BoxMesh.new()
			flow.size = Vector3(radius * 0.05, radius * 0.6, 0.4)
			flow.material = lava_mat
			var mi := _add_mesh(flow, Vector3.ZERO)
			var out := Vector3(cos(a), 0.0, sin(a))
			var slope := atan2(radius * 0.58, cone.height)
			mi.basis = Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -slope)
			mi.position = out * radius * 0.42 + Vector3(0.0, 0.6 + cone.height * 0.55, 0.0)
		_add_smoke(Vector3(0.0, top_y + 1.0, 0.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = island_seed
		for i in 9:
			var ang := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
			var r := radius * rng.randf_range(0.82, 0.95)
			_add_palm(Vector3(cos(ang) * r, 0.6, sin(ang) * r), rng)
		_build_palms()


	func _add_smoke(at: Vector3) -> void:
		var smoke := CPUParticles3D.new()
		smoke.name = "Smoke"
		var puff := SphereMesh.new()
		puff.radius = 2.5
		puff.height = 5.0
		puff.radial_segments = 10
		puff.rings = 5
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		puff.material = mat
		smoke.mesh = puff
		smoke.amount = 26
		smoke.lifetime = 9.0
		smoke.preprocess = 9.0
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = radius * 0.12
		smoke.direction = Vector3(0.15, 1.0, 0.0)
		smoke.spread = 12.0
		smoke.gravity = Vector3(0.6, 0.4, 0.0)
		smoke.initial_velocity_min = 2.5
		smoke.initial_velocity_max = 4.0
		smoke.scale_amount_min = 1.0
		smoke.scale_amount_max = 1.6
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.6))
		grow.add_point(Vector2(1.0, 3.2))
		smoke.scale_amount_curve = grow
		var fade := Gradient.new()
		fade.set_color(0, Color(0.55, 0.52, 0.5, 0.85))
		fade.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
		smoke.color_ramp = fade
		smoke.position = at
		add_child(smoke)
