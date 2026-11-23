class_name JungleBankPiece
extends MapPiece
## Orilla de selva: tierra dibujada como figura (puntos y manijas, como la
## isla tropical) para poner a los lados de un río. En la orilla, barro que
## entra al agua; adentro, suelo de selva con árboles de jungla de varios
## tamaños (gigantes con lianas, medianos y chicos), matas de bambú, helechos
## y plantas de hojas grandes. Los árboles de la orilla se inclinan un poco
## hacia el agua.
##
## Funciona como la isla tropical (TropicalIslandPiece): es tierra (apaga las
## olas grandes cerca de la orilla), se choca si llega a la pista y un corte
## (IslandSplitPiece) la parte. No tiene público.
##
## Para que no pese: pocos modelos de cada planta (JungleMesh) repetidos con
## MultiMesh, y del lado que no da a la pista la selva es más rala.

const REQUIRED := ["shape"]

## Cómo se ve en el editor de mapas (ver MapPiece.editor_entry).
const EDITOR := {
	"name": "Orilla de selva", "place": "shape", "solid": true, "what": "una orilla de selva",
	"hint": "Dibujá la figura de la orilla como la pista (clic: punto, arrastrar: curva) y cerrala tocando el primer punto. Es tierra con selva: ponela a los lados del río.",
	"fields": {
		"bank_width": {"label": "Orilla de barro", "kind": "level", "options": [[1.5, "Angosta"], [3, "Normal"], [6, "Ancha"]]},
		"tree_density": {"label": "Árboles", "kind": "level", "options": [[0.5, "Pocos"], [1, "Normal"], [1.6, "Muchos"], [2.4, "Selva cerrada"]]},
		"bamboo": {"label": "Bambú", "kind": "level", "options": [[0, "Nada"], [1, "Algo"], [2, "Mucho"]]},
		"mud_color": "Color del barro", "ground_color": "Color del suelo", "leaf_color": "Color de las hojas",
		"shape_seed": {"label": "Variante", "kind": "variant"},
	},
}

## Contorno visto desde arriba: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var shape: Array = []
## Ancho de la franja de barro antes de la selva (m).
var bank_width: float = 3.0
## Árboles cada 100 m² (más = más tupida).
var tree_density: float = 1.0
## Cuánto bambú: 0 nada, 1 algo, 2 mucho.
var bamboo: float = 1.0
var mud_color: Color = Color("4e3420")
var ground_color: Color = Color("2c4519")
var leaf_color: Color = Color("1f5a1a")
var shape_seed: int = 1

const MUD_Y := 0.55
const GROUND_Y := 0.9
## Distancia de la orilla a la que tira al surfista (m, el barro entra al agua).
const SHORE := 1.5
## Hasta cuántos metros afuera de las corcheras una orilla todavía choca.
const SOLID_MARGIN := 4.0
## Escaloncito entre el barro y el suelo de la selva (m).
const DROP := 0.8

var _outline := PackedVector2Array()
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _ground: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()
var _cut_away: bool = false
var _solid: bool = true
var _track_pts := PackedVector2Array()
var _trees: int = 0


## Antes de construir: la forma y dónde empieza la selva. Si un corte la
## cruza, queda partida (como la isla tropical).
func prepare(course: Course) -> void:
	if _outline.is_empty():
		var bez := BezierShape.parse(shape)
		if not bez.is_valid():
			return
		var parts := IslandSplitPiece.cut(bez.polygon(4.0), course.pieces)
		if parts.is_empty():
			_cut_away = true
			return
		_outline = parts[0]
		for k in range(1, parts.size()):
			var twin := JungleBankPiece.new()
			twin.type = type
			twin.apply(to_dict())
			twin.shape_seed = shape_seed * 13 + k
			twin._outline = parts[k]
			course.pieces.append(twin)
	_lo = _outline[0]
	_hi = _outline[0]
	for p in _outline:
		_lo = _lo.min(p)
		_hi = _hi.max(p)
	_rng.seed = shape_seed
	_make_ground()
	course.register("ground", self)


