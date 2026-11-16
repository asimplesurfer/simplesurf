class_name RockFormationPiece
extends MapPiece
## Una formación de roca dibujada como una figura cerrada (puntos y manijas
## Bézier, como el recorrido). Lo que hace depende de dónde se dibuja:
## - Si tapa una parte de la pista, esa parte queda adentro de una CUEVA: un
##   túnel del ancho de la pista, con techo a `ceiling` metros, agua turquesa
##   que brilla, paredes oscuras y los ojos que se acostumbran al entrar y
##   salir. Con el techo bajo no se puede saltar tan alto (se sube más despacio
##   y no se toca el techo).
## - Si no toca la pista, es una roca grande de paisaje. Con `opening` tiene un
##   arco abajo por donde se ve el mar.
## - Si toca un poco, las dos cosas: un morro con un túnel en una punta.

const REQUIRED := ["shape"]

## La roca terminó de armarse (es en el frame siguiente a build).
signal built

## Contorno visto desde arriba: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var shape: Array = []
## Altura de la roca (m).
var height: float = 34.0
## Altura del techo de la cueva sobre el agua (m). Más bajo = saltos más bajos.
var ceiling: float = 12.0
## Si no toca la pista: un arco abajo (se ve el mar a través).
var opening: bool = false
## Ancho del arco (m).
var opening_width: float = 16.0
## Agujeros en el techo de la cueva por donde entra un haz de sol: [[x, z], ...].
var skylights: PackedVector2Array = PackedVector2Array()
## Colores de la piedra abajo (cerca del agua) y arriba.
var stone_low: Color = Color("8a4a2e")
var stone_high: Color = Color("b89a74")
## Pasto arriba de la roca y musgo en la base (alpha 0 = sin).
var grass_color: Color = Color("6fae4a")
var moss_color: Color = Color("6f8f3a")
## Color del agua y de la luz adentro de la cueva.
var glow_color: Color = Color("2fe3c8")
## Qué tan oscuro se ve al entrar (0 nada, 1 negro).
var darkness: float = 0.78
## Cuánto tardan los ojos en acostumbrarse (s).
var adapt_time: float = 1.6
## Semilla de la forma (facetas de la piedra).
var shape_seed: int = 1

## Contorno ya armado (polígono) y los tramos de pista que pasan por adentro.
var _outline := PackedVector2Array()
## Cada tramo: PackedVector2Array con el centro de la pista cada pocos metros.
var _runs: Array[PackedVector2Array] = []
var _tunnel_half: float = 24.0
var _noise := FastNoiseLite.new()


func build(course: Course) -> void:
	var bez := BezierShape.parse(shape)
	if not bez.is_valid():
		push_error("rock_formation: la figura necesita al menos 3 puntos")
		return
	_outline = bez.polygon(4.0)
	_tunnel_half = course.half_width + 4.0
	_noise.seed = shape_seed
	_noise.frequency = 0.09
	_find_runs(course.track)

	var root := Node3D.new()
	root.name = "Cave" if is_cave() else "RockFormation"
	course.add_child(root, true)

	_carve(root, course.track)
	if is_cave():
		_add_cave_light(root)
		CaveEyes.of(course).caves.append(self)


func is_cave() -> bool:
	return not _runs.is_empty()


## Dentro del contorno (visto desde arriba).
func covers(x: float, z: float) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, z), _outline)


## Qué tan oscuro está en ese lugar (para los ojos): 0 afuera, `darkness`
## adentro de la cueva (sube de a poco en los primeros metros).
func darkness_at(p: Vector3) -> float:
	if not is_cave() or p.y > ceiling or not covers(p.x, p.z):
		return 0.0
	var depth := BezierShape.distance_to_edge(_outline, Vector2(p.x, p.z))
	return darkness * smoothstep(0.0, 10.0, depth)


## Con techo: no se sube más que el techo (y se sube más despacio cuanto más
## cerca está). Así con un techo bajo los saltos y las olas lanzan menos.
func affect_rider(_course: Course, rider: Rider) -> bool:
	if not is_cave() or not covers(rider.position.x, rider.position.z):
		return false
	var top := ceiling - 2.4
	if rider.position.y > top:
		rider.position.y = top
		rider.vertical_speed = minf(rider.vertical_speed, 0.0)
	elif rider.vertical_speed > 0.0:
		# La velocidad con la que llegaría justo hasta el techo.
		var room := top - rider.position.y
		rider.vertical_speed = minf(rider.vertical_speed, sqrt(2.0 * rider.stats.gravity * room))
	return false


