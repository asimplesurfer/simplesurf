class_name Rider
extends Node3D
## El surfista. Guarda posición, rumbo y velocidad, y delega el comportamiento
## en la máquina de estados (riding, fallen...). No sabe quién lo controla:
## pide un RiderInput a su Controller cada frame.
##
## Por ahora se mueve libre sobre el plano (x, z). Cuando exista la isla,
## esto pasa a coordenadas de pista (progress + lateral) con TrackSpace.

signal fell
signal stood_up
signal mash_pressed
signal mash_progress_changed(value: float, stage: RecoveryStage)
signal recovery_stage_changed(stage: RecoveryStage)

## En qué punto de la recuperación está: en el agua, acostado sobre la tabla o parado.
enum RecoveryStage { IN_WATER, PRONE, STANDING }

@export var player_index: int = 0
@export var stats: RiderStats

## Rumbo en radianes (rotación alrededor de Y). 0 = mirando hacia -Z.
var heading: float = 0.0
var speed: float = 0.0
## Giro aplicado este frame (-1..1), para que la parte visual se incline.
var steer_amount: float = 0.0
var recovery_stage: RecoveryStage = RecoveryStage.STANDING
var water_normal: Vector3 = Vector3.UP
var water: Water

@onready var controller: BaseController = $Controller
@onready var state_machine: RiderStateMachine = $StateMachine
@onready var visual: RiderVisual = $Visual


func _ready() -> void:
	if stats == null:
		stats = RiderStats.new()
	water = get_tree().get_first_node_in_group("water") as Water
	heading = rotation.y
	_follow_water()
	visual.setup(self)
	state_machine.setup(self)


func _process(delta: float) -> void:
	# Se actualiza en _process (no en física) para que se vea fluido con
	# cualquier tasa de refresco. Se limita delta para evitar saltos grandes.
	delta = minf(delta, 1.0 / 20.0)
	var input := controller.get_input(delta)
	if input.debug_fall and not is_fallen():
		fall()
	state_machine.update(delta, input)
	_follow_water()
	rotation.y = heading


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func move_forward(delta: float) -> void:
	position += forward() * speed * delta


func steer(amount: float, delta: float, factor: float = 1.0) -> void:
	steer_amount = amount * factor
	heading -= amount * stats.turn_speed * factor * delta


func fall() -> void:
	state_machine.transition_to(&"fallen")


func is_fallen() -> bool:
	return state_machine.current_name == &"fallen"


func set_recovery_stage(stage: RecoveryStage) -> void:
	if stage == recovery_stage:
		return
	recovery_stage = stage
	recovery_stage_changed.emit(stage)


func _follow_water() -> void:
	if water == null:
		position.y = 0.0
		water_normal = Vector3.UP
		return
	position.y = water.height_at(position.x, position.z)
	water_normal = water.normal_at(position.x, position.z)
