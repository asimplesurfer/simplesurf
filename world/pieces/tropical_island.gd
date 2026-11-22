class_name TropicalIslandPiece
extends MapPiece
## Isla tropical dibujada como figura (puntos y manijas Bézier, como la pista):
## toda la figura es arena con playa que entra al agua; más adentro, selva:
## pasto, helechos, arbustos y palmeras de varios tamaños. Las de la orilla
## se inclinan hacia el mar.
## Se choca como una isla: subirse a la arena tira al surfista.
##
## Para que no pese: hay unas pocas palmeras modelo (world/pieces/lib/
## palm_mesh.gd) que se repiten con MultiMesh (una llamada de dibujo por
## modelo); las de adentro son más simples, los helechos y arbustos no hacen
## sombra, y del lado que no da a la pista la vegetación es más rala.

const REQUIRED := ["shape"]

## Contorno visto desde arriba: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var shape: Array = []
## Ancho de la franja de arena antes de la selva (m).
var beach_width: float = 5.0
## Palmeras cada 100 m² (más = más tupida).
var palm_density: float = 1.2
## Piedras sobre la arena.
var rocks: int = 3
## Público en la playa del lado de la pista (gente alentando, sillas,
## reposeras, sombrillas y banderas): 1 = normal, 0 = nadie, 2 = el doble.
var crowd: float = 1.0
var sand_color: Color = Color("f2d8a0")
var grass_color: Color = Color("3f7f2c")
var leaf_color: Color = Color("2f8f2c")
var shape_seed: int = 1

const SAND_Y := 0.55
const GRASS_Y := 0.85
## Distancia de la orilla a la que tira al surfista (m, la playa entra al agua).
const SHORE := 1.5
## Hasta cuántos metros del pasto puede haber palmeras en la arena (las de la orilla).
const PALM_SAND_REACH := 2.0

var _outline := PackedVector2Array()
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _grass: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()
var _palms: int = 0
## Dónde hay público (las plantas y palmeras no se ponen encima).
var _crowd_spots := PackedVector2Array()
var _crowd_room := PackedFloat32Array()
## true si un corte se comió la isla entera (no se arma nada).
var _cut_away: bool = false


## Antes de construir: la forma de la isla y dónde empieza el pasto. Si algún
## corte (IslandSplitPiece) la cruza, queda partida: esta pieza se queda con
## una parte y agrega al mapa una isla igual para cada una de las otras.
func prepare(course: Course) -> void:
	if _outline.is_empty():
		var bez := BezierShape.parse(shape)
		if not bez.is_valid():
			return
		var parts := IslandSplitPiece.cut(bez.polygon(4.0), course.pieces)
		if parts.is_empty():
			# El corte se la comió entera: no queda isla.
			_cut_away = true
			return
		_outline = parts[0]
		for k in range(1, parts.size()):
			var twin := TropicalIslandPiece.new()
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
	_make_grass()
	course.register("ground", self)


## El pasto empieza a distinta distancia de la orilla según el tramo, para que
## no quede una línea pareja alrededor de toda la isla. El borde corta de golpe
## (como la arena mojada) pero no es liso: va mordido a cada metro.
func _make_grass() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = shape_seed
	noise.frequency = 0.035
	# Achicar una figura simple no deja agujeros: todo lo que sale es selva.
	for g0 in Geometry2D.offset_polygon(_outline, -beach_width):
		if g0.size() < 3:
			continue
		var g := _resample(g0, EDGE_STEP)
		var normals := _normals(g)
		var pushes := PackedFloat32Array()
		var along := 0.0
		for i in g.size():
			if i > 0:
				along += g[i].distance_to(g[i - 1])
			var big := clampf(noise.get_noise_1d(along) * beach_width * 0.75, -beach_width * 0.6, beach_width * 0.5)
			# Mordiscos chicos: ruido rápido más un salto al azar en cada punto.
			var small := noise.get_noise_1d(along * 9.0 + 300.0) * EDGE_BITE + _rng.randf_range(-0.3, 0.3) * EDGE_BITE
			pushes.append(big + small)
		# Si al mover el borde la figura se cruza (no se puede dibujar), se
		# mueve menos.
		var moved := g
		for k in [1.0, 0.6, 0.3, 0.0]:
			var tryp := PackedVector2Array()
			for i in g.size():
				tryp.append(g[i] + normals[i] * pushes[i] * k)
			if not Geometry2D.triangulate_polygon(tryp).is_empty():
				moved = tryp
				break
		_grass.append(moved)


