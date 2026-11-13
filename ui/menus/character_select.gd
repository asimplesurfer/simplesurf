class_name CharacterSelect
extends Control
## Menú del juego, en dos pantallas:
## 1. "Creá tu surfista": categorías a la izquierda, el personaje en grande en
##    el medio y, a la derecha, cuadrados con la foto de cada opción (o el
##    color). Las barras (panza, músculos, cabeza) se mueven con ← →.
## 2. "Armá la partida": jugadores, bots, dificultad, olas y mapa, también en
##    cuadrados. De ahí arranca la carrera.
##
## Se maneja con el mouse, con el mando o con el teclado: flechas / stick para
## moverse, ESPACIO / A para elegir, ENTER / Start para seguir, ESC / B para
## volver. Sin tocar nada 10 s arranca la demo (carrera de bots).

signal start_requested
## Eligió el modo libre (mar abierto).
signal sandbox_requested

const RACE_SCENE := "res://main.tscn"
const SANDBOX_SCENE := "res://sandbox.tscn"
const YELLOW := Color(1.0, 0.86, 0.2)
const PANEL_BG := Color(0.05, 0.15, 0.3, 0.82)
const TILE := Vector2(104.0, 122.0)
## Segundos sin tocar nada para que arranque la demo (carrera de bots).
const IDLE_DEMO_TIME := 10.0

## Categorías del creador: nombre -> secciones. Cada sección es
## [título, tipo, campo, encuadre de la foto]. Tipos: "preset", "option",
## "color", "slider".
const CATEGORIES := {
	"Estilos": [["Estilos armados", "preset", "", ThumbRenderer.Frame.BODY]],
	"Cuerpo": [
		["Panza", "slider", "weight", 0],
		["Músculos", "slider", "muscle", 0],
		["Tamaño de cabeza", "slider", "head_size", 0],
		["Forma de cabeza", "option", "head", ThumbRenderer.Frame.HEAD],
	],
	"Piel": [["Color de piel", "color", "skin", 0]],
	"Pelo": [
		["Peinado", "option", "hair", ThumbRenderer.Frame.HEAD],
		["Color de pelo", "color", "hair_color", 0],
	],
	"Cara": [
		["Ojos", "option", "eyes", ThumbRenderer.Frame.HEAD],
		["Nariz", "option", "nose", ThumbRenderer.Frame.HEAD],
		["Boca", "option", "mouth", ThumbRenderer.Frame.HEAD],
		["Bigote y cejas", "option", "extra", ThumbRenderer.Frame.HEAD],
		["Orejas", "option", "ears", ThumbRenderer.Frame.HEAD],
	],
	"Accesorios": [
		["Anteojos", "option", "glasses", ThumbRenderer.Frame.HEAD],
		["Collar", "option", "neck", ThumbRenderer.Frame.CHEST],
	],
	"Short": [
		["Color del short", "color", "shorts", 0],
		["Estampado", "option", "shorts_pattern", ThumbRenderer.Frame.HIPS],
	],
	"Tabla": [
		["Color de la tabla", "color", "board", 0],
		["Diseño", "option", "board_design", ThumbRenderer.Frame.BOARD],
	],
}
## Con estas categorías la cámara se acerca a la cara.
const FACE_CATEGORIES := ["Pelo", "Cara", "Accesorios"]
## Colores de cada lista (para los cuadrados de color).
const COLOR_LISTS := {
	"skin": CharacterData.SKIN_COLORS,
	"hair_color": CharacterData.HAIR_COLORS,
	"shorts": CharacterData.SHORTS_COLORS,
	"board": CharacterData.BOARD_COLORS,
}
const SLIDER_ENDS := {
	"weight": ["Musculoso", "Panzón"],
	"muscle": ["Flaquito", "Musculoso"],
	"head_size": ["Cabecita", "Cabezón"],
}

## Si es false, no cambia de escena al empezar (para tests); solo emite la señal.
var auto_start: bool = true

## "creator" o "setup".
var screen: String = "creator"
## Jugador que se está armando.
var player: int = 0
var category: String = "Estilos"
## Último estilo armado elegido (-1 = a tu gusto).
var preset: int = -1

