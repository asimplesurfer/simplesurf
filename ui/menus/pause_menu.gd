class_name PauseMenu
extends CanvasLayer
## Menú de pausa (ESC o Start durante la partida): frena el juego y deja bajar
## el volumen de la música y de los efectos por separado (se guardan), seguir,
## reiniciar o volver al menú. Se maneja con flechas / stick y A / ESPACIO;
## B / ESC vuelve al juego.
##
## Atrás, el juego se sigue viendo en vivo pero fuera de foco y luminoso (ver
## ui/shaders/pause_backdrop.gdshader): al abrir, el foco se va de a poco; al
## cerrar, vuelve de a poco mientras el juego ya sigue. El panel va encima,
## nítido.
##
## Con el juego en pausa la escena no cambia: cuando el fondo termina de
## desenfocarse, las vistas 3D dejan de dibujarse (queda su última imagen) y
## solo se mueve el efecto. Al cerrar vuelven a dibujarse enseguida.

const YELLOW := Palette.BUTTER
## Paso de las barras de volumen (0..100).
const VOLUME_STEP := 10.0
const BACKDROP_SHADER := preload("res://ui/shaders/pause_backdrop.gdshader")
## Segundos que tarda el fondo en desenfocarse al abrir y en volver al cerrar.
const OPEN_TIME := 0.5
const CLOSE_TIME := 0.35

var session: GameSession
var music_slider: HSlider
var sfx_slider: HSlider
## Fondo desenfocado (lee la pantalla de atrás).
var backdrop: ColorRect
var _menu: Control
var _first: Button
var _opened_frame: int = -1
var _open: bool = false
var _amount: float = 0.0
var _fade: Tween
## Vistas congeladas mientras la pausa está abierta -> cómo se actualizaban.
var _frozen: Dictionary = {}


func _init() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build()


func is_open() -> bool:
	return _open


## Cuánto está desenfocado el fondo (0 nítido, 1 del todo).
func blur_amount() -> float:
	return _amount


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
	sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = true
	_menu.modulate.a = 0.0
	_first.grab_focus()
	_animate(1.0, OPEN_TIME)


## Vuelve al juego enseguida; el fondo recupera el foco de a poco.
func close() -> void:
	if not _open:
		return
	_open = false
	_freeze_views(false)
	_menu.visible = false
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	GameSettings.save_settings()
	_animate(0.0, CLOSE_TIME)


## Lleva el desenfoque hasta `target` (y el panel aparece al abrir). Si se
## abre o se cierra a mitad de camino, sigue desde donde estaba.
func _animate(target: float, seconds: float) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	var opening := target > _amount
	_fade.set_trans(Tween.TRANS_SINE if opening else Tween.TRANS_QUAD)
	_fade.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN_OUT)
	_fade.tween_method(_set_amount, _amount, target, maxf(seconds * absf(target - _amount), 0.01))
	if opening:
		_fade.parallel().tween_property(_menu, "modulate:a", 1.0, seconds * 0.6).set_delay(seconds * 0.15)
		_fade.tween_callback(func() -> void:
			if _open:
				_freeze_views(true)
		)
	else:
		_fade.tween_callback(func() -> void:
			if not _open:
				visible = false
		)


## Deja de dibujar (o vuelve a dibujar) las vistas 3D del juego. En pausa no
## cambian, y redibujarlas es lo que más le cuesta a la placa de video.
func _freeze_views(on: bool) -> void:
	if on:
		for node in get_tree().get_nodes_in_group(SharpView.GROUP):
			var vp := (node as SharpView).viewport
			if vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
				_frozen[vp] = vp.render_target_update_mode
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	for vp in _frozen:
		if is_instance_valid(vp):
			(vp as SubViewport).render_target_update_mode = _frozen[vp]
	_frozen.clear()


## Si la pausa desaparece abierta (por ejemplo, al cambiar de escena), las
## vistas no quedan congeladas.
func _exit_tree() -> void:
	_freeze_views(false)


func _set_amount(value: float) -> void:
	_amount = value
	(backdrop.material as ShaderMaterial).set_shader_parameter("amount", value)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or Engine.get_process_frames() == _opened_frame:
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
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	backdrop.material = mat
	add_child(backdrop)
	_set_amount(0.0)
	var center := CenterContainer.new()
	center.name = "Menu"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_menu = center
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
