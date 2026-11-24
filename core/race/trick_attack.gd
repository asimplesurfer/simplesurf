class_name TrickAttack
extends GameSession
## Modo trucos: hacer la mayor cantidad de puntos con trucos antes de que se
## termine el tiempo (cuenta para abajo; por defecto 2 minutos).
##
## - Los trucos dan puntos, no nitro (no hay turbo). La motivación sí queda
##   (derrapar y tirar al de atrás te da velocidad).
## - Más combo vale más que proporcional (ver `points_for`). Aterrizaje limpio:
##   todo; justo: menos (TIGHT_MULT). Si te caés, perdés los puntos de ese salto.
## - Al terminar: el puntaje y los mejores del mapa (con ese tiempo).
##
## Por ahora se juega solo (J1). Pensado para después: bots y otros jugadores
## (un puntaje por surfista: `scores` ya va por surfista), el clima que cambia
## durante la partida y olas de distintos tamaños (`set_wave_level`).

signal countdown_tick(value: int)
signal started
## Sumó puntos (gained) con un truco; total es lo que lleva.
signal scored(rider: Rider, gained: int, total: int, clean: bool)
## Se terminó el tiempo. rank: puesto entre los mejores (-1 = no entró).
signal finished(score: int, rank: int)

enum State { COUNTDOWN, PLAYING, FINISHED }

## Puntos por cada tiempo de truco (×1). Ver `points_for`.
const BASE_POINTS := 100
## Aterrizaje justo: esta parte de los puntos.
const TIGHT_MULT := 0.5
const COUNTDOWN_TIME := 3.0
## Nivel de olas (como el del modo libre, de 0 a SANDBOX_WAVE_LEVELS).
const WAVE_LEVEL := 3
## Récords: los mejores TOP puntajes de cada mapa y duración.
const SAVE_PATH := "user://trucos.cfg"
const TOP := 3

@export var world_path: NodePath

var state: State = State.COUNTDOWN
## Segundos que quedan (cuenta para abajo).
var time_left: float = 120.0
## Puntos de cada surfista.
var scores: Dictionary = {}
## Mejores puntajes del mapa con esta duración (al terminar, ya con el nuevo).
var top: Array = []
var world: Node3D
var _countdown: float = COUNTDOWN_TIME
var _last_tick: int = -1


func default_config() -> RaceConfig:
	return RaceConfig.tricks()


func config_for_players() -> RaceConfig:
	return RaceConfig.tricks()


func _ready() -> void:
	world = get_node_or_null(world_path) as Node3D
	_setup_input()
	time_left = float(config.trick_seconds)
	top = top_scores(map_id(), config.trick_seconds)
	var tw := world as TrickWorld
	var n := config.slots.size()
	for i in n:
		var spot: Array = tw.spawn_point(i, n) if tw else [Vector3(i * 6.0, 0.0, 0.0), 0.0]
		var r := spawn_rider(config.slots[i], spot[0], spot[1], &"riding")
		scores[r] = 0
		r.controls_locked = true
		r.trick_landed.connect(_on_trick_landed.bind(r))
	var waves := get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		waves.set_mode(GameSettings.WaveMode.SURGES)
	set_wave_level(WAVE_LEVEL, true)
	DayTime.apply(get_parent(), config.time_of_day)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.race_started()
		audio.connect_race(self)


## Sin nitro (los trucos dan puntos).
func _before_add(rider: Rider) -> void:
	rider.nitro_enabled = false


## Nombre interno del mapa (para los récords).
func map_id() -> String:
	return String(TrickWorld.map_for(config.trick_map).id)


## Tamaño de las olas: 0 (sin olas grandes) .. SANDBOX_WAVE_LEVELS.
func set_wave_level(level: int, instant: bool = false) -> void:
	var waves := get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		var l := clampi(level, 0, GameSettings.SANDBOX_WAVE_LEVELS)
		waves.set_amplitude_scale(float(l) / GameSettings.SANDBOX_WAVE_LEVELS, instant)


