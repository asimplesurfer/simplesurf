class_name AvatarFeatures
extends RefCounted
## Arma los detalles del personaje (cara, pelo, orejas, collar, estampado del
## short) con piezas simples: elipsoides, conos y cajas de color plano con
## contorno negro, igual que el cuerpo.
##
## Cada grupo sigue a una pieza del cuerpo (cabeza, pecho o cadera), así las
## animaciones los mueven juntos. Las piezas de un grupo se juntan en una sola
## malla con colores por vértice (una con contorno y otra sin): así cada
## personaje agrega pocas llamadas de dibujo aunque tenga 60 detalles. Las medidas de la cabeza se dan en "unidades
## de cabeza": (1, 1, 1) es el borde de la esfera; +Z es la cara.

## Grosor del contorno de los detalles (más fino que el del cuerpo).
const OUTLINE := 0.02
## Distancia a la cámara (m) desde la que no se dibujan los detalles.
const FAR_HIDE := 28.0
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
const BLACK := Color(0.05, 0.05, 0.06)
const WHITE := Color(0.98, 0.98, 0.96)

var _sphere: SphereMesh
var _cone: CylinderMesh
var _box: BoxMesh
var _materials: Dictionary = {}
## Vértices de cada malla base (se transforman y se copian a la malla del grupo).
var _source: Dictionary = {}
## Malla en armado: outline (bool) -> {verts, normals, colors, indices}.
var _batch: Dictionary = {}
var _count: int = 0

## Cabeza actual: radios y factor de tamaño (1 = cabeza normal).
var _r: Vector3
var _hs: float
var _group: Node3D


func _init() -> void:
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	# Pocos lados: son piezas chicas y se ven igual de redondas.
	_sphere.radial_segments = 10
	_sphere.rings = 5
	_cone = CylinderMesh.new()
	_cone.top_radius = 0.0
	_cone.bottom_radius = 1.0
	_cone.height = 2.0
	_cone.radial_segments = 8
	_box = BoxMesh.new()
	_box.size = Vector3(2.0, 2.0, 2.0)


## Forma del cráneo del modelo (mitad del ancho y frente de la cara, en z, a
## cada altura y): de y = 0.5 (arriba) a y = -0.5 (mentón).
const SKULL_PROFILE := [
	[0.5, 0.167, 0.142], [0.4, 0.351, 0.299], [0.3, 0.437, 0.372], [0.2, 0.498, 0.425],
	[0.1, 0.506, 0.446], [0.0, 0.479, 0.445], [-0.1, 0.44, 0.431], [-0.2, 0.363, 0.393],
	[-0.3, 0.276, 0.339], [-0.4, 0.191, 0.276], [-0.5, 0.074, 0.159],
]


## Cabeza: ojos, anteojos, nariz, boca, cara, orejas y pelo, apoyados sobre el
## cráneo del modelo (el grupo es hijo de la cabeza). Las opciones que vienen
## del modelo (melena, anteojos de sol, sonrisa de costado) no se arman acá.
func build_head(group: Node3D, data: CharacterData, skin: Color) -> void:
	_begin(group)
	# Parte de arriba del cráneo como un elipsoide (para pelos y orejas).
	_r = Vector3(0.51, 0.53, 0.45)
	_hs = 1.0
	var hair := data.hair_color()
	_ears(data.get_option("ears"), skin)
	_hair(data.get_option("hair"), hair)
	_eyes(data.get_option("eyes"))
	_extra(data.get_option("extra"), hair)
	_nose(data.get_option("nose"), skin)
	_mouth(data.get_option("mouth"))
	_glasses(data.get_option("glasses"))
	_commit()


