class_name Tuning
extends RefCounted
## Valores para probar en el momento (panel de ajustes, tecla F9): cuando quede
## decidido cada número, pasa a ser el valor por defecto.
## Se guardan en user://settings.cfg (sección "tuning") para que sigan al
## reiniciar la partida.

const PATH := "user://settings.cfg"

## Agua: 0 = el color de siempre, 1 = azul marino oscuro.
const WATER_DARK_DEFAULT := 0.0
## Distancia de la cámara detrás del surfista (m).
const CAMERA_DISTANCE_DEFAULT := 6.0
const CAMERA_DISTANCE_MIN := 3.0
const CAMERA_DISTANCE_MAX := 8.0

static var water_dark: float = WATER_DARK_DEFAULT
static var camera_distance: float = CAMERA_DISTANCE_DEFAULT
## Se ve el panel (se cambia con F9).
static var panel_visible: bool = true
static var _loaded: bool = false


static func load_values() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	water_dark = clampf(float(cfg.get_value("tuning", "water_dark", WATER_DARK_DEFAULT)), 0.0, 1.0)
	camera_distance = clampf(
		float(cfg.get_value("tuning", "camera_distance", CAMERA_DISTANCE_DEFAULT)),
		CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX
	)
	panel_visible = bool(cfg.get_value("tuning", "panel_visible", true))


static func save_values() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("tuning", "water_dark", water_dark)
	cfg.set_value("tuning", "camera_distance", camera_distance)
	cfg.set_value("tuning", "panel_visible", panel_visible)
	cfg.save(PATH)
