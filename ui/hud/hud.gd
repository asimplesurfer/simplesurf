class_name Hud
extends CanvasLayer
## HUD de un jugador (uno por pantalla): vuelta, posición, nitro, cartel de
## "spamea", cuenta regresiva, mensajes, rayas de velocidad, velocidad y ayuda.
## Se construye por código para que sea fácil de leer y cambiar.

@export var rider_path: NodePath

const PROMPT_COLOR := Color(1.0, 0.86, 0.2)
const NITRO_COLOR := Color(0.25, 0.85, 1.0)
const BAD_COLOR := Color(1.0, 0.4, 0.35)
const SPEED_LINES_SHADER := preload("res://ui/shaders/speed_lines.gdshader")

## Se pueden asignar antes de agregar el HUD al árbol (lo hace SplitScreen).
var rider: Rider
var race_manager: RaceManager
## Mostrar la ayuda al empezar.
var show_help: bool = true
## Demo: muestra "DEMO" y cómo salir.
var demo: bool = false
## Vista chica (pantalla en 4): todo el HUD se dibuja más chico.
var compact: bool = false

const COMPACT_SCALE := 0.6

var _root: Control

var _mash_box: VBoxContainer
var _mash_title: Label
var _mash_hint: Label
var _mash_bar: ProgressBar
var _speed_label: Label
var _place_label: Label
var _lap_label: Label
var _name_label: Label
var _center_label: Label
var _help: Label
var _nitro_bar: ProgressBar
var _message: Label
var _speed_lines: ColorRect
var _pop_label: Label
var _nitro_label: Label
var _speed_lines_material: ShaderMaterial
var _message_time: float = 0.0
var _center_time: float = 0.0
var _flash: float = 0.0
var _lines: float = 0.0


func _ready() -> void:
	_build()
	if rider == null:
		rider = get_node_or_null(rider_path) as Rider
	if rider:
		_connect_rider()
	if race_manager:
		race_manager.countdown_tick.connect(_on_countdown_tick)
		race_manager.lap_started.connect(_on_lap_started)
		race_manager.racer_finished.connect(_on_racer_finished)
	_help.visible = show_help
	_update_help()
	if demo:
		var tag := _make_label(18, PROMPT_COLOR)
		tag.text = "DEMO · %s\nTocá o apretá un botón para jugar" % (
			rider.display_name if rider else ""
		)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tag.position = Vector2(16.0, 12.0)
		add_child(tag)


func _connect_rider() -> void:
	rider.mash_pressed.connect(func() -> void: _flash = 1.0)
	rider.nitro_changed.connect(func(value: float, max_value: float) -> void:
		_nitro_bar.value = value / max_value
	)
	rider.trick_landed.connect(_on_trick_landed)
	rider.trick_failed.connect(func() -> void: show_message("¡Truco fallido!", BAD_COLOR))
	rider.drift_hit.connect(func(_victim: Rider) -> void: show_message("¡Lo tiraste!", PROMPT_COLOR))
	rider.ring_collected.connect(func() -> void: show_message("+ NITRO", NITRO_COLOR))
	rider.crashed.connect(func() -> void: show_message("¡Pum!", BAD_COLOR))
	rider.popped.connect(func() -> void: show_message("¡POP!", PROMPT_COLOR))
	var pc := rider.controller as PlayerController
	if pc:
		pc.pad_layout_changed.connect(func(layout_name: String) -> void:
			show_message("Mando: " + layout_name, Color.WHITE)
			_update_help()
		)
		pc.jump_style_changed.connect(func(style_name: String) -> void:
			show_message("Salto: " + style_name, Color.WHITE)
			_update_help()
		)
		pc.forward_mode_changed.connect(func(mode_name: String) -> void:
			show_message("Avance: " + mode_name, Color.WHITE)
			_update_help()
		)
		pc.jump_mode_changed.connect(func(mode_name: String) -> void:
			show_message("Salto: " + mode_name, Color.WHITE)
			_update_help()
		)


func show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message_time = 1.4


func show_center(text: String, color: Color, seconds: float) -> void:
	_center_label.text = text
	_center_label.add_theme_color_override("font_color", color)
	_center_time = seconds


func _on_trick_landed(spins: int) -> void:
	var text := "¡Truco!" if spins <= 1 else "¡Truco x%d!" % spins
	show_message(text, NITRO_COLOR)


func _on_countdown_tick(value: int) -> void:
	if value > 0:
		show_center(str(value), Color.WHITE, 0.9)
	else:
		show_center("¡YA!", PROMPT_COLOR, 0.8)


