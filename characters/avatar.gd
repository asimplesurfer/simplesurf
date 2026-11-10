class_name Avatar
extends Node3D
## El personaje armado con las piezas de AvatarCore: cada pieza es una esfera
## escalada (elipsoide), con color plano sin luces y contorno negro grueso.
## Mira hacia +Z y los pies están en y = 0 (en unidades de AvatarCore; escalar
## el nodo para el tamaño).
##
## Animaciones genéricas: las mismas para cualquier cuerpo. Mueven cada pieza
## desde su lugar de reposo (que depende del peso), así que sirven igual para
## el Musculoso y para el Cervecero. Se elige con `anim` y se ajusta con
## charge / steer / drift_side / effort. Los cambios se suavizan solos.
##
## Ejes del avatar: X a los costados (las piezas _L están en +X), Y arriba,
## Z al frente. Acostado boca abajo, Y apunta hacia adelante y Z hacia abajo.

const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
## Grosor del contorno en unidades del avatar.
const OUTLINE := 0.06

## Animaciones disponibles.
const ANIMS := [
	&"idle",       # parado tranquilo (menú): saluda de vez en cuando
	&"ride",       # sobre la tabla: brazos abiertos para el equilibrio
	&"air",        # en el aire: brazos arriba, piernas recogidas
	&"trick",      # truco: brazos bien abiertos
	&"drift",      # derrape: una mano rozando el agua
	&"flail",      # recién caído: agita los brazos hundiéndose
	&"tread",      # en el agua: se mantiene a flote
	&"climb",      # se sube a la tabla
	&"paddle",     # acostado: rema
	&"pop_up",     # se para de un salto
	&"celebrate",  # festeja
]

var data: CharacterData

## Animación actual (ver ANIMS).
var anim: StringName = &"idle"
## 0..1: cuánto está cargando el salto (se agacha).
var charge: float = 0.0
## -1..1: hacia dónde gira (+1 = a la derecha del surfista).
var steer: float = 0.0
## Lado del derrape (-1 / 1).
var drift_side: int = 1
## 0..1: esfuerzo (remar o patalear más rápido).
var effort: float = 0.0

var _sphere := SphereMesh.new()
var _pieces: Dictionary = {}
var _materials: Dictionary = {}
## Posición de reposo de cada pieza (según el peso).
var _base: Dictionary = {}
## Desplazamiento actual de cada pieza (suavizado).
var _offset: Dictionary = {}
var _time: float = 0.0
var _anim_time: float = 0.0
var _last_anim: StringName = &""
var _eyes: Array[MeshInstance3D] = []


func _init() -> void:
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 20
	_sphere.rings = 10


func _ready() -> void:
	if data == null:
		data = CharacterData.new()
	rebuild()


## Vuelve a calcular las piezas (llamar al cambiar peso o colores).
func rebuild() -> void:
	var parts := AvatarCore.get_avatar(data.weight, data.skin_color(), data.shorts_color())
	for part in parts:
		var id: String = part.id
		var piece: MeshInstance3D = _pieces.get(id)
		if piece == null:
			piece = MeshInstance3D.new()
			piece.name = id
			piece.mesh = _sphere
			add_child(piece)
			_pieces[id] = piece
		var radii: Vector3 = part.radii
		var min_r := minf(radii.x, minf(radii.y, radii.z))
		piece.visible = min_r >= 0.05
		piece.position = part.pos
		piece.scale = radii
		piece.material_override = _material_for(part.color, radii)
		_base[id] = part.pos
		if not _offset.has(id):
			_offset[id] = Vector3.ZERO
	_place_eyes()


## Material plano con contorno. El contorno se infla en el espacio de la esfera
## (antes de escalar), así que se compensa con el tamaño medio de la pieza.
func _material_for(color: Color, radii: Vector3) -> StandardMaterial3D:
	var avg := (radii.x + radii.y + radii.z) / 3.0
	var key := "%s_%.3f" % [color.to_html(), avg]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("outline_width", OUTLINE / maxf(avg, 0.05))
	m.next_pass = outline
	_materials[key] = m
	return m


func _place_eyes() -> void:
	var head: MeshInstance3D = _pieces.get("head")
	if head == null:
		return
	if _eyes.is_empty():
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.07
		eye_mesh.height = 0.14
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color.BLACK
		eye_mesh.material = black
		for i in 2:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			add_child(eye)
			_eyes.append(eye)
	# Sobre el frente de la cabeza (+Z), un poco arriba del centro.
	var r := head.scale
	for i in _eyes.size():
		var side := -1.0 if i == 0 else 1.0
		_eyes[i].position = head.position + Vector3(side * r.x * 0.36, r.y * 0.15, r.z * 0.9)


