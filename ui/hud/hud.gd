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
const ControlsHint := preload("res://ui/hud/controls_hint.gd")
## Guía de controles (abajo a la derecha): se ve solo durante la cuenta
## regresiva y los primeros HINT_START segundos de la carrera.
const HINT_START := 20.0
const NITRO_GAUGE_SHADER := preload("res://ui/shaders/nitro_gauge.gdshader")
## Lado del medidor de nitro (la ventanita redonda con el aro).
const NITRO_GAUGE_SIZE := 118.0
const BAD_COLOR := Color(1.0, 0.4, 0.35)
## Reloj del récord en contrarreloj: verde si vamos mejor, rojo si peor
## (los mismos verde y rojo pastel del contador de trucos).
const AHEAD_COLOR := Color(0.5, 1.0, 0.5)
const BEHIND_COLOR := Color(1.0, 0.32, 0.3)
## Tamaño de la señal de ir al revés (px).
const WRONG_WAY_SIZE := 190.0
const SPEED_LINES_SHADER := preload("res://ui/shaders/speed_lines.gdshader")
const SPLASH_SHADER := preload("res://ui/shaders/wave_splash.gdshader")
const TUBE_WARNING_SHADER := preload("res://ui/shaders/tube_warning.gdshader")
## Duración del efecto de atravesar una ola (s): golpe de agua y gotas que chorrean.
const SPLASH_TIME := 1.2
## Duración del golpe (cortina de espuma) al principio (s).
const SPLASH_WASH := 0.22

## Se pueden asignar antes de agregar el HUD al árbol (lo hace SplitScreen).
var rider: Rider
## La partida (carrera o modo libre). Lo de carrera (vuelta, posición, cuenta
## regresiva) se pide solo si es una carrera (ver `_race()`).
var session: GameSession
## Mostrar la ayuda al empezar (escondida: la H la muestra).
var show_help: bool = false
## Demo: muestra "DEMO" y cómo salir.
var demo: bool = false
## Vista chica (pantalla en 4): todo el HUD se dibuja más chico.
var compact: bool = false
## Modo libre: sin vuelta ni posición; muestra el nivel de las olas.
var free_ride: bool = false

## Colores del contador de trucos: van rotando (después del último vuelve al
## primero), así cada vuelta cambia de color aunque sean muchas.
const TRICK_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.45, 0.9, 1.0),
	Color(0.5, 1.0, 0.5),
	Color(1.0, 0.9, 0.25),
	Color(1.0, 0.6, 0.2),
	Color(1.0, 0.32, 0.3),
	Color(1.0, 0.62, 0.93),
]
## Tamaño del contador: x1 en TRICK_FONT, crece parejo hasta x10
## (TRICK_FONT * TRICK_GROW) y de ahí queda igual. Desde x3 tiembla, cada vez
## más (hasta TRICK_SHAKE píxeles en x10): "esto es un montón".
const TRICK_FONT := 90
## Tamaño base de las palabras de la calificación (ver GRADES).
const GRADE_FONT := 72
const TRICK_GROW := 1.5
const TRICK_MAX_AT := 10
const TRICK_SHAKE := 7.0
## Cuánto se baja el centro de los anillos del contador (veces el tamaño de letra).
const TRICK_CENTER_DROP := 0.15
## Dónde va el contador (respecto del centro de arriba de la pantalla).
const TRICK_BOX := Rect2(-320.0, 10.0, 640.0, 190.0)
## Calificación al aterrizar según el combo: [desde cuántos, palabra, color,
## tamaño (veces GRADE_FONT)]. Abajo de la palabra va el combo exacto (×N).
const GRADES := [
	[1, "Bien", Color(1.0, 1.0, 1.0), 0.8],
	[3, "¡Bueno!", Color(0.56, 0.9, 1.0), 0.92],
	[5, "¡Genial!", Color(1.0, 0.88, 0.4), 1.05],
	[8, "¡Bestial!", Color(1.0, 0.63, 0.3), 1.18],
	[12, "¡LEYENDA!", Color(1.0, 0.61, 0.9), 1.32],
]
## Cuánto dura la calificación en pantalla, y lo que tardan las gotas en
## llegar al medidor de nitro.
const GRADE_TIME := 1.6
const DROP_TRAIL_TIME := 0.7

const COMPACT_SCALE := 0.6
## Color de la posición (pastel): oro, plata, bronce y, del 4º en adelante, un
## gris casi blanco.
const PLACE_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.42),
	Color(0.8, 0.86, 0.94),
	Color(0.94, 0.7, 0.52),
	Color(0.9, 0.9, 0.9),
]

var _root: Control