## Pecho: collar (las perlas son del modelo).
func build_chest(group: Node3D, data: CharacterData, radii: Vector3) -> void:
	_begin(group)
	match data.get_option("neck"):
		2:
			_necklace(radii, 12, 0.085, [Color("#ff6fb5"), Color("#ffd23f"), Color("#ff5a4e"), WHITE])
		3:
			_necklace(radii, 15, 0.035, [Color("#f2c230")])
			var d := Vector3(0.0, 0.3, 1.0).normalized()
			_disc(_on_ellipsoid(radii, d, 0.05), _normal(radii, d), 0.1, Color("#f2c230"))
	_commit()


## Cadera: estampado del short (las flores son del modelo).
func build_hips(group: Node3D, data: CharacterData, radii: Vector3) -> void:
	_begin(group)
	_hips_pattern(data.get_option("shorts_pattern"), radii)
	_commit()


func _hips_pattern(pattern: int, radii: Vector3) -> void:
	if pattern == 3:
		for y in [-0.09, 0.07]:
			_piece(_sphere, Vector3(0.0, y, 0.0), Vector3(radii.x * 1.02, 0.035, radii.z * 1.02), WHITE)
		return
	if pattern != 2 and pattern != 4:
		return
	var spots: Array = []
	for i in 14:
		# Puntos repartidos alrededor de la cadera (adelante, costados, atrás).
		var a := i * 2.399
		var y := -0.45 + fmod(i * 0.37, 0.8)
		spots.append(Vector3(sin(a), y, cos(a)).normalized())
	var n: int = 14 if pattern == 2 else 9
	var palette := [Color("#ff5a4e"), Color("#ffd23f"), WHITE, Color("#ff8fd0")]
	for i in n:
		var d: Vector3 = spots[i]
		var nrm := _normal(radii, d)
		if pattern == 2:
			_disc(_on_ellipsoid(radii, d, 0.004), nrm, 0.04, WHITE)
		else:
			_disc(_on_ellipsoid(radii, d, 0.004), nrm, 0.11, palette[i % palette.size()])
			_disc(_on_ellipsoid(radii, d, 0.018), nrm, 0.035, Color("#ffd23f"), false)


# ---------------------------------------------------------------- cabeza

## Punto en "unidades de cabeza" sobre el elipsoide de arriba del cráneo.
func _h(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * _r.x, y * _r.y, z * _r.z)


## Punto sobre la cara (frente del cráneo) a la altura y y al costado x, un
## poco afuera (`out`).
func _face(x: float, y: float, out: float = 0.0) -> Vector3:
	var hw := 0.0
	var fz := 0.0
	for i in SKULL_PROFILE.size() - 1:
		var a: Array = SKULL_PROFILE[i]
		var b: Array = SKULL_PROFILE[i + 1]
		if y <= a[0] and y >= b[0]:
			var t: float = (a[0] - y) / (a[0] - b[0])
			hw = lerpf(a[1], b[1], t)
			fz = lerpf(a[2], b[2], t)
			break
	var k := clampf(x / maxf(hw, 0.01), -0.98, 0.98)
	var z := fz * sqrt(1.0 - k * k)
	var normal := Vector3(x / maxf(hw * hw, 0.0001), 0.0, z / maxf(fz * fz, 0.0001)).normalized()
	return Vector3(x, y, z) + normal * out


func _eye_pos(side: float) -> Vector3:
	return _face(side * 0.2, 0.1)


func _eyes(style: int) -> void:
	for side in [-1.0, 1.0]:
		var p := _eye_pos(side)
		match style:
			0:
				_piece(_sphere, p, Vector3.ONE * 0.065, BLACK, false)
			1, 2:
				var big := 0.13 if style == 1 else 0.11
				_piece(_sphere, p + Vector3(0, 0, 0.03), Vector3.ONE * big, WHITE)
				var look := 0.0
				if style == 2:
					look = -side * 0.045
				_piece(_sphere, p + Vector3(look, 0.0, 0.03 + big - 0.02), Vector3(0.05, 0.05, 0.03), BLACK,
					false)
			3:
				_piece(_sphere, p + Vector3(0, -0.01, 0.01), Vector3(0.085, 0.017, 0.03), BLACK, false,
					Basis(Vector3.FORWARD, side * 0.15))
			4:
				if side < 0.0:
					_piece(_sphere, p + Vector3(0, 0.02, 0.04), Vector3.ONE * 0.16, WHITE)
					_piece(_sphere, p + Vector3(0.02, 0.02, 0.18), Vector3(0.055, 0.055, 0.03), BLACK, false)
				else:
					_piece(_sphere, p, Vector3.ONE * 0.05, BLACK, false)


