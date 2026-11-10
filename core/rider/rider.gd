class_name Rider
extends Node3D
## El surfista. Guarda posición, rumbo, velocidad y nitro, y delega el
## comportamiento en la máquina de estados (riding, drifting, airborne, fallen).
## No sabe quién lo controla: pide un RiderInput a su Controller cada frame.
##
## Por ahora se mueve libre sobre el plano (x, z). Cuando exista la isla,
## esto pasa a coordenadas de pista (progress + lateral) con TrackSpace.

signal fell
signal stood_up
signal mash_pressed
signal mash_progress_changed(value: float, stage: RecoveryStage)
signal recovery_stage_changed(stage: RecoveryStage)
signal jumped
signal landed
signal trick_landed(spins: int)
signal trick_failed
signal nitro_changed(value: float, max_value: float)
signal drift_started(side: int)
signal drift_ended
signal drift_hit(victim: Rider)
signal motivation_started
signal popped
signal ring_collected
signal crashed

## En qué punto de la recuperación está: en el agua, acostado sobre la tabla o parado.
enum RecoveryStage { IN_WATER, PRONE, STANDING }

const NITRO_MAX := 1.0

@export var player_index: int = 0
@export var stats: RiderStats
## Nombre que se muestra (J1, J2, Bot...).
@export var display_name: String = "J1"
## true si lo controla una persona (los bots no cuentan para el volumen épico, etc.).
@export var is_human: bool = true

## Rumbo en radianes (rotación alrededor de Y). 0 = mirando hacia -Z.
var heading: float = 0.0
var speed: float = 0.0
var vertical_speed: float = 0.0
## true si está apoyado en el agua (no en el aire).
var grounded: bool = true
## Giro aplicado este frame (-1..1), para que la parte visual se incline.
var steer_amount: float = 0.0
var recovery_stage: RecoveryStage = RecoveryStage.STANDING
var water_normal: Vector3 = Vector3.UP
var nitro: float = 0.0
## Carga del salto (0..1) mientras se mantiene ESPACIO en el agua.
var jump_charge: float = 0.0
## Giro acumulado de la tabla durante un truco (radianes).
var trick_angle: float = 0.0
## Lado del derrape: -1 izquierda, 1 derecha, 0 sin derrapar.
var drift_side: int = 0
## Entrada del frame actual (la leen los estados al entrar).
var input: RiderInput = RiderInput.new()
## Si es true, el Rider ignora los controles (cuenta regresiva, por ejemplo).
var controls_locked: bool = false
## Tiempo que le queda al mini sprint automático (motivación).
var motivation_timer: float = 0.0
## true mientras el turbo está empujando (para efectos visuales).
var turbo_active: bool = false
## true cuando ya cruzó la meta (festeja).
var race_finished: bool = false
## Modo olas: tiempo que queda del A apretado subiendo la ola (para el pop).
var pop_buffer: float = 0.0
## Tiempo desde que una ola lo lanzó (-1 si no fue una ola).
var wave_air_time: float = -1.0
## Si ya hizo el pop en este salto.
var did_pop: bool = false
## Si en este salto se puede hacer truco (en el saltito no: no daría el tiempo).
var can_trick: bool = true
## Handicap (0..1): cuánto ayuda el juego por ir atrás. Lo calcula RaceManager.
var catchup: float = 0.0
var water: Water

var _steer_smoothed: float = 0.0

@onready var controller: BaseController = $Controller
@onready var state_machine: RiderStateMachine = $StateMachine
@onready var visual: RiderVisual = $Visual


func _ready() -> void:
	add_to_group("riders")
	if stats == null:
		stats = RiderStats.new()
	water = get_tree().get_first_node_in_group("water") as Water
	heading = rotation.y
	position.y = water_height()
	visual.setup(self)
	state_machine.setup(self)


func _process(delta: float) -> void:
	# Se actualiza en _process (no en física) para que se vea fluido con
	# cualquier tasa de refresco. Se limita delta para evitar saltos grandes.
	delta = minf(delta, 1.0 / 20.0)
	input = controller.get_input(delta)
	if controls_locked:
		input = RiderInput.new()
	motivation_timer = maxf(0.0, motivation_timer - delta)
	pop_buffer = maxf(0.0, pop_buffer - delta)
	if catchup > 0.0 and not controls_locked:
		add_nitro(stats.catchup_nitro_trickle * catchup * delta)
	if wave_air_time >= 0.0:
		wave_air_time += delta
	turbo_active = false
	if input.debug_fall and not is_fallen():
		fall()
	state_machine.update(delta, input)
	rotation.y = heading


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


func move_forward(delta: float) -> void:
	position += forward() * speed * delta


## Gira con algo de inercia; cuesta más girar a poca velocidad.
func apply_steer(amount: float, delta: float, factor: float = 1.0) -> void:
	_steer_smoothed = move_toward(_steer_smoothed, amount, stats.steer_response * delta)
	steer_amount = _steer_smoothed * factor
	var speed_factor := clampf(0.35 + speed / stats.max_speed, 0.35, 1.0)
	heading -= _steer_smoothed * stats.turn_speed * factor * speed_factor * delta


func reset_steer() -> void:
	_steer_smoothed = 0.0
	steer_amount = 0.0


## Steer suavizado actual (-1..1).
func current_steer() -> float:
	return _steer_smoothed


## Acelera / frena según el acelerador. El turbo (si hay nitro) y la
## motivación suben la velocidad máxima.
func apply_throttle(throttle: float, delta: float, turbo: bool = false) -> void:
	var top := stats.max_speed * speed_mult()
	var target := top * maxf(throttle, 0.0)
	var rate := stats.acceleration
	if motivation_timer > 0.0:
		target = maxf(target, top * stats.motivation_speed_mult)
		rate *= 2.0
	if turbo and nitro > 0.0:
		turbo_active = true
		target = maxf(target, top * stats.turbo_speed_mult)
		rate = stats.acceleration * stats.turbo_accel_mult
		add_nitro(-stats.turbo_drain * delta)
	if speed > target:
		rate = stats.brake_decel if throttle < -0.1 else stats.coast_decel
	speed = move_toward(speed, target, rate * delta)


