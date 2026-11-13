class_name ThumbRenderer
extends Node
## Fotos chiquitas de cada opción del creador (un peinado, unos ojos, una
## tabla...): arma esa variante del personaje en un mundo aparte, la encuadra
## y guarda la imagen en el cuadrado. Hace una por vez, de a pocos cuadros,
## para que el menú no se trabe.

const SIZE := 112
## Encuadres: cabeza, cuerpo entero, pecho, short o solo la tabla.
enum Frame { HEAD, BODY, CHEST, HIPS, BOARD }

var _vp: SubViewport
var _pivot: Node3D
var _avatar: Avatar
var _board: Node3D
var _cam: Camera3D
var _jobs: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_avatar = Avatar.new()
	_avatar.data = CharacterData.new()
	_pivot.add_child(_avatar)
	_board = Node3D.new()
	_pivot.add_child(_board)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_cam.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	_vp.add_child(sun)


## Pide la foto de `data` con ese encuadre; cuando está, la pone en `target`.
func request(data: CharacterData, frame: Frame, target: TextureRect) -> void:
	_jobs.append({"data": data, "frame": frame, "target": target})
	if not _busy:
		_run()


## Olvida lo pendiente (al cambiar de categoría).
func clear() -> void:
	_jobs.clear()


func _run() -> void:
	_busy = true
	while not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		var target: TextureRect = job.target
		if not is_instance_valid(target):
			continue
		_frame_job(job.data, job.frame)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(target) or not is_inside_tree():
			continue
		var img := _vp.get_texture().get_image()
		if img and not img.is_empty():
			target.texture = ImageTexture.create_from_image(img)
	_busy = false


func _frame_job(data: CharacterData, frame: Frame) -> void:
	var board := frame == Frame.BOARD
	_avatar.visible = not board
	_board.visible = board
	if board:
		for c in _board.get_children():
			c.free()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.5
		mesh.height = 3.6
		mesh.material = ToonMaterial.make(data.board_color(), 0.04)
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.18))
		_board.add_child(body)
		BoardDesign.add_to(_board, data, 3.6, 1.0, 0.09)
		_board.rotation = Vector3(0.0, 0.6, 0.0)
		_look(Vector3(2.6, 3.4, 2.6), Vector3.ZERO)
		return
	_avatar.data = data
	_avatar.rebuild()
	_pivot.rotation.y = -0.35
	var head := _avatar.head_center()
	var r := _avatar.head_radius()
	match frame:
		Frame.HEAD:
			_look(head + Vector3(0.0, 0.0, 1.2 + r * 3.6), head + Vector3(0.0, -0.06, 0.0))
		Frame.CHEST:
			_look(Vector3(0.0, 1.5, 3.6), Vector3(0.0, 1.45, 0.0))
		Frame.HIPS:
			_look(Vector3(0.0, 0.85, 3.2), Vector3(0.0, 0.8, 0.0))
		_:
			_look(Vector3(0.0, 1.5, 8.6), Vector3(0.0, 1.35, 0.0))


func _look(eye: Vector3, at: Vector3) -> void:
	_cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(at, Vector3.UP)