## La figura con puntos cada `step` metros como mucho.
static func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var parts := maxi(1, ceili(a.distance_to(b) / step))
		for k in parts:
			out.append(a.lerp(b, float(k) / parts))
	return out


## Altura del suelo en un punto (-INF si ahí no hay isla).
func ground_y(p: Vector2) -> float:
	if _outline.is_empty() or not Geometry2D.is_point_in_polygon(p, _outline):
		return -INF
	if _on_grass(p):
		return GRASS_Y
	var d := INF
	for g in _grass:
		d = minf(d, BezierShape.distance_to_edge(g, p))
	return lerpf(GRASS_Y, SAND_Y, clampf(d / DROP, 0.0, 1.0))


func build(course: Course) -> void:
	if _outline.is_empty():
		if not _cut_away:
			push_error("tropical_island: la figura necesita al menos 3 puntos")
		return
	var root := Node3D.new()
	root.name = "TropicalIsland"
	course.add_child(root, true)
	root.add_child(_sand_mesh())
	if not _grass.is_empty():
		root.add_child(_grass_mesh())
	_sample_track(course.track)
	_solid = _touches_track(course)
	# El público va primero: las plantas y las palmeras le dejan lugar.
	var crowd_lists := _plan_crowd(course)
	_add_vegetation(root)
	for key in crowd_lists:
		var list: Array = crowd_lists[key]
		root.add_child(BeachCrowd.multimesh("Crowd_" + key, key, list[0], list[1]))


