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

var _outline := PackedVector2Array()
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _grass: Array[PackedVector2Array] = []
## Ancho de la franja pasto-arena en cada punto del borde del pasto.
var _fades: Array[PackedFloat32Array] = []
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


## El pasto empieza a distinta distancia de la orilla según el tramo (y la
## franja donde se mezcla con la arena también cambia), para que no quede una
## línea pareja alrededor de toda la isla.
func _make_grass() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = shape_seed
	noise.frequency = 0.035
	# Achicar una figura simple no deja agujeros: todo lo que sale es selva.
	for g in Geometry2D.offset_polygon(_outline, -beach_width):
		if g.size() < 3:
			continue
		var normals := _normals(g)
		var fades := PackedFloat32Array()
		var pushes := PackedFloat32Array()
		var along := 0.0
		for i in g.size():
			if i > 0:
				along += g[i].distance_to(g[i - 1])
			pushes.append(clampf(noise.get_noise_1d(along) * beach_width * 0.75, -beach_width * 0.6, beach_width * 0.5))
			fades.append(FADE * (1.0 + 0.6 * noise.get_noise_1d(along + 500.0)))
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
		_fades.append(fades)


## Altura del suelo en un punto (-INF si ahí no hay isla).
func ground_y(p: Vector2) -> float:
	if _outline.is_empty() or not Geometry2D.is_point_in_polygon(p, _outline):
		return -INF
	if _on_grass(p):
		return GRASS_Y
	var d := INF
	for g in _grass:
		d = minf(d, BezierShape.distance_to_edge(g, p))
	return lerpf(GRASS_Y, SAND_Y, clampf(d / FADE, 0.0, 1.0))


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
	# El público va primero: las plantas y las palmeras le dejan lugar.
	var crowd_lists := _plan_crowd(course)
	_add_vegetation(root)
	for key in crowd_lists:
		var list: Array = crowd_lists[key]
		var jump := 1.0 if String(key).begins_with("stand") else 0.0
		root.add_child(BeachCrowd.multimesh("Crowd_" + key, key, list[0], list[1], jump))


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


## Arena: arriba plana y una playa en pendiente que entra al agua, con arena
## mojada cerca del agua (ver BeachMesh).
func _sand_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Sand"
	mi.mesh = BeachMesh.build(_outline, _normals(_outline), SAND_Y, -1.8, 9.0, sand_color, shape_seed)
	return mi


## Pasto de la selva: un poco más alto que la arena. El borde no corta de
## golpe: una franja de FADE metros baja hasta la arena y pasa del verde al
## color de la arena (y encima van helechos).
const FADE := 6.0


func _grass_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sandy := grass_color.lerp(sand_color, 0.55)
	for gi in _grass.size():
		var g := _grass[gi]
		var fades := _fades[gi]
		var normals := _normals(g)
		var n := g.size()
		# Tres anillos: borde del pasto, mitad (pasto con arena) y arena. El
		# ancho de la franja cambia en cada punto.
		var rings := [[0.0, GRASS_Y, grass_color], [0.45, lerpf(GRASS_Y, SAND_Y, 0.6) + 0.03, sandy], [1.0, SAND_Y + 0.02, sand_color]]
		for r in 2:
			for i in n:
				var j := (i + 1) % n
				var a0: Vector2 = g[i] + normals[i] * rings[r][0] * fades[i]
				var b0: Vector2 = g[j] + normals[j] * rings[r][0] * fades[j]
				var a1: Vector2 = g[i] + normals[i] * rings[r + 1][0] * fades[i]
				var b1: Vector2 = g[j] + normals[j] * rings[r + 1][0] * fades[j]
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
	for i in TALL_MODELS:
		tall_models.append(PalmMesh.build(shape_seed * 31 + i, _rng.randf_range(8.5, 12.5), lerpf(0.3, 0.95, float(i) / (TALL_MODELS - 1))))
	var mid_models: Array[Mesh] = []
	for i in MID_MODELS:
		mid_models.append(PalmMesh.build(shape_seed * 37 + i, _rng.randf_range(7.0, 10.0), _rng.randf_range(0.0, 0.3), 0.5))
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
			if depth < beach_width * 0.4 or _near_crowd(p, 2.6):
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
					tall[_rng.randi() % TALL_MODELS].append(_placed(p, ground, out.rotated(_rng.randf_range(-0.6, 0.6)), size))
				else:
					young[_rng.randi() % YOUNG_MODELS].append(_placed(p, ground, out.rotated(_rng.randf_range(-1.0, 1.0)), size))
			else:
				# Adentro: medianas casi derechas, chicas y alguna alta.
				var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
				if roll < 0.55:
					mid[_rng.randi() % MID_MODELS].append(_placed(p, ground, dir, size))
				elif roll < 0.85:
					young[_rng.randi() % YOUNG_MODELS].append(_placed(p, ground, dir, size))
				else:
					tall[_rng.randi() % TALL_MODELS].append(_placed(p, ground, dir, size))
			_palms += 1
			# Que no se vea de dónde sale el tronco (atrás alcanza con menos).
			_base_cover(ferns, bushes, bush_colors, p, ground, 3 if facing > 0.3 else 1)
		x += spacing

	# Borde del pasto: helechos y matas sobre la transición a la arena.
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
			_cover_at(ferns, bushes, bush_colors, g[i] + gn[i] * _rng.randf_range(-2.0, 1.0), GRASS_Y, 1.0)
			_cover_at(ferns, bushes, bush_colors, g[i] + gn[i] * _rng.randf_range(1.5, FADE * 0.8), lerpf(GRASS_Y, SAND_Y, 0.6), 0.7)

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


