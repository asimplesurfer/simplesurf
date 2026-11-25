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
## Modo trucos: la ola rompe en tubo (0 = ola normal, 1 = rompiendo: ver
## `profile`). Solo en olas que ya rompieron del todo. El dibujo (shader) y la
## física usan la misma forma.
var curl: float = 0.0
## Rompe de a poco a lo largo de la cresta, como una ola de verdad: el punto
## de rotura (`peel_w`: metros a lo ancho desde el medio) avanza hacia
## `peel_dir` (+1 / -1) a `peel_speed` m/s. Mirando hacia donde avanza:
##   - adelante, el hombro: la ola entera, empinada;
##   - la garganta (BARREL_THROAT m): el labio se va tirando hacia adelante;
##   - detrás del punto de rotura, el tubo abierto (`barrel_len` m);
##   - más atrás, el tubo se cae: el labio ya tocó el agua, el hueco se llena
##     (espuma) y la ola baja (BARREL_DROP).
## Mientras, la ola sigue avanzando (`speed`). Ver `barrel_at`.
##
## Si empezó a romper en el medio de la cresta (`peel_from`: donde se paró el
## surfista), rompe como un pico, para los dos lados: hacia `peel_dir` el tubo
## que sigue el surfista y hacia el otro lado lo mismo, espejado (ver `peel_s`).
## INF: empezó más allá de la punta (rompe para un solo lado).
var peel_w: float = -1.0e9
var peel_dir: float = 1.0
var peel_from: float = INF
var peel_speed: float = 0.0
var barrel_len: float = 22.0
const BARREL_THROAT := 10.0
const BARREL_COLLAPSE := 16.0
const BARREL_DROP := 0.6
## Forma del tubo (en veces la altura de la ola), visto de costado: la
## superficie pasa la cresta y da la vuelta por afuera del labio (un óvalo de
## radios TUBE_RX × TUBE_RY) hacia adelante y abajo hasta la punta
## (TUBE_END_ANGLE); vuelve por adentro del labio (más fino: TUBE_THICK) hasta
## atrás (TUBE_BACK_ANGLE), baja como pared cóncava hasta el piso
## (TUBE_WALL_BACK atrás de la cresta, a TUBE_FLOOR_Y de alto) y sigue hacia
## adelante como agua. TUBE_REACH: hasta dónde llega por delante (veces el
## ancho). Igual en water_surface.gdshaderinc.
const TUBE_RX := 0.55
const TUBE_RY := 0.48
const TUBE_THICK := 0.1
const TUBE_END_ANGLE := -0.35
## Hasta dónde baja la punta cuando el labio cae (rad; ver land_at).
const TUBE_LAND_ANGLE := -1.2
const TUBE_BACK_ANGLE := 2.44
const TUBE_WALL_BACK := 0.5
const TUBE_FLOOR_Y := 0.1
const TUBE_REACH := 3.0
## En qué parte del recorrido de la cara de adelante (0..1) termina cada tramo:
## labio por afuera, punta, labio por adentro, pared (y después el piso).
const TUBE_S := [0.3, 0.35, 0.55, 0.72]
## Cómo se forma (ver tube_shape): el labio sale de la cresta y se va
## enrollando hacia adelante y hacia abajo con el agua de arriba de la cara
## (crece de tamaño y de largo a la vez), mientras el resto de la cara se
## retira (hacia atrás y abajo) hasta ser la pared y el piso del hueco. Nada
## sube desde abajo. TUBE_STEEP: hasta dónde (de cuánto se formó) la
## pendiente y la luz del shader se mezclan con las de la ola normal.
const TUBE_STEEP := 0.25
## Adelante del punto de rotura, el labio se achica en BARREL_THROAT m (la
## garganta), pero la ola sigue hueca y empinada (la pared y el agua baja
## adelante) hasta BARREL_SHOULDER_HOLD m y vuelve a la ola normal hasta
## BARREL_SHOULDER_END m: desde adentro del tubo se ve la salida (el ojo).
const BARREL_SHOULDER_HOLD := 16.0
const BARREL_SHOULDER_END := 40.0
## Cuánto hacia adelante termina la curva de la cara (veces la altura).
const TUBE_FOOT := 0.4
## Muestras para encontrar qué parte de la ola se dibuja en un lugar (tubo).
const TUBE_SCAN := 96
## La punta del labio se dibuja como una línea derecha: la malla del agua
## (celdas de ~1 m en el modo trucos) queda en diagonal con la ola y, si no,
## el borde del labio se ve serruchado. Los puntos a TUBE_TIP_BAND m (de u0)
## de la punta van justo a la punta (ningún triángulo la cruza: miden a lo
## sumo 1,41 celdas) y los siguientes TUBE_TIP_RAMP m se estiran para no
## dejar un salto.
const TUBE_TIP_BAND := 0.78
const TUBE_TIP_RAMP := 1.2
## Tiempo que tarda en romper del todo después de llegar al máximo (s).
const BREAK_TIME := 1.2


