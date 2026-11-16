class_name PlayerController
extends BaseController
## Lee mando y teclado del jugador `player_index` (acciones p1_, p2_...).
## La distribución del mando se detecta sola; con la tecla M se cambia a mano
## y la elección se guarda para la próxima vez.

signal pad_layout_changed(layout_name: String)
signal jump_mode_changed(mode_name: String)

const SETTINGS_PATH := "user://settings.cfg"
@export var player_index: int = 0

## true si lo último que tocó el jugador fue un mando (para mostrar "A" o "ESPACIO").
var using_joypad: bool = false

var _prefix: String = ""
var _pending_mash: int = 0
var _pending_turbo: bool = false
## Distribución elegida a mano (-1 = automática).
var _manual_layout: int = -1


func _ready() -> void:
	GameSettings.load_settings()
	var rider := get_parent() as Rider
	if rider:
		player_index = rider.player_index
	InputSetup.ensure_player_actions(player_index)
	_prefix = InputSetup.prefix(player_index)

	_manual_layout = _load_manual_layout()
	var device := InputSetup.device_for_player(player_index)
	if device >= 0:
		if _manual_layout >= 0:
			InputSetup.set_pad_layout(player_index, _manual_layout as InputSetup.PadLayout)
		else:
			InputSetup.set_pad_layout(player_index, InputSetup.detect_pad_layout(device))
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func layout_name() -> String:
	return InputSetup.LAYOUT_NAMES[InputSetup.get_pad_layout(player_index)]


func is_generic_pad() -> bool:
	return InputSetup.get_pad_layout(player_index) == InputSetup.PadLayout.GENERIC


## Pasa a la otra distribución de mando y la guarda.
func toggle_pad_layout() -> void:
	var next := InputSetup.PadLayout.GENERIC
	if is_generic_pad():
		next = InputSetup.PadLayout.STANDARD
	InputSetup.set_pad_layout(player_index, next)
	_manual_layout = next
	_save_manual_layout(next)
	pad_layout_changed.emit(layout_name())


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# El ID real puede ser distinto de player_index. Reasignar todos los slots
	# según la lista actual también contempla desconexiones y reconexiones.
	InputSetup.refresh_player_devices()
	var device := InputSetup.device_for_player(player_index)
	if device >= 0 and _manual_layout < 0:
		InputSetup.set_pad_layout(player_index, InputSetup.detect_pad_layout(device))
		pad_layout_changed.emit(layout_name())


func _unhandled_input(event: InputEvent) -> void:
	# Las pulsaciones se cuentan por evento para no perder ninguna al spamear rápido.
	if event.is_action_pressed(_prefix + "a"):
		_pending_mash += 1
	if event.is_action_pressed(_prefix + "b"):
		_pending_turbo = true

	if event is InputEventKey:
		using_joypad = false
	elif event is InputEventJoypadButton:
		using_joypad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		using_joypad = true


func get_input(delta: float) -> RiderInput:
	var input := RiderInput.new()
	input.steer = Input.get_axis(_prefix + "left", _prefix + "right")
	# Avanza solo; tirar el stick claramente hacia atrás frena (un poco de
	# diagonal al girar no frena).
	input.throttle = -1.0 if Input.get_action_strength(_prefix + "down") > 0.5 else 1.0
	var rider := get_parent() as Rider
	var free := rider != null and rider.free_ride
	if free:
		# Modo libre: avanza solo si empuja el stick (o W), y tanto como lo empuje.
		if input.throttle > 0.0:
			input.throttle = Input.get_action_strength(_prefix + "up")
	input.trick = Input.is_action_pressed(_prefix + "a")
	# Tirar el stick hacia atrás (o S) es derrapar: frena igual y además tira a
	# los de atrás. Más lento que el derrape, frena (ver StateRiding).
	var back := Input.get_action_strength(_prefix + "down") > 0.5
	input.drift = (Input.is_action_pressed(_prefix + "drift") or back) and not free
	input.turbo = Input.is_action_pressed(_prefix + "b")
	input.look_back = Input.is_action_pressed(_prefix + "look_back")
	input.jump_pressed = _pending_mash > 0
	input.mash_presses = _pending_mash
	input.turbo_pressed = _pending_turbo
	_pending_turbo = false
	_pending_mash = 0
	return input


func _load_manual_layout() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return -1
	return int(cfg.get_value("pad_layout", "player_%d" % player_index, -1))


func _save_manual_layout(layout: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("pad_layout", "player_%d" % player_index, layout)
	cfg.save(SETTINGS_PATH)
