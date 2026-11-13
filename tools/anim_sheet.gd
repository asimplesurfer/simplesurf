extends SceneTree
## Planilla de animaciones: dibuja cada animación del surfista en varios
## momentos y la guarda como una sola imagen, para revisarlas a ojo.
## Igual que en el juego: el personaje en su pose (de pie, en el agua o
## acostado) sobre la tabla y con el nivel del agua.
##
## Uso (con pantalla):
##   godot --path . --rendering-driver opengl3 --script res://tools/anim_sheet.gd -- salida.png

const CELL := 220
const COLS := 6

var _vp: SubViewport
var _avatar: Avatar
var _body_pivot: Node3D
var _board: Node3D
var _water: MeshInstance3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_scene()
	var rows := _scenarios()
	var sheet := Image.create(CELL * COLS, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.3, 0.4))
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			var cell: Dictionary = row[c]
			_pose(cell)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := _vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(c * CELL, r * CELL))
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://anim_sheet.png"
	sheet.save_png(out)
	print("Planilla: ", out)
	quit()


func _build_scene() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL, CELL)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#86d6f5")
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	_vp.add_child(sun)
	# Agua: un plano semitransparente en y = 0.
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.5, 0.75, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = wm
	_water.mesh = plane
	_vp.add_child(_water)
	_board = Node3D.new()
	_vp.add_child(_board)
	var cap := CapsuleMesh.new()
	cap.radius = RiderVisual.BOARD_WIDTH * 0.5
	cap.height = RiderVisual.BOARD_LENGTH
	cap.material = ToonMaterial.make(Color("#fff1c9"), 0.02)
	var b := MeshInstance3D.new()
	b.mesh = cap
	b.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, RiderVisual.BOARD_THICKNESS_SCALE))
	_board.add_child(b)
	_body_pivot = Node3D.new()
	_vp.add_child(_body_pivot)
	_avatar = Avatar.new()
	_avatar.data = CharacterData.new()
	_avatar.data.apply_preset(0)
	_avatar.scale = Vector3.ONE * RiderVisual.AVATAR_SCALE
	_avatar.rotation.y = PI
	_body_pivot.add_child(_avatar)
	_avatar.set_process(false)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	_cam.current = true


## Filas de la planilla: cada celda es un estado de la animación.
func _scenarios() -> Array:
	var rows := []
	var ride := []
	for i in 6:
		ride.append({"anim": &"ride", "time": i * 0.12, "speed": 0.6, "label": "ride"})
	rows.append(ride)
	rows.append([
		{"anim": &"ride", "speed": 0.6, "steer": -1.0},
		{"anim": &"ride", "speed": 0.6, "steer": 1.0},
		{"anim": &"ride", "speed": 1.0, "turbo": true},
		{"anim": &"ride", "speed": 0.5, "charge": 1.0},
		{"anim": &"ride", "speed": 0.6, "vy": 4.0},
		{"anim": &"ride", "speed": 0.6, "pop": 1.0},
	])
	rows.append([
		{"anim": &"air", "vy": 9.0, "air": true},
		{"anim": &"air", "vy": 4.0, "air": true},
		{"anim": &"air", "vy": 0.0, "air": true},
		{"anim": &"air", "vy": -4.0, "air": true},
		{"anim": &"air", "vy": -9.0, "air": true},
		{"anim": &"trick", "vy": 2.0, "air": true},
	])
	rows.append([
		{"anim": &"ride", "speed": 0.6, "land": 1.0},
		{"anim": &"ride", "speed": 0.6, "land": 0.5},
		{"anim": &"drift", "speed": 0.8, "drift_side": 1},
		{"anim": &"drift", "speed": 0.8, "drift_side": -1},
		{"anim": &"duck"},
		{"anim": &"pop_up", "t": 0.15},
	])
	var flail := []
	for i in 6:
		flail.append({"anim": &"flail", "t": i * 0.07, "time": i * 0.07, "stage": "water"})
	rows.append(flail)
	var tread := []
	for i in 6:
		tread.append({"anim": &"tread", "time": i * 0.18, "stage": "water"})
	rows.append(tread)
	var paddle := []
	for i in 6:
		paddle.append({"anim": &"paddle", "time": i * 0.2, "effort": 0.3, "stage": "prone"})
	rows.append(paddle)
	rows.append([
		{"anim": &"climb", "t": 0.1, "stage": "prone"},
		{"anim": &"climb", "t": 0.25, "stage": "prone"},
		{"anim": &"celebrate", "time": 0.0},
		{"anim": &"celebrate", "time": 0.26},
		{"anim": &"idle", "time": 0.0},
		{"anim": &"idle", "time": 2.0},
	])
	var shake := []
	for i in 6:
		shake.append({"anim": &"ride", "speed": 0.5, "shake": 1.0 - i * 0.16, "time": i * 0.013 + 0.02})
	rows.append(shake)
	return rows


func _pose(cell: Dictionary) -> void:
	var stage := Rider.RecoveryStage.STANDING
	match cell.get("stage", ""):
		"water":
			stage = Rider.RecoveryStage.IN_WATER
		"prone":
			stage = Rider.RecoveryStage.PRONE
	var lift := 0.8 if cell.get("air", false) else 0.0
	var xf := RiderVisual.body_pose(stage)
	xf.origin.y += lift
	_body_pivot.transform = xf
	_board.transform = Transform3D(Basis(RiderVisual.board_pose(stage)), Vector3(0.0, lift, 0.0))
	var state := {
		"anim": cell.anim, "t": cell.get("t", 0.0), "time": cell.get("time", 0.0),
		"steer": cell.get("steer", 0.0), "charge": cell.get("charge", 0.0),
		"drift_side": cell.get("drift_side", 1), "effort": cell.get("effort", 0.0),
		"speed": cell.get("speed", 0.0), "vy": cell.get("vy", 0.0), "land": cell.get("land", 0.0),
		"pop": cell.get("pop", 0.0), "turbo": cell.get("turbo", false),
		"shake": cell.get("shake", 0.0),
	}
	_avatar._kit.animate(state, 0.0, true)
	# Cámara de costado y un poco adelante (el Rider avanza hacia -Z).
	var at := Vector3(0.0, 0.75 + lift, 0.0)
	if stage == Rider.RecoveryStage.PRONE:
		at = Vector3(0.0, 0.3, -0.3)
	elif stage == Rider.RecoveryStage.IN_WATER:
		at = Vector3(0.6, -0.1, 0.2)
	_cam.transform = Transform3D(Basis.IDENTITY, at + Vector3(-1.9, 0.9, -1.7)).looking_at(at, Vector3.UP)
