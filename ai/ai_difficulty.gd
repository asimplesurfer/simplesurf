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
## Modo olas: probabilidad de hacer el pop al subir una ola.
@export_range(0.0, 1.0) var pop_skill: float = 0.6
## Modo olas: probabilidad de ir a buscar una ola grande que tiene adelante.
@export_range(0.0, 1.0) var wave_seek: float = 0.6
## Probabilidad de derrapar cuando tiene a un rival justo detrás.
@export_range(0.0, 1.0) var aggression: float = 0.4
## Si usa el turbo.
@export var uses_turbo: bool = true
## Cuánto nitro junta antes de usar el turbo.
@export_range(0.0, 1.0) var turbo_threshold: float = 0.6
## Hasta cuánto giro usa el turbo (bajo = solo en recta; alto = también en curvas,
## o sea, lo desperdicia).
@export_range(0.0, 1.0) var turbo_steer_limit: float = 0.35
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
			# Usa el turbo tarde (con la barra casi llena) y mal (también en curvas).
			d.uses_turbo = true
			d.turbo_threshold = 0.9
			d.turbo_steer_limit = 0.9
			d.look_ahead = 18.0
			d.pop_skill = 0.25
			d.wave_seek = 0.3
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
			d.pop_skill = 0.9
			d.wave_seek = 0.9
	return d
