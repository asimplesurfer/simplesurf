class_name RacerSlot
extends Resource
## Un lugar en la carrera: quién corre y con qué colores.

enum Kind { HUMAN, BOT }

@export var kind: Kind = Kind.HUMAN
## Jugador (mando / teclado) que lo controla. Solo para humanos.
@export var player_index: int = 0
@export var display_name: String = "J1"
@export var body_color: Color = Color(0.98, 0.5, 0.32)
@export var board_color: Color = Color(1.0, 0.86, 0.3)
