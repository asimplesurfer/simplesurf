extends "res://tests/test_base.gd"
## Regresión: los eventos del mando deben usar el ID real del dispositivo,
## aunque sea distinto del índice del jugador.

func run() -> void:
	InputSetup.ensure_player_actions(0)
	InputSetup.set_player_device(0, 37)
	_check(_has_joy_axis(&"p1_left", 37, JOY_AXIS_LEFT_X, -1.0), "el eje izquierdo se registra con el ID real del mando")
	_check(_has_joy_axis(&"p1_right", 37, JOY_AXIS_LEFT_X, 1.0), "el eje derecho se registra con el ID real del mando")
	_check(_has_joy_button(&"p1_a", 37, JOY_BUTTON_A), "el botón A usa el ID real del mando")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.GENERIC)
	_check(_has_joy_button(&"p1_a", 37, 2), "el cambio de distribución conserva el ID real")
	InputSetup.set_pad_layout(0, InputSetup.PadLayout.STANDARD)
	InputSetup.refresh_player_devices()


func _has_joy_axis(action: StringName, device: int, axis: JoyAxis, direction: float) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.device == device and ev.axis == axis and is_equal_approx(ev.axis_value, direction):
			return true
	return false


func _has_joy_button(action: StringName, device: int, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.device == device and ev.button_index == button:
			return true
	return false