var _mash_box: VBoxContainer
var _mash_prompt: ButtonPrompt
var _mash_hint: Label
var _mash_bar: ProgressBar
var _place_label: Label
var _lap_label: Label
var _center_label: Label
## Ir al revés: señal de prohibido grande y roja (en vez de un texto).
var _wrong_way: Control
## Contrarreloj: el tiempo del récord (arriba de nuestro reloj).
var _record_label: Label
var _help: Label
## Contador de FPS (tecla P). Se recuerda entre carreras.
static var show_fps: bool = false
var _fps_label: Label
var _nitro_bar: ProgressBar
var _message: Label
## Efecto de cámara al atravesar una ola (borroso, gotas, tono de agua).
var splash_overlay: ColorRect
## Tubo: el borde de la pantalla avisa que se está por caer.
var tube_warning: ColorRect
var _tube_warning_mat: ShaderMaterial
var _tube_warning_amount: float = 0.0
var _tube_time: float = 0.0
var _splash_material: ShaderMaterial
var _splash_t: float = 0.0
var _speed_lines: ColorRect
var _nitro_label: Label
var _speed_lines_material: ShaderMaterial
## Modo trucos (ver TrickAttack): reloj, puntos y lo último que sumó, arriba a
## la derecha.
var _tricks_box: VBoxContainer
var _clock_label: Label
var _score_label: Label
var _gain_label: Label
var _gain_time: float = 0.0
## Últimos segundos: el reloj late en rojo.
const CLOCK_WARN := 10.0
## Ola de borde (modo trucos): la barra de equilibrio, abajo al centro.
var _lip_meter: LipMeter
var _message_time: float = 0.0
## Contador de vueltas del truco mientras está en el aire (x1, x2...).
var _trick_label: Label
var _trick_pop: float = 0.0
var _trick_spins: int = 0
var _trick_shake_t: float = 0.0
## Las vueltas del truco en curso (para partir el número si se cae).
var _air_spins: int = 0
## Efectos del contador y de la calificación (se dibujan en _fx): ondas al
## sumar una vuelta, el brillo de los combos grandes, las gotas que van al
## medidor y el número partido que cae.
var _fx: Control
var _ripples: Array = []
var _grade: Label
var _grade_count: Label
var _grade_t: float = -1.0
var _trail: Array = []
var _shards: Array = []
## Modo libre: manteniendo la coma (,) se ve el contador de trucos subiendo
## (x1, x2, x3...) para evaluar su tamaño, sus colores y la fuente.
var _preview_spins: int = 0
var _preview_time: float = 0.0
const PREVIEW_STEP := 0.6
## Modo libre: nivel de las olas (barritas).
var _waves_box: HBoxContainer
var _wave_bars: Array[ColorRect] = []
## Para avisar cuando se cambia la distancia de la cámara con turbo (tecla B).
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
var _hint: Control
## 0 = a la vista, 1 = escondida a la derecha.
var _hint_slide: float = 0.0
var _hint_hold: float = 0.0
## Lo que se ve del nitro: el "ojo de buey" (ver nitro_gauge.gdshader). Las
## barras de arriba quedan ocultas y llevan el estado (cuánto hay, lo que se
## gasta, el brillo de lo ganado), que el medidor dibuja.
var _gauge: ColorRect
var _gauge_mat: ShaderMaterial
## El agua de adentro se mueve con el surfista: inclinación al doblar (resorte,
## se mece), rebote en saltos y caídas, y cuánto se agita.
var _slosh: float = 0.0
var _slosh_v: float = 0.0
var _bob: float = 0.0
var _bob_v: float = 0.0
var _ripple: float = 0.0
var _last_heading: float = 0.0
var _last_y: float = 0.0
var _last_vy: float = 0.0
var _was_grounded: bool = true
var _water_ready: bool = false
## Gotas que salta el agua al caer fuerte: [posición (centro 0, lado 1),
## velocidad, vida que le queda].
var _drops: Array = []
## Espuma acumulada, chorrito al ganar nitro, remolino del turbo, pulso del
## tramo del aro recién completado (y cuál), y cuántas cargas había.
var _foam: float = 0.0
var _stream: float = 0.0
var _swirl: float = 0.0
var _pulse: float = 0.0
var _pulse_seg: int = 0
var _last_charges: int = -1
## De noche el agua brilla en los bordes.
var _night: float = -1.0
## Amague de la barra al apretar turbo cuando no se puede (0..1).
var _blocked: float = 0.0


func _ready() -> void:
	_build()
	if rider == null:
		rider = get_node_or_null(rider_path) as Rider
	if rider:
		_connect_rider()
	var race := _race()
	var tricks := session as TrickAttack
	if tricks:
		tricks.countdown_tick.connect(_on_countdown_tick)
		tricks.scored.connect(_on_scored)
		tricks.finished.connect(func(_score: int, _rank: int) -> void: show_center("¡TIEMPO!", PROMPT_COLOR, 1.5))
		_tricks_box.visible = true
		# Sin nitro: los trucos dan puntos.
		_nitro_box.visible = false
	if race:
		race.countdown_tick.connect(_on_countdown_tick)
		race.lap_started.connect(_on_lap_started)
		race.racer_finished.connect(_on_racer_finished)
	# La ayuda (tecla H) solo en el modo libre: en carrera no se muestra.
	_help.visible = show_help and free_ride
	_update_help()


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
	rider.trick_failed.connect(_on_trick_failed)
	rider.sloppy_landed.connect(func() -> void: show_message("¡Justo!", PROMPT_COLOR))
	rider.drift_hit.connect(func(_victim: Rider) -> void: show_message("¡Lo tiraste!", PROMPT_COLOR))
	rider.turbo_blocked.connect(func() -> void: _blocked = 1.0)
	rider.trick_preview_started.connect(func(trick_name: String, index: int, total: int) -> void:
		show_message("Truco %d/%d: %s" % [index + 1, total, trick_name], Color.WHITE)
	)
	rider.crashed.connect(func() -> void: show_message("¡Pum!", BAD_COLOR))
	rider.wave_punched.connect(_on_wave_punched)
	rider.tube_entered.connect(func() -> void: show_message("¡Al tubo!", PROMPT_COLOR))
	rider.tube_exited.connect(func(success: bool) -> void:
		if success:
			show_center("¡Qué tubo!", PROMPT_COLOR, 1.4)
	)
	rider.lip_entered.connect(func() -> void: show_message("¡En el borde! Mantené el equilibrio", PROMPT_COLOR))
	rider.lip_exited.connect(func(success: bool) -> void:
		if success:
			show_center("¡Ola completa!", PROMPT_COLOR, 1.6)
		else:
			show_message("¡Te caíste del borde!", BAD_COLOR)
	)
	rider.tube_wiped_out.connect(func(lip: bool) -> void:
		show_message("¡Te tapó la ola!" if lip else "¡Te escupió la espuma!", BAD_COLOR)
	)
	var pc := rider.controller as PlayerController
	if pc:
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


## Calificación de un combo: [palabra, color, tamaño].
static func trick_grade(spins: int) -> Array:
	var best: Array = GRADES[0]
	for g in GRADES:
		if spins >= int(g[0]):
			best = g
	return [best[1], best[2], best[3]]


## Al aterrizar: la palabra entra como un sello con el combo exacto abajo, y
## sale un hilito de gotas hacia el medidor de nitro.
func _on_trick_landed(spins: int) -> void:
	if Rider.sloppy_landings() and rider.last_landing_clean:
		show_message("¡Limpio!", AHEAD_COLOR)
	var g := trick_grade(spins)
	var font := roundi(GRADE_FONT * float(g[2]))
	_grade.text = g[0]
	_grade.add_theme_color_override("font_color", g[1])
	_grade.add_theme_font_size_override("font_size", font)
	_style_number(_grade, font)
	_grade_count.text = "×%d" % spins
	# Del mismo color que tenía en el contador (no siempre blanco).
	_grade_count.add_theme_color_override("font_color", trick_color(spins))
	_style_number(_grade_count, 42)
	_grade_t = 0.0
	_air_spins = 0
	# Lo nuevo borra lo viejo (un número partido que todavía caía).
	_shards.clear()
	_ripples.clear()
	_trail.clear()
	for k in 7:
		_trail.append(-k * 0.05)