## El suelo de la selva empieza a distinta distancia de la orilla según el tramo.
func _make_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = shape_seed
	noise.frequency = 0.04
	for g0 in Geometry2D.offset_polygon(_outline, -bank_width):
		if g0.size() < 3:
			continue
		var g := TropicalIslandPiece._resample(g0, 1.2)
		var normals := _normals(g)
		var moved := g
		for k in [1.0, 0.5, 0.0]:
			var tryp := PackedVector2Array()
			var along := 0.0
			for i in g.size():
				if i > 0:
					along += g[i].distance_to(g[i - 1])
				var push := noise.get_noise_1d(along) * bank_width * 0.6 + _rng.randf_range(-0.4, 0.4)
				tryp.append(g[i] + normals[i] * push * k)
			if not Geometry2D.triangulate_polygon(tryp).is_empty():
				moved = tryp
				break
		_ground.append(moved)


func blocks_track(samples: PackedVector2Array) -> Variant:
	var bez := BezierShape.parse(shape)
	if not bez.is_valid():
		return null
	var poly := bez.polygon(4.0)
	for q in samples:
		if Geometry2D.is_point_in_polygon(q, poly):
			return q
	return null


func outline() -> PackedVector2Array:
	return _outline


## Altura del suelo en un punto (-INF si ahí no hay tierra).
func ground_y(p: Vector2) -> float:
	if _outline.is_empty() or not Geometry2D.is_point_in_polygon(p, _outline):
		return -INF
	if _on_ground(p):
		return GROUND_Y
	var d := INF
	for g in _ground:
		d = minf(d, BezierShape.distance_to_edge(g, p))
	return lerpf(GROUND_Y, MUD_Y, clampf(d / DROP, 0.0, 1.0))


func build(course: Course) -> void:
	if _outline.is_empty():
		if not _cut_away:
			push_error("jungle_bank: la figura necesita al menos 3 puntos")
		return
	var root := Node3D.new()
	root.name = "JungleBank"
	course.add_child(root, true)
	var mud := MeshInstance3D.new()
	mud.name = "Mud"
	mud.mesh = BeachMesh.build(_outline, _normals(_outline), MUD_Y, -1.8, 6.0, mud_color, shape_seed)
	root.add_child(mud)
	if not _ground.is_empty():
		root.add_child(_ground_mesh())
	_sample_track(course.track)
	_solid = _touches_track(course)
	_add_vegetation(root)


