class_name PlayerController
extends BaseController
## Lee mando y teclado del jugador `player_index` (acciones p1_, p2_...).

@export var player_index: int = 0

## true si lo último que tocó el jugador fue un mando (para mostrar "A" o "ESPACIO").
var using_joypad: bool = false

var _prefix: String = ""
var _pending_mash: int = 0
var _pending_debug_fall: bool = false


func _ready() -> void:
	var rider := get_parent() as Rider
	if rider:
		player_index = rider.player_index
	InputSetup.ensure_player_actions(player_index)
	_prefix = InputSetup.prefix(player_index)


func _unhandled_input(event: InputEvent) -> void:
	# Las pulsaciones se cuentan por evento para no perder ninguna al spamear rápido.
	if event.is_action_pressed(_prefix + "a"):
		_pending_mash += 1
	if event.is_action_pressed(_prefix + "debug_fall"):
		_pending_debug_fall = true

	if event is InputEventKey:
		using_joypad = false
	elif event is InputEventJoypadButton:
		using_joypad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		using_joypad = true


func get_input(_delta: float) -> RiderInput:
	var input := RiderInput.new()
	input.steer = Input.get_axis(_prefix + "left", _prefix + "right")
	var a_held := Input.is_action_pressed(_prefix + "a")
	input.drift = a_held
	input.trick = a_held
	input.turbo = Input.is_action_pressed(_prefix + "b")
	input.mash_presses = _pending_mash
	input.debug_fall = _pending_debug_fall
	_pending_mash = 0
	_pending_debug_fall = false
	return input
