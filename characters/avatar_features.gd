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
## Distancia a la cámara (m) desde la que no se dibujan los detalles.
const FAR_HIDE := 28.0
const BLACK := Color(0.05, 0.05, 0.06)
const WHITE := Color(0.98, 0.98, 0.96)

var _sphere: SphereMesh
var _cone: CylinderMesh
var _box: BoxMesh
var _cyl: CylinderMesh
## Aros de anteojos (fino y grueso).
var _ring: TorusMesh
var _ring_thick: TorusMesh
var _materials: Dictionary = {}
## Raíz del personaje (la pone SurferKit): el contorno se mide ahí, así tiene
## el mismo grosor que el del cuerpo aunque la cabeza esté agrandada.
var char_root: Node3D
var _outline_mat: StandardMaterial3D
## Vértices de cada malla base (se transforman y se copian a la malla del grupo).
var _source: Dictionary = {}
## Malla en armado: outline (bool) -> {verts, normals, colors, indices}.
var _batch: Dictionary = {}
var _count: int = 0

## Cabeza actual: radios y factor de tamaño (1 = cabeza normal).
var _r: Vector3
var _hs: float
var _group: Node3D
## Transformación extra para las piezas (agrandar el sombrero sobre pelos grandes).
var _extra_xf := Transform3D.IDENTITY
## Pelos voluminosos: el sombrero va más grande y más arriba (si no, lo tapan).
const BIG_HAIR := [2, 3, 4, 5, 12, 13]


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
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 1.0
	_cyl.bottom_radius = 1.0
	_cyl.height = 2.0
	_cyl.radial_segments = 16
	_cyl.rings = 1
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.82
	_ring.outer_radius = 1.0
	_ring.rings = 20
	_ring.ring_segments = 6
	_ring_thick = TorusMesh.new()
	_ring_thick.inner_radius = 0.7
	_ring_thick.outer_radius = 1.0
	_ring_thick.rings = 20
	_ring_thick.ring_segments = 6


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
## El pelo va en su propio grupo (`hair_group`), así se puede mover solo.
func build_head(group: Node3D, hair_group: Node3D, data: CharacterData, skin: Color) -> void:
	# Parte de arriba del cráneo como un elipsoide (para pelos y orejas).
	_r = Vector3(0.51, 0.53, 0.45)
	_hs = 1.0
	var hair := data.hair_color()
	_begin(hair_group)
	_hair(data.get_option("hair"), hair)
	_commit()
	_begin(group)
	_ears(data.get_option("ears"), skin)
	_eyes(data.get_option("eyes"), data.get_option("glasses"))
	_extra(data.get_option("extra"), hair)
	_nose(data.get_option("nose"), skin)
	_mouth(data.get_option("mouth"))
	_glasses(data.get_option("glasses"))
	if data.get_option("hair") in BIG_HAIR:
		# Agrandado desde la frente (así no se corre hacia atrás) y un poco arriba.
		var pivot := Vector3(0.0, 0.3, 0.0)
		_extra_xf = Transform3D(Basis.from_scale(Vector3.ONE * 1.15), pivot + Vector3(0.0, 0.07, 0.0)) \
			* Transform3D(Basis.IDENTITY, -pivot)
	_hat(data.get_option("hat"))
	_extra_xf = Transform3D.IDENTITY
	_commit()


