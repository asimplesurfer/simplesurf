class_name PathTrack
extends TrackSpace
## Circuito con curvas: un recorrido cerrado (no un círculo). Tiene las mismas
## funciones que TrackSpace, así el resto del juego (vueltas, posiciones, bots,
## olas) funciona igual:
## - "ángulo": cuánto avanzó por el recorrido, de -PI a PI (la meta en 0).
## - lateral: distancia a la línea central (+ a la izquierda del que corre).
##
## El recorrido se arma con una curva que pasa por los puntos de control, se
## suaviza y se re-muestrea en tramos iguales. Entre dos puntos la curva es una
## Bézier: cada punto puede tener manijas (como en un programa de dibujo). Si
## un punto no tiene manija, es automática: la curva pasa suave por los vecinos
## (Catmull-Rom).

## Distancia entre muestras del recorrido (m).
const STEP := 2.0
## Tamaño de celda de la grilla que acelera la búsqueda del punto más cercano (m).
const CELL := 20.0

## Puntos del recorrido (cerrado, separados STEP metros más o menos).
var points: PackedVector2Array = PackedVector2Array()
var _seg_len: float = STEP
var _total: float = 1.0
var _grid: Dictionary = {}


## `handles_in` / `handles_out`: manija de entrada y de salida de cada punto
## (relativas al punto; null o vacío = automática). `smoothing`: pasadas de
## suavizado (redondean las curvas más cerradas).
## `start`: recta de la meta (opcional, ver start_strip). Si está, la meta va
## en esa recta, la pista sale de su punta de adelante, pasa por los puntos de
## control y vuelve a entrar por la punta de atrás. La recta no se suaviza.
func _init(
	control: PackedVector2Array = PackedVector2Array(), p_half_width: float = 20.0,
	handles_in: Array = [], handles_out: Array = [], smoothing: int = 60, start: Dictionary = {}
) -> void:
	half_width = p_half_width
	if control.size() >= (1 if not start.is_empty() else 3):
		_build(control, handles_in, handles_out, smoothing, start)


## La recta de la meta: {"x", "z": la línea de llegada; "angle": hacia dónde
## corre la carrera (grados; 0 = +X, 90 = -Z); "back" / "front": metros de
## recta antes y después de la meta; "bend": curva leve (grados que gira de
## punta a punta)}. Devuelve [puntos de la punta de atrás a la de adelante
## (cada ~2 m), índice de la meta].
static func start_strip(start: Dictionary) -> Array:
	var finish := Vector2(float(start.get("x", 0.0)), float(start.get("z", 0.0)))
	var a := deg_to_rad(float(start.get("angle", 0.0)))
	var back := maxf(float(start.get("back", 40.0)), 2.0)
	var front := maxf(float(start.get("front", 60.0)), 2.0)
	var bend := deg_to_rad(clampf(float(start.get("bend", 0.0)), -10.0, 10.0))
	var total := back + front
	var nb := maxi(int(ceil(back / 2.0)), 1)
	var nf := maxi(int(ceil(front / 2.0)), 1)
	var pts: Array[Vector2] = []
	# Hacia atrás desde la meta.
	var p := finish
	var behind: Array[Vector2] = []
	for i in nb:
		var s := -back * (i + 0.5) / nb
		var h := a + bend * s / total
		p -= Vector2(cos(h), -sin(h)) * (back / nb)
		behind.append(p)
	behind.reverse()
	pts.append_array(behind)
	var f := pts.size()
	pts.append(finish)
	p = finish
	for i in nf:
		var s := front * (i + 0.5) / nf
		var h := a + bend * s / total
		p += Vector2(cos(h), -sin(h)) * (front / nf)
		pts.append(p)
	return [PackedVector2Array(pts), f]


