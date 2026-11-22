class_name PauseMenu
extends CanvasLayer
## Menú de pausa (ESC o Start durante la partida): frena el juego y deja bajar
## el volumen de la música y de los efectos por separado (se guardan), seguir,
## reiniciar o volver al menú. Se maneja con flechas / stick y A / ESPACIO;
## B / ESC vuelve al juego.

const YELLOW := Palette.BUTTER
## Paso de las barras de volumen (0..100).
const VOLUME_STEP := 10.0

var session: GameSession
var music_slider: HSlider
var sfx_slider: HSlider
var _first: Button
var _opened_frame: int = -1


func _init() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
	sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	_first.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	GameSettings.save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed("ui_cancel") or _is_toggle(event):
		get_viewport().set_input_as_handled()
		close()
		return
	# Mando: las acciones "ui_" de Godot mueven el foco con el stick / la cruz,
	# pero no traen botones para elegir ni volver: A elige, B vuelve al juego.
	match _pad_role(event):
		"bottom":
			get_viewport().set_input_as_handled()
			var focused := get_viewport().gui_get_focus_owner() as Button
			if focused:
				focused.pressed.emit()
		"right":
			get_viewport().set_input_as_handled()
			close()


## Posición del botón del mando apretado ("bottom" = A, "right" = B...), o "".
static func _pad_role(event: InputEvent) -> String:
	var jb := event as InputEventJoypadButton
	if jb == null or not jb.pressed:
		return ""
	var buttons: Dictionary = InputSetup.PAD_BUTTONS[InputSetup.detect_pad_layout(jb.device)]
	for role in buttons:
		if buttons[role] == jb.button_index:
			return role
	return ""


## ESC o Start de cualquier jugador (abre y cierra la pausa).
static func _is_toggle(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		return true
	for i in InputSetup.MAX_PLAYERS:
		var action := InputSetup.prefix(i) + "start"
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.UI_PANEL
	style.set_corner_radius_all(18)
	style.set_border_width_all(4)
	style.border_color = Color.BLACK
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("Pausa", 44, YELLOW))

	_first = _button("Seguir", close)
	box.add_child(_first)
	music_slider = _volume_row(box, "Música", GameSettings.music_volume, func(v: float) -> void:
		GameSettings.music_volume = v
		_apply_volumes()
	)
	sfx_slider = _volume_row(box, "Efectos", GameSettings.sfx_volume, func(v: float) -> void:
		GameSettings.sfx_volume = v
		_apply_volumes()
	)
	box.add_child(_button("Reiniciar", func() -> void:
		close()
		if session:
			session.restart()
	))
	box.add_child(_button("Volver al menú", func() -> void:
		close()
		if session:
			session.back_to_menu()
	))
	box.add_child(_label("ESC / Start / B: seguir · A: elegir · flechas: moverse y cambiar el volumen", 15, Color(0.85, 0.9, 1.0)))


func _apply_volumes() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.apply_volumes()


## Fila "Música [-----o----] 80": la barra se mueve con izquierda / derecha.
func _volume_row(parent: Control, title: String, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := _label(title, 24, Color.WHITE)
	l.custom_minimum_size.x = 120.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = VOLUME_STEP
	slider.value = value * 100.0
	slider.custom_minimum_size = Vector2(260.0, 32.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var pct := _label("%d%%" % roundi(value * 100.0), 22, Color.WHITE)
	pct.custom_minimum_size.x = 70.0
	row.add_child(pct)
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v)
		on_change.call(v / 100.0)
	)
	return slider


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(320.0, 52.0)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, font_size / 5))
	return l
