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
##
## Bifurcaciones: además del recorrido principal puede tener ramales, caminos
## alternativos que salen de un punto de control y vuelven a entrar en otro
## más adelante (ver Branch). En un mismo tramo puede haber varios. El avance
## por un ramal se cuenta como si fuera el tramo de la principal que reemplaza
## (proporcional al largo), así vueltas y posiciones no cambian. Cada ramal es
## una "ruta": la 0 es la principal y la k, el ramal k (en el orden del mapa).

## Distancia entre muestras del recorrido (m).
const STEP := 2.0
## Tamaño de celda de la grilla que acelera la búsqueda del punto más cercano (m).
const CELL := 20.0

## Puntos del recorrido (cerrado, separados STEP metros más o menos).
var points: PackedVector2Array = PackedVector2Array()
var _seg_len: float = STEP
var _total: float = 1.0
var _grid: Dictionary = {}
## Distancia recorrida (m) en la que pasa por cada punto de control.
var _control_s: PackedFloat32Array = PackedFloat32Array()
## Ramales (la ruta k es branches[k - 1]).
var branches: Array[Branch] = []
## Tramos con más de un camino, en orden: {"from", "to": metros de la
## principal; "routes": las rutas que se pueden tomar (la 0 primero)}.
var _groups: Array[Dictionary] = []
## Recorridos completos de una vuelta eligiendo un camino en cada tramo (ver variant).
var _variants: Dictionary = {}


## Un camino alternativo: sale de la principal en `s_from` y vuelve a entrar
## en `s_to` (metros de la principal). Es una línea abierta, de punta a punta.
class Branch:
	var points: PackedVector2Array = PackedVector2Array()
	var seg_len: float = 2.0
	var length: float = 1.0
	var s_from: float = 0.0
	var s_to: float = 1.0
	## Índices de los puntos de control de la principal de donde sale y adonde llega.
	var from_index: int = 0
	var to_index: int = 0
	var grid: Dictionary = {}

	## Metros de la principal que le corresponden a `s` metros del ramal.
	func main_s(s: float) -> float:
		return s_from + s / length * (s_to - s_from)

	## Metros del ramal que le corresponden a `ms` metros de la principal.
	func own_s(ms: float) -> float:
		return (ms - s_from) / maxf(s_to - s_from, 0.001) * length


## `handles_in` / `handles_out`: manija de entrada y de salida de cada punto
## (relativas al punto; null o vacío = automática). `smoothing`: pasadas de
## suavizado (redondean las curvas más cerradas).
## `start`: recta de la meta (opcional, ver start_strip). Si está, la meta va
## en esa recta, la pista sale de su punta de adelante, pasa por los puntos de
## control y vuelve a entrar por la punta de atrás. La recta no se suaviza.
## `p_branches`: ramales, cada uno {"from", "to": índices de los puntos de
## control de donde sale y adonde vuelve (from < to); "path": sus puntos;
## "in" / "out": sus manijas (como las de la principal)}.
func _init(
	control: PackedVector2Array = PackedVector2Array(), p_half_width: float = 20.0,
	handles_in: Array = [], handles_out: Array = [], smoothing: int = 60, start: Dictionary = {},
	p_branches: Array = []
) -> void:
	half_width = p_half_width
	if control.size() >= (1 if not start.is_empty() else 3):
		_build(control, handles_in, handles_out, smoothing, start)
		for b in p_branches:
			_add_branch(b, smoothing)
		_build_groups()


## Una pista armada directo con sus muestras (una vuelta cerrada, ya suave).
static func from_points(pts: PackedVector2Array, p_half_width: float) -> PathTrack:
	var t := PathTrack.new(PackedVector2Array(), p_half_width)
	t._finish_build(pts, [])
	return t


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
	# Muestra (de raw) por la que pasa cada punto de control.
	var at_control: Array[int] = []
	if not start.is_empty():
		_build_with_start(control, handles_in, handles_out, start, raw, fixed, at_control)
	var n := 0 if not start.is_empty() else control.size()
	for i in n:
		at_control.append(raw.size())
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
	_finish_build(raw, at_control)


## Re-muestreo en tramos iguales (así el "ángulo" avanza parejo), centro y grilla.
## `at_control`: muestras de raw por las que pasan los puntos de control.
func _finish_build(raw: PackedVector2Array, at_control: Array[int]) -> void:
	var m := raw.size()
	var total := 0.0
	_control_s.resize(at_control.size())
	var next_c := 0
	for i in m:
		while next_c < at_control.size() and at_control[next_c] == i:
			_control_s[next_c] = total
			next_c += 1
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
	_grid = _grid_for(points, true)


