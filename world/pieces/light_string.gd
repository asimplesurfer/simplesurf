class_name LightStringPiece
extends MapPiece
## Guirnalda de luces entre dos islas tropicales: uno o varios cables (hasta
## 20) que salen de palmeras de una isla y llegan a palmeras de la otra, con
## focos colgando. Cada cable está atado al tronco (un nudo de soga abajo de
## la copa) y cae un poco por su peso. De día están apagados (vidrio de
## color). Al atardecer se prenden suave; de noche alumbran fuerte: una luz
## que llega a lo que está cerca y luces en el agua que iluminan las olas y
## se reflejan en ellas.
##
## En el mapa: `a` y `b` son un punto en cada isla (donde se toca en el
## editor); cada punta se ata a las palmeras de esa isla más cercanas a ese
## punto. `style`: "fria", "calida" o "navidad". Las islas se buscan al final
## (finish), cuando ya tienen sus palmeras.

const REQUIRED := ["a", "b"]

## Cómo se ve en el editor de mapas (ver MapPiece.editor_entry).
const EDITOR := {
	"name": "Guirnalda de luces", "place": "two_points",
	"hint": "Tocá una isla tropical y después la otra: la guirnalda va de palmeras de una a palmeras de la otra (de noche se prenden).",
	"fields": {
		"lines": "Cables (1 a 20)",
		"style": {"label": "Luces", "kind": "choice", "options": [["calida", "Cálidas"], ["fria", "Frías"], ["navidad", "Navideñas"]]},
	},
}

var a: Vector2 = Vector2.ZERO
var b: Vector2 = Vector2.ZERO
## Cuántos cables cruzan de una isla a la otra (1 a 20).
var lines: int = 1
## Color de las luces: "fria", "calida" o "navidad".
var style: String = "calida"

const STYLES := ["fria", "calida", "navidad"]
const MAX_LINES := 20
## Distancia entre focos (m) y radio del cable (m).
const BULB_GAP := 0.95
const WIRE := 0.035
## Lo más bajo que puede quedar un cable sobre el agua (m): que no cuelgue
## sobre la gente que pasa.
const LOWEST := 7.0
const WIRE_COLOR := Color("2a2420")
const ROPE_COLOR := Color("e2c48a")
const COLD := Color(0.72, 0.86, 1.0)
const WARM := Color(1.0, 0.72, 0.36)
const XMAS: Array[Color] = [
	Color(1.0, 0.16, 0.14), Color(0.2, 0.95, 0.3), Color(0.25, 0.45, 1.0), Color(1.0, 0.82, 0.18), Color(1.0, 0.4, 0.85),
]

const BULB_SHADER := preload("res://world/pieces/lib/string_bulb.gdshader")
const GLOW_SHADER := preload("res://world/pieces/lib/string_glow.gdshader")

## Cables armados: cada uno [punta en la isla de a, punta en la isla de b]
## (para los tests).
var cables: Array = []
## Las islas que une (para los tests).
var island_a: TropicalIslandPiece
var island_b: TropicalIslandPiece


func finish(course: Course) -> void:
	island_a = _island_at(course, a)
	island_b = _island_at(course, b)
	if island_a == null or island_b == null or island_a == island_b:
		push_warning("light_string: las dos puntas tienen que estar en dos islas tropicales distintas")
		return
	var n := clampi(lines, 1, MAX_LINES)
	# El mismo "costado" para las dos puntas: el cable de más a la izquierda
	# en una isla llega al de más a la izquierda en la otra (no se cruzan).
	var across := (b - a).normalized()
	var side := Vector2(-across.y, across.x)
	var ties_a := _pick_ties(island_a, a, b, n, side)
	var ties_b := _pick_ties(island_b, b, a, n, side)
	if ties_a.is_empty() or ties_b.is_empty():
		push_warning("light_string: una de las islas no tiene palmeras altas")
		return
	var root := Node3D.new()
	root.name = "LightString"
	course.add_child(root, true)
	var wires := SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ropes := SurfaceTool.new()
	ropes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bulbs: Array[Transform3D] = []
	var colors: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.x * 13.0 + a.y * 7.0 + b.x * 3.0 + b.y)
	for i in n:
		var ta: Array = ties_a[i]
		var tb: Array = ties_b[i]
		var p0 := _knot(ropes, ta, tb[0])
		var p1 := _knot(ropes, tb, ta[0])
		cables.append([p0, p1])
		_cable(wires, bulbs, colors, p0, p1, i, rng)
	var mi := MeshInstance3D.new()
	mi.name = "Wires"
	var wire_mat := ToonMaterial.make(WIRE_COLOR, 0.0)
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wires.set_material(wire_mat)
	var mesh := wires.commit()
	var rope_mat := ToonMaterial.make(ROPE_COLOR, 0.0)
	rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ropes.set_material(rope_mat)
	ropes.commit(mesh)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# De día apagadas; al atardecer prendidas suave; de noche, a full.
	var lit := 0.0
	match DayTime.of(course):
		GameSettings.TimeOfDay.NIGHT:
			lit = 1.0
		GameSettings.TimeOfDay.SUNSET:
			lit = 0.45
	var twinkle := 0.35 if style == "navidad" else 0.08
	root.add_child(_bulbs(bulbs, colors, lit, twinkle))
	if lit > 0.0:
		root.add_child(_glows(bulbs, colors, lit, twinkle))
		_light_up(course, root, colors, lit)


