class_name CharacterSelect
extends Control
## Menú del juego, en tres pantallas:
## 1. Título: JUGAR. Al apretarlo pasa a JUGADORES ◀ 1 ▶ (de 1 a 4).
## 2. Personajes: una tarjeta por jugador (PlayerCard). Cada persona se une
##    apretando A / ESPACIO con su mando o el teclado (el teclado es de una sola
##    persona) y arma su surfista; todos a la vez. Cuando todos los que se
##    unieron están listos (Start / ENTER), sigue.
## 3. "Armá la partida": bots, dificultad, olas, mapa, clima. De ahí arranca la
##    carrera (o el modo libre). Cada jugador juega con el dispositivo con el
##    que se unió.
## Sin tocar nada 10 s arranca la demo (carrera de bots). Apenas alguien usa
## el juego (teclado, mouse o mando) la demo ya no arranca sola.

signal start_requested
## Eligió el modo libre (mar abierto).
signal sandbox_requested
## La configuración de la última partida que se abrió desde este menú.
var started_config: RaceConfig

const RACE_SCENE := "res://main.tscn"
const SANDBOX_SCENE := "res://sandbox.tscn"
const YELLOW := Palette.BUTTER
const PANEL_BG := Palette.UI_PANEL
const IDLE_DEMO_TIME := 10.0

## Categorías del creador: nombre -> secciones. Cada sección es
## [título, tipo, campo, encuadre de la foto]. Tipos: "preset", "option",
## "color", "slider".
const CATEGORIES := {
	"Estilos": [["Estilos armados", "preset", "", ThumbRenderer.Frame.BODY]],
	"Cuerpo": [
		["Cuerpo", "slider", "weight", 0],
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
		["Sombrero", "option", "hat", ThumbRenderer.Frame.HEAD],
		["Color del sombrero", "color", "hat_color", 0],
		["Anteojos", "option", "glasses", ThumbRenderer.Frame.HEAD],
		["Collar", "option", "neck", ThumbRenderer.Frame.CHEST],
	],
	"Ropa": [
		["Arriba", "option", "top", ThumbRenderer.Frame.CHEST],
		["Color del short", "color", "shorts", 0],
		["Estampado", "option", "shorts_pattern", ThumbRenderer.Frame.HIPS],
		["Color del estampado", "color", "shorts_pattern_color", 0],
		["Segundo color", "color", "shorts_pattern_color2", 0],
	],
	"Tabla": [
		["Color de la tabla", "color", "board", 0],
		["Diseño", "option", "board_design", ThumbRenderer.Frame.BOARD],
		["Color del diseño", "color", "board_design_color", 0],
		["Segundo color", "color", "board_design_color2", 0],
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
	"hat_color": CharacterData.ACCENT_COLORS,
	"shorts_pattern_color": CharacterData.ACCENT_COLORS,
	"shorts_pattern_color2": CharacterData.ACCENT_COLORS,
	"board_design_color": CharacterData.ACCENT_COLORS,
	"board_design_color2": CharacterData.ACCENT_COLORS,
}
const SLIDER_ENDS := {
	"weight": ["Musculoso", "Panzón"],
}

## Si es false, no cambia de escena al empezar (para tests); solo emite la señal.
var auto_start: bool = true
## Pantalla actual: "title", "players" o "setup".
var screen: String = "title"
## En el título: false = botón JUGAR, true = elegir cuántos juegan.
var choosing_count: bool = false
## Tarjetas de los jugadores (pantalla "players").
var cards: Array[PlayerCard] = []
## Dispositivo de cada jugador que ya se unió (para volver a las tarjetas).
var _joined: Dictionary = {}
var _idle_time: float = 0.0
## Alguien ya usó el juego (teclado, mouse o mando): la demo no vuelve a
## arrancar sola mientras siga abierto.
static var someone_played: bool = false
var _demo_label: Label
var _thumbs: ThumbRenderer
var _count_label: Label
## Stick ya movido (hay que soltarlo para el próximo paso): "device:eje" -> true.
var _stick_armed: Dictionary = {}


func _ready() -> void:
	GameSettings.load_settings()
	for i in InputSetup.MAX_PLAYERS:
		InputSetup.ensure_player_actions(i)
	# En el menú cada uno se une con su dispositivo; hasta entonces se reparte solo.
	InputSetup.clear_assignments()
	InputSetup.apply_keyboard_layout(GameSettings.player_count)
	# En el navegador el mando "aparece" recién al tocar un botón (a veces ya en
	# el menú): se reasignan los mandos apenas se conecta o desconecta uno.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_build()
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.menu_opened()


## Arma la pantalla actual desde cero.
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	cards.clear()
	_count_label = null
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.UI_SKY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_thumbs = ThumbRenderer.new()
	add_child(_thumbs)
	match screen:
		"title":
			_build_title()
		"players":
			_build_players()
		_:
			_build_setup()
	_demo_label = _label("", 16, Palette.UI_SOFT_TEXT)
	_demo_label.position = Vector2(20.0, 4.0)
	add_child(_demo_label)


# ---------------------------------------------------------------- título

func _build_title() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)
	box.add_child(_label("SimpleSurf", 72, YELLOW))
	if not choosing_count:
		var play := _button("JUGAR", 44)
		play.custom_minimum_size = Vector2(320.0, 96.0)
		play.pressed.connect(func() -> void: _title_accept())
		box.add_child(play)
		box.add_child(_label("ESPACIO / A", 18, Color.WHITE))
		return
	box.add_child(_label("Jugadores", 34, Color.WHITE))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var less := _button("<", 44)
	less.custom_minimum_size = Vector2(90.0, 90.0)
	less.focus_mode = Control.FOCUS_NONE
	less.pressed.connect(func() -> void: change_player_count(-1))
	row.add_child(less)
	_count_label = _label(str(GameSettings.player_count), 64, YELLOW)
	_count_label.custom_minimum_size = Vector2(90.0, 0.0)
	row.add_child(_count_label)
	var more := _button(">", 44)
	more.custom_minimum_size = Vector2(90.0, 90.0)
	more.focus_mode = Control.FOCUS_NONE
	more.pressed.connect(func() -> void: change_player_count(1))
	row.add_child(more)
	var go := _button("¡Vamos!", 30)
	go.custom_minimum_size = Vector2(260.0, 70.0)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(go_players)
	box.add_child(go)
	box.add_child(_label("Izquierda / derecha: cuántos juegan · ESPACIO / A seguir · ESC / B volver", 18, Color.WHITE))