## true si (x, z) está sobre la isla (con la playa que entra al agua).
func covers(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if p.x < _lo.x - SHORE or p.y < _lo.y - SHORE or p.x > _hi.x + SHORE or p.y > _hi.y + SHORE:
		return false
	return Geometry2D.is_point_in_polygon(p, _outline) or BezierShape.distance_to_edge(_outline, p) < SHORE


## Subirse a la arena: se cae y queda afuera, en el agua. Solo las islas que
## tocan la pista (o están a pocos metros de las corcheras): las de afuera no se
## pueden alcanzar, así que no chocan nunca.
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


## Arena: arriba plana y una playa en pendiente que entra al agua, con arena
## mojada cerca del agua (ver BeachMesh).
func _sand_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Sand"
	mi.mesh = BeachMesh.build(_outline, _normals(_outline), SAND_Y, -1.8, 9.0, sand_color, shape_seed)
	return mi


## Pasto de la selva: un poco más alto que la arena. El borde corta de golpe,
## sin degradé: un escaloncito de DROP metros, todo verde, y después arena.
const DROP := 0.7
## Cada cuánto hay un punto en el borde del pasto y cuánto se mete o sale.
const EDGE_STEP := 1.1
const EDGE_BITE := 1.4


func _grass_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := grass_color.darkened(0.12)
	for g in _grass:
		var normals := _normals(g)
		var n := g.size()
		for i in n:
			var j := (i + 1) % n
			var a0 := Vector3(g[i].x, GRASS_Y, g[i].y)
			var b0 := Vector3(g[j].x, GRASS_Y, g[j].y)
			var ai := g[i] + normals[i] * DROP
			var bj := g[j] + normals[j] * DROP
			var a1 := Vector3(ai.x, SAND_Y + 0.02, ai.y)
			var b1 := Vector3(bj.x, SAND_Y + 0.02, bj.y)
			for v in [a0, b0, b1, a0, b1, a1]:
				st.set_normal(Vector3.UP)
				st.set_color(side)
				st.add_vertex(v)
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


## Cuánto adentro del pasto está `p` (0 si está en la arena).
func _grass_depth(p: Vector2) -> float:
	for g in _grass:
		if Geometry2D.is_point_in_polygon(p, g):
			return BezierShape.distance_to_edge(g, p)
	return 0.0


## true si está en el pasto o a menos de `reach` metros de su borde.
func _near_grass(p: Vector2, reach: float) -> bool:
	if _on_grass(p):
		return true
	for g in _grass:
		if BezierShape.distance_to_edge(g, p) < reach:
			return true
	return false


func _on_grass(p: Vector2) -> bool:
	for g in _grass:
		if Geometry2D.is_point_in_polygon(p, g):
			return true
	return false


## Vegetación: palmeras de varios tamaños, arbustos redondos y helechos, todo
## en MultiMesh. Hay unas pocas palmeras modelo (PalmMesh) que se repiten
## giradas y de distinto tamaño: una MultiMesh por modelo.
##
## El lado que da a la pista va tupido; hacia atrás (lo que casi no se ve) se
## va raleando, así la isla pesa mucho menos.
const TALL_MODELS := 5
const MID_MODELS := 3
const YOUNG_MODELS := 3
const FERN_MODELS := 3


func _add_vegetation(root: Node3D) -> void:
	var tall_models: Array[Mesh] = []
	var tall_shape: Array[Vector2] = []
	for i in TALL_MODELS:
		var h := _rng.randf_range(8.5, 12.5)
		var lean := lerpf(0.3, 0.95, float(i) / (TALL_MODELS - 1))
		tall_shape.append(Vector2(h, lean))
		tall_models.append(PalmMesh.build(shape_seed * 31 + i, h, lean))
	var mid_models: Array[Mesh] = []
	var mid_shape: Array[Vector2] = []
	for i in MID_MODELS:
		var h := _rng.randf_range(7.0, 10.0)
		var lean := _rng.randf_range(0.0, 0.3)
		mid_shape.append(Vector2(h, lean))
		mid_models.append(PalmMesh.build(shape_seed * 37 + i, h, lean, 0.5))
	var young_models: Array[Mesh] = []
	for i in YOUNG_MODELS:
		young_models.append(PalmMesh.build(shape_seed * 43 + i, _rng.randf_range(3.5, 5.5), _rng.randf_range(0.1, 0.5), 0.5))
	var fern_models: Array[Mesh] = []
	for i in FERN_MODELS:
		fern_models.append(PalmMesh.build(shape_seed * 41 + i, _rng.randf_range(2.0, 3.0), 0.0, 0.3, false))
	var tall := _lists(TALL_MODELS)
	var mid := _lists(MID_MODELS)
	var young := _lists(YOUNG_MODELS)
	var ferns := _lists(FERN_MODELS)
	var bushes: Array[Transform3D] = []
	var bush_colors: Array[Color] = []
	var stones: Array[Transform3D] = []

	# Palmeras: grilla movida (más pareja que al azar).
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
			# Solo en el pasto o pegadas a su borde (no en medio de la playa): con
			# una playa más ancha, las palmeras se corren hacia adentro.
			if depth < beach_width * 0.4 or _near_crowd(p, 2.6) or not _near_grass(p, PALM_SAND_REACH):
				continue
			var facing := _facing(p)
			if _rng.randf() > 0.2 + 0.8 * facing:
				continue
			var q := _closest_edge_point(p)
			var out := (q - p).normalized() if q.distance_to(p) > 0.01 else Vector2.RIGHT
			var ground := GRASS_Y if _on_grass(p) else SAND_Y
			var size := _rng.randf_range(0.75, 1.25)
			var roll := _rng.randf()
			if depth < beach_width + 6.0:
				# Orilla: altas inclinadas hacia el mar, y algunas chicas.
				if roll < 0.7:
					var k := _rng.randi() % TALL_MODELS
					var xf := _placed(p, ground, out.rotated(_rng.randf_range(-0.6, 0.6)), size)
					tall[k].append(xf)
					_add_tie(tall_shape[k], xf)
				else:
					young[_rng.randi() % YOUNG_MODELS].append(_placed(p, ground, out.rotated(_rng.randf_range(-1.0, 1.0)), size))
			else:
				# Adentro: medianas casi derechas, chicas y alguna alta.
				var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
				if roll < 0.55:
					var k := _rng.randi() % MID_MODELS
					var xf := _placed(p, ground, dir, size)
					mid[k].append(xf)
					_add_tie(mid_shape[k], xf)
				elif roll < 0.85:
					young[_rng.randi() % YOUNG_MODELS].append(_placed(p, ground, dir, size))
				else:
					var k := _rng.randi() % TALL_MODELS
					var xf := _placed(p, ground, dir, size)
					tall[k].append(xf)
					_add_tie(tall_shape[k], xf)
			_palms += 1
			# Que no se vea de dónde sale el tronco (atrás alcanza con menos).
			_base_cover(ferns, bushes, bush_colors, p, ground, 3 if facing > 0.3 else 1)
		x += spacing

	# Borde del pasto: helechos y matas justo adentro (en la arena no va nada).
	for g in _grass:
		var gn := _normals(g)
		var along := 0.0
		for i in g.size():
			along += g[i].distance_to(g[(i + 1) % g.size()])
			if along < 2.4:
				continue
			along = 0.0
			if _rng.randf() > 0.15 + 0.85 * _facing(g[i]):
				continue
			_cover_at(ferns, bushes, bush_colors, g[i] - gn[i] * _rng.randf_range(1.2, 3.0), GRASS_Y, 1.0)

	# Suelo de la selva: helechos y arbustos de varios tamaños.
	var bs := 6.5
	x = _lo.x + bs * 0.5
	while x < _hi.x:
		var z := _lo.y + bs * 0.5
		while z < _hi.y:
			var p := Vector2(x + _rng.randf_range(-2.0, 2.0), z + _rng.randf_range(-2.0, 2.0))
			z += bs
			if _on_grass(p) and _rng.randf() < 0.25 + 0.75 * _facing(p):
				_cover_at(ferns, bushes, bush_colors, p, GRASS_Y, 1.3)
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

	for i in TALL_MODELS:
		root.add_child(_multi("Palms%d" % i, tall_models[i], tall[i], _tints(tall[i].size()), true))
	for i in MID_MODELS:
		root.add_child(_multi("MidPalms%d" % i, mid_models[i], mid[i], _tints(mid[i].size()), true))
	for i in YOUNG_MODELS:
		root.add_child(_multi("YoungPalms%d" % i, young_models[i], young[i], _tints(young[i].size()), false))
	for i in FERN_MODELS:
		var f := _multi("Ferns%d" % i, fern_models[i], ferns[i], _tints(ferns[i].size()), false)
		f.visibility_range_end = 360.0
		root.add_child(f)
	var b := _multi("Bushes", _bush_mesh(), bushes, bush_colors, false)
	b.visibility_range_end = 420.0
	root.add_child(b)
	root.add_child(_multi("Stones", _stone_mesh(), stones, [], true))


func _lists(count: int) -> Array:
	var out := []
	for i in count:
		out.append([] as Array[Transform3D])
	return out


## Un tono por planta: del verde de siempre (el más claro) a uno más oscuro.
func _tints(count: int) -> Array[Color]:
	var out: Array[Color] = []
	for i in count:
		out.append(Color.WHITE.lerp(Color(0.55, 0.68, 0.55), _rng.randf()))
	return out


## Público: como en las competencias de verdad, la gente se junta en puntos de
## fiesta (uno o dos por isla, donde la pista pasa más cerca): una carpa,
## gente apretada en la orilla alentando, banderas y sillas. El resto de la
## playa que da a la pista está tranquila: alguno tirado en una toalla o
## sentado bajo una sombrilla. Todo con su sombra en la arena y en pocas
## MultiMesh (ver BeachCrowd). Cada punto de fiesta se anota en CrowdDirector
## (para el murmullo y el festejo).
const CROWD_REACH := 75.0
## Un punto de fiesta va donde la pista pasa a menos de esto del borde (m),
## uno por isla como mucho y a PARTY_GAP (m) de cualquier otro del mapa (así
## hay unos pocos, bien repartidos).
const PARTY_REACH := 30.0
const PARTY_GAP := 160.0
## Ancho de orilla que ocupa un punto de fiesta (m, para cada lado).
const PARTY_HALF := 8.5
## Lugar que ocupa cada cosa del público (radio en m): no se pone nada encima
## de otra cosa (la gente no se choca entre sí). Los sentados van en su silla
## y los acostados en su toalla.
const CROWD_ROOM := {"stand": 0.62, "chair": 0.6, "lounger": 0.65, "towel": 0.7, "umbrella": 0.25, "flag": 0.3,
	"tent": 2.4}
## Hasta cuántos metros de la orilla se pone el público (en la arena, cerca
## del agua: no en el medio de la isla ni entre las plantas).
const CROWD_DEPTH := 2.3
## Tamaño de la sombra de cada cosa (m, ancho y largo).
const SHADOW_SIZE := {"stand": Vector2(1.0, 1.0), "sit": Vector2(1.1, 1.2), "sitground": Vector2(1.1, 1.3), "chair": Vector2(0.9, 0.9),
	"lie": Vector2(1.1, 2.3), "lounger": Vector2(0.9, 2.4), "umbrella": Vector2(3.0, 3.0), "tent": Vector2(5.0, 4.0)}

## true si la partida es de noche (nadie toma sol).
var _night: bool = false

## Puntos de fiesta de esta isla (para los tests).
var party_spots := PackedVector2Array()


func _plan_crowd(course: Course) -> Dictionary:
	var lists := {}
	var hour := course.time_of_day if course.time_of_day >= 0 else GameSettings.time_of_day
	_night = hour == GameSettings.TimeOfDay.NIGHT
	if crowd <= 0.0 or _track_pts.is_empty():
		return lists
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 97 + 5
	# Orilla que mira a la pista, cada 2 m: [punto, hacia el mar, pista, distancia, recorrido].
	var shore: Array = []
	var normals := _normals(_outline)
	var n := _outline.size()
	var along := 0.0
	var next := 0.0
	for i in n:
		var a := _outline[i]
		var b := _outline[(i + 1) % n]
		var seg := a.distance_to(b)
		while next < along + seg:
			var k := (next - along) / maxf(seg, 0.001)
			var q := a.lerp(b, k)
			var nrm := normals[i].lerp(normals[(i + 1) % n], k).normalized()
			var track_q := _nearest_track(q)
			var d := q.distance_to(track_q) - course.half_width
			if d < CROWD_REACH and nrm.dot((track_q - q).normalized()) >= 0.35:
				shore.append([q, nrm, track_q, d, next])
			next += 2.0
		along += seg
	if shore.is_empty():
		return lists
	var perimeter := along
	# Puntos de fiesta: donde la pista pasa más cerca (uno o dos por isla).
	var by_distance := shore.duplicate()
	by_distance.sort_custom(func(x: Array, y: Array) -> bool: return x[3] < y[3])
	var parties: Array = []
	var director := CrowdDirector.of(course)
	for cand in by_distance:
		if cand[3] > PARTY_REACH:
			break
		var q: Vector2 = cand[0]
		if not director.near_spot(Vector3(q.x, 0.0, q.y), PARTY_GAP):
			parties.append(cand)
			break
	for p in parties:
		_party(lists, rng, p[0], p[1], p[2])
		party_spots.append(p[0])
		director.add_spot(Vector3(p[0].x, SAND_Y, p[0].y))
	# El resto de la playa: tranquilo, alguno cada tanto.
	var last := -INF
	for s in shore:
		if float(s[4]) - last < 7.0:
			continue
		var near_party := false
		for p in parties:
			var gap := absf(float(s[4]) - float(p[4]))
			if minf(gap, perimeter - gap) < PARTY_HALF + 6.0:
				near_party = true
		if near_party or rng.randf() > 0.22 * minf(crowd, 1.5):
			continue
		last = float(s[4])
		_calm(lists, rng, s[0], s[1], s[2])
	return lists


## Un punto de fiesta: carpa atrás, dos o tres filas de gente apretada en la
## orilla (de colores que combinan), banderas en las puntas y unas sillas.
func _party(lists: Dictionary, rng: RandomNumberGenerator, q: Vector2, out: Vector2, track_q: Vector2) -> void:
	var side := Vector2(-out.y, out.x)
	var hue := rng.randf()
	_crowd_put(lists, rng, "tent", q - out * 4.2, track_q, 0.05, false, INF, hue, true)
	var x := -PARTY_HALF
	while x <= PARTY_HALF:
		for row in [0.9, 1.75, 2.6]:
			if row > 2.0 and absf(x) > 3.5:
				continue
			if rng.randf() < 0.85 * minf(crowd, 1.0):
				var p := q - out * (float(row) + rng.randf_range(-0.12, 0.12)) + side * (x + rng.randf_range(-0.25, 0.25))
				_crowd_put(lists, rng, "stand%d" % (rng.randi() % BeachCrowd.STANDING), p, track_q, 0.3, false, INF,
					hue)
		x += 1.3
	for end in [-1.0, 1.0]:
		_crowd_put(lists, rng, "flag", q - out * 1.2 + side * end * (PARTY_HALF + 1.2), track_q, 0.0, true, INF,
			hue + 0.5)
	# Unas sillas con gente sentada a un costado, bajo una sombrilla.
	var c := q - out * 1.3 + side * (PARTY_HALF + 3.2) * (1.0 if rng.randf() < 0.5 else -1.0)
	_crowd_put(lists, rng, "umbrella", c - out * 0.8, track_q, 0.0, true, INF, hue)
	for k in [-0.88, 0.88]:
		var p := c + side * float(k)
		if _crowd_put(lists, rng, "chair", p, track_q, 0.25, false, INF, hue):
			_crowd_put(lists, rng, "sit%d" % (rng.randi() % BeachCrowd.SITTING), p, track_q, 0.0, false, _last_yaw, hue)


## Un rincón tranquilo de la playa: alguien tomando sol en su toalla (a veces
## con sombrilla), dos sillas bajo una sombrilla o dos reposeras.
func _calm(lists: Dictionary, rng: RandomNumberGenerator, q: Vector2, out: Vector2, track_q: Vector2) -> void:
	var side := Vector2(-out.y, out.x)
	var roll := rng.randf()
	if roll < 0.5:
		var p := q - out * rng.randf_range(1.2, 1.8)
		if _crowd_put(lists, rng, "towel", p, track_q, 0.5) and rng.randf() < 0.75:
			# De día toma sol; de noche, sentado en la toalla alentando.
			var who := "sitground%d" % (rng.randi() % BeachCrowd.GROUND_SITTING) if _night \
				else "lie%d" % (rng.randi() % BeachCrowd.LYING)
			_crowd_put(lists, rng, who, p, track_q, 0.0, false, _last_yaw)
		if rng.randf() < 0.4:
			_crowd_put(lists, rng, "umbrella", p - out * 1.2 + side * 0.9, track_q, 0.0, true)
	elif roll < 0.8:
		var c := q - out * 1.3
		_crowd_put(lists, rng, "umbrella", c - out * 0.8, track_q, 0.0, true)
		for k in [-0.88, 0.88]:
			var p := c + side * float(k)
			if _crowd_put(lists, rng, "chair", p, track_q, 0.25) and rng.randf() < 0.6:
				_crowd_put(lists, rng, "sit%d" % (rng.randi() % BeachCrowd.SITTING), p, track_q, 0.0, false, _last_yaw)
	else:
		var c := q - out * 1.8
		_crowd_put(lists, rng, "umbrella", c - out * 1.25, track_q, 0.0, true)
		for k in [-0.62, 0.62]:
			_crowd_put(lists, rng, "lounger", c + side * float(k), track_q, 0.15)


var _last_yaw: float = 0.0


## Pone una cosa del público en `p`, mirando a la pista (más un poco de giro
## al azar), con su sombra. Devuelve false si ahí no se puede (fuera de la
## arena, sobre el pasto o encima de otra cosa). `hue`: familia de colores
## (ver BeachCrowd.custom). La carpa va atrás y puede quedar sobre el pasto.
func _crowd_put(lists: Dictionary, rng: RandomNumberGenerator, model: String, p: Vector2, track_q: Vector2,
		turn: float, any_yaw: bool = false, yaw: float = INF, hue: float = -1.0, on_grass: bool = false) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _outline) or (_on_grass(p) and not on_grass):
		return false
	if BezierShape.distance_to_edge(_outline, p) < 0.6:
		return false
	var kind := model.rstrip("0123456789")
	var room: float = CROWD_ROOM.get(kind, 0.0)
	if room > 0.0:
		for k in _crowd_spots.size():
			if _crowd_spots[k].distance_to(p) < room + _crowd_room[k]:
				return false
	_crowd_spots.append(p)
	_crowd_room.append(room)
	var to := track_q - p
	if yaw == INF:
		yaw = rng.randf() * TAU if any_yaw else atan2(to.x, to.y) + rng.randf_range(-turn, turn)
	_last_yaw = yaw
	var y := GRASS_Y if _on_grass(p) else SAND_Y
	_add_item(lists, model, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)), BeachCrowd.custom(rng, hue))
	if SHADOW_SIZE.has(kind):
		var size: Vector2 = SHADOW_SIZE[kind] * BeachCrowd.SIZE
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, 1.0, size.y))
		_add_item(lists, "shadow", Transform3D(basis, Vector3(p.x, y, p.y)), Color())
	return true