## Tramos de pista que pasan por adentro de la figura (o la rozan con el ancho).
func _find_runs(track: TrackSpace) -> void:
	var step := 4.0
	var n := maxi(int(track.length() / step), 32)
	var centers := PackedVector2Array()
	var hit: Array[bool] = []
	var any := false
	for i in n:
		var p := track.position_at(-PI + TAU * i / n)
		var c := Vector2(p.x, p.z)
		centers.append(c)
		var h := Geometry2D.is_point_in_polygon(c, _outline) or BezierShape.distance_to_edge(_outline, c) < _tunnel_half
		hit.append(h)
		any = any or h
	if not any:
		return
	if not hit.has(false):
		var loop := centers.duplicate()
		loop.append(centers[0])
		_runs.append(loop)
		return
	# Empezar en un lugar libre para que ningún tramo quede partido.
	var start := hit.find(false)
	var margin := 6
	var i := 0
	while i < n:
		var k := (start + i) % n
		if not hit[k]:
			i += 1
			continue
		var j := i
		while j < n and hit[(start + j) % n]:
			j += 1
		var run := PackedVector2Array()
		for m in range(i - margin, j + margin):
			run.append(centers[posmod(start + m, n)])
		_runs.append(run)
		i = j


## La roca maciza menos los túneles. Godot la calcula en el frame siguiente;
## ahí se pasa a una malla con facetas y colores (y se borra lo demás).
func _carve(root: Node3D, track: TrackSpace) -> void:
	var combiner := CSGCombiner3D.new()
	root.add_child(combiner)
	_add_boulders(combiner)
	var cut_paths: Array[PackedVector3Array] = []
	for run in _runs:
		var pts := PackedVector3Array()
		for c in run:
			pts.append(Vector3(c.x, 0.0, c.y))
		cut_paths.append(pts)
	if _runs.is_empty() and opening:
		cut_paths.append(_opening_line())
	var section := _tunnel_section(_tunnel_half if is_cave() else opening_width * 0.5)
	for pts in cut_paths:
		var path := Path3D.new()
		var curve := Curve3D.new()
		for p in pts:
			curve.add_point(p)
		path.curve = curve
		root.add_child(path)
		var cut := CSGPolygon3D.new()
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.mode = CSGPolygon3D.MODE_PATH
		cut.polygon = section
		cut.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
		cut.path_interval = 3.0
		cut.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH
		cut.path_joined = pts.size() > 2 and pts[0].is_equal_approx(pts[pts.size() - 1])
		combiner.add_child(cut)
		cut.path_node = cut.get_path_to(path)
	# Agujeros en el techo.
	for s in skylights:
		var hole := CSGCylinder3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.radius = 5.0
		hole.height = height + 10.0
		hole.sides = 9
		hole.position = Vector3(s.x, ceiling - 2.0 + hole.height * 0.5, s.y)
		combiner.add_child(hole)
	var tools := root.get_children()
	await root.get_tree().process_frame
	if not is_instance_valid(root):
		return
	var baked := combiner.bake_static_mesh()
	# Ya no hace falta lo que se usó para tallar.
	for c in tools:
		c.queue_free()
	if baked == null:
		push_error("rock_formation: no se pudo armar la roca")
		return
	var mi := MeshInstance3D.new()
	mi.name = "Rock"
	mi.mesh = _finish_mesh(baked, track)
	root.add_child(mi)
	built.emit()


## Corte del túnel (visto de frente): paredes rectas y techo en arco.
func _tunnel_section(half: float) -> PackedVector2Array:
	var poly := PackedVector2Array([Vector2(-half, -8.0), Vector2(half, -8.0)])
	var wall := ceiling * 0.55
	for k in 9:
		var a := PI * k / 8.0
		poly.append(Vector2(cos(a) * half, wall + sin(a) * (ceiling - wall)))
	return poly