## Puntos de un salto con `spins` tiempos de truco: cada tiempo vale más que
## el anterior (×1 = 100, ×2 = 300, ×3 = 600, ×5 = 1500, ×10 = 5500). Con
## aterrizaje justo, la mitad.
static func points_for(spins: int, clean: bool) -> int:
	if spins <= 0:
		return 0
	var p := BASE_POINTS * spins * (spins + 1) / 2
	return p if clean else roundi(p * TIGHT_MULT)


func score_of(rider: Rider) -> int:
	return int(scores.get(rider, 0))


func _on_trick_landed(spins: int, rider: Rider) -> void:
	if state != State.PLAYING:
		return
	var clean := rider.last_landing_clean
	var gained := points_for(spins, clean)
	scores[rider] = score_of(rider) + gained
	scored.emit(rider, gained, score_of(rider), clean)


## En pasos fijos: la cuenta regresiva y el reloj, igual con cualquier FPS.
func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown -= delta
			var tick := ceili(_countdown)
			if tick != _last_tick and tick > 0:
				_last_tick = tick
				countdown_tick.emit(tick)
			if _countdown <= 0.0:
				start()
		State.PLAYING:
			time_left = maxf(time_left - delta, 0.0)
			if time_left <= 0.0:
				finish()


## Arranca (termina la cuenta regresiva).
func start() -> void:
	if state != State.COUNTDOWN:
		return
	state = State.PLAYING
	for r in racers:
		r.controls_locked = false
	countdown_tick.emit(0)
	started.emit()


## Se terminó el tiempo: todos quietos, se guarda el puntaje.
func finish() -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	time_left = 0.0
	for r in racers:
		r.controls_locked = true
	var people := humans()
	var score := score_of(people[0]) if not people.is_empty() else 0
	var rank := save_score(map_id(), config.trick_seconds, score)
	top = top_scores(map_id(), config.trick_seconds)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play("finish", -1.0)
	finished.emit(score, rank)


# ---------------------------------------------------------------- récords

static func _key(id: String, seconds: int) -> String:
	return "%s_%d" % [id, seconds]


## Los mejores puntajes de un mapa con esa duración (de mayor a menor).
static func top_scores(id: String, seconds: int) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return []
	var list: Variant = cfg.get_value("top", _key(id, seconds), [])
	return (list as Array).duplicate() if list is Array else []


## Guarda un puntaje. Devuelve su puesto entre los mejores (-1 si no entró).
static func save_score(id: String, seconds: int, score: int) -> int:
	if score <= 0:
		return -1
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var list: Array = top_scores(id, seconds)
	var rank := list.size()
	for i in list.size():
		if score > int(list[i]):
			rank = i
			break
	if rank >= TOP:
		return -1
	list.insert(rank, score)
	list.resize(mini(list.size(), TOP))
	cfg.set_value("top", _key(id, seconds), list)
	cfg.save(SAVE_PATH)
	return rank


## El puntaje con separador de miles (12.400).
static func format_score(score: int) -> String:
	var s := str(absi(score))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if score < 0 else "") + s + out


## El reloj en minutos y segundos (1:05). Redondea para arriba: muestra 0:00
## recién cuando se terminó.
static func format_clock(t: float) -> String:
	var s := ceili(maxf(t, 0.0) - 0.0001)
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- teclas

## Teclas: la pausa y el FPS, como en carrera; al terminar, R / Start: otra
## vez y C: al menú. (Sin teclas de prueba: el visor de trucos o la cámara
## lenta harían trampa; tampoco cambiar la cantidad de jugadores, por ahora.)
func _handle_common_key(key: InputEventKey) -> bool:
	if state == State.FINISHED:
		match key.physical_keycode:
			KEY_R, KEY_ENTER, KEY_KP_ENTER:
				restart()
				return true
			KEY_C:
				back_to_menu()
				return true
	return super(key)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		_handle_common_key(key)
		return
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if InputMap.has_action(p + "start") and event.is_action_pressed(p + "start"):
			if state == State.FINISHED:
				restart()
			else:
				toggle_pause()
			return