## Con recta de meta: meta -> punta de adelante (fija), curvas por los puntos
## de control (las manijas de las puntas siguen la recta, así empalma sin
## quiebre), punta de atrás -> meta (fija). La muestra 0 es la meta.
static func _build_with_start(control: PackedVector2Array, handles_in: Array, handles_out: Array,
		start: Dictionary, raw: PackedVector2Array, fixed: Array[bool], at_control: Array[int] = []) -> void:
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
		if i + 1 < k:
			# La última muestra de este tramo es el punto de control i.
			at_control.append(raw.size() - 1)
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


## Para cada celda cerca de la línea `pts`, la muestra más cercana a su centro.
func _grid_for(pts: PackedVector2Array, _closed: bool) -> Dictionary:
	var grid := {}
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
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
			for i in pts.size():
				var d := c.distance_squared_to(pts[i])
				if d < best_d:
					best_d = d
					best = i
			if best_d < (margin + CELL) * (margin + CELL):
				grid[Vector2i(gx, gz)] = best
	return grid


## Proyección sobre la principal: Vector3(distancia recorrida, lateral, distancia²).
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


## Proyección sobre un ramal: Vector3(metros del ramal, lateral, distancia²).
## Lejos del ramal (fuera de su grilla), distancia² infinita.
func _project_branch(b: Branch, p: Vector2) -> Vector3:
	var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	if not b.grid.has(key):
		return Vector3(0.0, 0.0, INF)
	var count := b.points.size()
	var window := int(CELL / b.seg_len * 1.5) + 4
	var from := maxi(int(b.grid[key]) - window, 0)
	var to := mini(int(b.grid[key]) + window + 1, count - 1)
	var best := Vector3(0.0, 0.0, INF)
	for i in range(from, to):
		var a := b.points[i]
		var ab := b.points[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best.z:
			var dir := ab.normalized()
			var normal := Vector2(dir.y, -dir.x)
			best = Vector3(i * b.seg_len + t * b.seg_len, (p - q).dot(normal), d)
	return best


## Proyección sobre el camino más cercano (la principal o un ramal):
## Vector4(metros de la principal, lateral, distancia², ruta).
func _project_all(p: Vector2) -> Vector4:
	var best := Vector4(0.0, 0.0, INF, 0.0)
	for k in branches.size():
		var b := branches[k]
		var pr := _project_branch(b, p)
		if pr.z < best.z:
			best = Vector4(b.main_s(pr.x), pr.y, pr.z, float(k + 1))
	# Lejos de la principal (fuera de su grilla) y cerca de un ramal: no hace
	# falta recorrer toda la principal.
	if best.z < INF and not _grid.has(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))):
		return best
	var m := _project(p)
	if m.z <= best.z:
		best = Vector4(m.x, m.y, m.z, 0.0)
	return best


func angle_of(p: Vector3) -> float:
	var s := _project_all(Vector2(p.x, p.z)).x
	return wrapf(s / _total * TAU, -PI, PI)


func locate(p: Vector3) -> Vector2:
	var pr := _project_all(Vector2(p.x, p.z))
	return Vector2(wrapf(pr.x / _total * TAU, -PI, PI), pr.y)


func lateral_of(p: Vector3) -> float:
	return _project_all(Vector2(p.x, p.z)).y


func locate_route(p: Vector3) -> Vector3:
	var pr := _project_all(Vector2(p.x, p.z))
	return Vector3(wrapf(pr.x / _total * TAU, -PI, PI), pr.y, pr.w)


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


# ------------------------------------------------------------- ramales

