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
## Velocidad hacia arriba que da el botón de salto (m/s).
@export var jump_speed: float = 7.0
## Velocidad vertical mínima para que una ola te lance al aire (m/s).
@export var min_launch_speed: float = 3.5
## Multiplicador de giro en el aire.
@export var air_turn_factor: float = 0.5

@export_group("Truco")
## Tiempo manteniendo A en el aire antes de que empiece a girar la tabla (s).
@export var trick_hold_delay: float = 0.12
## Velocidad de giro de la tabla en el truco (radianes por segundo).
@export var trick_spin_speed: float = 15.0
## Nitro que carga por segundo girando (1.0 = barra llena).
@export var trick_nitro_rate: float = 0.5

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
@export var mash_fill_per_press: float = 0.16
## Cuánto se vacía la barra por segundo. Con 0.16 y 0.55 hacen falta
## más de ~3.5 pulsaciones por segundo para avanzar.
@export var mash_decay_per_second: float = 0.55
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