## Se cayó con trucos encima: el número se parte en dos y cae, en gris.
func _on_trick_failed() -> void:
	show_message("¡Al agua!", BAD_COLOR)
	# Lo nuevo borra lo viejo (la calificación anterior y sus gotas).
	_grade_t = -1.0
	_trail.clear()
	_ripples.clear()
	if _air_spins <= 0:
		return
	var center := _trick_center()
	var text := "×%d" % _air_spins
	var font := roundi(TRICK_FONT * trick_size(_air_spins))
	_shards = [
		{"text": text, "font": font, "pos": center, "vel": Vector2(-90.0, -160.0), "rot": 0.0, "spin": -2.2, "left": true, "t": 0.0},
		{"text": text, "font": font, "pos": center, "vel": Vector2(110.0, -120.0), "rot": 0.0, "spin": 2.6, "left": false, "t": 0.0},
	]
	_air_spins = 0


## Contador del truco en el aire: x1, x2... cambia de color al subir.
func _on_live_spins(spins: int) -> void:
	if spins <= 0:
		return
	_trick_spins = spins
	_trick_label.text = "×%d" % spins
	_trick_label.add_theme_color_override("font_color", trick_color(spins))
	var font := roundi(TRICK_FONT * trick_size(spins))
	_trick_label.add_theme_font_size_override("font_size", font)
	_style_number(_trick_label, font)
	_trick_pop = 1.0
	# Un truco nuevo borra lo que quedaba del anterior.
	if spins == 1:
		_grade_t = -1.0
		_shards.clear()
	# Una onda que sale de atrás del número, como una gota en el agua.
	_ripples.append([0.0, trick_color(spins)])


## Modo libre: mientras se mantiene la coma, el contador sube solo (x1, x2,
## x3...) cada PREVIEW_STEP segundos; al soltarla se va.
func _update_trick_preview(delta: float) -> void:
	if not free_ride or not Input.is_physical_key_pressed(KEY_COMMA):
		_preview_spins = 0
		_preview_time = 0.0
		return
	_preview_time += delta
	var spins := 1 + int(_preview_time / PREVIEW_STEP)
	if spins != _preview_spins:
		_preview_spins = spins
		_on_live_spins(spins)


static func trick_color(spins: int) -> Color:
	return TRICK_COLORS[posmod(spins - 1, TRICK_COLORS.size())]


## Cuánto más grande que x1 se ve el contador (1 en x1, TRICK_GROW desde x10).
static func trick_size(spins: int) -> float:
	var k := clampf(float(spins - 1) / float(TRICK_MAX_AT - 1), 0.0, 1.0)
	return lerpf(1.0, TRICK_GROW, k)


## Cuánto tiembla el contador (0 hasta x2, TRICK_SHAKE píxeles desde x10).
static func trick_shake(spins: int) -> float:
	return TRICK_SHAKE * clampf(float(spins - 2) / float(TRICK_MAX_AT - 2), 0.0, 1.0)


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
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_H and free_ride:
		_help.visible = not _help.visible
	# Tecla oculta para probar el efecto de atravesar una ola.
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F8 and rider and free_ride:
		_on_wave_punched()
		var cam := get_viewport().get_camera_3d() as ChaseCamera
		if cam:
			cam.shake(0.6)




const HINT_WIDTH := 230.0


## La guía de controles: solo en carrera (no en el modo libre ni en la demo).
## A la vista al principio; después se va a la derecha.
func _update_hint(delta: float) -> void:
	var race := _race()
	if race == null or free_ride or demo:
		_hint.visible = false
		return
	_hint.visible = true
	_hint.pad = _using_pad()
	var racing := race.state == RaceManager.State.RACING
	var need := race.state == RaceManager.State.COUNTDOWN or (racing and race.race_time < HINT_START)
	_hint_hold = 0.1 if need else maxf(_hint_hold - delta, 0.0)
	var show := _hint_hold > 0.0 and race.state != RaceManager.State.FINISHED
	_hint_slide = move_toward(_hint_slide, 0.0 if show else 1.0, delta * 2.5)
	var e := _hint_slide * _hint_slide * (3.0 - 2.0 * _hint_slide)
	_hint.offset_left = -20.0 - HINT_WIDTH + e * (HINT_WIDTH + 60.0)
	_hint.offset_right = -20.0 + e * (HINT_WIDTH + 60.0)
	_hint.modulate.a = 1.0 - e


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
	_update_splash(delta)
	_update_tube_warning(delta)
	_update_mash(delta)

	# Handicap: muestra cuánto más rápido carga el nitro.
	var mult := rider.nitro_gain_mult()
	# Al lado del medidor, solo el multiplicador (y solo cuando hay).
	_nitro_label.text = "×%.1f" % mult if mult >= 1.15 else ""
	_nitro_label.visible = mult >= 1.15

	# Contador del truco: visible mientras gira en el aire; late al sumar una vuelta.
	_update_trick_preview(delta)
	_trick_label.visible = (rider.live_spins > 0 and not rider.grounded) or _preview_spins > 0
	if rider.live_spins > 0 and not rider.grounded:
		_air_spins = rider.live_spins
	_trick_pop = move_toward(_trick_pop, 0.0, delta * 2.6)
	_trick_label.pivot_offset = _trick_label.size * 0.5
	# Entra con rebote: grande, se pasa de chico y vuelve (un resorte amortiguado).
	var bounce := 1.0 - _trick_pop
	_trick_label.scale = Vector2.ONE * (1.0 + 0.5 * exp(-7.0 * bounce) * cos(13.0 * bounce) * signf(_trick_pop))
	_update_trick_fx(delta)
	# Temblor: más fuerte cuantas más vueltas (y un golpe extra al sumar una).
	var shake := trick_shake(_trick_spins) * (1.0 + _trick_pop) if _trick_label.visible else 0.0
	_trick_shake_t += delta
	var jitter := Vector2(sin(_trick_shake_t * 61.0) + 0.6 * sin(_trick_shake_t * 97.0),
		cos(_trick_shake_t * 53.0) + 0.6 * sin(_trick_shake_t * 83.0)) * shake * 0.6
	_trick_label.offset_left = TRICK_BOX.position.x + jitter.x
	_trick_label.offset_right = TRICK_BOX.end.x + jitter.x
	_trick_label.offset_top = TRICK_BOX.position.y + jitter.y
	_trick_label.offset_bottom = TRICK_BOX.end.y + jitter.y
	_trick_label.rotation = jitter.x * 0.004

	if session is TrickAttack:
		_update_tricks(delta)
	elif free_ride:
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
		var place := race.place_of(rider)
		_place_label.text = "%dº" % place
		_place_label.add_theme_color_override("font_color", PLACE_COLORS[clampi(place - 1, 0, PLACE_COLORS.size() - 1)])
		if race.time_trial:
			# Contrarreloj: el tiempo en vez del puesto, y el récord a batir.
			var t: float = race.finish_times.get(rider, race.race_time)
			_place_label.text = ResultsPanel.format_time(t)
			_place_label.add_theme_color_override("font_color", Color.WHITE)
			# Arriba de nuestro reloj, chico, el del récord: verde si vamos mejor,
			# rojo si vamos peor (comparado en el mismo punto de la pista).
			var best := race.time_trial.best_time
			_record_label.visible = best > 0.0
			_record_label.text = ResultsPanel.format_time(best)
			var gap: float = race.time_trial.gap()
			var col := Color.WHITE
			if not is_nan(gap):
				col = AHEAD_COLOR if gap <= 0.0 else BEHIND_COLOR
			_record_label.add_theme_color_override("font_color", col)
		var wrong := race.is_wrong_way(rider) and _center_time <= 0.0
		_wrong_way.visible = wrong
		_center_label.visible = _center_time > 0.0 and not wrong

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
	_update_hint(delta)