func _process(delta: float) -> void:
	_time += delta
	if anim != _last_anim:
		_last_anim = anim
		_anim_time = 0.0
	_anim_time += delta

	var target := _target_offsets()
	var k := 1.0 - exp(-14.0 * delta)
	for id in _base:
		var goal: Vector3 = target.get(id, Vector3.ZERO)
		_offset[id] = (_offset[id] as Vector3).lerp(goal, k)
		var piece: MeshInstance3D = _pieces[id]
		piece.position = _base[id] + _offset[id]
	_place_eyes()


## Desplazamiento de cada pieza para la animación actual.
func _target_offsets() -> Dictionary:
	var o := {}
	var t := _anim_time
	match anim:
		&"ride":
			_ride(o)
		&"air":
			_air(o, false)
		&"trick":
			_air(o, true)
		&"drift":
			_ride(o)
			_drift(o)
		&"flail":
			_flail(o, t)
		&"tread":
			_tread(o)
		&"climb":
			_climb(o, t)
		&"paddle":
			_paddle(o)
		&"pop_up":
			_pop_up(o, t)
		&"celebrate":
			_celebrate(o)
		_:
			_idle(o)
	if charge > 0.0:
		_crouch(o, charge)
	return o


func _add(o: Dictionary, id: String, v: Vector3) -> void:
	o[id] = o.get(id, Vector3.ZERO) + v


## Mueve todo el torso (cabeza, pecho, panza, hombros, cadera).
func _torso(o: Dictionary, v: Vector3) -> void:
	for id in ["head", "chest", "belly", "hips", "delt_L", "delt_R"]:
		_add(o, id, v)


## Lleva una mano a una altura relativa a la cabeza (para cualquier cuerpo).
func _hand_to_head(o: Dictionary, id: String, above: float, out: float, forward: float) -> void:
	var base: Vector3 = _base[id]
	var head: Vector3 = _base["head"]
	var side := 1.0 if id.ends_with("_L") else -1.0
	_add(o, id, Vector3(side * out, head.y + above - base.y, forward))


func _idle(o: Dictionary) -> void:
	var breath := sin(_time * 1.8) * 0.02
	_torso(o, Vector3(0.0, breath, 0.0))
	_add(o, "hand_L", Vector3(0.0, sin(_time * 2.4) * 0.05, 0.0))
	# Saluda con la mano derecha cada tanto.
	var cycle := fmod(_time, 5.0)
	if cycle < 1.6:
		var w := sin(cycle / 1.6 * PI)
		_hand_to_head(o, "hand_R", 0.15 * w, 0.1 + sin(_time * 12.0) * 0.12 * w, 0.0)
		o["hand_R"] = (o["hand_R"] as Vector3) * w
	else:
		_add(o, "hand_R", Vector3(0.0, sin(_time * 2.4 + 1.3) * 0.05, 0.0))


func _ride(o: Dictionary) -> void:
	var bob := sin(_time * 3.0) * 0.03
	# Rodillas un poco flexionadas y un leve rebote.
	_torso(o, Vector3(0.0, -0.08 + bob, 0.0))
	_add(o, "leg_L", Vector3(0.0, -0.04 + bob * 0.5, 0.0))
	_add(o, "leg_R", Vector3(0.0, -0.04 + bob * 0.5, 0.0))
	# Brazos abiertos para el equilibrio. Al girar a la derecha (steer > 0), la
	# mano de afuera de la curva sube y la de adentro baja.
	# (El avatar mira al revés que el Rider: su _R queda del lado derecho del surfista.)
	_add(o, "hand_L", Vector3(0.14, -0.22 + steer * 0.25 + bob, 0.0))
	_add(o, "hand_R", Vector3(-0.14, -0.22 - steer * 0.25 + bob, 0.0))


func _air(o: Dictionary, trick: bool) -> void:
	var wiggle := sin(_time * 7.0) * 0.05
	for id in ["foot_L", "foot_R"]:
		_add(o, id, Vector3(0.0, 0.3, 0.12))
	for id in ["leg_L", "leg_R"]:
		_add(o, id, Vector3(0.0, 0.16, 0.06))
	if trick:
		_add(o, "hand_L", Vector3(0.45, 0.25 + wiggle, 0.0))
		_add(o, "hand_R", Vector3(-0.45, 0.25 - wiggle, 0.0))
	else:
		_hand_to_head(o, "hand_L", 0.0 + wiggle, 0.15, 0.1)
		_hand_to_head(o, "hand_R", 0.0 - wiggle, 0.15, 0.1)


func _drift(o: Dictionary) -> void:
	# La mano del lado del derrape roza el agua; la otra arriba.
	var low := "hand_R" if drift_side > 0 else "hand_L"
	var high := "hand_L" if drift_side > 0 else "hand_R"
	var s := -1.0 if drift_side > 0 else 1.0
	o[low] = Vector3(s * 0.3, -1.0, -0.15)
	o[high] = Vector3(-s * 0.2, 0.35, 0.0)
	_torso(o, Vector3(0.0, -0.12, 0.0))


