class_name RiderVisual
extends Node3D
## Parte visual del Rider: la tabla y la "pastilla" (el personaje).
## No tiene lógica de juego: escucha las señales del Rider y anima.
##
## Jerarquía que se crea en _ready():
##   Visual
##   └── Tilt            (se inclina con la ola y al girar)
##       ├── BoardPivot  (tabla; se ladea cuando está caído)
##       │   ├── Board
##       │   └── Stripe
##       └── BodyPivot   (está en los pies del personaje; se anima entre poses)
##           └── Body    (la pastilla)
##               └── ojos
##   ├── Wake            (estela al girar)
##   └── Spray           (cono de agua del derrape)

@export var body_color: Color = Color(0.98, 0.5, 0.32)
@export var board_color: Color = Color(1.0, 0.86, 0.3)
@export var stripe_color: Color = Color(0.2, 0.55, 0.95)

const BODY_HEIGHT := 1.6
const BODY_RADIUS := 0.34
const BOARD_LENGTH := 2.4
const BOARD_WIDTH := 0.66
const BOARD_THICKNESS_SCALE := 0.18
const BOARD_TOP := 0.06
const LEAN_ANGLE := 0.35
## Cuánto se pone de costado la tabla al derrapar (radianes).
const DRIFT_YAW := 1.15
const WATER_COLOR := Color(0.9, 0.97, 1.0)

var rider: Rider

var _tilt: Node3D
var _board_pivot: Node3D
var _body_pivot: Node3D
var _body: MeshInstance3D

var _pose_from: Transform3D
var _pose_to: Transform3D
var _board_from: Quaternion
var _board_to: Quaternion
var _pose_t: float = 1.0
var _pose_duration: float = 0.4
var _pose_arc: float = 0.0
var _initialized: bool = false

var _punch: float = 0.0
var _lean: float = 0.0
var _drift_yaw: float = 0.0
var _time: float = 0.0

var _wake: CPUParticles3D
var _spray: CPUParticles3D


func _ready() -> void:
	_build()


func setup(p_rider: Rider) -> void:
	rider = p_rider
	rider.recovery_stage_changed.connect(_on_recovery_stage_changed)
	rider.mash_pressed.connect(_on_mash_pressed)
	_snap_to(rider.recovery_stage)


func _build() -> void:
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	_tilt.position.y = -0.03
	add_child(_tilt)

	# Tabla: una cápsula acostada y aplastada.
	_board_pivot = Node3D.new()
	_board_pivot.name = "BoardPivot"
	_tilt.add_child(_board_pivot)

	var board_mesh := CapsuleMesh.new()
	board_mesh.radius = BOARD_WIDTH * 0.5
	board_mesh.height = BOARD_LENGTH
	board_mesh.material = ToonMaterial.make(board_color, 0.04)
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = board_mesh
	# Acostada sobre Z (rotación en X) y aplastada en lo que queda vertical.
	board.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(
		Vector3(1.0, 1.0, BOARD_THICKNESS_SCALE)
	)
	_board_pivot.add_child(board)

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.09, 0.01, BOARD_LENGTH * 0.75)
	stripe_mesh.material = ToonMaterial.make(stripe_color, 0.0)
	var stripe := MeshInstance3D.new()
	stripe.name = "Stripe"
	stripe.mesh = stripe_mesh
	stripe.position.y = BOARD_TOP - 0.002
	_board_pivot.add_child(stripe)

	# Personaje: la pastilla, con el origen del pivot en los pies.
	_body_pivot = Node3D.new()
	_body_pivot.name = "BodyPivot"
	_tilt.add_child(_body_pivot)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = BODY_RADIUS
	body_mesh.height = BODY_HEIGHT
	body_mesh.material = ToonMaterial.make(body_color, 0.035)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = body_mesh
	_body.position.y = BODY_HEIGHT * 0.5
	_body_pivot.add_child(_body)

	# Ojos para saber hacia dónde mira.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.055
	eye_mesh.height = 0.13
	eye_mesh.material = ToonMaterial.flat(Color.BLACK)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.position = Vector3(0.12 * side, 0.42, -BODY_RADIUS + 0.03)
		_body.add_child(eye)

	# Partículas de agua. No están dentro de Tilt para controlar su dirección a mano.
	_wake = _make_particles(70, 0.6, 0.11)
	_wake.name = "Wake"
	_wake.initial_velocity_min = 2.0
	_wake.initial_velocity_max = 4.0
	_wake.spread = 18.0
	add_child(_wake)

	_spray = _make_particles(160, 0.75, 0.16)
	_spray.name = "Spray"
	_spray.initial_velocity_min = 5.0
	_spray.initial_velocity_max = 8.5
	_spray.spread = 22.0
	add_child(_spray)


