extends Node
## Música de fondo y volumen dinámico (autoload "AudioManager").
##
## - La música suena durante la carrera (y la demo), en bucle, y sigue sonando
##   entre carreras sin cortarse.
## - Volumen épico: si una persona pasa mucho tiempo en el aire, la música sube;
##   al volver al agua, baja de nuevo. Con pantalla dividida manda el que más
##   tiempo lleva en el aire. Los bots no cuentan.
## Los Riders no conocen el audio: esto solo mira su estado.

## Se carga al arrancar (no con preload, para no depender del orden de importación).
const MUSIC_PATH := "res://assets/audio/simple_surf.ogg"
const NORMAL_DB := -8.0
const EPIC_DB := -1.0
const MENU_DB := -16.0
## Segundos en el aire para que empiece a subir la música.
const EPIC_AIRTIME := 0.5

var player: AudioStreamPlayer
## Volumen objetivo actual (se suaviza).
var target_db: float = NORMAL_DB
## true mientras la música está en modo épico.
var epic: bool = false

var _airtime: Dictionary = {}
var _in_race: bool = false

## Efectos de sonido (assets/audio/sfx/<nombre>.wav, generados con tools/make_sfx.py).
const SFX_NAMES := [
	"splash", "wave_punch", "pop", "hop", "land", "turbo", "ring", "trick_ok", "trick_fail",
	"crash", "bonk", "mash", "beep", "go", "lap", "finish",
]
const SFX_VOICES := 16
## Más allá de esta distancia a un jugador, los sonidos de otros no se escuchan (m).
const SFX_RANGE := 70.0
var _sfx: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
## Mar de fondo, siempre sonando bajito.
var ocean: AudioStreamPlayer
## Último efecto que sonó (para los tests).
var last_sfx: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	var music := load(MUSIC_PATH) as AudioStreamOggVorbis
	if music:
		var stream: AudioStreamOggVorbis = music.duplicate()
		stream.loop = true
		player.stream = stream
	player.volume_db = -40.0
	add_child(player)

	for sfx_name in SFX_NAMES:
		var stream := load("res://assets/audio/sfx/%s.wav" % sfx_name) as AudioStream
		if stream:
			_sfx[sfx_name] = stream
	for i in SFX_VOICES:
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voices.append(v)
	ocean = AudioStreamPlayer.new()
	ocean.stream = SfxLoop.make("res://assets/audio/sfx/ocean_loop.wav")
	ocean.volume_db = -20.0
	add_child(ocean)
	if ocean.stream:
		ocean.play()


## Toca un efecto de sonido. Devuelve true si sonó.
func play(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	var stream: AudioStream = _sfx.get(sfx_name)
	if stream == null:
		return false
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = stream
	v.volume_db = volume_db
	v.pitch_scale = pitch
	v.play()
	last_sfx = sfx_name
	return true


## Efecto de un corredor: fuerte si es una persona; los demás, según qué tan
## cerca estén de alguna persona (o de cualquiera, en la demo). Lejos, no suena.
func play_for(rider: Rider, sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if rider == null:
		return false
	if rider.is_human:
		return play(sfx_name, volume_db, pitch)
	var listeners: Array[Rider] = []
	var everyone: Array[Rider] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r:
			everyone.append(r)
			if r.is_human:
				listeners.append(r)
	var demo := listeners.is_empty()
	if demo:
		listeners = everyone
	var nearest := INF
	for l in listeners:
		if l != rider or demo:
			nearest = minf(nearest, l.global_position.distance_to(rider.global_position))
	if demo:
		nearest = 0.0
	if nearest > SFX_RANGE:
		return false
	# Los de los demás, más bajos y bajando con la distancia.
	var fall := -6.0 - 18.0 * (nearest / SFX_RANGE)
	return play(sfx_name, volume_db + fall, pitch)


## Cuenta regresiva y llegada (las escucha todo el mundo).
func connect_race(race: Node) -> void:
	if race.has_signal("countdown_tick"):
		race.countdown_tick.connect(func(value: int) -> void:
			play("go" if value <= 0 else "beep", -2.0)
		)
	if race.has_signal("lap_started"):
		race.lap_started.connect(func(r: Rider, _lap: int) -> void:
			if r.is_human:
				play("lap", -3.0)
		)
	if race.has_signal("racer_finished"):
		race.racer_finished.connect(func(r: Rider, _place: int) -> void:
			if r.is_human:
				play("finish", -1.0)
		)


## Llamado por RaceManager al cargar una carrera.
func race_started() -> void:
	_in_race = true
	if player.stream and not player.playing:
		player.play()


## Llamado por el menú.
func menu_opened() -> void:
	_in_race = false
	if player.stream and not player.playing:
		player.play()


func _process(delta: float) -> void:
	var max_air := 0.0
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r == null or not r.is_human:
			continue
		var air: float = _airtime.get(r, 0.0)
		air = air + delta if not r.grounded else 0.0
		_airtime[r] = air
		max_air = maxf(max_air, air)
	# Limpiar Riders que ya no existen.
	for r in _airtime.keys():
		if not is_instance_valid(r):
			_airtime.erase(r)

	epic = _in_race and max_air > EPIC_AIRTIME
	if not _in_race:
		target_db = MENU_DB
	elif epic:
		target_db = EPIC_DB
	else:
		target_db = NORMAL_DB
	# Sube rápido y baja más despacio.
	var rate := 6.0 if target_db > player.volume_db else 2.0
	player.volume_db = lerpf(player.volume_db, target_db, 1.0 - exp(-rate * delta))