## Modo trucos: el reloj (para abajo) y los puntos.
func _update_tricks(delta: float) -> void:
	var tricks := session as TrickAttack
	_place_label.visible = false
	_lap_label.visible = false
	_center_label.visible = _center_time > 0.0
	_clock_label.text = TrickAttack.format_clock(tricks.time_left)
	var warn := tricks.state == TrickAttack.State.PLAYING and tricks.time_left <= CLOCK_WARN
	var beat := 1.0 - fposmod(tricks.time_left, 1.0)
	_clock_label.add_theme_color_override("font_color", BEHIND_COLOR if warn else Color.WHITE)
	_clock_label.pivot_offset = _clock_label.size * Vector2(1.0, 0.5)
	_clock_label.scale = Vector2.ONE * (1.0 + 0.18 * exp(-6.0 * beat) if warn else 1.0)
	_score_label.text = "%s pts" % TrickAttack.format_score(tricks.score_of(rider))
	_lip_meter.visible = rider.on_lip()
	if _lip_meter.visible:
		_lip_meter.balance = rider.lip_balance
		_lip_meter.danger = rider.lip_danger
		_lip_meter.time_left = rider.lip_time_left
		_lip_meter.queue_redraw()
	_gain_time = maxf(_gain_time - delta, 0.0)
	_gain_label.modulate.a = clampf(_gain_time / 0.5, 0.0, 1.0)


## Sumó puntos con un truco: "+600" abajo de los puntos (más apagado si el
## aterrizaje fue justo).
func _on_scored(r: Rider, gained: int, _total: int, clean: bool) -> void:
	if r != rider:
		return
	_gain_label.text = "+%s%s" % [TrickAttack.format_score(gained), "" if clean else " (justo)"]
	_gain_label.add_theme_color_override("font_color", AHEAD_COLOR if clean else PROMPT_COLOR)
	_gain_time = 2.0


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
	# El medidor no se pinta entero de naranja con turbo: lo guardado sigue
	# celeste y lo que se está gastando va arriba, en naranja (ver _update_gauge).
	_update_gauge(delta, NITRO_COLOR.lerp(full_color, _full_look), fire, turbo_on)
	_last_nitro = rider.nitro
	_blocked = move_toward(_blocked, 0.0, delta * 4.0)
	# Vibración: amague al apretar de más; temblor fino con la barra llena.
	var shake := sin(_blocked * 18.0) * 4.0 * _blocked
	shake += sin(t * 70.0) * 1.6 * _full_look
	var shake_y := cos(t * 83.0) * 1.0 * _full_look
	_nitro_box.position.x = 24.0 + shake
	_nitro_box.offset_bottom = -12.0 + shake_y
	_nitro_box.offset_top = -12.0 - NITRO_GAUGE_SIZE + shake_y


## El agua del medidor: se inclina hacia afuera de la curva (como el agua en un
## vaso que gira) y se mece al enderezar; en el aire flota, al caer salpica;
## con velocidad se agita. Todo con resortes, a partir de cómo se mueve el
## surfista en este cuadro.
const SLOSH_PER_G := 0.4
const SLOSH_MAX := 0.6
const SLOSH_SPRING := 38.0
const SLOSH_DAMP := 3.2
const BOB_SPRING := 30.0
const BOB_DAMP := 4.0