## Público: en la arena que da a la pista hay grupos de gente alentando
## (parados, algunos saltando), sillas playeras con gente sentada, reposeras,
## sombrillas y banderas, como en una competencia que todas las islas vienen a
## ver. Se reparte por tramos de la orilla: unos con mucha gente y otros con
## poca (no es una fila pareja). Todo en pocas MultiMesh (ver BeachCrowd).
const CROWD_REACH := 75.0
const CROWD_SLOT := 4.5
## Lugar que ocupa cada cosa del público (radio en m): no se pone nada encima
## de otra cosa (la gente no se choca entre sí). Los sentados van en su silla.
const CROWD_ROOM := {"stand": 0.42, "chair": 0.42, "lounger": 0.45, "towel": 0.5, "umbrella": 0.2, "flag": 0.2}
## Hasta cuántos metros de la orilla se pone el público (en la arena, cerca
## del agua: no en el medio de la isla ni entre las plantas).
const CROWD_DEPTH := 2.3


func _plan_crowd(course: Course) -> Dictionary:
	var lists := {}
	if crowd <= 0.0 or _track_pts.is_empty():
		return lists
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed * 97 + 5
	var noise := FastNoiseLite.new()
	noise.seed = shape_seed + 11
	noise.frequency = 0.03
	var normals := _normals(_outline)
	var n := _outline.size()
	var along := 0.0
	var next_slot := rng.randf_range(0.0, CROWD_SLOT)
	var deep := CROWD_DEPTH
	for i in n:
		var a := _outline[i]
		var b := _outline[(i + 1) % n]
		var seg := a.distance_to(b)
		while next_slot < along + seg:
			var q := a.lerp(b, (next_slot - along) / maxf(seg, 0.001))
			var nrm := normals[i].lerp(normals[(i + 1) % n], (next_slot - along) / maxf(seg, 0.001)).normalized()
			var track_q := _nearest_track(q)
			# Más gente donde la pista pasa cerca; tramos con mucha y con poca.
			var near := 1.0 - clampf((q.distance_to(track_q) - course.half_width) / CROWD_REACH, 0.0, 1.0)
			# Solo en la playa que mira a la pista (no en la de atrás de la isla).
			if nrm.dot((track_q - q).normalized()) < 0.35:
				near = 0.0
			var busy := clampf(noise.get_noise_1d(next_slot) * 0.9 + 0.55, 0.0, 1.0)
			if near > 0.0 and rng.randf() < (0.25 + 0.45 * near) * (0.35 + 0.65 * busy) * minf(crowd, 1.0):
				_crowd_slot(lists, rng, q, nrm, track_q, deep, crowd * (0.5 + 0.5 * busy))
			next_slot += CROWD_SLOT * rng.randf_range(0.8, 1.25)
		along += seg
	return lists


