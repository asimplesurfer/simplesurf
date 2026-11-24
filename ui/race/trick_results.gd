class_name TrickResults
extends CanvasLayer
## Modo trucos: al terminar el tiempo, el puntaje, el mejor combo y los
## mejores puntajes del mapa (con esa duración). Otra vez o al menú.

@export var session_path: NodePath

const YELLOW := Color(1.0, 0.86, 0.2)

var _session: TrickAttack
var _panel: PanelContainer
var _title: Label
var _list: RichTextLabel
var _again: Button


func _ready() -> void:
	layer = 10
	_session = get_node(session_path) as TrickAttack
	_build()
	_session.finished.connect(_show)


func _show(score: int, rank: int) -> void:
	_title.text = "¡NUEVO RÉCORD!" if rank == 0 else ("¡%dº mejor puntaje!" % (rank + 1) if rank > 0 else "¡Tiempo!")
	var rows: PackedStringArray = []
	rows.append("[font_size=64][color=#%s]%s[/color][/font_size]" % [YELLOW.to_html(false), TrickAttack.format_score(score)])
	rows.append("puntos")
	var people := _session.humans()
	if not people.is_empty() and people[0].best_combo > 0:
		var combo := people[0].best_combo
		rows.append("")
		rows.append("Mejor combo:   ×%d · %s" % [combo, Hud.trick_grade(combo)[0]])
	rows.append("")
	rows.append("Mejores puntajes (%s):" % _duration_name())
	if _session.top.is_empty():
		rows.append("todavía ninguno")
	for i in _session.top.size():
		var line := "%dº   %s" % [i + 1, TrickAttack.format_score(int(_session.top[i]))]
		if i == rank:
			line = "[color=#%s]%s[/color]" % [YELLOW.to_html(false), line]
		rows.append(line)
	_list.text = "[center]%s[/center]" % "\n".join(rows)
	_panel.visible = true
	_again.grab_focus.call_deferred()


func _duration_name() -> String:
	var s := _session.config.trick_seconds
	return "%d min" % (s / 60) if s % 60 == 0 else "%d s" % s


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -280.0
	_panel.offset_right = 280.0
	_panel.offset_top = -230.0
	_panel.offset_bottom = 230.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.1, 0.2, 0.85)
	style.set_corner_radius_all(18)
	style.set_border_width_all(4)
	style.border_color = Color.BLACK
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	_title = _label("¡Tiempo!", 40, YELLOW)
	box.add_child(_title)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.fit_content = true
	_list.scroll_active = false
	_list.custom_minimum_size.x = 500.0
	_list.add_theme_font_size_override("normal_font_size", 26)
	_list.add_theme_color_override("default_color", Color.WHITE)
	_list.add_theme_color_override("font_outline_color", Color.BLACK)
	_list.add_theme_constant_override("outline_size", 6)
	box.add_child(_list)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	box.add_child(bar)
	_again = _button("Otra vez", func() -> void: _session.restart())
	bar.add_child(_again)
	bar.add_child(_button("Menú", func() -> void: _session.back_to_menu()))
	box.add_child(_label("R o Start: otra vez · C: menú", 18, Color(0.8, 0.9, 1.0)))


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170.0, 52.0)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(on_press)
	# Como los cuadrados del menú: con el foco, borde blanco.
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.UI_TILE_HOVER if state == "hover" else Palette.UI_TILE
		if state == "pressed":
			sb.bg_color = Palette.UI_TILE_ON
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = Palette.UI_INK
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(4)
			sb.border_color = Color.WHITE
			sb.set_expand_margin_all(3.0)
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
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
