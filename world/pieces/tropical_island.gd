class_name TropicalIslandPiece
extends MapPiece
## Isla tropical dibujada como figura (puntos y manijas Bézier, como la pista):
## toda la figura es arena con playa que entra al agua; más adentro, selva:
## pasto, arbustos de varios verdes y muchas palmeras. Las de la orilla se
## inclinan hacia el mar; las de adentro forman un techo de hojas.
## Se choca como una isla: subirse a la arena tira al surfista.
##
## Para que no pese: hay unas pocas palmeras modelo (world/pieces/lib/
## palm_mesh.gd) que se repiten con MultiMesh (una llamada de dibujo por
## modelo); las de adentro de la selva son más simples, y los helechos y
## arbustos no hacen sombra y no se dibujan de lejos.

const REQUIRED := ["shape"]

## Contorno visto desde arriba: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var shape: Array = []
## Ancho de la franja de arena antes de la selva (m).
var beach_width: float = 12.0
## Palmeras cada 100 m² (más = más tupida).
var palm_density: float = 1.8
## Piedras sobre la arena.
var rocks: int = 3
var sand_color: Color = Color("f2d8a0")
var grass_color: Color = Color("3f7f2c")
var leaf_color: Color = Color("2f8f2c")
var shape_seed: int = 1

const SAND_Y := 0.55
const GRASS_Y := 0.85
## Distancia de la orilla a la que tira al surfista (m, la playa entra al agua).
const SHORE := 1.5

var _outline := PackedVector2Array()
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _grass: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()
var _palms: int = 0


func build(course: Course) -> void:
	var bez := BezierShape.parse(shape)
	if not bez.is_valid():
		push_error("tropical_island: la figura necesita al menos 3 puntos")
		return
	_outline = bez.polygon(4.0)
	_lo = _outline[0]
	_hi = _outline[0]
	for p in _outline:
		_lo = _lo.min(p)
		_hi = _hi.max(p)
	_rng.seed = shape_seed
	# Achicar una figura simple no deja agujeros: todo lo que sale es selva.
	for g in Geometry2D.offset_polygon(_outline, -beach_width):
		if g.size() >= 3:
			_grass.append(g)
	var root := Node3D.new()
	root.name = "TropicalIsland"
	course.add_child(root, true)
	root.add_child(_sand_mesh())
	if not _grass.is_empty():
		root.add_child(_grass_mesh())
	_add_vegetation(root)


