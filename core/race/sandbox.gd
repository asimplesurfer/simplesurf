class_name Sandbox
extends RaceManager
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


func _ready() -> void:
	add_to_group("race_manager")
	GameSettings.load_settings()
	GameSettings.sandbox_mode = true
	if config == null:
		config = RaceConfig.create(GameSettings.player_count, 0, 0)
	config.laps = 1
	world = get_node_or_null(course_path) as SandboxWorld
	for slot in config.slots:
		InputSetup.ensure_player_actions(slot.player_index)
	InputSetup.apply_keyboard_layout(config.slots.size())
	_spawn_free()
	state = State.RACING
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.race_started()
	var waves := get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		# Mar abierto: solo olas que aparecen (la ola constante es de la isla).
		waves.set_mode(GameSettings.WaveMode.SURGES)
	set_wave_level(GameSettings.sandbox_wave_level, true)
	set_storm(GameSettings.weather == GameSettings.Weather.STORM)


func _spawn_free() -> void:
	var parent := get_node_or_null(riders_path)
	if parent == null:
		parent = self
	var n := config.slots.size()
	for i in n:
		var slot := config.slots[i]
		var rider: Rider = RIDER_SCENE.instantiate()
		rider.name = slot.display_name
		rider.player_index = slot.player_index
		rider.display_name = slot.display_name
		rider.is_human = true
		rider.free_ride = true
		(rider.get_node("Visual") as RiderVisual).character = slot.character
		# Arranca acostado en la tabla, quieto, mirando hacia el slalom.
		(rider.get_node("StateMachine") as RiderStateMachine).initial_state = &"paddling"
		rider.position = Vector3((i - (n - 1) * 0.5) * 6.0, 0.0, 0.0)
		parent.add_child(rider)
		racers.append(rider)


func free_ride() -> bool:
	return true


func _physics_process(_delta: float) -> void:
	pass


func lap_of(_r: Rider) -> int:
	return 1


func place_of(_r: Rider) -> int:
	return 1


func is_wrong_way(_r: Rider) -> bool:
	return false


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
