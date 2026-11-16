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
## Mechón: una hoja que se afina hasta la punta y se curva hacia +X.
var _lock: ArrayMesh
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
const BIG_HAIR := [2, 3, 4, 5, 12, 13, 14, 15]
## Rastas (peinado 14).
const DREADS := 14
## Ancho y fondo del pecho (para el collar).
var _neck_scale := Vector2.ONE


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
	_lock = _make_lock()
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
	if data.get_option("hair") == DREADS:
		# La raíz y el volumen de las rastas van con la cabeza (no se sacuden),
		# así nunca dejan ver ni atraviesan la cabeza.
		_dread_roots(hair)
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
	_hat(data.get_option("hat"), data.accent("hat_color"))
	_extra_xf = Transform3D.IDENTITY
	_commit()


## Pecho: ropa de arriba y collar (las perlas son del modelo). Los collares dan
## toda la vuelta al cuello (como las perlas): más abajo adelante y más arriba
## atrás. `neck_scale` = ancho y fondo del pecho (x, z), que cambian con el cuerpo.
func build_chest(group: Node3D, data: CharacterData, radii: Vector3, neck_scale := Vector2.ONE) -> void:
	_begin(group)
	_top(data.get_option("top"), data.shorts_color(), radii)
	_neck_scale = neck_scale
	var front := _neck_at(0.0)
	# Hacia adelante y un poco para arriba (como el pecho).
	var face := Basis(Vector3.RIGHT, -0.3)
	match data.get_option("neck"):
		2:
			_necklace(20, 0.075, [Color("#ff6fb5"), Color("#ffd23f"), Color("#ff5a4e"), WHITE])
		3:
			_necklace(34, 0.03, [Color("#f2c230")])
			_disc(front + Vector3(0.0, -0.07, 0.03), Vector3(0.0, 0.3, 1.0).normalized(), 0.08, Color("#f2c230"))
		4:
			# Dientes de tiburón en un cordón.
			_necklace(34, 0.022, [Color("#5a3a22")])
			for i in 5:
				var a := lerpf(-0.55, 0.55, i / 4.0)
				var pos := _neck_at(a) + Vector3(0.0, -0.05, 0.01)
				_piece(_cone, pos, Vector3(0.035, 0.05, 0.02), WHITE, true,
					Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI))
		5:
			# Silbato de guardavidas.
			_necklace(34, 0.02, [Color("#e8302a")])
			var pos := front + Vector3(0.0, -0.07, 0.03)
			_piece(_box, pos, Vector3(0.07, 0.04, 0.035), Color("#ff9b1f"), true, face)
			_piece(_cyl, pos + Vector3(0.08, 0.0, 0.0), Vector3(0.025, 0.035, 0.025), Color("#ff9b1f"), true,
				Basis(Vector3.BACK, PI / 2.0))
		6:
			# Caracol de mar.
			_necklace(34, 0.02, [Color("#5a3a22")])
			var pos := front + Vector3(0.0, -0.08, 0.03)
			_piece(_sphere, pos, Vector3(0.09, 0.08, 0.04), Color("#ffb7a8"), true, face)
			for k in 3:
				_piece(_sphere, pos + Vector3((k - 1) * 0.03, 0.0, 0.035), Vector3(0.008, 0.06, 0.008),
					Color("#d9776a"), false, Basis(Vector3.BACK, (k - 1) * 0.35))
		7:
			# Cuentas rasta: rojo, amarillo y verde.
			_necklace(24, 0.045, [Color("#e8302a"), Color("#ffd23f"), Color("#2fa84f")])
		9:
			# Cordón blanco ajustado y dos dientes de tiburón en el medio.
			_necklace(56, 0.014, [WHITE])
			for side in [-1.0, 1.0]:
				var a: float = side * 0.17
				var pos := _neck_at(a) + Vector3(0.0, -0.055, 0.015)
				_piece(_cone, pos + Vector3(0.0, -0.02, 0.0), Vector3(0.04, 0.08, 0.02), WHITE, true,
					Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI - 0.25) * Basis(Vector3.BACK, side * 0.35))
		8:
			# Paz y amor: cordón de cuero y el símbolo de la paz.
			_necklace(34, 0.02, [Color("#7a4a24")])
			var c := front + Vector3(0.0, -0.11, 0.03)
			var silver := Color("#e6e6ea")
			_piece(_ring_thick, c, Vector3.ONE * 0.085, silver, true, face * Basis(Vector3.RIGHT, PI / 2.0))
			var up := face * Vector3.UP
			var right := face * Vector3.RIGHT
			_piece(_box, c, Vector3(0.011, 0.07, 0.011), silver, false, face)
			for side in [-1.0, 1.0]:
				var d: Vector3 = (-up + right * side).normalized()
				_piece(_box, c + d * 0.035, Vector3(0.011, 0.04, 0.011), silver, false,
					face * Basis(Vector3.BACK, side * 0.785))
	_commit()


