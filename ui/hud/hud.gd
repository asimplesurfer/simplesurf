class_name Hud
extends CanvasLayer
## HUD de un jugador. Por ahora: cartel de "spamea" con barra, velocidad y ayuda.
## Se construye por código para que sea fácil de leer y cambiar.

@export var rider_path: NodePath

const PROMPT_COLOR := Color(1.0, 0.86, 0.2)

var rider: Rider

var _mash_box: VBoxContainer
var _mash_title: Label
var _mash_hint: Label
var _mash_bar: ProgressBar
var _speed_label: Label
var _flash: float = 0.0


func _ready() -> void:
	_build()
	rider = get_node_or_null(rider_path) as Rider
	if rider:
		rider.mash_pressed.connect(func() -> void: _flash = 1.0)


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


func _button_name() -> String:
	var pc := rider.controller as PlayerController
	if pc and pc.using_joypad:
		return "(A)"
	return "ESPACIO"


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

	_mash_bar = ProgressBar.new()
	_mash_bar.min_value = 0.0
	_mash_bar.max_value = 1.0
	_mash_bar.show_percentage = false
	_mash_bar.custom_minimum_size = Vector2(0.0, 26.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_corner_radius_all(13)
	bg.set_border_width_all(3)
	bg.border_color = Color.BLACK
	var fill := StyleBoxFlat.new()
	fill.bg_color = PROMPT_COLOR
	fill.set_corner_radius_all(13)
	fill.set_border_width_all(3)
	fill.border_color = Color.BLACK
	_mash_bar.add_theme_stylebox_override("background", bg)
	_mash_bar.add_theme_stylebox_override("fill", fill)
	_mash_box.add_child(_mash_bar)

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
	var help := _make_label(18, Color.WHITE)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.position = Vector2(20.0, 16.0)
	help.text = (
		"Girar: A / D, flechas o stick\n"
		+ "Levantarse: spamear ESPACIO o (A)\n"
		+ "Caerse (prueba): R o (Y)\n"
		+ "Si no responde, haz clic en el juego"
	)
	root.add_child(help)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(6, font_size / 5))
	return label
