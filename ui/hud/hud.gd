class_name Hud
extends CanvasLayer
## HUD de un jugador: cartel de "spamea" con barra, nitro, mensajes de truco,
## velocidad y ayuda.
## Se construye por código para que sea fácil de leer y cambiar.

@export var rider_path: NodePath

const PROMPT_COLOR := Color(1.0, 0.86, 0.2)
const NITRO_COLOR := Color(0.25, 0.85, 1.0)

var rider: Rider

var _mash_box: VBoxContainer
var _mash_title: Label
var _mash_hint: Label
var _mash_bar: ProgressBar
var _speed_label: Label
var _help: Label
var _nitro_bar: ProgressBar
var _message: Label
var _message_time: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	_build()
	rider = get_node_or_null(rider_path) as Rider
	if rider:
		rider.mash_pressed.connect(func() -> void: _flash = 1.0)
		rider.nitro_changed.connect(func(value: float, max_value: float) -> void:
			_nitro_bar.value = value / max_value
		)
		rider.trick_landed.connect(_on_trick_landed)
		rider.trick_failed.connect(func() -> void: show_message("¡Truco fallido!", Color(1.0, 0.4, 0.35)))
		rider.drift_hit.connect(func(_victim: Rider) -> void: show_message("¡Lo tiraste!", PROMPT_COLOR))
		var pc := rider.controller as PlayerController
		if pc:
			pc.pad_layout_changed.connect(func(layout_name: String) -> void:
				show_message("Mando: " + layout_name, Color.WHITE)
				_update_help()
			)
			pc.jump_mode_changed.connect(func(mode_name: String) -> void:
				show_message("Salto: " + mode_name, Color.WHITE)
				_update_help()
			)
		_update_help()


func show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_time = 1.4


func _on_trick_landed(spins: int) -> void:
	var text := "¡Truco!" if spins <= 1 else "¡Truco x%d!" % spins
	show_message(text, NITRO_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_H:
		_help.visible = not _help.visible


func _process(delta: float) -> void:
	if rider == null:
		return
	var fallen := rider.is_fallen()
	_mash_box.visible = fallen
	if fallen:
		var meter := 0.0
		var state := rider.state_machine.current
		if "meter" in state:
			meter = state.meter
		_mash_bar.value = meter

		var button := _button_name()
		_mash_title.text = "¡Spamea %s!" % button
		if rider.recovery_stage == Rider.RecoveryStage.IN_WATER:
			_mash_hint.text = "Súbete a la tabla"
		else:
			_mash_hint.text = "¡Ahora párate!"

		_flash = move_toward(_flash, 0.0, delta * 6.0)
		_mash_title.pivot_offset = _mash_title.size * 0.5
		_mash_title.scale = Vector2.ONE * (1.0 + 0.15 * _flash)

	_speed_label.text = "%d km/h" % roundi(rider.speed * 3.6)

	_message_time = maxf(0.0, _message_time - delta)
	_message.visible = _message_time > 0.0
	_message.modulate.a = clampf(_message_time / 0.4, 0.0, 1.0)


func _button_name() -> String:
	var pc := rider.controller as PlayerController
	if pc and pc.using_joypad:
		return "(X)" if pc.is_generic_pad() else "(A)"
	return "ESPACIO"


func _update_help() -> void:
	var layout := "estándar"
	if rider and rider.controller is PlayerController:
		layout = (rider.controller as PlayerController).layout_name()
	_help.text = (
		"Acelerar / frenar: W / S o stick\n"
		+ "Girar: A / D o stick\n"
		+ "Saltar: ESPACIO o botón de abajo (%s · T para cambiar)\n" % GameSettings.jump_mode_name()
		+ "Truco: en el aire, mantener ESPACIO / botón de abajo\n"
		+ "Derrapar: SHIFT o botón izquierdo / RB\n"
		+ "Levantarse: spamear ESPACIO o botón de abajo\n"
		+ "Caerse (prueba): R o botón de arriba\n"
		+ "Mando: %s (M para cambiar)\n" % layout
		+ "H: ocultar esta ayuda  ·  Si no responde, haz clic en el juego"
	)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Cartel de spam, abajo al centro.
	_mash_box = VBoxContainer.new()
	_mash_box.anchor_left = 0.5
	_mash_box.anchor_right = 0.5
	_mash_box.anchor_top = 1.0
	_mash_box.anchor_bottom = 1.0
	_mash_box.offset_left = -260.0
	_mash_box.offset_right = 260.0
	_mash_box.offset_top = -210.0
	_mash_box.offset_bottom = -50.0
	_mash_box.alignment = BoxContainer.ALIGNMENT_END
	_mash_box.add_theme_constant_override("separation", 10)
	root.add_child(_mash_box)

	_mash_hint = _make_label(26, Color.WHITE)
	_mash_box.add_child(_mash_hint)

	_mash_title = _make_label(48, PROMPT_COLOR)
	_mash_box.add_child(_mash_title)

	_mash_bar = _make_bar(PROMPT_COLOR, 26.0)
	_mash_box.add_child(_mash_bar)

	# Nitro, abajo a la izquierda.
	var nitro_box := VBoxContainer.new()
	nitro_box.anchor_top = 1.0
	nitro_box.anchor_bottom = 1.0
	nitro_box.offset_left = 24.0
	nitro_box.offset_right = 284.0
	nitro_box.offset_top = -86.0
	nitro_box.offset_bottom = -24.0
	nitro_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(nitro_box)
	var nitro_label := _make_label(22, NITRO_COLOR)
	nitro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nitro_label.text = "NITRO"
	nitro_box.add_child(nitro_label)
	_nitro_bar = _make_bar(NITRO_COLOR, 20.0)
	nitro_box.add_child(_nitro_bar)

	# Mensajes (truco, etc.), arriba al centro.
	_message = _make_label(44, NITRO_COLOR)
	_message.anchor_left = 0.5
	_message.anchor_right = 0.5
	_message.offset_left = -300.0
	_message.offset_right = 300.0
	_message.offset_top = 90.0
	_message.visible = false
	root.add_child(_message)

	# Velocidad, arriba a la derecha.
	_speed_label = _make_label(28, Color.WHITE)
	_speed_label.anchor_left = 1.0
	_speed_label.anchor_right = 1.0
	_speed_label.offset_left = -220.0
	_speed_label.offset_right = -20.0
	_speed_label.offset_top = 16.0
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_speed_label)

	# Ayuda de controles, arriba a la izquierda.
	_help = _make_label(17, Color.WHITE)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help.position = Vector2(20.0, 16.0)
	root.add_child(_help)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(6, font_size / 5))
	return label


func _make_bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_corner_radius_all(int(height * 0.5))
	bg.set_border_width_all(3)
	bg.border_color = Color.BLACK
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(int(height * 0.5))
	fill.set_border_width_all(3)
	fill.border_color = Color.BLACK
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar
