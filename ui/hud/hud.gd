class_name Hud
extends CanvasLayer
## HUD de un jugador (uno por pantalla): vuelta, posición, nitro, cartel de
## "spamea", cuenta regresiva, mensajes, rayas de velocidad, velocidad y ayuda.
## Se construye por código para que sea fácil de leer y cambiar.

@export var rider_path: NodePath

const PROMPT_COLOR := Color(1.0, 0.86, 0.2)
const NITRO_COLOR := Color(0.25, 0.85, 1.0)
## Turbo en curso: toda la barra en naranja fuerte, con fuego que la consume.
const BURN_COLOR := Color(1.0, 0.45, 0.05)
## Barra llena (3 cargas): roja, vibra y parpadea.
const FULL_COLOR := Color(1.0, 0.12, 0.1)
const NITRO_FIRE_SHADER := preload("res://ui/shaders/nitro_fire.gdshader")
const BAD_COLOR := Color(1.0, 0.4, 0.35)
const SPEED_LINES_SHADER := preload("res://ui/shaders/speed_lines.gdshader")
const SPLASH_SHADER := preload("res://ui/shaders/wave_splash.gdshader")
## Duración del efecto de atravesar una ola (s): golpe de agua y gotas que chorrean.
const SPLASH_TIME := 1.2
## Duración del golpe (cortina de espuma) al principio (s).
const SPLASH_WASH := 0.22

## Se pueden asignar antes de agregar el HUD al árbol (lo hace SplitScreen).
var rider: Rider
## La partida (carrera o modo libre). Lo de carrera (vuelta, posición, cuenta
## regresiva) se pide solo si es una carrera (ver `_race()`).
var session: GameSession
## Mostrar la ayuda al empezar.
var show_help: bool = true
## Demo: muestra "DEMO" y cómo salir.
var demo: bool = false
## Vista chica (pantalla en 4): todo el HUD se dibuja más chico.
var compact: bool = false
## Modo libre: sin vuelta ni posición; muestra el nivel de las olas.
var free_ride: bool = false

## Colores del contador de trucos: cuanto más vueltas, más "caliente".
const TRICK_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.45, 0.9, 1.0),
	Color(0.5, 1.0, 0.5),
	Color(1.0, 0.9, 0.25),
	Color(1.0, 0.6, 0.2),
	Color(1.0, 0.32, 0.3),
	Color(1.0, 0.35, 0.9),
]

const COMPACT_SCALE := 0.6

var _root: Control

var _mash_box: VBoxContainer
var _mash_prompt: ButtonPrompt
var _mash_hint: Label
var _mash_bar: ProgressBar
var _speed_label: Label
var _place_label: Label
var _lap_label: Label
var _name_label: Label
var _center_label: Label
var _help: Label
## Contador de FPS (tecla P). Se recuerda entre carreras.
static var show_fps: bool = false
var _fps_label: Label
var _nitro_bar: ProgressBar
var _message: Label
## Efecto de cámara al atravesar una ola (borroso, gotas, tono de agua).
var splash_overlay: ColorRect
var _splash_material: ShaderMaterial
var _splash_t: float = 0.0
var _speed_lines: ColorRect
var _nitro_label: Label
var _speed_lines_material: ShaderMaterial
var _message_time: float = 0.0
## Contador de vueltas del truco mientras está en el aire (x1, x2...).
var _trick_label: Label
var _trick_pop: float = 0.0
## Modo libre: nivel de las olas (barritas).
var _waves_box: HBoxContainer
var _wave_bars: Array[ColorRect] = []
## Para avisar cuando se cambia la distancia de la cámara con turbo (tecla B).
var _seen_boost_option: int = -1
var _center_time: float = 0.0
var _flash: float = 0.0
var _lines: float = 0.0
## Detrás de la barra de nitro: la carga del turbo en curso, que se consume.
var _burn_bar: ProgressBar
var _burn_fill: StyleBoxFlat
var _nitro_fill: StyleBoxFlat
## Llamas sobre la parte llena de la barra (turbo y barra llena).
var _fire: ColorRect
var _fire_mat: ShaderMaterial
## 0..1: cuánto se ve el turbo / la barra llena (para entrar y salir suave).
var _turbo_look: float = 0.0
## Lo recién ganado (truco, círculo) brilla en blanco un instante: tramo de la
## barra (0..1) y cuánto brilla todavía.
var _gain_glow: ColorRect
var _gain_from: float = 0.0
var _gain_to: float = 0.0
var _gain_flash: float = 0.0
var _last_nitro: float = 0.0
var _full_look: float = 0.0
var _nitro_box: VBoxContainer
## Amague de la barra al apretar turbo cuando no se puede (0..1).
var _blocked: float = 0.0


