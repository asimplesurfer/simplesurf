class_name GameSettings
extends RefCounted
## Preferencias del jugador (las elige en el menú y se guardan para la próxima
## vez). Lo propio de cada partida (modo, mapa, clima, corredores) va en su
## RaceConfig, que se arma con estas opciones al empezar.

enum JumpMode { CHARGE, TAP }
## WAVES: la altura la dan las olas (A en el agua: saltito; A en la ola: "pop").
## FREE: A salta alto en cualquier lado (como antes).
enum JumpStyle { WAVES, FREE }
## SURGES: olas grandes que aparecen solas (casi siempre vienen de frente).
## CONSTANT_LEFT: una ola constante a la izquierda (lado de afuera de la pista).
enum WaveMode { SURGES, CONSTANT_LEFT }
const WAVE_MODE_NAMES := ["grandes que aparecen", "constante a la izquierda"]
## Clima: sol o tormenta eléctrica (cielo gris, rayos, mar picado).
enum Weather { SUNNY, STORM }
const WEATHER_NAMES := ["soleado", "tormenta"]
## Hora del día de la partida: cambia el cielo, la luz y el mar (ver DayTime).
enum TimeOfDay { DAY, SUNSET, NIGHT }
const TIME_NAMES := ["día", "atardecer", "noche"]

const PATH := "user://settings.cfg"
const JUMP_MODE_NAMES := ["mantener para cargar", "tocar para saltar"]

## CHARGE: mantener carga el salto (salta solo al llegar al máximo).
## TAP: tocar salta enseguida, con una altura fija.
## Por ahora el salto es solo "tocar para saltar" (el cargado queda en el código
## para probarlo más adelante; no se carga de la configuración guardada).
static var jump_mode: JumpMode = JumpMode.TAP
static var jump_style: JumpStyle = JumpStyle.WAVES
static var wave_mode: WaveMode = WaveMode.SURGES
## El mapa elegido: su lugar en la lista de mapas de hoy (TrackMap.all()).
## Sirve mientras el juego está abierto; se guarda por nombre y número (ver
## save_settings), así sacar o reordenar mapas no cambia el elegido.
static var track_layout: int = TrackMap.default_index()
static var weather: Weather = Weather.SUNNY
static var time_of_day: TimeOfDay = TimeOfDay.DAY
## Cuántas personas juegan (pantalla dividida). Se elige en el menú (y en el
## modo libre, con las teclas 1 / 2).
static var player_count: int = 1
## Bots en la carrera (0 a 3) y su dificultad (0 Fácil, 1 Normal, 2 Difícil).
static var bot_count: int = 1
static var bot_level: int = 1
## Canciones del juego (assets/audio). La música elegida: una canción en bucle
## (su índice) o MUSIC_SHUFFLE = todas, una distinta cuando termina la anterior.
const SONG_NAMES := ["Simple Surf", "King of the Tide"]
const SONG_PATHS := ["res://assets/audio/simple_surf.ogg", "res://assets/audio/king_of_the_tide.ogg"]
const MUSIC_SHUFFLE := 2
static var music_choice: int = MUSIC_SHUFFLE
## Volúmenes (0..1) de la música y de los efectos (menú de pausa).
static var music_volume: float = 1.0
static var sfx_volume: float = 1.0
## Modo libre: nivel de las olas (0 = sin olas grandes .. SANDBOX_WAVE_LEVELS =
## como en una carrera). Se recuerda mientras el juego está abierto.
const SANDBOX_WAVE_LEVELS := 5
static var sandbox_wave_level: int = 3
## La demo siempre es igual: dos bots en Imposible, en El Atolón con tormenta
## (ver RaceConfig.demo; el modo de la partida va en su RaceConfig, no acá).
const DEMO_MAP := "atoll"
const DEMO_WEATHER := Weather.STORM
const DEMO_BOTS := 2
const DEMO_LEVEL := 4
## Personaje de cada jugador (índice -> CharacterData).
static var characters: Dictionary = {}
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_count = clampi(int(cfg.get_value("gameplay", "player_count", 1)), 1, InputSetup.MAX_PLAYERS)
		# Se juega siempre con el salto de olas (saltito + pop): ya no se elige.
		jump_style = JumpStyle.WAVES
		# El mapa va por nombre y número. Antes iba solo "track_layout" (el
		# lugar en la lista, que era igual al número).
		var map_id := str(cfg.get_value("gameplay", "map", ""))
		var map_order := int(cfg.get_value("gameplay", "map_order", cfg.get_value("gameplay", "track_layout", -1)))
		track_layout = TrackMap.find(map_id, map_order)
		weather = clampi(int(cfg.get_value("gameplay", "weather", Weather.SUNNY)), 0, WEATHER_NAMES.size() - 1) as Weather
		time_of_day = clampi(int(cfg.get_value("gameplay", "time_of_day", TimeOfDay.DAY)), 0, TIME_NAMES.size() - 1) as TimeOfDay
		wave_mode = clampi(int(cfg.get_value("gameplay", "wave_mode", WaveMode.SURGES)), 0, 1) as WaveMode
		bot_count = clampi(int(cfg.get_value("gameplay", "bot_count", 1)), 0, 3)
		bot_level = clampi(int(cfg.get_value("gameplay", "bot_level", 1)), 0, AIDifficulty.NAMES.size() - 1)
		music_choice = clampi(int(cfg.get_value("audio", "music", MUSIC_SHUFFLE)), 0, MUSIC_SHUFFLE)
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
		for i in InputSetup.MAX_PLAYERS:
			var key := "player_%d" % i
			if not cfg.has_section_key("characters", key):
				continue
			var d: Variant = cfg.get_value("characters", key)
			if d is Dictionary:
				characters[i] = CharacterData.from_dict(d)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("gameplay", "jump_mode", jump_mode)
	cfg.set_value("gameplay", "player_count", player_count)
	cfg.set_value("gameplay", "jump_style", jump_style)
	cfg.set_value("gameplay", "wave_mode", wave_mode)
	var map := TrackMap.for_layout(track_layout)
	cfg.set_value("gameplay", "map", map.id)
	cfg.set_value("gameplay", "map_order", map.order)
	if cfg.has_section_key("gameplay", "track_layout"):
		cfg.erase_section_key("gameplay", "track_layout")
	cfg.set_value("gameplay", "weather", weather)
	cfg.set_value("gameplay", "time_of_day", time_of_day)
	cfg.set_value("gameplay", "bot_count", bot_count)
	cfg.set_value("gameplay", "bot_level", bot_level)
	cfg.set_value("audio", "music", music_choice)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	for i in characters:
		cfg.set_value("characters", "player_%d" % i, (characters[i] as CharacterData).to_dict())
	cfg.save(PATH)


