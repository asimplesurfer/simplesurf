class_name Swell
extends RefCounted
## Una ola grande y localizada: una "loma" alargada que avanza, crece al nacer
## y se desvanece al morir. La misma fórmula está en water.gdshader (add_swell).
##
## En su sistema local: u = a lo largo de la dirección de avance, w = a lo ancho.
## altura = amplitud * exp(-(u/ancho)²) * borde(w)

var center: Vector2 = Vector2.ZERO
## Dirección de avance (normalizada).
var direction: Vector2 = Vector2.RIGHT
var speed: float = 5.0
var max_amplitude: float = 1.8
## Ancho de la loma (m). Más chico = más empinada.
var width: float = 4.0
## Mitad del largo de la cresta (m).
var half_length: float = 18.0
## Distancia en la que se suavizan las puntas (m).
var edge: float = 8.0
var lifetime: float = 12.0
var grow_time: float = 2.0
var fade_time: float = 2.5

var age: float = 0.0
var amplitude: float = 0.0
## 0 mientras crece; sube a 1 apenas llega a su máximo (rompe: labio y espuma).
var breaking: float = 0.0
## Tiempo que tarda en romper del todo después de llegar al máximo (s).
const BREAK_TIME := 1.2
## Puntos del perfil para saber si la cara quedó adentro de la ola.
const FACE_SAMPLES := 64
## Altura mínima de la ola sobre el mar en ese punto para que cuente (m).
const MIN_FACE_DEPTH := 0.25


func update(delta: float) -> void:
	age += delta
	center += direction * speed * delta
	var k := minf(age / grow_time, 1.0) * clampf((lifetime - age) / fade_time, 0.0, 1.0)
	amplitude = max_amplitude * smoothstep(0.0, 1.0, k)
	breaking = clampf((age - grow_time) / BREAK_TIME, 0.0, 1.0)


## Que se termine pronto (ya pasó y no le sirve a nadie): se desvanece.
func retire() -> void:
	lifetime = minf(lifetime, age + fade_time)


func is_dead() -> bool:
	return age >= lifetime


## Distancias en el sistema local de la ola: (u a lo largo, w a lo ancho).
func local_coords(p: Vector2) -> Vector2:
	var rel := p - center
	return Vector2(rel.dot(direction), rel.dot(Vector2(-direction.y, direction.x)))


func height_at(p: Vector2) -> float:
	if amplitude <= 0.0:
		return 0.0
	var uw := local_coords(p)
	var aw := absf(uw.y)
	if aw >= half_length or absf(uw.x) > width * 4.0:
		return 0.0
	return amplitude * exp(-(uw.x * uw.x) / (width * width)) * _edge(aw)


## Derivadas de la altura en el mundo: (dh/dx, dh/dz).
func gradient_at(p: Vector2) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var uw := local_coords(p)
	var aw := absf(uw.y)
	if aw >= half_length or absf(uw.x) > width * 4.0:
		return Vector2.ZERO
	var g := exp(-(uw.x * uw.x) / (width * width))
	var e := _edge(aw)
	var dh_du := amplitude * (-2.0 * uw.x / (width * width)) * g * e
	var dh_dw := amplitude * g * _edge_derivative(aw) * signf(uw.y)
	var perp := Vector2(-direction.y, direction.x)
	return direction * dh_du + perp * dh_dw


func _edge(aw: float) -> float:
	return 1.0 - smoothstep(half_length - edge, half_length, aw)


func _edge_derivative(aw: float) -> float:
	var t := clampf((aw - (half_length - edge)) / edge, 0.0, 1.0)
	return -6.0 * t * (1.0 - t) / edge


## true si el punto q (la cara del personaje) está adentro del agua de esta ola
## tal como se ve: con el labio corrido hacia adelante igual que en
## water.gdshader. base_y = altura del agua sin esta ola; fade = island_fade.
## Tira un rayo hacia arriba desde q y cuenta cuántas veces cruza el perfil de
## la ola (impar = adentro; debajo del labio pero en el aire da par).
func face_inside(q: Vector3, base_y: float, fade: float = 1.0) -> bool:
	if amplitude <= 0.0 or fade <= 0.0:
		return false
	var uw := local_coords(Vector2(q.x, q.z))
	var aw := absf(uw.y)
	if aw >= half_length:
		return false
	var e := _edge(aw)
	var amp := amplitude * fade
	var lean := (0.35 + 0.95 * breaking) * amplitude * fade
	var span := width * 4.0
	if uw.x < -span or uw.x > span + lean:
		return false
	var crossings := 0
	var top := -INF
	var prev := Vector2.ZERO
	for i in FACE_SAMPLES + 1:
		var u := lerpf(-span, span, float(i) / FACE_SAMPLES)
		var n := exp(-(u * u) / (width * width)) * e
		var cur := Vector2(u + lean * n * n * n, base_y + amp * n)
		if i > 0 and (prev.x - uw.x) * (cur.x - uw.x) <= 0.0 and prev.x != cur.x:
			var y := lerpf(prev.y, cur.y, (uw.x - prev.x) / (cur.x - prev.x))
			if y > q.y:
				crossings += 1
				top = maxf(top, y)
		prev = cur
	# Tiene que ser agua de la ola, no el nivel del mar de siempre.
	return crossings % 2 == 1 and top - base_y > MIN_FACE_DEPTH


## Parámetros empaquetados para el shader.
func shader_a() -> Vector4:
	return Vector4(center.x, center.y, direction.x, direction.y)


func shader_b() -> Vector4:
	# El borde (edge) es fijo en el shader (8 m); el último valor es lo que rompió.
	return Vector4(amplitude, width, half_length, breaking)
