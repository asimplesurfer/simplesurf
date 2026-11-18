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
		"lb": JOY_BUTTON_LEFT_SHOULDER,
		# El gatillo izquierdo en los mandos estándar es un eje (se agrega aparte).
		"lt": -1,
		"start": JOY_BUTTON_START,
		"select": JOY_BUTTON_BACK,
	},
	PadLayout.GENERIC: {
		"bottom": 2,
		"right": 1,
		"left": 3,
		"top": 0,
		"rb": 5,
		"lb": 4,
		"lt": 6,
		"start": 9,
		"select": 8,
	},
}

## Qué posiciones de botón activan cada acción.
const BUTTON_ROLES := {
	"a": ["bottom"],
	"b": ["right"],
	"drift": ["left", "rb"],
	"look_back": ["lt"],
	"start": ["start"],
	"select": ["select"],
	# Modo libre: subir / bajar las olas y prender / apagar la tormenta.
	"waves_up": ["rb"],
	"waves_down": ["lb"],
	"storm": ["select"],
}

## Teclado: lo usa una sola persona (J1), con todas las teclas. Los demás
## juegan con mando.
const KEYBOARD_KEYS := {
	"left": [KEY_A, KEY_LEFT],
	"right": [KEY_D, KEY_RIGHT],
	"up": [KEY_W, KEY_UP],
	"down": [KEY_S, KEY_DOWN],
	"a": [KEY_SPACE, KEY_J],
	"drift": [KEY_S, KEY_DOWN],
	"b": [KEY_E],
	"look_back": [KEY_Q],
	"waves_up": [KEY_X],
	"waves_down": [KEY_Z],
	"storm": [KEY_T],
}

## Hasta cuántas personas pueden jugar a la vez.
const MAX_PLAYERS := 4
## "Dispositivo" del teclado (los mandos son 0, 1, 2...).
const KEYBOARD := -2

static var _layouts: Dictionary = {}
static var _devices: Dictionary = {}
## Quién juega con qué, elegido en el menú (cada uno se une con su teclado o
## mando): jugador -> dispositivo (KEYBOARD o el id del mando). Vacío = se
## reparte solo (por orden de conexión, como antes).
static var _assigned: Dictionary = {}
## Cuántas personas juegan (lo fija apply_player_count).
static var _player_count: int = 1


static func prefix(player_index: int) -> String:
	return "p%d_" % (player_index + 1)


## Crea las acciones del jugador si todavía no existen. Se puede llamar varias veces.
static func ensure_player_actions(player_index: int) -> void:
	var p := prefix(player_index)
	# No salir temprano: el menú puede haber creado las acciones antes de que
	# conectaran el mando. Aseguramos cada acción y refrescamos el dispositivo.
	for action in ["left", "right", "up", "down"]:
		if not InputMap.has_action(p + action):
			InputMap.add_action(p + action, STICK_DEADZONE)
	for action in BUTTON_ROLES:
		if not InputMap.has_action(p + action):
			InputMap.add_action(p + action, BUTTON_DEADZONE)

	refresh_player_devices()


## Asigna los mandos conectados por orden de conexión, no suponiendo que el ID
## del dispositivo coincida con el número de jugador. En navegador/macOS los
## IDs pueden no ser 0, 1 aunque haya uno o dos mandos.
##
## Con 2 jugadores y un solo mando: J1 juega con el teclado (entero) y J2 con
## el mando. Así se puede jugar de a dos en la misma compu con teclado + mando.
static func refresh_player_devices() -> void:
	if not _assigned.is_empty():
		_apply_assigned()
		return
	var connected: Array = Input.get_connected_joypads()
	connected.sort()
	var keyboard_and_pad := keyboard_and_pad_mode(connected.size())
	for player in MAX_PLAYERS:
		var device := int(connected[player]) if player < connected.size() else -1
		if keyboard_and_pad and player < 2:
			device = int(connected[0]) if player == 1 else -1
		set_player_device(player, device)
	_apply_keys(connected.size())


## Fija quién juega con qué (lo elige el menú): jugador -> KEYBOARD o el id de
## un mando. El teclado es de una sola persona (con todas las teclas).
static func assign_devices(assignment: Dictionary) -> void:
	_assigned = assignment.duplicate()
	for player in _assigned:
		var device: int = _assigned[player]
		if device >= 0 and not _layouts.has(player):
			_layouts[player] = detect_pad_layout(device)
	_apply_assigned()