func _build(control: PackedVector2Array, handles_in: Array, handles_out: Array, smoothing: int, start: Dictionary = {}) -> void:
	# Curva por los puntos de control.
	var raw := PackedVector2Array()
	# Muestras que no se suavizan (la recta de la meta).
	var fixed: Array[bool] = []
	if not start.is_empty():
		_build_with_start(control, handles_in, handles_out, start, raw, fixed)
	var n := 0 if not start.is_empty() else control.size()
	for i in n:
		var p0 := control[(i - 1 + n) % n]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[(i + 2) % n]
		var h_out: Variant = handles_out[i] if i < handles_out.size() else null
		var h_in: Variant = handles_in[(i + 1) % n] if (i + 1) % n < handles_in.size() else null
		if h_out == null and h_in == null:
			for j in 24:
				raw.append(_catmull_rom(p0, p1, p2, p3, j / 24.0))
		else:
			# Manija automática = la misma curva que Catmull-Rom.
			var c1: Vector2 = p1 + (h_out if h_out != null else (p2 - p0) / 6.0)
			var c2: Vector2 = p2 + (h_in if h_in != null else (p1 - p3) / 6.0)
			for j in 24:
				raw.append(_bezier(p1, c1, c2, p2, j / 24.0))
	# Suavizado (agranda las curvas más cerradas). La recta de la meta queda.
	var m := raw.size()
	for it in smoothing:
		var smooth := PackedVector2Array()
		smooth.resize(m)
		for i in m:
			if not fixed.is_empty() and fixed[i]:
				smooth[i] = raw[i]
			else:
				smooth[i] = (raw[(i - 1 + m) % m] + raw[i] * 2.0 + raw[(i + 1) % m]) * 0.25
		raw = smooth
	# Re-muestreo en tramos iguales: así el "ángulo" avanza parejo.
	var total := 0.0
	for i in m:
		total += raw[i].distance_to(raw[(i + 1) % m])
	var count := maxi(int(round(total / STEP)), 16)
	_seg_len = total / count
	points.resize(count)
	var seg := 0
	var seg_start := 0.0
	for k in count:
		var target := k * _seg_len
		while seg_start + raw[seg].distance_to(raw[(seg + 1) % m]) < target and seg < m - 1:
			seg_start += raw[seg].distance_to(raw[(seg + 1) % m])
			seg += 1
		var a := raw[seg]
		var b := raw[(seg + 1) % m]
		var l := maxf(a.distance_to(b), 0.0001)
		points[k] = a.lerp(b, clampf((target - seg_start) / l, 0.0, 1.0))
	_total = _seg_len * count
	radius = _total / TAU
	var c := Vector2.ZERO
	for p in points:
		c += p
	center = c / count
	_build_grid()


## Con recta de meta: meta -> punta de adelante (fija), curvas por los puntos
## de control (las manijas de las puntas siguen la recta, así empalma sin
## quiebre), punta de atrás -> meta (fija). La muestra 0 es la meta.
static func _build_with_start(control: PackedVector2Array, handles_in: Array, handles_out: Array,
		start: Dictionary, raw: PackedVector2Array, fixed: Array[bool]) -> void:
	var strip := start_strip(start)
	var pts: PackedVector2Array = strip[0]
	var f: int = strip[1]
	var last := pts.size() - 1
	for i in range(f, pts.size()):
		raw.append(pts[i])
		fixed.append(true)
	var front_end := pts[last]
	var back_end := pts[0]
	var dir_front := (pts[last] - pts[last - 1]).normalized()
	var dir_back := (pts[1] - pts[0]).normalized()
	var chain := PackedVector2Array([front_end])
	chain.append_array(control)
	chain.append(back_end)
	var ins: Array = [null]
	var outs: Array = [null]
	for i in control.size():
		ins.append(handles_in[i] if i < handles_in.size() else null)
		outs.append(handles_out[i] if i < handles_out.size() else null)
	ins.append(null)
	outs.append(null)
	var k := chain.size() - 1
	for i in k:
		var p1 := chain[i]
		var p2 := chain[i + 1]
		var p0 := chain[maxi(i - 1, 0)]
		var p3 := chain[mini(i + 2, k)]
		var reach := p1.distance_to(p2) / 3.0
		var c1: Vector2 = p1 + (dir_front * reach if i == 0 else (outs[i] if outs[i] != null else (p2 - p0) / 6.0))
		var c2: Vector2 = p2 + (-dir_back * reach if i + 1 == k else (ins[i + 1] if ins[i + 1] != null else (p1 - p3) / 6.0))
		# Sin repetir las puntas de la recta (ya están).
		for j in range(1, 24 if i + 1 == k else 25):
			raw.append(_bezier(p1, c1, c2, p2, j / 24.0))
			fixed.append(false)
	for i in f:
		raw.append(pts[i])
		fixed.append(true)