var _idle_time: float = 0.0
var _demo_label: Label
var _thumbs: ThumbRenderer
var _avatar: Avatar
var _pivot: Node3D
var _board: Node3D
var _cam: Camera3D
var _zoom: float = 0.0
var _options_box: VBoxContainer
var _category_buttons: Dictionary = {}
## Cuadrados de la categoría actual: campo (o "preset") -> Array de botones.
var _tiles: Dictionary = {}
var _sliders: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameSettings.demo_mode = false
	GameSettings.load_settings()
	for i in 2:
		InputSetup.ensure_player_actions(i)
	InputSetup.apply_keyboard_layout(GameSettings.player_count)
	_rng.randomize()
	_build()
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.menu_opened()


func data() -> CharacterData:
	return GameSettings.character_for(player)


## Arma la pantalla actual desde cero.
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_tiles.clear()
	_sliders.clear()
	_category_buttons.clear()
	_options_box = null
	_cam = null
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.7, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_thumbs = ThumbRenderer.new()
	add_child(_thumbs)
	if screen == "creator":
		_build_creator()
	else:
		_build_setup()
	_demo_label = _label("", 16, Color(0.9, 0.97, 1.0))
	_demo_label.position = Vector2(20.0, 4.0)
	add_child(_demo_label)


# ---------------------------------------------------------------- creador

func _build_creator() -> void:
	var root := _root_box()
	var title := "Creá tu surfista"
	if GameSettings.player_count > 1:
		title = "Jugador %d · creá tu surfista" % (player + 1)
	root.add_child(_label(title, 40, YELLOW))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	# Categorías.
	var cats := VBoxContainer.new()
	cats.add_theme_constant_override("separation", 6)
	cats.custom_minimum_size.x = 160.0
	body.add_child(_panel(cats))
	for cat_name in CATEGORIES:
		var b := _button(cat_name, 22)
		b.custom_minimum_size = Vector2(150.0, 46.0)
		b.pressed.connect(func() -> void: _select_category(cat_name))
		b.focus_entered.connect(func() -> void: _select_category(cat_name))
		cats.add_child(b)
		_category_buttons[cat_name] = b

	# Vista previa grande.
	var view := SubViewportContainer.new()
	view.stretch = true
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(300.0, 300.0)
	body.add_child(_panel(view))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	view.add_child(vp)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_avatar = Avatar.new()
	_avatar.data = data()
	_pivot.add_child(_avatar)
	_board = Node3D.new()
	_pivot.add_child(_board)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	vp.add_child(_cam)
	_cam.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	vp.add_child(sun)
	_rebuild_board()

	# Opciones de la categoría (con desplazamiento).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.x = 470.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(_panel(scroll))
	_options_box = VBoxContainer.new()
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_options_box)

	# Abajo: al azar, ayuda y seguir.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)
	var random := _button("Al azar", 22)
	random.custom_minimum_size = Vector2(140.0, 48.0)
	random.pressed.connect(randomize_character)
	bar.add_child(random)
	var hint := _label("Flechas / stick: moverse · ESPACIO / A: elegir · ENTER / Start: seguir", 16, Color.WHITE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	var next := _button("Listo  →", 26)
	next.custom_minimum_size = Vector2(170.0, 48.0)
	next.pressed.connect(go_setup)
	bar.add_child(next)
	_show_category(category)
	(_category_buttons[category] as Button).grab_focus.call_deferred()


func _select_category(cat_name: String) -> void:
	if cat_name != category:
		_show_category(cat_name)


func _show_category(cat_name: String) -> void:
	category = cat_name
	for c in _category_buttons:
		_style_tile(_category_buttons[c], c == cat_name)
	_fill_options()


func _fill_options() -> void:
	if _options_box == null:
		return
	for c in _options_box.get_children():
		_options_box.remove_child(c)
		c.queue_free()
	_tiles.clear()
	_sliders.clear()
	_thumbs.clear()
	for section in CATEGORIES[category]:
		var title: String = section[0]
		var kind: String = section[1]
		var field: String = section[2]
		var l := _label(title, 20, YELLOW)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_options_box.add_child(l)
		match kind:
			"slider":
				_add_slider(field)
			"preset":
				_add_grid("preset", CharacterData.PRESET_NAMES, kind, section[3])
			_:
				_add_grid(field, (CharacterData.FIELDS[field][1] as Array), kind, section[3])
	_refresh_selection()


func _add_slider(prop: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label(SLIDER_ENDS[prop][0], 16, Color.WHITE))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200.0, 40.0)
	slider.value = float(data().get(prop))
	slider.value_changed.connect(func(v: float) -> void: set_slider(prop, v))
	row.add_child(slider)
	row.add_child(_label(SLIDER_ENDS[prop][1], 16, Color.WHITE))
	_options_box.add_child(row)
	_sliders[prop] = slider