## Altura y fondo del moño del short (en radios de la cadera).
const TIE_HEIGHT := 0.75
const TIE_DEPTH := 1.0
## Cadera: el estampado del short ya no se arma con piezas (se pinta en la
## tela, ver shorts_pattern.gdshader); queda el grupo por si se agrega algo.
func build_hips(group: Node3D, data: CharacterData, radii: Vector3) -> void:
	_begin(group)
	var tie := data.get_option("shorts_tie")
	if tie > 0:
		var color := WHITE
		if tie == 2:
			color = BLACK
		elif tie == 3:
			color = data.accent("shorts_pattern_color")
		_shorts_tie(radii, color)
	_commit()


## Cordón del short: un moño adelante, arriba, con las dos puntas colgando.
func _shorts_tie(radii: Vector3, color: Color) -> void:
	var c := Vector3(0.0, radii.y * TIE_HEIGHT, radii.z * TIE_DEPTH)
	_piece(_sphere, c, Vector3(0.022, 0.022, 0.016), color, true)
	for side in [-1.0, 1.0]:
		# Las dos orejas del moño.
		_piece(_sphere, c + Vector3(side * 0.04, 0.005, 0.0), Vector3(0.04, 0.02, 0.012), color, true,
			Basis(Vector3.BACK, side * 0.25))
		# Las puntas, cayendo un poco abiertas.
		_piece(_sphere, c + Vector3(side * 0.022, -0.065, 0.006), Vector3(0.012, 0.06, 0.01), color, true,
			Basis(Vector3.BACK, side * 0.22))


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
		11, 12:
			# Redondos de sol (negros) o de color (estilo hippie), con marco fino.
			var lens := Color("#1d2a24") if style == 11 else Color("#ff8a3d")
			var frame := BLACK if style == 11 else Color("#d9a520")
			for side in [-1.0, 1.0]:
				var c := _eye_pos(side) + Vector3(0, -0.01, 0.05)
				_piece(_sphere, c, Vector3(0.12, 0.11, 0.03), lens, true)
				_piece(_ring, c + Vector3(0, 0, 0.012), Vector3(0.125, 0.12, 0.125), frame, false, facing)
				_piece(_sphere, c + Vector3(-0.035, 0.035, 0.03), Vector3(0.03, 0.012, 0.01),
					Color(1, 1, 1, 1) if style == 11 else Color("#ffd9a8"), false, Basis(Vector3.BACK, 0.6))
			_piece(_sphere, _face(0.0, 0.12, 0.06), Vector3(0.06, 0.012, 0.012), frame, false)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.44, 0.12, 0.12), Vector3(0.012, 0.012, 0.18), frame, false,
					Basis(Vector3.UP, side * 0.35))
		13:
			_wrap_shades()
		10:
			# Snorkel: antiparras de buceo y el tubo al costado.
			_piece(_sphere, _face(0.0, 0.1, 0.06), Vector3(0.38, 0.17, 0.05), Color("#2fbfb0"))
			_piece(_sphere, _face(0.0, 0.1, 0.1), Vector3(0.32, 0.12, 0.02), Color(0.75, 0.95, 1.0, 1.0), false)
			_piece(_sphere, Vector3(0.0, 0.1, 0.0), Vector3(0.5, 0.035, 0.47), Color("#2fbfb0"), false)
			_piece(_cyl, Vector3(0.46, 0.2, 0.02), Vector3(0.035, 0.3, 0.035), Color("#ff7a2f"))
			_piece(_cyl, Vector3(0.36, -0.15, 0.32), Vector3(0.03, 0.13, 0.03), Color("#ff7a2f"), true,
				Basis(Vector3.BACK, 0.9))