func update(delta: float) -> void:
	age += delta
	center += direction * speed * delta
	if curl > 0.0:
		peel_w += peel_dir * peel_speed * delta
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
		var hs := tube_heights(uw.x, uw.y)
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


## Cómo está la ola en `w` (metros a lo ancho desde el medio) mientras rompe:
## Vector4(cuánto salió el labio 0..1, cuánto se cayó 0..1, cuánto se llenó el
## hueco 0..1, cuánto se ahuecó la cara 0..1). Ver `peel_w`. Adelante de la
## rotura el labio se achica antes que el hueco (el ojo: ver
## BARREL_SHOULDER_HOLD). Donde se cae, primero el hueco se llena de agua (el
## labio ya cayó: queda un bulto de espuma) y después el bulto se desarma y
## baja. Igual en water_surface.gdshaderinc.
func barrel_at(w: float) -> Vector4:
	if curl <= 0.0:
		return Vector4.ZERO
	var s := peel_s(w)
	if s > 0.0:
		return Vector4(
			curl * (1.0 - smoothstep(0.0, BARREL_THROAT, s)), 0.0, 0.0,
			curl * (1.0 - smoothstep(BARREL_SHOULDER_HOLD, BARREL_SHOULDER_END, s)))
	var q := 1.0 - smoothstep(-barrel_len - BARREL_COLLAPSE, -barrel_len, s)
	var c := curl * (1.0 - smoothstep(0.45, 1.0, q))
	return Vector4(c, q * curl, smoothstep(0.0, 0.5, q), c)


## Cuánto cayó el labio en `w` (0..1): recién tirado cerca del punto de
## rotura (hueco grande); más atrás va cayendo hasta tocar el agua (el tubo se
## cierra, antes de caerse del todo). Igual en water_surface.gdshaderinc.
func land_at(w: float) -> float:
	if curl <= 0.0:
		return 0.0
	var s := peel_s(w)
	return smoothstep(0.0, barrel_len + BARREL_COLLAPSE * 0.5, -s)


## Cuánto corrió la rotura desde donde empezó (m; ver `peel_from`). Sin punto
## de partida, un número enorme (como si viniera de lejos).
func peel_run() -> float:
	if is_inf(peel_from):
		return 1.0e6
	return maxf((peel_w - peel_from) * peel_dir, 0.0)


## Dónde queda `w` respecto de la rotura (m): positivo = todavía no rompió (el
## hombro); negativo = ya rompió hace tantos metros (el tubo y, más atrás, lo
## que se cae). De las dos roturas (la que va hacia `peel_dir` y su espejo, la
## que vuelve desde `peel_from`), la que le queda más cerca. Igual en
## water_surface.gdshaderinc.
func peel_s(w: float) -> float:
	var a := (w - peel_w) * peel_dir
	return maxf(a, -a - 2.0 * peel_run())


## Para el shader: (punto de rotura, hacia dónde, largo del tubo, cuánto
## corrió desde donde empezó).
func barrel_uniform() -> Vector4:
	return Vector4(peel_w, peel_dir, barrel_len, peel_run())


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
func profile(u0: float, w: float) -> Vector2:
	var e := _edge(absf(w))
	var n := exp(-(u0 * u0) / (width * width)) * e
	var off := lean() * n * n * n
	var h := amplitude * n
	var bq := barrel_at(w)
	# Detrás del tubo la ola se cae: más baja (y con espuma, en el shader).
	var drop := 1.0 - BARREL_DROP * bq.y
	if (bq.x <= 0.0 and bq.w <= 0.0) or u0 <= 0.0 or u0 >= TUBE_REACH * width:
		return Vector2(off, h * drop)
	var t := tube_shape(u0, bq.x, bq.w, land_at(w), bq.z, e)
	return Vector2(t.x - u0, t.y * drop)