func _ready() -> void:
	_build()
	if rider == null:
		rider = get_node_or_null(rider_path) as Rider
	if rider:
		_connect_rider()
	var race := _race()
	if race:
		race.countdown_tick.connect(_on_countdown_tick)
		race.lap_started.connect(_on_lap_started)
		race.racer_finished.connect(_on_racer_finished)
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
	_last_nitro = rider.nitro
	rider.nitro_changed.connect(func(value: float, max_value: float) -> void:
		_nitro_bar.value = value / max_value
		_on_nitro_gain(_last_nitro / max_value, value / max_value)
		_last_nitro = value
	)
	rider.trick_landed.connect(_on_trick_landed)
	rider.live_spins_changed.connect(_on_live_spins)
	rider.trick_failed.connect(func() -> void: show_message("¡Truco fallido!", BAD_COLOR))
	rider.drift_hit.connect(func(_victim: Rider) -> void: show_message("¡Lo tiraste!", PROMPT_COLOR))
	rider.turbo_blocked.connect(func() -> void: _blocked = 1.0)
	rider.ring_collected.connect(func() -> void: show_message("+ NITRO", NITRO_COLOR))
	rider.crashed.connect(func() -> void: show_message("¡Pum!", BAD_COLOR))
	rider.popped.connect(func() -> void: show_message("¡POP!", PROMPT_COLOR))
	rider.wave_punched.connect(_on_wave_punched)
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
		pc.jump_mode_changed.connect(func(mode_name: String) -> void:
			show_message("Salto: " + mode_name, Color.WHITE)
			_update_help()
		)


## La carrera, si la partida es una carrera (en el modo libre, null).
func _race() -> RaceManager:
	return session as RaceManager


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


## Contador del truco en el aire: x1, x2... cambia de color al subir.
func _on_live_spins(spins: int) -> void:
	if spins <= 0:
		return
	_trick_label.text = "x%d" % spins
	_trick_label.add_theme_color_override("font_color", trick_color(spins))
	_trick_pop = 1.0


static func trick_color(spins: int) -> Color:
	return TRICK_COLORS[clampi(spins - 1, 0, TRICK_COLORS.size() - 1)]


func _on_countdown_tick(value: int) -> void:
	if value > 0:
		show_center(str(value), Color.WHITE, 0.9)
	else:
		show_center("¡YA!", PROMPT_COLOR, 0.8)


func _on_lap_started(r: Rider, lap: int) -> void:
	if r != rider or lap <= 1:
		return
	if lap == session.config.laps:
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
	# Tecla oculta para probar el efecto de atravesar una ola.
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F8 and rider:
		_on_wave_punched()
		var cam := get_viewport().get_camera_3d() as ChaseCamera
		if cam:
			cam.shake(0.6)


func _process(delta: float) -> void:
	if compact and _root:
		# Más chico: se escala la capa y se agranda la raíz para que ocupe toda la vista.
		scale = Vector2.ONE * COMPACT_SCALE
		_root.size = get_viewport().get_visible_rect().size / COMPACT_SCALE
	if _fps_label:
		_fps_label.visible = show_fps
	if show_fps and _fps_label:
		_fps_label.text = "%d FPS  (%.0f ms)  ·  %d corredores" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			get_tree().get_nodes_in_group("riders").size(),
		]
	if rider == null:
		return
	if _seen_boost_option != ChaseCamera.boost_option:
		if _seen_boost_option >= 0:
			show_message(
				"Cámara turbo %d/%d  (+%.1f m)" % [
					ChaseCamera.boost_option + 1, ChaseCamera.BOOST_PULLBACKS.size(), ChaseCamera.boost_pullback()
				],
				Color.WHITE
			)
		_seen_boost_option = ChaseCamera.boost_option
	_update_splash(delta)
	_update_mash(delta)

	_speed_label.text = "%d km/h" % roundi(rider.speed * 3.6)
	# Handicap: muestra cuánto más rápido carga el nitro.
	var mult := rider.nitro_gain_mult()
	_nitro_label.text = "NITRO ×%.1f" % mult if mult >= 1.15 else "NITRO"
	_name_label.text = rider.display_name

	# Contador del truco: visible mientras gira en el aire; late al sumar una vuelta.
	_trick_label.visible = rider.live_spins > 0 and not rider.grounded
	_trick_pop = move_toward(_trick_pop, 0.0, delta * 4.0)
	_trick_label.pivot_offset = _trick_label.size * 0.5
	_trick_label.scale = Vector2.ONE * (1.0 + 0.45 * _trick_pop * _trick_pop)

	if free_ride:
		_place_label.visible = false
		_lap_label.visible = false
		_waves_box.visible = true
		var level := GameSettings.sandbox_wave_level
		for k in _wave_bars.size():
			_wave_bars[k].color = Color(0.3, 0.85, 1.0) if k < level else Color(0.0, 0.0, 0.0, 0.45)
		_center_label.visible = _center_time > 0.0
	elif _race():
		var race := _race()
		_lap_label.text = "VUELTA %d/%d" % [race.lap_of(rider), race.config.laps]
		_place_label.text = "%dº" % race.place_of(rider)
		if race.is_wrong_way(rider) and _center_time <= 0.0:
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
	_update_turbo_meter(delta)


