class_name CharacterSelect
extends Control
## Menú de personaje: cada jugador arma su surfista (estilos armados, cuerpo,
## piel, cara, pelo, accesorios, short y tabla, o uno al azar) y marca "listo". J1 además elige cuántos bots y su dificultad.
## Cuando todos están listos, empieza la carrera.
##
## Controles por jugador: ↑↓ elegir fila · ←→ cambiar · A / ESPACIO listo ·
## B / E volver. Teclas 1 / 2 (o Select): cantidad de jugadores.

signal start_requested

const RACE_SCENE := "res://main.tscn"
const ROWS_PLAYER := [
	"Estilo", "Sorpresa", "Panza", "Músculos", "Piel", "Tamaño de cabeza", "Cabeza", "Pelo", "Color de pelo", "Ojos", "Anteojos",
	"Nariz", "Boca", "Cara", "Orejas", "Collar", "Short", "Estampado", "Tabla", "Diseño de tabla",
]
## Fila del menú -> campo de CharacterData.
const ROW_FIELDS := {
	"Piel": "skin", "Cabeza": "head", "Pelo": "hair", "Color de pelo": "hair_color", "Ojos": "eyes",
	"Anteojos": "glasses", "Nariz": "nose", "Boca": "mouth", "Cara": "extra", "Orejas": "ears",
	"Collar": "neck", "Short": "shorts", "Estampado": "shorts_pattern", "Tabla": "board",
	"Diseño de tabla": "board_design",
}
## Con estas filas la cámara se acerca a la cara.
## Barras del menú -> propiedad de CharacterData.
const ROW_SLIDERS := {"Panza": "weight", "Músculos": "muscle", "Tamaño de cabeza": "head_size"}
const FACE_ROWS := [
	"Tamaño de cabeza", "Cabeza", "Pelo", "Color de pelo", "Ojos", "Anteojos", "Nariz", "Boca", "Cara", "Orejas",
]
## Filas visibles a la vez (el resto se ve al bajar).
const VISIBLE_ROWS := 11
const ROWS_GLOBAL := ["Bots", "Dificultad", "Olas", "Mapa"]
const WEIGHT_STEP := 0.05
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.1
const YELLOW := Color(1.0, 0.86, 0.2)

## Segundos sin tocar nada para que arranque la demo (carrera de bots).
const IDLE_DEMO_TIME := 10.0

## Si es false, no cambia de escena al empezar (para tests); solo emite la señal.
var auto_start: bool = true

var _idle_time: float = 0.0
var _demo_label: Label

var _panels: Array[Dictionary] = []
var _footer: Label


func _ready() -> void:
	GameSettings.demo_mode = false
	GameSettings.load_settings()
	for i in 2:
		InputSetup.ensure_player_actions(i)
	InputSetup.apply_keyboard_layout(GameSettings.player_count)
	_build()
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.menu_opened()


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

	_demo_label = _label("", 16, Color(0.85, 0.95, 1.0))
	root.add_child(_demo_label)
	_footer = _label("", 18, Color.WHITE)
	root.add_child(_footer)
	_footer.text = (
		"Arriba / abajo: elegir  ·  Izquierda / derecha: cambiar  ·  ESPACIO / A: ¡listo!  ·  E / B: volver\n"
		+ "Jugadores: teclas 1 / 2 o Select  ·  J2 usa flechas y ENTER  ·  "
		+ "Pantalla dividida (V): %s\n" % ("lado a lado" if GameSettings.split_vertical else "arriba y abajo")
		+ "Salto (O): %s" % GameSettings.jump_style_name()
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
	var board := Node3D.new()
	board.name = "Board"
	pivot.add_child(board)
	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 6.2)).looking_at(
		Vector3(0.0, 1.3, 0.0), Vector3.UP
	)
	cam.fov = 38.0
	cam.set_meta("zoom", 0.0)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)

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
	# Indicadores de que hay más filas arriba / abajo.
	var up_label := _label("", 16, Color(0.8, 0.9, 1.0))
	up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(up_label)
	for r in mini(rows.size(), VISIBLE_ROWS):
		var l := _label("", 21, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		right.add_child(l)
		row_labels.append(l)
	var down_label := _label("", 16, Color(0.8, 0.9, 1.0))
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(down_label)
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
		"up_label": up_label,
		"down_label": down_label,
		"cam": cam,
		"preset": -1,
		"rng": RandomNumberGenerator.new(),
		"ready_label": ready_label,
		"row": 0,
		"ready": false,
		"repeat": 0.0,
		"last_dir": Vector2i.ZERO,
	})
	return panel


func _input(event: InputEvent) -> void:
	# Cualquier cosa que toque el jugador reinicia la espera de la demo.
	var moved := event is InputEventJoypadMotion and absf(event.axis_value) > 0.5
	if RaceManager.is_any_press(event) or moved:
		_idle_time = 0.0


func _process(delta: float) -> void:
	_idle_time += delta
	var left := IDLE_DEMO_TIME - _idle_time
	if _demo_label:
		_demo_label.text = "Demo en %d s" % ceili(left) if left < 6.0 else ""
	if left <= 0.0:
		_start_demo()
		return
	for p in _panels:
		_animate_preview(p, delta)
		_handle_stick(p, delta)


