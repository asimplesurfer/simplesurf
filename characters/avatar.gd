class_name Avatar
extends Node3D
## El personaje armado con las piezas de AvatarCore: cada pieza es una esfera
## escalada (elipsoide), con color plano sin luces y contorno negro grueso.
## Las manos flotan sin brazos con un leve vaivén. Mira hacia +Z y los pies
## están en y = 0 (en unidades de AvatarCore; escalar el nodo para el tamaño).

const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
## Grosor del contorno en unidades del avatar.
const OUTLINE := 0.06

var data: CharacterData

var _sphere := SphereMesh.new()
var _pieces: Dictionary = {}
var _materials: Dictionary = {}
var _hand_base: Dictionary = {}
var _time: float = 0.0
var _eyes: Array[MeshInstance3D] = []


func _init() -> void:
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 20
	_sphere.rings = 10


func _ready() -> void:
	if data == null:
		data = CharacterData.new()
	rebuild()


## Vuelve a calcular las piezas (llamar al cambiar peso o colores).
func rebuild() -> void:
	var parts := AvatarCore.get_avatar(data.weight, data.skin_color(), data.shorts_color())
	for part in parts:
		var id: String = part.id
		var piece: MeshInstance3D = _pieces.get(id)
		if piece == null:
			piece = MeshInstance3D.new()
			piece.name = id
			piece.mesh = _sphere
			add_child(piece)
			_pieces[id] = piece
		var radii: Vector3 = part.radii
		var min_r := minf(radii.x, minf(radii.y, radii.z))
		piece.visible = min_r >= 0.05
		piece.position = part.pos
		piece.scale = radii
		piece.material_override = _material_for(part.color, radii)
		if id.begins_with("hand"):
			_hand_base[id] = part.pos
	_place_eyes()


## Material plano con contorno. El contorno se infla en el espacio de la esfera
## (antes de escalar), así que se compensa con el tamaño medio de la pieza.
func _material_for(color: Color, radii: Vector3) -> StandardMaterial3D:
	var avg := (radii.x + radii.y + radii.z) / 3.0
	var key := "%s_%.3f" % [color.to_html(), avg]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("outline_width", OUTLINE / maxf(avg, 0.05))
	m.next_pass = outline
	_materials[key] = m
	return m


func _place_eyes() -> void:
	var head: MeshInstance3D = _pieces.get("head")
	if head == null:
		return
	if _eyes.is_empty():
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.07
		eye_mesh.height = 0.14
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color.BLACK
		eye_mesh.material = black
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			add_child(eye)
			_eyes.append(eye)
	# Sobre el frente de la cabeza (+Z), un poco arriba del centro.
	var r := head.scale
	for i in _eyes.size():
		var side := -1.0 if i == 0 else 1.0
		_eyes[i].position = head.position + Vector3(side * r.x * 0.36, r.y * 0.15, r.z * 0.9)


func _process(delta: float) -> void:
	_time += delta
	# Manos flotando con un leve vaivén.
	for id in _hand_base:
		var piece: MeshInstance3D = _pieces[id]
		var phase := 0.0 if String(id).ends_with("_L") else 1.3
		piece.position = _hand_base[id] + Vector3(0.0, sin(_time * 2.4 + phase) * 0.05, 0.0)