func _make_particles(amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = ToonMaterial.flat(WATER_COLOR)
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	return p


## Pose del personaje (transform del BodyPivot) para cada etapa.
static func body_pose(stage: Rider.RecoveryStage) -> Transform3D:
	match stage:
		Rider.RecoveryStage.IN_WATER:
			# Flotando al costado de la tabla, medio hundido, agarrado del borde.
			var b := Basis(Vector3.FORWARD, 0.35) * Basis(Vector3.RIGHT, -PI / 2.0 + 0.25)
			return Transform3D(b, Vector3(0.8, -0.1, 0.75))
		Rider.RecoveryStage.PRONE:
			# Acostado boca abajo sobre la tabla, con la cabeza hacia adelante.
			var b := Basis(Vector3.RIGHT, -PI / 2.0)
			return Transform3D(b, Vector3(0.0, BOARD_TOP + BODY_RADIUS, BODY_HEIGHT * 0.5))
		_:
			return Transform3D(Basis.IDENTITY, Vector3(0.0, BOARD_TOP, 0.0))


## Orientación de la tabla para cada etapa (caída: un poco ladeada y girada).
static func board_pose(stage: Rider.RecoveryStage) -> Quaternion:
	if stage == Rider.RecoveryStage.IN_WATER:
		return Quaternion(Vector3.UP, 0.25) * Quaternion(Vector3.FORWARD, -0.12)
	return Quaternion.IDENTITY


func _snap_to(stage: Rider.RecoveryStage) -> void:
	_pose_from = body_pose(stage)
	_pose_to = _pose_from
	_board_from = board_pose(stage)
	_board_to = _board_from
	_pose_t = 1.0
	_body_pivot.transform = _pose_to
	_board_pivot.quaternion = _board_to
	_initialized = true


func _on_recovery_stage_changed(stage: Rider.RecoveryStage) -> void:
	if not _initialized:
		_snap_to(stage)
		return
	_pose_from = _body_pivot.transform
	_pose_to = body_pose(stage)
	_board_from = _board_pivot.quaternion
	_board_to = board_pose(stage)
	_pose_t = 0.0
	match stage:
		Rider.RecoveryStage.IN_WATER:  # Sale volando de la tabla.
			_pose_duration = 0.35
			_pose_arc = 0.6
		Rider.RecoveryStage.PRONE:  # Se trepa a la tabla.
			_pose_duration = rider.stats.climb_time
			_pose_arc = 0.55
		_:  # Se para de un salto.
			_pose_duration = 0.3
			_pose_arc = 0.35


func _on_mash_pressed() -> void:
	_punch = 1.0


func _process(delta: float) -> void:
	if rider == null:
		return
	_time += delta
	var stage := rider.recovery_stage

	# Inclinación: seguir la normal del agua, ponerse de costado al derrapar
	# y ladearse al girar. En el aire: nariz arriba al subir, abajo al bajar.
	var tilt_base := Quaternion.IDENTITY
	if rider.grounded:
		var local_normal := (Basis(Vector3.UP, -rider.heading) * rider.water_normal).normalized()
		tilt_base = Quaternion(Vector3.UP, local_normal)
	else:
		tilt_base = Quaternion(Vector3.RIGHT, clampf(rider.vertical_speed * 0.04, -0.35, 0.35))
	var drift_target := -rider.drift_side * DRIFT_YAW
	_drift_yaw = lerpf(_drift_yaw, drift_target, 1.0 - exp(-12.0 * delta))
	var lean_target := rider.steer_amount * LEAN_ANGLE
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-6.0 * delta))
	var tilt_target := (
		tilt_base * Quaternion(Vector3.UP, _drift_yaw) * Quaternion(Vector3.FORWARD, _lean)
	)
	_tilt.quaternion = _tilt.quaternion.slerp(tilt_target, 1.0 - exp(-10.0 * delta))

	# Animación entre poses, con un pequeño arco hacia arriba (salto).
	if _pose_t < 1.0:
		_pose_t = minf(1.0, _pose_t + delta / _pose_duration)
	var t := smoothstep(0.0, 1.0, _pose_t)
	var xf := _pose_from.interpolate_with(_pose_to, t)
	xf.origin.y += sin(_pose_t * PI) * _pose_arc
	xf.origin += _idle_offset(stage)
	_body_pivot.transform = xf
	# En el truco la tabla gira bajo el jugador.
	_board_pivot.quaternion = (
		_board_from.slerp(_board_to, t) * Quaternion(Vector3.UP, -rider.trick_angle)
	)
	_update_particles()

	# "Golpe" de cada pulsación: la pastilla se aplasta un poco.
	_punch = move_toward(_punch, 0.0, delta * 5.0)
	_body.scale = Vector3(1.0 + 0.18 * _punch, 1.0 - 0.15 * _punch, 1.0 + 0.18 * _punch)


func _idle_offset(stage: Rider.RecoveryStage) -> Vector3:
	match stage:
		Rider.RecoveryStage.IN_WATER:
			return Vector3(0.0, sin(_time * 2.5) * 0.06, 0.0)
		Rider.RecoveryStage.PRONE:
			return Vector3(0.0, absf(sin(_time * 7.0)) * 0.03 * minf(rider.speed, 1.0), 0.0)
		_:
			return Vector3(0.0, sin(_time * 3.0) * 0.02, 0.0)


func _update_particles() -> void:
	var on_water := rider.grounded and rider.recovery_stage == Rider.RecoveryStage.STANDING

	# Cono de agua del derrape: sale de la cola de la tabla, hacia atrás y afuera.
	var drifting := on_water and rider.drift_side != 0
	_spray.emitting = drifting
	if drifting:
		var side := float(rider.drift_side)
		_spray.position = Vector3(-side * 0.5, 0.15, 0.9)
		_spray.direction = Vector3(-side * 0.35, 0.55, 1.0).normalized()

	# Estela al girar: sale del borde de afuera de la curva.
	var turn := absf(rider.steer_amount) * rider.speed
	var turning := on_water and not drifting and turn > 3.0
	_wake.emitting = turning
	if turning:
		var outside := -signf(rider.steer_amount)
		_wake.position = Vector3(outside * 0.35, 0.1, 0.8)
		_wake.direction = Vector3(outside * 0.8, 0.7, 0.6).normalized()
		_wake.initial_velocity_max = 2.5 + turn * 0.25
