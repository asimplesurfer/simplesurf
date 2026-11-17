class_name BeachCrowd
extends RefCounted
## El público de las playas: gente alentando (parada, saltando y agitando los
## brazos, o sentada en sillas playeras), reposeras, sombrillas a rayas y
## banderas. Cada cosa es una malla chica armada con cajas y esferas, que se
## repite con MultiMesh; el color de cada uno y cómo se mueve salen del shader
## (crowd.gdshader) y de los datos de cada instancia (ver custom()).
##
## Todo mira hacia +Z (hacia la pista, una vez girado) con la base en y = 0.

const SHADER := preload("res://world/pieces/lib/crowd.gdshader")
const OUTLINE_SHADER := preload("res://world/pieces/lib/crowd_outline.gdshader")

## Qué parte es cada vértice (ver crowd.gdshader).
const FIXED := 0.0
const SKIN := 0.25
const OWN := 0.5
const ACCENT := 0.75
const HAIR := 0.875
const WHITE := 1.0

## Tonos de piel y colores de pelo de la gente (los naturales de los
## personajes jugables). Cada persona saca uno de cada lista (ver el shader).
const SKIN_TONES := [
	Color("#f3d0b0"), Color("#f8e0cc"), Color("#e0ac80"), Color("#b97b45"), Color("#8a5a3b"), Color("#5c3a24"),
]
const HAIR_TONES := [
	Color("#f0c13a"), Color("#7a4a24"), Color("#222222"), Color("#d2552b"), Color("#e8e8e8"), Color("#9a521c"),
]

## Colores fijos (pelo, caños, paja, ojos...). Van al shader como una lista
## (fixed_colors) y cada vértice dice cuál usa: el color de vértice no llega
## a la MultiMesh en el navegador.
const FIXED_COLORS := [
	Color("2b1d14"), Color("5a3a22"), Color("c99a4b"), Color("111111"),
	Color("c8c8cc"), Color("d9b56a"), Color("f2efe6"), Color("1a1a1a"), Color("7a2e26"),
]
const FRAME := Color("c8c8cc")
const STRAW := Color("d9b56a")
const POLE := Color("f2efe6")
const EYES := Color("1a1a1a")

## Modelos de gente parada y sentada (pocos: cada uno es una llamada de
## dibujo por isla; el color de cada persona sale del shader).
const STANDING := 5
const SITTING := 3

## Hasta dónde se ve el público (m): más lejos son puntitos y pesan mucho.
const VISIBLE_UP_TO := 200.0
## Tamaño del público al lado del personaje jugable (que mide ~2,7 m).
const PERSON_SCALE := 0.62
## Tamaño de todo el público (gente y cosas, en la misma proporción para que
## los sentados entren en sus sillas). Al lado del personaje jugable, la gente
## mide unos 2,3 m.
const SIZE := 1.35

static var _models: Dictionary = {}
## Escala con la que se arma la pieza actual.
static var _k: float = SIZE


## Las mallas (se arman una sola vez).
static func models() -> Dictionary:
	if _models.is_empty():
		# Parados: pelo corto, pelo largo, gorra, sombrero o rodete. Sentados:
		# pelo corto, pelo largo o sombrero.
		for i in STANDING:
			_models["stand%d" % i] = _person([0, 1, 2, 3, 4][i], false)
		for i in SITTING:
			_models["sit%d" % i] = _person([0, 1, 3][i], true)
		_models["chair"] = _chair()
		_models["lounger"] = _lounger()
		_models["umbrella"] = _umbrella()
		_models["flag"] = _flag()
		_models["towel"] = _towel()
	return _models


## Datos de una instancia: color propio, piel, fase y ganas (ver crowd.gdshader).
static func custom(rng: RandomNumberGenerator) -> Color:
	# Las ganas tiran a poco: la mayoría alienta tranquila, algunos saltan.
	return Color(rng.randf(), rng.randf(), rng.randf(), pow(rng.randf(), 1.8))


