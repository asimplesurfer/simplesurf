class_name PalmMesh
extends RefCounted
## Una palmera armada por código, en una sola malla (para repetirla con
## MultiMesh): tronco curvo con anillos, cocos, hojas en forma de pluma
## (nervadura que sube y cae, con foliolos finitos a los dos lados en V) y un
## par de hojas secas colgando.
##
## Se arma inclinada hacia +X con la base en (0, 0, 0). Superficie 0: tronco y
## cocos; superficie 1: hojas (de las dos caras).

const TRUNK_DARK := Color("5a4330")
const TRUNK_LIGHT := Color("8a6a48")
const LEAF_BASE := Color("1e5a1e")
const LEAF_TIP := Color("6fae35")
const LEAF_DRY := Color("9a8a4a")
const NUT := Color("5e4326")


## height: alto (m). lean: inclinación (rad, 0 = derecha). detail: 1 = la
## completa (para las que se ven de cerca), menos = menos triángulos (las de
## adentro de la selva). trunk: false para un helecho (solo la corona, al ras).
static func build(palm_seed: int, height: float, lean: float, detail: float = 1.0, trunk: bool = true) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = palm_seed
	var reach := height * sin(lean)
	var rise := height * cos(lean * 0.6)
	# Curva del tronco (Bézier cuadrática): sale inclinado y se endereza arriba.
	var p0 := Vector3.ZERO
	var p1 := Vector3(reach * 0.62, rise * 0.42, 0.0)
	var p2 := Vector3(reach, rise, 0.0)
	var top := p2 if trunk else Vector3(0.0, 0.1, 0.0)
	var top_dir := (p2 - p1).normalized()

	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	if trunk:
		_trunk(bark, p0, p1, p2, rng, detail)
		_nuts(bark, top, top_dir, rng)
	bark.index()
	bark.generate_normals()
	var bark_mat := ToonMaterial.make(Color.WHITE, 0.025)
	bark_mat.vertex_color_use_as_albedo = true
	bark.set_material(bark_mat)
	bark.commit(mesh)

	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 12 if detail >= 1.0 else (8 if detail >= 0.5 else 6)
	var steps := 8 if detail >= 1.0 else (6 if detail >= 0.5 else 3)
	var turn := rng.randf() * TAU
	for k in count:
		var yaw := turn + TAU * k / count + rng.randf_range(-0.18, 0.18)
		if trunk:
			# Las de arriba más paradas, las de abajo más caídas.
			var up := rng.randf_range(0.15, 0.85)
			var length := height * rng.randf_range(0.42, 0.55) + 1.5
			_frond(leaves, top, yaw, up, length, false, rng, steps)
		else:
			# Helecho: las mismas hojas pero saliendo del suelo hacia arriba,
			# abiertas en abanico, y que caen poco.
			var up := rng.randf_range(0.8, 1.25)
			var length := height * rng.randf_range(0.85, 1.1)
			_frond(leaves, top, yaw, up, length, false, rng, steps, rng.randf_range(0.3, 0.45))
	# Hojas secas colgando abajo de la corona.
	if trunk:
		for k in 2:
			var yaw := turn + rng.randf() * TAU
			_frond(leaves, top - Vector3.UP * 0.3, yaw, -0.6, height * 0.32 + 1.0, true, rng, steps)
	var leaf_mat := ToonMaterial.make(Color.WHITE, 0.0)
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves.set_material(leaf_mat)
	leaves.commit(mesh)
	return mesh


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


