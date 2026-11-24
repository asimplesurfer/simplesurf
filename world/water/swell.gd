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
## Modo trucos: cuánto se cerró en tubo (0 = ola normal, 1 = tubo: ver
## `profile`). Solo en olas que ya rompieron del todo. El dibujo (shader) y la
## física usan la misma forma.
var curl: float = 0.0
## Forma del tubo (en veces la altura de la ola), visto de costado: la
## superficie pasa la cresta, da la vuelta por afuera del labio (radio TUBE_R)
## hasta la punta (TUBE_END_ANGLE), vuelve por adentro del labio (grosor
## TUBE_THICK) hasta atrás (TUBE_BACK_ANGLE), baja como pared hasta el piso
## (TUBE_WALL_BACK atrás de la cresta, a TUBE_FLOOR_Y de alto) y sigue hacia
## adelante como agua. TUBE_REACH: hasta dónde llega por delante (veces el
## ancho). Igual en water_surface.gdshaderinc.
const TUBE_R := 0.5
const TUBE_THICK := 0.15
const TUBE_END_ANGLE := -0.14
const TUBE_BACK_ANGLE := 2.62
const TUBE_WALL_BACK := 0.4
const TUBE_FLOOR_Y := 0.12
const TUBE_REACH := 3.0
## En qué parte del recorrido de la cara de adelante (0..1) termina cada tramo:
## labio por afuera, punta, labio por adentro, pared (y después el piso).
const TUBE_S := [0.25, 0.3, 0.5, 0.7]
## Cómo se forma: hasta TUBE_STEEP de curl la cara se pone empinada (de la ola
## normal a una pared); después el labio sale arriba y va creciendo hacia
## adelante y hacia abajo hasta cerrar (el hueco crece con él).
const TUBE_STEEP := 0.25
## Largo de la garganta del tubo, en cada punta (m; ver curl_at).
const TUBE_THROAT := 14.0
## Cuánto hacia adelante termina la curva de la cara (veces la altura).
const TUBE_FOOT := 0.35
## Muestras para encontrar qué parte de la ola se dibuja en un lugar (tubo).
const TUBE_SCAN := 96
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
	if curl > 0.0:
		# Cerrándose en tubo: lo más alto que se dibuja ahí (el techo).
		if aw >= half_length or uw.x < -width * 4.0 or uw.x > _drawn_ahead():
			return 0.0
		var hs := tube_heights(uw.x, aw)
		return hs[hs.size() - 1] if not hs.is_empty() else 0.0
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
	if curl > 0.0:
		var d := 0.25
		return Vector2(
			(height_at(p + Vector2(d, 0.0)) - height_at(p - Vector2(d, 0.0))) / (2.0 * d),
			(height_at(p + Vector2(0.0, d)) - height_at(p - Vector2(0.0, d))) / (2.0 * d))
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
	return absf(uw.y) < half_length and uw.x > -width * 4.0 and uw.x < (_drawn_ahead() if match_drawn else width * 4.0)


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


## Largo de las puntas, donde la ola se achica (m).
func edge_len() -> float:
	return edge


## Cuánto se cerró en tubo a `aw` m del medio: entero en el medio y, hacia las
## puntas, se va abriendo de a poco a lo largo de TUBE_THROAT m (la garganta:
## el labio sale cada vez menos). Así, mirando desde la punta, se ve el hueco
## que se agranda hacia adentro (si se achicara todo junto, quedaba cerrado).
func curl_at(aw: float) -> float:
	if curl <= 0.0:
		return 0.0
	var full_to := half_length - edge - TUBE_THROAT
	return curl * (1.0 - smoothstep(full_to, half_length - edge, aw))


func _edge(aw: float) -> float:
	var ed := edge_len()
	return 1.0 - smoothstep(half_length - ed, half_length, aw)


func _edge_derivative(aw: float) -> float:
	var ed := edge_len()
	var t := clampf((aw - (half_length - ed)) / ed, 0.0, 1.0)
	return -6.0 * t * (1.0 - t) / ed


## Cuánto se corre la cresta hacia adelante (m), igual que en water_surface.gdshaderinc.
func lean() -> float:
	return (0.35 + 0.95 * breaking) * amplitude


## Parámetros empaquetados para el shader.
func shader_a() -> Vector4:
	return Vector4(center.x, center.y, direction.x, direction.y)


func shader_b() -> Vector4:
	# El borde (edge) es fijo en el shader (8 m); el último valor es lo que rompió.
	# Con tubo (curl > 0), 1 + curl (ya rompió del todo).
	return Vector4(amplitude, width, half_length, 1.0 + curl if curl > 0.0 else breaking)