## true si (x, z) está sobre la isla (con la playa que entra al agua).
func covers(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if p.x < _lo.x - SHORE or p.y < _lo.y - SHORE or p.x > _hi.x + SHORE or p.y > _hi.y + SHORE:
		return false
	return Geometry2D.is_point_in_polygon(p, _outline) or BezierShape.distance_to_edge(_outline, p) < SHORE


## Subirse a la arena: se cae y queda afuera, en el agua.
func affect_rider(course: Course, rider: Rider) -> bool:
	if not course.hazards_enabled or rider.is_fallen() or _outline.is_empty():
		return false
	if not covers(rider.position.x, rider.position.z):
		return false
	var p := Vector2(rider.position.x, rider.position.z)
	var q := _closest_edge_point(p)
	var out := _outward_at(q, p)
	var safe := q + out * (SHORE + 3.0)
	course.crash(rider, Vector3(safe.x, rider.position.y, safe.y))
	return true


func _closest_edge_point(p: Vector2) -> Vector2:
	var best := _outline[0]
	var best_d := INF
	var n := _outline.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, _outline[i], _outline[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


## Dirección hacia afuera de la isla en un punto del borde.
func _outward_at(q: Vector2, from: Vector2) -> Vector2:
	var d := q - from
	if d.length() < 0.01:
		d = q - _center()
	d = d.normalized()
	# Si `from` estaba afuera, d apunta hacia adentro.
	if not Geometry2D.is_point_in_polygon(q - d * 0.5, _outline):
		d = -d
	return d


func _center() -> Vector2:
	return (_lo + _hi) * 0.5


## Normal hacia afuera de cada punto del contorno.
func _normals(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var t := (poly[(i + 1) % n] - poly[(i - 1 + n) % n]).normalized()
		var nr := Vector2(t.y, -t.x)
		if Geometry2D.is_point_in_polygon(poly[i] + nr * 0.5, poly):
			nr = -nr
		out.append(nr)
	return out


## Arena: arriba plana y una playa en pendiente que entra al agua.
func _sand_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normals := _normals(_outline)
	var n := _outline.size()
	for i in n:
		var j := (i + 1) % n
		var a := _outline[i]
		var b := _outline[j]
		var a2 := a + normals[i] * 9.0
		var b2 := b + normals[j] * 9.0
		var na := Vector3(normals[i].x * 0.4, 1.0, normals[i].y * 0.4).normalized()
		var nb := Vector3(normals[j].x * 0.4, 1.0, normals[j].y * 0.4).normalized()
		for v in [[a, SAND_Y, na], [b, SAND_Y, nb], [b2, -1.8, nb], [a, SAND_Y, na], [b2, -1.8, nb], [a2, -1.8, na]]:
			st.set_normal(v[2])
			st.add_vertex(Vector3(v[0].x, v[1], v[0].y))
	var idx := Geometry2D.triangulate_polygon(_outline)
	for k in idx:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(_outline[k].x, SAND_Y, _outline[k].y))
	var mat := ToonMaterial.make(sand_color, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Sand"
	mi.mesh = st.commit()
	return mi


## Pasto de la selva: un poco más alto que la arena. El borde no corta de
## golpe: una franja de FADE metros baja hasta la arena y pasa del verde al
## color de la arena (y encima van helechos).
const FADE := 6.0


func _grass_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sandy := grass_color.lerp(sand_color, 0.55)
	for g in _grass:
		var normals := _normals(g)
		var n := g.size()
		# Tres anillos: borde del pasto, mitad (pasto con arena) y arena.
		var rings := [
			[0.0, GRASS_Y, grass_color], [FADE * 0.45, lerpf(GRASS_Y, SAND_Y, 0.6) + 0.03, sandy],
			[FADE, SAND_Y + 0.02, sand_color],
		]
		for r in 2:
			for i in n:
				var j := (i + 1) % n
				var a0: Vector2 = g[i] + normals[i] * rings[r][0]
				var b0: Vector2 = g[j] + normals[j] * rings[r][0]
				var a1: Vector2 = g[i] + normals[i] * rings[r + 1][0]
				var b1: Vector2 = g[j] + normals[j] * rings[r + 1][0]
				for v in [[a0, r], [b0, r], [b1, r + 1], [a0, r], [b1, r + 1], [a1, r + 1]]:
					st.set_normal(Vector3.UP)
					st.set_color(rings[v[1]][2])
					st.add_vertex(Vector3(v[0].x, rings[v[1]][1], v[0].y))
		for k in Geometry2D.triangulate_polygon(g):
			st.set_normal(Vector3.UP)
			st.set_color(grass_color)
			st.add_vertex(Vector3(g[k].x, GRASS_Y, g[k].y))
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Grass"
	mi.mesh = st.commit()
	return mi


func _on_grass(p: Vector2) -> bool:
	for g in _grass:
		if Geometry2D.is_point_in_polygon(p, g):
			return true
	return false


## Palmeras, helechos, arbustos y piedras: todo en MultiMesh. Hay unas pocas
## palmeras modelo (PalmMesh) que se repiten giradas y de distinto tamaño:
## una MultiMesh por modelo.
const EDGE_MODELS := 6
const INNER_MODELS := 3
const FERN_MODELS := 3


func _add_vegetation(root: Node3D) -> void:
	var edge_models: Array[Mesh] = []
	for i in EDGE_MODELS:
		edge_models.append(PalmMesh.build(shape_seed * 31 + i, _rng.randf_range(8.5, 12.0), lerpf(0.3, 0.95, float(i) / (EDGE_MODELS - 1))))
	var inner_models: Array[Mesh] = []
	for i in INNER_MODELS:
		inner_models.append(PalmMesh.build(shape_seed * 37 + i, _rng.randf_range(10.0, 13.5), _rng.randf_range(0.0, 0.25), 0.5))
	var fern_models: Array[Mesh] = []
	for i in FERN_MODELS:
		fern_models.append(PalmMesh.build(shape_seed * 41 + i, _rng.randf_range(1.6, 2.6), 0.0, 0.3, false))
	var edge: Array = []
	var inner: Array = []
	var ferns: Array = []
	for i in EDGE_MODELS:
		edge.append([] as Array[Transform3D])
	for i in INNER_MODELS:
		inner.append([] as Array[Transform3D])
	for i in FERN_MODELS:
		ferns.append([] as Array[Transform3D])
	var bushes: Array[Transform3D] = []
	var bush_colors: Array[Color] = []
	var stones: Array[Transform3D] = []

	# Palmeras: grilla movida (más pareja que al azar), más tupida en la orilla.
	var spacing := sqrt(100.0 / maxf(palm_density, 0.05))
	var x := _lo.x + spacing * 0.5
	while x < _hi.x:
		var z := _lo.y + spacing * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-0.45, 0.45) * spacing, z + _rng.randf_range(-0.45, 0.45) * spacing)
			z += spacing
			if not Geometry2D.is_point_in_polygon(p, _outline):
				continue
			var depth := BezierShape.distance_to_edge(_outline, p)
			if depth < beach_width * 0.4:
				continue
			var q := _closest_edge_point(p)
			var out := (q - p).normalized() if q.distance_to(p) > 0.01 else Vector2.RIGHT
			var ground := GRASS_Y if _on_grass(p) else SAND_Y
			if depth < beach_width + 6.0:
				# Orilla: inclinadas hacia el mar (y a veces otra al lado).
				edge[_rng.randi() % EDGE_MODELS].append(_placed(p, ground, out.rotated(_rng.randf_range(-0.6, 0.6)), _rng.randf_range(0.85, 1.15)))
				_palms += 1
				_fern_at(ferns, p, ground, 1.3, 1.8)
				if _rng.randf() < 0.35:
					var p2 := p + out.rotated(PI * 0.5 * signf(_rng.randf() - 0.5)) * _rng.randf_range(2.0, 3.5)
					edge[_rng.randi() % EDGE_MODELS].append(_placed(p2, ground, out.rotated(_rng.randf_range(-0.9, 0.9)), _rng.randf_range(0.75, 1.0)))
					_palms += 1
					_fern_at(ferns, p2, ground, 1.2, 1.6)
			else:
				inner[_rng.randi() % INNER_MODELS].append(_placed(p, ground, Vector2.RIGHT.rotated(_rng.randf() * TAU), _rng.randf_range(0.85, 1.15)))
				_palms += 1
				_fern_at(ferns, p, ground, 1.3, 1.8)
		x += spacing

	# Borde del pasto: una franja de helechos sobre la transición a la arena.
	for g in _grass:
		var gn := _normals(g)
		var along := 0.0
		for i in g.size():
			along += g[i].distance_to(g[(i + 1) % g.size()])
			if along < 2.6:
				continue
			along = 0.0
			var p := g[i] + gn[i] * _rng.randf_range(-1.5, FADE * 0.8)
			_fern_at(ferns, p, lerpf(GRASS_Y, SAND_Y, 0.5), 0.9, 1.5)

	# Suelo de la selva: helechos y matas oscuras que tapan el pasto.
	var bs := 4.0
	x = _lo.x + bs * 0.5
	while x < _hi.x:
		var z := _lo.y + bs * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-1.5, 1.5), z + _rng.randf_range(-1.5, 1.5))
			z += bs
			if not _on_grass(p):
				continue
			if _rng.randf() < 0.4:
				ferns[_rng.randi() % FERN_MODELS].append(_placed(p, GRASS_Y - 0.2, Vector2.RIGHT.rotated(_rng.randf() * TAU), _rng.randf_range(0.8, 1.4)))
			else:
				var r := _rng.randf_range(2.2, 4.0)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * _rng.randf_range(0.7, 1.1), r))
				bushes.append(Transform3D(basis, Vector3(p.x, GRASS_Y + r * 0.3, p.y)))
				bush_colors.append(Color("1d4f1f").lerp(Color("36802a"), _rng.randf()))
		x += bs

	# Unas piedras en la arena.
	var normals := _normals(_outline)
	var n := _outline.size()
	for i in rocks:
		var k := _rng.randi() % n
		var p := _outline[k] - normals[k] * _rng.randf_range(2.0, beach_width * 0.4)
		var r := _rng.randf_range(1.2, 2.6)
		var basis := Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())).scaled(Vector3(r, r * 0.7, r))
		stones.append(Transform3D(basis, Vector3(p.x, SAND_Y + r * 0.2, p.y)))

	for i in EDGE_MODELS:
		root.add_child(_multi("Palms%d" % i, edge_models[i], edge[i], [], true))
	for i in INNER_MODELS:
		root.add_child(_multi("JunglePalms%d" % i, inner_models[i], inner[i], [], true))
	for i in FERN_MODELS:
		var f := _multi("Ferns%d" % i, fern_models[i], ferns[i], [], false)
		f.visibility_range_end = 360.0
		root.add_child(f)
	var b := _multi("Bushes", _bush_mesh(), bushes, bush_colors, false)
	b.visibility_range_end = 520.0
	root.add_child(b)
	root.add_child(_multi("Stones", _stone_mesh(), stones, [], true))


## Un helecho en `p` (un poco movido), de un tamaño entre `lo` y `hi`.
func _fern_at(ferns: Array, p: Vector2, ground: float, lo: float, hi: float) -> void:
	var q := p + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
	ferns[_rng.randi() % FERN_MODELS].append(_placed(q, ground + 0.05, Vector2.RIGHT.rotated(_rng.randf() * TAU), _rng.randf_range(lo, hi)))


## Dónde va una palmera modelo: en `p`, inclinada hacia `dir` (los modelos se
## arman inclinados hacia +X) y con un tamaño.
func _placed(p: Vector2, ground: float, dir: Vector2, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(p.x, ground - 0.25, p.y))


## Cuántas palmeras tiene la isla.
func palm_count() -> int:
	return _palms


func _multi(node_name: String, mesh: Mesh, items: Array[Transform3D], colors: Array[Color], shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _bush_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	return m


func _stone_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = ToonMaterial.make(Color("8d8a86"), 0.05)
	return m
