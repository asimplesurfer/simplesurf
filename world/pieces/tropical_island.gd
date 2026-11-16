class_name TropicalIslandPiece
extends MapPiece
## Isla tropical dibujada como figura (puntos y manijas Bézier, como la pista):
## toda la figura es arena con playa que entra al agua; más adentro, selva:
## pasto, arbustos de varios verdes y muchas palmeras. Las de la orilla se
## inclinan hacia el mar; las de adentro forman un techo de hojas.
## Se choca como una isla: subirse a la arena tira al surfista.
##
## Para que no pese: todo lo que se repite (troncos, hojas, cocos, arbustos,
## piedras) va en unas pocas MultiMesh (una llamada de dibujo cada una), las
## palmeras de adentro no tienen tronco (no se ve, lo tapan las hojas) y los
## arbustos no hacen sombra y no se dibujan de lejos.

const REQUIRED := ["shape"]

## Contorno visto desde arriba: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var shape: Array = []
## Ancho de la franja de arena antes de la selva (m).
var beach_width: float = 12.0
## Palmeras cada 100 m² (más = más tupida).
var palm_density: float = 1.2
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
var _frond_mesh: ArrayMesh


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


## Pasto de la selva: un poco más alto que la arena, con un borde en pendiente.
func _grass_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in _grass:
		var normals := _normals(g)
		var n := g.size()
		for i in n:
			var j := (i + 1) % n
			var a2 := g[i] + normals[i] * 2.0
			var b2 := g[j] + normals[j] * 2.0
			var nrm := Vector3(normals[i].x * 0.3, 1.0, normals[i].y * 0.3).normalized()
			for v in [[g[i], GRASS_Y], [g[j], GRASS_Y], [b2, SAND_Y - 0.05], [g[i], GRASS_Y], [b2, SAND_Y - 0.05], [a2, SAND_Y - 0.05]]:
				st.set_normal(nrm)
				st.add_vertex(Vector3(v[0].x, v[1], v[0].y))
		for k in Geometry2D.triangulate_polygon(g):
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(g[k].x, GRASS_Y, g[k].y))
	var mat := ToonMaterial.make(grass_color, 0.0)
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


## Palmeras, arbustos, cocos y piedras: todo en MultiMesh.
func _add_vegetation(root: Node3D) -> void:
	var trunks: Array[Transform3D] = []
	var fronds: Array[Transform3D] = []
	var frond_colors: Array[Color] = []
	var nuts: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var bush_colors: Array[Color] = []
	var stones: Array[Transform3D] = []

	# Palmeras: una grilla movida (más pareja que al azar), solo sobre la isla.
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
			# La orilla queda libre (arena y agua).
			if depth < beach_width * 0.45:
				continue
			_palm(p, depth, trunks, fronds, frond_colors, nuts)
		x += spacing

	# Arbustos: tapan todo el pasto (y un poco más alto adentro, la selva).
	var bs := 4.2
	x = _lo.x + bs * 0.5
	while x < _hi.x:
		var z := _lo.y + bs * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-1.6, 1.6), z + _rng.randf_range(-1.6, 1.6))
			z += bs
			if not _on_grass(p):
				continue
			var depth := BezierShape.distance_to_edge(_outline, p)
			var r := _rng.randf_range(2.0, 3.4)
			var y := GRASS_Y + r * 0.2
			# Adentro, matas más grandes y altas (el cuerpo de la selva).
			if depth > beach_width + 10.0 and _rng.randf() < 0.45:
				r *= 1.7
				y += _rng.randf_range(1.0, 2.5)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * _rng.randf_range(0.6, 0.9), r))
			bushes.append(Transform3D(basis, Vector3(p.x, y, p.y)))
			var shade := _rng.randf_range(0.0, 1.0)
			bush_colors.append(Color("1f5a22").lerp(Color("3f8f2e"), shade))
		x += bs

	# Unas piedras en la arena.
	var n := _outline.size()
	for i in rocks:
		var k := _rng.randi() % n
		var nr := _normals(_outline)[k]
		var p := _outline[k] - nr * _rng.randf_range(2.0, beach_width * 0.4)
		var r := _rng.randf_range(1.2, 2.6)
		var basis := Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())).scaled(Vector3(r, r * 0.7, r))
		stones.append(Transform3D(basis, Vector3(p.x, SAND_Y + r * 0.2, p.y)))

	root.add_child(_multi("Trunks", _trunk_mesh(), trunks, [], true))
	root.add_child(_multi("Fronds", _frond(), fronds, frond_colors, true))
	var c := _multi("Coconuts", _nut_mesh(), nuts, [], false)
	c.visibility_range_end = 260.0
	root.add_child(c)
	var b := _multi("Bushes", _bush_mesh(), bushes, bush_colors, false)
	b.visibility_range_end = 520.0
	root.add_child(b)
	root.add_child(_multi("Stones", _stone_mesh(), stones, [], true))


