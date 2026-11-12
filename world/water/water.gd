class_name Water
extends Node3D
## Plano de agua que sigue a cada jugador (parece infinito) y se ondula.
## Con pantalla dividida hay un plano por jugador, cada uno en su propia capa
## de render, y cada cámara ve solo el suyo.
## Altura = olas de fondo (WaveDefinition) + olas grandes (Swell) que maneja WaveManager.
## Ofrece height_at() / normal_at() para que las cosas floten justo sobre lo que se ve.

const SHADER := preload("res://world/water/water.gdshader")
## Cantidad de olas grandes que entiende el shader (swell_a0..swell_a7).
const MAX_SWELLS := 8

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
## Modo "ola constante a la izquierda" (null = sin ola constante).
var ring_wave: RingWave = null
## Islas: las olas grandes se apagan cerca de la orilla. Cada una (x, z, radio).
var islands: Array[Vector3] = []
## Islas que entiende el shader (islands[0..15]).
const MAX_ISLANDS := 16

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
	if ring_wave:
		ring_wave.update(delta)
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


## Pone (o saca, con null) la ola constante.
func set_ring_wave(rw: RingWave) -> void:
	ring_wave = rw
	_push_swells()


func height_at(x: float, z: float) -> float:
	return waves.height_at(x, z, time) + swell_height_at(x, z)


## Altura que aportan solo las olas grandes (para saber si está sobre una).
func swell_height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	for s in swells:
		h += s.height_at(p)
	if ring_wave:
		h += ring_wave.height_at(p)
	if h == 0.0:
		return 0.0
	return h * _island_fade(p)


## Qué tanto está rompiendo la ola grande que hay en ese punto (0 si no hay).
func breaking_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for s in swells:
		if s.breaking > best and s.height_at(p) > s.max_amplitude * 0.35:
			best = s.breaking
	return best


## true si el punto (la cara de alguien) quedó adentro del agua de una ola
## grande tal como se ve en pantalla, incluido el labio que se curva al romper.
func face_in_wave(q: Vector3) -> bool:
	var p := Vector2(q.x, q.z)
	var fade := _island_fade(p)
	if fade <= 0.0:
		return false
	var ambient := waves.height_at(q.x, q.z, time)
	if ring_wave:
		var rh := ring_wave.height_at(p) * fade
		if rh > Swell.MIN_FACE_DEPTH and q.y < ambient + rh:
			return true
	for s in swells:
		# El resto de las olas grandes suma su altura en ese punto.
		var others := 0.0
		for o in swells:
			if o != s:
				others += o.height_at(p)
		if ring_wave:
			others += ring_wave.height_at(p)
		if s.face_inside(q, ambient + others * fade, fade):
			return true
	return false


func normal_at(x: float, z: float) -> Vector3:
	var g := waves.gradient_at(x, z, time)
	var p := Vector2(x, z)
	var swell_g := Vector2.ZERO
	for s in swells:
		swell_g += s.gradient_at(p)
	if ring_wave:
		swell_g += ring_wave.gradient_at(p)
	if swell_g != Vector2.ZERO:
		g += swell_g * _island_fade(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## 0 pegado a la isla, 1 lejos: las olas grandes no se meten en la playa.
## (Igual que island_fade en water.gdshader.)
func _island_fade(p: Vector2) -> float:
	var fade := 1.0
	for i in mini(islands.size(), MAX_ISLANDS):
		var isl := islands[i]
		var d := p.distance_to(Vector2(isl.x, isl.y))
		fade *= smoothstep(isl.z + 4.0, isl.z + 28.0, d)
	return fade


## Pista (anillo): el agua de afuera se ve más oscura, para que se note el borde.
func set_track(center: Vector2, inner: float, outer: float) -> void:
	_material.set_shader_parameter("track_band", Vector4(center.x, center.y, inner, outer))


func set_island(center: Vector2, radius: float) -> void:
	var list: Array[Vector3] = [Vector3(center.x, center.y, radius)]
	set_islands(list)


## Islas (x, z, radio): las olas grandes se apagan cerca de cada orilla.
## El shader entiende hasta MAX_ISLANDS (las primeras de la lista).
func set_islands(list: Array[Vector3]) -> void:
	islands = list.duplicate()
	var packed := PackedVector3Array()
	packed.resize(MAX_ISLANDS)
	for i in MAX_ISLANDS:
		packed[i] = list[i] if i < list.size() else Vector3.ZERO
	_material.set_shader_parameter("islands", packed)
	_material.set_shader_parameter("island_count", mini(list.size(), MAX_ISLANDS))


func _push_swells() -> void:
	for i in MAX_SWELLS:
		var a := Vector4(0.0, 0.0, 1.0, 0.0)
		var b := Vector4.ZERO
		if i < swells.size():
			a = swells[i].shader_a()
			b = swells[i].shader_b()
		_material.set_shader_parameter("swell_a%d" % i, a)
		_material.set_shader_parameter("swell_b%d" % i, b)
	var ra := Vector4(0.0, 0.0, 1.0, 1.0)
	var rb := Vector4.ZERO
	if ring_wave:
		ra = ring_wave.shader_a()
		rb = ring_wave.shader_b()
	_material.set_shader_parameter("ring_a", ra)
	_material.set_shader_parameter("ring_b", rb)