## Un tramo de playa: un grupo de gente, sillas con sombrilla, reposeras o
## una bandera. `q` es el punto de la orilla, `out` hacia el mar.
func _crowd_slot(lists: Dictionary, rng: RandomNumberGenerator, q: Vector2, out: Vector2, track_q: Vector2,
		deep: float, amount: float) -> void:
	var side := Vector2(-out.y, out.x)
	var roll := rng.randf()
	if roll < 0.55:
		# Gente parada en la orilla, en una o dos filas.
		var count := clampi(int(round(rng.randf_range(1.0, 3.0) * amount)), 1, 4)
		for k in count:
			var row := 0.85 if k % 2 == 0 else 1.6
			var p := q - out * (row + rng.randf_range(-0.15, 0.15)) + side * rng.randf_range(-1.4, 1.4)
			_crowd_put(lists, rng, "stand%d" % (rng.randi() % BeachCrowd.STANDING), p, track_q, 0.35)
	elif roll < 0.68:
		# Toallas en la arena (una o dos, a veces con alguien parado al lado).
		for k in rng.randi_range(1, 2):
			var p := q - out * rng.randf_range(1.0, 1.7) + side * rng.randf_range(-1.1, 1.1)
			_crowd_put(lists, rng, "towel", p, track_q, 0.5)
		if rng.randf() < 0.5:
			_crowd_put(lists, rng, "stand%d" % (rng.randi() % BeachCrowd.STANDING), q - out * 0.8 + side * 1.3,
				track_q, 0.3)
	elif roll < 0.84:
		# Sombrilla con dos sillas (casi siempre con alguien sentado).
		var c := q - out * rng.randf_range(1.1, 1.5)
		_crowd_put(lists, rng, "umbrella", c - out * 0.6, track_q, 0.0, true)
		for s in [-0.65, 0.65]:
			var p := c + side * float(s)
			if _crowd_put(lists, rng, "chair", p, track_q, 0.25) and rng.randf() < 0.8:
				_crowd_put(lists, rng, "sit%d" % (rng.randi() % BeachCrowd.SITTING), p, track_q, 0.0, false,
					_last_yaw)
	elif roll < 0.92:
		# Dos reposeras con su sombrilla.
		var c := q - out * 1.5
		_crowd_put(lists, rng, "umbrella", c - out * 0.9, track_q, 0.0, true)
		for s in [-0.45, 0.45]:
			_crowd_put(lists, rng, "lounger", c + side * float(s), track_q, 0.15)
	else:
		# Una bandera y alguien al lado.
		var p := q - out * rng.randf_range(1.0, 1.8)
		_crowd_put(lists, rng, "flag", p, track_q, 0.0, true)
		_crowd_put(lists, rng, "stand%d" % (rng.randi() % BeachCrowd.STANDING), p + side * 0.8, track_q, 0.3)


var _last_yaw: float = 0.0


## Pone una cosa del público en `p`, mirando a la pista (más un poco de giro
## al azar). Devuelve false si ahí no se puede (fuera de la arena, sobre el
## pasto).
func _crowd_put(lists: Dictionary, rng: RandomNumberGenerator, model: String, p: Vector2, track_q: Vector2,
		turn: float, any_yaw: bool = false, yaw: float = INF) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _outline) or _on_grass(p):
		return false
	if BezierShape.distance_to_edge(_outline, p) < 0.6:
		return false
	var room: float = CROWD_ROOM.get(model.rstrip("0123456789"), 0.0)
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
	if not lists.has(model):
		lists[model] = [[] as Array[Transform3D], [] as Array[Color]]
	(lists[model][0] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, SAND_Y, p.y)))
	(lists[model][1] as Array[Color]).append(BeachCrowd.custom(rng))
	return true


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
	if _rng.randf() < 0.55:
		var s := _rng.randf_range(0.6, 1.6) * size
		ferns[_rng.randi() % FERN_MODELS].append(_placed(q, ground + 0.05, Vector2.RIGHT.rotated(_rng.randf() * TAU), s))
	else:
		# Arbustos: de bajitos y anchos a altos y redondos.
		var r := _rng.randf_range(0.45, 1.1) * size
		var tall := _rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(r, r * tall, r))
		bushes.append(Transform3D(basis, Vector3(q.x, ground + r * tall * 0.35, q.y)))
		colors.append(Color("123d16").lerp(Color("4f9a34"), _rng.randf()))


## Dónde va una palmera modelo: en `p`, inclinada hacia `dir` (los modelos se
## arman inclinados hacia +X) y con un tamaño.
func _placed(p: Vector2, ground: float, dir: Vector2, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(p.x, ground - 0.25, p.y))


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