## Barra de nitro según el turbo:
## - Con turbo en curso: toda la barra en naranja fuerte, con fuego; la carga
##   gastada se consume de a poco y al terminar vuelve al celeste. Mientras
##   tanto otro toque no hace nada (si se aprieta, la barra hace un amague).
## - Llena (3 cargas): roja, vibra y parpadea (nitro al máximo).
func _update_turbo_meter(delta: float) -> void:
	var burning := rider.turbo_time / rider.stats.turbo_burst_time * Rider.TURBO_CHARGE
	_nitro_bar.value = rider.nitro / Rider.NITRO_MAX
	_burn_bar.value = (rider.nitro + burning) / Rider.NITRO_MAX
	var turbo_on := rider.turbo_time > 0.0
	var full := not turbo_on and rider.turbo_charges() >= Rider.TURBO_CHARGES
	# Entra de golpe y se va rápido (a mitad de camino entre celeste y naranja
	# el color queda feo).
	_turbo_look = 1.0 if turbo_on else move_toward(_turbo_look, 0.0, delta * 7.0)
	_full_look = 0.0 if turbo_on else move_toward(_full_look, 1.0 if full else 0.0, delta * 6.0)
	var t := Time.get_ticks_msec() * 0.001
	# Parpadeo de la barra llena (rápido y marcado).
	var blink := 0.5 + 0.5 * sin(t * 18.0)
	var full_color := FULL_COLOR.lerp(Color(1.0, 0.75, 0.6), blink * 0.55)
	var base := NITRO_COLOR.lerp(BURN_COLOR, _turbo_look).lerp(full_color, _full_look)
	_nitro_fill.bg_color = base
	_burn_fill.bg_color = BURN_COLOR.lerp(Color(1.0, 0.7, 0.2), 0.5 + 0.5 * sin(t * 12.0))
	_nitro_label.add_theme_color_override("font_color", base)
	# Fuego: naranja con turbo; rojo y más nervioso con la barra llena.
	var fire := maxf(_turbo_look, _full_look)
	_fire.visible = fire > 0.01
	if _fire.visible:
		_fire_mat.set_shader_parameter("fill", _burn_bar.value)
		_fire_mat.set_shader_parameter("intensity", fire * (0.6 + 0.4 * blink * _full_look))
		_fire_mat.set_shader_parameter("aspect", _burn_bar.size.x / maxf(_burn_bar.size.y, 1.0))
		_fire_mat.set_shader_parameter("cold", Color(0.85, 0.2, 0.02).lerp(Color(0.6, 0.0, 0.02), _full_look))
		_fire_mat.set_shader_parameter("hot", Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.45, 0.35), _full_look))
		_fire_mat.set_shader_parameter("flow", lerpf(3.0, 7.0, _full_look))
	_update_gain_glow(delta)
	_last_nitro = rider.nitro
	_blocked = move_toward(_blocked, 0.0, delta * 4.0)
	# Vibración: amague al apretar de más; temblor fino con la barra llena.
	var shake := sin(_blocked * 18.0) * 4.0 * _blocked
	shake += sin(t * 70.0) * 1.6 * _full_look
	var shake_y := cos(t * 83.0) * 1.0 * _full_look
	_nitro_box.position.x = 24.0 + shake
	_nitro_box.offset_bottom = -20.0 + shake_y
	_nitro_box.offset_top = -80.0 + shake_y


## Ganó nitro de golpe (no el goteo de a poco): ese tramo brilla en blanco.
const GAIN_MIN := 0.02
const GAIN_FLASH_TIME := 0.9


func _on_nitro_gain(before: float, after: float) -> void:
	if after - before < GAIN_MIN:
		return
	# Si todavía brilla una ganancia anterior, se suman en un solo tramo.
	_gain_from = minf(_gain_from, before) if _gain_flash > 0.0 else before
	_gain_to = after
	_gain_flash = 1.0


