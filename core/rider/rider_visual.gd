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
## Duración del revolcón al caerse (s).
const TUMBLE_TIME := 0.7
## Acostado: cuánto más atrás en la tabla va el cuerpo (m).
const PRONE_BACK := 0.5
## Cuánto tarda en pararse desde acostado (empuja, recoge las piernas, se para).
const POP_UP_PRONE_TIME := 0.65

var rider: Rider
## Para los golpes de despegue y aterrizaje de la animación.
var _was_in_air: bool = false
var _last_air_vy: float = 0.0

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
## Etapa anterior y si se está trepando a la tabla desde el agua (en el modo
## libre también se acuesta desde parado, y ahí no se trepa).
var _last_stage: Rider.RecoveryStage = Rider.RecoveryStage.STANDING
var _climbing: bool = false
var _spray: DriftSpray
## Pared de agua al girar rápido (hacia afuera de la curva). Solo se ve: no
## tumba a nadie (eso es del derrape).
var _carve: CarveSpray
const CARVE_ANGLE := 55.0
## Chapuzón al atravesar una ola que rompe.
var _splash: CPUParticles3D
var _ring_splash: CPUParticles3D
## Tiempo que queda de la animación de atravesar la ola (agachado, brazos sobre la cabeza).
var duck_time: float = 0.0
const DUCK_DURATION := 0.45


func _ready() -> void:
	if character == null:
		character = CharacterData.new()
	_build()


func setup(p_rider: Rider) -> void:
	rider = p_rider
	rider.recovery_stage_changed.connect(_on_recovery_stage_changed)
	rider.mash_pressed.connect(_on_mash_pressed)
	rider.wave_punched.connect(_on_wave_punched)
	# Salpicón alrededor (solo se ve): al chocar con otro y al caer de alto.
	rider.bumped.connect(func(_d: Vector3, strength: float) -> void: _ring_burst(0.5 + strength))
	rider.bumped_other.connect(func(_v: Rider) -> void: _ring_burst(0.6))
	rider.hard_landed.connect(func(strength: float) -> void: _ring_burst(0.6 + strength))
	# Festeja cuando clava un truco o tira a un rival.
	rider.trick_landed.connect(func(_spins: int) -> void: _body.cheer())
	rider.drift_hit.connect(func(_victim: Rider) -> void: _body.cheer())
	_trail.setup(rider)
	_last_stage = rider.recovery_stage
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
	board_mesh.material = BoardDesign.material(character, BOARD_LENGTH, BOARD_WIDTH)
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = board_mesh
	# Acostada sobre Z (rotación en X) y aplastada en lo que queda vertical.
	board.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(
		Vector3(1.0, 1.0, BOARD_THICKNESS_SCALE)
	)
	_board_pivot.add_child(board)

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
	_carve = CarveSpray.new()
	_carve.name = "CarveSpray"
	add_child(_carve)

	# Gotas que salen al atravesar la ola: hacia arriba y para los costados.
	_splash = WaterFx.soft_particles(70, 0.9, 0.35)
	_splash.name = "Splash"
	_splash.one_shot = true
	_splash.explosiveness = 0.9
	_splash.emission_sphere_radius = 0.8
	_splash.direction = Vector3(0.0, 1.0, 0.3)
	_splash.spread = 70.0
	_splash.initial_velocity_min = 3.0
	_splash.initial_velocity_max = 8.0
	_splash.position = Vector3(0.0, 1.0, 0.0)
	add_child(_splash)

	# Salpicón en anillo alrededor de la tabla (choques y caídas de alto).
	_ring_splash = WaterFx.soft_particles(60, 0.8, 0.4)
	_ring_splash.name = "RingSplash"
	_ring_splash.one_shot = true
	_ring_splash.explosiveness = 0.95
	_ring_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_ring_splash.emission_ring_axis = Vector3.UP
	_ring_splash.emission_ring_radius = 0.9
	_ring_splash.emission_ring_inner_radius = 0.6
	_ring_splash.emission_ring_height = 0.1
	_ring_splash.direction = Vector3(0.0, 1.0, 0.0)
	_ring_splash.spread = 55.0
	_ring_splash.initial_velocity_min = 3.0
	_ring_splash.initial_velocity_max = 6.5
	_ring_splash.position = Vector3(0.0, 0.15, 0.0)
	add_child(_ring_splash)