## Pecho: collar (las perlas son del modelo).
func build_chest(group: Node3D, data: CharacterData, radii: Vector3) -> void:
	_begin(group)
	_top(data.get_option("top"), data.shorts_color(), radii)
	match data.get_option("neck"):
		2:
			_necklace(radii, 12, 0.085, [Color("#ff6fb5"), Color("#ffd23f"), Color("#ff5a4e"), WHITE])
		3:
			_necklace(radii, 15, 0.035, [Color("#f2c230")])
			var d := Vector3(0.0, 0.3, 1.0).normalized()
			_disc(_on_ellipsoid(radii, d, 0.05), _normal(radii, d), 0.1, Color("#f2c230"))
		4:
			# Dientes de tiburón en un cordón.
			_necklace(radii, 15, 0.025, [Color("#5a3a22")])
			for i in 5:
				var a := lerpf(-0.6, 0.6, i / 4.0)
				var dd := Vector3(sin(a) * 0.95, 0.62 - 0.62 * cos(a), cos(a) * 0.7).normalized()
				var pos := _on_ellipsoid(radii, dd, 0.05) + Vector3(0, -0.05, 0)
				_piece(_cone, pos, Vector3(0.035, 0.05, 0.02), WHITE, true, Basis(Vector3.RIGHT, PI))
		5:
			# Silbato de guardavidas.
			_necklace(radii, 15, 0.022, [Color("#e8302a")])
			var dd := Vector3(0.0, 0.25, 1.0).normalized()
			var pos := _on_ellipsoid(radii, dd, 0.07)
			_piece(_box, pos, Vector3(0.07, 0.04, 0.035), Color("#ff9b1f"))
			_piece(_cyl, pos + Vector3(0.08, 0.0, 0.0), Vector3(0.025, 0.035, 0.025), Color("#ff9b1f"), true,
				Basis(Vector3.BACK, PI / 2.0))
		6:
			# Caracol de mar.
			_necklace(radii, 15, 0.022, [Color("#5a3a22")])
			var dd := Vector3(0.0, 0.25, 1.0).normalized()
			var pos := _on_ellipsoid(radii, dd, 0.06)
			_piece(_sphere, pos, Vector3(0.09, 0.08, 0.04), Color("#ffb7a8"))
			for k in 3:
				_piece(_sphere, pos + Vector3((k - 1) * 0.03, 0.0, 0.035), Vector3(0.008, 0.06, 0.008),
					Color("#d9776a"), false, Basis(Vector3.BACK, (k - 1) * 0.35))
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


## Ojos. Con anteojos de sol no se ven (no se dibujan); con lentes, antiparras
## o monóculo se achican para quedar detrás del vidrio (que no lo atraviesen).
func _eyes(style: int, glasses: int = 0) -> void:
	# Detrás de los anteojos oscuros no se ven.
	if glasses in OPAQUE_GLASSES:
		return
	var k := 1.0 if glasses == 0 or glasses == 9 else 0.68
	for side in [-1.0, 1.0]:
		var p := _eye_pos(side)
		match style:
			0:
				_piece(_sphere, p, Vector3.ONE * 0.065 * maxf(k, 0.8), BLACK, false)
			1, 2:
				var big := (0.13 if style == 1 else 0.11) * k
				var bulge := 0.03 * k
				_piece(_sphere, p + Vector3(0, 0, bulge), Vector3.ONE * big, WHITE)
				var look := 0.0
				if style == 2:
					look = -side * 0.045 * k
				_piece(_sphere, p + Vector3(look, 0.0, bulge + big - 0.02 * k), Vector3(0.05, 0.05, 0.03) * k,
					BLACK, false)
			3:
				_piece(_sphere, p + Vector3(0, -0.01, 0.01), Vector3(0.085, 0.017, 0.03), BLACK, false,
					Basis(Vector3.FORWARD, side * 0.15))
			4:
				if side < 0.0:
					_piece(_sphere, p + Vector3(0, 0.02, 0.04 * k), Vector3.ONE * 0.16 * k, WHITE)
					_piece(_sphere, p + Vector3(0.02, 0.02, 0.18 * k), Vector3(0.055, 0.055, 0.03) * k, BLACK,
						false)
				else:
					_piece(_sphere, p, Vector3.ONE * 0.05, BLACK, false)
			5:
				# Con pestañas: ojo ovalado y tres pestañas hacia afuera.
				_piece(_sphere, p, Vector3(0.06, 0.075, 0.03) * maxf(k, 0.8), BLACK, false)
				for j in 3:
					var a: float = side * (0.35 + j * 0.35)
					var tip := p + Vector3(side * (0.035 + j * 0.03), 0.085 - j * 0.02, 0.012)
					_piece(_sphere, tip, Vector3(0.013, 0.05, 0.012), BLACK, false, Basis(Vector3.BACK, -a))
			6:
				# Brillosos: grandes y negros con un brillo blanco.
				_piece(_sphere, p, Vector3(0.085, 0.11, 0.04) * maxf(k, 0.8), BLACK, false)
				_piece(_sphere, p + Vector3(-0.025, 0.035, 0.035), Vector3.ONE * 0.025, WHITE, false)
				_piece(_sphere, p + Vector3(0.025, -0.03, 0.035), Vector3.ONE * 0.012, WHITE, false)
			7:
				# Felices: dos rayitas en forma de ^.
				for s2 in [-1.0, 1.0]:
					_piece(_sphere, p + Vector3(s2 * 0.03, 0.0, 0.01), Vector3(0.04, 0.012, 0.02), BLACK, false,
						Basis(Vector3.BACK, s2 * -0.6))
			8:
				# Guiño: un ojo abierto y el otro cerrado.
				if side < 0.0:
					_piece(_sphere, p, Vector3.ONE * 0.065, BLACK, false)
				else:
					_piece(_sphere, p + Vector3(0, -0.01, 0.01), Vector3(0.07, 0.014, 0.02), BLACK, false,
						Basis(Vector3.BACK, 0.25))
			9:
				# Enojados: punto y ceja en diagonal hacia el centro.
				_piece(_sphere, p, Vector3.ONE * 0.06, BLACK, false)
				_piece(_sphere, p + Vector3(0.0, 0.09, 0.01), Vector3(0.08, 0.02, 0.02), BLACK, false,
					Basis(Vector3.BACK, side * 0.45))