func _update_gain_glow(delta: float) -> void:
	_gain_flash = maxf(_gain_flash - delta / GAIN_FLASH_TIME, 0.0)
	_gain_glow.visible = _gain_flash > 0.0
	if not _gain_glow.visible:
		return
	# Sigue a la barra: si se gastó nitro, el tramo se corre con ella.
	var to := minf(_gain_to, _nitro_bar.value)
	var from := minf(_gain_from, to)
	_gain_glow.anchor_left = from
	_gain_glow.anchor_right = to
	_gain_glow.color = Color(1.0, 1.0, 1.0, 0.9 * _gain_flash * _gain_flash)


func _update_mash(delta: float) -> void:
	var fallen := rider.is_fallen() and not rider.controls_locked
	_mash_box.visible = fallen
	if not fallen:
		return
	# Una sola barra: a la mitad te subís a la tabla, llena te parás.
	var meter := 0.0
	var state := rider.state_machine.current
	if "meter" in state:
		meter = state.meter
	_mash_bar.value = meter

	_set_prompt(_mash_prompt)
	if rider.recovery_stage == Rider.RecoveryStage.IN_WATER:
		_mash_hint.text = "Súbete a la tabla"
	else:
		_mash_hint.text = "¡Ahora párate!"

	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_mash_prompt.pulse = _flash


## Atravesó una ola que rompía: medio segundo de imagen mojada que se aclara.
func _on_wave_punched() -> void:
	# Cada vista tiene su HUD: también las de los bots en la demo.
	_splash_t = SPLASH_TIME
	_splash_material.set_shader_parameter("seed", randf() * 100.0)


func _update_splash(delta: float) -> void:
	_splash_t = maxf(_splash_t - delta, 0.0)
	splash_overlay.visible = _splash_t > 0.0
	if splash_overlay.visible:
		var elapsed := SPLASH_TIME - _splash_t
		# El golpe: entra de una y se va rápido.
		var wash := 1.0 - smoothstep(0.0, SPLASH_WASH, elapsed - 0.04)
		# Las gotas: quedan y se van de a poco.
		var drops := 1.0 - smoothstep(SPLASH_TIME * 0.45, SPLASH_TIME, elapsed)
		_splash_material.set_shader_parameter("wash", wash)
		_splash_material.set_shader_parameter("drops", drops)
		_splash_material.set_shader_parameter("elapsed", elapsed)


func _using_pad() -> bool:
	var pc := rider.controller as PlayerController
	# Los bots (demo) muestran los íconos de mando.
	return pc == null or pc.using_joypad


## Tecla del botón principal (A) para quien juega con teclado.
func _key_name() -> String:
	if rider.player_index == 1 and GameSettings.player_count >= 2:
		return "ENTER"
	return "ESPACIO"


## Botón de abajo si juega con mando; la tecla si juega con teclado.
func _set_prompt(prompt: ButtonPrompt) -> void:
	if _using_pad():
		prompt.kind = ButtonPrompt.Kind.FACE_BOTTOM
	else:
		prompt.kind = ButtonPrompt.Kind.KEY
		prompt.key_text = _key_name()


func _update_help() -> void:
	var layout := "estándar"
	if rider and rider.controller is PlayerController:
		layout = (rider.controller as PlayerController).layout_name()
	if free_ride:
		_help.text = (
			"MODO LIBRE · mar abierto\n"
			+ "Avanzar: W / stick adelante (soltá y te frenás; lento, remás acostado)\n"
			+ "Girar: A / D o stick   ·   Pop / truco: ESPACIO / botón de abajo\n"
			+ "Turbo: E o botón derecho   ·   Mirar atrás: Q o gatillo izquierdo\n"
			+ "Olas: X sube · Z baja (mando: RB / LB)\n"
			+ "Tormenta: T (mando: Select)\n"
			+ "Circuitos a lo lejos: slalom (rojo), círculos (celeste), géiseres (naranja)\n"
			+ "B: probar distancia de cámara con turbo (1/2/3)\n"
			+ "Esc: menú   ·   H: ocultar ayuda"
		)
		return
	_help.text = (
		"Avanza solo (atrás frena)   ·   Girar: A / D o stick\n"
		+ "Saltar: ESPACIO / botón de abajo\n"
		+ "Salto: %s (O cambia)   ·   Pantalla dividida: V\n" % GameSettings.jump_style_name()
		+ "Truco: en el aire, mantener ESPACIO / botón de abajo\n"
		+ "Derrapar: SHIFT o botón izquierdo / RB   ·   Turbo (tocar, gasta 1 carga): E o botón derecho\n"
		+ "Mirar atrás: Q o gatillo izquierdo\n"
		+ "Levantarse: spamear ESPACIO o botón de abajo   ·   Caerse (prueba): F\n"
		+ "J2: flechas, ENTER salta, . derrapa, - turbo   ·   Esc: menú\n"
		+ "Olas: %s (se cambia en el menú)\n" % GameSettings.wave_mode_name()
		+ "Mando: %s (M cambia)   ·   H: ocultar ayuda   ·   P: FPS\n" % layout
		+ "B: probar distancia de cámara con turbo (1/2/3)\n"
		+ "Si no responde, haz clic en el juego"
	)


