class_name BezierShape
extends RefCounted
## Una figura cerrada dibujada con puntos y manijas Bézier (como el recorrido:
## ver world/maps/README.md). Las piezas que se dibujan como una zona (rocas,
## cuevas) la usan para leer su figura del mapa.
##
## Cada punto es [x, z] (manijas automáticas: la curva pasa suave por los
## vecinos) o {"p": [x, z], "in": [dx, dz], "out": [dx, dz]}.

var points := PackedVector2Array()
var handles_in: Array = []
var handles_out: Array = []


static func parse(nodes: Array) -> BezierShape:
	var s := BezierShape.new()
	for node in nodes:
		if node is Array and node.size() >= 2:
			s.points.append(Vector2(float(node[0]), float(node[1])))
			s.handles_in.append(null)
			s.handles_out.append(null)
		elif node is Dictionary and node.has("p"):
			s.points.append(Vector2(float(node.p[0]), float(node.p[1])))
			s.handles_in.append(_vec(node.get("in")))
			s.handles_out.append(_vec(node.get("out")))
	return s


static func _vec(v: Variant) -> Variant:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() >= 2 else null


func is_valid() -> bool:
	return points.size() >= 3


## Manijas de salida y de entrada del tramo i -> i+1 (las automáticas, como
## Catmull-Rom).
func segment_controls(i: int) -> Array[Vector2]:
	var n := points.size()
	var p0 := points[(i - 1 + n) % n]
	var p1 := points[i]
	var p2 := points[(i + 1) % n]
	var p3 := points[(i + 2) % n]
	var h_out: Variant = handles_out[i]
	var h_in: Variant = handles_in[(i + 1) % n]
	var c1: Vector2 = p1 + (h_out if h_out != null else (p2 - p0) / 6.0)
	var c2: Vector2 = p2 + (h_in if h_in != null else (p1 - p3) / 6.0)
	return [p1, c1, c2, p2]


## El contorno como polígono, con un punto cada `step` metros más o menos.
## Siempre en sentido antihorario (visto desde arriba con z hacia abajo).
func polygon(step: float = 4.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_valid():
		return out
	for i in points.size():
		var c := segment_controls(i)
		var approx := c[0].distance_to(c[1]) + c[1].distance_to(c[2]) + c[2].distance_to(c[3])
		var count := maxi(int(ceil(approx / step)), 1)
		for j in count:
			out.append(bezier(c[0], c[1], c[2], c[3], float(j) / count))
	if Geometry2D.is_polygon_clockwise(out):
		out.reverse()
	return out


static func bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p1


## Distancia de un punto al borde de un polígono.
static func distance_to_edge(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best