## Anteojos armados (los de sol son del modelo): aros, con el ojo a la vista adentro.
func _glasses(style: int) -> void:
	var front := Vector3(0, 0, 0.05)
	var facing := Basis(Vector3.RIGHT, PI / 2.0)
	match style:
		2:
			_piece(_sphere, Vector3(0.0, 0.1, -0.02), Vector3(0.53, 0.07, 0.48), Color("#23305e"), false)
			for side in [-1.0, 1.0]:
				_piece(_ring_thick, _eye_pos(side) + front, Vector3(0.15, 0.15, 0.15), Color("#2c7fd6"), true,
					facing)
		3:
			for side in [-1.0, 1.0]:
				_piece(_ring, _eye_pos(side) + front, Vector3(0.13, 0.13, 0.13), BLACK, false, facing)
			_piece(_sphere, _face(0.0, 0.12, 0.05), Vector3(0.07, 0.015, 0.015), BLACK, false)
		4:
			_piece(_ring, _eye_pos(1.0) + front, Vector3(0.13, 0.13, 0.13), Color("#d9a520"), false, facing)
			_piece(_sphere, _eye_pos(1.0) + Vector3(0.06, -0.28, 0.07), Vector3(0.011, 0.2, 0.011),
				Color("#f2c230"), false, Basis(Vector3.FORWARD, 0.25))
		5:
			# Aviador: gotas oscuras con marco dorado.
			for side in [-1.0, 1.0]:
				_piece(_sphere, _eye_pos(side) + Vector3(0, -0.015, 0.05), Vector3(0.14, 0.115, 0.035),
					Color("#20303e"), true, Basis(Vector3.BACK, side * 0.12))
				_piece(_sphere, _eye_pos(side) + Vector3(-0.04, 0.03, 0.09), Vector3(0.04, 0.012, 0.01),
					Color("#7fb6d8"), false, Basis(Vector3.BACK, 0.4))
			_piece(_sphere, _face(0.0, 0.17, 0.06), Vector3(0.36, 0.012, 0.012), Color("#d9a520"), false)
		6:
			# Corazones rosas.
			for side in [-1.0, 1.0]:
				var c := _eye_pos(side) + Vector3(0, 0, 0.05)
				for s2 in [-1.0, 1.0]:
					_piece(_sphere, c + Vector3(s2 * 0.045, 0.025, 0.0), Vector3(0.065, 0.065, 0.03), Color("#ff4f8b"))
				_piece(_cone, c + Vector3(0, -0.05, 0.0), Vector3(0.1, 0.06, 0.03), Color("#ff4f8b"), true,
					Basis(Vector3.RIGHT, PI))
			_piece(_sphere, _face(0.0, 0.12, 0.06), Vector3(0.06, 0.012, 0.012), BLACK, false)
		7:
			# Estrellas amarillas.
			for side in [-1.0, 1.0]:
				var c := _eye_pos(side) + Vector3(0, 0, 0.05)
				_piece(_sphere, c, Vector3(0.07, 0.07, 0.03), Color("#ffd23f"))
				for j in 5:
					var a := j * TAU / 5.0
					_piece(_cone, c + Vector3(sin(a), cos(a), 0.0) * 0.085, Vector3(0.045, 0.06, 0.02),
						Color("#ffd23f"), true, Basis(Vector3.BACK, -a))
			_piece(_sphere, _face(0.0, 0.12, 0.06), Vector3(0.06, 0.012, 0.012), BLACK, false)
		8:
			# Visera futurista: una sola franja de lado a lado.
			_piece(_sphere, _face(0.0, 0.1, 0.07), Vector3(0.5, 0.085, 0.07), Color("#7a3cff"))
			_piece(_sphere, _face(-0.1, 0.13, 0.13), Vector3(0.18, 0.012, 0.01), Color("#d9c8ff"), false)
		9:
			# Parche pirata en el ojo derecho, con la tira cruzando la cabeza.
			var c := _eye_pos(1.0) + Vector3(0, 0, 0.04)
			_piece(_sphere, c, Vector3(0.12, 0.1, 0.035), BLACK)
			_piece(_sphere, Vector3(0.0, 0.22, 0.05), Vector3(0.52, 0.018, 0.47), BLACK, false,
				Basis(Vector3.BACK, -0.35))
		10:
			# Snorkel: antiparras de buceo y el tubo al costado.
			_piece(_sphere, _face(0.0, 0.1, 0.06), Vector3(0.38, 0.17, 0.05), Color("#2fbfb0"))
			_piece(_sphere, _face(0.0, 0.1, 0.1), Vector3(0.32, 0.12, 0.02), Color(0.75, 0.95, 1.0, 1.0), false)
			_piece(_sphere, Vector3(0.0, 0.1, 0.0), Vector3(0.5, 0.035, 0.47), Color("#2fbfb0"), false)
			_piece(_cyl, Vector3(0.46, 0.2, 0.02), Vector3(0.035, 0.3, 0.035), Color("#ff7a2f"))
			_piece(_cyl, Vector3(0.36, -0.15, 0.32), Vector3(0.03, 0.13, 0.03), Color("#ff7a2f"), true,
				Basis(Vector3.BACK, 0.9))


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
		2:
			# Sonrisa de costado del surfista original: sube hacia la derecha, con
			# un rulito en la punta.
			var sm := _face(0.03, -0.206, 0.005)
			_curve(sm, [-0.1, -0.05, 0.0, 0.05, 0.1], 0.025, 0.55)
			_piece(_sphere, _face(0.14, -0.18, 0.006), Vector3(0.03, 0.012, 0.02), BLACK, false,
				Basis(Vector3.BACK, 1.1))
		6:
			# Labios pintados.
			_piece(_sphere, m + Vector3(0, 0.012, 0.0), Vector3(0.09, 0.025, 0.03), Color("#d8344c"))
			_piece(_sphere, m + Vector3(0, -0.02, 0.0), Vector3(0.08, 0.03, 0.03), Color("#d8344c"))
		7:
			# Sonrisa con la lengua afuera.
			_curve(m, [-0.1, -0.05, 0.0, 0.05, 0.1], 0.035)
			_piece(_sphere, m + Vector3(0.02, -0.04, 0.02), Vector3(0.045, 0.05, 0.025), Color("#ff6f86"))
		8:
			# Silbando: boquita redonda.
			_piece(_sphere, m + Vector3(0.02, -0.01, 0.0), Vector3(0.04, 0.04, 0.03), Color("#5a1620"))
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
		8:
			# Pelo largo: cortina por detrás y mechones a los costados de la cara.
			_cap(hair)
			_piece(_sphere, Vector3(0.0, -0.12, -0.24), Vector3(0.5, 0.62, 0.28), hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.43, -0.12, 0.02), Vector3(0.13, 0.5, 0.22), hair, true,
					Basis(Vector3.BACK, side * 0.06))
			_piece(_sphere, _face(0.12, 0.33, 0.04), Vector3(0.26, 0.08, 0.08), hair, true,
				Basis(Vector3.BACK, 0.3))
		9:
			# Colita alta.
			_cap(hair)
			_piece(_sphere, Vector3(0.0, 0.38, -0.5), Vector3.ONE * 0.08, Color("#ff4f8b"))
			_piece(_sphere, Vector3(0.0, 0.1, -0.68), Vector3(0.13, 0.36, 0.13), hair, true,
				Basis(Vector3.RIGHT, 0.5))
		10:
			# Dos colitas a los costados.
			_cap(hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.5, 0.25, -0.12), Vector3.ONE * 0.07, Color("#ff4f8b"))
				_piece(_sphere, Vector3(side * 0.66, 0.0, -0.15), Vector3(0.12, 0.3, 0.12), hair, true,
					Basis(Vector3.BACK, side * 0.5))
		11:
			# Carré: hasta la mandíbula, con flequillo.
			_cap(hair)
			_piece(_sphere, Vector3(0.0, 0.0, -0.18), Vector3(0.55, 0.45, 0.36), hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.44, -0.07, 0.06), Vector3(0.13, 0.36, 0.26), hair)
			_piece(_sphere, _face(0.0, 0.32, 0.04), Vector3(0.38, 0.08, 0.08), hair)
		12:
			# Afro: una bola grande de pelo (sin tapar los ojos).
			_piece(_sphere, Vector3(0.0, 0.42, -0.22), Vector3(0.74, 0.62, 0.64), hair)
		13:
			# Dos rodetes arriba.
			_cap(hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.3, 0.6, -0.08), Vector3.ONE * 0.17, hair)
		14:
			# Rastas: muchas tiras que cuelgan por detrás y a los costados.
			_cap(hair)
			for j in 11:
				var a := deg_to_rad(lerpf(-120.0, 120.0, j / 10.0)) + PI
				var top := Vector3(sin(a) * 0.46, 0.18, cos(a) * 0.4)
				_piece(_sphere, top + Vector3(sin(a) * 0.05, -0.32, cos(a) * 0.04), Vector3(0.06, 0.34, 0.06),
					hair, true, Basis(Vector3(cos(a), 0.0, -sin(a)), 0.15))