static func _bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p1


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


## Para cada celda cerca del recorrido, el tramo más cercano a su centro.
func _build_grid() -> void:
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var margin := half_width + 60.0
	var x0 := int(floor((lo.x - margin) / CELL))
	var x1 := int(floor((hi.x + margin) / CELL))
	var z0 := int(floor((lo.y - margin) / CELL))
	var z1 := int(floor((hi.y + margin) / CELL))
	for gx in range(x0, x1 + 1):
		for gz in range(z0, z1 + 1):
			var c := Vector2((gx + 0.5) * CELL, (gz + 0.5) * CELL)
			var best := 0
			var best_d := INF
			for i in points.size():
				var d := c.distance_squared_to(points[i])
				if d < best_d:
					best_d = d
					best = i
			if best_d < (margin + CELL) * (margin + CELL):
				_grid[Vector2i(gx, gz)] = best


## Proyección sobre el recorrido: Vector3(distancia recorrida, lateral, distancia²).
func _project(p: Vector2) -> Vector3:
	var count := points.size()
	var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	var from := 0
	var to := count
	if _grid.has(key):
		var window := int(CELL / _seg_len * 1.5) + 4
		from = int(_grid[key]) - window
		to = int(_grid[key]) + window + 1
	var best := Vector3(0.0, 0.0, INF)
	for k in range(from, to):
		var i := posmod(k, count)
		var a := points[i]
		var b := points[(i + 1) % count]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best.z:
			var dir := ab.normalized()
			var normal := Vector2(dir.y, -dir.x)
			best = Vector3(i * _seg_len + t * _seg_len, (p - q).dot(normal), d)
	return best


func angle_of(p: Vector3) -> float:
	var s := _project(Vector2(p.x, p.z)).x
	return wrapf(s / _total * TAU, -PI, PI)


func locate(p: Vector3) -> Vector2:
	var pr := _project(Vector2(p.x, p.z))
	return Vector2(wrapf(pr.x / _total * TAU, -PI, PI), pr.y)


func lateral_of(p: Vector3) -> float:
	return _project(Vector2(p.x, p.z)).y


func position_at(angle: float, lateral: float = 0.0) -> Vector3:
	var s := wrapf(angle, 0.0, TAU) / TAU * _total
	var count := points.size()
	var i := int(s / _seg_len) % count
	var t := (s - i * _seg_len) / _seg_len
	var a := points[i]
	var b := points[(i + 1) % count]
	var dir := _smooth_dir(i, t)
	var normal := Vector2(dir.y, -dir.x)
	var p := a.lerp(b, t) + normal * lateral
	return Vector3(p.x, 0.0, p.y)


func tangent_at(angle: float) -> Vector3:
	var s := wrapf(angle, 0.0, TAU) / TAU * _total
	var i := int(s / _seg_len) % points.size()
	var t := (s - i * _seg_len) / _seg_len
	var dir := _smooth_dir(i, t)
	return Vector3(dir.x, 0.0, dir.y)


## Dirección suavizada entre el tramo i y el siguiente (sin saltos en las curvas).
func _smooth_dir(i: int, t: float) -> Vector2:
	var count := points.size()
	var d0 := points[(i + 1) % count] - points[i]
	var d1 := points[(i + 2) % count] - points[(i + 1) % count]
	return d0.normalized().lerp(d1.normalized(), t).normalized()


func length() -> float:
	return _total