## Para el arco de una roca de paisaje: una línea por el medio de la figura, a
## lo largo de su lado más largo.
func _opening_line() -> PackedVector3Array:
	var c := Vector2.ZERO
	for p in _outline:
		c += p
	c /= _outline.size()
	var axis := Vector2.RIGHT
	var best := 0.0
	for p in _outline:
		var d := c.distance_to(p)
		if d > best:
			best = d
			axis = (p - c).normalized()
	var across := Vector2(-axis.y, axis.x)
	var a := c - across * (best + 20.0)
	var b := c + across * (best + 20.0)
	return PackedVector3Array([Vector3(a.x, 0.0, a.y), Vector3(c.x, 0.0, c.y), Vector3(b.x, 0.0, b.y)])


## La roca maciza: muchas piedras facetadas juntas (como el arco de roca),
## que rellenan la figura. Más altas en el medio y más bajas en los bordes,
## así el contorno sigue la figura pero se ve irregular, como roca de verdad.
func _add_boulders(combiner: CSGCombiner3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var spots: Array[Vector3] = []
	# Por el borde: piedras con el centro un poco adentro.
	var n := _outline.size()
	var along := 0.0
	for i in n:
		var a := _outline[i]
		var b := _outline[(i + 1) % n]
		along += a.distance_to(b)
		if along < 9.0:
			continue
		along = 0.0
		var dir := (b - a).normalized()
		var inward := Vector2(-dir.y, dir.x)
		var r := rng.randf_range(8.0, 12.0)
		spots.append(Vector3(a.x + inward.x * r * 0.55, r, a.y + inward.y * r * 0.55))
	# Por adentro: una grilla movida.
	var lo := _outline[0]
	var hi := _outline[0]
	for p in _outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var cell := 13.0
	var x := lo.x + cell * 0.5
	while x < hi.x:
		var z := lo.y + cell * 0.5
		while z < hi.y:
			var p := Vector2(x + rng.randf_range(-4.0, 4.0), z + rng.randf_range(-4.0, 4.0))
			if Geometry2D.is_point_in_polygon(p, _outline):
				spots.append(Vector3(p.x, rng.randf_range(10.0, 15.0), p.y))
			z += cell
		x += cell
	var deepest := 1.0
	for s in spots:
		deepest = maxf(deepest, BezierShape.distance_to_edge(_outline, Vector2(s.x, s.z)))
	for s in spots:
		var depth := BezierShape.distance_to_edge(_outline, Vector2(s.x, s.z))
		var inside := Geometry2D.is_point_in_polygon(Vector2(s.x, s.z), _outline)
		var k := clampf(depth / deepest, 0.0, 1.0) if inside else 0.0
		# Alto de esta parte de la roca: los bordes llegan a 2/3, el medio a todo.
		var top := height * lerpf(0.62, 1.0, sqrt(k)) * rng.randf_range(0.85, 1.05)
		var r := s.y
		# Una piedra grande de base (del agua hasta casi arriba) y una encima,
		# angosta y alta (como agujas de roca), más en el medio.
		_boulder(combiner, Vector3(s.x, top * 0.3, s.z), Vector3(r, top * 0.62 + 4.0, r), rng)
		var cap := r * rng.randf_range(0.5, 0.75)
		_boulder(combiner, Vector3(s.x + rng.randf_range(-2, 2), top - cap * 0.9, s.z + rng.randf_range(-2, 2)),
			Vector3(cap, cap * rng.randf_range(1.2, 1.9), cap), rng)


func _boulder(combiner: CSGCombiner3D, at: Vector3, radii: Vector3, rng: RandomNumberGenerator) -> void:
	var b := CSGMesh3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	b.mesh = sm
	b.position = at
	b.rotation = Vector3(rng.randf_range(-0.18, 0.18), rng.randf() * TAU, rng.randf_range(-0.18, 0.18))
	b.scale = radii * Vector3(rng.randf_range(0.9, 1.15), 1.0, rng.randf_range(0.9, 1.15))
	combiner.add_child(b)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Facetas planas (estilo low-poly) y colores: capas de piedra, musgo abajo,
## pasto arriba y el interior oscuro y teñido de turquesa por el agua.
func _finish_mesh(mesh: ArrayMesh, track: TrackSpace) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else verts.size()
		for t in range(0, count, 3):
			var tri: Array[Vector3] = []
			for k in 3:
				var v := verts[indices[t + k]] if not indices.is_empty() else verts[t + k]
				tri.append(v)
			var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
			if normal == Vector3.ZERO:
				continue
			var mid := (tri[0] + tri[1] + tri[2]) / 3.0
			var color := _color_at(mid, normal, track)
			# Cada cara un poco distinta (piedra facetada).
			color = color.darkened(0.08 * (0.5 + 0.5 * _noise.get_noise_3d(mid.x * 7.0, mid.y * 7.0, mid.z * 7.0)))
			for k in 3:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(tri[k])
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)
	return st.commit()


