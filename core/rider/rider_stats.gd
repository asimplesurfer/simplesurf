class_name RiderStats
extends Resource
## Valores de balance del Rider. Se editan en rider_stats.tres sin tocar código.

@export_group("Movimiento")
## Velocidad máxima acelerando a fondo (m/s).
@export var max_speed: float = 13.0
## Aceleración con W / stick arriba (m/s²).
@export var acceleration: float = 6.0
## Frenado al soltar el acelerador (m/s²).
@export var coast_decel: float = 2.5
## Frenado con S / stick abajo (m/s²).
@export var brake_decel: float = 9.0
## Velocidad de giro con el stick a fondo (radianes por segundo).
@export var turn_speed: float = 1.3
## Qué tan rápido responde el giro (más alto = más directo).
@export var steer_response: float = 3.5

@export_group("Salto y olas")
@export var gravity: float = 20.0
## Velocidad hacia arriba de un salto sin cargar (toque rápido) (m/s).
@export var jump_speed_min: float = 5.5
## Velocidad hacia arriba con el salto cargado al máximo (m/s).
@export var jump_speed_max: float = 10.0
## Tiempo manteniendo ESPACIO para cargar el salto al máximo (s). Al llegar, salta solo.
@export var jump_charge_time: float = 1.0
## Velocidad hacia arriba en el modo "tocar para saltar" (m/s).
@export var jump_speed_tap: float = 8.0
## Modo olas: velocidad del saltito en agua plana (m/s); ~40 cm de alto.
@export var hop_speed: float = 4.0
## Modo olas: el "pop" multiplica el impulso con el que te lanza la ola.
@export var pop_mult: float = 1.7
## Modo olas: segundos que se recuerda el A apretado subiendo la ola (y
## después del lanzamiento en los que todavía vale el pop).
@export var pop_window: float = 0.35
## Velocidad hacia arriba subiendo una ola para que A cuente como pop (m/s).
@export var pop_min_climb: float = 1.5
## Velocidad vertical mínima para que una ola te lance al aire (m/s).
@export var min_launch_speed: float = 4.5
## Multiplica la velocidad hacia arriba al salir despedido de una ola.
@export var wave_launch_boost: float = 1.5
## Multiplicador de giro en el aire.
@export var air_turn_factor: float = 0.5

@export_group("Truco")
## Tiempo manteniendo A en el aire antes de que empiece a girar la tabla (s).
@export var trick_hold_delay: float = 0.12
## Velocidad de giro de la tabla en el truco (radianes por segundo).
@export var trick_spin_speed: float = 15.0
## Nitro que carga por segundo girando (1.0 = barra llena).
@export var trick_nitro_rate: float = 0.5

@export_group("Turbo y motivación")
## Multiplica la velocidad máxima con el turbo.
@export var turbo_speed_mult: float = 1.55
## Multiplica la aceleración con el turbo.
@export var turbo_accel_mult: float = 2.5
## Nitro que gasta el turbo por segundo (1.0 = barra llena).
@export var turbo_drain: float = 0.35
## Duración del mini sprint automático (motivación) (s).
@export var motivation_time: float = 1.3
## Multiplica la velocidad máxima durante la motivación.
@export var motivation_speed_mult: float = 1.3
## Nitro que da pasar por un círculo de velocidad.
@export var ring_nitro: float = 0.25
## Si una ola te lanza mientras usás el turbo, el impulso hacia arriba se multiplica.
@export var turbo_launch_mult: float = 1.6
## Turbo en el aire: empuje hacia arriba al empezar (m/s²); crece exponencialmente.
@export var air_turbo_lift: float = 12.0
## Qué tan rápido crece el empuje en el aire (por segundo, exponencial).
@export var air_turbo_growth: float = 1.6
## Velocidad máxima hacia arriba con el turbo en el aire (m/s).
@export var air_turbo_max_up: float = 9.0
## Nitro que gasta el turbo por segundo en el aire.
@export var air_turbo_drain: float = 0.6
## "Aire fino": desde esta altura sobre el agua (m) el impulso hacia arriba
## se va perdiendo de a poco y el turbo empuja cada vez menos.
@export var air_soft_height: float = 10.0
## Altura (m) a la que el turbo ya no empuja nada y el frenado es pleno.
## No es un techo duro: la subida se va frenando y el salto hace la curva.
@export var air_max_height: float = 17.0
## Frenado extra de la subida en el aire fino (veces la gravedad, al máximo).
@export var air_thin_gravity: float = 1.5
## Frenado extra proporcional a la velocidad de subida (por segundo, al máximo).
@export var air_thin_drag: float = 2.5

@export_group("Handicap (los de atrás se acercan)")
## Distancia al primero (m, medida por la pista sumando las vueltas) a la que el
## handicap llega al máximo. Una vuelta mide ~515 m: con una vuelta de atraso
## ya es el máximo.
@export var catchup_full_gap: float = 120.0
## Multiplicador máximo del nitro que se gana (círculos y trucos).
@export var catchup_nitro_mult: float = 2.5
## Nitro que se carga solo por segundo con el handicap al máximo.
@export var catchup_nitro_trickle: float = 0.04
## Cuánto más alto salta (olas, pop, saltito) con el handicap al máximo (0.35 = +35%).
@export var catchup_jump_bonus: float = 0.35
## Velocidad máxima extra con el handicap al máximo (0.2 = +20%).
@export var catchup_speed_bonus: float = 0.2
## Tolerancia al caer de un truco con el handicap al máximo (radianes que le
## pueden faltar al giro para que igual cuente como bien hecho; ~70°).
@export var catchup_trick_grace: float = 1.2

@export_group("Derrape")
## Velocidad mínima para poder derrapar (m/s).
@export var drift_min_speed: float = 6.0
## Si baja de esta velocidad, el derrape termina (m/s).
@export var drift_end_speed: float = 3.0
## Cuánto frena derrapando (m/s²).
@export var drift_decel: float = 4.0
## Multiplicador de giro derrapando.
@export var drift_turn_factor: float = 1.6
## Largo del cono de agua hacia atrás (m).
@export var drift_range: float = 6.0
## Apertura del cono (grados a cada lado).
@export var drift_cone_half_angle: float = 30.0

@export_group("Caída y levantarse")
## Cuánto llena la barra cada pulsación (1.0 = barra llena).
@export var mash_fill_per_press: float = 0.32
## Cuánto se vacía la barra por segundo. Con 0.32 y 1.1 hacen falta
## más de ~3.5 pulsaciones por segundo para avanzar.
@export var mash_decay_per_second: float = 1.1
## Duración de la animación de subirse a la tabla (s). Durante ella no cuentan las pulsaciones.
@export var climb_time: float = 0.45
## Tiempo tras pararse en el que A no salta (para que el spam no te haga saltar).
@export var stand_jump_lock: float = 0.4
## Frenado al caer al agua viniendo rápido (m/s²).
@export var water_drag: float = 9.0
## Frenado suave mientras se rema acostado (m/s²).
@export var paddle_drag: float = 1.2
## Velocidad que suma cada pulsación estando acostado (remar).
@export var paddle_impulse: float = 0.6
## Velocidad máxima remando.
@export var paddle_max_speed: float = 3.0
## Multiplicador de giro estando acostado.
@export var prone_turn_factor: float = 0.6
