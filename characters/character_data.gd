class_name CharacterData
extends Resource
## Cómo se ve un corredor: peso (forma del cuerpo), piel, short y tabla.

## Colores de piel para elegir (el último es verde alien).
const SKIN_COLORS := [
	Color("#f3d0b0"),
	Color("#e0ac80"),
	Color("#b07a4e"),
	Color("#8a5a3b"),
	Color("#5c3a24"),
	Color("#7bd16a"),
	Color("#8fb8ff"),
]
const SKIN_NAMES := ["Clara", "Trigueña", "Morena", "Canela", "Oscura", "Alien verde", "Alien azul"]
const SHORTS_COLORS := [
	Color("#1c2b66"),
	Color("#d23c3c"),
	Color("#f2b630"),
	Color("#1f9e8f"),
	Color("#8a4fd1"),
	Color("#222222"),
	Color("#f07ab0"),
]
const SHORTS_NAMES := ["Azul", "Rojo", "Amarillo", "Turquesa", "Violeta", "Negro", "Rosa"]
const BOARD_COLORS := [
	Color(1.0, 0.86, 0.3),
	Color(0.95, 0.95, 0.95),
	Color(0.35, 0.75, 1.0),
	Color(1.0, 0.5, 0.35),
	Color(0.55, 0.9, 0.4),
	Color(0.9, 0.5, 1.0),
]
const BOARD_NAMES := ["Amarilla", "Blanca", "Celeste", "Naranja", "Verde", "Lila"]

## 0 = Musculoso ... 1 = Cervecero.
@export_range(0.0, 1.0) var weight: float = 0.4
@export var skin_index: int = 2
@export var shorts_index: int = 0
@export var board_index: int = 0


func skin_color() -> Color:
	return SKIN_COLORS[posmod(skin_index, SKIN_COLORS.size())]


func shorts_color() -> Color:
	return SHORTS_COLORS[posmod(shorts_index, SHORTS_COLORS.size())]


func board_color() -> Color:
	return BOARD_COLORS[posmod(board_index, BOARD_COLORS.size())]


func to_dict() -> Dictionary:
	return {"weight": weight, "skin": skin_index, "shorts": shorts_index, "board": board_index}


static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.weight = clampf(float(d.get("weight", 0.4)), 0.0, 1.0)
	c.skin_index = int(d.get("skin", 2))
	c.shorts_index = int(d.get("shorts", 0))
	c.board_index = int(d.get("board", 0))
	return c


## Personaje al azar (para los bots).
static func random(rng: RandomNumberGenerator) -> CharacterData:
	var c := CharacterData.new()
	c.weight = rng.randf()
	c.skin_index = rng.randi() % SKIN_COLORS.size()
	c.shorts_index = rng.randi() % SHORTS_COLORS.size()
	c.board_index = rng.randi() % BOARD_COLORS.size()
	return c


## Personaje por defecto para cada jugador (distintos entre sí).
static func default_for_player(player_index: int) -> CharacterData:
	var c := CharacterData.new()
	c.weight = [0.3, 0.7, 0.5, 0.1][player_index % 4]
	c.skin_index = [2, 0, 3, 5][player_index % 4]
	c.shorts_index = [0, 1, 3, 4][player_index % 4]
	c.board_index = [0, 2, 4, 5][player_index % 4]
	return c
