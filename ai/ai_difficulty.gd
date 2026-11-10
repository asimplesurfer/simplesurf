class_name AIDifficulty
extends Resource
## Qué tan bien juega un bot. Se balancea sin tocar código.

@export var display_name: String = "Normal"
## Acelerador máximo (1 = a fondo).
@export_range(0.0, 1.0) var max_throttle: float = 0.95
## Cada cuánto vuelve a decidir (s). Más alto = reacciona más tarde.
@export var think_interval: float = 0.15
## Ruido en el volante (0 = perfecto).
@export var steer_noise: float = 0.15
## Probabilidad de ir a buscar el próximo círculo de velocidad.
@export_range(0.0, 1.0) var ring_seek: float = 0.6
## Probabilidad de equivocarse en un truco (mantener de más y caerse).
@export_range(0.0, 1.0) var trick_fail_chance: float = 0.2
## Probabilidad (por segundo) de saltar para hacer un truco en una recta.
@export var trick_jump_rate: float = 0.15
## Probabilidad de derrapar cuando tiene a un rival justo detrás.
@export_range(0.0, 1.0) var aggression: float = 0.4
## Si usa el turbo.
@export var uses_turbo: bool = true
## Cuánto nitro junta antes de usar el turbo.
@export_range(0.0, 1.0) var turbo_threshold: float = 0.6
## Distancia a la que ve las rocas (m).
@export var look_ahead: float = 26.0
## Pulsaciones por segundo al spamear para levantarse (siempre al máximo).
@export var mash_rate: float = 10.0

const NAMES := ["Fácil", "Normal", "Difícil"]


static func preset(level: int) -> AIDifficulty:
	var d := AIDifficulty.new()
	match clampi(level, 0, 2):
		0:
			d.display_name = "Fácil"
			d.max_throttle = 0.82
			d.think_interval = 0.3
			d.steer_noise = 0.3
			d.ring_seek = 0.3
			d.trick_fail_chance = 0.45
			d.trick_jump_rate = 0.08
			d.aggression = 0.1
			d.uses_turbo = false
			d.look_ahead = 18.0
		1:
			d.display_name = "Normal"
		2:
			d.display_name = "Difícil"
			d.max_throttle = 1.0
			d.think_interval = 0.08
			d.steer_noise = 0.05
			d.ring_seek = 0.95
			d.trick_fail_chance = 0.05
			d.trick_jump_rate = 0.25
			d.aggression = 0.85
			d.turbo_threshold = 0.35
			d.look_ahead = 32.0
	return d