## Atravesó una ola que rompía: chapuzón y animación.
## Dónde está la cara del personaje (para saber si atravesó una ola).
func face_position() -> Vector3:
	if _body:
		return _body.face_position()
	return global_position + Vector3.UP * BODY_HEIGHT * 0.9


## Salpicón en anillo (fuerza ~0.5..1.6: más gotas y más alto).
func _ring_burst(strength: float) -> void:
	_ring_splash.amount = clampi(int(40 * strength), 20, 80)
	_ring_splash.initial_velocity_max = 4.0 + 3.0 * strength
	_ring_splash.restart()
	WaterFx.emit(_ring_splash, true)


## La cortina de agua del derrape (para saber a quién tira).
func drift_spray() -> DriftSpray:
	return _spray


func _on_wave_punched() -> void:
	duck_time = DUCK_DURATION
	_splash.restart()
	WaterFx.emit(_splash, true)


## Pose del personaje (transform del BodyPivot) para cada etapa.
static func body_pose(stage: Rider.RecoveryStage) -> Transform3D:
	match stage:
		Rider.RecoveryStage.IN_WATER:
			# En el agua al costado de la tabla, casi parado y hundido hasta el
			# pecho (así se ven la cabeza y los brazos agitándose).
			var b := Basis(Vector3.FORWARD, 0.25) * Basis(Vector3.RIGHT, -0.35)
			return Transform3D(b, Vector3(1.0, -BODY_HEIGHT * 0.54, 0.3))
		Rider.RecoveryStage.PRONE:
			# Acostado boca abajo sobre la tabla, con la cabeza hacia adelante,
			# bien atrás en la tabla y con el pecho apenas levantado.
			var b := Basis(Vector3.RIGHT, -PI / 2.0 + 0.1)
			return Transform3D(b, Vector3(0.0, BOARD_TOP + BODY_RADIUS, BODY_HEIGHT * 0.5 + PRONE_BACK))
		_:
			return Transform3D(Basis.IDENTITY, Vector3(0.0, BOARD_TOP, 0.0))