func _update_gauge(delta: float, base: Color, glow: float, turbo_on: bool) -> void:
	var heading := rider.heading
	var y := rider.position.y
	if not _water_ready or delta <= 0.0:
		_water_ready = true
		_last_heading = heading
		_last_y = y
		_was_grounded = rider.grounded
	if delta > 0.0:
		# Doblar: aceleración de costado (hacia el centro de la curva). El agua
		# se va para afuera: doblando a la izquierda, sube a la derecha.
		var yaw_rate := wrapf(heading - _last_heading, -PI, PI) / delta
		var lateral := rider.speed * yaw_rate
		var target := clampf(lateral / 9.8 * SLOSH_PER_G, -SLOSH_MAX, SLOSH_MAX)
		_slosh_v += ((target - _slosh) * SLOSH_SPRING - _slosh_v * SLOSH_DAMP) * delta
		_slosh += _slosh_v * delta
		# Arriba y abajo: en el aire el agua flota (sube un poco); al caer, la
		# empuja hacia abajo según qué tan fuerte cayó (y después rebota).
		var vy := (y - _last_y) / delta
		var lift := 0.12 if not rider.grounded else 0.0
		if rider.grounded and not _was_grounded:
			var impact := clampf(-_last_vy / 18.0, 0.0, 1.0)
			_bob_v -= impact * 2.2
			_ripple = maxf(_ripple, 0.05 + impact * 0.12)
			_foam = maxf(_foam, impact)
			if impact > 0.25:
				_splash(impact)
		if not rider.grounded and _was_grounded:
			_bob_v += 0.6
		_bob_v += ((lift - _bob) * BOB_SPRING - _bob_v * BOB_DAMP) * delta
		_bob += _bob_v * delta
		_bob = clampf(_bob, -0.5, 0.5)
		_last_vy = vy
		# Agitación: un poco siempre, más con velocidad, al doblar fuerte y con turbo.
		var calm := 0.012 + clampf(rider.speed / 30.0, 0.0, 1.0) * 0.035 + absf(_slosh_v) * 0.01
		if turbo_on:
			calm += 0.03
		_ripple = move_toward(_ripple, calm, delta * 0.25)
		if _ripple < calm:
			_ripple = calm
		# Espuma: se junta en las curvas fuertes y se disuelve sola.
		_foam = clampf(maxf(_foam, absf(_slosh_v) * 0.25) - delta * 0.6, 0.0, 1.0)
		_update_drops(delta)
		# Chorrito al ganar nitro (sigue el brillo de lo ganado).
		_stream = _gain_flash
		# Remolino: entra rápido con el turbo y se va suave.
		_swirl = move_toward(_swirl, 1.0 if turbo_on else 0.0, delta * (4.0 if turbo_on else 1.5))
		_pulse = maxf(_pulse - delta * 2.2, 0.0)
	_last_heading = heading
	_last_y = y
	_was_grounded = rider.grounded
	var ready := rider.turbo_charges()
	if _last_charges >= 0 and ready > _last_charges:
		_pulse = 1.0
		_pulse_seg = ready - 1
	_last_charges = ready
	if _night < 0.0:
		var course := get_tree().get_first_node_in_group("course") as Course
		_night = 1.0 if course and course.time_of_day == GameSettings.TimeOfDay.NIGHT else 0.0
	var charges := float(ready)
	var part := fposmod(rider.nitro / Rider.TURBO_CHARGE, 1.0) if charges < Rider.TURBO_CHARGES else 1.0
	_gauge_mat.set_shader_parameter("size", _gauge.size)
	# El agua llega hasta lo guardado más lo que el turbo todavía está
	# gastando; esa capa de arriba (naranja) se va vaciando, y lo guardado
	# (abajo) sube aparte si se gana nitro mientras tanto.
	_gauge_mat.set_shader_parameter("level", _burn_bar.value if turbo_on else _nitro_bar.value)
	_gauge_mat.set_shader_parameter("stored", _nitro_bar.value)
	_gauge_mat.set_shader_parameter("burn_color", BURN_COLOR)
	_gauge_mat.set_shader_parameter("slope", _slosh)
	_gauge_mat.set_shader_parameter("bob", _bob)
	_gauge_mat.set_shader_parameter("ripple", _ripple)
	_gauge_mat.set_shader_parameter("color", base)
	_gauge_mat.set_shader_parameter("glow", glow)
	_gauge_mat.set_shader_parameter("flash", _gain_glow.color.a if _gain_glow.visible else 0.0)
	_gauge_mat.set_shader_parameter("bubbles", 1.0 if turbo_on or _full_look > 0.5 else 0.0)
	_gauge_mat.set_shader_parameter("boil", _full_look)
	_gauge_mat.set_shader_parameter("foam", _foam)
	_gauge_mat.set_shader_parameter("stream", _stream)
	_gauge_mat.set_shader_parameter("swirl", _swirl)
	_gauge_mat.set_shader_parameter("pulse", _pulse)
	_gauge_mat.set_shader_parameter("pulse_seg", float(_pulse_seg))
	_gauge_mat.set_shader_parameter("night", _night)
	var drops := []
	for k in 4:
		if k < _drops.size():
			var d: Array = _drops[k]
			drops.append(Vector4(d[0].x, d[0].y, 0.014, clampf(d[2] * 3.0, 0.0, 1.0)))
		else:
			drops.append(Vector4.ZERO)
	_gauge_mat.set_shader_parameter("drops", drops)
	_gauge_mat.set_shader_parameter("charges", charges)
	_gauge_mat.set_shader_parameter("charge_part", part)


## Al caer fuerte saltan gotas de la superficie (más cuanto más fuerte).
func _splash(impact: float) -> void:
	var water_r := 0.36
	var level := _nitro_bar.value
	if level <= 0.03:
		return
	for k in 2 + int(impact * 2.0):
		var x := randf_range(-0.14, 0.14)
		var y := (level * 2.0 - 1.0) * water_r + _slosh * x
		_drops.append([Vector2(x, y), Vector2(randf_range(-0.18, 0.18), randf_range(0.45, 0.8) * (0.6 + impact)), 1.0])
	while _drops.size() > 4:
		_drops.pop_front()


## Las gotas suben, caen y se apagan al volver al agua.
func _update_drops(delta: float) -> void:
	var water_r := 0.36
	var surface := (_nitro_bar.value * 2.0 - 1.0) * water_r
	for d in _drops:
		var pos: Vector2 = d[0]
		var vel: Vector2 = d[1]
		vel.y -= 2.6 * delta
		pos += vel * delta
		var life: float = d[2] - delta * 0.6
		if vel.y < 0.0 and pos.y < surface + _slosh * pos.x:
			life = 0.0
		d[0] = pos
		d[1] = vel
		d[2] = life
	_drops = _drops.filter(func(d: Array) -> bool: return d[2] > 0.0)


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