## Arma un ramal (ver _init) y lo suma a `branches`. Sale de la principal en
## el punto de control `from` y vuelve en `to`, mirando para el mismo lado que
## la principal en las dos puntas (así se abre y se cierra de a poco).
func _add_branch(d: Dictionary, smoothing: int) -> void:
	var fi := int(d.get("from", -1))
	var ti := int(d.get("to", -1))
	var ctrl: PackedVector2Array = d.get("path", PackedVector2Array())
	if fi < 0 or ti <= fi or ti >= _control_s.size() or ctrl.is_empty():
		push_error("ramal mal armado (de %d a %d)" % [fi, ti])
		return
	var ins: Array = d.get("in", [])
	var outs: Array = d.get("out", [])
	var b := Branch.new()
	b.from_index = fi
	b.to_index = ti
	b.s_from = _control_s[fi]
	b.s_to = _control_s[ti]
	var a_pos := _main_point(b.s_from)
	var b_pos := _main_point(b.s_to)
	var a_dir := _main_dir(b.s_from)
	var b_dir := _main_dir(b.s_to)
	# Entrada y salida: unos metros de la principal (fijos), así el suavizado
	# empalma sin quiebre con ella.
	const LEAD := 16.0
	var raw := PackedVector2Array()
	var fixed: Array[bool] = []
	var lead_n := int(LEAD / STEP)
	for k in range(lead_n, 0, -1):
		raw.append(_main_point(b.s_from - k * STEP))
		fixed.append(true)
	var first := raw.size()
	var chain := PackedVector2Array([a_pos])
	chain.append_array(ctrl)
	chain.append(b_pos)
	var last := chain.size() - 1
	raw.append(a_pos)
	fixed.append(true)
	for i in last:
		var p1 := chain[i]
		var p2 := chain[i + 1]
		var p0 := chain[maxi(i - 1, 0)]
		var p3 := chain[mini(i + 2, last)]
		var reach := p1.distance_to(p2) / 3.0
		var h_out: Variant = outs[i - 1] if i >= 1 and i - 1 < outs.size() else null
		var h_in: Variant = ins[i] if i + 1 < last and i < ins.size() else null
		var c1: Vector2 = p1 + (a_dir * reach if i == 0 else (h_out if h_out != null else (p2 - p0) / 6.0))
		var c2: Vector2 = p2 + (-b_dir * reach if i + 1 == last else (h_in if h_in != null else (p1 - p3) / 6.0))
		for j in range(1, 25):
			raw.append(_bezier(p1, c1, c2, p2, j / 24.0))
			fixed.append(i + 1 == last and j == 24)
	var end := raw.size() - 1
	for k in range(1, lead_n + 1):
		raw.append(_main_point(b.s_to + k * STEP))
		fixed.append(true)
	# Suavizado (como la principal, pero abierto: las puntas no se tocan).
	var m := raw.size()
	for it in smoothing:
		var smooth := raw.duplicate()
		for i in range(1, m - 1):
			if not fixed[i]:
				smooth[i] = (raw[i - 1] + raw[i] * 2.0 + raw[i + 1]) * 0.25
		raw = smooth
	var line := raw.slice(first, end + 1)
	# Re-muestreo en tramos iguales.
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var count := maxi(int(round(total / STEP)), 2)
	b.seg_len = total / count
	b.length = total
	b.points.resize(count + 1)
	var seg := 0
	var seg_start := 0.0
	for k in count + 1:
		var target := minf(k * b.seg_len, total)
		while seg < line.size() - 2 and seg_start + line[seg].distance_to(line[seg + 1]) < target:
			seg_start += line[seg].distance_to(line[seg + 1])
			seg += 1
		var l := maxf(line[seg].distance_to(line[seg + 1]), 0.0001)
		b.points[k] = line[seg].lerp(line[seg + 1], clampf((target - seg_start) / l, 0.0, 1.0))
	b.grid = _grid_for(b.points, false)
	branches.append(b)


## Punto de la línea central de la principal a `s` metros de la meta.
func _main_point(s: float) -> Vector2:
	var p := position_at(wrapf(s, 0.0, _total) / _total * TAU)
	return Vector2(p.x, p.z)


func _main_dir(s: float) -> Vector2:
	var t := tangent_at(wrapf(s, 0.0, _total) / _total * TAU)
	return Vector2(t.x, t.z).normalized()


## Junta los ramales que salen y llegan a los mismos puntos: cada tramo con
## más de un camino es un grupo.
func _build_groups() -> void:
	_groups.clear()
	var by_key := {}
	for k in branches.size():
		var b := branches[k]
		var key := Vector2i(b.from_index, b.to_index)
		if not by_key.has(key):
			by_key[key] = {"from": b.s_from, "to": b.s_to, "routes": [0]}
			_groups.append(by_key[key])
		(by_key[key].routes as Array).append(k + 1)
	_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.from) < float(b.from))


func route_count() -> int:
	return branches.size() + 1


func groups() -> Array[Dictionary]:
	return _groups


## Grupo (índice en groups()) al que pertenece la ruta (-1 si es la principal).
func group_of_route(route: int) -> int:
	for g in _groups.size():
		if route != 0 and (_groups[g].routes as Array).has(route):
			return g
	return -1


## Grupo en el que está ese "ángulo" de la principal (-1 si en ninguno).
func group_at(angle: float) -> int:
	var s := wrapf(angle, 0.0, TAU) / TAU * _total
	for g in _groups.size():
		if s > float(_groups[g].from) and s < float(_groups[g].to):
			return g
	return -1