## Revolcón al caerse: da una vuelta entera hacia adelante mientras sale
## despedido (t = 0..1 del vuelo), frenando al llegar al agua.
static func tumble(t: float) -> Basis:
	# Gira rápido al principio y llega acostado de espaldas (se termina de
	# acomodar con la pose de "en el agua").
	var k := clampf(t, 0.0, 1.0)
	var spin := (1.0 - pow(1.0 - k, 2.5)) * (TAU + PI * 0.5)
	return Basis(Vector3.RIGHT, -spin) * Basis(Vector3.RIGHT, PI * 0.5 * k * k)


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
	var from_water := _last_stage == Rider.RecoveryStage.IN_WATER
	_last_stage = stage
	_climbing = stage == Rider.RecoveryStage.PRONE and from_water
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
		Rider.RecoveryStage.IN_WATER:  # Sale volando de la tabla con un revolcón.
			_pose_duration = TUMBLE_TIME
			_pose_arc = 1.1
		Rider.RecoveryStage.PRONE:
			if _climbing:  # Se trepa a la tabla.
				_pose_duration = rider.stats.climb_time
				_pose_arc = 0.55
			else:  # Modo libre: frena y se acuesta a remar.
				_pose_duration = 0.4
				_pose_arc = 0.2
		_:  # Se para: desde acostado, empuja con las manos y sube las piernas.
			var from_prone := _pose_from.basis.get_euler().x < -0.8
			_pose_duration = POP_UP_PRONE_TIME if from_prone else 0.3
			_pose_arc = 0.2 if from_prone else 0.35


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
	# El derrape ya no pone la tabla de costado: solo frena (ver state_drifting).
	_drift_yaw = lerpf(_drift_yaw, 0.0, 1.0 - exp(-12.0 * delta))
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
	if stage == Rider.RecoveryStage.IN_WATER and _pose_t < 1.0:
		xf.basis = tumble(_pose_t) * xf.basis
	xf.origin += _idle_offset(stage)
	# Cargando el salto: se agacha e inclina hacia adelante.
	var charge := rider.jump_charge
	xf.basis = xf.basis * Basis(Vector3.RIGHT, -0.35 * charge)
	# Truco en el aire: cada vuelta es uno distinto (todos duran lo mismo).
	var board := Transform3D(Basis(_board_from.slerp(_board_to, t)), Vector3.ZERO)
	var trick := _trick_transforms(rider.current_trick(), rider.current_trick_phase())
	_body_pivot.transform = trick[2] * trick[3] * Transform3D(Basis.IDENTITY, trick[1]) * xf
	_board_pivot.transform = trick[2] * board * trick[0]
	_update_particles(delta)
	_update_avatar_anim(delta)

	# "Golpe" de cada pulsación: la pastilla se aplasta un poco.
	_punch = move_toward(_punch, 0.0, delta * 5.0)
	var squash := maxf(_punch * 0.15, rider.jump_charge * 0.3)
	_body.scale = (
		Vector3(1.0 + squash * 1.1, 1.0 - squash, 1.0 + squash * 1.1) * AVATAR_SCALE
	)


## Altura del centro del cuerpo (sobre el que gira en las vueltas).
const FLIP_CENTER := 0.9
## En el giro de cabeza, cuánto más abajo va el eje (con los brazos estirados
## el cuerpo se encoge un poco y si no, la cabeza quedaría flotando).
const HEADSPIN_DROP := -0.15
## Giro de cabeza: parte del truco que dura la entrada (y la salida) en rueda,
## y cuánto sube en arco mientras se da vuelta (m).
const HEADSPIN_IN := 0.3
const HEADSPIN_ARC := 0.45
## Pose del cuerpo en cada truco que no es la de siempre (agarrar la tabla).
## "air" con vertical_speed alto = brazos estirados hacia arriba.
const TRICK_ANIMS := {
	Rider.Trick.HELICOPTER: &"air",
	Rider.Trick.OVERBOARD: &"air",
	Rider.Trick.HEADSPIN: &"hands_down",
	Rider.Trick.WINDMILL: &"pommel",
	Rider.Trick.SUPERMAN: &"superman",
}
## Altura del pecho (m): sobre él gira el cuerpo en el molino y el superman.
const CHEST_HEIGHT := 0.78
## Molino: cuánto se acuesta de costado (rad) y cuánto sube el cuerpo (m).
const WINDMILL_ROLL := -PI * 0.5
const WINDMILL_RAISE := 0.0
## Superman: cuánto sube y se corre hacia atrás el cuerpo, cuánto gira sobre
## su largo para quedar boca abajo, y dónde queda la tabla agarrada (m).
const SUPERMAN_UP := 0.5
const SUPERMAN_BACK := 0.45
const SUPERMAN_TWIST := -PI * 0.5
const SUPERMAN_BOARD_UP := 1.55
const SUPERMAN_BOARD_FWD := -1.35


## Giro alrededor de un eje horizontal a la altura `center` (por defecto, el
## centro del cuerpo).
static func _about_center(b: Basis, center: float = FLIP_CENTER) -> Transform3D:
	var c := Vector3(0.0, center, 0.0)
	return Transform3D(Basis.IDENTITY, c) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -c)


