class_name ResultsPanel
extends CanvasLayer
## Resultados al terminar la carrera (cuando llegaron todos los humanos):
## los puestos abajo, al instante, y arriba la repetición de la carrera en el
## minimapa (RaceReplay), con cada nombre del color de su punto.

@export var race_manager_path: NodePath

var _panel: PanelContainer
var _list: RichTextLabel
var _replay: RaceReplay
var _record_button: Button
var _record_note: Label
var _race: RaceManager
## Contrarreloj: en qué puesto quedó entre los mejores (-1 = no entró).
var _trial_rank: int = -1


func _ready() -> void:
	layer = 10
	var race_manager := get_node(race_manager_path) as RaceManager
	_race = race_manager
	if race_manager.time_trial:
		race_manager.time_trial.finished.connect(func(_t: float, rank: int) -> void: _trial_rank = rank)
	race_manager.record_downloaded.connect(func(where: String) -> void:
		_record_note.text = "Registro descargado: %s\nAdjuntáselo a Claude para analizarlo." % where.get_file()
		_record_note.visible = true
	)
	race_manager.race_finished.connect(func(ranking: Array[Rider]) -> void:
		_show(race_manager, ranking)
	)
	_build()


func _show(race_manager: RaceManager, ranking: Array[Rider]) -> void:
	_replay.setup(race_manager)
	_replay.visible = race_manager.time_trial == null and _replay.sample_count() > 1
	var lines: PackedStringArray = []
	for i in ranking.size():
		var r := ranking[i]
		var time_text := "--"
		if race_manager.finish_times.has(r):
			time_text = format_time(race_manager.finish_times[r])
		var col := _replay.color_of(race_manager.racers.find(r)) if _replay.visible else Color.WHITE
		lines.append("%dº   [color=#%s]%s[/color]   %s" % [i + 1, col.to_html(false), _escape(r.display_name), time_text])
	# El mejor combo de cada persona, con su calificación.
	for r in ranking:
		if r.is_human and r.best_combo > 0:
			lines.append("Mejor combo de %s:   ×%d · %s" % [_escape(r.display_name), r.best_combo, Hud.trick_grade(r.best_combo)[0]])
	_list.text = "[center]%s[/center]" % "\n".join(lines)
	var trial := race_manager.time_trial
	if trial:
		# Contrarreloj: el tiempo, si es récord y los mejores del mapa.
		var t: float = race_manager.finish_times.get(trial.rider, race_manager.race_time)
		var head := "¡NUEVO RÉCORD!" if _trial_rank == 0 else ("¡%dº mejor tiempo!" % (_trial_rank + 1) if _trial_rank > 0 else "Tu tiempo")
		var rows: PackedStringArray = ["%s   %s" % [head, format_time(t)], "", "Mejores tiempos:"]
		for i in trial.top.size():
			rows.append("%dº   %s" % [i + 1, format_time(float(trial.top[i].time))])
		_list.text = "[center]%s[/center]" % "\n".join(rows)
	_record_button.visible = race_manager.recorder != null
	_panel.visible = true


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func format_time(t: float) -> String:
	var minutes := int(t / 60.0)
	return "%d:%04.1f" % [minutes, t - minutes * 60.0]


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -300.0
	_panel.offset_right = 300.0
	_panel.offset_top = -340.0
	_panel.offset_bottom = 340.0
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
	box.add_child(_label("Resultados", 40, Color(1.0, 0.86, 0.2)))
	_replay = RaceReplay.new()
	_replay.custom_minimum_size = Vector2(540.0, 230.0)
	box.add_child(_replay)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.fit_content = true
	_list.scroll_active = false
	_list.custom_minimum_size.x = 540.0
	_list.add_theme_font_size_override("normal_font_size", 26)
	_list.add_theme_color_override("default_color", Color.WHITE)
	_list.add_theme_color_override("font_outline_color", Color.BLACK)
	_list.add_theme_constant_override("outline_size", 6)
	box.add_child(_list)
	_record_button = Button.new()
	_record_button.text = "Descargar registro (L)"
	_record_button.focus_mode = Control.FOCUS_NONE
	_record_button.add_theme_font_size_override("font_size", 20)
	_record_button.pressed.connect(func() -> void:
		if _race:
			_race.download_record()
	)
	box.add_child(_record_button)
	_record_note = _label("", 16, Color(0.8, 1.0, 0.8))
	_record_note.visible = false
	box.add_child(_record_note)
	box.add_child(_label("R o Start: otra carrera\nC: cambiar personaje · Esc: pausa", 18, Color(0.8, 0.9, 1.0)))


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, font_size / 5))
	return l