func set_slider(prop: String, value: float) -> void:
	data().set(prop, clampf(value, 0.0, 1.0))
	preset = -1
	if _sliders.has(prop):
		(_sliders[prop] as HSlider).set_value_no_signal(value)
	_changed()


func _add_grid(field: String, names: Array, kind: String, frame: int) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_options_box.add_child(grid)
	var buttons: Array[Button] = []
	for i in names.size():
		var b := Button.new()
		b.custom_minimum_size = TILE
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = names[i]
		_style_tile(b, false)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 6.0
		box.offset_right = -6.0
		box.offset_top = 6.0
		box.offset_bottom = -4.0
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		b.add_child(box)
		if kind == "color":
			var swatch := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = (COLOR_LISTS[field] as Array)[i]
			sb.set_corner_radius_all(40)
			sb.set_border_width_all(3)
			sb.border_color = Color.BLACK
			swatch.add_theme_stylebox_override("panel", sb)
			swatch.custom_minimum_size = Vector2(70.0, 70.0)
			swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(swatch)
		else:
			var pic := TextureRect.new()
			pic.custom_minimum_size = Vector2(80.0, 80.0)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pic)
			_thumbs.request(_variant(field, i), frame, pic)
		var name_label := _label(names[i], 12, Color.WHITE)
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_label)
		var index := i
		b.pressed.connect(func() -> void: choose(field, index))
		grid.add_child(b)
		buttons.append(b)
	_tiles[field] = buttons


## El personaje actual con esa opción cambiada (para la foto del cuadrado).
func _variant(field: String, index: int) -> CharacterData:
	var d := CharacterData.from_dict(data().to_dict())
	if field == "preset":
		d.apply_preset(index)
	else:
		d.set(CharacterData.FIELDS[field][0], index)
		# Para ver los ojos y las cejas, la foto va sin anteojos.
		if field in ["eyes", "extra"]:
			d.glasses_index = 0
	return d


## Elige la opción `index` del campo (o un estilo armado con field = "preset").
func choose(field: String, index: int) -> void:
	if field == "preset":
		preset = index
		data().apply_preset(index)
		for prop in _sliders:
			(_sliders[prop] as HSlider).set_value_no_signal(float(data().get(prop)))
	else:
		data().set(CharacterData.FIELDS[field][0], index)
		preset = -1
	_changed()
	_refresh_selection()
	# Un color cambia las fotos de esa categoría: se rehacen.
	if field in COLOR_LISTS:
		_refresh_thumbs()


func randomize_character() -> void:
	var r := CharacterData.random(_rng)
	for prop in CharacterData.SLIDERS.values():
		data().set(prop, r.get(prop))
	for f in CharacterData.FIELDS:
		data().set(CharacterData.FIELDS[f][0], r.get_option(f))
	preset = -1
	_changed()
	_fill_options()


## Vuelve a pedir las fotos de los cuadrados de la categoría.
func _refresh_thumbs() -> void:
	_thumbs.clear()
	for section in CATEGORIES[category]:
		var kind: String = section[1]
		if kind != "option" and kind != "preset":
			continue
		var field: String = "preset" if kind == "preset" else section[2]
		var buttons: Array = _tiles.get(field, [])
		for i in buttons.size():
			var pic := (buttons[i] as Button).find_children("*", "TextureRect", true, false)
			if not pic.is_empty():
				_thumbs.request(_variant(field, i), section[3], pic[0])


func _changed() -> void:
	_avatar.rebuild()
	_rebuild_board()


func _refresh_selection() -> void:
	for field in _tiles:
		var selected := preset if field == "preset" else data().get_option(field)
		var buttons: Array = _tiles[field]
		for i in buttons.size():
			_style_tile(buttons[i], i == selected)


