class_name Water
extends Node3D
## Plano de agua que sigue a cada jugador (parece infinito) y se ondula.
## Con pantalla dividida hay un plano por jugador, cada uno en su propia capa
## de render, y cada cámara ve solo el suyo.
## Altura = olas de fondo (WaveDefinition) + olas grandes (Swell) que maneja WaveManager.
## Ofrece height_at() / normal_at() para que las cosas floten justo sobre lo que se ve.

const SHADER := preload("res://world/water/water.gdshader")
## Cantidad de olas grandes que entiende el shader (swell_a0..swell_a5).
const MAX_SWELLS := 6

## Primera capa de render (índice desde 0) para los planos de cada jugador.
const FOLLOWER_LAYER_BASE := 10

@export var waves: WaveDefinition
## Nodo al que sigue el plano si nadie llama a add_follower (opcional).
@export var follow_path: NodePath
@export var size: float = 260.0
@export var subdivisions: int = 170

## Tiempo de las olas; se comparte con el shader.
var time: float = 0.0
var swells: Array[Swell] = []
## Isla: las olas grandes se apagan cerca de la orilla. (x, z, radio); radio 0 = sin isla.
var island := Vector3.ZERO

var _plane: PlaneMesh
var _material: ShaderMaterial
## Cada uno: {node: Node3D, mesh: MeshInstance3D}
var _followers: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("water")
	# Se procesa antes que el resto para que todos usen el mismo estado en el frame.
	process_priority = -10
	if waves == null:
		waves = WaveDefinition.new()

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	waves.apply_to(_material)

	_plane = PlaneMesh.new()
	_plane.size = Vector2(size, size)
	_plane.subdivide_width = subdivisions
	_plane.subdivide_depth = subdivisions
	_plane.material = _material

	var follow := get_node_or_null(follow_path) as Node3D
	if follow:
		add_follower(follow, -1)
	_push_swells()


## Agrega un plano de agua que sigue a `node`. layer_index = -1: capa normal (1);
## si no, usa la capa FOLLOWER_LAYER_BASE + layer_index (para pantalla dividida).
func add_follower(node: Node3D, layer_index: int = -1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Surface%d" % _followers.size()
	mi.mesh = _plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 6.0
	if layer_index >= 0:
		mi.layers = 1 << (FOLLOWER_LAYER_BASE + layer_index)
	add_child(mi)
	_followers.append({"node": node, "mesh": mi})
	_snap(mi, node)
	return mi


## Máscara de render para la cámara del jugador `layer_index`: todo menos el
## agua de los demás jugadores.
static func camera_cull_mask(layer_index: int, max_players: int = 4) -> int:
	var mask := 0xFFFFF
	for i in max_players:
		if i != layer_index:
			mask &= ~(1 << (FOLLOWER_LAYER_BASE + i))
	return mask


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	time += delta
	_material.set_shader_parameter("wave_time", time)

	for i in range(swells.size() - 1, -1, -1):
		swells[i].update(delta)
		if swells[i].is_dead():
			swells.remove_at(i)
	_push_swells()

	for f in _followers:
		if is_instance_valid(f.node):
			_snap(f.mesh, f.node)


## Mueve el plano en pasos del tamaño de una celda para que la malla no "nade".
func _snap(mi: MeshInstance3D, node: Node3D) -> void:
	var step := size / float(subdivisions + 1)
	var p := node.global_position
	mi.global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))


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
	var swell_h := 0.0
	for s in swells:
		swell_h += s.height_at(p)
	return h + swell_h * _island_fade(p)


func normal_at(x: float, z: float) -> Vector3:
	var g := waves.gradient_at(x, z, time)
	var p := Vector2(x, z)
	var swell_g := Vector2.ZERO
	for s in swells:
		swell_g += s.gradient_at(p)
	g += swell_g * _island_fade(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## 0 pegado a la isla, 1 lejos: las olas grandes no se meten en la playa.
## (Igual que island_fade en water.gdshader.)
func _island_fade(p: Vector2) -> float:
	if island.z <= 0.0:
		return 1.0
	var d := p.distance_to(Vector2(island.x, island.y))
	return smoothstep(island.z + 4.0, island.z + 28.0, d)


func set_island(center: Vector2, radius: float) -> void:
	island = Vector3(center.x, center.y, radius)
	_material.set_shader_parameter("island", island)


func _push_swells() -> void:
	for i in MAX_SWELLS:
		var a := Vector4(0.0, 0.0, 1.0, 0.0)
		var b := Vector4.ZERO
		if i < swells.size():
			a = swells[i].shader_a()
			b = swells[i].shader_b()
		_material.set_shader_parameter("swell_a%d" % i, a)
		_material.set_shader_parameter("swell_b%d" % i, b)