## Tubo: el borde se tiñe cuando está por perder el equilibrio (amarillo y
## después rojo, más fuerte del lado hacia donde se va).
func _update_tube_warning(delta: float) -> void:
	var target := rider.tube_danger if rider.in_tube() else (rider.lip_danger if rider.on_lip() else 0.0)
	_tube_warning_amount = move_toward(_tube_warning_amount, target, delta * 4.0)
	tube_warning.visible = _tube_warning_amount > 0.01
	if not tube_warning.visible:
		return
	_tube_time += delta
	var a := _tube_warning_amount
	_tube_warning_mat.set_shader_parameter("amount", a)
	_tube_warning_mat.set_shader_parameter("color", Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.2, 0.15), smoothstep(0.3, 0.9, a)))
	_tube_warning_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_tube_time * lerpf(6.0, 16.0, a)))
	# Hacia qué lado de la pantalla se va (la pared puede estar a la izquierda o a la derecha).
	var side := 0.0
	var state := rider.state_machine.current
	if rider.on_lip():
		side = signf(rider.lip_balance)
	elif state and state.has_method("wall_on_right_sign"):
		side = signf(rider.tube_balance) * float(state.call("wall_on_right_sign"))
	_tube_warning_mat.set_shader_parameter("side", side)


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
	if pc == null:
		return true
	# Si se unió en el menú, se sabe con qué juega.
	var assigned := InputSetup.assigned_device(rider.player_index)
	if assigned == InputSetup.KEYBOARD:
		return false
	if assigned >= 0:
		return true
	return pc.using_joypad