func _add_item(lists: Dictionary, model: String, xf: Transform3D, custom: Color) -> void:
	if not lists.has(model):
		lists[model] = [[] as Array[Transform3D], [] as Array[Color]]
	(lists[model][0] as Array[Transform3D]).append(xf)
	(lists[model][1] as Array[Color]).append(custom)


## true si hay público a menos de `r` metros de `p`.
func _near_crowd(p: Vector2, r: float) -> bool:
	var r2 := r * r
	for c in _crowd_spots:
		if c.distance_squared_to(p) < r2:
			return true
	return false


func _nearest_track(p: Vector2) -> Vector2:
	var best := _track_pts[0]
	var best_d := INF
	for t in _track_pts:
		var d := p.distance_squared_to(t)
		if d < best_d:
			best_d = d
			best = t
	return best


## Puntos de la pista (cada ~8 m), para saber qué lado de la isla se ve.
var _track_pts := PackedVector2Array()
## true si la isla llega a la pista (ver affect_rider).
var _solid: bool = true
## Hasta cuántos metros afuera de las corcheras una isla todavía choca.
const SOLID_MARGIN := 4.0


## true si algún punto de la orilla queda dentro de la pista (o a SOLID_MARGIN
## de las corcheras), o si la isla tapa el centro de la pista.
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