## Vuelve a repartir solo (por orden de conexión).
static func clear_assignments() -> void:
	_assigned.clear()
	refresh_player_devices()


static func has_assignments() -> bool:
	return not _assigned.is_empty()


## Dispositivo con el que se unió el jugador en el menú (-1 si ninguno).
static func assigned_device(player_index: int) -> int:
	return int(_assigned.get(player_index, -1))


static func _apply_assigned() -> void:
	for player in MAX_PLAYERS:
		var device := assigned_device(player)
		if InputMap.has_action(prefix(player) + "a"):
			set_player_device(player, device if device >= 0 else -1)
		_set_keys(player, KEYBOARD_KEYS if device == KEYBOARD else {})


## true si juegan dos y hay un solo mando: J1 teclado, J2 mando.
static func keyboard_and_pad_mode(pad_count: int = -1) -> bool:
	if pad_count < 0:
		pad_count = Input.get_connected_joypads().size()
	return _player_count >= 2 and pad_count == 1


static func device_for_player(player_index: int) -> int:
	return int(_devices.get(player_index, -1))


## Cambia el dispositivo real asociado al jugador y reconstruye sus eventos.
static func set_player_device(player_index: int, device: int) -> void:
	_devices[player_index] = device
	var p := prefix(player_index)
	var actions: Array = ["left", "right", "up", "down", "look_back"]
	actions.append_array(BUTTON_ROLES.keys())

	# Quitar eventos anteriores de joystick, conservando las teclas.
	for action in actions:
		var action_name: String = p + action
		if not InputMap.has_action(action_name):
			continue
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action_name, ev)

	if device < 0:
		return

	_joy_axis(p + "left", device, JOY_AXIS_LEFT_X, -1.0)
	_joy_axis(p + "right", device, JOY_AXIS_LEFT_X, 1.0)
	_joy_axis(p + "up", device, JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis(p + "down", device, JOY_AXIS_LEFT_Y, 1.0)
	_joy_button(p + "left", device, JOY_BUTTON_DPAD_LEFT)
	_joy_button(p + "right", device, JOY_BUTTON_DPAD_RIGHT)
	_joy_button(p + "up", device, JOY_BUTTON_DPAD_UP)
	_joy_button(p + "down", device, JOY_BUTTON_DPAD_DOWN)
	_joy_axis(p + "look_back", device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	set_pad_layout(player_index, _layouts.get(player_index, PadLayout.STANDARD))


## Fija cuántas personas juegan y reasigna mandos y teclas (con teclado + un
## mando, el mando pasa a J2).
static func apply_player_count(player_count: int) -> void:
	_player_count = player_count
	if InputMap.has_action(prefix(0) + "a") or not _assigned.is_empty():
		# Refresca mandos y teclas juntos (llama a _apply_keys).
		refresh_player_devices()
	else:
		_apply_keys(Input.get_connected_joypads().size())


## Pone las teclas: todo el teclado es de J1 (los demás juegan con mando).
static func _apply_keys(_pad_count: int) -> void:
	for player in MAX_PLAYERS:
		_set_keys(player, KEYBOARD_KEYS if player == 0 else {})


## Cambia las teclas del jugador por `keys` (acción -> teclas).
static func _set_keys(player: int, keys: Dictionary) -> void:
	var p := prefix(player)
	if not InputMap.has_action(p + "a"):
		return
	for action in InputMap.get_actions():
		if not String(action).begins_with(p):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
	for action in keys:
		if InputMap.has_action(p + action):
			for key in keys[action]:
				_key(p + action, key)


static func get_pad_layout(player_index: int) -> PadLayout:
	return _layouts.get(player_index, PadLayout.STANDARD)


## Cambia la distribución de botones del mando del jugador.
static func set_pad_layout(player_index: int, layout: PadLayout) -> void:
	_layouts[player_index] = layout
	var device := device_for_player(player_index)
	if device < 0:
		return
	var p := prefix(player_index)
	for action in BUTTON_ROLES:
		var action_name: String = p + action
		if not InputMap.has_action(action_name):
			continue
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(action_name, ev)
		for role in BUTTON_ROLES[action]:
			var button: int = PAD_BUTTONS[layout][role]
			if button >= 0:
				_joy_button(action_name, device, button)


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
