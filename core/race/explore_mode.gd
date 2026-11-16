class_name ExploreMode
extends Node
## Modo libre dentro de un mapa (sin bots): el mapa de siempre, con boyas,
## islas y todo, pero sin cuenta regresiva ni final, para recorrerlo con calma.
## Lo agrega RaceManager cuando la partida es Mode.EXPLORE.
##
## Mientras se juega:
##   - X / RB sube las olas y Z / LB las baja (como en el modo libre).
##   - T / Select prende o apaga la tormenta.
##   - F: las boyas se pueden atravesar o no (para ver más allá de la pista).

var race: RaceManager
var course: Course
var wave_level: int = 3
## true: las boyas no frenan (se puede salir de la pista).
var buoys_open: bool = false


func _ready() -> void:
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
			hud.show_center("Boyas: se atraviesan" if open else "Boyas: normales", Color(0.6, 0.95, 1.0), 1.6)


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
