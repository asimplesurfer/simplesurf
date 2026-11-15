class_name TuningPanel
extends PanelContainer
## Panel de ajustes para probar (abajo a la derecha): color del agua, con el
## número a la vista. Escondido de entrada; F9 lo muestra / esconde.
## Los sliders no toman el foco: las flechas y el teclado siguen siendo del juego.

var _water_slider: HSlider
var _water_label: Label


func _ready() -> void:
	# Pegado abajo a la derecha (crece hacia arriba y a la izquierda).
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -330.0
	offset_right = -16.0
	offset_top = -120.0
	offset_bottom = -64.0
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.72)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "AJUSTES DE PRUEBA  (F9 esconde)"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(1, 1, 1, 0.7)
	box.add_child(title)

	_water_label = _label(box)
	_water_slider = _slider(box, 0.0, 1.0, 0.01, Tuning.water_dark)
	_water_slider.value_changed.connect(func(v: float) -> void:
		Tuning.water_dark = v
		_refresh())
	visible = Tuning.panel_visible
	_refresh()


func _label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 17)
	parent.add_child(l)
	return l


func _slider(parent: Control, lo: float, hi: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(270.0, 24.0)
	parent.add_child(s)
	return s


func _refresh() -> void:
	_water_label.text = "Color del agua: %.2f   (elegido %.2f; 0 original, 1 marino)" % [
		Tuning.water_dark, Tuning.WATER_DARK_DEFAULT
	]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F9:
		Tuning.panel_visible = not Tuning.panel_visible
		visible = Tuning.panel_visible
		get_viewport().set_input_as_handled()