## Mini sprint automático tras pasar por un círculo o tirar a alguien.
func trigger_motivation() -> void:
	if motivation_timer <= 0.0:
		motivation_started.emit()
	motivation_timer = stats.motivation_time


## Choque (roca, isla): se cae y queda en `safe_position`, fuera del obstáculo.
func crash(safe_position: Vector3) -> void:
	position.x = safe_position.x
	position.z = safe_position.z
	speed = minf(speed, 3.0)
	crashed.emit()
	if not is_fallen():
		fall()


func water_height() -> float:
	if water == null:
		return 0.0
	return water.height_at(position.x, position.z)


## Pega al Rider a la superficie. Devuelve true si la ola lo lanzó al aire:
## pasa cuando la superficie "se cae" más rápido que la gravedad (al pasar la
## cresta con velocidad). Cuanto más rápido sube, más alto sale.
func stick_to_water(delta: float, allow_launch: bool = true) -> bool:
	var h := water_height()
	var ballistic_y := position.y + vertical_speed * delta - 0.5 * stats.gravity * delta * delta
	if allow_launch and vertical_speed > stats.min_launch_speed and ballistic_y > h:
		position.y = ballistic_y
		var boost := stats.wave_launch_boost * jump_mult()
		if turbo_active:
			boost *= stats.turbo_launch_mult
		vertical_speed = (vertical_speed - stats.gravity * delta) * boost
		jump_charge = 0.0
		grounded = false
		wave_air_time = 0.0
		did_pop = false
		can_trick = true
		if pop_buffer > 0.0:
			do_pop()
		return true
	vertical_speed = clampf((h - position.y) / delta, -30.0, 30.0)
	position.y = h
	grounded = true
	if water:
		water_normal = water.normal_at(position.x, position.z)
	return false


## Salta con la fuerza que indica jump_charge (0 = toque, 1 = cargado al máximo).
## En el modo "tocar para saltar" la altura es fija.
func jump() -> void:
	var jump_speed := lerpf(stats.jump_speed_min, stats.jump_speed_max, jump_charge)
	if GameSettings.jump_mode == GameSettings.JumpMode.TAP:
		jump_speed = stats.jump_speed_tap
	vertical_speed = maxf(vertical_speed, 0.0) + jump_speed * jump_mult()
	jump_charge = 0.0
	grounded = false
	can_trick = true
	jumped.emit()


## Modo olas: true en el momento justo para el pop (subiendo una ola grande o
## apenas la ola lo lanzó). El HUD muestra el botón.
func pop_ready() -> bool:
	if GameSettings.jump_style != GameSettings.JumpStyle.WAVES or did_pop or is_fallen():
		return false
	if grounded:
		var on_swell := water != null and water.swell_height_at(position.x, position.z) > 0.8
		return on_swell and vertical_speed > stats.pop_min_climb + 1.0 and pop_buffer <= 0.0
	return wave_air_time >= 0.0 and wave_air_time < stats.pop_window


## Modo olas: saltito en agua plana (no alcanza para un truco).
func hop() -> void:
	vertical_speed = maxf(vertical_speed, 0.0) + stats.hop_speed * jump_mult()
	grounded = false
	wave_air_time = -1.0
	did_pop = false
	can_trick = false
	jumped.emit()


## Modo olas: apretar A en la ola hace salir mucho más alto.
func do_pop() -> void:
	if did_pop:
		return
	did_pop = true
	pop_buffer = 0.0
	vertical_speed = maxf(vertical_speed, 0.0) * stats.pop_mult + stats.pop_extra
	popped.emit()


## Mueve en el aire. Devuelve true cuando toca el agua.
func update_air(delta: float) -> bool:
	vertical_speed -= stats.gravity * delta
	position.y += vertical_speed * delta
	var h := water_height()
	if position.y <= h and vertical_speed <= 0.0:
		position.y = h
		grounded = true
		wave_air_time = -1.0
		landed.emit()
		return true
	return false


## Multiplicador del nitro que se gana por el handicap.
func nitro_gain_mult() -> float:
	return 1.0 + catchup * (stats.catchup_nitro_mult - 1.0)


## Multiplicador de la velocidad máxima por el handicap.
func speed_mult() -> float:
	return 1.0 + catchup * stats.catchup_speed_bonus


## Radianes que le pueden faltar a un truco al caer para que igual cuente (handicap).
func trick_grace() -> float:
	return catchup * stats.catchup_trick_grace


## Multiplicador de la altura de los saltos por el handicap.
func jump_mult() -> float:
	return 1.0 + catchup * stats.catchup_jump_bonus


## Suma nitro. Lo que se gana se multiplica por el handicap (lo que se gasta no).
func add_nitro(amount: float) -> void:
	if amount > 0.0:
		amount *= nitro_gain_mult()
	nitro = clampf(nitro + amount, 0.0, NITRO_MAX)
	nitro_changed.emit(nitro, NITRO_MAX)


func reset_nitro() -> void:
	nitro = 0.0
	nitro_changed.emit(nitro, NITRO_MAX)


func fall() -> void:
	state_machine.transition_to(&"fallen")


func is_fallen() -> bool:
	return state_machine.current_name == &"fallen"


func set_recovery_stage(stage: RecoveryStage) -> void:
	if stage == recovery_stage:
		return
	recovery_stage = stage
	recovery_stage_changed.emit(stage)
