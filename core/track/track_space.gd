class_name TrackSpace
extends RefCounted
## Coordenadas de pista de un circuito circular alrededor de la isla.
## - ángulo: cuánto avanzó alrededor de la isla (la meta está en ángulo 0 y la
##   carrera va en el sentido en que el ángulo crece).
## - lateral: cuánto se alejó de la línea central (+ hacia afuera, - hacia la isla).
##
## Los Riders se mueven libres sobre el agua; esto convierte su posición a
## coordenadas de pista para vueltas, posiciones, obstáculos y el bot.

var center: Vector2 = Vector2.ZERO
## Radio de la línea central del circuito (m).
var radius: float = 95.0
## Mitad del ancho del circuito (m).
var half_width: float = 36.0


func _init(p_radius: float = 95.0, p_half_width: float = 36.0) -> void:
	radius = p_radius
	half_width = p_half_width


func angle_of(p: Vector3) -> float:
	return atan2(p.z - center.y, p.x - center.x)


func lateral_of(p: Vector3) -> float:
	return Vector2(p.x, p.z).distance_to(center) - radius


## Ángulo y lateral juntos: Vector2(ángulo, lateral).
func locate(p: Vector3) -> Vector2:
	return Vector2(angle_of(p), lateral_of(p))


func position_at(angle: float, lateral: float = 0.0) -> Vector3:
	var r := radius + lateral
	return Vector3(center.x + cos(angle) * r, 0.0, center.y + sin(angle) * r)


## Dirección en la que hay que ir (sentido de la carrera) en ese ángulo.
func tangent_at(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle))


## Rumbo de Rider (rotación en Y) que mira en el sentido de la carrera.
func heading_at(angle: float) -> float:
	var t := tangent_at(angle)
	return atan2(-t.x, -t.z)


func length() -> float:
	return TAU * radius


# ---------------------------------------------------- caminos (bifurcaciones)
# Un circuito puede tener tramos con más de un camino (ver PathTrack). Cada
# camino es una "ruta": la 0 es la principal. El anillo tiene una sola.

func route_count() -> int:
	return 1


## Ángulo, lateral y ruta juntos: Vector3(ángulo, lateral, ruta), sobre el
## camino más cercano.
func locate_route(p: Vector3) -> Vector3:
	var l := locate(p)
	return Vector3(l.x, l.y, 0.0)


## Como position_at, pero sobre esa ruta (en su tramo; fuera de él, la principal).
func position_on(_route: int, angle: float, lateral: float = 0.0) -> Vector3:
	return position_at(angle, lateral)


func tangent_on(_route: int, angle: float) -> Vector3:
	return tangent_at(angle)


func heading_on(route: int, angle: float) -> float:
	var t := tangent_on(route, angle)
	return atan2(-t.x, -t.z)


## Tramos con más de un camino (ver PathTrack.groups). El anillo no tiene.
func groups() -> Array[Dictionary]:
	return []


## La vuelta entera eligiendo un camino en cada tramo (ver PathTrack.variant).
func variant(_choices: Array) -> TrackSpace:
	return self
