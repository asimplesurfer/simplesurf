class_name RacerSlot
extends Resource
## Un lugar en la carrera: quién corre (persona o bot) y cómo se ve.

enum Kind { HUMAN, BOT }

@export var kind: Kind = Kind.HUMAN
## Jugador (mando / teclado) que lo controla. Solo para humanos.
@export var player_index: int = 0
@export var display_name: String = "J1"
@export var character: CharacterData
## Solo para bots.
@export var difficulty: AIDifficulty
