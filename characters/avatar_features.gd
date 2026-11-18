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
## Media esfera (para copas de sombrero que no cuelgan debajo del ala).
var _hemi: SphereMesh
## Mechón: una hoja que se afina hasta la punta y se curva hacia +X.
var _lock: ArrayMesh
## Mechón ondulado (en S): primero se abomba para un lado y la punta se da
## vuelta para el otro.
var _wavy: ArrayMesh
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
const BIG_HAIR := [2, 3, 4, 5, 12, 13, 14, 15, 17]
## Melena ondulada (peinado 17).
const WAVY_BOB := 17
## Cuánto se sube el sombrero con la melena ondulada (con otros pelos grandes, 0.07).
const HAT_LIFT_BOB := -0.03
## Colita alta (peinado 16).
const HIGH_PONYTAIL := 16
## Rastas (peinado 14).
const DREADS := 14
## Altura del ribete de la bombacha (en radios de la cadera).
const BIKINI_TRIM_Y := 0.5
## Con panza redonda, cuánto se agrandan (x ancho, y fondo) la franja de la
## lycra y el bikini, para quedar sobre la panza.
const LYCRA_BELLY := Vector2(0.32, 1.0)
const BIKINI_BELLY := Vector2(0.1, 1.0)
## Cuánto de panza redonda tiene (0 normal ... 1 panzón).
var _belly_k: float = 0.0
## Bikini: color de los lunares (transparente si no lleva) y del ribete.
var _bikini_dots := Color(0, 0, 0, 0)
var _bikini_trim := Color("#e8302a")
## Franja de la lycra: altura (en el grupo del pecho) y tamaño (en radios del pecho).
const LYCRA_BAND_Y := -0.2
const LYCRA_BAND_R := Vector2(1.0, 1.04)
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
	_lock = _make_lock(0.9, 0.0)
	_wavy = _make_lock(0.8, -0.28)
	_hemi = SphereMesh.new()
	_hemi.radius = 1.0
	_hemi.height = 1.0
	_hemi.is_hemisphere = true
	_hemi.radial_segments = 16
	_hemi.rings = 6
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


## Formas de cabeza con otro perfil de cara (más lindas para personajes
## dulces): la parte de arriba es la misma; cachetes y mentón más redondos.
## Índice de forma (CharacterData.HEAD_SHAPES) -> perfil como SKULL_PROFILE.
const HEAD_PROFILES := {
	4: [
		[0.5, 0.17, 0.142], [0.4, 0.355, 0.3], [0.3, 0.44, 0.373], [0.2, 0.498, 0.425],
		[0.1, 0.506, 0.446], [0.0, 0.495, 0.447], [-0.1, 0.475, 0.44], [-0.2, 0.44, 0.422],
		[-0.3, 0.385, 0.392], [-0.4, 0.3, 0.342], [-0.5, 0.17, 0.25],
	],
	5: [
		[0.5, 0.167, 0.142], [0.4, 0.351, 0.299], [0.3, 0.437, 0.372], [0.2, 0.49, 0.42],
		[0.1, 0.495, 0.44], [0.0, 0.48, 0.44], [-0.1, 0.458, 0.432], [-0.2, 0.415, 0.41],
		[-0.3, 0.35, 0.375], [-0.4, 0.262, 0.318], [-0.5, 0.13, 0.215],
	],
	6: [
		[0.5, 0.167, 0.142], [0.4, 0.351, 0.299], [0.3, 0.437, 0.372], [0.2, 0.498, 0.425],
		[0.1, 0.506, 0.446], [0.0, 0.485, 0.446], [-0.1, 0.455, 0.435], [-0.2, 0.4, 0.405],
		[-0.3, 0.325, 0.362], [-0.4, 0.24, 0.302], [-0.5, 0.115, 0.2],
	],
}


## Cachetes (de ardilla): la cara se ensancha abajo, cachetes inflados y
## mentón redondo.
const CHEEKS_PROFILE := [
	[0.5, 0.167, 0.142], [0.4, 0.351, 0.299], [0.3, 0.437, 0.372], [0.2, 0.495, 0.425],
	[0.1, 0.52, 0.448], [0.0, 0.545, 0.455], [-0.1, 0.56, 0.455], [-0.2, 0.55, 0.445],
	[-0.3, 0.5, 0.415], [-0.4, 0.4, 0.36], [-0.5, 0.22, 0.26],
]


## Perfil de la cara para la forma de cabeza `shape`.
static func profile_for(shape: int) -> Array:
	if shape == 7:
		return CHEEKS_PROFILE
	return HEAD_PROFILES.get(shape, SKULL_PROFILE)


## Mitad del ancho y frente de la cara a la altura `y` según `profile`.
static func profile_at(profile: Array, y: float) -> Vector2:
	y = clampf(y, profile[profile.size() - 1][0], profile[0][0])
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		if y <= a[0] and y >= b[0]:
			var t: float = (a[0] - y) / (a[0] - b[0])
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	return Vector2(profile[0][1], profile[0][2])


## Perfil de la cara de este personaje (lo pone build_head).
var _profile: Array = SKULL_PROFILE


## Cabeza: ojos, anteojos, nariz, boca, cara, orejas y pelo, apoyados sobre el
## cráneo del modelo (el grupo es hijo de la cabeza). Las opciones que vienen
## del modelo (melena, anteojos de sol, sonrisa de costado) no se arman acá.
## El pelo va en su propio grupo (`hair_group`), así se puede mover solo.
func build_head(group: Node3D, hair_group: Node3D, data: CharacterData, skin: Color) -> void:
	# Parte de arriba del cráneo como un elipsoide (para pelos y orejas).
	_r = Vector3(0.51, 0.53, 0.45)
	_hs = 1.0
	_profile = profile_for(data.get_option("head"))
	var hair := data.hair_color()
	_begin(hair_group)
	_hair(data.get_option("hair"), hair)
	_commit()
	_begin(group)
	if data.get_option("hair") == DREADS:
		# La raíz y el volumen de las rastas van con la cabeza (no se sacuden),
		# así nunca dejan ver ni atraviesan la cabeza.
		_dread_roots(hair)
	if data.get_option("hair") == WAVY_BOB:
		# La parte de arriba y el flequillo de la melena van con la cabeza: así
		# no atraviesan el sombrero cuando el pelo se balancea.
		_wavy_bob_top(hair)
	_ears(data.get_option("ears"), skin)
	_eyes(data.get_option("eyes"), data.get_option("glasses"), hair)
	_extra(data.get_option("extra"), hair, skin)
	_nose(data.get_option("nose"), skin)
	_mouth(data.get_option("mouth"))
	_glasses(data.get_option("glasses"))
	if data.get_option("hair") in BIG_HAIR:
		# Agrandado desde la frente (así no se corre hacia atrás) y un poco arriba.
		var pivot := Vector3(0.0, 0.3, 0.0)
		# La melena ondulada es lisa arriba: el sombrero va más abajo (calzado).
		var lift := HAT_LIFT_BOB if data.get_option("hair") == WAVY_BOB else 0.07
		_extra_xf = Transform3D(Basis.from_scale(Vector3.ONE * 1.15), pivot + Vector3(0.0, lift, 0.0)) \
			* Transform3D(Basis.IDENTITY, -pivot)
	_hat(data.get_option("hat"), data.accent("hat_color"))
	_extra_xf = Transform3D.IDENTITY
	_commit()


## Pecho: ropa de arriba y collar (las perlas son del modelo). Los collares dan
## toda la vuelta al cuello (como las perlas): más abajo adelante y más arriba
## atrás. `neck_scale` = ancho y fondo del pecho (x, z), que cambian con el cuerpo.
func build_chest(group: Node3D, data: CharacterData, radii: Vector3, neck_scale := Vector2.ONE) -> void:
	_begin(group)
	_neck_scale = neck_scale
	_belly_k = clampf((data.weight - 0.5) / 0.5, 0.0, 1.0)
	_bikini_dots = data.accent("shorts_pattern_color") if data.get_option("shorts_pattern") == 2 else Color(0, 0, 0, 0)
	_bikini_trim = data.accent("trim_color")
	_top(data.get_option("top"), data.shorts_color(), radii, data.accent("top_color2"))
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
		10:
			# Dije: cordón finito oscuro y una gotita dorada adelante.
			_necklace(72, 0.012, [Color("#3a2414")], false)
			var pos := front + Vector3(0.0, -0.05, 0.02)
			_piece(_sphere, pos, Vector3(0.028, 0.038, 0.016), Color("#ffc21f"), true, face)
		9:
			# Cuellito blanco: cordón fino y dos puntas en V adelante (como un
			# cuello de camisa).
			_necklace(56, 0.012, [WHITE])
			for side in [-1.0, 1.0]:
				var pos := _neck_at(side * 0.12) + Vector3(side * 0.02, -0.045, 0.03)
				_piece(_cone, pos, Vector3(0.05, 0.055, 0.012), WHITE, true,
					face * Basis(Vector3.BACK, PI + side * 0.55))
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