## Nombres para el menú: cada canción y "Aleatoria".
static func music_names() -> Array:
	var names: Array = SONG_NAMES.duplicate()
	names.append("Aleatoria")
	return names


static func toggle_jump_mode() -> void:
	jump_mode = JumpMode.TAP if jump_mode == JumpMode.CHARGE else JumpMode.CHARGE
	save_settings()


static func jump_mode_name() -> String:
	return JUMP_MODE_NAMES[jump_mode]


## Personaje guardado del jugador (o uno por defecto).
static func character_for(player_index: int) -> CharacterData:
	if not characters.has(player_index):
		characters[player_index] = CharacterData.default_for_player(player_index)
	return characters[player_index]


static func jump_style_name() -> String:
	return "olas (saltito + pop en la ola)" if jump_style == JumpStyle.WAVES else "libre"


static func toggle_wave_mode() -> void:
	wave_mode = WaveMode.CONSTANT_LEFT if wave_mode == WaveMode.SURGES else WaveMode.SURGES
	save_settings()


static func wave_mode_name() -> String:
	return WAVE_MODE_NAMES[wave_mode]


static func toggle_track_layout() -> void:
	track_layout = (track_layout + 1) % TrackMap.count()
	save_settings()


## Elige el mapa número `layout` (su lugar en la lista de mapas).
static func set_track_layout(layout: int) -> void:
	track_layout = clampi(layout, 0, TrackMap.count() - 1)
	save_settings()


static func track_layout_name() -> String:
	return TrackMap.for_layout(track_layout).name


## Nombres de todos los mapas (para el menú), en orden.
static func track_layout_names() -> Array[String]:
	return TrackMap.names()


## Vueltas de la carrera según el mapa (el archipiélago y el atolón son mucho
## más largos que la isla).
static func laps_for(layout: int) -> int:
	return TrackMap.for_layout(layout).laps