## Entra suave al principio y sale suave al final (0 -> 1 -> 0) para las poses
## que se sostienen (superman, molino).
static func _hold_curve(p: float, edge: float = 0.25) -> float:
	return smoothstep(0.0, edge, p) * (1.0 - smoothstep(1.0 - edge, 1.0, p))


## Cómo se mueven la tabla y el cuerpo en el truco `kind`, a `p` (0..1) del
## truco. Devuelve [giro de la tabla, subida del cuerpo, giro de todo, giro
## solo del cuerpo]. Al terminar (p = 1) todo vuelve a su lugar.
func _trick_transforms(kind: int, p: float) -> Array:
	var spin := Transform3D.IDENTITY
	var lift := Vector3.ZERO
	var whole := Transform3D.IDENTITY
	var body := Transform3D.IDENTITY
	var a := p * TAU
	var hop := sin(p * PI)
	match kind:
		Rider.Trick.SPIN:
			# La tabla gira bajo los pies.
			spin = Transform3D(Basis(Vector3.UP, -a), Vector3.ZERO)
		Rider.Trick.KICKFLIP:
			# La tabla da una vuelta sobre su largo, justo debajo de los pies: el
			# cuerpo sube y la tabla baja un poco cuando está de canto (no lo
			# atraviesa y no se pierde de vista).
			spin = Transform3D(Basis(Vector3.BACK, a), Vector3(0.0, -0.22 * absf(sin(a)), 0.0))
			lift = Vector3(0.0, 0.42 * hop, 0.0)
		Rider.Trick.TRE_FLIP:
			# Gira y da la vuelta sobre su largo a la vez.
			spin = Transform3D(
				Basis(Vector3.UP, -a) * Basis(Vector3.BACK, a), Vector3(0.0, -0.22 * absf(sin(a)), 0.0)
			)
			lift = Vector3(0.0, 0.42 * hop, 0.0)
		Rider.Trick.VARIAL:
			# El cuerpo gira para un lado y la tabla para el otro.
			body = Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
			spin = Transform3D(Basis(Vector3.UP, -a), Vector3.ZERO)
			lift = Vector3(0.0, 0.3 * hop, 0.0)
		Rider.Trick.HELICOPTER:
			# Dos vueltas enteras en el aire, con los brazos abiertos.
			whole = Transform3D(Basis(Vector3.UP, -2.0 * a), Vector3.ZERO)
		Rider.Trick.BARREL_ROLL:
			# Vuelta de costado (como un tonel), con la tabla pegada a los pies.
			whole = _about_center(Basis(Vector3.FORWARD, a))
		Rider.Trick.SPIN_FLIP:
			# Da un giro entero en el aire mientras la tabla da dos vueltas sobre
			# su largo debajo de los pies.
			whole = Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
			spin = Transform3D(Basis(Vector3.BACK, 2.0 * a), Vector3(0.0, -0.22 * absf(sin(2.0 * a)), 0.0))
			lift = Vector3(0.0, 0.42 * hop, 0.0)
		Rider.Trick.OVERBOARD:
			# Se suelta de la tabla: sube con los brazos abiertos mientras la
			# tabla da dos vueltas sobre su largo debajo, y vuelve a caer en ella.
			var e := _hold_curve(p, 0.3)
			lift = Vector3(0.0, 0.85 * e, 0.0)
			spin = Transform3D(Basis(Vector3.BACK, 2.0 * a), Vector3(0.0, -0.15 * e, 0.0))
		Rider.Trick.HEADSPIN:
			# Se tira de costado como una rueda (sube en arco mientras se da
			# vuelta), apoya la cabeza y las manos en la tabla y gira de cabeza con
			# la tabla agarrada; después sigue la rueda en arco hasta caer de pie
			# (completa la vuelta, sin girar en el lugar).
			var go_in := smoothstep(0.0, HEADSPIN_IN, p)
			var go_out := smoothstep(1.0 - HEADSPIN_IN, 1.0, p)
			var flip := PI * (go_in + go_out)
			# Arco: sube mientras da vuelta (entrada y salida), no gira en el lugar.
			var arc := HEADSPIN_ARC * (sin(go_in * PI) + sin(go_out * PI))
			var twirl := 2.0 * TAU * smoothstep(HEADSPIN_IN * 0.8, 1.0 - HEADSPIN_IN * 0.8, p)
			# Da vuelta alrededor de la mitad de su altura: queda con la coronilla
			# apoyada sobre la tabla.
			var mid := (BODY_HEIGHT + BOARD_TOP) * 0.5 - HEADSPIN_DROP
			body = Transform3D(Basis(Vector3.UP, twirl), Vector3(0.0, arc, 0.0)) \
				* _about_center(Basis(Vector3.FORWARD, flip), mid)
			spin = Transform3D(Basis(Vector3.UP, twirl), Vector3.ZERO)
		Rider.Trick.WINDMILL:
			# Molino: apoya las manos en el medio de la tabla con el cuerpo
			# acostado de costado, y las piernas (abiertas, pateando) dan vueltas
			# alrededor. Para volver, las piernas bajan de un envión en arco y
			# cae parado.
			var e := _hold_curve(p, 0.3)
			var around := 2.0 * TAU * smoothstep(0.15, 0.85, p)
			# Al entrar y salir sube un poco (envión con las piernas).
			var swing := 0.35 * sin(smoothstep(0.0, 0.3, p) * PI) + 0.45 * sin(smoothstep(0.7, 1.0, p) * PI)
			body = Transform3D(Basis(Vector3.UP, around), Vector3(0.0, WINDMILL_RAISE * e + swing, 0.0)) \
				* _about_center(Basis(Vector3.FORWARD, WINDMILL_ROLL * e), CHEST_HEIGHT)
		Rider.Trick.BACKFLIP:
			# Vuelta mortal hacia atrás, con la tabla pegada a los pies.
			whole = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3 * hop, 0.0)) * _about_center(Basis(Vector3.RIGHT, a))
		Rider.Trick.SUPERMAN:
			# Superman, hacia adelante: tira la tabla hacia adelante, se agarra
			# de la cola y vuela estirado detrás, boca abajo; después tira de la
			# tabla hacia atrás para volver a ponerla bajo los pies mientras se
			# para.
			var board_out := smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.68, 0.95, p))
			var fly := smoothstep(0.1, 0.35, p) * (1.0 - smoothstep(0.65, 0.98, p))
			body = Transform3D(Basis.IDENTITY, Vector3(0.0, SUPERMAN_UP * fly, SUPERMAN_BACK * fly)) \
				* _about_center(Basis(Vector3.RIGHT, -PI * 0.5 * fly) * Basis(Vector3.UP, SUPERMAN_TWIST * fly), CHEST_HEIGHT)
			spin = Transform3D(Basis.IDENTITY, Vector3(0.0, SUPERMAN_BOARD_UP * board_out, SUPERMAN_BOARD_FWD * board_out))
	return [spin, lift, whole, body]