## Anteojos de sol envolventes y cuadrados: una sola pieza recortada (los dos
## vidrios y el puente) que sigue la curva de la cara, azul con degradé (más
## oscuro arriba) y dos brillos en diagonal en cada vidrio.
func _wrap_shades() -> void:
	# Contorno de la mitad derecha (x >= 0), en unidades de cabeza; se espeja.
	var half := [
		Vector2(0.0, 0.19), Vector2(0.43, 0.2), Vector2(0.455, 0.18), Vector2(0.45, 0.11),
		Vector2(0.42, 0.05), Vector2(0.37, 0.025), Vector2(0.17, 0.025), Vector2(0.11, 0.045),
		Vector2(0.065, 0.09), Vector2(0.0, 0.11),
	]
	var poly := PackedVector2Array()
	for i in range(half.size() - 1, -1, -1):
		var p: Vector2 = half[i]
		if p.x > 0.0:
			poly.append(Vector2(-p.x, p.y))
	for p in half:
		poly.append(p)
	var top := Color("#13215c")
	var bottom := Color("#2f6be0")
	_extruded(poly, 0.07, 0.035, func(p: Vector2) -> Color:
		return top.lerp(bottom, clampf((0.2 - p.y) / 0.15, 0.0, 1.0)), true)
	# Brillos: dos tiras finas en diagonal en cada vidrio.
	var shine := Color("#cfe9ff")
	for side in [-1.0, 1.0]:
		for j in 2:
			var cx: float = side * (0.24 + j * 0.09)
			var strip := PackedVector2Array([
				Vector2(cx - 0.03, 0.055), Vector2(cx - 0.01 - j * 0.004, 0.055),
				Vector2(cx + 0.03 - j * 0.01, 0.165), Vector2(cx + 0.01, 0.165),
			])
			_extruded(strip, 0.108, 0.004, func(_p: Vector2) -> Color: return shine, false)
	# Patillas negras hacia las orejas.
	for side in [-1.0, 1.0]:
		_piece(_box, Vector3(side * 0.47, 0.18, 0.08), Vector3(0.012, 0.016, 0.17), BLACK, false,
			Basis(Vector3.UP, side * 0.25))


## Pieza chata con forma de `poly` (x, y sobre la cara) apoyada sobre la cara:
## la parte de atrás a `out` de la piel y la de adelante `depth` más afuera.
## El color sale de `color_at` (por punto del contorno).
func _extruded(poly: PackedVector2Array, out: float, depth: float, color_at: Callable, outline: bool) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var n := poly.size()
	# Sentido del contorno (para saber de qué lado queda afuera).
	var area := 0.0
	for i in n:
		area += poly[i].cross(poly[(i + 1) % n])
	var ccw := area > 0.0
	var b: Dictionary = _batch[outline]
	var base := (b.verts as PackedVector3Array).size()
	for layer in 2:
		for i in n:
			var p := poly[i]
			var on_face := _face(p.x, p.y)
			var face_n := (_face(p.x, p.y, 1.0) - on_face).normalized()
			var pos := on_face + face_n * (out + depth * layer)
			# Normal hacia afuera del contorno (en el plano) más hacia adelante o
			# atrás: así el contorno negro rodea toda la pieza.
			var e := (poly[(i + 1) % n] - poly[(i - 1 + n) % n]).normalized()
			var side := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
			var nrm := (Vector3(side.x, side.y, 0.0) + face_n * (0.8 if layer == 1 else -0.8)).normalized()
			b.verts.append(_extra_xf * pos)
			b.normals.append(nrm)
			b.colors.append(color_at.call(p))
	# Adelante y atrás.
	for t in range(0, tris.size(), 3):
		var i0 := tris[t]
		var i1 := tris[t + 1]
		var i2 := tris[t + 2]
		if not ccw:
			b.indices.append_array([base + n + i0, base + n + i2, base + n + i1])
			b.indices.append_array([base + i0, base + i1, base + i2])
		else:
			b.indices.append_array([base + n + i0, base + n + i1, base + n + i2])
			b.indices.append_array([base + i0, base + i2, base + i1])
	# Costados.
	for i in n:
		var j := (i + 1) % n
		var a0 := base + i
		var a1 := base + j
		var f0 := base + n + i
		var f1 := base + n + j
		if not ccw:
			b.indices.append_array([a0, a1, f1, a0, f1, f0])
		else:
			b.indices.append_array([a0, f1, a1, a0, f0, f1])
	_count += 1


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
		5:
			# Chivita: barbita en la punta del mentón.
			_piece(_sphere, _face(0.0, -0.37, 0.02), Vector3(0.085, 0.1, 0.06), hair)
		6:
			# Bigote fino y chivita.
			_piece(_sphere, _face(0.0, -0.39, 0.02), Vector3(0.08, 0.1, 0.06), hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, _face(side * 0.07, -0.135, 0.012), Vector3(0.085, 0.024, 0.035), hair, true,
					Basis(Vector3.BACK, side * 0.22))
		7:
			# Barba tupida: de patilla a patilla, con bigote (la boca queda a la vista).
			_piece(_sphere, Vector3(0.0, -0.38, 0.1), Vector3(0.42, 0.26, 0.34), hair)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.4, -0.12, 0.02), Vector3(0.11, 0.26, 0.2), hair)
				_piece(_sphere, _face(side * 0.08, -0.14, 0.015), Vector3(0.1, 0.035, 0.045), hair, true,
					Basis(Vector3.BACK, side * 0.3))


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
			# Rastas: tiras gruesas con nudos que cuelgan alrededor de la cabeza
			# (la raíz y el volumen van en _dread_roots, fijos a la cabeza).
			_dread_strands(hair)
		15:
			_shaggy(hair)


