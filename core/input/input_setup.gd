class_name InputSetup
extends RefCounted
## Registra las acciones de entrada de cada jugador por código.
##
## Cada jugador tiene sus acciones con prefijo: p1_left, p1_right, p1_a, p1_b...
## A sirve para varias cosas según el estado: saltar, truco (mantener en el aire)
## y levantarse (spamear). El derrape tiene su propio botón.

const STICK_DEADZONE := 0.2
const BUTTON_DEADZONE := 0.5


static func prefix(player_index: int) -> String:
	return "p%d_" % (player_index + 1)


## Crea las acciones del jugador si todavía no existen. Se puede llamar varias veces.
static func ensure_player_actions(player_index: int) -> void:
	var p := prefix(player_index)
	if InputMap.has_action(p + "a"):
		return

	_add(p + "left", STICK_DEADZONE)
	_add(p + "right", STICK_DEADZONE)
	_add(p + "up", STICK_DEADZONE)
	_add(p + "down", STICK_DEADZONE)
	_add(p + "a", BUTTON_DEADZONE)
	_add(p + "drift", BUTTON_DEADZONE)
	_add(p + "b", BUTTON_DEADZONE)
	_add(p + "debug_fall", BUTTON_DEADZONE)

	# Mando: el mando N se asigna al jugador N.
	var device := player_index
	_joy_axis(p + "left", device, JOY_AXIS_LEFT_X, -1.0)
	_joy_axis(p + "right", device, JOY_AXIS_LEFT_X, 1.0)
	_joy_button(p + "left", device, JOY_BUTTON_DPAD_LEFT)
	_joy_button(p + "right", device, JOY_BUTTON_DPAD_RIGHT)
	_joy_axis(p + "up", device, JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis(p + "down", device, JOY_AXIS_LEFT_Y, 1.0)
	_joy_button(p + "up", device, JOY_BUTTON_DPAD_UP)
	_joy_button(p + "down", device, JOY_BUTTON_DPAD_DOWN)
	_joy_button(p + "a", device, JOY_BUTTON_A)
	_joy_button(p + "drift", device, JOY_BUTTON_X)
	_joy_button(p + "drift", device, JOY_BUTTON_RIGHT_SHOULDER)
	_joy_button(p + "b", device, JOY_BUTTON_B)
	_joy_button(p + "debug_fall", device, JOY_BUTTON_Y)

	# Teclado: por ahora solo el jugador 1.
	if player_index == 0:
		_key(p + "left", KEY_A)
		_key(p + "left", KEY_LEFT)
		_key(p + "right", KEY_D)
		_key(p + "right", KEY_RIGHT)
		_key(p + "up", KEY_W)
		_key(p + "up", KEY_UP)
		_key(p + "down", KEY_S)
		_key(p + "down", KEY_DOWN)
		_key(p + "a", KEY_SPACE)
		_key(p + "a", KEY_J)
		_key(p + "drift", KEY_SHIFT)
		_key(p + "drift", KEY_L)
		_key(p + "b", KEY_K)
		_key(p + "debug_fall", KEY_R)


static func _add(action: StringName, deadzone: float) -> void:
	InputMap.add_action(action, deadzone)


static func _key(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


static func _joy_button(action: StringName, device: int, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _joy_axis(action: StringName, device: int, axis: JoyAxis, direction: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
