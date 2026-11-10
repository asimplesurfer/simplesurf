class_name CharacterSelect
extends Control
## Menú de personaje: cada jugador arma su surfista (peso, piel, short, tabla)
## y marca "listo". J1 además elige cuántos bots y su dificultad.
## Cuando todos están listos, empieza la carrera.
##
## Controles por jugador: ↑↓ elegir fila · ←→ cambiar · A / ESPACIO listo ·
## B / E volver. Teclas 1 / 2 (o Select): cantidad de jugadores.

signal start_requested

const RACE_SCENE := "res://main.tscn"
const ROWS_PLAYER := ["Peso", "Piel", "Short", "Tabla"]
const ROWS_GLOBAL := ["Bots", "Dificultad"]
const WEIGHT_STEP := 0.05
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.1
const YELLOW := Color(1.0, 0.86, 0.2)

## Si es false, no cambia de escena al empezar (para tests); solo emite la señal.
var auto_start: bool = true

var _panels: Array[Dictionary] = []
var _footer: Label


func _ready() -> void:
	GameSettings.load_settings()
	for i in 2:
		InputSetup.ensure_player_actions(i)
	InputSetup.apply_keyboard_layout(GameSettings.player_count)
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_panels.clear()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.7, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24.0
	root.offset_right = -24.0
	root.offset_top = 12.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := _label("SIMPLE SURF", 52, YELLOW)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	root.add_child(columns)
	for i in GameSettings.player_count:
		columns.add_child(_build_panel(i))

	_footer = _label("", 18, Color.WHITE)
	root.add_child(_footer)
	_footer.text = (
		"↑↓ elegir  ·  ←→ cambiar  ·  ESPACIO / A: ¡listo!  ·  E / B: volver\n"
		+ "Jugadores: teclas 1 / 2 o Select  ·  J2 usa flechas y ENTER"
	)
	_refresh_all()