## El punto u0 (de la cara de adelante, 0 < u0 < TUBE_REACH·ancho) de una ola
## que rompe en tubo: Vector2(adelante desde el centro, altura), ya con las
## puntas (`e`). `lip_k`: cuánto salió el labio (0..1); `hollow`: cuánto se
## ahuecó la cara (0..1); con los dos en 0, la ola normal. El labio se hace con
## el agua de arriba de la cara (los primeros lip_k · TUBE_S[2] del recorrido):
## un arco que sale de la cresta, del tamaño que tenga. El resto de la cara va
## de la ola normal (hollow 0) a la pared y el piso del tubo entero (hollow 1),
## y empieza donde termina el labio por adentro. `fill`: cuánto se llenó el
## hueco (0: abierto; 1: macizo, ver barrel_at). Igual en
## water_surface.gdshaderinc.
func tube_shape(u0: float, lip_k: float, hollow: float, land: float = 0.0, fill: float = 0.0, e: float = 1.0) -> Vector2:
	var reach := TUBE_REACH * width
	var s2: float = TUBE_S[2]
	var lip_len := lip_k * s2 * reach
	if u0 <= lip_len:
		# La punta, derecha (ver TUBE_TIP_BAND), en proporción al labio.
		var tip := (TUBE_S[0] + TUBE_S[1]) * 0.5 / s2 * lip_len
		var band := TUBE_TIP_BAND * lip_k
		var ramp := TUBE_TIP_RAMP * lip_k
		var d := u0 - tip
		var ad := absf(d)
		if ad < band + ramp:
			u0 = tip + signf(d) * maxf(ad - band, 0.0) * (band + ramp) / ramp
		var lp := _lip_point(u0 / lip_len * s2, lip_k, land, fill)
		return Vector2(lp.x, lp.y * e)
	var t := (u0 - lip_len) / (reach - lip_len)
	var m := _plain_point(t * reach, e).lerp(_face_point(t, fill, e), hollow)
	# Que empiece donde termina el labio por adentro (se corrige de a poco).
	var back := _lip_point(s2, lip_k, land, fill)
	back.y *= e
	var m0 := _plain_point(0.0, e).lerp(_face_point(0.0, fill, e), hollow)
	return m + (back - m0) * (1.0 - t) * (1.0 - t)


## Un punto del labio (`s`: 0..TUBE_S[2] del recorrido del labio: por afuera,
## la punta, por adentro), del tamaño `lip_k` (sin las puntas de la ola).
func _lip_point(s: float, lip_k: float, land: float, fill: float) -> Vector2:
	var a := amplitude
	var rx := TUBE_RX * a * lip_k
	var ry := TUBE_RY * a * lip_k
	var rxi := (TUBE_RX - TUBE_THICK) * a * lip_k * (1.0 - fill)
	var ryi := (TUBE_RY - TUBE_THICK) * a * lip_k * (1.0 - fill)
	var end_angle := lerpf(PI * 0.5, lerpf(TUBE_END_ANGLE, TUBE_LAND_ANGLE, land), lip_k)
	var s0: float = TUBE_S[0]
	var s1: float = TUBE_S[1]
	var s2: float = TUBE_S[2]
	var c := Vector2(1.3 * a + 0.05 * a * lip_k, a - ry)
	if s <= s0:
		var ang := lerpf(PI * 0.5, end_angle, s / s0)
		return c + Vector2(cos(ang) * rx, sin(ang) * ry)
	if s <= s1:
		var k := (s - s0) / (s1 - s0)
		return c + Vector2(cos(end_angle) * lerpf(rx, rxi, k), sin(end_angle) * lerpf(ry, ryi, k))
	var ang2 := lerpf(end_angle, TUBE_BACK_ANGLE, (s - s1) / (s2 - s1))
	return c + Vector2(cos(ang2) * rxi, sin(ang2) * ryi)