## Anteojos oscuros: detrás no se ven los ojos.
const OPAQUE_GLASSES := [1, 5, 6, 7, 8, 10]


## Sombreros y gorros (de playa y de mar).
func _hat(style: int) -> void:
	match style:
		1:
			# Sombrero de paja con cinta roja.
			var straw := Color("#e9c766")
			_piece(_cyl, Vector3(0.0, 0.43, -0.02), Vector3(0.9, 0.018, 0.9), straw, true, Basis(Vector3.RIGHT, -0.08))
			_piece(_sphere, Vector3(0.0, 0.5, -0.04), Vector3(0.46, 0.3, 0.46), straw)
			_piece(_cyl, Vector3(0.0, 0.5, -0.04), Vector3(0.475, 0.055, 0.475), Color("#d8262c"))
		2:
			# Sombrero pirata: ala ancha levantada a los costados y calavera blanca.
			var black := Color("#1b1b22")
			_piece(_sphere, Vector3(0.0, 0.5, -0.04), Vector3(0.5, 0.32, 0.48), black)
			_piece(_cyl, Vector3(0.0, 0.48, -0.04), Vector3(0.78, 0.02, 0.62), black)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.55, 0.6, -0.04), Vector3(0.25, 0.2, 0.45), black, true,
					Basis(Vector3.BACK, side * 0.9))
			_piece(_sphere, Vector3(0.0, 0.62, 0.42), Vector3(0.1, 0.09, 0.03), WHITE)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.035, 0.63, 0.45), Vector3.ONE * 0.022, black, false)
			_piece(_sphere, Vector3(0.0, 0.53, 0.43), Vector3(0.13, 0.014, 0.02), WHITE, false, Basis(Vector3.BACK, 0.6))
			_piece(_sphere, Vector3(0.0, 0.53, 0.43), Vector3(0.13, 0.014, 0.02), WHITE, false, Basis(Vector3.BACK, -0.6))
		3:
			# Gorra de capitán: blanca, visera negra y ancla dorada.
			_piece(_cyl, Vector3(0.0, 0.5, -0.04), Vector3(0.5, 0.12, 0.5), WHITE)
			_piece(_cyl, Vector3(0.0, 0.62, -0.06), Vector3(0.56, 0.06, 0.56), WHITE)
			_piece(_cyl, Vector3(0.0, 0.42, -0.04), Vector3(0.505, 0.04, 0.505), Color("#1b1b22"))
			_piece(_sphere, Vector3(0.0, 0.4, 0.38), Vector3(0.3, 0.03, 0.2), Color("#1b1b22"))
			_piece(_sphere, Vector3(0.0, 0.53, 0.47), Vector3(0.06, 0.06, 0.02), Color("#f2c230"))
		4:
			# Gorro de tiburón: con aleta, dientes y ojitos.
			var shark := Color("#7f9db5")
			_piece(_sphere, Vector3(0.0, 0.22, -0.06), Vector3(0.58, 0.44, 0.54), shark)
			_piece(_cone, Vector3(0.0, 0.72, -0.12), Vector3(0.05, 0.2, 0.18), shark, true, Basis(Vector3.RIGHT, -0.35))
			for j in 7:
				var a := lerpf(-0.9, 0.9, j / 6.0)
				_piece(_cone, Vector3(sin(a) * 0.48, 0.34, cos(a) * 0.42), Vector3(0.035, 0.05, 0.02), WHITE, true,
					Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI))
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.36, 0.5, 0.3), Vector3.ONE * 0.04, BLACK, false)
		5:
			# Pañuelo atado atrás.
			var red := Color("#d8262c")
			_piece(_sphere, Vector3(0.0, 0.22, -0.06), Vector3(0.545, 0.38, 0.5), red)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.08, 0.05, -0.56), Vector3(0.06, 0.16, 0.04), red, true,
					Basis(Vector3.BACK, side * 0.5))
			for j in 5:
				_piece(_sphere, Vector3(-0.3 + j * 0.15, 0.42, 0.25), Vector3.ONE * 0.025, WHITE, false)
		6:
			# Gorra con visera.
			var cap := Color("#2f7fd6")
			_piece(_sphere, Vector3(0.0, 0.3, -0.06), Vector3(0.545, 0.36, 0.5), cap)
			_piece(_sphere, Vector3(0.0, 0.36, 0.45), Vector3(0.36, 0.035, 0.26), cap)
			_piece(_sphere, Vector3(0.0, 0.66, -0.06), Vector3.ONE * 0.05, WHITE)
		7:
			# Gorro de lana con pompón.
			var wool := Color("#ff9b1f")
			_piece(_sphere, Vector3(0.0, 0.32, -0.06), Vector3(0.55, 0.42, 0.51), wool)
			_piece(_cyl, Vector3(0.0, 0.3, -0.05), Vector3(0.56, 0.06, 0.52), Color("#ffd23f"))
			_piece(_sphere, Vector3(0.0, 0.8, -0.08), Vector3.ONE * 0.13, WHITE)
		8:
			# Corona de flores.
			var colors := [Color("#ff6fb5"), Color("#ffd23f"), Color("#ff5a4e"), WHITE, Color("#a46cff")]
			for j in 12:
				var a := j * TAU / 12.0
				var p := Vector3(sin(a) * 0.5, 0.36 + 0.05 * cos(a), cos(a) * 0.45 - 0.04)
				_piece(_sphere, p, Vector3.ONE * 0.075, colors[j % colors.size()])