## Una MultiMesh de un modelo. `jump`: cuánto saltan (0 sentados y cosas).
static func multimesh(node_name: String, model: String, items: Array[Transform3D], customs: Array[Color],
		jump: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = models()[model]
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i])
		mm.set_instance_custom_data(i, customs[i])
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("jump", jump)
	var palette := PackedVector3Array()
	for c in FIXED_COLORS:
		palette.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("fixed_colors", palette)
	# Ropa de la gente en tonos pastel; las cosas de la playa, un poco más vivas.
	var person := model.begins_with("stand") or model.begins_with("sit")
	mat.set_shader_parameter("own_saturation", 0.32 if person else 0.4)
	mat.set_shader_parameter("accent_saturation", 0.3 if person else 0.38)
	mat.set_shader_parameter("skin_tones", _vec3s(SKIN_TONES))
	mat.set_shader_parameter("hair_tones", _vec3s(HAIR_TONES))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	# Contorno negro solo en la gente (como los personajes jugables).
	if model.begins_with("stand") or model.begins_with("sit"):
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("jump", jump)
		mat.next_pass = outline
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = VISIBLE_UP_TO
	return mmi


static func _vec3s(colors: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in colors:
		out.append(Vector3(c.r, c.g, c.b))
	return out


# ---------------------------------------------------------------- modelos

## Una persona con la misma estructura que los personajes jugables, pero más
## simple: cabeza grande de huevo con ojos de punto (sin boca), pecho y short redondeados,
## piernas cortas, pies redondos y las manos sueltas (sin brazos), arriba para
## alentar. variant: 0 pelo corto, 1 pelo largo, 2 gorra, 3 sombrero de
## paja, 4 rodete. El color del pelo y de la piel es de cada persona. Se arma con las
## medidas del personaje jugable y se achica a PERSON_SCALE.
static func _person(variant: int, sitting: bool) -> ArrayMesh:
	var st := _begin()
	_k = PERSON_SCALE * SIZE
	var torso := Vector3(0.0, 1.24, 0.0)
	var head := Vector3(0.0, 2.08, 0.02)
	if sitting:
		# Sentado en la silla: muslos para adelante y piernas para abajo.
		_ellipsoid(st, Vector3(0.36, 0.25, 0.38), Vector3(0.0, 0.85, 0.08), ACCENT)
		for side in [-1.0, 1.0]:
			_ellipsoid(st, Vector3(0.15, 0.14, 0.28), Vector3(side * 0.2, 0.86, 0.4), ACCENT)
			_ellipsoid(st, Vector3(0.13, 0.3, 0.13), Vector3(side * 0.2, 0.52, 0.64), SKIN)
			_ellipsoid(st, Vector3(0.13, 0.08, 0.2), Vector3(side * 0.2, 0.12, 0.74), SKIN)
		torso = Vector3(0.0, 1.28, -0.06)
		head = Vector3(0.0, 2.12, -0.06)
	else:
		for side in [-1.0, 1.0]:
			_ellipsoid(st, Vector3(0.14, 0.09, 0.21), Vector3(side * 0.24, 0.09, 0.07), SKIN)
			_ellipsoid(st, Vector3(0.15, 0.3, 0.15), Vector3(side * 0.24, 0.42, 0.0), SKIN)
		_ellipsoid(st, Vector3(0.36, 0.3, 0.3), Vector3(0.0, 0.82, 0.0), ACCENT)
	# Pecho (remera del color de cada uno) y cabeza de huevo.
	_ellipsoid(st, Vector3(0.37, 0.44, 0.27), torso, OWN)
	_ellipsoid(st, Vector3(0.5, 0.6, 0.47), head, SKIN, Color.WHITE, 0, 2)
	# Ojos de punto (sin boca).
	for side in [-1.0, 1.0]:
		_ellipsoid(st, Vector3(0.05, 0.05, 0.02), head + Vector3(side * 0.15, 0.06, 0.45), FIXED, EYES, 0, 0)
	match variant:
		2:
			# Gorra con visera.
			_ellipsoid(st, Vector3(0.51, 0.34, 0.49), head + Vector3(0.0, 0.27, -0.01), ACCENT)
			_ellipsoid(st, Vector3(0.28, 0.035, 0.24), head + Vector3(0.0, 0.31, 0.45), ACCENT)
		3:
			# Sombrero de paja.
			_cylinder(st, 0.72, 0.72, 0.04, head + Vector3(0.0, 0.34, 0.0), FIXED, STRAW)
			_cylinder(st, 0.34, 0.42, 0.28, head + Vector3(0.0, 0.48, 0.0), FIXED, STRAW)
		_:
			_ellipsoid(st, Vector3(0.53, 0.4, 0.5), head + Vector3(0.0, 0.22, -0.06), HAIR, Color.WHITE, 0, 2)
			if variant == 1:
				# Pelo largo: cae por atrás hasta los hombros.
				_ellipsoid(st, Vector3(0.5, 0.55, 0.26), head + Vector3(0.0, -0.15, -0.28), HAIR, Color.WHITE, 0, 1)
			elif variant == 4:
				# Rodete arriba.
				_ellipsoid(st, Vector3(0.2, 0.18, 0.2), head + Vector3(0.0, 0.62, -0.12), HAIR)
	# Manos sueltas, en alto para alentar (se mueven en el shader).
	for side in [-1.0, 1.0]:
		var hand := 1 if side < 0.0 else 2
		_ellipsoid(st, Vector3(0.15, 0.15, 0.17), head + Vector3(side * 0.78, 0.42, 0.12), SKIN, Color.WHITE, hand)
	_k = SIZE
	return _commit(st)


## Silla playera: caño de aluminio y lona a rayas (color propio y blanco).
static func _chair() -> ArrayMesh:
	var st := _begin()
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.03, 0.4, 0.03), Vector3(side * 0.25, 0.2, 0.22), FIXED, Basis(), 0, Vector3.ZERO, 1.0, FRAME)
		_box(st, Vector3(0.03, 0.7, 0.03), Vector3(side * 0.25, 0.42, -0.2), FIXED, Basis(Vector3.RIGHT, -0.35), 0,
			Vector3.ZERO, 1.0, FRAME)
	for k in 3:
		var part := OWN if k != 1 else WHITE
		var x := (k - 1) * 0.167
		_box(st, Vector3(0.167, 0.03, 0.42), Vector3(x, 0.37, 0.04), part)
		_box(st, Vector3(0.167, 0.55, 0.03), Vector3(x, 0.63, -0.2), part, Basis(Vector3.RIGHT, -0.35))
	return _commit(st)