## Hacia dónde mirar: al rival más cercano (si está cerca y no atrás del
## todo), o un poco hacia la curva.
func _look_target() -> float:
	var best := 7.0
	var target := -rider.steer_amount * 0.3
	for other in get_tree().get_nodes_in_group("riders"):
		if other == rider or not other is Node3D:
			continue
		var rel := _body.to_local((other as Node3D).global_position)
		var dist := Vector2(rel.x, rel.z).length() * AVATAR_SCALE
		var ang := atan2(rel.x, rel.z)
		if dist < best and absf(ang) < 2.0:
			best = dist
			target = clampf(ang, -1.0, 1.0)
	return target


## Elige la animación del personaje según lo que está haciendo el Rider.
func _update_avatar_anim(delta: float) -> void:
	_stage_time += delta
	var was_ducking := duck_time > 0.0
	duck_time = maxf(duck_time - delta, 0.0)
	# Terminó de atravesar la ola: se seca la cara.
	if was_ducking and duck_time <= 0.0 and rider.recovery_stage == Rider.RecoveryStage.STANDING:
		_body.shake_off()
	var stage := rider.recovery_stage
	var a: StringName = &"ride"
	_body.effort = clampf(_punch * 1.5, 0.0, 1.0)
	_body.charge = rider.jump_charge
	_body.steer = rider.steer_amount
	_body.speed = clampf(rider.speed / maxf(rider.stats.max_speed, 0.1), 0.0, 1.2)
	_body.vertical_speed = rider.vertical_speed
	_body.turbo = rider.turbo_active
	_body.look_yaw = lerpf(_body.look_yaw, _look_target(), 1.0 - exp(-6.0 * delta))
	match stage:
		Rider.RecoveryStage.IN_WATER:
			a = &"flail" if _stage_time < 1.4 or _punch > 0.3 else &"tread"
		Rider.RecoveryStage.PRONE:
			a = &"climb" if _climbing and _stage_time < rider.stats.climb_time else &"paddle"
			# Rema solo si empuja (quieto o dejándose llevar, los brazos
			# descansan); cuanto más rápido va, brazadas más rápidas y amplias.
			var push := 1.0
			if rider.input != null and rider.free_ride:
				push = clampf(rider.input.throttle, 0.0, 1.0)
			var pace := clampf(rider.speed / 2.7, 0.0, 1.0)
			_body.effort = maxf(_body.effort, push * (0.3 + 0.7 * pace))
		_:
			if _stage_time < _pose_duration and _pose_t < 1.0:
				a = &"pop_up"
				_body.pop_time = _pose_duration
			elif duck_time > 0.0:
				a = &"duck"
			elif not rider.grounded:
				a = &"trick" if rider.trick_angle > 0.0 else &"air"
				var trick_anim: StringName = TRICK_ANIMS.get(rider.current_trick(), &"")
				if trick_anim != &"":
					a = trick_anim
					# "air" con velocidad hacia arriba = brazos estirados.
					_body.vertical_speed = 12.0
			elif rider.drift_side != 0:
				a = &"drift"
				_body.drift_side = rider.drift_side
			elif rider.race_finished:
				a = &"celebrate"
	# Despegó (salto o la ola lo lanzó) / aterrizó: golpes de la animación.
	var in_air := a == &"air" or a == &"trick"
	if in_air and not _was_in_air:
		_body.pop()
	elif not in_air and _was_in_air and stage == Rider.RecoveryStage.STANDING:
		_body.land(clampf(absf(_last_air_vy) / 9.0, 0.35, 1.0))
	if in_air:
		_last_air_vy = rider.vertical_speed
	_was_in_air = in_air
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

	# Al girar rápido, el canto de la tabla levanta una pared de agua hacia
	# afuera de la curva (más alta cuanto más rápido y más cerrado gira).
	var carve := absf(rider.steer_amount) * rider.speed
	var carving := on_water and drift_side == 0 and rider.speed > 6.0 and carve > 3.0
	if carving:
		var side := -signf(rider.steer_amount)
		_carve.position = Vector3(side * 0.35, 0.05, 0.45)
		_carve.rotation.y = side * deg_to_rad(CARVE_ANGLE)
	_carve.update_spray(1 if carving else 0, clampf((carve - 3.0) / 6.0, 0.0, 1.0), delta)

	# Salpicadura al girar: sale del borde de afuera de la curva.
	var turn := absf(rider.steer_amount) * rider.speed
	var turning := on_water and drift_side == 0 and turn > 3.0
	WaterFx.emit(_wake, turning)
	if turning:
		var outside := -signf(rider.steer_amount)
		_wake.position = Vector3(outside * 0.35, 0.1, 0.8)
		_wake.direction = Vector3(outside * 0.8, 0.7, 0.6).normalized()
		_wake.initial_velocity_max = 2.5 + turn * 0.25