## Anteojos armados (los de sol son del modelo).
func _glasses(style: int) -> void:
	var front := Vector3(0, 0, 0.06)
	match style:
		2:
			_piece(_sphere, Vector3(0.0, 0.1, -0.02), Vector3(0.53, 0.07, 0.48), Color("#23305e"), false)
			for side in [-1.0, 1.0]:
				_piece(_sphere, _eye_pos(side) + front, Vector3(0.16, 0.14, 0.06), Color("#9fe8ff"))
		3:
			for side in [-1.0, 1.0]:
				_piece(_sphere, _eye_pos(side) + front * 0.8, Vector3(0.13, 0.13, 0.025), Color(0.85, 0.95, 1.0))
			_piece(_sphere, _face(0.0, 0.13, 0.04), Vector3(0.08, 0.017, 0.02), BLACK, false)
		4:
			_piece(_sphere, _eye_pos(1.0) + front * 0.8, Vector3(0.13, 0.13, 0.025), Color(0.85, 0.95, 1.0))
			_piece(_sphere, _eye_pos(1.0) + Vector3(0.06, -0.28, 0.07), Vector3(0.011, 0.2, 0.011),
				Color("#f2c230"), false, Basis(Vector3.FORWARD, 0.25))


func _nose(style: int, skin: Color) -> void:
	var p := _face(0.0, -0.05)
	match style:
		1:
			_piece(_sphere, p, Vector3.ONE * 0.06, skin.darkened(0.08))
		2:
			_piece(_sphere, p + Vector3(0, -0.02, 0.05), Vector3(0.12, 0.11, 0.14), skin.darkened(0.06))
		3:
			_piece(_sphere, p + Vector3(0, 0, 0.05), Vector3.ONE * 0.1, Color("#e8302a"))
		4:
			_piece(_sphere, p + Vector3(0, 0, 0.22), Vector3(0.05, 0.05, 0.26), skin.darkened(0.06))


## Bocas armadas (la de costado es la del modelo).
func _mouth(style: int) -> void:
	var m := _face(0.0, -0.21, 0.005)
	match style:
		1:
			_curve(m, [-0.11, -0.055, 0.0, 0.055, 0.11], 0.045)
		3:
			_piece(_sphere, m + Vector3(0, -0.01, 0.0), Vector3(0.11, 0.09, 0.04), Color("#5a1620"))
			_piece(_sphere, m + Vector3(0, -0.05, 0.02), Vector3(0.065, 0.032, 0.03), Color("#ff7b8a"), false)
		4:
			_piece(_sphere, m, Vector3(0.11, 0.012, 0.02), BLACK, false)
			for side in [-1.0, 1.0]:
				_piece(_box, m + Vector3(side * 0.031, -0.045, 0.0), Vector3(0.028, 0.042, 0.012), WHITE)
		5:
			for i in 4:
				var x := -0.11 + i * 0.073
				_piece(_sphere, m + Vector3(x, 0, 0), Vector3(0.046, 0.011, 0.02), BLACK, false,
					Basis(Vector3.FORWARD, 0.5 if i % 2 == 0 else -0.5))


## Línea curva de la boca: segmentos negros en arco (`bend` = cuánto se curva,
## `tilt` = cuánto sube hacia la derecha).
func _curve(center: Vector3, xs: Array, bend: float, tilt: float = 0.0) -> void:
	for i in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var y0 := bend * pow(x0 / 0.11, 2.0) + tilt * x0 * 0.3
		var y1 := bend * pow(x1 / 0.11, 2.0) + tilt * x1 * 0.3
		var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
		var ang := atan2(y1 - y0, x1 - x0)
		var seg := Vector2(x1 - x0, y1 - y0).length() * 0.6
		_piece(_sphere, center + mid, Vector3(seg, 0.013, 0.02), BLACK, false, Basis(Vector3.BACK, ang))