func _on_lap_started(r: Rider, lap: int) -> void:
	if r != rider or lap <= 1:
		return
	if lap == race_manager.config.laps:
		show_center("¡Última vuelta!", PROMPT_COLOR, 1.5)
	else:
		show_center("Vuelta %d" % lap, Color.WHITE, 1.2)


func _on_racer_finished(r: Rider, place: int) -> void:
	if r == rider:
		show_center("¡Llegaste %dº!" % place, PROMPT_COLOR, 3.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_H:
		_help.visible = not _help.visible


func _process(delta: float) -> void:
	if compact and _root:
		# Más chico: se escala la capa y se agranda la raíz para que ocupe toda la vista.
		scale = Vector2.ONE * COMPACT_SCALE
		_root.size = get_viewport().get_visible_rect().size / COMPACT_SCALE
	if rider == null:
		return
	_update_mash(delta)

	# Momento justo para el pop: el botón aparece en grande y late.
	var pop := rider.is_human and rider.pop_ready()
	_pop_label.visible = pop
	if pop:
		_pop_label.text = _button_name()
		_pop_label.pivot_offset = _pop_label.size * 0.5
		_pop_label.scale = Vector2.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.025))

	_speed_label.text = "%d km/h" % roundi(rider.speed * 3.6)
	# Handicap: muestra cuánto más rápido carga el nitro.
	var mult := rider.nitro_gain_mult()
	_nitro_label.text = "NITRO ×%.1f" % mult if mult >= 1.15 else "NITRO"
	_name_label.text = rider.display_name

	if race_manager:
		var laps := race_manager.config.laps
		_lap_label.text = "VUELTA %d/%d" % [race_manager.lap_of(rider), laps]
		_place_label.text = "%dº" % race_manager.place_of(rider)
		if race_manager.is_wrong_way(rider) and _center_time <= 0.0:
			_center_label.text = "¡Al revés!"
			_center_label.add_theme_color_override("font_color", BAD_COLOR)
			_center_label.visible = true
		else:
			_center_label.visible = _center_time > 0.0

	_center_time = maxf(0.0, _center_time - delta)
	_message_time = maxf(0.0, _message_time - delta)
	_message.visible = _message_time > 0.0
	_message.modulate.a = clampf(_message_time / 0.4, 0.0, 1.0)

	# Rayas de velocidad con turbo o motivación.
	var boosting := (rider.turbo_active or rider.motivation_timer > 0.0) and rider.speed > 5.0
	_lines = move_toward(_lines, 1.0 if boosting else 0.0, delta * 4.0)
	_speed_lines.visible = _lines > 0.01
	_speed_lines_material.set_shader_parameter("intensity", _lines)


func _update_mash(delta: float) -> void:
	var fallen := rider.is_fallen() and not rider.controls_locked and rider.is_human
	_mash_box.visible = fallen
	if not fallen:
		return
	# Una sola barra: la primera mitad sube a la tabla, la segunda te para.
	var meter := 0.0
	var state := rider.state_machine.current
	if "meter" in state:
		meter = state.meter
	var half := 0.5 if rider.recovery_stage == Rider.RecoveryStage.PRONE else 0.0
	_mash_bar.value = half + meter * 0.5

	_mash_title.text = "¡Spamea %s!" % _button_name()
	if rider.recovery_stage == Rider.RecoveryStage.IN_WATER:
		_mash_hint.text = "Súbete a la tabla"
	else:
		_mash_hint.text = "¡Ahora párate!"

	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_mash_title.pivot_offset = _mash_title.size * 0.5
	_mash_title.scale = Vector2.ONE * (1.0 + 0.15 * _flash)


func _button_name() -> String:
	var pc := rider.controller as PlayerController
	if pc and pc.using_joypad:
		return "(X)" if pc.is_generic_pad() else "(A)"
	if rider.player_index == 1 and GameSettings.player_count >= 2:
		return "ENTER"
	return "ESPACIO"


func _update_help() -> void:
	var layout := "estándar"
	if rider and rider.controller is PlayerController:
		layout = (rider.controller as PlayerController).layout_name()
	_help.text = (
		"Avance: %s (G cambia)   ·   Girar: A / D o stick\n" % GameSettings.forward_mode_name()
		+ "Salto: %s (O cambia)   ·   Pantalla dividida: V\n" % GameSettings.jump_style_name()
		+ "Truco: en el aire, mantener ESPACIO / botón de abajo\n"
		+ "Derrapar: SHIFT o botón izquierdo / RB   ·   Turbo: E o botón derecho\n"
		+ "Levantarse: spamear ESPACIO o botón de abajo   ·   Caerse (prueba): F\n"
		+ "J2: flechas, ENTER salta, . derrapa, - turbo   ·   Esc: menú\n"
		+ "Mando: %s (M cambia)   ·   H: ocultar ayuda\n" % layout
		+ "Si no responde, haz clic en el juego"
	)