func _title_accept() -> void:
	if not choosing_count:
		choosing_count = true
		_build()
	else:
		go_players()


func change_player_count(step: int) -> void:
	GameSettings.player_count = clampi(GameSettings.player_count + step, 1, InputSetup.MAX_PLAYERS)
	if _count_label:
		_count_label.text = str(GameSettings.player_count)


# ---------------------------------------------------------------- jugadores

func _build_players() -> void:
	var root := _root_box()
	var title := "Uníte y armá tu surfista" if GameSettings.player_count == 1 else "Cada uno se une y arma su surfista"
	root.add_child(_label(title, 34, YELLOW))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	var count := GameSettings.player_count
	for i in count:
		var card := PlayerCard.new()
		card.index = i
		card.compact = count >= 3
		card.thumbs = _thumbs
		if count <= 2:
			card.custom_minimum_size.x = 440.0
		else:
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		cards.append(card)
		card.ready_changed.connect(_check_all_ready)
		card.join_clicked.connect(func() -> void: _join(InputSetup.KEYBOARD))
		if _joined.has(i):
			card.join(_joined[i])
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)
	var back := _button("Volver", 22)
	back.custom_minimum_size = Vector2(150.0, 46.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(go_title)
	bar.add_child(back)
	var hint := _label("Cuando todos están listos (Start / ENTER), sigue", 18, Color.WHITE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)


## Une el dispositivo a la primera tarjeta libre. Devuelve la tarjeta (o null).
func _join(device: int) -> PlayerCard:
	if card_of(device):
		return null
	for card in cards:
		if not card.joined():
			card.join(device)
			_joined[card.index] = device
			return card
	return null


## Tarjeta que maneja el dispositivo (o null).
func card_of(device: int) -> PlayerCard:
	for card in cards:
		if card.device == device:
			return card
	return null


func _check_all_ready() -> void:
	for card in cards:
		if not card.joined() or not card.is_ready:
			return
	var assignment := {}
	for card in cards:
		assignment[card.index] = card.device
	InputSetup.assign_devices(assignment)
	go_setup()


## Lo que tocó un dispositivo en la pantalla de jugadores.
func _players_action(device: int, action: String) -> void:
	var card := card_of(device)
	if card == null:
		if action in ["accept", "start"]:
			_join(device)
		elif action == "back" and _joined.is_empty():
			go_title()
		return
	match action:
		"left":
			card.move(Vector2i(-1, 0))
		"right":
			card.move(Vector2i(1, 0))
		"up":
			card.move(Vector2i(0, -1))
		"down":
			card.move(Vector2i(0, 1))
		"accept":
			card.accept()
		"start":
			card.toggle_ready()
		"random":
			card.randomize_character()
		"export":
			card.export_character()
		"back":
			if not card.back():
				_joined.erase(card.index)
				card.leave()


# ---------------------------------------------------------------- partida

func _build_setup() -> void:
	var root := _root_box()
	root.add_child(_label("Armá la partida", 40, YELLOW))
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	root.add_child(_panel(box))
	var first := _setup_row(box, "Bots", ["Sin bots", "1 bot", "2 bots", "3 bots"], GameSettings.bot_count,
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
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)
	var back := _button("Personajes", 22)
	back.custom_minimum_size = Vector2(170.0, 48.0)
	back.pressed.connect(go_players)
	bar.add_child(back)
	var hint := _label("ESPACIO / A: elegir · ENTER / Start: ¡a surfear! · ESC: volver", 16, Color.WHITE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	var free := _button("Modo libre", 22)
	free.custom_minimum_size = Vector2(170.0, 48.0)
	free.pressed.connect(start_sandbox)
	bar.add_child(free)
	var go := _button("¡A surfear!", 28)
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


func set_wave_mode(mode: int) -> void:
	if GameSettings.wave_mode != mode:
		GameSettings.toggle_wave_mode()


func set_track_layout(layout: int) -> void:
	if GameSettings.track_layout != layout:
		GameSettings.toggle_track_layout()


# ---------------------------------------------------------------- flujo

func go_title() -> void:
	screen = "title"
	choosing_count = true
	_joined.clear()
	InputSetup.clear_assignments()
	_build()


func go_players() -> void:
	GameSettings.save_settings()
	screen = "players"
	# Si cambió la cantidad, se sueltan los que sobran.
	for i in _joined.keys():
		if i >= GameSettings.player_count:
			_joined.erase(i)
	_build()


func go_setup() -> void:
	GameSettings.save_settings()
	screen = "setup"
	_build()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	InputSetup.refresh_player_devices()


func start_race() -> void:
	GameSettings.save_settings()
	_launch(RACE_SCENE, RaceConfig.from_settings(), start_requested)


## Modo libre: mar abierto para practicar (sin carrera ni bots).
func start_sandbox() -> void:
	GameSettings.save_settings()
	_launch(SANDBOX_SCENE, RaceConfig.sandbox(), sandbox_requested)


func _start_demo() -> void:
	_idle_time = -1e9
	_launch(RACE_SCENE, RaceConfig.demo(), start_requested)


## Arma la partida y la abre (la configuración viaja con la escena: nada
## global). En los tests (auto_start = false) solo la deja en `started_config`.
func _launch(scene_path: String, config: RaceConfig, done: Signal) -> void:
	started_config = config
	done.emit()
	if auto_start:
		# Desde el menú, con la intro (mientras carga, la cámara recorre la pista).
		GameSession.launch(get_tree(), scene_path, config, null, true)


# ---------------------------------------------------------------- entrada

## Traduce un evento a (dispositivo, acción): acción = left/right/up/down,
## accept, back, start, random o export. Devuelve [] si no es nada de eso.
func _read(event: InputEvent) -> Array:
	var key := event as InputEventKey
	if key and key.pressed:
		var dir := ""
		match key.physical_keycode:
			KEY_LEFT, KEY_A:
				dir = "left"
			KEY_RIGHT, KEY_D:
				dir = "right"
			KEY_UP, KEY_W:
				dir = "up"
			KEY_DOWN, KEY_S:
				dir = "down"
		if dir != "":
			return [InputSetup.KEYBOARD, dir]
		if key.echo:
			return []
		match key.physical_keycode:
			KEY_SPACE, KEY_J:
				return [InputSetup.KEYBOARD, "accept"]
			KEY_ENTER, KEY_KP_ENTER:
				return [InputSetup.KEYBOARD, "start"]
			KEY_ESCAPE, KEY_BACKSPACE:
				return [InputSetup.KEYBOARD, "back"]
			KEY_R:
				return [InputSetup.KEYBOARD, "random"]
			KEY_C:
				return [InputSetup.KEYBOARD, "export"]
		return []
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		match jb.button_index:
			JOY_BUTTON_DPAD_LEFT:
				return [jb.device, "left"]
			JOY_BUTTON_DPAD_RIGHT:
				return [jb.device, "right"]
			JOY_BUTTON_DPAD_UP:
				return [jb.device, "up"]
			JOY_BUTTON_DPAD_DOWN:
				return [jb.device, "down"]
			JOY_BUTTON_BACK:
				return [jb.device, "export"]
		var buttons: Dictionary = InputSetup.PAD_BUTTONS[InputSetup.detect_pad_layout(jb.device)]
		for role in buttons:
			if buttons[role] == jb.button_index:
				match role:
					"bottom":
						return [jb.device, "accept"]
					"right":
						return [jb.device, "back"]
					"start":
						return [jb.device, "start"]
					"top":
						return [jb.device, "random"]
		return []
	var jm := event as InputEventJoypadMotion
	if jm and (jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y):
		var id := "%d:%d" % [jm.device, jm.axis]
		if absf(jm.axis_value) < 0.3:
			_stick_armed.erase(id)
			return []
		if absf(jm.axis_value) < 0.6 or _stick_armed.has(id):
			return []
		_stick_armed[id] = true
		if jm.axis == JOY_AXIS_LEFT_X:
			return [jm.device, "left" if jm.axis_value < 0.0 else "right"]
		return [jm.device, "up" if jm.axis_value < 0.0 else "down"]
	return []


func _input(event: InputEvent) -> void:
	# Cualquier cosa que toque el jugador reinicia la espera de la demo.
	var moved := event is InputEventJoypadMotion and absf(event.axis_value) > 0.5
	if GameSession.is_any_press(event) or moved or event is InputEventMouseButton:
		_idle_time = 0.0
		# El toque de celular no cuenta (la demo sigue para mostrar el juego).
		if not is_touch(event):
			someone_played = true
	elif event is InputEventMouseMotion and not is_touch(event) and (event as InputEventMouseMotion).relative.length() > 2.0:
		someone_played = true
	if screen == "setup":
		_setup_input(event)
		return
	var read := _read(event)
	if read.is_empty():
		return
	get_viewport().set_input_as_handled()
	var device: int = read[0]
	var action: String = read[1]
	if screen == "title":
		match action:
			"accept", "start":
				_title_accept()
			"back":
				if choosing_count:
					choosing_count = false
					_build()
			"left":
				if choosing_count:
					change_player_count(-1)
			"right":
				if choosing_count:
					change_player_count(1)
	else:
		_players_action(device, action)


## Armá la partida: ENTER / Start arranca; ESC / B vuelve a los personajes. El
## resto lo manejan los botones (foco con flechas / stick).
func _setup_input(event: InputEvent) -> void:
	var read := _read(event)
	if read.is_empty():
		return
	match read[1]:
		"start":
			get_viewport().set_input_as_handled()
			start_race()
		"back":
			get_viewport().set_input_as_handled()
			go_players()


## true si el evento viene de tocar la pantalla (o el mouse que imita el toque).
static func is_touch(event: InputEvent) -> bool:
	return event is InputEventScreenTouch or event is InputEventScreenDrag \
		or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)


func _process(delta: float) -> void:
	if someone_played:
		if _demo_label:
			_demo_label.text = ""
		return
	_idle_time += delta
	var left := IDLE_DEMO_TIME - _idle_time
	if _demo_label:
		_demo_label.text = "Demo en %d s" % ceili(left) if left < 6.0 else ""
	if left <= 0.0:
		_start_demo()
		return


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
		sb.bg_color = Palette.UI_TILE if state != "hover" else Palette.UI_TILE_HOVER
		if selected or state == "pressed":
			sb.bg_color = Palette.UI_TILE_ON
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(5 if selected else 2)
		sb.border_color = YELLOW if selected else Palette.UI_INK
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
