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
##           └── Body    (el personaje: Avatar armado con AvatarCore)
##   ├── Trail           (estela sobre el agua que sigue a la tabla; en coordenadas del mundo)
##   ├── Wake            (salpicadura al girar)
##   └── Spray           (cortina de agua del derrape)

## Cómo se ve el personaje. Se asigna antes de agregar el Rider al árbol.
@export var character: CharacterData
@export var stripe_color: Color = Color(0.2, 0.55, 0.95)

## Escala del avatar (AvatarCore mide ~2.7 de alto; así queda de ~1.75 m).
const AVATAR_SCALE := 0.65
const BODY_HEIGHT := AvatarCore.HEIGHT * AVATAR_SCALE
## Mitad del grosor del cuerpo acostado.
const BODY_RADIUS := 0.24
const BOARD_LENGTH := 2.4
const BOARD_WIDTH := 0.66
const BOARD_THICKNESS_SCALE := 0.18
const BOARD_TOP := 0.06
const LEAN_ANGLE := 0.35
## Cuánto se pone de costado la tabla al derrapar (radianes).
const DRIFT_YAW := 1.15

var rider: Rider

var _tilt: Node3D
var _board_pivot: Node3D
var _body_pivot: Node3D
var _body: Avatar

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

var _trail: BoardTrail
var _wake: CPUParticles3D
## Tiempo desde el último cambio de etapa (caída, subida, parada).
var _stage_time: float = 0.0
var _spray: DriftSpray


func _ready() -> void:
	if character == null:
		character = CharacterData.new()
	_build()


func setup(p_rider: Rider) -> void:
	rider = p_rider
	rider.recovery_stage_changed.connect(_on_recovery_stage_changed)
	rider.mash_pressed.connect(_on_mash_pressed)
	_trail.setup(rider)
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
	board_mesh.material = ToonMaterial.make(character.board_color(), 0.04)
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

	# El avatar mira hacia +Z; el Rider avanza hacia -Z, así que se gira.
	_body = Avatar.new()
	_body.name = "Body"
	_body.data = character
	_body.scale = Vector3.ONE * AVATAR_SCALE
	_body.rotation.y = PI
	_body_pivot.add_child(_body)

	# Efectos de agua. No están dentro de Tilt para controlar su dirección a mano.
	_trail = BoardTrail.new()
	_trail.name = "Trail"
	add_child(_trail)

	_wake = WaterFx.soft_particles(50, 0.6, 0.45)
	_wake.name = "Wake"
	_wake.initial_velocity_min = 2.0
	_wake.initial_velocity_max = 4.0
	_wake.spread = 18.0
	add_child(_wake)

	_spray = DriftSpray.new()
	_spray.name = "Spray"
	add_child(_spray)


## Pose del personaje (transform del BodyPivot) para cada etapa.
static func body_pose(stage: Rider.RecoveryStage) -> Transform3D:
	match stage:
		Rider.RecoveryStage.IN_WATER:
			# En el agua al costado de la tabla, casi parado y hundido hasta el
			# pecho (así se ven la cabeza y los brazos agitándose).
			var b := Basis(Vector3.FORWARD, 0.25) * Basis(Vector3.RIGHT, -0.35)
			return Transform3D(b, Vector3(1.0, -BODY_HEIGHT * 0.62, 0.3))
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
	_stage_time = 0.0
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
	# Cargando el salto: se agacha e inclina hacia adelante.
	var charge := rider.jump_charge
	xf.basis = xf.basis * Basis(Vector3.RIGHT, -0.35 * charge)
	_body_pivot.transform = xf
	# En el truco la tabla gira bajo el jugador.
	_board_pivot.quaternion = (
		_board_from.slerp(_board_to, t) * Quaternion(Vector3.UP, -rider.trick_angle)
	)
	_update_particles(delta)
	_update_avatar_anim(delta)

	# "Golpe" de cada pulsación: la pastilla se aplasta un poco.
	_punch = move_toward(_punch, 0.0, delta * 5.0)
	var squash := maxf(_punch * 0.15, rider.jump_charge * 0.3)
	_body.scale = (
		Vector3(1.0 + squash * 1.1, 1.0 - squash, 1.0 + squash * 1.1) * AVATAR_SCALE
	)


## Elige la animación del personaje según lo que está haciendo el Rider.
func _update_avatar_anim(delta: float) -> void:
	_stage_time += delta
	var stage := rider.recovery_stage
	var a: StringName = &"ride"
	_body.effort = clampf(_punch * 1.5, 0.0, 1.0)
	_body.charge = rider.jump_charge
	_body.steer = rider.steer_amount
	match stage:
		Rider.RecoveryStage.IN_WATER:
			a = &"flail" if _stage_time < 1.4 or _punch > 0.3 else &"tread"
		Rider.RecoveryStage.PRONE:
			a = &"climb" if _stage_time < rider.stats.climb_time else &"paddle"
			_body.effort = maxf(_body.effort, clampf(rider.speed / 3.0, 0.0, 1.0))
		_:
			if _stage_time < 0.3 and _pose_t < 1.0:
				a = &"pop_up"
			elif not rider.grounded:
				a = &"trick" if rider.trick_angle > 0.0 else &"air"
			elif rider.drift_side != 0:
				a = &"drift"
				_body.drift_side = rider.drift_side
			elif rider.race_finished:
				a = &"celebrate"
	_body.anim = a


func _idle_offset(stage: Rider.RecoveryStage) -> Vector3:
	match stage:
		Rider.RecoveryStage.IN_WATER:
			# Al caer se hunde un poco y vuelve a salir.
			var dip := -0.35 * sin(clampf(_stage_time / 1.2, 0.0, 1.0) * PI)
			return Vector3(0.0, sin(_time * 2.5) * 0.06 + dip, 0.0)
		Rider.RecoveryStage.PRONE:
			return Vector3(0.0, absf(sin(_time * 7.0)) * 0.03 * minf(rider.speed, 1.0), 0.0)
		_:
			return Vector3(0.0, sin(_time * 3.0) * 0.02, 0.0)


func _update_particles(delta: float) -> void:
	var on_water := rider.grounded and rider.recovery_stage == Rider.RecoveryStage.STANDING

	# Cortina de agua del derrape: sale de la cola de la tabla, recta hacia atrás
	# (justo donde el derrape tumba a los rivales).
	var drift_side := rider.drift_side if on_water else 0
	if drift_side != 0:
		_spray.position = Vector3(0.0, 0.05, 0.8)
	_spray.update_spray(drift_side, clampf(rider.speed / 8.0, 0.5, 1.0), delta)

	# Salpicadura al girar: sale del borde de afuera de la curva.
	var turn := absf(rider.steer_amount) * rider.speed
	var turning := on_water and drift_side == 0 and turn > 3.0
	_wake.emitting = turning
	if turning:
		var outside := -signf(rider.steer_amount)
		_wake.position = Vector3(outside * 0.35, 0.1, 0.8)
		_wake.direction = Vector3(outside * 0.8, 0.7, 0.6).normalized()
		_wake.initial_velocity_max = 2.5 + turn * 0.25