## Tronco: un tubo continuo, más ancho abajo, con anillos (la corteza de la
## palmera) que se marcan en el radio y en el color.
static func _trunk(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, rng: RandomNumberGenerator, detail: float) -> void:
	var sides := 8 if detail >= 1.0 else 6
	var rings := 22 if detail >= 1.0 else 11
	var length := p0.distance_to(p1) + p1.distance_to(p2)
	var prev: Array[Vector3] = []
	var prev_col: Color
	for i in rings + 1:
		var t := float(i) / rings
		var c := _bezier(p0, p1, p2, t)
		var tangent := (_bezier(p0, p1, p2, minf(t + 0.01, 1.0)) - _bezier(p0, p1, p2, maxf(t - 0.01, 0.0))).normalized()
		var side := tangent.cross(Vector3.BACK).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var other := tangent.cross(side).normalized()
		# Más ancha la base y un anillo cada ~0.5 m.
		var r := lerpf(0.42, 0.27, t) + 0.22 * pow(1.0 - t, 6.0)
		var band := fmod(t * length / 0.5, 1.0)
		r *= 1.0 + 0.07 * smoothstep(0.75, 1.0, band)
		var col := TRUNK_DARK.lerp(TRUNK_LIGHT, 0.35 + 0.4 * smoothstep(0.0, 0.8, band) + rng.randf_range(-0.05, 0.05))
		var ring: Array[Vector3] = []
		for s in sides:
			var a := TAU * s / sides
			ring.append(c + (side * cos(a) + other * sin(a)) * r)
		if not prev.is_empty():
			for s in sides:
				var s2 := (s + 1) % sides
				for v in [[prev[s], prev_col], [ring[s], col], [ring[s2], col], [prev[s], prev_col], [ring[s2], col], [prev[s2], prev_col]]:
					st.set_color(v[1])
					st.add_vertex(v[0])
		prev = ring
		prev_col = col


## Racimo de cocos abajo de la corona.
static func _nuts(st: SurfaceTool, top: Vector3, dir: Vector3, rng: RandomNumberGenerator) -> void:
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
		var c := top - dir * 0.55 + Vector3(cos(a), 0.0, sin(a)) * 0.38
		var r := 0.22
		# Octaedro un poco redondeado: alcanza de lejos.
		var pts := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
		for f in [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]:
			for idx in f:
				st.set_color(NUT)
				st.add_vertex(c + pts[idx] * r)


## Una hoja, simple (estilo low-poly): una lámina doblada en V a lo largo de la
## nervadura, que sale de la corona subiendo y cae en arco. El borde va en
## zigzag (unas pocas puntas grandes, como los foliolos de la palmera). Más
## oscura en la base y más clara en las puntas.
static func _frond(st: SurfaceTool, top: Vector3, yaw: float, up: float, length: float, dry: bool, rng: RandomNumberGenerator, steps: int, droop: float = -1.0) -> void:
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	if droop < 0.0:
		droop = rng.randf_range(0.55, 0.75)
	var pts: Array[Vector3] = []
	for i in steps + 1:
		var s := float(i) / steps
		pts.append(top + fwd * (length * s * cos(up * 0.5)) + Vector3.UP * (length * (sin(up) * s - droop * s * s)))
	var base_col := LEAF_DRY.darkened(0.25) if dry else LEAF_BASE
	var tip_col := LEAF_DRY if dry else LEAF_TIP.lerp(LEAF_BASE, rng.randf_range(0.0, 0.25))
	# Borde de cada lado: ancho en el medio, finito en la base y en la punta;
	# un punto sí y uno no más adentro (las puntas del zigzag).
	for sgn in [-1.0, 1.0]:
		var edge: Array[Vector3] = []
		for i in steps + 1:
			var s := float(i) / steps
			var tangent := (pts[mini(i + 1, steps)] - pts[maxi(i - 1, 0)]).normalized()
			var side := tangent.cross(Vector3.UP).normalized()
			var w := length * 0.2 * sin(PI * clampf(s * 0.95 + 0.05, 0.0, 1.0))
			if dry:
				w *= 0.6
			if i % 2 == 1:
				w *= 0.55
			# Las puntas apuntan hacia adelante y cuelgan (la V).
			var forward := tangent * (w * 0.5 if i % 2 == 0 else 0.0)
			edge.append(pts[i] + side * sgn * w + forward - Vector3.UP * w * 0.55)
		for i in steps:
			var c0 := base_col.lerp(tip_col, float(i) / steps)
			var c1 := base_col.lerp(tip_col, float(i + 1) / steps)
			var e0 := c0.lerp(tip_col, 0.35)
			var e1 := c1.lerp(tip_col, 0.35)
			_leaf_vertex(st, pts[i], c0)
			_leaf_vertex(st, pts[i + 1], c1)
			_leaf_vertex(st, edge[i + 1], e1)
			_leaf_vertex(st, pts[i], c0)
			_leaf_vertex(st, edge[i + 1], e1)
			_leaf_vertex(st, edge[i], e0)


static func _leaf_vertex(st: SurfaceTool, v: Vector3, col: Color) -> void:
	# Normal para arriba: las dos caras se ven con luz pareja (como hojas finas).
	st.set_normal(Vector3.UP)
	st.set_color(col)
	st.add_vertex(v)