func _build() -> void:
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Rayas de velocidad (detrás de todo lo demás).
	# Primero (debajo de los textos): el efecto de salir de la ola.
	splash_overlay = ColorRect.new()
	splash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_material = ShaderMaterial.new()
	_splash_material.shader = SPLASH_SHADER
	splash_overlay.material = _splash_material
	splash_overlay.visible = false
	root.add_child(splash_overlay)

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
	_mash_prompt = ButtonPrompt.new()
	_mash_prompt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mash_prompt.custom_minimum_size = Vector2(200.0, 100.0)
	_mash_box.add_child(_mash_prompt)
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
	_nitro_fill = _nitro_bar.get_theme_stylebox("fill") as StyleBoxFlat
	# Llamas arriba de la parte llena (debajo de las marcas de las cargas).
	_fire = ColorRect.new()
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fire.offset_left = 3.0
	_fire.offset_right = -3.0
	_fire.offset_top = 3.0
	_fire.offset_bottom = -3.0
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = NITRO_FIRE_SHADER
	_fire.material = _fire_mat
	_fire.visible = false
	_nitro_bar.add_child(_fire)
	_gain_glow = ColorRect.new()
	_gain_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gain_glow.anchor_top = 0.0
	_gain_glow.anchor_bottom = 1.0
	_gain_glow.offset_top = 3.0
	_gain_glow.offset_bottom = -3.0
	_gain_glow.visible = false
	_nitro_bar.add_child(_gain_glow)
	_nitro_box = nitro_box
	# Atrás, la carga del turbo que se está usando; adelante, el nitro.
	_burn_bar = _make_bar(BURN_COLOR, 18.0)
	_burn_fill = _burn_bar.get_theme_stylebox("fill") as StyleBoxFlat
	nitro_box.add_child(_burn_bar)
	_burn_bar.add_child(_nitro_bar)
	_nitro_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nitro_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	# La barra tiene 3 cargas de turbo (cada toque gasta una): marcas divisorias.
	for k in range(1, Rider.TURBO_CHARGES):
		var mark := ColorRect.new()
		mark.color = Color(0.0, 0.0, 0.0, 0.85)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = float(k) / Rider.TURBO_CHARGES
		mark.anchor_right = mark.anchor_left
		mark.anchor_top = 0.0
		mark.anchor_bottom = 1.0
		mark.offset_left = -1.5
		mark.offset_right = 1.5
		_nitro_bar.add_child(mark)

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
	# Modo libre: nivel de las olas (barritas de alto creciente).
	_waves_box = HBoxContainer.new()
	_waves_box.alignment = BoxContainer.ALIGNMENT_END
	_waves_box.add_theme_constant_override("separation", 5)
	_waves_box.visible = false
	right_box.add_child(_waves_box)
	var waves_label := _make_label(20, Color.WHITE)
	waves_label.text = "OLAS"
	_waves_box.add_child(waves_label)
	for k in GameSettings.SANDBOX_WAVE_LEVELS:
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(12.0, 10.0 + k * 5.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_waves_box.add_child(bar)
		_wave_bars.append(bar)

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

	# Contador del truco en el aire (x1, x2...), arriba, debajo de los mensajes.
	_trick_label = _make_label(72, Color.WHITE)
	_trick_label.anchor_left = 0.5
	_trick_label.anchor_right = 0.5
	_trick_label.offset_left = -150.0
	_trick_label.offset_right = 150.0
	_trick_label.offset_top = 120.0
	_trick_label.offset_bottom = 210.0
	_trick_label.visible = false
	root.add_child(_trick_label)

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

	# Contador de FPS (P), abajo al centro.
	_fps_label = _make_label(16, Color(1.0, 1.0, 0.6))
	_fps_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_fps_label.offset_top = -34.0
	_fps_label.offset_bottom = -10.0
	_fps_label.offset_left = -200.0
	_fps_label.offset_right = 200.0
	_fps_label.visible = false
	root.add_child(_fps_label)


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