func _extra(style: int, hair: Color) -> void:
	match style:
		1:
			for side in [-1.0, 1.0]:
				_piece(_sphere, _face(side * 0.07, -0.13, 0.015), Vector3(0.1, 0.04, 0.045), hair, true,
					Basis(Vector3.BACK, side * 0.3))
		2:
			_piece(_sphere, Vector3(0.0, -0.36, 0.12), Vector3(0.27, 0.2, 0.26), hair)
		3:
			_piece(_sphere, _face(0.0, 0.25, 0.01), Vector3(0.27, 0.04, 0.05), hair)
		4:
			for side in [-1.0, 1.0]:
				_piece(_sphere, _face(side * 0.2, 0.25, 0.01), Vector3(0.15, 0.045, 0.05), hair, true,
					Basis(Vector3.BACK, side * 0.28))


func _ears(style: int, skin: Color) -> void:
	if style == 0:
		return
	var sizes := [Vector3.ZERO, Vector3(0.065, 0.12, 0.09), Vector3(0.065, 0.19, 0.15), Vector3(0.05, 0.3, 0.28)]
	for side in [-1.0, 1.0]:
		var s: Vector3 = sizes[style]
		var p := Vector3(side * (0.47 + s.x * 0.6), 0.05, -0.02)
		var rot := Basis.IDENTITY
		if style == 3:
			p.x += side * 0.11
			rot = Basis(Vector3.UP, side * 0.5)
		_piece(_sphere, p, s, skin, true, rot)


## Pelos armados (la melena es la del modelo).
func _hair(style: int, hair: Color) -> void:
	match style:
		1:
			_cap(hair)
		3:
			for d in _cap_dirs(22, 0.25):
				_piece(_sphere, _h(d.x * 1.05, d.y * 1.05, d.z * 1.05), Vector3.ONE * 0.19, hair)
		4:
			for i in 5:
				var phi := deg_to_rad(55.0 - i * 30.0)
				var d := Vector3(0.0, cos(phi), sin(phi))
				var p := _h(d.x, d.y, d.z) + d * 0.1
				_piece(_sphere, p, Vector3(0.06, 0.21, 0.12), hair, true, _align_y(d))
		5:
			_cap(hair)
			for d in _cap_dirs(9, 0.45):
				var p := _h(d.x, d.y, d.z) + d * 0.12
				_piece(_cone, p, Vector3(0.085, 0.15, 0.085), hair, true, _align_y(d))
		6:
			_cap(hair)
			_piece(_sphere, Vector3(0.0, 0.62, -0.16), Vector3.ONE * 0.19, hair)
		7:
			_piece(_sphere, Vector3(0.06, 0.5, 0.02), Vector3(0.32, 0.07, 0.27), hair, true,
				Basis(Vector3.BACK, -0.18))


## Pelo corto pegado a la cabeza (deja la cara a la vista).
func _cap(hair: Color) -> void:
	_piece(_sphere, Vector3(0.0, 0.2, -0.07), Vector3(0.54, 0.38, 0.5), hair)


## Direcciones repartidas sobre la parte de arriba de la cabeza (y > min_y).
func _cap_dirs(n: int, min_y: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var i := 0
	while out.size() < n and i < n * 6:
		var y := 1.0 - (i + 0.5) / float(n * 2)
		var rad := sqrt(maxf(0.0, 1.0 - y * y))
		var a := i * 2.39996
		var d := Vector3(cos(a) * rad, y, sin(a) * rad)
		i += 1
		# Que no tape la cara.
		if d.y > min_y and not (d.z > 0.55 and d.y < 0.6):
			out.append(d)
	return out


## Base cuyo eje Y apunta hacia `d`.
func _align_y(d: Vector3) -> Basis:
	d = d.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length() < 0.001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), Vector3.UP.angle_to(d))