## La luz que dan: una luz de verdad por guirnalda (alumbra las palmeras, la
## arena y a los surfistas que pasan) y unas cuantas luces en el agua (ver
## Water.add_lamp), que iluminan el mar y las olas y se reflejan en ellas.
## Colores un poco lavados (no saturados).
func _light_up(course: Course, root: Node3D, colors: Array[Color], lit: float) -> void:
	var tint := Color.BLACK
	for c in colors:
		tint += Color(c.r, c.g, c.b)
	# Más amarillo que naranja: el naranja sumado al mar azul de noche queda
	# gris violáceo; el amarillo cálido lo lleva a un verde agua más natural.
	tint = (tint / maxf(colors.size(), 1)).lerp(Color(1.0, 0.93, 0.7), 0.6)
	# La guirnalda como un solo cable (el promedio de todos).
	var e0 := Vector3.ZERO
	var e1 := Vector3.ZERO
	for c in cables:
		e0 += c[0]
		e1 += c[1]
	e0 /= maxf(cables.size(), 1)
	e1 /= maxf(cables.size(), 1)
	var span := e0.distance_to(e1)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = tint
	light.light_energy = 3.0 * lit
	light.omni_range = maxf(span * 0.75, 22.0)
	light.omni_attenuation = 0.8
	light.shadow_enabled = false
	light.light_specular = 0.08
	# El agua no: se ilumina sola (así se iluminan bien las olas, sin el
	# límite de luces por objeto del motor).
	light.light_cull_mask = Water.LIGHT_MASK
	light.position = (e0 + e1) * 0.5 - Vector3.UP * 2.0
	root.add_child(light)
	var water := course.get_tree().get_first_node_in_group("water") as Water if course.is_inside_tree() else null
	if water == null:
		return
	var n := clampi(roundi(span / LAMP_SPACING), 1, 3)
	for i in n:
		var p := e0.lerp(e1, (i + 0.5) / n) - Vector3.UP * 1.5
		water.add_lamp(root.to_global(p) if root.is_inside_tree() else p, tint, LAMP_REACH, lit)


## Cada cuántos metros de guirnalda hay una luz en el agua (hasta 3), y hasta
## dónde llega cada una.
const LAMP_SPACING := 24.0
const LAMP_REACH := 26.0


## La isla tropical de un punto (la que lo tiene adentro, o la más cercana).
func _island_at(course: Course, p: Vector2) -> TropicalIslandPiece:
	var best: TropicalIslandPiece = null
	var best_d := 30.0
	for piece in course.pieces:
		var isl := piece as TropicalIslandPiece
		if isl == null or isl.palm_ties.is_empty() or isl._outline.is_empty():
			continue
		var d := 0.0 if Geometry2D.is_point_in_polygon(p, isl._outline) else BezierShape.distance_to_edge(isl._outline, p)
		if d < best_d:
			best_d = d
			best = isl
	return best


## Las palmeras de donde salen los `n` cables en esta isla: las altas más
## cerca del punto tocado (y del lado de la otra isla), ordenadas de un
## costado al otro (así los cables no se cruzan). Si no alcanzan, una misma
## palmera lleva más de un cable, cada uno un poco más abajo.
func _pick_ties(isl: TropicalIslandPiece, here: Vector2, there: Vector2, n: int, side: Vector2) -> Array:
	var ties: Array = isl.palm_ties.duplicate()
	ties.sort_custom(func(x: Array, y: Array) -> bool:
		return _tie_score(x, here, there) < _tie_score(y, here, there))
	# Solo palmeras cerca del punto tocado (no del medio de la isla): si no
	# alcanzan, una palmera lleva más de un cable.
	# Una palmera lleva como mucho 3 o 4 cables: si con las de cerca no
	# alcanza, se busca un poco más lejos.
	var want := mini(int(ceil(n / 3.0)), ties.size())
	var reach := PICK_RADIUS + n * 0.8
	var near: Array = []
	while true:
		near.clear()
		for t in ties:
			if _flat(t[0]).distance_to(here) <= reach:
				near.append(t)
		if near.size() >= want or reach >= 60.0:
			break
		reach += 5.0
	if near.is_empty():
		near = ties.slice(0, 1)
	var chosen := near.slice(0, mini(n, near.size()))
	if chosen.is_empty():
		return []
	chosen.sort_custom(func(x: Array, y: Array) -> bool:
		return _flat(x[0]).dot(side) < _flat(y[0]).dot(side))
	var out: Array = []
	var used := {}
	for i in n:
		# Repartidos de punta a punta entre las palmeras elegidas; si una lleva
		# más de un cable, el siguiente va un poco más abajo en el tronco.
		var k := int(floor(float(i) * chosen.size() / n))
		var times: int = used.get(k, 0)
		used[k] = times + 1
		var t: Array = chosen[k]
		out.append([t[0] - t[2] * times * 0.45, t[1] + 0.02 * times, t[2]])
	return out