## Gira el personaje; con una fila de la cara, la cámara se acerca y él mira
## al frente (moviéndose un poco), para ver bien lo que se elige.
func _animate_preview(p: Dictionary, delta: float) -> void:
	var pivot: Node3D = p.pivot
	var cam: Camera3D = p.cam
	var face: bool = not p.ready and p.rows[p.row] in FACE_ROWS
	var zoom: float = move_toward(cam.get_meta("zoom"), 1.0 if face else 0.0, delta * 3.0)
	cam.set_meta("zoom", zoom)
	var z := smoothstep(0.0, 1.0, zoom)
	var avatar: Avatar = p.avatar
	# Encuadre de la cara según el tamaño real de la cabeza.
	var head_y := avatar.head_center().y
	var head_r := avatar.head_radius()
	var eye := Vector3(0.0, 1.5, 6.2).lerp(Vector3(0.0, head_y - 0.05, 1.7 + head_r * 4.5), z)
	var look := Vector3(0.0, 1.3, 0.0).lerp(Vector3(0.0, head_y - 0.25, 0.0), z)
	cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	if face:
		var target := sin(Time.get_ticks_msec() * 0.0012) * 0.55
		pivot.rotation.y = lerp_angle(pivot.rotation.y, target, 1.0 - exp(-5.0 * delta))
	else:
		pivot.rotation.y += delta * 0.8


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
	if ROW_FIELDS.has(row):
		data.step_option(ROW_FIELDS[row], step)
		p.preset = -1
	match row:
		"Estilo":
			p.preset = posmod(int(p.preset) + step, CharacterData.PRESETS.size())
			data.apply_preset(p.preset)
		"Sorpresa":
			var rng: RandomNumberGenerator = p.rng
			rng.randomize()
			var r := CharacterData.random(rng)
			for slider in CharacterData.SLIDERS:
				data.set(CharacterData.SLIDERS[slider], r.get(CharacterData.SLIDERS[slider]))
			for field in CharacterData.FIELDS:
				data.set(CharacterData.FIELDS[field][0], r.get_option(field))
			p.preset = -1
		"Panza", "Músculos", "Tamaño de cabeza":
			var prop: String = ROW_SLIDERS[row]
			data.set(prop, clampf(snappedf(float(data.get(prop)) + step * WEIGHT_STEP, WEIGHT_STEP), 0.0, 1.0))
			p.preset = -1
		"Bots":
			GameSettings.bot_count = clampi(GameSettings.bot_count + step, 0, 3)
		"Dificultad":
			GameSettings.bot_level = clampi(GameSettings.bot_level + step, 0, 2)
		"Olas":
			GameSettings.toggle_wave_mode()
		"Mapa":
			GameSettings.toggle_track_layout()
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
		if key.physical_keycode == KEY_V:
			GameSettings.split_vertical = not GameSettings.split_vertical
			_build()
			return
		if key.physical_keycode == KEY_O:
			GameSettings.toggle_jump_style()
			_build()
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


func _start_demo() -> void:
	_idle_time = -1e9
	GameSettings.demo_mode = true
	start_requested.emit()
	if auto_start:
		get_tree().change_scene_to_file(RACE_SCENE)


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
	var rows: Array = p.rows
	# Ventana de filas visibles alrededor de la elegida.
	var first := clampi(int(p.row) - VISIBLE_ROWS / 2, 0, maxi(rows.size() - VISIBLE_ROWS, 0))
	for k in labels.size():
		var i := first + k
		var row: String = rows[i]
		var value := ""
		if ROW_FIELDS.has(row):
			value = data.option_name(ROW_FIELDS[row])
		match row:
			"Estilo":
				value = CharacterData.PRESET_NAMES[p.preset] if p.preset >= 0 else "a tu gusto"
			"Sorpresa":
				value = "uno al azar"
			"Panza":
				value = "%s  %s" % [_bar(data.weight), "Musculoso" if data.weight < 0.15 else AvatarCore.stage_name(data.weight)]
			"Músculos":
				value = _bar(data.muscle)
			"Tamaño de cabeza":
				value = _bar(data.head_size)
			"Bots":
				value = str(GameSettings.bot_count)
			"Dificultad":
				value = AIDifficulty.NAMES[GameSettings.bot_level]
			"Olas":
				value = GameSettings.wave_mode_name()
			"Mapa":
				value = GameSettings.track_layout_name()
		var selected: bool = i == p.row and not p.ready
		labels[k].text = ("> " if selected else "   ") + "%s:  < %s >" % [row, value]
		labels[k].add_theme_color_override("font_color", YELLOW if selected else Color.WHITE)
	(p.up_label as Label).text = "      ▲ más" if first > 0 else ""
	(p.down_label as Label).text = "      ▼ más" if first + labels.size() < rows.size() else ""
	var ready_label: Label = p.ready_label
	ready_label.text = "¡LISTO!" if p.ready else "Apretá ESPACIO / A"
	_rebuild_board(p.board, data)


## Tabla del menú: la misma forma que en la carrera (más grande) con su diseño.
func _rebuild_board(board: Node3D, data: CharacterData) -> void:
	for c in board.get_children():
		c.queue_free()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 3.6
	mesh.material = ToonMaterial.make(data.board_color(), 0.05)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.18))
	body.position.y = -0.06
	board.add_child(body)
	BoardDesign.add_to(board, data, 3.6, 1.0, 0.03)


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