## Anteojos oscuros: detrás no se ven los ojos.
const OPAQUE_GLASSES := [1, 5, 6, 7, 8, 10, 11, 12, 13]
## Rojo, amarillo y verde (de arriba a abajo).
const RASTA := [Color("#e8302a"), Color("#ffd23f"), Color("#2fa84f")]


## Sombreros y gorros (de playa y de mar).
func _hat(style: int, tint: Color = Color("#ff9b1f")) -> void:
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
			var red := tint
			_piece(_sphere, Vector3(0.0, 0.22, -0.06), Vector3(0.545, 0.38, 0.5), red)
			for side in [-1.0, 1.0]:
				_piece(_sphere, Vector3(side * 0.08, 0.05, -0.56), Vector3(0.06, 0.16, 0.04), red, true,
					Basis(Vector3.BACK, side * 0.5))
			for j in 5:
				_piece(_sphere, Vector3(-0.3 + j * 0.15, 0.42, 0.25), Vector3.ONE * 0.025, WHITE, false)
		6:
			# Gorra con visera.
			var cap := tint
			_piece(_sphere, Vector3(0.0, 0.3, -0.06), Vector3(0.545, 0.36, 0.5), cap)
			_piece(_sphere, Vector3(0.0, 0.36, 0.45), Vector3(0.36, 0.035, 0.26), cap)
			_piece(_sphere, Vector3(0.0, 0.66, -0.06), Vector3.ONE * 0.05, WHITE)
		7:
			# Gorro de lana con pompón.
			var wool := tint
			_piece(_sphere, Vector3(0.0, 0.32, -0.06), Vector3(0.55, 0.42, 0.51), wool)
			_piece(_cyl, Vector3(0.0, 0.3, -0.05), Vector3(0.56, 0.06, 0.52), tint.lightened(0.3))
			_piece(_sphere, Vector3(0.0, 0.8, -0.08), Vector3.ONE * 0.13, WHITE)
		8:
			# Corona de flores.
			var colors := [Color("#ff6fb5"), Color("#ffd23f"), Color("#ff5a4e"), WHITE, Color("#a46cff")]
			for j in 12:
				var a := j * TAU / 12.0
				var p := Vector3(sin(a) * 0.5, 0.36 + 0.05 * cos(a), cos(a) * 0.45 - 0.04)
				_piece(_sphere, p, Vector3.ONE * 0.075, colors[j % colors.size()])
		9:
			# Gorro rasta: una bolsa tejida grande caída hacia atrás, en franjas
			# verde, amarilla y roja.
			var tilt := Basis(Vector3.RIGHT, -0.32)
			_piece(_cyl, Vector3(0.0, 0.34, -0.06), Vector3(0.56, 0.09, 0.52), RASTA[2])
			_piece(_sphere, Vector3(0.0, 0.5, -0.18), Vector3(0.63, 0.28, 0.64), RASTA[1], true, tilt)
			_piece(_sphere, Vector3(0.0, 0.68, -0.3), Vector3(0.55, 0.25, 0.58), RASTA[0], true, tilt)
		10:
			# Bandana rasta: tres franjas en la frente y el nudo al costado.
			for k in 3:
				var y := 0.37 - k * 0.075
				_piece(_cyl, Vector3(0.0, y, -0.05), Vector3(0.53, 0.04, 0.5), RASTA[k], k == 1,
					Basis(Vector3.RIGHT, -0.12))
			var knot := Vector3(-0.48, 0.3, -0.2)
			_piece(_sphere, knot, Vector3(0.06, 0.08, 0.08), RASTA[1])
			for k in 3:
				var tail_rot := Basis(Vector3.UP, -0.5 - k * 0.25) * Basis(Vector3.BACK, 0.9 + k * 0.35)
				_piece(_sphere, knot + tail_rot * Vector3(0.0, 0.14, 0.0) + Vector3(-0.02, 0.0, 0.0),
					Vector3(0.05, 0.16, 0.025), RASTA[k], true, tail_rot)
		11:
			# Vincha hippie (del color elegido) con una flor al costado.
			_piece(_cyl, Vector3(0.0, 0.33, -0.05), Vector3(0.52, 0.035, 0.49), tint, true,
				Basis(Vector3.RIGHT, -0.12))
			var f := Vector3(0.42, 0.36, 0.22)
			for j in 5:
				var a := j * TAU / 5.0
				_piece(_sphere, f + Basis(Vector3.UP, 0.9) * Vector3(sin(a) * 0.055, cos(a) * 0.055, 0.0),
					Vector3(0.045, 0.045, 0.02), Color("#ff8fd0"), true, Basis(Vector3.UP, 0.9))
			_piece(_sphere, f + Basis(Vector3.UP, 0.9) * Vector3(0.0, 0.0, 0.015), Vector3.ONE * 0.03,
				Color("#ffd23f"), false)


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