## Cadera: el estampado del short ya no se arma con piezas (se pinta en la
## tela, ver shorts_pattern.gdshader); queda el grupo por si se agrega algo.
func build_hips(group: Node3D, data: CharacterData, radii: Vector3) -> void:
	_begin(group)
	if data.get_option("bottom") == CharacterData.BIKINI:
		# Ribete de la bombacha del bikini, en la cintura.
		_piece(_cyl, Vector3(0.0, radii.y * BIKINI_TRIM_Y, 0.0), Vector3(radii.x * 1.0, 0.03, radii.z * 1.04),
			data.accent("trim_color"), true)
	_commit()


# ---------------------------------------------------------------- cabeza

## Punto en "unidades de cabeza" sobre el elipsoide de arriba del cráneo.
func _h(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * _r.x, y * _r.y, z * _r.z)


## Punto sobre la cara (frente del cráneo) a la altura y y al costado x, un
## poco afuera (`out`).
func _face(x: float, y: float, out: float = 0.0) -> Vector3:
	var hz := profile_at(_profile, y)
	var hw := hz.x
	var fz := hz.y
	var k := clampf(x / maxf(hw, 0.01), -0.98, 0.98)
	var z := fz * sqrt(1.0 - k * k)
	var normal := Vector3(x / maxf(hw * hw, 0.0001), 0.0, z / maxf(fz * fz, 0.0001)).normalized()
	return Vector3(x, y, z) + normal * out


func _eye_pos(side: float) -> Vector3:
	return _face(side * 0.2, 0.1)


## Ojos. Con anteojos de sol no se ven (no se dibujan); con lentes, antiparras
## o monóculo se achican para quedar detrás del vidrio (que no lo atraviesen).
func _eyes(style: int, glasses: int = 0, hair: Color = BLACK) -> void:
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
			11:
				_cute_eye(p, side)
			10:
				# Grandes con brillo y cejas finas arqueadas.
				_piece(_sphere, p, Vector3(0.075, 0.1, 0.04) * maxf(k, 0.8), BLACK, false)
				_piece(_sphere, p + Vector3(-0.025, 0.035, 0.035), Vector3.ONE * 0.028, WHITE, false)
				var brow := PackedVector2Array()
				var ex := p.x
				for j in 7:
					var u := j / 6.0
					brow.append(Vector2(ex + (u - 0.5) * 0.17, 0.215 + 0.035 * sin(u * PI)))
				for j in 7:
					var u := 1.0 - j / 6.0
					brow.append(Vector2(ex + (u - 0.5) * 0.15, 0.215 + 0.015 * sin(u * PI) - 0.008))
				_extruded(brow, 0.004, 0.006, func(_q: Vector2) -> Color: return Color("#3a2414"), false)
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
		14:
			_thick_glasses()
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
## Culo de botella: vidrios redondos y gruesos con marco marrón; detrás, los
## ojos se ven enormes (blanco, pupila grande y brillo), y unos aros más
## claros marcan lo grueso del vidrio.
func _thick_glasses() -> void:
	var facing := Basis(Vector3.RIGHT, PI / 2.0)
	var frame := Color("#4a2f1c")
	var glass := Color("#dff3ff")
	for side in [-1.0, 1.0]:
		var c := _eye_pos(side) + Vector3(side * 0.015, 0.0, 0.06)
		_piece(_sphere, c, Vector3(0.17, 0.17, 0.04), glass, true)
		_piece(_ring, c + Vector3(0.0, 0.0, 0.03), Vector3(0.14, 0.14, 0.14), Color("#c5e6f7"), false, facing)
		# El ojo agrandado.
		_piece(_sphere, c + Vector3(0.0, -0.005, 0.03), Vector3(0.115, 0.12, 0.02), WHITE, false)
		_piece(_sphere, c + Vector3(-side * 0.01, -0.012, 0.044), Vector3(0.068, 0.072, 0.012), BLACK, false)
		_piece(_sphere, c + Vector3(-0.03, 0.025, 0.054), Vector3(0.024, 0.024, 0.008), WHITE, false)
		_piece(_sphere, c + Vector3(0.05, 0.075, 0.05), Vector3(0.03, 0.012, 0.006), WHITE, false,
			Basis(Vector3.BACK, -0.6))
		_piece(_ring_thick, c + Vector3(0.0, 0.0, 0.035), Vector3(0.18, 0.18, 0.18), frame, true, facing)
		# Patilla hacia la oreja.
		_piece(_box, Vector3(side * 0.47, 0.13, 0.1), Vector3(0.014, 0.018, 0.18), frame, false,
			Basis(Vector3.UP, side * 0.3))
	_piece(_cyl, _face(0.0, 0.13, 0.09), Vector3(0.022, 0.045, 0.022), frame, true, Basis(Vector3.BACK, PI / 2.0))


func _wrap_shades() -> void:
	# Contorno de la mitad derecha (x >= 0), en unidades de cabeza; se espeja.
	var half := [
		Vector2(0.0, 0.215), Vector2(0.44, 0.23), Vector2(0.46, 0.205), Vector2(0.41, 0.05),
		Vector2(0.36, 0.012), Vector2(0.15, 0.012), Vector2(0.1, 0.035),
		Vector2(0.05, 0.1), Vector2(0.0, 0.115),
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
		return top.lerp(bottom, clampf((0.23 - p.y) / 0.2, 0.0, 1.0)), true)
	# Brillos: dos tiras finas en diagonal en cada vidrio.
	var shine := Color("#cfe9ff")
	for side in [-1.0, 1.0]:
		for j in 2:
			var cx: float = side * (0.21 + j * 0.09)
			var strip := PackedVector2Array([
				Vector2(cx - 0.035, 0.04), Vector2(cx - 0.01 - j * 0.005, 0.04),
				Vector2(cx + 0.035 - j * 0.01, 0.2), Vector2(cx + 0.01, 0.2),
			])
			_extruded(strip, 0.108, 0.004, func(_p: Vector2) -> Color: return shine, false)
	# Patillas negras hacia las orejas.
	for side in [-1.0, 1.0]:
		_piece(_box, Vector3(side * 0.48, 0.2, 0.08), Vector3(0.012, 0.018, 0.17), BLACK, false,
			Basis(Vector3.UP, side * 0.25))


