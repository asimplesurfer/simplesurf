class_name PathTrack
extends TrackSpace
## Circuito con curvas: un recorrido cerrado (no un círculo). Tiene las mismas
## funciones que TrackSpace, así el resto del juego (vueltas, posiciones, bots,
## olas) funciona igual:
## - "ángulo": cuánto avanzó por el recorrido, de -PI a PI (la meta en 0).
## - lateral: distancia a la línea central (+ a la izquierda del que corre).
##
## El recorrido se arma con una curva suave (Catmull-Rom) que pasa por los
## puntos de control, se suaviza y se re-muestrea en tramos iguales.

## Distancia entre muestras del recorrido (m).
const STEP := 2.0
## Tamaño de celda de la grilla que acelera la búsqueda del punto más cercano (m).
const CELL := 20.0

## Puntos del recorrido (cerrado, separados STEP metros más o menos).
var points: PackedVector2Array = PackedVector2Array()
var _seg_len: float = STEP
var _total: float = 1.0
var _grid: Dictionary = {}


func _init(control: PackedVector2Array = PackedVector2Array(), p_half_width: float = 20.0) -> void:
	half_width = p_half_width
	if control.size() >= 3:
		_build(control)


func _build(control: PackedVector2Array) -> void:
	# Curva suave por los puntos de control.
	var raw := PackedVector2Array()
	var n := control.size()
	for i in n:
		var p0 := control[(i - 1 + n) % n]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[(i + 2) % n]
		for j in 24:
			raw.append(_catmull_rom(p0, p1, p2, p3, j / 24.0))
	# Suavizado (agranda las curvas más cerradas).
	var m := raw.size()
	for it in 60:
		var smooth := PackedVector2Array()
		smooth.resize(m)
		for i in m:
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