## Reposera: larga, con el respaldo levantado.
static func _lounger() -> ArrayMesh:
	var st := _begin()
	for z in [0.75, -0.35]:
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.04, 0.28, 0.04), Vector3(side * 0.28, 0.14, z), FIXED, Basis(), 0, Vector3.ZERO, 1.0, FRAME)
	for k in 4:
		var part := OWN if k % 2 == 0 else WHITE
		var x := (k - 1.5) * 0.15
		_box(st, Vector3(0.15, 0.05, 1.25), Vector3(x, 0.3, 0.3), part)
		_box(st, Vector3(0.15, 0.05, 0.7), Vector3(x, 0.52, -0.55), part, Basis(Vector3.RIGHT, 0.65))
	return _commit(st)


## Sombrilla: palo blanco y gajos a rayas.
static func _umbrella() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(0.05, 2.4, 0.05), Vector3(0.0, 1.2, 0.0), FIXED, Basis(), 0, Vector3.ZERO, 1.0, POLE)
	var apex := Vector3(0.0, 2.5, 0.0)
	var segs := 10
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var r0 := Vector3(cos(a0) * 1.3, 2.08, sin(a0) * 1.3)
		var r1 := Vector3(cos(a1) * 1.3, 2.08, sin(a1) * 1.3)
		var part := OWN if i % 2 == 0 else WHITE
		var n := (r1 - apex).cross(r0 - apex).normalized()
		for v in [apex, r0, r1]:
			_vertex(st, v * _k, n, part, Color.WHITE)
	return _commit(st)