func _color_at(p: Vector3, normal: Vector3, track: TrackSpace) -> Color:
	# Capas de piedra: rojiza abajo, clara arriba, con vetas.
	var t := clampf(p.y / maxf(height, 1.0) + 0.12 * sin(p.y * 0.8 + _noise.get_noise_2d(p.x, p.z) * 4.0), 0.0, 1.0)
	var c := stone_low.lerp(stone_high, t)
	if normal.y > 0.72 and p.y > height * 0.7:
		c = c.lerp(grass_color, grass_color.a)
	elif p.y < 2.5 and absf(normal.y) < 0.6:
		c = c.lerp(moss_color, moss_color.a * 0.55)
	if is_cave() and p.y < ceiling + 0.5 and covers(p.x, p.z):
		var lat := absf(track.lateral_of(p))
		if lat < _tunnel_half + 3.0:
			# Adentro: más oscuro y teñido por el agua turquesa (más cerca del agua, más).
			var glow := 1.0 - clampf(p.y / ceiling, 0.0, 1.0)
			c = c.darkened(0.35).lerp(glow_color, 0.5 * glow)
	return c


## Adentro: luces turquesas bajas (el agua brilla) y un brillo sobre el agua.
## Debajo de cada agujero del techo, un haz de sol.
func _add_cave_light(root: Node3D) -> void:
	for run in _runs:
		var since := 999.0
		var inside_pts := PackedVector2Array()
		for i in run.size():
			var c := run[i]
			if not covers(c.x, c.y):
				continue
			inside_pts.append(c)
			since += c.distance_to(run[maxi(i - 1, 0)])
			if since > 26.0:
				since = 0.0
				var light := OmniLight3D.new()
				light.light_color = glow_color
				light.light_energy = 1.4
				light.omni_range = _tunnel_half * 1.6
				light.position = Vector3(c.x, 1.2, c.y)
				root.add_child(light)
		if inside_pts.size() >= 2:
			root.add_child(_water_glow(inside_pts))
	for s in skylights:
		root.add_child(_sunbeam(s))


## Brillo turquesa sobre el agua, a lo largo de la pista adentro de la cueva
## (más fuerte en el medio y apagándose hacia las paredes y las bocas).
func _water_glow(pts: PackedVector2Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := _tunnel_half
	var total := pts.size()
	for i in total - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var fade_a := minf(smoothstep(0.0, 4.0, i), smoothstep(0.0, 4.0, total - 1 - i))
		var fade_b := minf(smoothstep(0.0, 4.0, i + 1), smoothstep(0.0, 4.0, total - 2 - i))
		for k in 4:
			var u0 := -1.0 + k * 0.5
			var u1 := u0 + 0.5
			var q := [
				[a + side * half * u0, fade_a * (1.0 - absf(u0))], [a + side * half * u1, fade_a * (1.0 - absf(u1))],
				[b + side * half * u1, fade_b * (1.0 - absf(u1))], [b + side * half * u0, fade_b * (1.0 - absf(u0))],
			]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for v in tri:
					var p: Vector2 = q[v][0]
					st.set_color(Color(glow_color, 0.5 * q[v][1]))
					st.add_vertex(Vector3(p.x, 0.35, p.y))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "WaterGlow"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sunbeam(at: Vector2) -> Node3D:
	var beam := Node3D.new()
	beam.name = "Sunbeam"
	beam.position = Vector3(at.x, 0.0, at.y)
	var cone := CylinderMesh.new()
	cone.top_radius = 4.5
	cone.bottom_radius = 7.0
	cone.height = ceiling
	cone.radial_segments = 12
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.92, 0.7, 0.16)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.position.y = ceiling * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.7)
	light.light_energy = 1.6
	light.omni_range = 14.0
	light.position.y = ceiling * 0.4
	beam.add_child(light)
	return beam
