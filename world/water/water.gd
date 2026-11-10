class_name Water
extends Node3D
## Plano de agua que sigue al jugador (parece infinito) y se ondula con WaveDefinition.
## Ofrece height_at() / normal_at() para que las cosas floten justo sobre lo que se ve.

const SHADER := preload("res://world/water/water.gdshader")

@export var waves: WaveDefinition
## Nodo al que sigue el plano (normalmente el Rider).
@export var follow_path: NodePath
@export var size: float = 260.0
@export var subdivisions: int = 170

## Tiempo de las olas; se comparte con el shader.
var time: float = 0.0

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _follow: Node3D


func _ready() -> void:
	add_to_group("water")
	# Se procesa antes que el resto para que todos usen el mismo `time` en el frame.
	process_priority = -10
	if waves == null:
		waves = WaveDefinition.new()

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	waves.apply_to(_material)

	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	plane.material = _material

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Surface"
	_mesh_instance.mesh = plane
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 2.0
	add_child(_mesh_instance)

	_follow = get_node_or_null(follow_path) as Node3D


func _process(delta: float) -> void:
	time += minf(delta, 1.0 / 20.0)
	_material.set_shader_parameter("wave_time", time)
	if _follow:
		# Se mueve en pasos del tamaño de una celda para que la malla no "nade".
		var step := size / float(subdivisions + 1)
		var p := _follow.global_position
		_mesh_instance.global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))


func height_at(x: float, z: float) -> float:
	return waves.height_at(x, z, time)


func normal_at(x: float, z: float) -> Vector3:
	return waves.normal_at(x, z, time)