## Toalla tirada en la arena: rayas del color propio y blancas, y un borde
## del segundo color.
static func _towel() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(0.84, 0.015, 1.64), Vector3(0.0, 0.008, 0.0), ACCENT)
	for k in 5:
		var part := OWN if k % 2 == 0 else WHITE
		_box(st, Vector3(0.76, 0.02, 0.31), Vector3(0.0, 0.012, (k - 2) * 0.31), part)
	return _commit(st)


## Bandera en un palo (flamea en el shader).
static func _flag() -> ArrayMesh:
	var st := _begin()
	_box(st, Vector3(0.05, 3.3, 0.05), Vector3(0.0, 1.65, 0.0), FIXED, Basis(), 0, Vector3.ZERO, 1.0, POLE)
	var top := Vector3(0.0, 3.25, 0.0)
	var low := Vector3(0.0, 2.6, 0.0)
	var tip := Vector3(1.0, 2.92, 0.0)
	for v in [top, tip, low]:
		st.set_uv(Vector2(3.0, (v as Vector3).x))
		st.set_uv2(Vector2(OWN, 0.0))
		st.set_normal(Vector3.BACK)
		st.add_vertex(v * _k)
	return _commit(st)


# ---------------------------------------------------------------- piezas

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


## move: qué se mueve (ver crowd_motion.gdshaderinc). Con `length` 0 se
## mueve entero (una mano); si no, más cuanto más lejos de `origin`.
static func _vertex(st: SurfaceTool, v: Vector3, n: Vector3, part: float, color: Color,
		move: int = 0, origin: Vector3 = Vector3.ZERO, length: float = 0.0) -> void:
	st.set_uv2(Vector2(part, float(maxi(FIXED_COLORS.find(color), 0))))
	var amount := 0.0
	if move > 0:
		amount = 1.0 if length <= 0.0 else clampf(v.distance_to(origin) / length, 0.0, 1.0)
	st.set_uv(Vector2(float(move), amount))
	st.set_normal(n)
	st.add_vertex(v)


## Agrega una malla primitiva movida a `pos` (y girada con `basis`).
static func _prim(st: SurfaceTool, mesh: PrimitiveMesh, pos: Vector3, part: float, basis: Basis, scale: Vector3,
		move: int, origin: Vector3, length: float, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * _k)) * Transform3D(basis * Basis.from_scale(scale), pos)
	for k in idx:
		_vertex(st, xf * verts[k], (basis * normals[k] / scale).normalized(), part, color, move, origin, length)


static func _box(st: SurfaceTool, size: Vector3, pos: Vector3, part: float, basis: Basis = Basis(),
		move: int = 0, origin: Vector3 = Vector3.ZERO, length: float = 1.0, color: Color = Color.WHITE) -> void:
	var m := BoxMesh.new()
	m.size = size
	_prim(st, m, pos, part, basis, Vector3.ONE, move, origin, length, color)


## Elipsoide de radios `radii` (cabeza, pecho, manos...).
## `detail` 0: lo mínimo (ojos, boca), 1: lo normal (pocas caras: se ven
## chicos y son muchos), 2: más redondo (la cabeza, que es lo que más se ve).
static func _ellipsoid(st: SurfaceTool, radii: Vector3, pos: Vector3, part: float, color: Color = Color.WHITE,
		move: int = 0, detail: int = 1) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = [4, 7, 10][detail]
	m.rings = [2, 3, 5][detail]
	_prim(st, m, pos, part, Basis(), radii, move, Vector3.ZERO, 0.0, color)


static func _cylinder(st: SurfaceTool, top: float, bottom: float, height: float, pos: Vector3, part: float,
		color: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	_prim(st, m, pos, part, Basis(), Vector3.ONE, 0, Vector3.ZERO, 1.0, color)