# ---------------------------------------------------------------- cuerpo

func _necklace(radii: Vector3, count: int, size: float, colors: Array) -> void:
	for i in count:
		var a := lerpf(-1.3, 1.3, i / float(count - 1))
		var d := Vector3(sin(a) * 0.95, 0.62 - 0.62 * cos(a), cos(a) * 0.7).normalized()
		_piece(_sphere, _on_ellipsoid(radii, d, size * 0.6), Vector3.ONE * size, colors[i % colors.size()])


## Punto sobre la superficie de un elipsoide (radios `radii`) en la dirección d,
## un poco afuera (`out`).
func _on_ellipsoid(radii: Vector3, d: Vector3, out: float) -> Vector3:
	var k := 1.0 / sqrt(pow(d.x / radii.x, 2.0) + pow(d.y / radii.y, 2.0) + pow(d.z / radii.z, 2.0))
	return d * k + _normal(radii, d) * out


func _normal(radii: Vector3, d: Vector3) -> Vector3:
	return Vector3(d.x / (radii.x * radii.x), d.y / (radii.y * radii.y), d.z / (radii.z * radii.z)).normalized()


## Disco chato apoyado en una superficie (su cara mira hacia `normal`).
func _disc(pos: Vector3, normal: Vector3, radius: float, color: Color, outline: bool = true) -> void:
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(-normal, up)
	_piece(_sphere, pos, Vector3(radius, radius, radius * 0.18), color, outline, basis)


# ---------------------------------------------------------------- piezas

func _piece(
	mesh: Mesh, pos: Vector3, size: Vector3, color: Color, outline: bool = true,
	rot: Basis = Basis.IDENTITY
) -> void:
	var xf := Transform3D(rot * Basis.from_scale(size), pos)
	var nb := xf.basis.inverse().transposed()
	var src: Dictionary = _source_for(mesh)
	var b: Dictionary = _batch[outline]
	var verts: PackedVector3Array = b.verts
	var base := verts.size()
	for v in (src.verts as PackedVector3Array):
		b.verts.append(xf * v)
	for n in (src.normals as PackedVector3Array):
		b.normals.append((nb * n).normalized())
		b.colors.append(color)
	for i in (src.indices as PackedInt32Array):
		b.indices.append(base + i)
	_count += 1


func _source_for(mesh: Mesh) -> Dictionary:
	if not _source.has(mesh):
		var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
		_source[mesh] = {
			"verts": arrays[Mesh.ARRAY_VERTEX],
			"normals": arrays[Mesh.ARRAY_NORMAL],
			"indices": arrays[Mesh.ARRAY_INDEX],
		}
	return _source[mesh]


func _begin(group: Node3D) -> void:
	_group = group
	_count = 0
	for outline in [true, false]:
		_batch[outline] = {
			"verts": PackedVector3Array(), "normals": PackedVector3Array(),
			"colors": PackedColorArray(), "indices": PackedInt32Array(),
		}


## Arma las mallas del grupo (una con contorno y otra sin).
func _commit() -> void:
	_group.set_meta("pieces", _count)
	for outline in [true, false]:
		var b: Dictionary = _batch[outline]
		if (b.verts as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.normals
		arrays[Mesh.ARRAY_COLOR] = b.colors
		arrays[Mesh.ARRAY_INDEX] = b.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Outlined" if outline else "Plain"
		mi.mesh = mesh
		mi.material_override = _material(outline)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# De lejos los detalles no se distinguen: no se dibujan.
		mi.visibility_range_end = FAR_HIDE
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		_group.add_child(mi)


func _material(outline: bool) -> StandardMaterial3D:
	if _materials.has(outline):
		return _materials[outline]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if outline:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter("outline_width", OUTLINE)
		m.next_pass = o
	_materials[outline] = m
	return m
