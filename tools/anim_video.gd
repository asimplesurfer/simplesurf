extends SceneTree
## Video de las animaciones: un guion de ~21 s que recorre todo lo que hace el
## surfista (andar, curvas, subir una ola, salto, chapuzón y secarse, turbo,
## derrape, truco, caída con revolcón, nadar, remar, pararse, festejar),
## moviéndolo de verdad (avanza, sube y baja) para que el pelo y el collar
## reaccionen. Guarda los cuadros en una carpeta; con ffmpeg se arma el video.
##
## Uso (con pantalla, a 30 cuadros por segundo fijos):
##   godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --script res://tools/anim_video.gd -- carpeta_de_salida

const SIZE := 360
const FPS := 30.0
const SPEED := 9.0
## Guion: [desde (s), qué pasa].
const SCRIPT := [
	[0.0, "ride"], [2.0, "left"], [3.2, "right"], [4.4, "climb_wave"], [5.2, "jump"],
	[6.8, "ride"], [7.6, "duck"], [8.3, "ride_shake"], [9.4, "turbo"], [10.4, "drift"],
	[11.6, "trick"], [13.0, "ride"], [13.6, "crash"], [16.4, "climb_board"], [16.85, "paddle"],
	[18.6, "pop_up"], [18.9, "ride"], [19.6, "celebrate"], [21.2, "end"],
]

