class_name ExploreMode
extends Node
## Modo libre dentro de un mapa (sin bots): el mapa de siempre, con boyas,
## islas y todo, pero sin cuenta regresiva ni final, para recorrerlo con calma.
## Lo agrega RaceManager cuando la partida es Mode.EXPLORE.
##
## Mientras se juega:
##   - X / RB sube las olas y Z / LB las baja (como en el modo libre).
##   - T / Select prende o apaga la tormenta.
##   - F: modo totalmente libre: las boyas se atraviesan y se puede volar
##     (mantener ESPACIO sube, mantener SHIFT baja; soltando, se queda en el
##     aire a esa altura). Al bajar hasta el agua, vuelve a surfear.

var race: RaceManager
var course: Course
var wave_level: int = 3
## true: las boyas no frenan (se puede salir de la pista) y se puede volar.
var buoys_open: bool = false
## Velocidad al subir o bajar volando (m/s).
const FLY_SPEED := 14.0
## Altura máxima de vuelo (m).
const FLY_MAX := 120.0
## Por surfista: a qué altura vuela (sin entrada: no está volando).
var _fly: Dictionary = {}


func _ready() -> void:
	# Después de la física del surfista: así la altura de vuelo es la última palabra.
	process_physics_priority = 100
	race = get_parent() as RaceManager
	course = race.course
	set_wave_level(GameSettings.sandbox_wave_level, true)


func _waves() -> WaveManager:
	return race.get_parent().get_node_or_null("WaveManager") as WaveManager


## Nivel de las olas: 0 (sin olas grandes) .. SANDBOX_WAVE_LEVELS (como en una
## carrera).
func set_wave_level(level: int, instant: bool = false) -> void:
	wave_level = clampi(level, 0, GameSettings.SANDBOX_WAVE_LEVELS)
	GameSettings.sandbox_wave_level = wave_level
	var waves := _waves()
	if waves:
		waves.set_amplitude_scale(float(wave_level) / GameSettings.SANDBOX_WAVE_LEVELS, instant)


## Prende o apaga la tormenta en el momento.
func set_storm(on: bool) -> void:
	if on == (course.storm != null):
		return
	if on:
		course.storm = Storm.new()
		course.storm.name = "Storm"
		course.add_child(course.storm)
	else:
		course.storm.stop()
		course.storm.queue_free()
		course.storm = null


## Boyas atravesables (true) o normales.
func set_buoys_open(open: bool) -> void:
	buoys_open = open
	course.bounds_enabled = not open
	var views := race.get_parent().get_node_or_null("Views") as SplitScreen
	if views:
		for hud in views.huds:
			hud.show_center("Libre: se vuela (ESPACIO sube, SHIFT baja)" if open else "Boyas: normales", Color(0.6, 0.95, 1.0), 1.8)


## Vuelo (solo con F): ESPACIO sube, SHIFT baja, soltando se queda en el aire.
func _physics_process(delta: float) -> void:
	if not buoys_open:
		_fly.clear()
		return
	var up := Input.is_physical_key_pressed(KEY_SPACE)
	var down := Input.is_physical_key_pressed(KEY_SHIFT)
	for r in race.racers:
		if not r.is_human or r.player_index != 0:
			continue
		if not _fly.has(r):
			if not up:
				continue
			_fly[r] = r.position.y
		var h: float = _fly[r]
		if up:
			h += FLY_SPEED * delta
		if down:
			h -= FLY_SPEED * delta
		h = minf(h, FLY_MAX)
		if h <= 0.6 and not up:
			# Llegó al agua: vuelve a surfear (cae normal).
			_fly.erase(r)
			r.can_trick = true
			continue
		_fly[r] = h
		r.position.y = h
		r.vertical_speed = 0.0
		r.can_trick = false


## true si ese surfista está volando.
func is_flying(r: Rider) -> bool:
	return _fly.has(r)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F:
		set_buoys_open(not buoys_open)
		get_viewport().set_input_as_handled()
		return
	for slot in race.config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if not InputMap.has_action(p + "waves_up"):
			continue
		var handled := true
		if event.is_action_pressed(p + "waves_up"):
			set_wave_level(wave_level + 1)
		elif event.is_action_pressed(p + "waves_down"):
			set_wave_level(wave_level - 1)
		elif event.is_action_pressed(p + "storm"):
			set_storm(course.storm == null)
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
