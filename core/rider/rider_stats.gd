class_name RiderStats
extends Resource
## Valores de balance del Rider. Se editan en rider_stats.tres sin tocar código.

@export_group("Movimiento")
## Velocidad normal sobre la tabla (m/s).
@export var cruise_speed: float = 12.0
## Cuánto acelera hasta llegar a la velocidad normal (m/s²).
@export var acceleration: float = 7.0
## Velocidad de giro con el stick a fondo (radianes por segundo).
@export var turn_speed: float = 2.0

@export_group("Caída y levantarse")
## Cuánto llena la barra cada pulsación (1.0 = barra llena).
@export var mash_fill_per_press: float = 0.16
## Cuánto se vacía la barra por segundo. Con 0.16 y 0.55 hacen falta
## más de ~3.5 pulsaciones por segundo para avanzar.
@export var mash_decay_per_second: float = 0.55
## Duración de la animación de subirse a la tabla (s). Durante ella no cuentan las pulsaciones.
@export var climb_time: float = 0.45
## Frenado al caer al agua viniendo rápido (m/s²).
@export var water_drag: float = 9.0
## Frenado suave mientras se rema acostado (m/s²).
@export var paddle_drag: float = 1.2
## Velocidad que suma cada pulsación estando acostado (remar).
@export var paddle_impulse: float = 0.6
## Velocidad máxima remando.
@export var paddle_max_speed: float = 3.0
## Multiplicador de giro estando acostado.
@export var prone_turn_factor: float = 0.5