var _vp: SubViewport
var _root: Node3D
var _tilt: Node3D
var _body_pivot: Node3D
var _avatar: Avatar
var _board: Node3D
var _water: MeshInstance3D
var _cam: Camera3D
var _t: float = 0.0
var _y: float = 0.0
var _vy: float = 0.0
var _z: float = 0.0
var _phase: String = ""
var _phase_t: float = 0.0
var _stage := Rider.RecoveryStage.STANDING
var _pose_from := Transform3D()
var _pose_to := Transform3D()
var _pose_t: float = 1.0
var _pose_dur: float = 0.3
var _pose_arc: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://anim_video"
	DirAccess.make_dir_recursive_absolute(out)
	_build_scene()
	var frame := 0
	while true:
		var phase := _phase_at(_t)
		if phase == "end":
			break
		if phase != _phase:
			_enter(phase)
		_step(1.0 / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.save_png("%s/f%04d.png" % [out, frame])
		frame += 1
		_t += 1.0 / FPS
		_phase_t += 1.0 / FPS
	print("Cuadros: %d en %s" % [frame, out])
	quit()


func _phase_at(t: float) -> String:
	var phase := "ride"
	for step in SCRIPT:
		if t >= step[0]:
			phase = step[1]
	return phase


func _enter(phase: String) -> void:
	_phase = phase
	_phase_t = 0.0
	match phase:
		"jump":
			_vy = 9.0
			_avatar.pop()
		"trick":
			_vy = 9.5
			_avatar.pop()
		"duck":
			pass
		"ride_shake":
			_avatar.shake_off()
		"crash":
			_set_stage(Rider.RecoveryStage.IN_WATER, RiderVisual.TUMBLE_TIME, 1.1)
		"climb_board":
			_set_stage(Rider.RecoveryStage.PRONE, 0.45, 0.55)
		"pop_up":
			_set_stage(Rider.RecoveryStage.STANDING, 0.3, 0.35)


func _set_stage(stage: Rider.RecoveryStage, dur: float, arc: float) -> void:
	_stage = stage
	_pose_from = _body_pivot.transform
	_pose_to = RiderVisual.body_pose(stage)
	_pose_t = 0.0
	_pose_dur = dur
	_pose_arc = arc


func _step(dt: float) -> void:
	var a := _avatar
	a.steer = 0.0
	a.turbo = false
	a.charge = 0.0
	a.speed = 0.6
	a.vertical_speed = 0.0
	var speed := SPEED
	var steer := 0.0
	match _phase:
		"ride", "ride_shake":
			a.anim = &"ride"
		"left":
			a.anim = &"ride"
			steer = -1.0
		"right":
			a.anim = &"ride"
			steer = 1.0
		"climb_wave":
			a.anim = &"ride"
			a.vertical_speed = 3.5
			_y += 1.2 * dt
		"jump", "trick":
			a.anim = &"trick" if _phase == "trick" else &"air"
			_vy -= 13.0 * dt
			_y += _vy * dt
			a.vertical_speed = _vy
			if _y <= 0.0 and _vy < 0.0:
				_y = 0.0
				a.land(clampf(absf(_vy) / 9.0, 0.35, 1.0))
				_phase = "ride"
				if _phase_t > 0.5 and a.anim == &"trick":
					a.cheer()
				a.anim = &"ride"
		"duck":
			a.anim = &"duck"
		"turbo":
			a.anim = &"ride"
			a.turbo = true
			a.speed = 1.0
			speed = SPEED * 1.4
		"drift":
			a.anim = &"drift"
			a.drift_side = 1
			speed = SPEED * 0.8
		"crash":
			a.anim = &"flail" if _phase_t < 1.4 else &"tread"
			a.effort = 0.3
			speed = 0.8
		"climb_board":
			a.anim = &"climb"
			speed = 1.0
		"paddle":
			a.anim = &"paddle"
			a.effort = 0.4
			speed = 2.5
		"pop_up":
			a.anim = &"pop_up"
			speed = 4.0
		"celebrate":
			a.anim = &"celebrate"
			speed = 5.0
	a.steer = move_toward(a.steer, steer, dt * 4.0)
	if _phase != "climb_wave" and _phase not in ["jump", "trick"]:
		_y = move_toward(_y, 0.0, dt * 2.0)
	_z -= speed * dt
	_root.position = Vector3(0.0, _y, _z)
	# Inclinación en la curva (como RiderVisual).
	_tilt.basis = Basis(Vector3.FORWARD, steer * RiderVisual.LEAN_ANGLE)
	# Cambio de etapa (caer, subir a la tabla, pararse).
	if _pose_t < 1.0:
		_pose_t = minf(1.0, _pose_t + dt / _pose_dur)
	var k := smoothstep(0.0, 1.0, _pose_t)
	var xf := _pose_from.interpolate_with(_pose_to, k)
	xf.origin.y += sin(_pose_t * PI) * _pose_arc
	if _stage == Rider.RecoveryStage.IN_WATER and _pose_t < 1.0:
		xf.basis = RiderVisual.tumble(_pose_t) * xf.basis
	if _stage == Rider.RecoveryStage.IN_WATER:
		xf.origin.y += sin(_t * 2.5) * 0.06
	_body_pivot.transform = xf
	_board.basis = Basis(RiderVisual.board_pose(_stage))
	# Cámara: de costado y adelante, siguiéndolo.
	# (A la altura del agua: así se ve cuánto sube en los saltos.)
	var at := Vector3(0.0, 0.9, _root.position.z)
	_cam.transform = Transform3D(Basis.IDENTITY, at + Vector3(-3.0, 1.2, -2.4)).looking_at(at, Vector3.UP)
	_water.position = Vector3(0.0, 0.0, _z)


func _build_scene() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
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
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.5, 0.75, 0.6)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = wm
	_water.mesh = plane
	_vp.add_child(_water)
	# Marcas en el agua para que se note que avanza.
	for i in 30:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.02, 0.1)
		box.material = ToonMaterial.make(Color(1, 1, 1, 1), 0.0)
		m.mesh = box
		m.position = Vector3(-1.5 + fmod(i * 1.7, 3.0), 0.01, -i * 4.0)
		_vp.add_child(m)
	_root = Node3D.new()
	_vp.add_child(_root)
	_tilt = Node3D.new()
	_root.add_child(_tilt)
	_board = Node3D.new()
	_tilt.add_child(_board)
	var cap := CapsuleMesh.new()
	cap.radius = RiderVisual.BOARD_WIDTH * 0.5
	cap.height = RiderVisual.BOARD_LENGTH
	cap.material = ToonMaterial.make(Color("#fff1c9"), 0.02)
	var b := MeshInstance3D.new()
	b.mesh = cap
	b.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, RiderVisual.BOARD_THICKNESS_SCALE))
	_board.add_child(b)
	_body_pivot = Node3D.new()
	_tilt.add_child(_body_pivot)
	_body_pivot.transform = RiderVisual.body_pose(Rider.RecoveryStage.STANDING)
	_avatar = Avatar.new()
	_avatar.data = CharacterData.new()
	_avatar.data.apply_preset(0)
	_avatar.scale = Vector3.ONE * RiderVisual.AVATAR_SCALE
	_avatar.rotation.y = PI
	_body_pivot.add_child(_avatar)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_vp.add_child(_cam)
	_cam.current = true