func _build_panel(player: int) -> Control:
	var data := GameSettings.character_for(player)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.15, 0.3, 0.75)
	style.set_corner_radius_all(18)
	style.set_border_width_all(4)
	style.border_color = Color.BLACK
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	# Vista 3D del personaje girando (mundo propio).
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(240.0, 300.0)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	view.add_child(vp)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var avatar := Avatar.new()
	avatar.data = data
	pivot.add_child(avatar)
	var board := MeshInstance3D.new()
	var board_mesh := CapsuleMesh.new()
	board_mesh.radius = 0.5
	board_mesh.height = 3.6
	board.mesh = board_mesh
	board.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.18))
	board.position.y = -0.06
	pivot.add_child(board)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.5, 6.2)
	cam.fov = 38.0
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 1.3, 0.0), Vector3.UP)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 10)
	box.add_child(right)
	right.add_child(_label("Jugador %d" % (player + 1), 34, Color.WHITE))

	var rows: Array = ROWS_PLAYER.duplicate()
	if player == 0:
		rows.append_array(ROWS_GLOBAL)
	var row_labels: Array[Label] = []
	for r in rows:
		var l := _label("", 22, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		right.add_child(l)
		row_labels.append(l)
	var ready_label := _label("", 30, YELLOW)
	right.add_child(ready_label)

	_panels.append({
		"player": player,
		"data": data,
		"avatar": avatar,
		"pivot": pivot,
		"board": board,
		"rows": rows,
		"row_labels": row_labels,
		"ready_label": ready_label,
		"row": 0,
		"ready": false,
		"repeat": 0.0,
		"last_dir": Vector2i.ZERO,
	})
	return panel


func _process(delta: float) -> void:
	for p in _panels:
		var pivot: Node3D = p.pivot
		pivot.rotation.y += delta * 0.8
		_handle_stick(p, delta)


## Stick / flechas mantenidos: repite el movimiento.
func _handle_stick(p: Dictionary, delta: float) -> void:
	var prefix := InputSetup.prefix(p.player)
	var x := Input.get_axis(prefix + "left", prefix + "right")
	var y := Input.get_axis(prefix + "up", prefix + "down")
	var dir := Vector2i.ZERO
	if absf(x) > 0.5:
		dir.x = int(signf(x))
	elif absf(y) > 0.5:
		dir.y = int(signf(y))
	if dir == Vector2i.ZERO:
		p.last_dir = dir
		return
	if dir != p.last_dir:
		p.last_dir = dir
		p.repeat = REPEAT_DELAY
		_move(p, dir)
		return
	p.repeat -= delta
	if p.repeat <= 0.0:
		p.repeat = REPEAT_RATE
		_move(p, dir)


func _move(p: Dictionary, dir: Vector2i) -> void:
	if p.ready:
		return
	if dir.y != 0:
		p.row = posmod(p.row + dir.y, p.rows.size())
	else:
		_change(p, p.rows[p.row], dir.x)
	_refresh(p)


func _change(p: Dictionary, row: String, step: int) -> void:
	var data: CharacterData = p.data
	match row:
		"Peso":
			data.weight = clampf(snappedf(data.weight + step * WEIGHT_STEP, WEIGHT_STEP), 0.0, 1.0)
		"Piel":
			data.skin_index = posmod(data.skin_index + step, CharacterData.SKIN_COLORS.size())
		"Short":
			data.shorts_index = posmod(data.shorts_index + step, CharacterData.SHORTS_COLORS.size())
		"Tabla":
			data.board_index = posmod(data.board_index + step, CharacterData.BOARD_COLORS.size())
		"Bots":
			GameSettings.bot_count = clampi(GameSettings.bot_count + step, 0, 3)
		"Dificultad":
			GameSettings.bot_level = clampi(GameSettings.bot_level + step, 0, 2)
	var avatar: Avatar = p.avatar
	avatar.rebuild()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_1:
			_set_player_count(1)
			return
		if key.physical_keycode == KEY_2:
			_set_player_count(2)
			return
	for p in _panels:
		var prefix := InputSetup.prefix(p.player)
		if event.is_action_pressed(prefix + "a"):
			p.ready = true
			_refresh(p)
			_check_start()
		elif event.is_action_pressed(prefix + "b"):
			p.ready = false
			_refresh(p)
		elif event.is_action_pressed(prefix + "select"):
			_set_player_count(2 if GameSettings.player_count == 1 else 1)


func _set_player_count(count: int) -> void:
	if count == GameSettings.player_count:
		return
	GameSettings.player_count = count
	InputSetup.apply_keyboard_layout(count)
	_build()


func _check_start() -> void:
	for p in _panels:
		if not p.ready:
			return
	GameSettings.save_settings()
	start_requested.emit()
	if auto_start:
		get_tree().change_scene_to_file(RACE_SCENE)


func _refresh_all() -> void:
	for p in _panels:
		_refresh(p)


func _refresh(p: Dictionary) -> void:
	var data: CharacterData = p.data
	var labels: Array[Label] = p.row_labels
	for i in p.rows.size():
		var row: String = p.rows[i]
		var value := ""
		match row:
			"Peso":
				value = "%s  %s" % [_bar(data.weight), AvatarCore.stage_name(data.weight)]
			"Piel":
				value = CharacterData.SKIN_NAMES[data.skin_index]
			"Short":
				value = CharacterData.SHORTS_NAMES[data.shorts_index]
			"Tabla":
				value = CharacterData.BOARD_NAMES[data.board_index]
			"Bots":
				value = str(GameSettings.bot_count)
			"Dificultad":
				value = AIDifficulty.NAMES[GameSettings.bot_level]
		var selected: bool = i == p.row and not p.ready
		labels[i].text = ("> " if selected else "   ") + "%s:  < %s >" % [row, value]
		labels[i].add_theme_color_override("font_color", YELLOW if selected else Color.WHITE)
	var ready_label: Label = p.ready_label
	ready_label.text = "¡LISTO!" if p.ready else "Apretá ESPACIO / A"
	var board: MeshInstance3D = p.board
	board.material_override = ToonMaterial.make(data.board_color(), 0.05)


func _bar(t: float) -> String:
	var n := 10
	var filled := roundi(t * n)
	return "[" + "|".repeat(filled) + ".".repeat(n - filled) + "]"


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(6, font_size / 5))
	return l
