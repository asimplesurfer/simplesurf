class_name JungleMesh
extends RefCounted
## Plantas de selva armadas por código, cada una en una sola malla (para
## repetirlas con MultiMesh, como las palmeras de PalmMesh):
## - tree: árbol de selva. Tronco que se afina, con raíces que se abren abajo y
##   alguna rama; copa hecha de varias bolas de hojas (low poly). Tres estilos:
##   GIANT (alto y finito con la copa ancha y chata arriba, con lianas
##   colgando), ROUND (mediano, copa redonda) y SMALL (bajito y tupido).
## - bamboo: una mata de cañas de bambú (con sus nudos) que se abren hacia
##   afuera, con hojitas finas arriba.
## - big_leaves: planta de hojas grandes al ras del suelo.
##
## Base en (0, 0, 0). Superficie 0: madera / cañas; superficie 1: hojas.

enum { GIANT, ROUND, SMALL }

const BARK_DARK := Color("2e2118")
const BARK_LIGHT := Color("4f3d2e")
const LEAF_DARK := Color("173f17")
const LEAF_LIGHT := Color("4c8a2a")
const VINE := Color("2f5a1e")
const CANE_DARK := Color("6f8a2a")
const CANE_LIGHT := Color("a9b850")
const CANE_NODE := Color("4f5a22")


## Árbol de selva de `height` m. `leaf`: el verde principal de las hojas.
static func tree(tree_seed: int, height: float, style: int, leaf: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := height * (0.028 if style == GIANT else 0.045)
	# Tronco: una curva suave, apenas torcida.
	var bend := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * height * 0.06
	var top := Vector3(bend.x, height * (0.82 if style == GIANT else 0.62), bend.z)
	var mid := Vector3(bend.x * 0.3, top.y * 0.5, bend.z * 0.3)
	_tube(wood, [Vector3.ZERO, mid, top], [radius * 1.25, radius * 0.85, radius * 0.5], 7, BARK_DARK, BARK_LIGHT)
	# Raíces que se abren abajo (aletas), en los grandes y medianos.
	if style != SMALL:
		var count := 4 if style == GIANT else 3
		for k in count:
			var a := TAU * k / count + rng.randf_range(-0.3, 0.3)
			var out := Vector3(cos(a), 0.0, sin(a))
			_tube(wood, [out * radius * 3.2 + Vector3(0, -0.2, 0), out * radius * 1.4 + Vector3(0, radius * 2.2, 0), Vector3(0, radius * 4.5, 0)],
				[radius * 0.35, radius * 0.45, radius * 0.3], 4, BARK_DARK, BARK_DARK)
	# Ramas que salen de arriba del tronco hacia la copa.
	var crown_r := height * (0.32 if style == GIANT else 0.3 if style == ROUND else 0.38)
	var branches := 4 if style == GIANT else 3
	var crown_pts: Array[Vector3] = []
	for k in branches:
		var a := TAU * k / branches + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var from := top.lerp(mid, rng.randf_range(0.0, 0.35))
		var to := top + out * crown_r * rng.randf_range(0.5, 0.8) + Vector3(0, height * rng.randf_range(0.04, 0.1), 0)
		_tube(wood, [from, (from + to) * 0.5 + Vector3(0, height * 0.04, 0), to], [radius * 0.45, radius * 0.32, radius * 0.18], 5, BARK_DARK, BARK_LIGHT)
		crown_pts.append(to)
	# Copa: bolas de hojas. Los gigantes, chata y ancha (como un paraguas); los
	# otros, más redonda.
	var blobs := 9 if style == GIANT else 7 if style == ROUND else 6
	var flat := 0.5 if style == GIANT else 0.75
	var center := top + Vector3(0, crown_r * (0.15 if style == GIANT else 0.35), 0)
	for k in blobs:
		var p: Vector3
		if k < crown_pts.size():
			p = crown_pts[k] + Vector3(0, crown_r * 0.12, 0)
		else:
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.2, 0.75) * crown_r
			p = center + Vector3(cos(a) * d, rng.randf_range(-0.25, 0.35) * crown_r * flat, sin(a) * d)
		var r := crown_r * rng.randf_range(0.42, 0.62)
		var shade := rng.randf()
		var col := leaf.darkened(0.35).lerp(leaf.lightened(0.1), shade)
		_blob(leaves, p, Vector3(r, r * flat * rng.randf_range(0.8, 1.1), r), col, rng)
	# Lianas colgando de la copa de los gigantes.
	if style == GIANT:
		for k in 5:
			var a := rng.randf() * TAU
			var p := center + Vector3(cos(a), 0.0, sin(a)) * crown_r * rng.randf_range(0.4, 0.85) - Vector3(0, crown_r * 0.2, 0)
			_vine(leaves, p, height * rng.randf_range(0.2, 0.45), rng)
	return _finish(wood, leaves)


