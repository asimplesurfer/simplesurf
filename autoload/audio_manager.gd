extends Node
## Música de fondo y volumen dinámico (autoload "AudioManager").
##
## - La música suena durante la carrera (y la demo) y sigue sonando entre
##   carreras sin cortarse. Se elige en el menú (GameSettings.music_choice): una
##   canción en bucle, o "Aleatoria": cuando termina una, arranca otra distinta.
## - Volumen épico: si una persona pasa mucho tiempo en el aire, la música sube;
##   al volver al agua, baja de nuevo. Con pantalla dividida manda el que más
##   tiempo lleva en el aire. Los bots no cuentan.
## Los Riders no conocen el audio: esto solo mira su estado.

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
## Las canciones (en el orden de GameSettings.SONG_NAMES).
var _songs: Array = []
## Canción que está sonando (índice) y modo elegido.
var song_index: int = -1
var music_choice: int = -1
var _in_race: bool = false

## Efectos de sonido (assets/audio/sfx/<nombre>.wav, generados con tools/make_sfx.py).
const SFX_NAMES := [
	"splash", "wave_punch", "pop", "hop", "land", "turbo", "ring", "trick_ok", "trick_fail",
	"crash", "bonk", "mash", "beep", "go", "lap", "finish", "thunder", "cheer",
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
## Últimos efectos que sonaron (para los tests).
var recent_sfx: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	player = AudioStreamPlayer.new()
	player.volume_db = -40.0
	player.bus = MUSIC_BUS
	add_child(player)
	player.finished.connect(_on_song_finished)
	for path in GameSettings.SONG_PATHS:
		var music := load(path) as AudioStreamOggVorbis
		_songs.append(music.duplicate() if music else null)
	GameSettings.load_settings()
	set_music(GameSettings.music_choice, false)

	for sfx_name in SFX_NAMES:
		var stream := load("res://assets/audio/sfx/%s.wav" % sfx_name) as AudioStream
		if stream:
			_sfx[sfx_name] = stream
	for i in SFX_VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = SFX_BUS
		add_child(v)
		_voices.append(v)
	ocean = AudioStreamPlayer.new()
	ocean.stream = SfxLoop.make("res://assets/audio/sfx/ocean_loop.wav")
	ocean.volume_db = -20.0
	ocean.bus = SFX_BUS
	add_child(ocean)
	apply_volumes()
	if ocean.stream:
		ocean.play()


## Buses de audio: la música y los efectos por separado (cada uno con su
## volumen en el menú de pausa). Los dos van al Master.
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"


## Los buses están en default_bus_layout.tres (en la web, un bus creado por
## código no se registra en el audio del navegador y lo que va por ahí no suena).
## Esto solo los crea si faltara el archivo.
func _make_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


## Aplica los volúmenes guardados (GameSettings.music_volume / sfx_volume).
func apply_volumes() -> void:
	_set_bus_volume(MUSIC_BUS, GameSettings.music_volume)
	_set_bus_volume(SFX_BUS, GameSettings.sfx_volume)


static func _set_bus_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


## Sin foco (otra ventana u otra pestaña): todo en silencio; al volver, suena.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			set_focus_mute(true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			set_focus_mute(false)


## Silencia (o no) todo el audio por haber perdido el foco.
func set_focus_mute(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


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
	recent_sfx.append(sfx_name)
	if recent_sfx.size() > 32:
		recent_sfx.pop_front()
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


## Cambia la música: una canción en bucle o aleatoria (otra distinta cuando
## termina). Si ya suena lo mismo, no la corta. `play_now`: arranca enseguida.
func set_music(choice: int, play_now: bool = true) -> void:
	choice = clampi(choice, 0, GameSettings.MUSIC_SHUFFLE)
	var was_playing := player.playing
	music_choice = choice
	if choice == GameSettings.MUSIC_SHUFFLE:
		# Sigue la que suena (ahora sin bucle); al terminar, otra.
		if song_index >= 0 and player.stream:
			(player.stream as AudioStreamOggVorbis).loop = false
			return
		_play_song(randi() % _songs.size(), false, play_now or was_playing)
		return
	if song_index == choice and player.stream:
		(player.stream as AudioStreamOggVorbis).loop = true
		if play_now and not player.playing:
			player.play()
		return
	_play_song(choice, true, play_now or was_playing)


func _play_song(index: int, loop: bool, start: bool) -> void:
	var stream := _songs[index] as AudioStreamOggVorbis
	if stream == null:
		return
	song_index = index
	stream.loop = loop
	player.stream = stream
	if start:
		player.play()


## Terminó la canción. Con una elegida, vuelve a empezar (por si el bucle no
## llegó a tomarse: se activa a mitad de la canción y el reproductor no lo ve).
## En aleatoria, otra distinta.
func _on_song_finished() -> void:
	if _songs.size() == 0:
		return
	if music_choice != GameSettings.MUSIC_SHUFFLE:
		_play_song(music_choice, true, true)
		return
	var next := song_index
	if _songs.size() > 1:
		while next == song_index:
			next = randi() % _songs.size()
	_play_song(next, false, true)


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
