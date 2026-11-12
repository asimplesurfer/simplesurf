class_name GameSettings
extends RefCounted
## Opciones del juego que se eligen en partida y se guardan para la próxima vez.

enum JumpMode { CHARGE, TAP }
## WAVES: la altura la dan las olas (A en el agua: saltito; A en la ola: "pop").
## FREE: A salta alto en cualquier lado (como antes).
enum JumpStyle { WAVES, FREE }
## SURGES: olas grandes que aparecen solas (casi siempre vienen de frente).
## CONSTANT_LEFT: una ola constante a la izquierda (lado de afuera de la pista).
enum WaveMode { SURGES, CONSTANT_LEFT }
const WAVE_MODE_NAMES := ["grandes que aparecen", "constante a la izquierda"]
## CLASSIC: un anillo alrededor de una isla. ARCHIPELAGO: un recorrido con
## curvas entre varias islas.
enum TrackLayout { CLASSIC, ARCHIPELAGO }
const TRACK_LAYOUT_NAMES := ["isla (anillo)", "archipiélago"]

const PATH := "user://settings.cfg"
const JUMP_MODE_NAMES := ["mantener para cargar", "tocar para saltar"]

## CHARGE: mantener carga el salto (salta solo al llegar al máximo).
## TAP: tocar salta enseguida, con una altura fija.
## Por ahora el salto es solo "tocar para saltar" (el cargado queda en el código
## para probarlo más adelante; no se carga de la configuración guardada).
static var jump_mode: JumpMode = JumpMode.TAP
static var jump_style: JumpStyle = JumpStyle.WAVES
static var wave_mode: WaveMode = WaveMode.SURGES
static var track_layout: TrackLayout = TrackLayout.ARCHIPELAGO
## Cuántas personas juegan (pantalla dividida). Se cambia con las teclas 1 / 2.
static var player_count: int = 1
## Pantalla dividida: true = un jugador a cada lado; false = uno arriba del otro.
static var split_vertical: bool = true
## Bots en la carrera (0 a 3) y su dificultad (0 Fácil, 1 Normal, 2 Difícil).
static var bot_count: int = 1
static var bot_level: int = 1
## Modo demo: carrera de bots que arranca sola si nadie toca el menú (no se guarda).
static var demo_mode: bool = false
## Personaje de cada jugador (índice -> CharacterData).
static var characters: Dictionary = {}
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		player_count = clampi(int(cfg.get_value("gameplay", "player_count", 1)), 1, 2)
		split_vertical = bool(cfg.get_value("gameplay", "split_vertical", true))
		jump_style = int(cfg.get_value("gameplay", "jump_style", JumpStyle.WAVES)) as JumpStyle
		track_layout = clampi(
			int(cfg.get_value("gameplay", "track_layout", TrackLayout.ARCHIPELAGO)), 0, 1
		) as TrackLayout
		wave_mode = clampi(int(cfg.get_value("gameplay", "wave_mode", WaveMode.SURGES)), 0, 1) as WaveMode
		bot_count = clampi(int(cfg.get_value("gameplay", "bot_count", 1)), 0, 3)
		bot_level = clampi(int(cfg.get_value("gameplay", "bot_level", 1)), 0, 2)
		for i in 2:
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
	cfg.set_value("gameplay", "split_vertical", split_vertical)
	cfg.set_value("gameplay", "jump_style", jump_style)
	cfg.set_value("gameplay", "wave_mode", wave_mode)
	cfg.set_value("gameplay", "track_layout", track_layout)
	cfg.set_value("gameplay", "bot_count", bot_count)
	cfg.set_value("gameplay", "bot_level", bot_level)
	for i in characters:
		cfg.set_value("characters", "player_%d" % i, (characters[i] as CharacterData).to_dict())
	cfg.save(PATH)


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


static func toggle_jump_style() -> void:
	jump_style = JumpStyle.FREE if jump_style == JumpStyle.WAVES else JumpStyle.WAVES
	save_settings()


static func jump_style_name() -> String:
	return "olas (saltito + pop en la ola)" if jump_style == JumpStyle.WAVES else "libre"


static func toggle_wave_mode() -> void:
	wave_mode = WaveMode.CONSTANT_LEFT if wave_mode == WaveMode.SURGES else WaveMode.SURGES
	save_settings()


static func wave_mode_name() -> String:
	return WAVE_MODE_NAMES[wave_mode]


static func toggle_track_layout() -> void:
	track_layout = (
		TrackLayout.CLASSIC if track_layout == TrackLayout.ARCHIPELAGO else TrackLayout.ARCHIPELAGO
	)
	save_settings()


static func track_layout_name() -> String:
	return TRACK_LAYOUT_NAMES[track_layout]


## Vueltas de la carrera según el mapa (el archipiélago es mucho más largo).
static func laps_for_layout() -> int:
	return 3 if track_layout == TrackLayout.ARCHIPELAGO else 5