## Ropa de arriba (del color del short).
func _top(style: int, color: Color, radii: Vector3) -> void:
	match style:
		1:
			# Bikini: dos copas grandes (acordes al torso), banda debajo y tiras al cuello.
			for side in [-1.0, 1.0]:
				var d := Vector3(side * 0.5, 0.02, 1.0).normalized()
				var nrm := _normal(radii, d)
				var up := Vector3.UP if absf(nrm.y) < 0.95 else Vector3.RIGHT
				var cup := Basis.looking_at(-nrm, up)
				_piece(_sphere, _on_ellipsoid(radii, d, 0.02), Vector3(0.2, 0.17, 0.06), color, true, cup)
				var neck := Vector3(side * 0.22, 0.85, 0.45).normalized()
				var top := _on_ellipsoid(radii, neck, 0.01)
				var bottom := _on_ellipsoid(radii, d, 0.03) + Vector3(0.0, 0.12, 0.0)
				var mid := (top + bottom) * 0.5
				_piece(_sphere, mid, Vector3(0.022, top.distance_to(bottom) * 0.5, 0.022), color, false,
					_align_y(top - bottom))
			_piece(_sphere, Vector3(0.0, -0.1, 0.0), Vector3(radii.x * 1.03, 0.04, radii.z * 1.04), color)
		2:
			# Musculosa: cubre el pecho.
			_piece(_sphere, Vector3(0.0, -0.03, 0.0), radii * Vector3(1.04, 0.95, 1.06), color)


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
	var xf := _extra_xf * Transform3D(rot * Basis.from_scale(size), pos)
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
		if outline:
			# Contorno: casco invertido con el grosor de todo el personaje.
			var hull := [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
			SurferKit.append_hull(
				hull, b.verts, b.normals, b.indices, _to_char(_group), SurferKit.OUTLINE_WIDTH
			)
			var hull_arrays := []
			hull_arrays.resize(Mesh.ARRAY_MAX)
			hull_arrays[Mesh.ARRAY_VERTEX] = hull[0]
			hull_arrays[Mesh.ARRAY_NORMAL] = hull[1]
			hull_arrays[Mesh.ARRAY_INDEX] = hull[2]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hull_arrays)
			mesh.surface_set_material(1, _hull_material())
		var mi := MeshInstance3D.new()
		mi.name = "Outlined" if outline else "Plain"
		mi.mesh = mesh
		mesh.surface_set_material(0, _material(outline))
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
	_materials[outline] = m
	return m


func _hull_material() -> StandardMaterial3D:
	if _outline_mat == null:
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.albedo_color = Color.BLACK
	return _outline_mat


## Del espacio del grupo al del personaje (con la escala de la cabeza, etc.).
func _to_char(node: Node3D) -> Basis:
	var b := Basis.IDENTITY
	var n: Node = node
	while n != null and n != char_root:
		if n is Node3D:
			b = (n as Node3D).basis * b
		n = n.get_parent()
	return b