## Tecla del botón principal (A) para quien juega con teclado.
func _key_name() -> String:
	if InputSetup.has_assignments():
		return "ESPACIO"
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
	if free_ride and session is RaceManager:
		# Modo libre dentro de un mapa (sin bots): ver ExploreMode.
		_help.text = (
			"MODO LIBRE · %s\n" % (session as RaceManager).course.map.name.to_upper()
			+ "Avanzar: W / stick adelante (soltá y te frenás; lento, remás acostado)\n"
			+ "Girar: A / D o stick   ·   Pop / truco: ESPACIO / botón de abajo\n"
			+ "Frenar: S / stick atrás   ·   Turbo: E o botón derecho   ·   Mirar atrás: Q o gatillo izquierdo\n"
			+ "Olas: X sube · Z baja (mando: RB / LB)   ·   Tormenta: T (mando: Select)\n"
			+ "F: totalmente libre (se atraviesan las boyas y se vuela: ESPACIO sube, SHIFT baja)\n"
			+ "G: ver los trucos uno por uno (cámara lenta)   ·   , (mantener): ver el contador de trucos\n"
			+ "Esc / Start: pausa (volumen)   ·   C: menú   ·   H: ocultar ayuda"
		)
		return
	if free_ride:
		_help.text = (
			"MODO LIBRE · mar abierto\n"
			+ "Avanzar: W / stick adelante (soltá y te frenás; lento, remás acostado)\n"
			+ "Girar: A / D o stick   ·   Pop / truco: ESPACIO / botón de abajo\n"
			+ "Frenar: S / stick atrás   ·   Turbo: E o botón derecho   ·   Mirar atrás: Q o gatillo izquierdo\n"
			+ "Olas: X sube · Z baja (mando: RB / LB)\n"
			+ "Tormenta: T (mando: Select)\n"
			+ "Circuitos a lo lejos: slalom (rojo), círculos (celeste), géiseres (naranja)\n"
			+ "G: ver los trucos uno por uno (cámara lenta)   ·   , (mantener): ver el contador de trucos\n"
			+ "Esc / Start: pausa (volumen)   ·   C: menú   ·   H: ocultar ayuda"
		)
		return
	_help.text = (
		"Avanza solo   ·   Girar: A / D o stick\n"
		+ "Saltar: ESPACIO / botón de abajo (pop en la ola)\n"
		+ "Truco: en el aire, mantener ESPACIO / botón de abajo\n"
		+ "Derrapar (frena y tira a los de atrás): S / stick atrás / botón izquierdo / RB\n"
		+ "Turbo (tocar, gasta 1 carga): E o botón derecho   ·   Mirar atrás: Q o gatillo izquierdo\n"
		+ "Levantarse: spamear ESPACIO o botón de abajo\n"
		+ "Esc / Start: pausa (volumen)   ·   P: FPS\n"
		+ "Si no responde, haz clic en el juego   ·   %s" % BuildInfo.label()
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

	tube_warning = ColorRect.new()
	tube_warning.set_anchors_preset(Control.PRESET_FULL_RECT)
	tube_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tube_warning_mat = ShaderMaterial.new()
	_tube_warning_mat.shader = TUBE_WARNING_SHADER
	tube_warning.material = _tube_warning_mat
	tube_warning.visible = false
	root.add_child(tube_warning)

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
	nitro_box.offset_top = -12.0 - NITRO_GAUGE_SIZE
	nitro_box.offset_bottom = -12.0
	nitro_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(nitro_box)
	var gauge_row := HBoxContainer.new()
	gauge_row.add_theme_constant_override("separation", 4)
	nitro_box.add_child(gauge_row)
	_gauge = ColorRect.new()
	_gauge.custom_minimum_size = Vector2(NITRO_GAUGE_SIZE, NITRO_GAUGE_SIZE)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_mat = ShaderMaterial.new()
	_gauge_mat.shader = NITRO_GAUGE_SHADER
	_gauge_mat.set_shader_parameter("charge_count", float(Rider.TURBO_CHARGES))
	_gauge.material = _gauge_mat
	gauge_row.add_child(_gauge)
	var nitro_label := _make_label(20, NITRO_COLOR)
	_nitro_label = nitro_label
	nitro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nitro_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nitro_label.text = ""
	nitro_label.visible = false
	gauge_row.add_child(nitro_label)
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
	_burn_bar.visible = false
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

	# Arriba a la izquierda: la silueta del mapa y, abajo, la vuelta.
	var left_box := VBoxContainer.new()
	left_box.offset_left = 20.0
	left_box.offset_right = 300.0
	left_box.offset_top = 14.0
	left_box.offset_bottom = 420.0
	left_box.add_theme_constant_override("separation", 2)
	left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_box)
	var minimap := TrackMinimap.new()
	minimap.name = "Minimap"
	minimap.hud = self
	var side := 120.0 if compact else 180.0
	minimap.custom_minimum_size = Vector2(side, side)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_box.add_child(minimap)
	_lap_label = _make_label(26, Color.WHITE)
	_lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left_box.add_child(_lap_label)

	# Arriba a la derecha: en el modo libre, el nivel de olas.
	var right_box := VBoxContainer.new()
	right_box.anchor_left = 1.0
	right_box.anchor_right = 1.0
	right_box.offset_left = -260.0
	right_box.offset_right = -20.0
	right_box.offset_top = 14.0
	right_box.offset_bottom = 120.0
	root.add_child(right_box)
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

	# Modo trucos: reloj y puntos, arriba a la derecha.
	_tricks_box = VBoxContainer.new()
	_tricks_box.anchor_left = 1.0
	_tricks_box.anchor_right = 1.0
	_tricks_box.offset_left = -340.0
	_tricks_box.offset_right = -24.0
	_tricks_box.offset_top = 12.0
	_tricks_box.offset_bottom = 200.0
	_tricks_box.add_theme_constant_override("separation", -4)
	_tricks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tricks_box.visible = false
	root.add_child(_tricks_box)
	_clock_label = _make_label(64, Color.WHITE)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_number(_clock_label, 64)
	_tricks_box.add_child(_clock_label)
	_score_label = _make_label(40, PROMPT_COLOR)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_number(_score_label, 40)
	_tricks_box.add_child(_score_label)
	_gain_label = _make_label(30, AHEAD_COLOR)
	_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gain_label.modulate.a = 0.0
	_style_number(_gain_label, 30)
	_tricks_box.add_child(_gain_label)

	# Modo trucos: la barra de equilibrio de la ola de borde, abajo al centro.
	_lip_meter = LipMeter.new()
	_lip_meter.anchor_left = 0.5
	_lip_meter.anchor_right = 0.5
	_lip_meter.anchor_top = 1.0
	_lip_meter.anchor_bottom = 1.0
	_lip_meter.offset_left = -LipMeter.WIDTH * 0.5 - 20.0
	_lip_meter.offset_right = LipMeter.WIDTH * 0.5 + 20.0
	_lip_meter.offset_top = -150.0
	_lip_meter.offset_bottom = -40.0
	_lip_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lip_meter.visible = false
	root.add_child(_lip_meter)

	# Abajo a la derecha: la posición (oro, plata, bronce o gris).
	_place_label = _make_label(64, PLACE_COLORS[0])
	_place_label.anchor_left = 1.0
	_place_label.anchor_right = 1.0
	_place_label.anchor_top = 1.0
	_place_label.anchor_bottom = 1.0
	_place_label.offset_left = -300.0
	_place_label.offset_right = -20.0
	_place_label.offset_top = -112.0
	_place_label.offset_bottom = -12.0
	_place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_style_number(_place_label, 64)
	root.add_child(_place_label)
	# Contrarreloj: el reloj del récord, chico, arriba del nuestro.
	_record_label = _make_label(30, Color.WHITE)
	_record_label.anchor_left = 1.0
	_record_label.anchor_right = 1.0
	_record_label.anchor_top = 1.0
	_record_label.anchor_bottom = 1.0
	_record_label.offset_left = -300.0
	_record_label.offset_right = -22.0
	_record_label.offset_top = -152.0
	_record_label.offset_bottom = -104.0
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_record_label.visible = false
	_style_number(_record_label, 30)
	root.add_child(_record_label)
	# Arriba del puesto: la guía de controles (ver _update_hint).
	_hint = ControlsHint.new()
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -20.0 - HINT_WIDTH
	_hint.offset_right = -20.0
	_hint.offset_top = -158.0 - _hint.custom_minimum_size.y
	_hint.offset_bottom = -158.0
	root.add_child(_hint)

	# Mensajes (truco, nitro...), arriba al centro.
	_message = _make_label(40, NITRO_COLOR)
	_message.anchor_left = 0.5
	_message.anchor_right = 0.5
	_message.offset_left = -300.0
	_message.offset_right = 300.0
	_message.offset_top = 70.0
	_message.visible = false
	root.add_child(_message)

	# Contador del truco en el aire (x1, x2...), arriba (centrado en TRICK_BOX:
	# crece hacia todos lados).
	_trick_label = _make_label(TRICK_FONT, Color.WHITE)
	_trick_label.anchor_left = 0.5
	_trick_label.anchor_right = 0.5
	_trick_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_trick_label.offset_left = TRICK_BOX.position.x
	_trick_label.offset_right = TRICK_BOX.end.x
	_trick_label.offset_top = TRICK_BOX.position.y
	_trick_label.offset_bottom = TRICK_BOX.end.y
	_trick_label.visible = false
	_style_number(_trick_label, TRICK_FONT)
	# Efectos del contador (atrás del número) y la calificación al aterrizar.
	_fx = FxLayer.new()
	_fx.hud = self
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fx)
	root.add_child(_trick_label)
	_grade = _make_label(GRADE_FONT, Color.WHITE)
	_grade_count = _make_label(42, Color.WHITE)
	for l in [_grade, _grade_count]:
		l.anchor_left = 0.5
		l.anchor_right = 0.5
		l.offset_left = TRICK_BOX.position.x
		l.offset_right = TRICK_BOX.end.x
		l.visible = false
		root.add_child(l)
	# Los mensajes ("¡Al agua!") van por delante del contador y del número partido.
	_message.move_to_front()

	# Cartel grande al centro (cuenta regresiva, vuelta, llegada, al revés).
	_center_label = _make_label(84, Color.WHITE)
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.offset_left = -400.0
	_center_label.offset_right = 400.0
	_center_label.offset_top = -80.0
	_center_label.offset_bottom = 20.0
	_center_label.visible = false
	root.add_child(_center_label)
	_wrong_way = preload("res://ui/hud/no_entry_sign.gd").new()
	_wrong_way.set_anchors_preset(Control.PRESET_CENTER)
	_wrong_way.offset_left = -WRONG_WAY_SIZE * 0.5
	_wrong_way.offset_right = WRONG_WAY_SIZE * 0.5
	_wrong_way.offset_top = -WRONG_WAY_SIZE * 0.5 - 40.0
	_wrong_way.offset_bottom = WRONG_WAY_SIZE * 0.5 - 40.0
	_wrong_way.visible = false
	root.add_child(_wrong_way)

	# Ayuda de controles, arriba a la izquierda.
	_help = _make_label(15, Color.WHITE)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help.position = Vector2(20.0, 250.0)
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