func _build() -> void:
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Rayas de velocidad (detrás de todo lo demás).
	_speed_lines = ColorRect.new()
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines_material = ShaderMaterial.new()
	_speed_lines_material.shader = SPEED_LINES_SHADER
	_speed_lines.material = _speed_lines_material
	_speed_lines.visible = false
	root.add_child(_speed_lines)

	# Cartel de spam, abajo al centro.
	_mash_box = VBoxContainer.new()
	_mash_box.anchor_left = 0.5
	_mash_box.anchor_right = 0.5
	_mash_box.anchor_top = 1.0
	_mash_box.anchor_bottom = 1.0
	_mash_box.offset_left = -260.0
	_mash_box.offset_right = 260.0
	_mash_box.offset_top = -190.0
	_mash_box.offset_bottom = -40.0
	_mash_box.alignment = BoxContainer.ALIGNMENT_END
	_mash_box.add_theme_constant_override("separation", 8)
	root.add_child(_mash_box)
	_mash_hint = _make_label(24, Color.WHITE)
	_mash_box.add_child(_mash_hint)
	_mash_title = _make_label(44, PROMPT_COLOR)
	_mash_box.add_child(_mash_title)
	_mash_bar = _make_bar(PROMPT_COLOR, 24.0)
	_mash_box.add_child(_mash_bar)

	# Nitro, abajo a la izquierda.
	var nitro_box := VBoxContainer.new()
	nitro_box.anchor_top = 1.0
	nitro_box.anchor_bottom = 1.0
	nitro_box.offset_left = 24.0
	nitro_box.offset_right = 284.0
	nitro_box.offset_top = -80.0
	nitro_box.offset_bottom = -20.0
	nitro_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(nitro_box)
	var nitro_label := _make_label(20, NITRO_COLOR)
	_nitro_label = nitro_label
	nitro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nitro_label.text = "NITRO"
	nitro_box.add_child(nitro_label)
	_nitro_bar = _make_bar(NITRO_COLOR, 18.0)
	nitro_box.add_child(_nitro_bar)

	# Posición, vuelta y velocidad, arriba a la derecha.
	var right_box := VBoxContainer.new()
	right_box.anchor_left = 1.0
	right_box.anchor_right = 1.0
	right_box.offset_left = -260.0
	right_box.offset_right = -20.0
	right_box.offset_top = 10.0
	right_box.offset_bottom = 180.0
	root.add_child(right_box)
	_place_label = _make_label(56, PROMPT_COLOR)
	_place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_box.add_child(_place_label)
	_lap_label = _make_label(26, Color.WHITE)
	_lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_box.add_child(_lap_label)
	_speed_label = _make_label(22, Color.WHITE)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_box.add_child(_speed_label)

	# Nombre del jugador, abajo a la derecha.
	_name_label = _make_label(28, Color.WHITE)
	_name_label.anchor_left = 1.0
	_name_label.anchor_right = 1.0
	_name_label.anchor_top = 1.0
	_name_label.anchor_bottom = 1.0
	_name_label.offset_left = -120.0
	_name_label.offset_right = -20.0
	_name_label.offset_top = -56.0
	_name_label.offset_bottom = -16.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_name_label)

	# Mensajes (truco, nitro...), arriba al centro.
	_message = _make_label(40, NITRO_COLOR)
	_message.anchor_left = 0.5
	_message.anchor_right = 0.5
	_message.offset_left = -300.0
	_message.offset_right = 300.0
	_message.offset_top = 70.0
	_message.visible = false
	root.add_child(_message)

	# Botón del pop (en la cresta de la ola), un poco abajo del centro.
	_pop_label = _make_label(64, PROMPT_COLOR)
	_pop_label.set_anchors_preset(Control.PRESET_CENTER)
	_pop_label.offset_left = -250.0
	_pop_label.offset_right = 250.0
	_pop_label.offset_top = 40.0
	_pop_label.offset_bottom = 130.0
	_pop_label.visible = false
	root.add_child(_pop_label)

	# Cartel grande al centro (cuenta regresiva, vuelta, llegada, al revés).
	_center_label = _make_label(84, Color.WHITE)
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.offset_left = -400.0
	_center_label.offset_right = 400.0
	_center_label.offset_top = -80.0
	_center_label.offset_bottom = 20.0
	_center_label.visible = false
	root.add_child(_center_label)

	# Ayuda de controles, arriba a la izquierda.
	_help = _make_label(15, Color.WHITE)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help.position = Vector2(16.0, 12.0)
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