func _flail(o: Dictionary, t: float) -> void:
	# Agita los brazos por encima de la cabeza, como hundiéndose.
	var speed := 13.0 + effort * 6.0
	_hand_to_head(o, "hand_L", 0.3 + sin(t * speed) * 0.3, 0.1 + sin(t * speed * 0.8) * 0.25, 0.1)
	_hand_to_head(o, "hand_R", 0.3 + sin(t * speed + 2.0) * 0.3, 0.1 + sin(t * speed * 0.8 + 1.0) * 0.25, 0.1)
	_kick(o, 14.0, 0.15)
	_torso(o, Vector3(0.0, sin(t * 6.0) * 0.06, 0.0))


func _tread(o: Dictionary) -> void:
	# Se mantiene a flote: manos en círculos a la altura del pecho.
	var ph := _time * (3.5 + effort * 6.0)
	_add(o, "hand_L", Vector3(-0.1 + cos(ph) * 0.18, 0.05, sin(ph) * 0.22))
	_add(o, "hand_R", Vector3(0.1 - cos(ph) * 0.18, 0.05, sin(ph + PI) * 0.22))
	_kick(o, 6.0 + effort * 8.0, 0.1)


func _climb(o: Dictionary, t: float) -> void:
	# Estira los brazos hacia la tabla y se trepa pataleando.
	var p := clampf(t / 0.45, 0.0, 1.0)
	var reach := sin(p * PI)
	_hand_to_head(o, "hand_L", 0.2 + 0.3 * reach, 0.0, 0.3 * reach)
	_hand_to_head(o, "hand_R", 0.2 + 0.3 * reach, 0.0, 0.3 * reach)
	_kick(o, 16.0, 0.2)


func _paddle(o: Dictionary) -> void:
	# Acostado: remada alternada. En reposo, la mano va de atrás (-Y) a adelante
	# (+Y) por arriba (-Z, fuera del agua) y vuelve por abajo (+Z, en el agua).
	var ph := _time * (3.0 + effort * 9.0)
	for i in 2:
		var id := "hand_L" if i == 0 else "hand_R"
		var a := ph + PI * i
		var inward := -0.25 if i == 0 else 0.25
		_add(o, id, Vector3(inward, -cos(a) * 0.5 + 0.35, -sin(a) * 0.35))
	_kick(o, 9.0 + effort * 6.0, 0.12)
	# Cabeza un poco levantada mirando adelante.
	_add(o, "head", Vector3(0.0, 0.04, -0.12))


func _pop_up(o: Dictionary, t: float) -> void:
	# Empuja la tabla con las manos y recoge las piernas.
	var p := clampf(t / 0.3, 0.0, 1.0)
	var push := sin(p * PI)
	_add(o, "hand_L", Vector3(-0.3, -0.6 * push, 0.25))
	_add(o, "hand_R", Vector3(0.3, -0.6 * push, 0.25))
	for id in ["foot_L", "foot_R", "leg_L", "leg_R"]:
		_add(o, id, Vector3(0.0, 0.2 * push, 0.1 * push))


func _celebrate(o: Dictionary) -> void:
	var hop := absf(sin(_time * 6.0)) * 0.12
	_torso(o, Vector3(0.0, hop, 0.0))
	_hand_to_head(o, "hand_L", 0.5 + sin(_time * 10.0) * 0.1, 0.35, 0.0)
	_hand_to_head(o, "hand_R", 0.5 + sin(_time * 10.0 + 2.0) * 0.1, 0.35, 0.0)


func _crouch(o: Dictionary, c: float) -> void:
	_torso(o, Vector3(0.0, -0.35 * c, 0.06 * c))
	_add(o, "leg_L", Vector3(0.06 * c, -0.16 * c, 0.0))
	_add(o, "leg_R", Vector3(-0.06 * c, -0.16 * c, 0.0))
	_add(o, "hand_L", Vector3(0.0, -0.35 * c, 0.25 * c))
	_add(o, "hand_R", Vector3(0.0, -0.35 * c, 0.25 * c))


## Patada alternada de piernas.
func _kick(o: Dictionary, speed: float, amount: float) -> void:
	var k := sin(_time * speed) * amount
	_add(o, "foot_L", Vector3(0.0, 0.0, k))
	_add(o, "foot_R", Vector3(0.0, 0.0, -k))
	_add(o, "leg_L", Vector3(0.0, 0.0, k * 0.5))
	_add(o, "leg_R", Vector3(0.0, 0.0, -k * 0.5))
