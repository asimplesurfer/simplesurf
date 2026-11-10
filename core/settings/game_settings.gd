class_name GameSettings
extends RefCounted
## Opciones del juego que se eligen en partida y se guardan para la próxima vez.

enum JumpMode { CHARGE, TAP }

const PATH := "user://settings.cfg"
const JUMP_MODE_NAMES := ["mantener para cargar", "tocar para saltar"]

## CHARGE: mantener carga el salto (salta solo al llegar al máximo).
## TAP: tocar salta enseguida, con una altura fija.
static var jump_mode: JumpMode = JumpMode.CHARGE
## Cuántas personas juegan (pantalla dividida). Se cambia con las teclas 1 / 2.
static var player_count: int = 1
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		jump_mode = int(cfg.get_value("gameplay", "jump_mode", JumpMode.CHARGE)) as JumpMode
		player_count = clampi(int(cfg.get_value("gameplay", "player_count", 1)), 1, 2)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("gameplay", "jump_mode", jump_mode)
	cfg.set_value("gameplay", "player_count", player_count)
	cfg.save(PATH)


static func toggle_jump_mode() -> void:
	jump_mode = JumpMode.TAP if jump_mode == JumpMode.CHARGE else JumpMode.CHARGE
	save_settings()


static func jump_mode_name() -> String:
	return JUMP_MODE_NAMES[jump_mode]