## Los números de trucos: contorno fino y una sombra suave abajo (en vez del
## contorno negro grueso).
static func _style_number(label: Label, font_size: int) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.13, 0.2))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 11))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.3))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(3, font_size / 18))
	label.add_theme_constant_override("shadow_outline_size", maxi(6, font_size / 7))


## Centro del contador de trucos (en el espacio de _fx). Las cifras quedan un
## poco más abajo que el centro del recuadro de la letra (que deja lugar
## arriba para los acentos): se baja para que los anillos queden centrados.
func _trick_center() -> Vector2:
	var fsize := float(_trick_label.get_theme_font_size("font_size")) * _trick_label.get_global_transform().get_scale().y
	return (_trick_label.get_global_rect().get_center() + Vector2(0.0, fsize * TRICK_CENTER_DROP)) * _fx.get_global_transform()


## Animaciones del contador y de la calificación (lo que dibuja _fx lo pinta
## _draw_fx).
func _update_trick_fx(delta: float) -> void:
	for r in _ripples:
		r[0] += delta / 0.55
	_ripples = _ripples.filter(func(r: Array) -> bool: return r[0] < 1.0)
	# Calificación: sello (grande -> su tamaño de golpe), quieta, y al final sube
	# y se desvanece.
	_grade.visible = _grade_t >= 0.0
	_grade_count.visible = _grade.visible
	if _grade_t >= 0.0:
		_grade_t += delta
		var stamp := clampf(_grade_t / 0.16, 0.0, 1.0)
		var s := lerpf(2.1, 1.0, 1.0 - pow(1.0 - stamp, 3.0))
		if stamp >= 1.0:
			var after := _grade_t - 0.16
			s = 1.0 + 0.07 * exp(-14.0 * after) * cos(30.0 * after)
		var fade := clampf((GRADE_TIME - _grade_t) / 0.35, 0.0, 1.0)
		var rise := (1.0 - fade) * 26.0
		for l in [_grade, _grade_count]:
			l.pivot_offset = l.size * 0.5
			l.scale = Vector2.ONE * s
			l.modulate.a = fade * clampf(_grade_t / 0.06, 0.0, 1.0)
		_grade.position.y = GRADE_TOP - rise
		_grade_count.position.y = GRADE_TOP + _grade.size.y * 0.78 - rise
		if _grade_t >= GRADE_TIME:
			_grade_t = -1.0
	for k in _trail.size():
		_trail[k] += delta / DROP_TRAIL_TIME
	_trail = _trail.filter(func(v: float) -> bool: return v < 1.0)
	for sh in _shards:
		sh["t"] += delta
		sh["vel"].y += 900.0 * delta
		sh["pos"] += sh["vel"] * delta
		sh["rot"] += sh["spin"] * delta
	_shards = _shards.filter(func(sh: Dictionary) -> bool: return sh["t"] < 1.3)
	_fx.queue_redraw()


## Dónde arranca la calificación (arriba, centrada).
const GRADE_TOP := 22.0


func _draw_fx() -> void:
	var font := ThemeDB.fallback_font
	var center := _trick_center()
	# Brillo detrás del número: suave desde ×5; desde ×10 un resplandor que late.
	if _trick_label.visible and _trick_spins >= 5:
		var col := trick_color(_trick_spins)
		var big := _trick_spins >= TRICK_MAX_AT
		var t := Time.get_ticks_msec() * 0.001
		var radius := _trick_label.get_theme_font_size("font_size") * (1.05 if big else 0.8)
		var strength := (0.32 + 0.12 * sin(t * 7.0)) if big else 0.2
		for i in 10:
			var f := 1.0 - i / 10.0
			_fx.draw_circle(center, radius * f, Color(col.r, col.g, col.b, strength * 0.12 * (1.0 - f * 0.5)))
	# Ondas.
	for r in _ripples:
		var k: float = r[0]
		var col: Color = r[1]
		var radius := lerpf(40.0, 150.0, 1.0 - pow(1.0 - k, 2.0))
		_fx.draw_arc(center, radius, 0.0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - k) * 0.55), 3.0 * (1.0 - k) + 1.0, true)
	# Gotas que van de la calificación al medidor de nitro (en el modo trucos,
	# a los puntos).
	if not _trail.is_empty():
		var from := _grade_count.get_global_rect().get_center() * _fx.get_global_transform()
		var target: Control = _score_label if _tricks_box.visible else _gauge
		var to := target.get_global_rect().get_center() * _fx.get_global_transform()
		var mid := Vector2(lerpf(from.x, to.x, 0.25), lerpf(from.y, to.y, 0.15) - 40.0)
		for v in _trail:
			if v <= 0.0:
				continue
			var e: float = v * v * (3.0 - 2.0 * v)
			var p := from.lerp(mid, e).lerp(mid.lerp(to, e), e)
			var a: float = clampf(v * 6.0, 0.0, 1.0) * clampf((1.0 - v) * 8.0, 0.0, 1.0)
			_fx.draw_circle(p, 5.0, Color(0.05, 0.13, 0.2, 0.5 * a))
			_fx.draw_circle(p, 3.6, Color(0.78, 0.95, 1.0, a))
	# El número partido que cae: cada mitad (los primeros caracteres y el
	# resto) por su lado, girando, en gris.
	for sh in _shards:
		var fsize: int = sh["font"]
		var text: String = sh["text"]
		var cut := ceili(text.length() / 2.0)
		var part := text.substr(0, cut) if sh["left"] else text.substr(cut)
		var w := font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var a := clampf((1.3 - float(sh["t"])) / 0.4, 0.0, 1.0)
		var at := Vector2(-w if sh["left"] else 0.0, fsize * 0.35)
		_fx.draw_set_transform(sh["pos"], sh["rot"], Vector2.ONE)
		_fx.draw_string_outline(font, at, part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(4, fsize / 11),
			Color(0.1, 0.13, 0.16, a))
		_fx.draw_string(font, at, part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.62, 0.65, 0.69, a))
		_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## Capa donde se dibujan los efectos de los trucos (ver Hud._draw_fx).
class FxLayer extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud:
			hud._draw_fx()