## Hasta dónde del punto tocado se buscan palmeras (m, más con más cables).
const PICK_RADIUS := 10.0


## Más bajo = mejor: cerca del punto tocado, un poco del lado de la otra isla
## y las palmeras más altas (el cable queda más arriba).
func _tie_score(t: Array, here: Vector2, there: Vector2) -> float:
	var p := _flat(t[0])
	return p.distance_to(here) + 0.15 * p.distance_to(there) - 1.5 * (t[0] as Vector3).y


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## El nudo en el tronco: una vuelta de soga alrededor y el nudo del lado del
## cable. Devuelve de dónde sale el cable (la cara del tronco que mira a
## `toward`).
func _knot(st: SurfaceTool, tie: Array, toward: Vector3) -> Vector3:
	var c: Vector3 = tie[0]
	var r: float = tie[1]
	var axis: Vector3 = tie[2]
	var flat := Vector3(toward.x - c.x, 0.0, toward.z - c.z).normalized()
	# La vuelta de soga: un anillo un poco más ancho que el tronco.
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := axis.cross(u).normalized()
	# Dos vueltas de soga, bien por fuera de los anillos del tronco.
	var sides := 14
	var half := 0.06
	var rr := r * 1.08 + 0.035
	for wrap in [-0.09, 0.09]:
		var mid: Vector3 = c + axis * float(wrap)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var q := [mid + d0 * rr - axis * half, mid + d1 * rr - axis * half, mid + d1 * rr + axis * half,
				mid + d0 * rr + axis * half]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal((d0 if k in [0, 3] else d1))
				st.add_vertex(q[k])
	# El nudo, del lado del cable.
	var knot := c + flat * (rr + 0.06)
	_blob(st, knot, 0.11)
	return knot + flat * 0.05


## Una bolita (el nudo).
func _blob(st: SurfaceTool, at: Vector3, radius: float) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 6
	m.rings = 3
	var arrays := m.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		st.set_normal(normals[k])
		st.add_vertex(at + verts[k])


## Un cable de p0 a p1 que cae por su peso, con focos colgando.
func _cable(st: SurfaceTool, bulbs: Array[Transform3D], colors: Array[Color], p0: Vector3, p1: Vector3, line: int,
		rng: RandomNumberGenerator) -> void:
	var span := p0.distance_to(p1)
	var sag := clampf(span * 0.05, 0.25, maxf(0.25, minf(p0.y, p1.y) - LOWEST))
	var segs := maxi(6, int(span / 1.2))
	var prev := p0
	for k in range(1, segs + 1):
		var t := float(k) / segs
		var p := _at(p0, p1, sag, t)
		_tube(st, prev, p)
		prev = p
	var count := maxi(int(span / BULB_GAP), 1)
	var base := _color(line, 0)
	for k in count:
		var t := (k + 0.5) / count
		var p := _at(p0, p1, sag, t) - Vector3.UP * 0.1
		bulbs.append(Transform3D(Basis.IDENTITY, p))
		var col := base if style != "navidad" else _color(line, k)
		colors.append(Color(col.r, col.g, col.b, rng.randf()))


static func _at(p0: Vector3, p1: Vector3, sag: float, t: float) -> Vector3:
	return p0.lerp(p1, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)


func _color(line: int, k: int) -> Color:
	match style:
		"fria":
			return COLD
		"navidad":
			return XMAS[(line * 2 + k) % XMAS.size()]
	return WARM


## Un tramo de cable: un tubo finito de cuatro caras.
func _tube(st: SurfaceTool, p0: Vector3, p1: Vector3) -> void:
	var d := (p1 - p0).normalized()
	var u := d.cross(Vector3.UP).normalized()
	if u.length() < 0.1:
		u = Vector3.RIGHT
	var v := d.cross(u).normalized()
	var dirs := [u, v, -u, -v]
	for s in 4:
		var e0: Vector3 = dirs[s]
		var e1: Vector3 = dirs[(s + 1) % 4]
		var q := [p0 + e0 * WIRE, p0 + e1 * WIRE, p1 + e1 * WIRE, p1 + e0 * WIRE]
		var nrm := (e0 + e1).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm)
			st.add_vertex(q[k])


func _bulbs(items: Array[Transform3D], colors: Array[Color], lit: float, twinkle: float) -> MultiMeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	var mat := ShaderMaterial.new()
	mat.shader = BULB_SHADER
	mat.set_shader_parameter("lit", lit)
	mat.set_shader_parameter("twinkle", twinkle)
	return _multi("Bulbs", m, items, colors, mat)


func _glows(items: Array[Transform3D], colors: Array[Color], lit: float, twinkle: float) -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("strength", 0.5 * lit)
	mat.set_shader_parameter("twinkle", twinkle)
	return _multi("Glow", q, items, colors, mat)


func _multi(node_name: String, mesh: Mesh, items: Array[Transform3D], colors: Array[Color],
		mat: ShaderMaterial) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i])
		mm.set_instance_custom_data(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
