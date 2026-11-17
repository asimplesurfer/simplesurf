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
	_test_keyboard_layouts()


## El teclado es de una sola persona (J1) con todas las teclas; los demás
## juegan con mando (sin mandos conectados en los tests, se prueba _apply_keys
## con la cantidad de mandos a mano).
func _test_keyboard_layouts() -> void:
	InputSetup.ensure_player_actions(1)
	InputSetup.apply_player_count(2)
	InputSetup._apply_keys(0)
	_check(_has_key(&"p1_left", KEY_A) and _has_key(&"p1_left", KEY_LEFT), "2 jugadores: J1 usa todo el teclado")
	_check(not _has_key(&"p2_left", KEY_LEFT) and not _has_key(&"p2_a", KEY_ENTER), "el teclado no se comparte: J2 no usa teclas")
	_check(InputSetup.keyboard_and_pad_mode(1), "2 jugadores con 1 mando: J1 teclado y J2 mando")
	_check(not InputSetup.keyboard_and_pad_mode(2), "2 jugadores con 2 mandos: uno cada uno")
	InputSetup.apply_player_count(1)
	_check(not InputSetup.keyboard_and_pad_mode(1), "1 jugador con 1 mando: J1 usa mando y teclado")
	_check(_has_key(&"p1_left", KEY_LEFT), "1 jugador: J1 usa también las flechas")


func _has_key(action: StringName, keycode: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.physical_keycode == keycode:
			return true
	return false


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