## 1 = cerca de la pista (se ve de cerca), 0 = lejos (atrás de la isla).
func _facing(p: Vector2) -> float:
	if _track_pts.is_empty():
		return 1.0
	var best := INF
	for q in _track_pts:
		best = minf(best, p.distance_squared_to(q))
	return clampf(1.0 - (sqrt(best) - 70.0) / 110.0, 0.0, 1.0)


## Al pie de una palmera: helechos y matas alrededor del tronco.
func _base_cover(ferns: Array, bushes: Array[Transform3D], colors: Array[Color], p: Vector2, ground: float, count: int) -> void:
	var turn := _rng.randf() * TAU
	for k in count:
		var a := turn + TAU * k / count
		_cover_at(ferns, bushes, colors, p + Vector2(cos(a), sin(a)) * _rng.randf_range(0.6, 1.5), ground, 1.2)


## Un helecho o un arbusto redondo, de tamaño variado (`size` lo agranda).
func _cover_at(ferns: Array, bushes: Array[Transform3D], colors: Array[Color], p: Vector2, ground: float, size: float) -> void:
	var q := p + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
	if not Geometry2D.is_point_in_polygon(q, _outline) or _near_crowd(q, 2.4):
		return
	# Helechos y arbustos solo en el pasto, y sin que las hojas lleguen a la
	# arena: cuanto más grande, más adentro.
	var depth := _grass_depth(q)
	if depth <= 0.0:
		return
	ground = GRASS_Y
	if _rng.randf() < 0.55:
		var s := minf(_rng.randf_range(0.6, 1.6) * size, depth * 0.9)
		if s < 0.45:
			return
		ferns[_rng.randi() % FERN_MODELS].append(_placed(q, ground + 0.05, Vector2.RIGHT.rotated(_rng.randf() * TAU), s))
	else:
		# Arbustos: de bajitos y anchos a altos y redondos.
		var r := minf(_rng.randf_range(0.45, 1.1) * size, depth * 0.8)
		if r < 0.35:
			return
		var tall := _rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * tall, r))
		bushes.append(Transform3D(basis, Vector3(q.x, ground + r * tall * 0.35, q.y)))
		colors.append(Color("123d16").lerp(Color("4f9a34"), _rng.randf()))