## Mata de bambú: `stalks` cañas de hasta `height` m.
static func bamboo(cane_seed: int, height: float, stalks: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = cane_seed
	var canes := SurfaceTool.new()
	canes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in stalks:
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var base := out * rng.randf_range(0.0, 0.9)
		var h := height * rng.randf_range(0.6, 1.0)
		var lean := rng.randf_range(0.08, 0.3)
		var r := rng.randf_range(0.07, 0.11)
		# La caña: se abre hacia afuera y se curva arriba.
		var pts: Array[Vector3] = []
		var radii: Array[float] = []
		var segs := 8
		for i in segs + 1:
			var t := float(i) / segs
			pts.append(base + out * (h * lean * t * t) + Vector3(0, h * t, 0))
			radii.append(r * (1.0 - 0.45 * t))
		_tube(canes, pts, radii, 5, CANE_DARK, CANE_LIGHT, CANE_NODE)
		# Hojitas finas en la mitad de arriba.
		for i in range(segs / 2, segs + 1):
			if rng.randf() > 0.75:
				continue
			for j in 3:
				var yaw := rng.randf() * TAU
				var dir := Vector3(cos(yaw), rng.randf_range(-0.5, -0.1), sin(yaw)).normalized()
				_leaf(leaves, pts[i], dir, rng.randf_range(0.7, 1.2), 0.14,
					LEAF_LIGHT.lerp(Color("8fbf4a"), rng.randf()), LEAF_DARK.lerp(LEAF_LIGHT, 0.4))
	return _finish(canes, leaves)


## Planta de hojas grandes (como una oreja de elefante), al ras del suelo.
static func big_leaves(plant_seed: int, size: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = plant_seed
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := rng.randi_range(5, 7)
	for k in count:
		var yaw := TAU * k / count + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var tip := out * size * rng.randf_range(0.35, 0.6) + Vector3(0, size * rng.randf_range(0.5, 0.9), 0)
		_tube(stems, [Vector3.ZERO, tip * 0.5 + Vector3(0, size * 0.1, 0), tip], [0.05, 0.04, 0.03], 4, VINE, LEAF_LIGHT)
		var dir := (out + Vector3(0, rng.randf_range(-0.35, 0.1), 0)).normalized()
		_leaf(leaves, tip, dir, size * rng.randf_range(0.75, 1.0), 0.45, LEAF_DARK.lerp(LEAF_LIGHT, rng.randf_range(0.2, 0.7)), LEAF_DARK)
	return _finish(stems, leaves)


# ------------------------------------------------------------------ partes

## Un tubo por los puntos `pts` (con su radio en cada uno). Con `node` pinta un
## anillo oscuro en cada punto (los nudos del bambú).
static func _tube(st: SurfaceTool, pts: Array, radii: Array, sides: int, dark: Color, light: Color, node: Color = Color(0, 0, 0, 0)) -> void:
	var rings: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * k / sides
			ring.append(p + (side * cos(a) + up * sin(a)) * float(radii[i]))
		rings.append(ring)
	for i in pts.size() - 1:
		var a: Array[Vector3] = rings[i]
		var b: Array[Vector3] = rings[i + 1]
		for k in sides:
			var k2 := (k + 1) % sides
			var shade := 0.5 + 0.5 * cos(TAU * k / sides)
			var c := dark.lerp(light, shade)
			var cb := c
			if node.a > 0.0:
				# Abajo de cada tramo, el nudo (más oscuro).
				c = node
			for v in [[a[k], c], [b[k], cb], [b[k2], cb], [a[k], c], [b[k2], cb], [a[k2], c]]:
				st.set_color(v[1])
				st.add_vertex(v[0])


## Una bola de hojas (esfera chata, con los vértices movidos un poco al azar
## para que no se vea perfecta).
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var lat := 4
	var lon := 7
	var grid: Array = []
	for i in lat + 1:
		var row: Array[Vector3] = []
		var th := PI * i / lat
		for j in lon:
			var ph := TAU * j / lon + (0.4 if i % 2 == 1 else 0.0)
			var jitter := 1.0 if i == 0 or i == lat else rng.randf_range(0.85, 1.12)
			row.append(c + Vector3(sin(th) * cos(ph) * r.x, cos(th) * r.y, sin(th) * sin(ph) * r.z) * jitter)
		grid.append(row)
	var top := col.lightened(0.12)
	var bottom := col.darkened(0.3)
	for i in lat:
		for j in lon:
			var j2 := (j + 1) % lon
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][j2]
			var d: Vector3 = grid[i + 1][j]
			var e: Vector3 = grid[i + 1][j2]
			var shade := top.lerp(bottom, float(i) / lat)
			for v in [a, d, e, a, e, b]:
				st.set_color(shade)
				st.add_vertex(v)


## Una hoja larga (rombo con un pliegue en el medio) que sale de `at` hacia `dir`.
static func _leaf(st: SurfaceTool, at: Vector3, dir: Vector3, length: float, width: float, col: Color, base: Color) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var mid := at + dir * length * 0.45 + Vector3(0, -length * 0.06, 0)
	var tip := at + dir * length + Vector3(0, -length * 0.2, 0)
	var w := side * length * width
	var fold := Vector3(0, length * width * 0.25, 0)
	for v in [[at, base], [mid + w, col], [mid + fold, col], [mid + fold, col], [mid + w, col], [tip, col],
			[at, base], [mid + fold, col], [mid - w, col], [mid + fold, col], [tip, col], [mid - w, col]]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## Una liana que cuelga de `at` (una tira finita que baja haciendo eses).
static func _vine(st: SurfaceTool, at: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	var segs := 6
	var sway := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.4
	var prev := at
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := at + Vector3(0, -length * t, 0) + sway * sin(t * PI * 1.5)
		var w := Vector3(0.06, 0, 0.06)
		for v in [prev - w, p - w, p + w, prev - w, p + w, prev + w]:
			st.set_color(VINE)
			st.add_vertex(v)
		prev = p


## Arma la malla con sus dos superficies (madera y hojas), sin contorno (como
## las palmeras) y con las hojas de las dos caras.
static func _finish(wood: SurfaceTool, leaves: SurfaceTool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	wood.generate_normals()
	var wood_mat := ToonMaterial.make(Color.WHITE, 0.0)
	wood_mat.vertex_color_use_as_albedo = true
	wood.set_material(wood_mat)
	wood.commit(mesh)
	leaves.generate_normals()
	var leaf_mat := ToonMaterial.make(Color.WHITE, 0.0)
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves.set_material(leaf_mat)
	leaves.commit(mesh)
	return mesh
