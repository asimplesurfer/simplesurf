class_name Water
extends Node3D
## Plano de agua que sigue al jugador (parece infinito) y se ondula.
## Altura = olas de fondo (WaveDefinition) + olas grandes (Swell) que maneja WaveManager.
## Ofrece height_at() / normal_at() para que las cosas floten justo sobre lo que se ve.

const SHADER := preload("res://world/water/water.gdshader")
## Cantidad de olas grandes que entiende el shader (swell_a0..swell_a5).
const MAX_SWELLS := 6

@export var waves: WaveDefinition
## Nodo al que sigue el plano (normalmente el Rider).
@export var follow_path: NodePath
@export var size: float = 260.0
@export var subdivisions: int = 170

## Tiempo de las olas; se comparte con el shader.
var time: float = 0.0
var swells: Array[Swell] = []

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _follow: Node3D


func _ready() -> void:
	add_to_group("water")
	# Se procesa antes que el resto para que todos usen el mismo estado en el frame.
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
	_mesh_instance.extra_cull_margin = 4.0
	add_child(_mesh_instance)

	_follow = get_node_or_null(follow_path) as Node3D
	_push_swells()


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	time += delta
	_material.set_shader_parameter("wave_time", time)

	for i in range(swells.size() - 1, -1, -1):
		swells[i].update(delta)
		if swells[i].is_dead():
			swells.remove_at(i)
	_push_swells()

	if _follow:
		# Se mueve en pasos del tamaño de una celda para que la malla no "nade".
		var step := size / float(subdivisions + 1)
		var p := _follow.global_position
		_mesh_instance.global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))


func can_add_swell() -> bool:
	return swells.size() < MAX_SWELLS


func add_swell(swell: Swell) -> void:
	if can_add_swell():
		swells.append(swell)


func clear_swells() -> void:
	swells.clear()
	_push_swells()


func height_at(x: float, z: float) -> float:
	var h := waves.height_at(x, z, time)
	var p := Vector2(x, z)
	for s in swells:
		h += s.height_at(p)
	return h


func normal_at(x: float, z: float) -> Vector3:
	var g := waves.gradient_at(x, z, time)
	var p := Vector2(x, z)
	for s in swells:
		g += s.gradient_at(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


func _push_swells() -> void:
	for i in MAX_SWELLS:
		var a := Vector4(0.0, 0.0, 1.0, 0.0)
		var b := Vector4.ZERO
		if i < swells.size():
			a = swells[i].shader_a()
			b = swells[i].shader_b()
		_material.set_shader_parameter("swell_a%d" % i, a)
		_material.set_shader_parameter("swell_b%d" % i, b)
