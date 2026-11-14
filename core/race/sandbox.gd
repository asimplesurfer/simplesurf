class_name Sandbox
extends GameSession
## Modo libre: mar abierto para practicar y pasear. No hay carrera (ni vueltas,
## ni posiciones, ni llegada) ni aceleración automática: se avanza empujando el
## stick y, quieto o lento, se rema acostado en la tabla.
##
## Mientras se juega:
##   - X / RB sube las olas y Z / LB las baja (de 0 = sin olas grandes, a la
##     altura de una carrera).
##   - T / Select prende o apaga la tormenta.
## A lo lejos hay circuitos de práctica (ver SandboxWorld).

var world: SandboxWorld
var storm: Storm = null
var wave_level: int = 3
@export var world_path: NodePath


func default_config() -> RaceConfig:
	return RaceConfig.sandbox()


func config_for_players() -> RaceConfig:
	var c := RaceConfig.sandbox()
	c.weather = config.weather
	return c


func free_ride() -> bool:
	return true


func _ready() -> void:
	world = get_node_or_null(world_path) as SandboxWorld
	_setup_input()
	var n := config.slots.size()
	for i in n:
		# Arranca acostado en la tabla, quieto, mirando hacia el slalom.
		spawn_rider(config.slots[i], Vector3((i - (n - 1) * 0.5) * 6.0, 0.0, 0.0), 0.0, &"paddling")
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.race_started()
	var waves := get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		# Mar abierto: solo olas que aparecen (la ola constante es de la isla).
		waves.set_mode(GameSettings.WaveMode.SURGES)
	set_wave_level(GameSettings.sandbox_wave_level, true)
	set_storm(config.weather == GameSettings.Weather.STORM)


## Todos los surfistas del modo libre: sin aceleración automática, reman.
func _before_add(rider: Rider) -> void:
	rider.free_ride = true


## Nivel de las olas: 0 (sin olas grandes) .. SANDBOX_WAVE_LEVELS (como en una
## carrera). Cambia de a poco.
func set_wave_level(level: int, instant: bool = false) -> void:
	wave_level = clampi(level, 0, GameSettings.SANDBOX_WAVE_LEVELS)
	GameSettings.sandbox_wave_level = wave_level
	var waves := get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		waves.set_amplitude_scale(float(wave_level) / GameSettings.SANDBOX_WAVE_LEVELS, instant)


func storm_on() -> bool:
	return storm != null


## Prende o apaga la tormenta en el momento.
func set_storm(on: bool) -> void:
	if on == storm_on():
		return
	if on:
		storm = Storm.new()
		storm.name = "Storm"
		world.add_child(storm)
	else:
		storm.stop()
		storm.queue_free()
		storm = null


func _unhandled_input(event: InputEvent) -> void:
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if not InputMap.has_action(p + "waves_up"):
			continue
		var handled := true
		if event.is_action_pressed(p + "waves_up"):
			set_wave_level(wave_level + 1)
		elif event.is_action_pressed(p + "waves_down"):
			set_wave_level(wave_level - 1)
		elif event.is_action_pressed(p + "storm"):
			set_storm(not storm_on())
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super(event)