## true si (x, z) está sobre la orilla (con el barro que entra al agua).
func covers(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if p.x < _lo.x - SHORE or p.y < _lo.y - SHORE or p.x > _hi.x + SHORE or p.y > _hi.y + SHORE:
		return false
	return Geometry2D.is_point_in_polygon(p, _outline) or BezierShape.distance_to_edge(_outline, p) < SHORE


## Subirse al barro: se cae y queda afuera, en el agua (solo si la orilla llega
## a la pista; las de lejos no se pueden alcanzar).
func affect_rider(course: Course, rider: Rider) -> bool:
	if not _solid or not course.hazards_enabled or rider.is_fallen() or _outline.is_empty():
		return false
	if not covers(rider.position.x, rider.position.z):
		return false
	var p := Vector2(rider.position.x, rider.position.z)
	var q := _closest_edge_point(p)
	var out := _outward_at(q, p)
	var safe := q + out * (SHORE + 3.0)
	course.crash(rider, Vector3(safe.x, rider.position.y, safe.y))
	return true


## Cuántos árboles tiene (para los tests).
func tree_count() -> int:
	return _trees


func _touches_track(course: Course) -> bool:
	if course.track == null:
		return true
	var reach := course.half_width + SHORE + SOLID_MARGIN
	for p in _outline:
		if absf(course.track.locate(Vector3(p.x, 0.0, p.y)).y) < reach:
			return true
	for q in _track_pts:
		if Geometry2D.is_point_in_polygon(q, _outline):
			return true
	return false


func _sample_track(track: TrackSpace) -> void:
	_track_pts.clear()
	if track == null:
		return
	var n := maxi(int(track.length() / 8.0), 16)
	for i in n:
		var q := track.position_at(-PI + TAU * i / n)
		_track_pts.append(Vector2(q.x, q.z))
	if track is PathTrack:
		for b in (track as PathTrack).branches:
			for i in range(0, b.points.size(), 4):
				_track_pts.append(b.points[i])


## 1 = cerca de la pista (se ve de cerca), 0 = lejos.
func _facing(p: Vector2) -> float:
	if _track_pts.is_empty():
		return 1.0
	var best := INF
	for q in _track_pts:
		best = minf(best, p.distance_squared_to(q))
	return clampf(1.0 - (sqrt(best) - 70.0) / 110.0, 0.0, 1.0)


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


## Dirección hacia afuera de la orilla en un punto del borde.
func _outward_at(q: Vector2, from: Vector2) -> Vector2:
	var d := q - from
	if d.length() < 0.01:
		d = q - (_lo + _hi) * 0.5
	d = d.normalized()
	if not Geometry2D.is_point_in_polygon(q - d * 0.5, _outline):
		d = -d
	return d


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


func _on_ground(p: Vector2) -> bool:
	for g in _ground:
		if Geometry2D.is_point_in_polygon(p, g):
			return true
	return false


## Cuánto adentro del suelo de selva está `p` (0 si está en el barro).
func _ground_depth(p: Vector2) -> float:
	for g in _ground:
		if Geometry2D.is_point_in_polygon(p, g):
			return BezierShape.distance_to_edge(g, p)
	return 0.0


## Suelo de la selva: más alto que el barro, con un escaloncito de tierra.
func _ground_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := mud_color.darkened(0.15)
	for g in _ground:
		var normals := _normals(g)
		var n := g.size()
		for i in n:
			var j := (i + 1) % n
			var a0 := Vector3(g[i].x, GROUND_Y, g[i].y)
			var b0 := Vector3(g[j].x, GROUND_Y, g[j].y)
			var ai := g[i] + normals[i] * DROP
			var bj := g[j] + normals[j] * DROP
			var a1 := Vector3(ai.x, MUD_Y + 0.02, ai.y)
			var b1 := Vector3(bj.x, MUD_Y + 0.02, bj.y)
			for v in [a0, b0, b1, a0, b1, a1]:
				st.set_normal(Vector3.UP)
				st.set_color(side)
				st.add_vertex(v)
		for k in Geometry2D.triangulate_polygon(g):
			st.set_normal(Vector3.UP)
			st.set_color(ground_color)
			st.add_vertex(Vector3(g[k].x, GROUND_Y, g[k].y))
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	return mi


## Modelos de cada planta (se repiten con MultiMesh).
const GIANT_MODELS := 2
const ROUND_MODELS := 3
const SMALL_MODELS := 3
const BAMBOO_MODELS := 2
const FERN_MODELS := 2
const LEAF_MODELS := 2


## La selva: árboles (gigantes adentro, medianos y chicos en todos lados; los
## de la orilla se inclinan hacia el agua), matas de bambú (más en la orilla),
## y abajo helechos, plantas de hojas grandes y arbustos.
func _add_vegetation(root: Node3D) -> void:
	var giants: Array[Mesh] = []
	for i in GIANT_MODELS:
		giants.append(JungleMesh.tree(shape_seed * 31 + i, _rng.randf_range(20.0, 26.0), JungleMesh.GIANT, leaf_color))
	var rounds: Array[Mesh] = []
	for i in ROUND_MODELS:
		rounds.append(JungleMesh.tree(shape_seed * 37 + i, _rng.randf_range(11.0, 15.0), JungleMesh.ROUND, leaf_color))
	var smalls: Array[Mesh] = []
	for i in SMALL_MODELS:
		smalls.append(JungleMesh.tree(shape_seed * 43 + i, _rng.randf_range(5.0, 7.5), JungleMesh.SMALL, leaf_color))
	var canes: Array[Mesh] = []
	for i in BAMBOO_MODELS:
		canes.append(JungleMesh.bamboo(shape_seed * 47 + i, _rng.randf_range(8.0, 11.0), _rng.randi_range(9, 14)))
	var ferns: Array[Mesh] = []
	for i in FERN_MODELS:
		ferns.append(PalmMesh.build(shape_seed * 41 + i, _rng.randf_range(2.0, 3.0), 0.0, 0.3, false))
	var big_leaves: Array[Mesh] = []
	for i in LEAF_MODELS:
		big_leaves.append(JungleMesh.big_leaves(shape_seed * 53 + i, _rng.randf_range(1.6, 2.4)))
	var giant_xf := _lists(GIANT_MODELS)
	var round_xf := _lists(ROUND_MODELS)
	var small_xf := _lists(SMALL_MODELS)
	var cane_xf := _lists(BAMBOO_MODELS)
	var fern_xf := _lists(FERN_MODELS)
	var leaf_xf := _lists(LEAF_MODELS)
	var bushes: Array[Transform3D] = []
	var bush_colors: Array[Color] = []

	# Árboles: grilla movida (más pareja que al azar).
	var spacing := sqrt(100.0 / maxf(tree_density, 0.05))
	var x := _lo.x + spacing * 0.5
	while x < _hi.x:
		var z := _lo.y + spacing * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-0.45, 0.45) * spacing, z + _rng.randf_range(-0.45, 0.45) * spacing)
			z += spacing
			var depth := _ground_depth(p)
			if depth <= 0.0:
				continue
			var facing := _facing(p)
			if _rng.randf() > 0.25 + 0.75 * facing:
				continue
			var q := _closest_edge_point(p)
			var to_water := (q - p).normalized() if q.distance_to(p) > 0.01 else Vector2.RIGHT
			var edge := BezierShape.distance_to_edge(_outline, p)
			var roll := _rng.randf()
			if edge > 14.0 and roll < 0.3:
				giant_xf[_rng.randi() % GIANT_MODELS].append(_placed(p, Vector2.RIGHT.rotated(_rng.randf() * TAU), 0.0, _rng.randf_range(0.85, 1.15)))
			elif edge > 5.0 and roll < 0.75:
				# Medianos: los de la orilla, inclinados hacia el agua.
				var lean := 0.12 if edge < 12.0 else 0.0
				round_xf[_rng.randi() % ROUND_MODELS].append(_placed(p, to_water, lean, _rng.randf_range(0.8, 1.2)))
			else:
				var lean := 0.18 if edge < 8.0 else 0.0
				small_xf[_rng.randi() % SMALL_MODELS].append(_placed(p, to_water, lean, _rng.randf_range(0.8, 1.25)))
			_trees += 1
			# Al pie: plantas, para que no se vea de dónde sale el tronco.
			for k in (3 if facing > 0.3 else 1):
				_cover_at(fern_xf, leaf_xf, bushes, bush_colors, p + Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(1.5, 3.5), 1.1)
		x += spacing

	# Bambú: matas en la orilla (y alguna adentro).
	if bamboo > 0.0:
		for g in _ground:
			var gn := _normals(g)
			var along := 0.0
			var every := 26.0 / bamboo
			for i in g.size():
				along += g[i].distance_to(g[(i + 1) % g.size()])
				if along < every:
					continue
				along = _rng.randf_range(0.0, every * 0.5)
				if _rng.randf() > 0.2 + 0.8 * _facing(g[i]):
					continue
				var p := g[i] - gn[i] * _rng.randf_range(1.5, 3.5)
				if _ground_depth(p) <= 0.5:
					continue
				cane_xf[_rng.randi() % BAMBOO_MODELS].append(_placed(p, Vector2.RIGHT.rotated(_rng.randf() * TAU), 0.0, _rng.randf_range(0.8, 1.2)))

	# Borde del suelo: plantas justo adentro (en el barro no va nada).
	for g in _ground:
		var gn := _normals(g)
		var along := 0.0
		for i in g.size():
			along += g[i].distance_to(g[(i + 1) % g.size()])
			if along < 2.6:
				continue
			along = 0.0
			if _rng.randf() > 0.15 + 0.85 * _facing(g[i]):
				continue
			_cover_at(fern_xf, leaf_xf, bushes, bush_colors, g[i] - gn[i] * _rng.randf_range(1.2, 3.0), 1.0)

	# Suelo de la selva: más plantas.
	var bs := 6.0
	x = _lo.x + bs * 0.5
	while x < _hi.x:
		var z := _lo.y + bs * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-2.0, 2.0), z + _rng.randf_range(-2.0, 2.0))
			z += bs
			if _on_ground(p) and _rng.randf() < 0.25 + 0.75 * _facing(p):
				_cover_at(fern_xf, leaf_xf, bushes, bush_colors, p, 1.3)
		x += bs

	for i in GIANT_MODELS:
		root.add_child(_multi("Giants%d" % i, giants[i], giant_xf[i], _tints(giant_xf[i].size()), true))
	for i in ROUND_MODELS:
		root.add_child(_multi("Trees%d" % i, rounds[i], round_xf[i], _tints(round_xf[i].size()), true))
	for i in SMALL_MODELS:
		root.add_child(_multi("SmallTrees%d" % i, smalls[i], small_xf[i], _tints(small_xf[i].size()), false))
	for i in BAMBOO_MODELS:
		root.add_child(_multi("Bamboo%d" % i, canes[i], cane_xf[i], _tints(cane_xf[i].size()), false))
	for i in FERN_MODELS:
		var f := _multi("Ferns%d" % i, ferns[i], fern_xf[i], _tints(fern_xf[i].size()), false)
		f.visibility_range_end = 360.0
		root.add_child(f)
	for i in LEAF_MODELS:
		var l := _multi("BigLeaves%d" % i, big_leaves[i], leaf_xf[i], _tints(leaf_xf[i].size()), false)
		l.visibility_range_end = 360.0
		root.add_child(l)
	var b := _multi("Bushes", _bush_mesh(), bushes, bush_colors, false)
	b.visibility_range_end = 420.0
	root.add_child(b)


