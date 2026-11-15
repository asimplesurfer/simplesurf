class_name Island
extends Node3D
## Isla: playa, una loma verde, palmeras y (si es grande) un faro.
## Solo es visual; el choque con la orilla lo maneja Course.

@export var radius: float = 45.0
## Semilla para que cada isla tenga sus palmeras en otro lugar.
@export var island_seed: int = 11
@export var lighthouse: bool = true
## Volcán: un cono de roca con lava en el cráter y humo (en vez de la loma).
@export var volcano: bool = false

const SAND := Color(0.98, 0.86, 0.6)
const GRASS := Color(0.45, 0.78, 0.35)
const TRUNK := Color(0.6, 0.42, 0.25)
const LEAVES := Color(0.25, 0.65, 0.3)


func _ready() -> void:
	add_to_group("island")

	# Playa: un cono truncado que entra en el agua.
	var beach_mesh := CylinderMesh.new()
	beach_mesh.top_radius = radius
	beach_mesh.bottom_radius = radius + 12.0
	beach_mesh.height = 4.0
	beach_mesh.radial_segments = 48
	beach_mesh.material = ToonMaterial.make(SAND, 0.0)
	_add_mesh(beach_mesh, Vector3(0.0, -1.4, 0.0))

	if volcano:
		_build_volcano()
		return

	# Loma verde.
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = radius * 0.82
	hill_mesh.height = radius * 0.82 * 0.7
	hill_mesh.radial_segments = 40
	hill_mesh.rings = 12
	hill_mesh.material = ToonMaterial.make(GRASS, 0.0)
	_add_mesh(hill_mesh, Vector3(0.0, 0.5, 0.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed
	# Más palmeras en las islas más grandes.
	var palms := clampi(int(radius / 5.0), 3, 9)
	var offset := rng.randf_range(0.0, TAU)
	for i in palms:
		var angle := offset + TAU * i / float(palms) + rng.randf_range(-0.2, 0.2)
		var r := radius * rng.randf_range(0.3 if lighthouse else 0.0, 0.72)
		var pos := Vector3(cos(angle) * r, _ground_height(r), sin(angle) * r)
		_add_palm(pos, rng)
	_build_palms()
	if lighthouse:
		_add_lighthouse(Vector3(0.0, _ground_height(0.0) - 0.5, 0.0))


## Volcán: falda verde con palmeras, cono de roca, lava en el cráter y una
## columna de humo que sube despacio.
func _build_volcano() -> void:
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


## Altura del suelo de la loma a una distancia del centro.
func _ground_height(r: float) -> float:
	var hr := radius * 0.82
	var hh := hr * 0.35
	if r >= hr:
		return 0.6
	return 0.5 + hh * sqrt(1.0 - (r * r) / (hr * hr))


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	return mi


## Palmeras: se juntan todos los troncos y todas las hojas de la isla en dos
## MultiMesh (muchas menos llamadas de dibujo que una malla por pieza).
var _trunks: Array[Transform3D] = []
var _leaves: Array[Transform3D] = []


func _add_palm(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(6.0, 9.0)
	var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)))
	# La malla del tronco mide 7.5 m: se escala poco (escalar mucho arruina la luz).
	var stretch := height / 7.5
	_trunks.append(Transform3D(tilt * Basis.from_scale(Vector3(1.0, stretch, 1.0)), pos + Vector3(0.0, height * 0.5, 0.0)))
	var top := pos + Vector3(0.0, height, 0.0)
	for k in 6:
		var a := TAU * k / 6.0
		var basis := Basis.from_euler(Vector3(0.0, -a, -0.35)).scaled(Vector3(2.0, 0.25, 0.7))
		_leaves.append(Transform3D(basis, top + Vector3(cos(a), -0.3, sin(a)) * 1.6))


func _build_palms() -> void:
	if _trunks.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.45
	trunk.height = 7.5
	trunk.radial_segments = 8
	trunk.material = ToonMaterial.make(TRUNK, 0.05)
	_add_multimesh(trunk, _trunks, "Trunks")
	var leaf := SphereMesh.new()
	leaf.radius = 1.0
	leaf.height = 2.0
	leaf.radial_segments = 10
	leaf.rings = 5
	leaf.material = ToonMaterial.make(LEAVES, 0.05)
	_add_multimesh(leaf, _leaves, "Leaves")


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)


func _add_lighthouse(base: Vector3) -> void:
	var colors := [Color(0.97, 0.97, 0.97), Color(0.9, 0.25, 0.25)]
	var y := 0.0
	for i in 5:
		var seg := CylinderMesh.new()
		seg.top_radius = 2.0 - i * 0.18
		seg.bottom_radius = 2.2 - i * 0.18
		seg.height = 3.0
		seg.material = ToonMaterial.make(colors[i % 2], 0.06)
		_add_mesh(seg, base + Vector3(0.0, y + 1.5, 0.0))
		y += 3.0
	var lamp := SphereMesh.new()
	lamp.radius = 1.4
	lamp.height = 2.8
	lamp.material = ToonMaterial.make(Color(1.0, 0.9, 0.4), 0.06)
	_add_mesh(lamp, base + Vector3(0.0, y + 0.8, 0.0))
