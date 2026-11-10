class_name InputSetup
extends RefCounted
## Registra las acciones de entrada de cada jugador por código.
##
## Cada jugador tiene sus acciones con prefijo: p1_left, p1_right, p1_a, p1_b...
## A sirve para varias cosas según el estado: saltar (mantener = cargar),
## truco (mantener en el aire) y levantarse (spamear). El derrape tiene su propio botón.
##
## Los mandos se asignan por POSICIÓN del botón (abajo, derecha, izquierda, arriba).
## Hay dos distribuciones porque algunos mandos genéricos USB, en el navegador,
## informan los botones en otro orden (ver PadLayout).

const STICK_DEADZONE := 0.2
const BUTTON_DEADZONE := 0.5

## STANDARD: mandos que el navegador reconoce como estándar (Xbox, PlayStation oficial...).
## GENERIC: mandos genéricos tipo PlayStation (DirectInput): △=0, ○=1, ✕=2, □=3.
enum PadLayout { STANDARD, GENERIC }

const LAYOUT_NAMES := ["estándar", "genérico (tipo PlayStation)"]

## Índice de botón para cada posición física, según la distribución.
const PAD_BUTTONS := {
	PadLayout.STANDARD: {
		"bottom": JOY_BUTTON_A,
		"right": JOY_BUTTON_B,
		"left": JOY_BUTTON_X,
		"top": JOY_BUTTON_Y,
		"rb": JOY_BUTTON_RIGHT_SHOULDER,
		"start": JOY_BUTTON_START,
		"select": JOY_BUTTON_BACK,
	},
	PadLayout.GENERIC: {
		"bottom": 2,
		"right": 1,
		"left": 3,
		"top": 0,
		"rb": 5,
		"start": 9,
		"select": 8,
	},
}

## Qué posiciones de botón activan cada acción.
const BUTTON_ROLES := {
	"a": ["bottom"],
	"b": ["right"],
	"drift": ["left", "rb"],
	"debug_fall": ["top"],
	"start": ["start"],
	"select": ["select"],
}

## Teclado según cuántos juegan. Con 1 jugador, J1 usa todo; con 2, se reparte.
const KEYBOARD_1P := {
	0: {
		"left": [KEY_A, KEY_LEFT],
		"right": [KEY_D, KEY_RIGHT],
		"up": [KEY_W, KEY_UP],
		"down": [KEY_S, KEY_DOWN],
		"a": [KEY_SPACE, KEY_J],
		"drift": [KEY_SHIFT, KEY_L],
		"b": [KEY_E, KEY_K],
		"debug_fall": [KEY_F],
	},
}
const KEYBOARD_2P := {
	0: {
		"left": [KEY_A],
		"right": [KEY_D],
		"up": [KEY_W],
		"down": [KEY_S],
		"a": [KEY_SPACE],
		"drift": [KEY_SHIFT],
		"b": [KEY_E],
		"debug_fall": [KEY_F],
	},
	1: {
		"left": [KEY_LEFT],
		"right": [KEY_RIGHT],
		"up": [KEY_UP],
		"down": [KEY_DOWN],
		"a": [KEY_ENTER, KEY_KP_0],
		"drift": [KEY_PERIOD, KEY_KP_1],
		"b": [KEY_SLASH, KEY_KP_2],
		"debug_fall": [KEY_BACKSPACE],
	},
}

static var _layouts: Dictionary = {}


static func prefix(player_index: int) -> String:
	return "p%d_" % (player_index + 1)


## Crea las acciones del jugador si todavía no existen. Se puede llamar varias veces.
static func ensure_player_actions(player_index: int) -> void:
	var p := prefix(player_index)
	if InputMap.has_action(p + "a"):
		return

	for action in ["left", "right", "up", "down"]:
		InputMap.add_action(p + action, STICK_DEADZONE)
	for action in BUTTON_ROLES:
		InputMap.add_action(p + action, BUTTON_DEADZONE)

	# Mando: el mando N se asigna al jugador N.
	var device := player_index
	_joy_axis(p + "left", device, JOY_AXIS_LEFT_X, -1.0)
	_joy_axis(p + "right", device, JOY_AXIS_LEFT_X, 1.0)
	_joy_axis(p + "up", device, JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis(p + "down", device, JOY_AXIS_LEFT_Y, 1.0)
	_joy_button(p + "left", device, JOY_BUTTON_DPAD_LEFT)
	_joy_button(p + "right", device, JOY_BUTTON_DPAD_RIGHT)
	_joy_button(p + "up", device, JOY_BUTTON_DPAD_UP)
	_joy_button(p + "down", device, JOY_BUTTON_DPAD_DOWN)
	set_pad_layout(player_index, PadLayout.STANDARD)

	if player_index == 0:
		apply_keyboard_layout(1)


## Reparte el teclado según la cantidad de jugadores (borra y vuelve a poner las teclas).
static func apply_keyboard_layout(player_count: int) -> void:
	var layout: Dictionary = KEYBOARD_2P if player_count >= 2 else KEYBOARD_1P
	for player in [0, 1]:
		var p := prefix(player)
		if not InputMap.has_action(p + "a"):
			continue
		for action in InputMap.get_actions():
			if not String(action).begins_with(p):
				continue
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					InputMap.action_erase_event(action, ev)
		if layout.has(player):
			for action in layout[player]:
				for key in layout[player][action]:
					_key(p + action, key)


static func get_pad_layout(player_index: int) -> PadLayout:
	return _layouts.get(player_index, PadLayout.STANDARD)


## Cambia la distribución de botones del mando del jugador.
static func set_pad_layout(player_index: int, layout: PadLayout) -> void:
	_layouts[player_index] = layout
	var p := prefix(player_index)
	var device := player_index
	for action in BUTTON_ROLES:
		var action_name: String = p + action
		# Quitar los botones de mando (no las flechas de la cruceta, que no están acá).
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(action_name, ev)
		for role in BUTTON_ROLES[action]:
			_joy_button(action_name, device, PAD_BUTTONS[layout][role])


## Adivina la distribución del mando. En el navegador, los mandos que no se
## reconocen como "estándar" suelen ser genéricos tipo PlayStation.
static func detect_pad_layout(device: int) -> PadLayout:
	var joy_name := Input.get_joy_name(device).to_upper()
	if joy_name.is_empty() or not OS.has_feature("web"):
		return PadLayout.STANDARD
	for known in ["STANDARD GAMEPAD", "XINPUT", "XBOX", "X-BOX"]:
		if joy_name.contains(known):
			return PadLayout.STANDARD
	return PadLayout.GENERIC


static func _key(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


static func _joy_button(action: StringName, device: int, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button as JoyButton
	InputMap.action_add_event(action, ev)


static func _joy_axis(action: StringName, device: int, axis: JoyAxis, direction: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