## Un helecho, una planta de hojas grandes o un arbusto (solo en el suelo de
## la selva, sin que las hojas lleguen al barro).
func _cover_at(ferns: Array, leaves: Array, bushes: Array[Transform3D], colors: Array[Color], p: Vector2, size: float) -> void:
	var depth := _ground_depth(p)
	if depth <= 0.0:
		return
	var roll := _rng.randf()
	if roll < 0.4:
		var s := minf(_rng.randf_range(0.6, 1.6) * size, depth * 0.9)
		if s >= 0.45:
			ferns[_rng.randi() % FERN_MODELS].append(_placed(p, Vector2.RIGHT.rotated(_rng.randf() * TAU), 0.0, s, 0.05))
	elif roll < 0.7:
		var s := minf(_rng.randf_range(0.7, 1.3) * size, depth * 0.6)
		if s >= 0.45:
			leaves[_rng.randi() % LEAF_MODELS].append(_placed(p, Vector2.RIGHT.rotated(_rng.randf() * TAU), 0.0, s, 0.0))
	else:
		var r := minf(_rng.randf_range(0.5, 1.2) * size, depth * 0.8)
		if r < 0.35:
			return
		var tall := _rng.randf_range(0.7, 1.3)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * tall, r))
		bushes.append(Transform3D(basis, Vector3(p.x, GROUND_Y + r * tall * 0.35, p.y)))
		colors.append(Color("0f3312").lerp(Color("3f7f2a"), _rng.randf()))


## Una planta en `p`, girada hacia `dir` e inclinada `lean` rad hacia allá.
func _placed(p: Vector2, dir: Vector2, lean: float, size: float, lift: float = -0.2) -> Transform3D:
	var yaw := atan2(-dir.y, dir.x)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -lean)
	return Transform3D(basis.scaled(Vector3.ONE * size), Vector3(p.x, GROUND_Y + lift, p.y))


func _lists(count: int) -> Array:
	var out := []
	for i in count:
		out.append([] as Array[Transform3D])
	return out


## Un tono por planta (más claro o más oscuro).
func _tints(count: int) -> Array[Color]:
	var out: Array[Color] = []
	for i in count:
		out.append(Color.WHITE.lerp(Color(0.6, 0.7, 0.6), _rng.randf()))
	return out


func _bush_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 7
	m.rings = 4
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	return m


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