## Dónde va una palmera modelo: en `p`, inclinada hacia `dir` (los modelos se
## arman inclinados hacia +X) y con un tamaño.
func _placed(p: Vector2, ground: float, dir: Vector2, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(p.x, ground - 0.25, p.y))


## Dónde se puede atar algo (una guirnalda) a cada palmera alta: un poco
## abajo de la copa. Cada uno: [punto, radio del tronco ahí, dirección del
## tronco] (en el mundo). Ver LightStringPiece.
var palm_ties: Array = []


## Anota el punto de atado de una palmera de alto y caída `shape` (como en
## PalmMesh.build) puesta con `xf`.
func _add_tie(shape: Vector2, xf: Transform3D) -> void:
	var reach := shape.x * sin(shape.y)
	var rise := shape.x * cos(shape.y * 0.6)
	var p1 := Vector3(reach * 0.62, rise * 0.42, 0.0)
	var p2 := Vector3(reach, rise, 0.0)
	var t := TIE_AT
	var c := PalmMesh._bezier(Vector3.ZERO, p1, p2, t)
	var tangent := (PalmMesh._bezier(Vector3.ZERO, p1, p2, t + 0.02) - PalmMesh._bezier(Vector3.ZERO, p1, p2, t - 0.02))
	# Radio del tronco ahí (como en PalmMesh._trunk).
	var r := lerpf(0.42, 0.27, t) + 0.22 * pow(1.0 - t, 6.0)
	var size := xf.basis.get_scale().x
	palm_ties.append([xf * c, r * size, (xf.basis * tangent).normalized()])


## A qué altura del tronco se ata (0 la base, 1 la copa).
const TIE_AT := 0.86


## Cuántas palmeras tiene la isla.
func palm_count() -> int:
	return _palms


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


func _stone_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = ToonMaterial.make(Color("8d8a86"), 0.05)
	return m