## Pieza chata con forma de `poly` (x, y sobre la cara) apoyada sobre la cara:
## la parte de atrás a `out` de la piel y la de adelante `depth` más afuera.
## El color sale de `color_at` (por punto del contorno).
func _extruded(
	poly: PackedVector2Array, out: float, depth: float, color_at: Callable, outline: bool, lift: float = 0.0
) -> void:
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
			var o := out + lift * pow(clampf((p.y - 0.25) / 0.22, 0.0, 1.0), 2.0)
			var pos := on_face + face_n * (o + depth * layer)
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
		5:
			# Con protector solar: nariz redonda pintada de blanco (de guardavidas).
			_piece(_sphere, p + Vector3(0, -0.01, 0.02), Vector3(0.075, 0.07, 0.07), skin.darkened(0.08))
			# Franja de protector de lado a lado, sobre la nariz.
			_piece(_sphere, _face(0.0, 0.0, 0.03), Vector3(0.16, 0.028, 0.05), WHITE, false)


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
		14:
			# Abuelo feliz: boca bien abierta (gritando de alegría arriba de una
			# ola), lengua y dos dientes arriba con un hueco en el medio.
			var mouth := PackedVector2Array()
			for j in 15:
				var u := j / 14.0
				mouth.append(Vector2(lerpf(-0.14, 0.14, u), -0.17 - 0.16 * sin(u * PI)))
			mouth.reverse()
			mouth.append(Vector2(-0.145, -0.16))
			mouth.append(Vector2(0.0, -0.15))
			mouth.append(Vector2(0.145, -0.16))
			_extruded(mouth, 0.0, 0.012, func(_q: Vector2) -> Color: return Color("#5a1620"), true)
			var tongue := PackedVector2Array()
			for j in 9:
				var u := j / 8.0
				tongue.append(Vector2(lerpf(-0.08, 0.08, u), -0.3 - 0.035 * sin(u * PI)))
			tongue.reverse()
			tongue.append(Vector2(0.0, -0.26))
			_extruded(tongue, 0.014, 0.004, func(_q: Vector2) -> Color: return Color("#ff7b8a"), false)
			for side in [-1.0, 1.0]:
				var x: float = side * 0.055
				_extruded(PackedVector2Array([Vector2(x - 0.03, -0.165), Vector2(x + 0.03, -0.165),
					Vector2(x + 0.026, -0.21), Vector2(x - 0.026, -0.21)]), 0.014, 0.004,
					func(_q: Vector2) -> Color: return WHITE, false)
		15:
			# Risa sin dientes: bien abierta y contenta, con encías rosadas arriba.
			_open_mouth(_arc_poly(0.15, -0.165, 0.15, 0.012), Color("#5a1620"))
			_extruded(_arc_poly(0.13, -0.168, 0.035, 0.0), 0.014, 0.004,
				func(_q: Vector2) -> Color: return Color("#e86a7c"), false)
			_extruded(_arc_poly(0.07, -0.27, 0.03, 0.0, true), 0.014, 0.004,
				func(_q: Vector2) -> Color: return Color("#ff7b8a"), false)
		16:
			# Un diente: sonrisa ancha cerrada, con un solo diente que asoma.
			_stroke(_face(0.0, -0.215, 0.012), -0.16, 0.16, 0.04, 0.0)
			_extruded(PackedVector2Array([Vector2(0.02, -0.2), Vector2(0.07, -0.2), Vector2(0.065, -0.245),
				Vector2(0.025, -0.245)]), 0.014, 0.006, func(_q: Vector2) -> Color: return WHITE, true)
		17:
			# Carcajada: media luna bien abierta con la fila de dientes de arriba.
			_open_mouth(_arc_poly(0.17, -0.17, 0.13, 0.03), Color("#5a1620"))
			_extruded(_arc_poly(0.145, -0.172, 0.03, 0.012), 0.014, 0.004,
				func(_q: Vector2) -> Color: return WHITE, false)
			_extruded(_arc_poly(0.07, -0.265, 0.025, 0.0, true), 0.014, 0.004,
				func(_q: Vector2) -> Color: return Color("#ff7b8a"), false)
		18:
			# ¡Wooo!: óvalo alto, gritando de emoción arriba de la ola.
			var o := PackedVector2Array()
			for j in 20:
				var a := j * TAU / 20.0
				o.append(Vector2(sin(a) * 0.085, -0.25 + cos(a) * 0.105))
			_open_mouth(o, Color("#5a1620"))
			var t := PackedVector2Array()
			for j in 12:
				var a := j * TAU / 12.0
				t.append(Vector2(sin(a) * 0.05, -0.31 + cos(a) * 0.03))
			_extruded(t, 0.014, 0.004, func(_q: Vector2) -> Color: return Color("#ff7b8a"), false)
		11:
			# Canchera: una línea que sube hacia la derecha, larga y segura.
			_stroke(_face(0.03, -0.215, 0.012), -0.1, 0.14, 0.03, 0.8)
		12:
			# Sonrisa ancha: una sola línea finita de lado a lado, poco curva.
			_stroke(m + Vector3(0.0, 0.0, 0.007), -0.16, 0.16, 0.035, 0.0)
		13:
			# Pícara: sube hacia la izquierda y tiene un hoyuelo en la punta.
			_stroke(_face(-0.03, -0.215, 0.012), -0.13, 0.08, 0.03, -0.8)
			_piece(_sphere, _face(-0.18, -0.165, 0.006), Vector3(0.012, 0.022, 0.01), BLACK, false,
				Basis(Vector3.BACK, -0.5))
		10:
			# Sonrisa abierta en D: arriba recta, abajo redonda, con los dientes
			# de arriba y la lengua.
			var mouth := PackedVector2Array()
			var teeth := PackedVector2Array()
			for j in 13:
				var u := j / 12.0
				var x := lerpf(-0.13, 0.13, u)
				mouth.append(Vector2(x, -0.2 - 0.11 * sin(u * PI)))
				teeth.append(Vector2(lerpf(-0.105, 0.105, u), -0.212 - 0.025 * sin(u * PI)))
			mouth.reverse()
			mouth.append(Vector2(-0.135, -0.19))
			mouth.append(Vector2(0.135, -0.19))
			teeth.reverse()
			teeth.append(Vector2(-0.11, -0.205))
			teeth.append(Vector2(0.11, -0.205))
			_extruded(mouth, 0.0, 0.012, func(_q: Vector2) -> Color: return Color("#5a1620"), true)
			_extruded(teeth, 0.014, 0.004, func(_q: Vector2) -> Color: return WHITE, false)
			_piece(_sphere, _face(0.0, -0.28, 0.008), Vector3(0.06, 0.025, 0.01), Color("#ff7b8a"), false)
		9:
			# Sonrisota: boca grande en media luna con los dientes de arriba.
			var c := _face(0.0, -0.235, 0.01)
			_piece(_sphere, c + Vector3(0.0, -0.01, 0.0), Vector3(0.17, 0.075, 0.04), Color("#5a1620"))
			_piece(_sphere, c + Vector3(0.0, -0.05, 0.02), Vector3(0.08, 0.03, 0.025), Color("#ff7b8a"), false)
			_piece(_sphere, c + Vector3(0.0, 0.025, 0.028), Vector3(0.145, 0.03, 0.02), WHITE, false)
			for side in [-1.0, 1.0]:
				# Comisuras para arriba.
				_piece(_sphere, c + Vector3(side * 0.17, 0.035, 0.0), Vector3(0.03, 0.012, 0.02), BLACK, false,
					Basis(Vector3.BACK, side * 0.7))
		5:
			for i in 4:
				var x := -0.11 + i * 0.073
				_piece(_sphere, m + Vector3(x, 0, 0), Vector3(0.046, 0.011, 0.02), BLACK, false,
					Basis(Vector3.FORWARD, 0.5 if i % 2 == 0 else -0.5))


## Ojo claro y tierno (estilo dibujo animado): blanco sin contorno, iris
## grande azul, un brillo y párpado de arriba grueso con una colita hacia afuera.
func _cute_eye(p: Vector3, side: float) -> void:
	var k := 1.2
	var e := p + Vector3(side * 0.015, -0.015, 0.0)
	_piece(_sphere, e + Vector3(0.0, 0.0, 0.012), Vector3(0.074, 0.088, 0.024) * k, WHITE, false)
	# Simple, como el resto del juego: iris de un color y un brillo (sin pupila).
	_piece(_sphere, e + Vector3(-side * 0.007, -0.006, 0.024), Vector3(0.06, 0.077, 0.02) * k, Color("#2f86e0"), false)
	_piece(_sphere, e + Vector3(-0.024, 0.028, 0.046), Vector3(0.022, 0.026, 0.008) * k, WHITE, false)
	# Párpado de arriba: arco grueso que termina en una colita hacia afuera.
	var lid := []
	var widths := []
	var n := 10
	for i in n + 1:
		var u := i / float(n)
		# Arco parejo y redondeado (si sube mucho hacia afuera parece enojada),
		# con una colita chiquita al final.
		var x := lerpf(-0.08, 0.1, u)
		# La punta de adentro un poco más alta (mirada dulce, no enojada).
		var y := 0.08 + 0.034 * sin(u * PI) + 0.02 * (1.0 - u)
		if u > 0.82:
			y += (u - 0.82) * 0.12
		var q := Vector2(e.x + side * x, e.y + y)
		lid.append(_face(q.x, q.y, 0.032))
		widths.append(0.018 * sin(lerpf(0.04, 0.88, u) * PI) * smoothstep(0.0, 0.35, u) + 0.002)
	_piece(_make_tube(lid, widths), Vector3.ZERO, Vector3.ONE, BLACK, false)