func _rebuild_board() -> void:
	for c in _board.get_children():
		c.free()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 3.6
	mesh.material = ToonMaterial.make(data().board_color(), 0.04)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.18))
	body.position.y = -0.06
	_board.add_child(body)
	BoardDesign.add_to(_board, data(), 3.6, 1.0, 0.03)


## Gira el personaje; en las categorías de la cara, la cámara se acerca y él
## mira al frente.
func _animate_preview(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var face := category in FACE_CATEGORIES
	_zoom = move_toward(_zoom, 1.0 if face else 0.0, delta * 3.0)
	var z := smoothstep(0.0, 1.0, _zoom)
	var head_y := _avatar.head_center().y
	var head_r := _avatar.head_radius()
	var eye := Vector3(0.0, 1.7, 7.4).lerp(Vector3(0.0, head_y + 0.05, 1.6 + head_r * 4.6), z)
	var look := Vector3(0.0, 1.35, 0.0).lerp(Vector3(0.0, head_y - 0.1, 0.0), z)
	_cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	if face:
		var target := -0.35 + sin(Time.get_ticks_msec() * 0.001) * 0.35
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target, 1.0 - exp(-4.0 * delta))
	else:
		_pivot.rotation.y += delta * 0.6


## 0 = lejos ... 1 = encima de la cara (para tests).
func zoom() -> float:
	return _zoom


# ---------------------------------------------------------------- partida

