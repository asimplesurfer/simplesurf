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
## Línea de carrera: 0 = sigue su camino; 1 = corta siempre por adentro de las
## curvas (el camino más corto), como un experto.
@export_range(0.0, 1.0) var line_skill: float = 0.0
## Margen (s) que deja antes de tocar el agua para terminar una vuelta de truco.
## Menos margen = más vueltas (y más nitro), con más riesgo.
@export var trick_margin: float = 0.12
## Cuánto acelera mientras esquiva una roca de cerca (1 = no afloja).
@export_range(0.0, 1.0) var rock_throttle: float = 0.6
## Guarda el turbo para usarlo justo antes de que la ola lo lance (sale más alto).
@export var saves_turbo_for_waves: bool = false
## Probabilidad de salirse del cono del derrape del rival de adelante (para que
## no lo tire).
@export_range(0.0, 1.0) var evade_skill: float = 0.0
## Espacio extra (m) que deja al esquivar rocas.
@export var rock_margin: float = 0.0
## Calcula el aterrizaje con el agua de adelante (no la de abajo): no lo
## agarra una ola a mitad de una vuelta de truco.
@export var reads_landing: bool = false

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
			# Muy bueno, pero no perfecto: casi no se equivoca, va a los aros y a
			# casi todas las olas, y a veces corta por adentro o esquiva el
			# derrape del de adelante. Calcula el aterrizaje con el agua de abajo
			# (alguna ola lo agarra a mitad de un truco).
			d.display_name = "Profesional"
			d.max_throttle = 1.0
			d.think_interval = 0.06
			d.steer_noise = 0.03
			d.ring_seek = 0.92
			d.trick_fail_chance = 0.03
			d.trick_jump_rate = 0.3
			d.aggression = 0.9
			d.turbo_threshold = 0.34
			d.turbo_steer_limit = 0.3
			d.look_ahead = 36.0
			d.pop_skill = 0.93
			d.wave_seek = 0.9
			d.mash_rate = 8.5
			d.line_skill = 0.3
			d.trick_margin = 0.11
			d.rock_throttle = 0.7
			d.evade_skill = 0.35
			d.rock_margin = 0.6
		4:
			# Lo mejor que se puede jugar, sin ninguna ventaja: la línea más corta
			# siempre, trucos al límite, turbo guardado para salir volando de
			# las olas, ni un error y se para lo más rápido posible.
			d.display_name = "Imposible"
			d.max_throttle = 1.0
			d.think_interval = 0.03
			d.steer_noise = 0.0
			d.ring_seek = 1.0
			d.trick_fail_chance = 0.0
			d.trick_jump_rate = 0.45
			d.aggression = 0.55
			d.turbo_threshold = 0.34
			d.turbo_steer_limit = 0.25
			d.look_ahead = 45.0
			d.pop_skill = 1.0
			d.wave_seek = 1.0
			d.mash_rate = 10.0
			d.line_skill = 0.8
			d.trick_margin = 0.1
			d.rock_throttle = 0.9
			d.saves_turbo_for_waves = true
			d.evade_skill = 1.0
			d.rock_margin = 1.5
			d.reads_landing = true
	return d