## Boca abierta: la forma `poly` sobre la cara, oscura y con contorno.
func _open_mouth(poly: PackedVector2Array, color: Color) -> void:
	_extruded(poly, 0.0, 0.012, func(_q: Vector2) -> Color: return color, true)


## Forma de media luna (boca o encía): arriba casi recta en `top` (con la
## curva `lift` en las puntas) y abajo un arco de alto `depth`, de ancho `half`
## a cada lado. `round_top`: también redondeada arriba (lengua).
func _arc_poly(half: float, top: float, depth: float, lift: float, round_top: bool = false) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var n := 14
	for j in n + 1:
		var u := j / float(n)
		poly.append(Vector2(lerpf(half, -half, u), top - depth * sin(u * PI)))
	for j in range(1, n):
		var u := j / float(n)
		var y := top + lift * pow(absf(u * 2.0 - 1.0), 2.0)
		if round_top:
			y = top + depth * 0.6 * sin(u * PI)
		poly.append(Vector2(lerpf(-half, half, u), y))
	return poly


## Línea finita apoyada sobre la cara siguiendo `points` (x, y), que se afina
## en las puntas (arrugas y detalles dibujados).
func _face_line(points: Array, width: float, color: Color, out: float = 0.012) -> void:
	var path := []
	var widths := []
	for i in points.size():
		var q: Vector2 = points[i]
		path.append(_face(q.x, q.y, out))
		widths.append(width * sin(lerpf(0.15, 0.85, i / float(points.size() - 1)) * PI))
	_piece(_make_tube(path, widths), Vector3.ZERO, Vector3.ONE, color, false)


## Arrugas de abuelo: tres en la frente, patas de gallo al costado de los ojos
## y las líneas de la sonrisa (de la nariz a la boca).
func _wrinkles(skin: Color) -> void:
	var c := skin.darkened(0.32)
	for k in 3:
		var y := 0.3 + k * 0.065
		var w := 0.24 - k * 0.04
		var pts := []
		for j in 7:
			var u := j / 6.0
			pts.append(Vector2(lerpf(-w, w, u), y + 0.018 * sin(u * PI)))
		_face_line(pts, 0.011, c)
	for side in [-1.0, 1.0]:
		for k in 3:
			var a := (k - 1) * 0.45
			var start := Vector2(side * 0.36, 0.1)
			var dir := Vector2(side * cos(a), sin(a))
			_face_line([start, start + dir * 0.04, start + dir * 0.08], 0.009, c)
		_face_line([Vector2(side * 0.11, -0.05), Vector2(side * 0.16, -0.11), Vector2(side * 0.18, -0.17),
			Vector2(side * 0.18, -0.21)], 0.011, c)


## Pelo de científico: pelado arriba y mechones blancos despeinados que salen
## para todos lados por los costados y atrás (y un par de pelitos sueltos arriba).
func _scientist_hair(hair: Color) -> void:
	# Pelado arriba; a los costados y atrás el pelo nace de la cabeza: una base
	# pegada al cráneo y mechones mullidos que salen de ahí para afuera y un
	# poco para arriba (despeinado y esponjoso, con las puntas redondas).
	_piece(_sphere, Vector3(0.0, 0.12, -0.12), Vector3(0.53, 0.3, 0.45), hair)
	var i := 0
	for row in 4:
		var y := -0.02 + row * 0.09
		var n := 18 - row * 3
		for k in n:
			var a := lerpf(-2.2, 2.2, k / float(n - 1)) + 0.11 * row
			var th := PI + a
			var out := Vector3(sin(th), 0.0, cos(th))
			var h := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			var side := absf(sin(th))
			var root := Vector3(out.x * 0.47, y, out.z * 0.43 - 0.06)
			var tangent := out.cross(Vector3.UP)
			var dir := out + Vector3(0.0, 0.25 + 0.3 * row + 0.25 * h, 0.0) + tangent * (h - 0.5) * 0.6
			var length := 0.14 + 0.08 * side + 0.1 * h
			var d := dir.normalized()
			# Mechón mullido: un óvalo alargado que nace en la cabeza y sale
			# hacia afuera, con la punta redonda (no en punta).
			var x := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
			var basis := Basis(x, d, x.cross(d))
			_piece(_sphere, root + d * length * 0.55, Vector3(0.065 + 0.025 * h, length * 0.62, 0.06),
				hair.darkened(0.07) if i % 4 == 1 else hair, true, basis)
			i += 1



## Trazo de boca de una línea, como de pincel: un tubo finito que sigue la
## misma curva que `_curve` (de `from` a `to`) y se afina en las puntas.
func _stroke(center: Vector3, from: float, to: float, bend: float, tilt: float) -> void:
	var path := []
	var widths := []
	var n := 10
	for i in n + 1:
		var x := lerpf(from, to, i / float(n))
		var y := bend * pow(x / 0.11, 2.0) + tilt * x * 0.3
		path.append(center + Vector3(x, y, 0.0))
		widths.append(0.016 * sin(lerpf(0.25, 0.75, i / float(n)) * PI))
	_piece(_make_tube(path, widths), Vector3.ZERO, Vector3.ONE, BLACK, false)


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


func _extra(style: int, hair: Color, skin: Color = Color.WHITE) -> void:
	match style:
		12:
			# Cachetes colorados: dos manchitas rosadas redondas.
			for side in [-1.0, 1.0]:
				var q := Vector2(side * 0.27, -0.09)
				_disc(_face(q.x, q.y, 0.008), (_face(q.x, q.y, 1.0) - _face(q.x, q.y)).normalized(), 0.07,
					skin.lerp(Color("#ff6f86"), 0.55), false)
		10, 11:
			_wrinkles(skin)
			if style == 11:
				_extra(8, hair, skin)
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
		9:
			# Pecas: tres en cada cachete.
			for side in [-1.0, 1.0]:
				for j in 3:
					var q := Vector2(side * (0.24 + 0.05 * (j % 2) + 0.02 * j), -0.06 - 0.04 * j)
					_disc(_face(q.x, q.y, 0.006), (_face(q.x, q.y, 1.0) - _face(q.x, q.y)).normalized(), 0.017,
						Color("#a85a2f"), false)
		8:
			# Bigotón: grueso y redondo, con las puntas para abajo (no tapa la sonrisa).
			for side in [-1.0, 1.0]:
				_piece(_sphere, _face(side * 0.08, -0.115, 0.03), Vector3(0.1, 0.042, 0.05), hair, true,
					Basis(Vector3.BACK, side * 0.25))
				_piece(_sphere, _face(side * 0.165, -0.145, 0.02), Vector3(0.04, 0.045, 0.04), hair, true,
					Basis(Vector3.BACK, side * 0.5))
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
	if style == 4:
		# Orejas normales con aritos dorados colgando.
		for side in [-1.0, 1.0]:
			_piece(_sphere, Vector3(side * 0.509, 0.05, -0.02), Vector3(0.065, 0.12, 0.09), skin, true)
			_piece(_ring_thick, Vector3(side * 0.53, -0.1, 0.0), Vector3(0.055, 0.055, 0.055), Color("#ffc21f"),
				true, Basis(Vector3.BACK, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0))
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
			# Afro: una bola grande de pelo (sin tapar los ojos), con el borde en
			# bultitos como una nube.
			var c := Vector3(0.0, 0.42, -0.22)
			var r := Vector3(0.74, 0.62, 0.64)
			_piece(_sphere, c, r, hair)
			for d in _cap_dirs(26, -0.55):
				if d.z > 0.5 and d.y < 0.35:
					continue
				_piece(_sphere, c + _on_ellipsoid(r, d, -0.1), Vector3.ONE * 0.2, hair)
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
		16:
			_high_ponytail(hair)
		17:
			_wavy_bob(hair)
		18:
			_scientist_hair(hair)


## Anteojos oscuros: detrás no se ven los ojos.
const OPAQUE_GLASSES := [1, 5, 6, 7, 8, 10, 11, 12, 13, 14]
## Rojo, amarillo y verde (de arriba a abajo).
const RASTA := [Color("#e8302a"), Color("#ffd23f"), Color("#2fa84f")]