## La ola normal en u0 (con la cresta corrida: el labio de siempre).
func _plain_point(u0: float, e: float) -> Vector2:
	var n := exp(-(u0 * u0) / (width * width)) * e
	return Vector2(u0 + lean() * n * n * n, amplitude * n)


## La pared y el piso del tubo entero (`t`: 0 donde termina el labio por
## adentro .. 1 al final de la cara), ya con las puntas (`e`).
func _face_point(t: float, fill: float, e: float) -> Vector2:
	var a := amplitude
	var full_lean := 1.3 * a
	var s2: float = TUBE_S[2]
	var s3: float = TUBE_S[3]
	var s := s2 + t * (1.0 - s2)
	var c := Vector2(full_lean + 0.05 * a, a - TUBE_RY * a)
	var top := c + Vector2(cos(TUBE_BACK_ANGLE) * (TUBE_RX - TUBE_THICK) * a * (1.0 - fill),
		sin(TUBE_BACK_ANGLE) * (TUBE_RY - TUBE_THICK) * a * (1.0 - fill))
	var base := Vector2(full_lean - TUBE_WALL_BACK * a, TUBE_FLOOR_Y * a)
	# La cara (la pared de atrás del tubo) es cóncava: baja empinada y se va
	# curvando hasta el agua de adelante (sin esquina).
	var foot := base + Vector2(TUBE_FOOT * a, 0.0)
	var p: Vector2
	if s <= s3:
		var k := (s - s2) / (s3 - s2)
		p = top * (1.0 - k) * (1.0 - k) + base * 2.0 * k * (1.0 - k) + foot * k * k
	else:
		var ue := TUBE_REACH * width
		var ne := exp(-(ue * ue) / (width * width))
		p = foot.lerp(Vector2(ue + full_lean * ne * ne * ne, a * ne), (s - s3) / (1.0 - s3))
	return Vector2(p.x, p.y * e)


## Ola rompiendo en tubo: las alturas (de abajo hacia arriba) de lo que se
## dibuja en (u, w) (hay más de una: el piso de adentro y el techo del labio).
func tube_heights(u: float, w: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var lo := -width * 4.0
	var hi := width * 4.0
	var prev_u := lo
	var prev_f := lo + profile(lo, w).x - u
	for k in range(1, TUBE_SCAN + 1):
		var cu := lerpf(lo, hi, float(k) / TUBE_SCAN)
		var cf := cu + profile(cu, w).x - u
		if (prev_f <= 0.0) != (cf <= 0.0):
			var a := prev_u
			var b := cu
			var fa := prev_f
			for i in MATCH_REFINE:
				var mid := (a + b) * 0.5
				var fm := mid + profile(mid, w).x - u
				if (fa <= 0.0) == (fm <= 0.0):
					a = mid
					fa = fm
				else:
					b = mid
			out.append(profile((a + b) * 0.5, w).y)
		prev_u = cu
		prev_f = cf
	out.sort()
	return out


## Ola rompiendo en tubo: de qué punto de la cara (u0, antes de correrse)
## viene el piso que se dibuja en (u, w) (la superficie más baja). El dibujo
## suma el mar de fondo de ese punto, no el de (u, w): ver Water.floor_height_at.
## NAN si no hay nada dibujado ahí.
func tube_floor_source(u: float, w: float) -> float:
	var lo := -width * 4.0
	var hi := width * 4.0
	var prev_u := lo
	var prev_f := lo + profile(lo, w).x - u
	var best_y := INF
	var best_u := NAN
	for k in range(1, TUBE_SCAN + 1):
		var cu := lerpf(lo, hi, float(k) / TUBE_SCAN)
		var cf := cu + profile(cu, w).x - u
		if (prev_f <= 0.0) != (cf <= 0.0):
			var a := prev_u
			var b := cu
			var fa := prev_f
			for i in MATCH_REFINE:
				var mid := (a + b) * 0.5
				var fm := mid + profile(mid, w).x - u
				if (fa <= 0.0) == (fm <= 0.0):
					a = mid
					fa = fm
				else:
					b = mid
			var y := profile((a + b) * 0.5, w).y
			if y < best_y:
				best_y = y
				best_u = (a + b) * 0.5
		prev_u = cu
		prev_f = cf
	return best_u


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
	var hs := tube_heights(uw.x, uw.y)
	return hs[0] if not hs.is_empty() else 0.0
