class_name TrackMap
extends Resource
## Los datos de un mapa: el recorrido, las islas y cuántos obstáculos tiene.
## Cada mapa es un archivo .tres en world/maps/ (agregar un mapa = agregar un
## archivo, no tocar código). Course lo lee y arma todo.

## Archivo de cada mapa, en el orden de GameSettings.TrackLayout.
const FILES := [
	"res://world/maps/classic.tres",
	"res://world/maps/archipelago.tres",
	"res://world/maps/atoll.tres",
]

## Recorrido: puntos de control (x, z) en el sentido de la carrera. Vacío = un
## anillo alrededor de la primera isla, de radio `ring_radius`.
@export var path: PackedVector2Array = PackedVector2Array()
@export var ring_radius: float = 82.0
## Mitad del ancho de la pista (m).
@export var half_width: float = 20.0
## Islas: (x, z, radio). La primera es la principal.
@export var islands: Array[Vector3] = []
## Índice de la isla que es un volcán (-1: ninguna).
@export var volcano_index: int = -1
@export var ring_count: int = 10
@export var rock_count: int = 12
@export var laps: int = 3
## Cosas propias del mapa (un script con `static func build(course)`), o nada.
@export var extras: Script


static func for_layout(layout: int) -> TrackMap:
	return load(FILES[clampi(layout, 0, FILES.size() - 1)]) as TrackMap


## true si el recorrido es un anillo alrededor de la isla principal.
func is_ring() -> bool:
	return path.is_empty()