## Sombreros y gorros (de playa y de mar).
func _hat(style: int, tint: Color = Color("#ff9b1f")) -> void:
	match style:
		1:
			# Sombrero de paja con cinta roja.
			var straw := Color("#e9c766")
			_piece(_cyl, Vector3(0.0, 0.43, -0.02), Vector3(0.9, 0.018, 0.9), straw, true, Basis(Vector3.RIGHT, -0.08))
			# Copa: un cilindro que nace en el ala y una cúpula arriba (nada cuelga
			# debajo del ala, así no tapa la frente ni el pelo).
			_piece(_cyl, Vector3(0.0, 0.535, -0.04), Vector3(0.47, 0.105, 0.47), straw)
			_piece(_sphere, Vector3(0.0, 0.64, -0.04), Vector3(0.47, 0.14, 0.47), straw)
			# Cinta: bien por encima del ala (con su contorno), así no asoma por
			# debajo aunque el ala esté inclinada.
			_piece(_cyl, Vector3(0.0, 0.555, -0.04), Vector3(0.485, 0.035, 0.485), Color("#d8262c"))
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
		13:
			# Bombín: chico (el pelo sobresale por los costados), copa redonda,
			# ala corta con el borde enrollado y una cinta (más oscura que el
			# color elegido, o dorada si el bombín es oscuro). La copa es media
			# esfera: nada cuelga debajo del ala.
			var band := tint.darkened(0.55) if tint.get_luminance() > 0.25 else Color("#c9a227")
			var c := Vector3(0.0, 0.42, -0.04)
			_piece(_cyl, c, Vector3(0.5, 0.014, 0.46), tint, true, Basis(Vector3.RIGHT, -0.08))
			_piece(_ring_thick, c + Vector3(0.0, 0.012, 0.0), Vector3(0.5, 0.06, 0.46), tint, true,
				Basis(Vector3.RIGHT, -0.08))
			_piece(_hemi, c, Vector3(0.37, 0.36, 0.36), tint, true)
			_piece(_cyl, c + Vector3(0.0, 0.05, 0.0), Vector3(0.375, 0.045, 0.365), band, true)
		12:
			# Vincha deportiva: banda gruesa de toalla con una raya blanca.
			_piece(_cyl, Vector3(0.0, 0.3, -0.04), Vector3(0.53, 0.07, 0.5), tint, true,
				Basis(Vector3.RIGHT, -0.12))
			_piece(_cyl, Vector3(0.0, 0.3, -0.04), Vector3(0.535, 0.015, 0.505), WHITE, false,
				Basis(Vector3.RIGHT, -0.12))


## Ropa de arriba (del color del short).
func _top(style: int, color: Color, radii: Vector3, band: Color = WHITE) -> void:
	match style:
		1:
			# El bikini sigue el ancho del pecho (más finito en la silueta flaca) y
			# la panza redonda de los gorditos.
			radii *= Vector3(_neck_scale.x, 1.0, _neck_scale.y) * Vector3(1.0 + BIKINI_BELLY.x * _belly_k, 1.0, 1.0 + BIKINI_BELLY.y * _belly_k)
			# Bikini: dos copas grandes (acordes al torso), banda debajo y tiras al cuello.
			for side in [-1.0, 1.0]:
				var d := Vector3(side * 0.5, 0.02, 1.0).normalized()
				var nrm := _normal(radii, d)
				var up := Vector3.UP if absf(nrm.y) < 0.95 else Vector3.RIGHT
				var cup := Basis.looking_at(-nrm, up)
				var cup_pos := _on_ellipsoid(radii, d, 0.02)
				# Copa en triángulo (punta para arriba, hacia la tira del cuello).
				_piece(_cone, cup_pos + cup * Vector3(0.0, -0.01, 0.0), Vector3(0.16, 0.13, 0.035), color, true, cup)
				# Ribete abajo de la copa.
				_piece(_cyl, cup_pos + cup * Vector3(0.0, -0.13, 0.0), Vector3(0.17, 0.018, 0.04), _bikini_trim,
					false, cup * Basis(Vector3.RIGHT, PI / 2.0))
				# Lunares (si el estampado es de lunares).
				if _bikini_dots.a > 0.0:
					for q2 in [Vector2(-0.075, -0.1), Vector2(0.075, -0.1), Vector2(0.0, -0.08), Vector2(-0.035, -0.03),
							Vector2(0.035, -0.03), Vector2(0.0, 0.03)]:
						var dot: Vector2 = q2
						var depth := 0.035 * (1.0 - (dot.y + 0.14) / 0.27) + 0.006
						var q := cup * Vector3(dot.x, dot.y, depth)
						_piece(_sphere, cup_pos + q, Vector3(0.02, 0.02, 0.008), _bikini_dots, false, cup)
				var neck := Vector3(side * 0.22, 0.85, 0.45).normalized()
				var top := _on_ellipsoid(radii, neck, 0.01)
				var bottom := _on_ellipsoid(radii, d, 0.03) + Vector3(0.0, 0.12, 0.0)
				var mid := (top + bottom) * 0.5
				_piece(_sphere, mid, Vector3(0.018, top.distance_to(bottom) * 0.5, 0.018), _bikini_trim, false,
					_align_y(top - bottom))
			_piece(_sphere, Vector3(0.0, -0.1, 0.0), Vector3(radii.x * 1.03, 0.04, radii.z * 1.04), color)
		2:
			# Musculosa: cubre el pecho (con panza redonda, la panza ya es de tela).
			if _belly_k <= 0.0:
				_piece(_sphere, Vector3(0.0, -0.03, 0.0), radii * Vector3(1.04, 0.95, 1.06), color)
		CharacterData.LYCRA:
			# Lycra de surf: el torso ya es de tela (SurferKit); acá va la franja
			# de otro color alrededor de la panza, sobre la tela.
			_piece(_cyl, Vector3(0.0, LYCRA_BAND_Y, 0.0),
				Vector3(radii.x * _neck_scale.x * LYCRA_BAND_R.x * (1.0 + LYCRA_BELLY.x * _belly_k), 0.055,
					radii.z * _neck_scale.y * LYCRA_BAND_R.y * (1.0 + LYCRA_BELLY.y * _belly_k)),
				band, true)


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
	# Base: tapa la cabeza (casi no se ve, la cubren los mechones).
	_piece(_shaggy_shell[0], Vector3.ZERO, Vector3.ONE, hair)
	_piece(_shaggy_shell[1], Vector3.ZERO, Vector3.ONE, hair.darkened(0.35), false)
	var dark := hair.darkened(0.14)
	var light := hair.lightened(0.06)
	# Mechones ondulados que nacen en filas desde la coronilla y caen hacia
	# afuera, cada uno con la punta para un lado: el despeinado.
	var rows := [[0.25, 5, 0.45, 0.32], [0.7, 9, 0.45, 0.38], [1.1, 12, 0.35, 0.44], [1.5, 13, 0.4, 0.42]]
	var n := 0
	for row in rows:
		var ph: float = row[0]
		var count: int = row[1]
		for i in count:
			var th := (i + 0.5 * (n % 2)) * TAU / count + 0.3
			# La cara queda libre (ahí va el flequillo).
			var front := cos(th)
			if ph > 0.6 and front > 0.55:
				continue
			var d := Vector3(sin(th) * sin(ph), cos(ph), cos(th) * sin(ph))
			var root := SHAGGY_CENTER + d * SHAGGY_RADII * 0.95
			var down := Vector3(sin(th) * cos(ph), -sin(ph), cos(th) * cos(ph))
			var side := Vector3(cos(th), 0.0, -sin(th))
			var jitter := sin(n * 2.7) * 0.35
			var dir := down + d * float(row[2]) + side * jitter
			var len: float = float(row[3]) + 0.06 * sin(n * 1.9)
			var tone := dark if n % 4 == 1 else (light if n % 4 == 3 else hair)
			_lock_piece(root, dir, len, 0.28, side * (1.0 if n % 2 == 0 else -1.0), tone, _wavy)
			n += 1
	# Patillas: a los costados de la cara bajan hasta las mejillas y la punta
	# se abre para afuera.
	for s2 in [-1.0, 1.0]:
		for k in 2:
			var root := Vector3(s2 * (0.46 + k * 0.06), 0.34 - k * 0.04, 0.24 - k * 0.16)
			_lock_piece(root, Vector3(s2 * (0.35 + k * 0.15), -1.0, 0.1), 0.5 - k * 0.04, 0.27,
				Vector3(s2, 0.0, 0.0), hair if k == 0 else dark, _wavy)
	# Flequillo: mechones que caen sobre la frente hasta los anteojos, con la
	# punta para un costado.
	for k in 5:
		var x := lerpf(-0.34, 0.34, k / 4.0)
		var root := Vector3(x * 1.05, 0.56 - absf(x) * 0.25, 0.33 - absf(x) * 0.25)
		var lean := x * 0.9 + 0.2 * sin(k * 2.3)
		var flick := Vector3(-1.0 if x < 0.0 else 1.0, 0.0, 0.0)
		if k == 2:
			flick = Vector3(-1.0, 0.0, 0.0)
		_lock_piece(root, Vector3(lean, -1.0, 0.45), 0.36 + 0.04 * cos(k * 1.3), 0.21, flick,
			hair.darkened(0.25) if k % 2 == 1 else hair, _wavy)


