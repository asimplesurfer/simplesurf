class_name BuoyField
extends Node3D
## Boyas de referencia repartidas al azar, para que se note el movimiento.
## Se "teletransportan" alrededor del jugador, así nunca se acaban.

@export var follow_path: NodePath
@export var count: int = 45
## Lado del cuadrado (m) en el que se reparten alrededor del jugador.
@export var area: float = 220.0
@export var random_seed: int = 7

var _buoys: Array[Node3D] = []
var _offsets: Array[Vector2] = []
var _follow: Node3D
var _water: Water


func _ready() -> void:
	_follow = get_node_or_null(follow_path) as Node3D
	_water = get_tree().get_first_node_in_group("water") as Water

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var colors := [Color(0.95, 0.25, 0.25), Color(1.0, 0.6, 0.15), Color(0.6, 0.35, 0.95)]

	for i in count:
		var buoy := _make_buoy(colors[i % colors.size()])
		add_child(buoy)
		_buoys.append(buoy)
		_offsets.append(Vector2(rng.randf_range(0.0, area), rng.randf_range(0.0, area)))


func _process(_delta: float) -> void:
	var center := Vector2.ZERO
	if _follow:
		center = Vector2(_follow.global_position.x, _follow.global_position.z)
	for i in _buoys.size():
		var o := _offsets[i]
		var p := Vector2(_wrap(o.x - center.x), _wrap(o.y - center.y)) + center
		var y := 0.0
		if _water:
			y = _water.height_at(p.x, p.y)
		_buoys[i].global_position = Vector3(p.x, y, p.y)


func _wrap(v: float) -> float:
	return fposmod(v + area * 0.5, area) - area * 0.5


func _make_buoy(color: Color) -> Node3D:
	var root := Node3D.new()

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.25
	base_mesh.bottom_radius = 0.45
	base_mesh.height = 0.9
	base_mesh.material = ToonMaterial.make(color, 0.04)
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.position.y = 0.2
	root.add_child(base)

	var top_mesh := SphereMesh.new()
	top_mesh.radius = 0.22
	top_mesh.height = 0.44
	top_mesh.material = ToonMaterial.make(Color(0.97, 0.97, 0.97), 0.03)
	var top := MeshInstance3D.new()
	top.mesh = top_mesh
	top.position.y = 0.75
	root.add_child(top)
	return root