## Rastas: dónde nace y hasta dónde cae cada tira (ángulo desde la nuca hacia
## los costados, en grados; largo hacia abajo en unidades de cabeza).
const DREAD_RING := Vector2(0.62, 0.6)


func _dread_dirs() -> Array:
	var out := []
	var n := 21
	for j in n:
		var deg := lerpf(-110.0, 110.0, j / float(n - 1))
		var a := deg_to_rad(deg)
		# Atrás, largas; hacia la cara, más cortas (hasta los hombros).
		var side := absf(deg) / 110.0
		var bottom := lerpf(-0.88, -0.5, side * side) + 0.05 * sin(j * 2.3)
		out.append([a, bottom])
	return out


## Raíz y volumen de las rastas (en el grupo de la cabeza): un gorro de pelo
## y una masa detrás de la nuca, así no queda ningún hueco por donde se vea la
## cabeza (con cualquier forma de cabeza, que escala todo junto).
func _dread_roots(hair: Color) -> void:
	_piece(_sphere, Vector3(0.0, 0.21, -0.08), Vector3(0.57, 0.41, 0.53), hair)
	_piece(_sphere, Vector3(0.0, -0.16, -0.27), Vector3(0.52, 0.6, 0.3), hair)
	# Raíz de cada tira, sobre el borde del gorro.
	for d in _dread_dirs():
		var a: float = d[0]
		var root := Vector3(sin(a) * DREAD_RING.x, 0.16, -cos(a) * DREAD_RING.y)
		_piece(_sphere, root, Vector3(0.085, 0.13, 0.085), hair)


## Tiras de las rastas (en el grupo del pelo, que se sacude): nudos gruesos
## uno debajo del otro y la punta más clara.
func _dread_strands(hair: Color) -> void:
	var tip := hair.lightened(0.28)
	var i := 0
	for d in _dread_dirs():
		var a: float = d[0]
		var bottom: float = d[1]
		var out := Vector3(sin(a), 0.0, -cos(a))
		var top := Vector3(out.x * DREAD_RING.x, 0.12, out.z * DREAD_RING.y)
		# Se abren un poco hacia afuera al caer.
		var end := top + out * (0.15 + 0.05 * sin(i * 1.7)) + Vector3(0.0, bottom - 0.12, 0.0)
		var segs := 3
		for k in segs:
			var t := (k + 0.5) / segs
			var p := top.lerp(end, t) + Vector3(0.01 * sin(i * 3.1 + k * 2.0), 0.0, 0.01 * cos(i * 2.3 + k))
			var len := top.distance_to(end) / segs * 0.62
			var r := 0.064 - k * 0.004
			_piece(_sphere, p, Vector3(r, len, r), hair, true, _align_y(end - top))
		_piece(_sphere, end + (end - top).normalized() * 0.02, Vector3(0.052, 0.065, 0.052), tip, true,
			_align_y(end - top))
		i += 1