## Colita alta: pelo pegado a la cabeza hasta las orejas y la nuca, flequillo
## de costado que cruza la frente y una colita gruesa atada arriba atrás que
## sube un poco y cae en curva hasta los hombros (se balancea con el pelo).
func _high_ponytail(hair: Color) -> void:
	if _ponytail_meshes.is_empty():
		_ponytail_meshes = [
			_make_hair_shell(PONY_CENTER, PONY_RADII, 1.0, 1.9, 2.15, false),
			_make_hair_shell(PONY_CENTER, PONY_RADII, 1.0, 1.9, 2.15, true),
			_make_tube(PONY_PATH, PONY_WIDTH),
		]
		for x0 in [-0.32, -0.12, 0.12, 0.32]:
			var path := []
			var widths := []
			for k in 6:
				var u := k / 5.0
				# Del borde de adelante hacia donde se ata la colita.
				var d := Vector3(x0 * (1.0 - u) * 1.4, 0.55 + 0.4 * sin(u * PI * 0.5), 0.75 * (1.0 - u) - 0.55 * u)
				path.append(PONY_CENTER + _on_ellipsoid(PONY_RADII, d.normalized(), 0.008))
				widths.append(0.011 * sin(maxf(u, 0.08) * PI))
			_ponytail_meshes.append(_make_tube(path, widths))
	_piece(_ponytail_meshes[0], Vector3.ZERO, Vector3.ONE, hair)
	_piece(_ponytail_meshes[1], Vector3.ZERO, Vector3.ONE, hair.darkened(0.35), false)
	_piece(_ponytail_meshes[2], Vector3.ZERO, Vector3.ONE, hair)
	# Rayas de peinado: de la frente hacia la colita (así no parece un casco).
	for line in _ponytail_meshes.slice(3):
		_piece(line, Vector3.ZERO, Vector3.ONE, hair.darkened(0.3), false)
	# Gomita.
	var tie: Vector3 = PONY_PATH[0].lerp(PONY_PATH[1], 0.5)
	_piece(_ring_thick, tie, Vector3(0.13, 0.16, 0.13), Color("#ff6f61"), true,
		_align_y(PONY_PATH[1] - PONY_PATH[0]))
	# Flequillo de costado: una sola pieza que cruza la frente, más baja del
	# lado izquierdo (de quien mira) y con la punta en la sien.
	_extruded(PackedVector2Array(PONY_FRINGE), 0.0, 0.05, func(_p: Vector2) -> Color: return hair, true)
	_extruded(PackedVector2Array(PONY_FRINGE_LINE), 0.052, 0.006,
		func(_p: Vector2) -> Color: return hair.darkened(0.3), false)


const PONY_CENTER := Vector3(0.0, 0.14, -0.05)
const PONY_RADII := Vector3(0.56, 0.6, 0.53)
## Camino de la colita (desde donde se ata) y su grosor en cada punto.
const PONY_PATH := [
	Vector3(0.0, 0.62, -0.36), Vector3(0.02, 0.74, -0.52), Vector3(0.1, 0.72, -0.72),
	Vector3(0.2, 0.55, -0.84), Vector3(0.28, 0.3, -0.86), Vector3(0.3, 0.06, -0.8),
	Vector3(0.27, -0.14, -0.72), Vector3(0.2, -0.28, -0.66),
]
const PONY_WIDTH := [0.11, 0.13, 0.17, 0.19, 0.18, 0.15, 0.09, 0.0]
## Flequillo de costado (x, y sobre la cara).
const PONY_FRINGE := [
	Vector2(-0.42, 0.42), Vector2(-0.34, 0.5), Vector2(-0.1, 0.53), Vector2(0.22, 0.5), Vector2(0.4, 0.42),
	Vector2(0.42, 0.34), Vector2(0.3, 0.39), Vector2(0.1, 0.4), Vector2(-0.12, 0.35), Vector2(-0.3, 0.29),
	Vector2(-0.43, 0.27),
]
## Raya que marca el mechón del flequillo.
const PONY_FRINGE_LINE := [
	Vector2(0.18, 0.52), Vector2(0.2, 0.505), Vector2(-0.14, 0.38), Vector2(-0.3, 0.3), Vector2(-0.31, 0.315),
	Vector2(-0.15, 0.4),
]

var _ponytail_meshes: Array = []


## Cáscara de pelo lisa sobre la cabeza: baja hasta `hem_front` en la frente,
## `hem_side` a los costados y `hem_back` atrás (ángulos desde la coronilla).
## `inner`: la cara de adentro (más oscura, se ve por debajo del borde).
static func _make_hair_shell(center: Vector3, radii: Vector3, hem_front: float, hem_side: float,
		hem_back: float, inner: bool) -> ArrayMesh:
	var cols := 64
	var rows := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cols:
		var th := c * TAU / cols
		var f := cos(th)
		var hem := lerpf(hem_side, hem_front, pow(maxf(f, 0.0), 1.3)) if f >= 0.0 \
			else lerpf(hem_side, hem_back, pow(-f, 1.3))
		for r in rows + 1:
			var t := r / float(rows)
			var ph := hem * t
			var d := Vector3(sin(th) * sin(ph), cos(ph), cos(th) * sin(ph))
			# El borde se mete un poquito hacia la cabeza (no queda como casco).
			var tuck := 1.0 - 0.04 * pow(t, 6.0)
			st.add_vertex(center + d * radii * (tuck - (0.04 if inner else 0.0)))
	for c in cols:
		var c2 := (c + 1) % cols
		for r in rows:
			var a := c * (rows + 1) + r
			var b := c2 * (rows + 1) + r
			if inner:
				st.add_index(a); st.add_index(a + 1); st.add_index(b)
				st.add_index(b); st.add_index(a + 1); st.add_index(b + 1)
			else:
				st.add_index(a); st.add_index(b); st.add_index(a + 1)
				st.add_index(b); st.add_index(b + 1); st.add_index(a + 1)
	st.generate_normals()
	return st.commit()


## Tubo suave que sigue `path` con el grosor `widths` en cada punto (curva
## Catmull-Rom, así no se ven quiebres). Cerrado en las puntas.
static func _make_tube(path: Array, widths: Array) -> ArrayMesh:
	var samples: Array[Vector3] = []
	var ws: Array[float] = []
	var steps := 5
	for i in path.size() - 1:
		var p0: Vector3 = path[maxi(i - 1, 0)]
		var p1: Vector3 = path[i]
		var p2: Vector3 = path[i + 1]
		var p3: Vector3 = path[mini(i + 2, path.size() - 1)]
		for k in steps:
			var t := k / float(steps)
			samples.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
			ws.append(lerpf(widths[i], widths[i + 1], t))
	samples.append(path[path.size() - 1])
	ws.append(widths[widths.size() - 1])
	var sides := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3.RIGHT
	for i in samples.size():
		var fwd := (samples[mini(i + 1, samples.size() - 1)] - samples[maxi(i - 1, 0)]).normalized()
		var side := fwd.cross(normal).normalized()
		normal = side.cross(fwd).normalized()
		for j in sides:
			var a := j * TAU / sides
			# Un poco chata (de costado es más finita).
			st.add_vertex(samples[i] + (normal * cos(a) * 0.8 + side * sin(a)) * ws[i])
	for i in samples.size() - 1:
		for j in sides:
			var a := i * sides + j
			var b := i * sides + (j + 1) % sides
			st.add_index(a); st.add_index(a + sides); st.add_index(b)
			st.add_index(b); st.add_index(a + sides); st.add_index(b + sides)
	# Tapa de la base (la punta ya termina en grosor 0).
	var cap := samples.size() * sides
	st.add_vertex(samples[0])
	for j in sides:
		st.add_index(cap); st.add_index(j); st.add_index((j + 1) % sides)
	st.generate_normals()
	return st.commit()