## Largo (m) de una ruta en su tramo: el ramal entero, o la principal entre
## las puntas del grupo.
func route_length(route: int, group: int) -> float:
	if route > 0 and route <= branches.size():
		return branches[route - 1].length
	return float(_groups[group].to) - float(_groups[group].from)


## Los puntos de la línea central de un ramal (de la salida a la vuelta).
func branch_points(route: int) -> PackedVector2Array:
	return branches[route - 1].points


## Todas las líneas centrales (la principal y los ramales) en una sola lista.
func all_points() -> PackedVector2Array:
	var out := points.duplicate()
	for b in branches:
		out.append_array(b.points)
	return out


func position_on(route: int, angle: float, lateral: float = 0.0) -> Vector3:
	var b := _branch_at(route, angle)
	if b == null:
		return position_at(angle, lateral)
	var s := b.own_s(wrapf(angle, 0.0, TAU) / TAU * _total)
	return branch_position(b, s, lateral)


func tangent_on(route: int, angle: float) -> Vector3:
	var b := _branch_at(route, angle)
	if b == null:
		return tangent_at(angle)
	var d := _branch_dir(b, b.own_s(wrapf(angle, 0.0, TAU) / TAU * _total))
	return Vector3(d.x, 0.0, d.y)


## Punto de un ramal a `s` metros de su salida, corrido `lateral` metros.
func branch_position(b: Branch, s: float, lateral: float = 0.0) -> Vector3:
	var n := b.points.size() - 1
	var f := clampf(s / b.seg_len, 0.0, float(n))
	var i := mini(int(f), n - 1)
	var dir := _branch_dir(b, s)
	var p := b.points[i].lerp(b.points[i + 1], f - i) + Vector2(dir.y, -dir.x) * lateral
	return Vector3(p.x, 0.0, p.y)


func _branch_dir(b: Branch, s: float) -> Vector2:
	var n := b.points.size() - 1
	var f := clampf(s / b.seg_len, 0.0, float(n))
	var i := mini(int(f), n - 1)
	var d0 := b.points[i + 1] - b.points[i]
	var d1 := b.points[mini(i + 2, n)] - b.points[i + 1] if i + 1 < n else d0
	return d0.normalized().lerp(d1.normalized(), f - i).normalized()


## El ramal de esa ruta si el ángulo cae en su tramo (si no, null: ahí es la principal).
func _branch_at(route: int, angle: float) -> Branch:
	if route <= 0 or route > branches.size():
		return null
	var b := branches[route - 1]
	var s := wrapf(angle, 0.0, TAU) / TAU * _total
	if s < b.s_from or s > b.s_to:
		return null
	return b


## Una vuelta entera eligiendo un camino en cada tramo: `choices[g]` es la
## ruta del grupo g. Es una pista común (sin ramales) que empieza en la meta;
## sus "ángulos" son los suyos, no los de esta. La usan los bots para seguir
## el camino que eligieron y las olas tubo. Se arma una vez por combinación.
func variant(choices: Array) -> TrackSpace:
	if _groups.is_empty():
		return self
	var key := str(choices)
	if _variants.has(key):
		return _variants[key]
	var pts := PackedVector2Array()
	var g := 0
	var i := 0
	var count := points.size()
	while i < count:
		var s := i * _seg_len
		if g < _groups.size() and s >= float(_groups[g].from):
			var route: int = choices[g] if g < choices.size() else 0
			if route == 0:
				# Por la principal: sigue normal hasta el final del tramo.
				while i < count and i * _seg_len < float(_groups[g].to):
					pts.append(points[i])
					i += 1
			else:
				pts.append_array(branches[route - 1].points)
				while i < count and i * _seg_len <= float(_groups[g].to):
					i += 1
			g += 1
			continue
		pts.append(points[i])
		i += 1
	var v := PathTrack.from_points(_dedupe(pts), half_width)
	_variants[key] = v
	return v


## Todas las combinaciones de caminos (para calcular de antemano lo de los bots).
func all_choices() -> Array:
	var out: Array = [[]]
	for grp in _groups:
		var next: Array = []
		for c in out:
			for r in grp.routes:
				next.append((c as Array) + [r])
		out = next
	return out


## Saca puntos repetidos (las puntas de un ramal caen sobre la principal).
static func _dedupe(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.25:
			out.append(p)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 0.25:
		out.remove_at(out.size() - 1)
	return out