## Una palmera: tronco curvo (si se ve) y una corona de hojas largas que caen.
func _palm(p: Vector2, depth: float, trunks: Array[Transform3D], fronds: Array[Transform3D],
		colors: Array[Color], nuts: Array[Transform3D]) -> void:
	var edge_band := depth < beach_width + 5.0
	# Las de la orilla se inclinan hacia el mar; las de adentro casi derechas.
	var q := _closest_edge_point(p)
	var out := (q - p).normalized() if q.distance_to(p) > 0.01 else Vector2.RIGHT
	var dir := out.rotated(_rng.randf_range(-0.5, 0.5)) if edge_band else Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var lean := _rng.randf_range(0.45, 1.0) if edge_band else _rng.randf_range(0.0, 0.3)
	var height := _rng.randf_range(7.0, 11.5) if edge_band else _rng.randf_range(9.0, 13.0)
	var ground := GRASS_Y if _on_grass(p) else SAND_Y
	var base := Vector3(p.x, ground - 0.3, p.y)
	var side := Vector3(dir.x, 0.0, dir.y)
	var reach := height * sin(lean)
	var rise := height * cos(lean * 0.5)
	# Curva del tronco: se va para el costado abajo y se endereza arriba.
	var pts: Array[Vector3] = []
	var segs := 6
	for k in segs + 1:
		var t := float(k) / segs
		pts.append(base + side * reach * (2.0 * t - t * t) + Vector3.UP * rise * t)
	var top := pts[segs]
	# Solo las palmeras que se ven tienen tronco (la orilla y algunas de adentro).
	if edge_band or _rng.randf() < 0.1:
		for k in segs:
			var a := pts[k]
			var b := pts[k + 1]
			var axis := (b - a).normalized()
			var r := lerpf(0.55, 0.32, float(k) / segs)
			var basis := Basis(Quaternion(Vector3.UP, axis)).scaled(Vector3(r, a.distance_to(b) * 1.25, r))
			trunks.append(Transform3D(basis, (a + b) * 0.5))
		for c in 3:
			var ang := TAU * c / 3.0 + _rng.randf()
			nuts.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.38), top + Vector3(cos(ang) * 0.45, -0.45, sin(ang) * 0.45)))
	# Corona: hojas alrededor, algunas más paradas y otras más caídas.
	# Las de adentro (sin tronco a la vista) con menos hojas: forman el techo igual.
	var count := 9 if edge_band else 6
	var turn := _rng.randf() * TAU
	var tint := leaf_color.lerp(Color("7fb33a"), _rng.randf_range(0.0, 0.35)).darkened(_rng.randf_range(0.0, 0.2))
	for k in count:
		var yaw := turn + TAU * k / count + _rng.randf_range(-0.2, 0.2)
		var up := _rng.randf_range(0.05, 0.55)
		var length := _rng.randf_range(4.6, 6.4) * (height / 10.0 + 0.3)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, up)
		fronds.append(Transform3D(basis.scaled(Vector3(length, length, length * 0.9)), top))
		colors.append(tint)


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


func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 7
	m.rings = 1
	m.material = ToonMaterial.make(Color("6b4f33"), 0.04)
	return m


## Hoja de palmera: una tira larga doblada en V (el nervio en el medio) que se
## curva para abajo, con el borde aserrado (los foliolos).
func _frond() -> ArrayMesh:
	if _frond_mesh:
		return _frond_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	var rows: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var y := 0.22 * t - 0.62 * t * t
		var w := 0.2 * sin(PI * minf(t * 1.1, 1.0)) + 0.015
		# Foliolos: el borde va y viene.
		var jag := 0.05 if i % 2 == 0 else -0.03
		var fold := 0.07 * w / 0.2
		rows.append([Vector3(t, y - fold, -(w + jag)), Vector3(t, y, 0.0), Vector3(t, y - fold, w + jag)])
	for i in segs:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for tri in [[a[0], a[1], b[0]], [a[1], b[1], b[0]], [a[1], a[2], b[1]], [a[2], b[2], b[1]]]:
			var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for v in tri:
				st.set_normal(nrm)
				st.add_vertex(v)
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	_frond_mesh = st.commit()
	return _frond_mesh


func _nut_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = ToonMaterial.make(Color("6b4a2a"), 0.0)
	return m


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
