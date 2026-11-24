class_name Swell
extends RefCounted
## Una ola grande y localizada: una "loma" alargada que avanza, crece al nacer
## y se desvanece al morir. La misma fórmula está en water_surface.gdshaderinc (add_swell); tests/water_match.gd comprueba que coincidan.
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

## Modo trucos: ola de borde (larga; si se llega a la cresta desde atrás, lleva
## al surfista por el borde; ver el estado `lip`).
var lip: bool = false
## Ya se usó (la ola de borde lleva a uno solo, una vez).
var lip_used: bool = false
## No sacarla para hacer lugar (alguien la está usando).
var keep: bool = false
## Modo trucos: la física usa la ola TAL COMO SE DIBUJA, con la cresta corrida
## hacia adelante (el labio; ver `lean`). Sin esto (como en carrera) la física
## usa la loma sin corrimiento: con olas chicas casi no se nota, pero con las
## de 10 m la cresta dibujada queda muchos metros adelante de la que se siente.
var match_drawn: bool = false
## Para encontrar de qué punto de la loma viene lo que se dibuja en un lugar
## (ver `_source_u`): en cuántos tramos se revisa y cuántas veces se parte el
## tramo donde está.
const MATCH_STEPS := 12
const MATCH_REFINE := 7

var age: float = 0.0
var amplitude: float = 0.0
## 0 mientras crece; sube a 1 apenas llega a su máximo (rompe: labio y espuma).
var breaking: float = 0.0
## Tiempo que tarda en romper del todo después de llegar al máximo (s).
const BREAK_TIME := 1.2


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
	if match_drawn:
		if aw >= half_length or uw.x < -width * 4.0 or uw.x > width * 4.0 + lean():
			return 0.0
		uw.x = _source_u(uw.x, aw)
	if aw >= half_length or absf(uw.x) > width * 4.0:
		return 0.0
	return amplitude * exp(-(uw.x * uw.x) / (width * width)) * _edge(aw)


## Derivadas de la altura en el mundo: (dh/dx, dh/dz).
func gradient_at(p: Vector2) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var uw := local_coords(p)
	var aw := absf(uw.y)
	var stretch := 1.0
	if match_drawn:
		if aw >= half_length or uw.x < -width * 4.0 or uw.x > width * 4.0 + lean():
			return Vector2.ZERO
		uw.x = _source_u(uw.x, aw)
	if aw >= half_length or absf(uw.x) > width * 4.0:
		return Vector2.ZERO
	var g := exp(-(uw.x * uw.x) / (width * width))
	var e := _edge(aw)
	if match_drawn:
		# Como en el dibujo: la cara de adelante, apretada, queda más empinada.
		var n := g * e
		stretch = maxf(1.0 + lean() * 3.0 * n * n * (-2.0 * uw.x / (width * width)) * g * e, 0.12)
	var dh_du := amplitude * (-2.0 * uw.x / (width * width)) * g * e / stretch
	var dh_dw := amplitude * g * _edge_derivative(aw) * signf(uw.y)
	var perp := Vector2(-direction.y, direction.x)
	return direction * dh_du + perp * dh_dw


## Dónde está en la loma (u, antes del corrimiento) el punto que se dibuja en
## `u`: el dibujo corre cada punto lean·n³ hacia adelante (como en
## water_surface.gdshaderinc), así que se busca u0 con u0 + lean·n(u0)³ = u.
## Está entre u - lean y u. Rompiendo fuerte, el labio se pliega sobre la cara
## y hay más de uno: se queda con el más alto (lo que se ve y se pisa).
func _source_u(u: float, aw: float) -> float:
	var lean_now := lean()
	if lean_now <= 0.0:
		return u
	var e := _edge(aw)
	var lo := u - lean_now
	var best := u
	var best_n := -1.0
	var prev_u := lo
	var prev_f := _shift_error(lo, u, lean_now, e)
	for k in range(1, MATCH_STEPS + 1):
		var cur_u := lerpf(lo, u, float(k) / MATCH_STEPS)
		var cur_f := _shift_error(cur_u, u, lean_now, e)
		if (prev_f <= 0.0) != (cur_f <= 0.0) or cur_f == 0.0:
			# Hay un punto en este tramo: se lo busca partiendo el tramo.
			var a := prev_u
			var b := cur_u
			var fa := prev_f
			for i in MATCH_REFINE:
				var mid := (a + b) * 0.5
				var fm := _shift_error(mid, u, lean_now, e)
				if (fa <= 0.0) == (fm <= 0.0):
					a = mid
					fa = fm
				else:
					b = mid
			var root := (a + b) * 0.5
			var n := exp(-(root * root) / (width * width))
			if n > best_n:
				best_n = n
				best = root
		prev_u = cur_u
		prev_f = cur_f
	return best


## u0 + lean·n(u0)³ - u (0 en el punto buscado; ver _source_u).
func _shift_error(u0: float, u: float, lean_now: float, e: float) -> float:
	var n := exp(-(u0 * u0) / (width * width)) * e
	return u0 + lean_now * n * n * n - u


## true si `p` puede estar sobre esta ola tal como se dibuja (contando el
## corrimiento del labio).
func reaches(p: Vector2) -> bool:
	if amplitude <= 0.0:
		return false
	var uw := local_coords(p)
	return absf(uw.y) < half_length and uw.x > -width * 4.0 and uw.x < width * 4.0 + (lean() if match_drawn else 0.0)


## La loma sin corrimiento en `p`: 0..1 (altura = amplitude · esto).
func plain_n(p: Vector2) -> float:
	var uw := local_coords(p)
	var aw := absf(uw.y)
	if aw >= half_length or absf(uw.x) > width * 4.0:
		return 0.0
	return exp(-(uw.x * uw.x) / (width * width)) * _edge(aw)


## Dónde está la cresta (lo más alto) a lo largo de la dirección de avance (m
## desde el centro): corrida por el labio si la física sigue al dibujo.
func crest_u() -> float:
	return lean() if match_drawn else 0.0


func _edge(aw: float) -> float:
	return 1.0 - smoothstep(half_length - edge, half_length, aw)


func _edge_derivative(aw: float) -> float:
	var t := clampf((aw - (half_length - edge)) / edge, 0.0, 1.0)
	return -6.0 * t * (1.0 - t) / edge


## Cuánto se corre la cresta hacia adelante (m), igual que en water_surface.gdshaderinc.
func lean() -> float:
	return (0.35 + 0.95 * breaking) * amplitude


## Parámetros empaquetados para el shader.
func shader_a() -> Vector4:
	return Vector4(center.x, center.y, direction.x, direction.y)


func shader_b() -> Vector4:
	# El borde (edge) es fijo en el shader (8 m); el último valor es lo que rompió.
	return Vector4(amplitude, width, half_length, breaking)