## Despeinado: mucho volumen, mechones en punta para todos lados (arriba y a
## los costados) y un flequillo de puntas que cae hasta los anteojos.
func _shaggy(hair: Color) -> void:
	if _shaggy_shell.is_empty():
		_shaggy_shell = [_make_shaggy_shell(false), _make_shaggy_shell(true)]
	_piece(_shaggy_shell[0], Vector3.ZERO, Vector3.ONE, hair)
	# Por dentro, más oscuro (se ve debajo de las puntas que se abren).
	_piece(_shaggy_shell[1], Vector3.ZERO, Vector3.ONE, hair.darkened(0.35), false)
	# Arriba: mechones acostados sobre el volumen, barridos hacia un costado
	# y para atrás, con la punta apenas levantada (peinado con onda).
	var vol := Vector3(0.66, 0.64, 0.6) * 1.0
	var center := Vector3(0.0, 0.14, -0.06)
	var sweep := Vector3(0.75, 0.0, -0.65).normalized()
	for k in 6:
		var a := lerpf(-0.9, 0.9, k / 5.0)
		var d := Vector3(sin(a) * 0.45, 0.85, cos(a) * 0.45 - 0.1).normalized()
		var root := center + _on_ellipsoid(vol, d, -0.06)
		var n := _normal(vol, d)
		var along := (sweep - n * sweep.dot(n)).normalized()
		_lock_piece(root, along + n * (0.3 + 0.15 * sin(k * 1.7)), 0.32 + 0.05 * sin(k * 2.3), 0.28,
			n.cross(along) * (1.0 if k % 2 == 0 else -1.0),
			hair.darkened(0.1) if k % 2 == 1 else hair)
	# Costados: puntas cortas pegadas a la cabeza que se curvan para afuera y
	# para arriba (vistas de frente y de atrás).
	for side in [-1.0, 1.0]:
		for k in 3:
			var root := Vector3(side * 0.56, 0.08 - k * 0.1, 0.05 - k * 0.2)
			var dir := Vector3(side * 0.7, -1.0, 0.0)
			_lock_piece(root, dir, 0.2 - k * 0.02, 0.2, Vector3(0.0, 1.0, 0.0),
				hair.darkened(0.12) if k == 1 else hair)
	# Flequillo calcado del dibujo: mechones planos en punta sobre la frente,
	# que caen por encima del borde de los anteojos.
	for lock in SHAGGY_BANGS:
		_extruded(PackedVector2Array(lock), 0.1, 0.05, func(_p: Vector2) -> Color: return hair, true)


## Mechones del flequillo (x, y sobre la cara, en unidades de cabeza).
const SHAGGY_BANGS := [
	# Izquierda (de quien mira): cae hacia afuera.
	[Vector2(-0.46, 0.42), Vector2(-0.2, 0.47), Vector2(-0.3, 0.3), Vector2(-0.44, 0.13), Vector2(-0.43, 0.3)],
	# Centro-izquierda: punta larga hacia abajo, un poco hacia la izquierda.
	[Vector2(-0.27, 0.47), Vector2(0.02, 0.47), Vector2(-0.1, 0.33), Vector2(-0.2, 0.17), Vector2(-0.2, 0.33)],
	# Centro: corto, hacia la derecha.
	[Vector2(-0.06, 0.47), Vector2(0.2, 0.47), Vector2(0.12, 0.33), Vector2(0.06, 0.2), Vector2(0.0, 0.34)],
	# Derecha: cae hacia afuera.
	[Vector2(0.14, 0.47), Vector2(0.44, 0.42), Vector2(0.44, 0.3), Vector2(0.42, 0.14), Vector2(0.28, 0.32)],
]

## Cáscara del despeinado: [por fuera, por dentro].
var _shaggy_shell: Array = []