## Cómo se dibuja el punto u0 de la loma (a lo ancho, `aw` de la mitad):
## Vector2(cuánto se corre hacia adelante, altura). Sin tubo: la loma con la
## cresta corrida por el labio. Con tubo (curl), la cara de adelante se
## transforma de a poco en un labio que se tira hacia adelante y baja (un arco),
## un piso por adentro y la cara que sigue hacia adelante. En las puntas (donde
## la ola se achica) el tubo se achica pero queda abierto: la boca. Igual en
## water_surface.gdshaderinc.
func profile(u0: float, aw: float) -> Vector2:
	var e := _edge(aw)
	var n := exp(-(u0 * u0) / (width * width)) * e
	var off := lean() * n * n * n
	var h := amplitude * n
	var c := curl_at(aw)
	if c <= 0.0 or u0 <= 0.0 or u0 >= TUBE_REACH * width:
		return Vector2(off, h)
	var target := tube_point(u0, c)
	target.y *= e
	var k := smoothstep(0.0, TUBE_STEEP, c)
	var x := lerpf(u0 + off, target.x, k)
	return Vector2(x - u0, lerpf(h, target.y, k))


## El punto u0 (de la cara de adelante, 0 < u0 < TUBE_REACH·ancho) en la forma
## de tubo, sin las puntas: Vector2(adelante desde el centro, altura).
func tube_point(u0: float, c_now: float) -> Vector2:
	var a := amplitude
	var full_lean := 1.3 * a
	# Cuánto salió el labio (0: recién la pared; 1: cerrado).
	var sw := smoothstep(0.0, 1.0, (c_now - TUBE_STEEP) / (1.0 - TUBE_STEEP))
	var r := TUBE_R * a * sw
	var r_in := (TUBE_R - TUBE_THICK) * a * sw
	var end_angle := lerpf(PI * 0.5, TUBE_END_ANGLE, sw)
	var s := u0 / (TUBE_REACH * width)
	var c := Vector2(full_lean, a - r)
	var s0: float = TUBE_S[0]
	var s1: float = TUBE_S[1]
	var s2: float = TUBE_S[2]
	var s3: float = TUBE_S[3]
	if s <= s0:
		var ang := lerpf(PI * 0.5, end_angle, s / s0)
		return c + Vector2(cos(ang), sin(ang)) * r
	if s <= s1:
		var rr := lerpf(r, r_in, (s - s0) / (s1 - s0))
		return c + Vector2(cos(end_angle), sin(end_angle)) * rr
	if s <= s2:
		var ang2 := lerpf(end_angle, TUBE_BACK_ANGLE, (s - s1) / (s2 - s1))
		return c + Vector2(cos(ang2), sin(ang2)) * r_in
	var top := c + Vector2(cos(TUBE_BACK_ANGLE), sin(TUBE_BACK_ANGLE)) * r_in
	var base := Vector2(full_lean - (TUBE_WALL_BACK * sw - 0.15 * (1.0 - sw)) * a, TUBE_FLOOR_Y * a)
	# La cara (la pared de atrás del tubo) es cóncava: baja empinada y se va
	# curvando hasta el agua de adelante (sin esquina).
	var foot := base + Vector2(TUBE_FOOT * a, 0.0)
	if s <= s3:
		var t := (s - s2) / (s3 - s2)
		return top * (1.0 - t) * (1.0 - t) + base * 2.0 * t * (1.0 - t) + foot * t * t
	var ue := TUBE_REACH * width
	var ne := exp(-(ue * ue) / (width * width))
	var end := Vector2(ue + full_lean * ne * ne * ne, a * ne)
	return foot.lerp(end, (s - s3) / (1.0 - s3))


## Ola cerrándose en tubo: las alturas (de abajo hacia arriba) de lo que se
## dibuja en `u` (hay más de una: el piso de adentro y el techo del labio).
func tube_heights(u: float, aw: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var lo := -width * 4.0
	var hi := width * 4.0
	var prev_u := lo
	var prev_f := lo + profile(lo, aw).x - u
	for k in range(1, TUBE_SCAN + 1):
		var cu := lerpf(lo, hi, float(k) / TUBE_SCAN)
		var cf := cu + profile(cu, aw).x - u
		if (prev_f <= 0.0) != (cf <= 0.0):
			var a := prev_u
			var b := cu
			var fa := prev_f
			for i in MATCH_REFINE:
				var mid := (a + b) * 0.5
				var fm := mid + profile(mid, aw).x - u
				if (fa <= 0.0) == (fm <= 0.0):
					a = mid
					fa = fm
				else:
					b = mid
			out.append(profile((a + b) * 0.5, aw).y)
		prev_u = cu
		prev_f = cf
	out.sort()
	return out


## Lo que hay a lo largo de la ola (de atrás hacia adelante) que puede tener
## agua dibujada (con el corrimiento del labio y el tubo).
func _drawn_ahead() -> float:
	return width * 4.0 + lean() + (2.0 * amplitude if curl > 0.0 else 0.0)


## Ola cerrándose en tubo: la altura del piso de adentro en `p` (la superficie
## más baja que se dibuja ahí).
func floor_height_at(p: Vector2) -> float:
	if curl <= 0.0:
		return height_at(p)
	if amplitude <= 0.0:
		return 0.0
	var uw := local_coords(p)
	var aw := absf(uw.y)
	if aw >= half_length or uw.x < -width * 4.0 or uw.x > _drawn_ahead():
		return 0.0
	var hs := tube_heights(uw.x, aw)
	return hs[0] if not hs.is_empty() else 0.0