## Melena ondulada hasta los hombros: raya al costado, flequillo barrido que
## enmarca la cara y mechones gruesos que caen ondulando y se abren en la punta.
func _wavy_bob(hair: Color) -> void:
	_bob_build_meshes()
	# Lo que se balancea: la parte de abajo, hecha solo de mechones (por fuera
	# del color del pelo, con contorno; por dentro más oscuros).
	for i in range(2, _bob_meshes.size(), 3):
		_piece(_bob_meshes[i], Vector3.ZERO, Vector3.ONE, hair, false)
		_piece(_bob_meshes[i + 1], Vector3.ZERO, Vector3.ONE, hair)
		_piece(_bob_meshes[i + 2], Vector3.ZERO, Vector3.ONE, hair.darkened(0.35), false)
	for edge in _bob_edges:
		_piece(edge, Vector3.ZERO, Vector3.ONE, BLACK, false)


## Parte de arriba de la melena (fija a la cabeza): la cáscara y el flequillo
## grande que cruza la frente en curva, más un mechón del otro lado.
func _wavy_bob_top(hair: Color) -> void:
	_bob_build_meshes()
	_piece(_bob_meshes[0], Vector3.ZERO, Vector3.ONE, hair)
	_piece(_bob_meshes[1], Vector3.ZERO, Vector3.ONE, hair.darkened(0.35), false)
	_piece(_bob_top_meshes[0], Vector3.ZERO, Vector3.ONE, hair)
	# (Sin rayas arriba: cerca del sombrero no lleva líneas.)
	# Más afuera cuanto más arriba: así sale de abajo del borde del pelo y cae
	# sobre la frente (si no, queda tapado por la cáscara).
	var fringe := PackedVector2Array(BOB_FRINGE)
	fringe.reverse()
	_extruded(fringe, 0.03, 0.05, func(_p: Vector2) -> Color: return hair, true, 0.15)
	_extruded(PackedVector2Array(BOB_SIDE_LOCK), 0.0, 0.05, func(_p: Vector2) -> Color: return hair, true)
	_extruded(PackedVector2Array(BOB_FRINGE_LINE), 0.082, 0.006,
		func(_p: Vector2) -> Color: return hair.darkened(0.3), false, 0.15)
	# Raya del peinado: de la frente hacia la coronilla.
	var part := []
	var widths := []
	for k in 6:
		var u := k / 5.0
		var d := Vector3(0.28 * (1.0 - u) + 0.1 * u, 0.55 + 0.45 * u, 0.8 * (1.0 - u) - 0.3 * u).normalized()
		part.append(BOB_CENTER + _on_ellipsoid(BOB_RADII, d, 0.012))
		widths.append(0.012 * sin(lerpf(0.1, 0.9, u) * PI))
	_piece(_make_tube(part, widths), Vector3.ZERO, Vector3.ONE, hair.darkened(0.3), false)


const BOB_LINES := 9
## Desde qué parte del largo (0..1) el mechón va suelto y lleva contorno.
const BOB_LOOSE := 0.5
## Mechones de la parte de abajo de la melena.
const BOB_LOCKS := 15


## Parte de arriba de la cortina (de la coronilla a las orejas) y sus rayas:
## van con la cabeza, no se balancean.
var _bob_top_meshes: Array = []
## Contorno de los bordes de cada mechón de abajo.
var _bob_edges: Array = []


func _bob_build_meshes() -> void:
	if _bob_top_meshes.is_empty():
		_bob_top_meshes = [_make_bob_curtain(false, -BOB_TOP, 0.02)]
		for i in BOB_LINES:
			var u := lerpf(0.12, 0.88, i / float(BOB_LINES - 1)) + 0.02 * sin(i * 3.1)
			var path := []
			var widths := []
			for k in 5:
				var t := lerpf(-0.5, 0.02, k / 4.0)
				path.append(_bob_point(u, t, 0.012))
				widths.append(0.012 * sin(maxf(k / 4.0, 0.1) * PI * 0.5 + 0.2))
			_bob_top_meshes.append(_make_tube(path, widths))
	if not _bob_meshes.is_empty():
		return
	_bob_meshes = [
		_make_hair_shell(BOB_CENTER, BOB_RADII, 0.85, 1.75, 1.95, false),
		_make_hair_shell(BOB_CENTER, BOB_RADII, 0.85, 1.75, 1.95, true),
	]
	# Parte de abajo: mechones anchos arriba (se superponen y forman una sola
	# masa) que se afinan hasta una punta, cada uno con su largo y su onda.
	for i in BOB_LOCKS:
		var h := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var uc := (i + 0.5) / float(BOB_LOCKS)
		var du := 1.15 / float(BOB_LOCKS)
		var tend := 0.88 + 0.22 * h
		var out := 0.014 if i % 2 == 1 else 0.0
		# Arriba (se junta con el resto del pelo, sin contorno), abajo (suelto,
		# con contorno) y la cara de adentro.
		_bob_meshes.append(_make_bob_lock(uc, du, tend, out, false, 0.0, BOB_LOOSE + 0.04))
		_bob_meshes.append(_make_bob_lock(uc, du, tend, out, false, BOB_LOOSE, 1.0))
		_bob_meshes.append(_make_bob_lock(uc, du, tend, out, true))
		# Contorno de los dos bordes del mechón en la parte suelta (las puntas).
		for side in [-1.0, 1.0]:
			var path := []
			var widths := []
			for k in 11:
				var f := k / 10.0
				var w := du * (1.0 - 0.94 * pow(f, 2.6))
				var wave := 0.018 * f * sin(f * PI * 2.2 + uc * 23.0)
				var u := clampf(uc + side * w * 0.97 + wave, 0.0, 1.0)
				path.append(_bob_point(u, tend * f, out + 0.008))
				# Solo donde el mechón ya va suelto (abajo): arriba se junta con
				# el resto del pelo y ahí no lleva línea.
				widths.append(0.011 * (1.0 - 0.6 * f) * smoothstep(BOB_LOOSE, BOB_LOOSE + 0.15, f))
			_bob_edges.append(_make_tube(path, widths))


const BOB_CENTER := Vector3(0.0, 0.14, -0.05)
const BOB_RADII := Vector3(0.57, 0.6, 0.54)
## Flequillo grande: nace en la raya (a la derecha de quien mira), cruza la
## frente en curva y cae por la sien hasta el cachete, terminando en punta.
const BOB_FRINGE := [
	# Borde de arriba (dentro de la frente; más arriba ya está la cáscara del
	# pelo), de derecha a izquierda.
	Vector2(0.26, 0.44), Vector2(0.14, 0.49), Vector2(0.0, 0.5), Vector2(-0.14, 0.49), Vector2(-0.26, 0.44),
	Vector2(-0.42, 0.3), Vector2(-0.5, 0.12),
	# Punta larga en la sien y, de izquierda a derecha, el flequillo en puntas
	# que cae sobre la frente hasta arriba de los ojos.
	Vector2(-0.5, -0.06), Vector2(-0.43, 0.12), Vector2(-0.34, 0.24), Vector2(-0.27, 0.27),
	Vector2(-0.2, 0.22), Vector2(-0.12, 0.28), Vector2(-0.03, 0.31), Vector2(0.05, 0.25), Vector2(0.13, 0.32),
	Vector2(0.21, 0.35), Vector2(0.28, 0.31), Vector2(0.33, 0.38),
]
## Mechón del otro lado de la raya: baja enmarcando la cara.
const BOB_SIDE_LOCK := [
	Vector2(0.17, 0.56), Vector2(0.38, 0.47), Vector2(0.49, 0.28), Vector2(0.5, 0.06), Vector2(0.45, 0.16),
	Vector2(0.39, 0.33), Vector2(0.28, 0.44),
]
## Raya que marca el mechón del flequillo.
const BOB_FRINGE_LINE := [
	Vector2(0.12, 0.53), Vector2(0.14, 0.51), Vector2(-0.12, 0.47), Vector2(-0.36, 0.33), Vector2(-0.44, 0.16),
	Vector2(-0.43, 0.17), Vector2(-0.34, 0.35), Vector2(-0.12, 0.49),
]
var _bob_meshes: Array = []