## Cáscara del despeinado: cubre la cabeza (más ancha que el cráneo) y el borde
## de abajo es una fila de puntas que se abren hacia afuera, más largas a los
## costados y atrás.
static func _make_shaggy_shell(inner: bool) -> ArrayMesh:
	var center := Vector3(0.0, 0.14, -0.06)
	var radii := Vector3(0.66, 0.64, 0.6)
	var cols := 72
	var rows := 10
	var teeth := 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cols:
		var th := c * TAU / cols
		var front := maxf(cos(th), 0.0)
		# Hasta dónde baja (0 = coronilla, PI = abajo): la frente queda libre
		# (la tapa el flequillo); costados hasta la mandíbula; atrás, la nuca.
		var hem := lerpf(1.82, 1.12, pow(front, 1.2))
		# Puntas: triángulos alrededor.
		var tri := 1.0 - absf(fmod(c * teeth / float(cols), 1.0) * 2.0 - 1.0)
		var tooth := tri * (1.0 - pow(front, 2.0))
		hem += 0.4 * tooth - 0.12
		for r in rows + 1:
			var t := r / float(rows)
			var ph := hem * t
			var d := Vector3(sin(th) * sin(ph), cos(ph), cos(th) * sin(ph))
			# Bultos de pelo (no un casco liso).
			var lump := 1.0 + 0.07 * sin(th * 7.0 + 1.3) * sin(ph * 3.0)
			# Cerca del borde se abre bien hacia afuera (más en las puntas).
			var flare := lump + (0.04 + 0.2 * tooth) * pow(t, 4.0)
			var p := center + d * radii * (flare - (0.05 if inner else 0.0))
			# Las puntas de los costados se levantan (se curvan para arriba).
			p.y += 0.16 * tooth * pow(t, 6.0) * (0.4 + 0.6 * absf(sin(th)))
			st.set_uv(Vector2(c, r))
			st.add_vertex(p)
	for c in cols:
		var c2 := (c + 1) % cols
		for r in rows:
			var a := c * (rows + 1) + r
			var b := c2 * (rows + 1) + r
			if inner:
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(b + 1)
			else:
				st.add_index(a)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b + 1)
				st.add_index(a + 1)
	st.generate_normals()
	return st.commit()


## Malla del mechón: de y = -1 (raíz, ancha) a y = 1 (punta), chata (de
## frente es ancha y de costado finita) y curvada hacia +X al final, como los
## mechones de pelo de dibujo animado.
static func _make_lock() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	var sides := 8
	var pts := []
	for i in rings + 1:
		var t := i / float(rings)
		# Ancho: redondeado en la raíz y afinándose hasta la punta.
		var r := sin(minf(t * 3.0, 1.0) * PI * 0.5) * 0.5 + 0.5
		r *= pow(1.0 - t, 0.9)
		var center := Vector3(0.9 * t * t, -1.0 + 2.0 * t, 0.0)
		var ring := []
		for j in sides:
			var a := j * TAU / sides
			ring.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.32))
		pts.append(ring)
	for i in rings:
		for j in sides:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % sides]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][(j + 1) % sides]
			for v in [a, b, c, b, d, c]:
				st.add_vertex(v)
	# Tapa de la raíz.
	var base := Vector3(0.0, -1.0, 0.0)
	for j in sides:
		st.add_vertex(base)
		st.add_vertex(pts[0][(j + 1) % sides])
		st.add_vertex(pts[0][j])
	st.index()
	st.generate_normals()
	return st.commit()


## Un mechón desde `root` hacia `dir`, de largo `len` y ancho `width`; la
## punta se curva hacia `bend`. Lo ancho del mechón mira hacia `face`.
func _lock_piece(root: Vector3, dir: Vector3, len: float, width: float, bend: Vector3, color: Color) -> void:
	var y := dir.normalized()
	var x := bend - y * bend.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	_piece(_lock, root + y * len * 0.5, Vector3(width, len * 0.5, width), color, true, Basis(x, y, z))


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

## Collar de cuentas que da toda la vuelta al cuello.
func _necklace(count: int, size: float, colors: Array) -> void:
	for i in count:
		_piece(_sphere, _neck_at(i * TAU / count), Vector3.ONE * size, colors[i % colors.size()])


## Punto del collar alrededor del cuello (a = 0 adelante, PI atrás), en el
## grupo del pecho: el mismo aro que el collar de perlas del modelo.
func _neck_at(a: float) -> Vector3:
	return Vector3(sin(a) * 0.32 * _neck_scale.x, 0.14 - 0.065 * cos(a), cos(a) * 0.285 * _neck_scale.y)


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
		var arrays: Array
		if mesh is PrimitiveMesh:
			arrays = (mesh as PrimitiveMesh).get_mesh_arrays()
		else:
			arrays = mesh.surface_get_arrays(0)
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