func _build_setup() -> void:
	var root := _root_box()
	root.add_child(_label("Armá la partida", 40, YELLOW))
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	root.add_child(_panel(box))
	var first := _setup_row(box, "Jugadores", ["1 jugador", "2 jugadores"], GameSettings.player_count - 1,
		func(i: int) -> void: set_player_count(i + 1))
	_setup_row(box, "Bots", ["Sin bots", "1 bot", "2 bots", "3 bots"], GameSettings.bot_count,
		func(i: int) -> void: GameSettings.bot_count = i)
	_setup_row(box, "Dificultad", AIDifficulty.NAMES, GameSettings.bot_level,
		func(i: int) -> void: GameSettings.bot_level = i)
	_setup_row(box, "Olas", _capitalized(GameSettings.WAVE_MODE_NAMES), GameSettings.wave_mode, set_wave_mode)
	_setup_row(box, "Mapa", _capitalized(GameSettings.TRACK_LAYOUT_NAMES), GameSettings.track_layout,
		set_track_layout)
	_setup_row(box, "Clima", _capitalized(GameSettings.WEATHER_NAMES), GameSettings.weather,
		func(i: int) -> void: GameSettings.weather = i as GameSettings.Weather)
	if GameSettings.player_count == 2:
		_setup_row(box, "Pantalla", ["Lado a lado", "Arriba y abajo"], 0 if GameSettings.split_vertical else 1,
			func(i: int) -> void: GameSettings.split_vertical = i == 0)
		var edit := HBoxContainer.new()
		edit.add_theme_constant_override("separation", 10)
		box.add_child(edit)
		for p in 2:
			var b := _button("Editar surfista J%d" % (p + 1), 20)
			b.custom_minimum_size = Vector2(240.0, 50.0)
			b.pressed.connect(func() -> void: go_creator(p))
			edit.add_child(b)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)
	var back := _button("←  Personaje", 22)
	back.custom_minimum_size = Vector2(170.0, 48.0)
	back.pressed.connect(func() -> void: go_creator(0))
	bar.add_child(back)
	var hint := _label("ESPACIO / A: elegir · ENTER / Start: ¡a surfear! · ESC: volver", 16, Color.WHITE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	var free := _button("Modo libre", 22)
	free.custom_minimum_size = Vector2(170.0, 48.0)
	free.pressed.connect(start_sandbox)
	bar.add_child(free)
	var go := _button("¡A surfear!  →", 28)
	go.custom_minimum_size = Vector2(220.0, 52.0)
	go.pressed.connect(start_race)
	bar.add_child(go)
	first.grab_focus.call_deferred()


func _capitalized(names: Array) -> Array:
	var out := []
	for n in names:
		var t := String(n)
		out.append(t.substr(0, 1).to_upper() + t.substr(1))
	return out


## Una fila de opciones en cuadrados; devuelve el primer botón.
func _setup_row(parent: Control, title: String, names: Array, selected: int, on_pick: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _label(title, 22, YELLOW)
	l.custom_minimum_size.x = 150.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	var buttons: Array[Button] = []
	for i in names.size():
		var b := _button(names[i], 18)
		b.custom_minimum_size = Vector2(150.0, 54.0)
		_style_tile(b, i == selected)
		var index := i
		b.pressed.connect(func() -> void:
			on_pick.call(index)
			for k in buttons.size():
				if is_instance_valid(buttons[k]):
					_style_tile(buttons[k], k == index)
			GameSettings.save_settings()
		)
		row.add_child(b)
		buttons.append(b)
	return buttons[0]


func set_player_count(count: int) -> void:
	if count == GameSettings.player_count:
		return
	GameSettings.player_count = count
	InputSetup.apply_keyboard_layout(count)
	_build()


func set_wave_mode(mode: int) -> void:
	if GameSettings.wave_mode != mode:
		GameSettings.toggle_wave_mode()


func set_track_layout(layout: int) -> void:
	if GameSettings.track_layout != layout:
		GameSettings.toggle_track_layout()


# ---------------------------------------------------------------- flujo

func go_setup() -> void:
	GameSettings.save_settings()
	screen = "setup"
	_build()


func go_creator(p: int) -> void:
	player = p
	screen = "creator"
	preset = -1
	_build()


func start_race() -> void:
	GameSettings.save_settings()
	start_requested.emit()
	if auto_start:
		get_tree().change_scene_to_file(RACE_SCENE)


## Modo libre: mar abierto para practicar (sin carrera ni bots).
func start_sandbox() -> void:
	GameSettings.save_settings()
	GameSettings.demo_mode = false
	GameSettings.sandbox_mode = true
	sandbox_requested.emit()
	if auto_start:
		get_tree().change_scene_to_file(SANDBOX_SCENE)


func _start_demo() -> void:
	_idle_time = -1e9
	GameSettings.demo_mode = true
	start_requested.emit()
	if auto_start:
		get_tree().change_scene_to_file(RACE_SCENE)


func _input(event: InputEvent) -> void:
	# Cualquier cosa que toque el jugador reinicia la espera de la demo.
	var moved := event is InputEventJoypadMotion and absf(event.axis_value) > 0.5
	if RaceManager.is_any_press(event) or moved or event is InputEventMouseButton:
		_idle_time = 0.0
	# ENTER / Start: seguir (antes que los botones, que usan ENTER para elegir).
	var key := event as InputEventKey
	var forward := key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
	for p in 2:
		var prefix := InputSetup.prefix(p)
		if InputMap.has_action(prefix + "start") and event.is_action_pressed(prefix + "start"):
			forward = true
	if forward:
		get_viewport().set_input_as_handled()
		if screen == "creator":
			go_setup()
		else:
			start_race()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screen == "setup":
		get_viewport().set_input_as_handled()
		go_creator(0)


func _process(delta: float) -> void:
	_idle_time += delta
	var left := IDLE_DEMO_TIME - _idle_time
	if _demo_label:
		_demo_label.text = "Demo en %d s" % ceili(left) if left < 6.0 else ""
	if left <= 0.0:
		_start_demo()
		return
	if screen == "creator":
		_animate_preview(delta)


# ---------------------------------------------------------------- piezas de UI

func _root_box() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20.0
	root.offset_right = -20.0
	root.offset_top = 10.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	return root


func _panel(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = Color.BLACK
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = content.size_flags_horizontal
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	_style_tile(b, false)
	return b


## Estilo de un cuadrado: elegido = borde amarillo grueso; con el foco (mando
## o teclado encima) = borde blanco.
func _style_tile(b: Button, selected: bool) -> void:
	b.set_meta("selected", selected)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.25, 0.45) if state != "hover" else Color(0.16, 0.34, 0.58)
		if selected or state == "pressed":
			sb.bg_color = Color(0.2, 0.42, 0.7)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(5 if selected else 2)
		sb.border_color = YELLOW if selected else Color(0.02, 0.05, 0.1)
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(4)
			sb.border_color = Color.WHITE
			sb.expand_margin_left = 3.0
			sb.expand_margin_right = 3.0
			sb.expand_margin_top = 3.0
			sb.expand_margin_bottom = 3.0
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
	return l
