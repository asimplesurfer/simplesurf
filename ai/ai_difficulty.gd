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
## Pulsaciones por segundo al spamear para levantarse. Escala con la dificultad;
## el más rápido (Difícil) es el 75 % de lo que spameaban antes todos (10/s).
## Cada caída sale entre MASH_SPREAD y 100 % de esto, así no se paran todos igual.
@export var mash_rate: float = 6.0
## Ventaja física (solo en los niveles más altos): velocidad máxima y nitro que gana.
@export var speed_bonus: float = 1.0
@export var nitro_bonus: float = 1.0

const MASH_SPREAD := 0.8

const NAMES := ["Fácil", "Normal", "Difícil", "Profesional", "Imposible"]


static func preset(level: int) -> AIDifficulty:
	var d := AIDifficulty.new()
	match clampi(level, 0, NAMES.size() - 1):
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
			d.mash_rate = 4.5
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
			d.mash_rate = 7.5
		3:
			# Juega perfecto: sin errores, siempre al mejor camino, turbo con cada
			# carga en recta, todos los pops y todas las olas.
			d.display_name = "Profesional"
			d.max_throttle = 1.0
			d.think_interval = 0.05
			d.steer_noise = 0.02
			d.ring_seek = 1.0
			d.trick_fail_chance = 0.02
			d.trick_jump_rate = 0.35
			d.aggression = 0.95
			d.turbo_threshold = 0.34
			d.turbo_steer_limit = 0.25
			d.look_ahead = 38.0
			d.pop_skill = 0.97
			d.wave_seek = 0.97
			d.mash_rate = 8.5
		4:
			# Como Profesional pero sin un solo error, y con ventaja física:
			# un poco más rápido y carga más nitro. Para ganarle hay que jugar perfecto.
			d.display_name = "Imposible"
			d.max_throttle = 1.0
			d.think_interval = 0.03
			d.steer_noise = 0.0
			d.ring_seek = 1.0
			d.trick_fail_chance = 0.0
			d.trick_jump_rate = 0.45
			d.aggression = 1.0
			d.turbo_threshold = 0.34
			d.turbo_steer_limit = 0.25
			d.look_ahead = 45.0
			d.pop_skill = 1.0
			d.wave_seek = 1.0
			d.mash_rate = 10.0
			d.speed_bonus = 1.12
			d.nitro_bonus = 1.7
	return d