## Punto de la cortina de la melena: `u` de un costado de la cara al otro
## (por atrás), `t` de arriba (0) a la punta (1); `out` hacia afuera.
static func _bob_point(u: float, t: float, out: float) -> Vector3:
	var th := PI + lerpf(-2.3, 2.3, u)
	var front := maxf(cos(th), 0.0)
	# Abajo: más corto adelante (enmarca la cara), ondas en el borde.
	var bottom := lerpf(-0.82, -0.62, pow(front, 0.8)) + 0.06 * absf(sin(u * PI * 8.0))
	if t < 0.0:
		# Arriba (t < 0): nace en la coronilla siguiendo la cabeza, así el pelo
		# es uno solo de arriba abajo (se ve bien sin sombrero).
		var s := clampf(-t / BOB_TOP, 0.0, 1.0)
		var y_top := lerpf(0.32, 0.7, s)
		var low := _bob_point(u, 0.0, out)
		var k := sqrt(maxf(0.0, 1.0 - pow((y_top - BOB_CENTER.y) / (BOB_RADII.y * 1.03), 2.0)))
		var r_head := BOB_RADII.x * 1.03 * k + 0.012 * sin(u * PI * 16.0) * (1.0 - s) + out
		var head := BOB_CENTER * Vector3(1.0, 0.0, 1.0) + Vector3(sin(th) * r_head, y_top, cos(th) * r_head * 0.95)
		return low.lerp(head, smoothstep(0.0, 1.0, s)) if s < 1.0 else head
	var y := lerpf(0.32, bottom, t)
	# Radio: el de la cabeza arriba, y se abre al bajar.
	var rad := 0.6 + 0.14 * t * t + 0.045 * sin(t * PI * 2.0 + u * 9.0)
	# Mechones: surcos a lo largo (más marcados abajo) que ondulan al caer.
	rad += 0.035 * (0.3 + t) * sin(u * PI * 16.0 + t * 3.0)
	# Las puntas se abren para afuera.
	rad += 0.1 * pow(t, 4.0)
	# Los costados de la cara se meten un poco.
	rad -= 0.08 * pow(front, 2.0) * (1.0 - t)
	rad += out
	# Ondas de costado al bajar (el pelo no cae recto como una tela dura).
	th += 0.07 * t * sin(t * PI * 2.0 + u * 11.0)
	return BOB_CENTER * Vector3(1.0, 0.0, 1.0) + Vector3(sin(th) * rad * 0.97, y, cos(th) * rad * 0.92)


## Un mechón de la melena: una hoja que sigue la cortina (`_bob_point`)
## alrededor de `uc`, de ancho `du` arriba, que se afina hasta una punta en
## `tend` y ondula al caer. Un poco abombado en el medio (así el contorno marca
## la separación entre mechones). `inner`: la cara de adentro (más oscura).
static func _make_bob_lock(
	uc: float, du: float, tend: float, out: float, inner: bool, f0: float = 0.0, f1: float = 1.0
) -> ArrayMesh:
	var cols := 6
	var rows := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := BOB_CENTER * Vector3(1.0, 0.0, 1.0)
	for c in cols + 1:
		var v := lerpf(-1.0, 1.0, c / float(cols))
		for r in rows + 1:
			var f := lerpf(f0, f1, r / float(rows))
			var t := tend * f
			var w := du * (1.0 - 0.94 * pow(f, 2.6))
			var wave := 0.018 * f * sin(f * PI * 2.2 + uc * 23.0)
			var p := _bob_point(clampf(uc + v * w + wave, 0.0, 1.0), t, out + 0.022 * (1.0 - v * v) * (1.0 - f * 0.5))
			if inner:
				p = center + (p - center) * Vector3(0.95, 1.0, 0.95)
			st.add_vertex(p)
	for c in cols:
		for r in rows:
			var a := c * (rows + 1) + r
			var b := (c + 1) * (rows + 1) + r
			if not inner:
				st.add_index(a); st.add_index(b); st.add_index(a + 1)
				st.add_index(b); st.add_index(b + 1); st.add_index(a + 1)
			else:
				st.add_index(a); st.add_index(a + 1); st.add_index(b)
				st.add_index(b); st.add_index(a + 1); st.add_index(b + 1)
	st.generate_normals()
	return st.commit()


## Cuánto sube la cortina por encima de las orejas (en `t` negativo).
const BOB_TOP := 0.6


## Cortina de la melena: sigue la cabeza desde arriba de las orejas hasta los
## hombros (abierta adelante, donde está la cara), ondula hacia abajo y el
## borde de abajo hace ondas, con las puntas que se abren para afuera.
static func _make_bob_curtain(inner: bool, t0: float = -BOB_TOP, t1: float = 1.0) -> ArrayMesh:
	var cols := 60
	var rows := 22
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cols + 1:
		var u := c / float(cols)
		for r in rows + 1:
			# Con t1 < 1 (la parte de arriba), el borde de abajo va en ondas: así
			# el corte con los mechones parece una capa de pelo, no una línea.
			var t_end := t1 + (0.07 * absf(sin(u * PI * 13.0)) if t1 < 0.5 else 0.0)
			var t := lerpf(t0, t_end, r / float(rows))
			var p := _bob_point(u, t, 0.0)
			if inner:
				p = BOB_CENTER * Vector3(1.0, 0.0, 1.0) + (p - BOB_CENTER * Vector3(1.0, 0.0, 1.0)) * Vector3(0.93, 1.0, 0.93)
			st.add_vertex(p)
	for c in cols:
		for r in rows:
			var a := c * (rows + 1) + r
			var b := (c + 1) * (rows + 1) + r
			if not inner:
				st.add_index(a); st.add_index(b); st.add_index(a + 1)
				st.add_index(b); st.add_index(b + 1); st.add_index(a + 1)
			else:
				st.add_index(a); st.add_index(a + 1); st.add_index(b)
				st.add_index(b); st.add_index(a + 1); st.add_index(b + 1)
	st.generate_normals()
	return st.commit()


## Volumen del despeinado (centro y radios), en unidades de cabeza.
const SHAGGY_CENTER := Vector3(0.0, 0.17, -0.06)
const SHAGGY_RADII := Vector3(0.66, 0.68, 0.6)


## Cáscara del despeinado: [por fuera, por dentro].
var _shaggy_shell: Array = []


## Cáscara del despeinado: cubre la cabeza (más ancha que el cráneo) y el borde
## de abajo es una fila de puntas que se abren hacia afuera, más largas a los
## costados y atrás.
static func _make_shaggy_shell(inner: bool) -> ArrayMesh:
	var center := SHAGGY_CENTER
	var radii := SHAGGY_RADII
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
			var flare := lump + (0.02 + 0.08 * tooth) * pow(t, 4.0)
			var p := center + d * radii * (flare - (0.05 if inner else 0.0))
			# Las puntas de los costados se levantan (se curvan para arriba).
			p.y += 0.05 * tooth * pow(t, 6.0)
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
static func _make_lock(bend: float, wave: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var sides := 8
	var pts := []
	for i in rings + 1:
		var t := i / float(rings)
		# Ancho: redondeado en la raíz y afinándose hasta la punta.
		var r := sin(minf(t * 3.0, 1.0) * PI * 0.5) * 0.5 + 0.5
		r *= pow(1.0 - t, 0.9)
		var center := Vector3(bend * t * t * t + wave * sin(PI * t), -1.0 + 2.0 * t, 0.0)
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
func _lock_piece(
	root: Vector3, dir: Vector3, len: float, width: float, bend: Vector3, color: Color, mesh: Mesh = null
) -> void:
	var y := dir.normalized()
	var x := bend - y * bend.dot(y)
	if x.length() < 0.001:
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	_piece(mesh if mesh else _lock, root + y * len * 0.5, Vector3(width, len * 0.5, width), color, true,
		Basis(x, y, z))


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
func _necklace(count: int, size: float, colors: Array, outline: bool = true) -> void:
	for i in count:
		_piece(_sphere, _neck_at(i * TAU / count), Vector3.ONE * size, colors[i % colors.size()], outline)


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
