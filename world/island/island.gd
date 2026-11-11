class_name Island
extends Node3D
## Isla: playa, una loma verde, palmeras y (si es grande) un faro.
## Solo es visual; el choque con la orilla lo maneja Course.

@export var radius: float = 45.0
## Semilla para que cada isla tenga sus palmeras en otro lugar.
@export var island_seed: int = 11
@export var lighthouse: bool = true

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
