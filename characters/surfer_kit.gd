class_name SurferKit
extends RefCounted
## Arma el cuerpo de cualquier personaje con las piezas del surfista original
## (assets/characters/surfista.glb): cráneo, pecho, cintura, hombros, short,
## piernas, pies y puños. Con las barras se deforma (panza, músculos, tamaño de
## cabeza) y los accesorios se eligen: la melena, los anteojos de sol, la sonrisa
## de costado, el collar de perlas y las flores del short son los del modelo; el
## resto (otros pelos, ojos, narices, bocas...) los agrega AvatarFeatures.
##
## Con los valores por defecto (musculoso, cabeza normal, esos accesorios) queda
## exactamente igual al modelo original.
##
## Cada parte que se anima es un nodo; sus piezas se juntan en una sola malla
## por color (pocas llamadas de dibujo). Parado sobre la tabla queda de costado
## (postura de surf) mirando hacia adelante; caído, nadando o festejando, de frente.

const SCENE := preload("res://assets/characters/surfista.glb")
## Pieza del Avatar (las que mueven las animaciones) -> partes del modelo.
const PART_MAP := {
	"head": ["Head"],
	"chest": ["Torso"],
	"hips": ["ShortsHips"],
	"thigh_L": ["SleeveL"],
	"thigh_R": ["SleeveR"],
	"leg_L": ["ThighL", "ShinL"],
	"leg_R": ["ThighR", "ShinR"],
	"foot_L": ["FootL"],
	"foot_R": ["FootR"],
	"hand_L": ["HandL"],
	"hand_R": ["HandR"],
}
const STANCE_YAW := PI / 2.0
const FRONT_YAW := 0.0
## De dónde cuelga el pelo (coronilla) y el collar (cuello), en su parte.
const HAIR_PIVOT := Vector3(0.0, 0.42, -0.05)
const NECK_PIVOT := Vector3(0.0, 0.62, 0.04)
## Resortes de la pose: rigidez y amortiguación (un poco menos que crítica).
const SPRING_K := 240.0
const SPRING_D := 21.0
## Punto entre los ojos, en el espacio de la cabeza del modelo.
const FACE_LOCAL := Vector3(0.0, 0.1, 0.45)
## Medio tamaño del pecho y de la cadera del modelo (para ubicar collares y estampados).
const CHEST_RADII := Vector3(0.426, 0.326, 0.276)
## Grosor del contorno, igual en todo el cuerpo y en todos los accesorios, sea
## cual sea el tamaño de cada parte (como en pixel art: un solo grosor de trazo).
## Se mide en el espacio del personaje: agrandar la panza o la cabeza no lo
## engorda.
const OUTLINE_WIDTH := 0.025
const HIPS_RADII := Vector3(0.321, 0.326, 0.246)

var character: Node3D
var head: Node3D
var _parts: Dictionary = {}
var _base: Dictionary = {}
## Partes animadas: nombre -> nodo, con su transformación original.
var _nodes: Dictionary = {}
var _base_xf: Dictionary = {}
## Pose actual: parte -> {pos, rot, vpos, vrot} (resortes: con velocidad, así
## los movimientos tienen peso, se pasan un poco y vuelven).
var _pose: Dictionary = {}
## Pelo y collar: se mueven solos (con la velocidad, los saltos, los giros).
var hair_rig: Node3D
var necklace_rig: Node3D
var _hair_rot := Vector3.ZERO
var _hair_vel := Vector3.ZERO
var _neck_rot := Vector3.ZERO
var _neck_vel := Vector3.ZERO
var _prev_head := Vector3.ZERO
var _prev_head_vel := Vector3.ZERO
var _prev_chest := Vector3.ZERO
var _prev_chest_vel := Vector3.ZERO
var _has_prev: bool = false
## Piernas (cinemática inversa): puntos de cadera, rodilla y tobillo del modelo.
var _legs: Dictionary = {}
var _yaw: float = STANCE_YAW
var _materials: Dictionary = {}


## Arma el personaje dentro de `parent` según `data`.
func build(parent: Node3D, data: CharacterData, features: AvatarFeatures) -> void:
	var root := SCENE.instantiate()
	character = root.find_child("Character", true, false) as Node3D
	character.get_parent().remove_child(character)
	root.free()
	parent.add_child(character)
	character.basis = Basis(Vector3.UP, _yaw)
	_fist_left_hand()
	_choose_accessories(data)
	_apply_sliders(data)
	_make_materials(data)
	# Pelo y collar del modelo en sus propios nodos (colgando de la coronilla y
	# del cuello), para que se muevan solos.
	var head_node := character.find_child("Head", false, false) as Node3D
	hair_rig = _rig(head_node, "HairRig", HAIR_PIVOT, ["Hair", "HairStrand"])
	var torso_node := character.find_child("Torso", false, false) as Node3D
	necklace_rig = _rig(torso_node, "NecklaceRig", NECK_PIVOT, ["PearlNecklace"])
	_bake(hair_rig)
	_bake(necklace_rig)
	# Juntar las piezas de cada parte animada en una malla por color.
	for id in PART_MAP:
		var nodes: Array[Node3D] = []
		for node_name in PART_MAP[id]:
			var n := character.find_child(node_name, false, false) as Node3D
			if n:
				_bake(n)
				nodes.append(n)
				_base[n] = n.position
				_nodes[node_name] = n
				_base_xf[node_name] = n.transform
		_parts[id] = nodes
	head = character.find_child("Head", false, false) as Node3D
	# Accesorios armados (pelo, ojos, nariz, boca, orejas, collar, estampado).
	features.char_root = character
	var head_group := _group(head, "HeadFeatures")
	var hair_group := _group(hair_rig, "HairFeatures")
	hair_group.position = -HAIR_PIVOT
	features.build_head(head_group, hair_group, data, data.skin_color())
	var chest_group := _group(necklace_rig, "ChestFeatures")
	chest_group.position = Vector3(0.0, 0.24, 0.0) - NECK_PIVOT
	features.build_chest(chest_group, data, CHEST_RADII)
	_setup_legs()
	var hips := character.find_child("ShortsHips", false, false) as Node3D
	features.build_hips(_group(hips, "HipsFeatures"), data, HIPS_RADII)


func free_model() -> void:
	if character and is_instance_valid(character):
		if character.get_parent():
			character.get_parent().remove_child(character)
		character.queue_free()
	character = null
	head = null
	_parts.clear()
	_base.clear()


## Pone al personaje en la pose de la animación (ver SurferAnim), suavizando
## el paso de una pose a otra. `snap` = sin suavizar.
func animate(state: Dictionary, delta: float, snap: bool = false) -> void:
	if character == null:
		return
	var target_pose := SurferAnim.pose(state)
	var dt := clampf(delta, 0.0, 1.0 / 30.0)
	for part in target_pose:
		var goal: Dictionary = target_pose[part]
		if not _pose.has(part) or snap:
			_pose[part] = {"pos": goal.pos, "rot": goal.rot, "vpos": Vector3.ZERO, "vrot": Vector3.ZERO}
			continue
		var cur: Dictionary = _pose[part]
		cur.vpos += ((goal.pos - cur.pos) * SPRING_K - cur.vpos * SPRING_D) * dt
		cur.vrot += ((goal.rot - cur.rot) * SPRING_K - cur.vrot * SPRING_D) * dt
		cur.pos += cur.vpos * dt
		cur.rot += cur.vrot * dt
	var target_yaw := STANCE_YAW if SurferAnim.is_stance(state.anim) else FRONT_YAW
	_yaw = target_yaw if snap else lerp_angle(_yaw, target_yaw, 1.0 - exp(-10.0 * delta))
	var root: Dictionary = _pose["root"]
	character.transform = Transform3D(
		Basis(Vector3.UP, _yaw) * Basis.from_euler(root.rot), Vector3(0.0, 0.05, 0.0) + root.pos
	)
	for part in _nodes:
		if part in ["ThighL", "ThighR", "ShinL", "ShinR", "SleeveL", "SleeveR"]:
			continue
		var node := _nodes[part] as Node3D
		var base: Transform3D = _base_xf[part]
		var pp: Dictionary = _pose.get(part, {"pos": Vector3.ZERO, "rot": Vector3.ZERO})
		node.transform = Transform3D(Basis.from_euler(pp.rot) * base.basis, base.origin + pp.pos)
	_solve_legs()
	_secondary(state, dt, snap)


## Piernas: con la cadera y el pie donde los pone la pose, se calcula dónde
## queda la rodilla (doblándose hacia adelante, como en el modelo) y se
## acomodan muslo, canilla y pierna del short.
func _setup_legs() -> void:
	for side in ["L", "R"]:
		var thigh: Transform3D = _base_xf.get("Thigh" + side, Transform3D())
		var shin: Transform3D = _base_xf.get("Shin" + side, Transform3D())
		var t_ends := _ends(thigh, 0.21)
		var s_ends := _ends(shin, 0.223)
		var hip: Vector3 = t_ends[0]
		var knee: Vector3 = (t_ends[1] + s_ends[0]) * 0.5
		var ankle: Vector3 = s_ends[1]
		var mid := (hip + ankle) * 0.5
		_legs[side] = {
			"hip": hip, "knee": knee, "ankle": ankle,
			"l1": hip.distance_to(knee), "l2": knee.distance_to(ankle),
			"pole": (knee - mid).normalized(),
		}


## Extremos (arriba, abajo) de una parte alargada: su eje Y local, `half` de largo.
func _ends(xf: Transform3D, half: float) -> Array:
	var a := xf.origin + xf.basis.y * half
	var b := xf.origin - xf.basis.y * half
	return [a, b] if a.y >= b.y else [b, a]


func _solve_legs() -> void:
	var hips_off: Vector3 = (_pose.get("ShortsHips", {"pos": Vector3.ZERO}) as Dictionary).pos
	for side in _legs:
		var leg: Dictionary = _legs[side]
		var foot_off: Vector3 = (_pose.get("Foot" + side, {"pos": Vector3.ZERO}) as Dictionary).pos
		var hip: Vector3 = leg.hip + hips_off
		var ankle: Vector3 = leg.ankle + foot_off
		var l1: float = leg.l1
		var l2: float = leg.l2
		var to_ankle := ankle - hip
		var d := clampf(to_ankle.length(), 0.01, l1 + l2 - 0.001)
		var dir := to_ankle.normalized()
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var pole: Vector3 = leg.pole - dir * (leg.pole as Vector3).dot(dir)
		if pole.length() < 0.001:
			pole = Vector3.BACK
		var knee := hip + dir * a + pole.normalized() * h
		# Muslo y pierna del short giran sobre la cadera; la canilla sobre la rodilla.
		var r1 := _rotation_between((leg.knee as Vector3) - leg.hip, knee - hip)
		var r2 := _rotation_between((leg.ankle as Vector3) - leg.knee, (ankle - knee))
		for part in ["Thigh" + side, "Sleeve" + side]:
			if _nodes.has(part):
				var base: Transform3D = _base_xf[part]
				(_nodes[part] as Node3D).transform = Transform3D(r1 * base.basis, hip + r1 * (base.origin - leg.hip))
		if _nodes.has("Shin" + side):
			var base: Transform3D = _base_xf["Shin" + side]
			(_nodes["Shin" + side] as Node3D).transform = Transform3D(r2 * base.basis, knee + r2 * (base.origin - leg.knee))


func _rotation_between(from: Vector3, to: Vector3) -> Basis:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	if axis.length() < 0.00001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), a.angle_to(b))


## Pelo y collar: resortes que reaccionan al movimiento de la cabeza y del
## pecho (se quedan atrás al arrancar, flamean con la velocidad, rebotan en los
## saltos y en los giros).
func _secondary(state: Dictionary, dt: float, snap: bool) -> void:
	if hair_rig == null or not hair_rig.is_inside_tree() or dt <= 0.0:
		return
	var head_pos := head.global_position
	var chest_pos := necklace_rig.global_position
	if not _has_prev or snap:
		_prev_head = head_pos
		_prev_chest = chest_pos
		_prev_head_vel = Vector3.ZERO
		_prev_chest_vel = Vector3.ZERO
		_has_prev = true
		return
	var hv := (head_pos - _prev_head) / dt
	var ha := (hv - _prev_head_vel) / dt
	var cv := (chest_pos - _prev_chest) / dt
	var ca := (cv - _prev_chest_vel) / dt
	_prev_head = head_pos
	_prev_chest = chest_pos
	_prev_head_vel = hv
	_prev_chest_vel = cv
	# Al espacio de la cabeza (sin escala): la velocidad empuja el pelo para
	# atrás (viento) y la aceleración lo sacude.
	var hb := head.global_transform.basis.orthonormalized().inverse()
	var v_local := hb * hv
	var a_local := hb * ha
	var target := Vector3(
		clampf(v_local.z * 0.035 - a_local.z * 0.004 + a_local.y * 0.003, -0.6, 0.6),
		0.0,
		clampf(-v_local.x * 0.035 + a_local.x * 0.004, -0.5, 0.5)
	)
	_hair_vel += ((target - _hair_rot) * 120.0 - _hair_vel * 9.0) * dt
	_hair_rot += _hair_vel * dt
	hair_rig.basis = Basis.from_euler(_hair_rot)
	var tb: Basis = (necklace_rig.get_parent() as Node3D).global_transform.basis.orthonormalized().inverse()
	var cv_local := tb * cv
	var ca_local := tb * ca
	var neck_target := Vector3(
		clampf(cv_local.z * 0.02 - ca_local.z * 0.006 + ca_local.y * 0.004, -0.5, 0.5),
		0.0,
		clampf(-cv_local.x * 0.02 + ca_local.x * 0.006, -0.4, 0.4)
	)
	_neck_vel += ((neck_target - _neck_rot) * 90.0 - _neck_vel * 5.0) * dt
	_neck_rot += _neck_vel * dt
	necklace_rig.basis = Basis.from_euler(_neck_rot)


func face_position() -> Vector3:
	return head.global_transform * FACE_LOCAL


# ---------------------------------------------------------------- armado

## La mano izquierda del modelo señala con el dedo: se cambia por un puño igual
## al de la derecha.
func _fist_left_hand() -> void:
	var left := character.find_child("HandL", false, false) as Node3D
	var right := character.find_child("HandR", false, false) as Node3D
	for c in left.get_children():
		left.remove_child(c)
		c.free()
	for c in right.get_children():
		left.add_child(c.duplicate())
	left.basis = Basis.IDENTITY


## Muestra solo los accesorios del modelo que se eligieron.
func _choose_accessories(data: CharacterData) -> void:
	var keep_hair := data.get_option("hair") == 2
	var keep_glasses := data.get_option("glasses") == 1
	var keep_smirk := data.get_option("mouth") == 2
	var keep_pearls := data.get_option("neck") == 1
	var keep_flowers := data.get_option("shorts_pattern") == 1
	var to_remove: Array[Node] = []
	for n in character.find_children("*", "Node3D", true, false):
		var node_name := String(n.name)
		var remove := false
		if node_name == "Hair" or node_name.begins_with("HairStrand"):
			remove = not keep_hair
		elif node_name.begins_with("Lens") or node_name == "GlassesBridge":
			remove = not keep_glasses
		elif node_name.begins_with("Smirk"):
			remove = not keep_smirk
		elif node_name == "PearlNecklace":
			remove = not keep_pearls
		elif node_name.begins_with("Flower"):
			remove = not keep_flowers
		if remove:
			to_remove.append(n)
	# Se borran al final (borrar un padre ya borra sus hijos de la lista).
	for n in to_remove:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()


## Barras: panza (0 musculoso ... 1 cervecero), músculos y tamaño de cabeza.
func _apply_sliders(data: CharacterData) -> void:
	var w := data.weight
	var m := data.muscle
	var torso := character.find_child("Torso", false, false) as Node3D
	var waist := torso.find_child("Waist", false, false) as Node3D
	var chest := torso.find_child("Chest", false, false) as Node3D
	# Panza: la cintura se hace una panza redonda que sale para adelante.
	waist.scale = Vector3(1.0 + 1.25 * w, 1.0 + 0.45 * w, 1.0 + 1.7 * w)
	waist.position += Vector3(0.0, -0.06 * w, 0.13 * w)
	# Pecho: con músculos más ancho; con panza, más redondo.
	chest.scale = Vector3((0.8 + 0.2 * m) * (1.0 + 0.08 * w), 0.92 + 0.08 * m, 1.0 + 0.3 * w)
	var delt := (0.35 + 0.65 * m) * (1.0 - 0.45 * w)
	for side in ["DeltL", "DeltR"]:
		var d := torso.find_child(side, false, false) as Node3D
		d.scale = Vector3.ONE * delt
		d.position.x *= 0.85 + 0.15 * m
	var lines_visible := m > 0.55 and w < 0.4
	for line in ["PecLineL", "PecLineR", "Sternum", "AbMid"]:
		var l := torso.find_child(line, false, false) as Node3D
		if l and not lines_visible:
			torso.remove_child(l)
			l.free()
	# Collar de perlas: acompaña el ancho del pecho.
	var pearls := torso.find_child("PearlNecklace", false, false) as Node3D
	if pearls:
		pearls.scale = Vector3(chest.scale.x, 1.0, chest.scale.z)
	# Short y piernas: más anchos con la panza.
	var hips := character.find_child("ShortsHips", false, false) as Node3D
	hips.scale = Vector3(1.0 + 0.35 * w, 1.0 + 0.08 * w, 1.0 + 0.45 * w)
	for part in ["SleeveL", "SleeveR", "ThighL", "ThighR"]:
		(character.find_child(part, false, false) as Node3D).scale *= Vector3(1.0 + 0.35 * w, 1.0, 1.0 + 0.35 * w)
	for part in ["ShinL", "ShinR"]:
		(character.find_child(part, false, false) as Node3D).scale *= Vector3(1.0 + 0.2 * w, 1.0, 1.0 + 0.2 * w)
	# Las manos se abren un poco con la panza.
	for part in ["HandL", "HandR"]:
		var hand := character.find_child(part, false, false) as Node3D
		var out := Vector3(hand.position.x, 0.0, hand.position.z).normalized()
		hand.position += out * 0.18 * w
	# Cabeza: tamaño (barra) y forma; se sube para no hundirse en el pecho.
	var s := lerpf(0.72, 1.45, data.head_size)
	var shape := data.head_scale()
	var h := character.find_child("Head", false, false) as Node3D
	h.basis = h.basis * Basis.from_scale(shape * s)
	h.position.y += (s * shape.y - 1.0) * 0.42


func _make_materials(data: CharacterData) -> void:
	var skin := data.skin_color()
	var colors := {
		"skin": skin,
		"skin_line": skin.darkened(0.36),
		"shorts": data.shorts_color(),
		"hair": data.hair_color(),
	}
	for mi in character.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		if m == null or _materials.has(m.resource_name):
			continue
		var copy := m.duplicate() as BaseMaterial3D
		copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if m.resource_name == "outline":
			# Contorno: la malla inflada ya viene dada vuelta (se ve por dentro).
			copy.cull_mode = BaseMaterial3D.CULL_BACK
		if colors.has(m.resource_name):
			copy.albedo_color = colors[m.resource_name]
		_materials[m.resource_name] = copy


## Junta todas las piezas debajo de `part` en una malla (una superficie por color),
## con las posiciones relativas a `part`, y borra las piezas sueltas.
func _bake(part: Node3D) -> void:
	var batches := {}
	# De la parte al personaje (con la escala de las barras: cabeza, panza...).
	var to_char := _relative(part, character).basis
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if _inside_rig(inst, part):
			continue
		var mat := inst.mesh.surface_get_material(0) as BaseMaterial3D
		var key := mat.resource_name if mat else "skin"
		# El contorno del modelo no se usa tal cual (se agrandaría con la pieza):
		# se vuelve a armar abajo a partir de la pieza, con el grosor de siempre.
		if key == "outline":
			continue
		var outlined := _has_outline(inst)
		var xf := _relative(inst, part)
		var nb := xf.basis.inverse().transposed()
		var arrays := inst.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if not batches.has(key):
			batches[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		var b: Array = batches[key]
		var base := (b[0] as PackedVector3Array).size()
		# Espejado (escala negativa): se da vuelta el orden de los triángulos.
		var flip := xf.basis.determinant() < 0.0
		for v in verts:
			b[0].append(xf * v)
		for nrm in normals:
			b[1].append((nb * nrm).normalized())
		if indices.is_empty():
			for i in verts.size():
				indices.append(i)
		for t in range(0, indices.size(), 3):
			if flip:
				b[2].append_array([base + indices[t], base + indices[t + 2], base + indices[t + 1]])
			else:
				b[2].append_array([base + indices[t], base + indices[t + 1], base + indices[t + 2]])
		if outlined:
			if not batches.has("outline"):
				batches["outline"] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
			var ob: Array = batches["outline"]
			var count := verts.size()
			var part_verts := (b[0] as PackedVector3Array).slice(base, base + count)
			var part_normals := (b[1] as PackedVector3Array).slice(base, base + count)
			var part_indices := (b[2] as PackedInt32Array).slice(b[2].size() - indices.size())
			for t in part_indices.size():
				part_indices[t] -= base
			append_hull(ob, part_verts, part_normals, part_indices, to_char, OUTLINE_WIDTH)
	for c in part.get_children():
		if c == hair_rig or c == necklace_rig:
			continue
		part.remove_child(c)
		c.free()
	var mesh := ArrayMesh.new()
	for key in batches:
		var b: Array = batches[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b[0]
		arrays[Mesh.ARRAY_NORMAL] = b[1]
		arrays[Mesh.ARRAY_INDEX] = b[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials.get(key))
	var out := MeshInstance3D.new()
	out.name = "Mesh"
	out.mesh = mesh
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_child(out)


## true si la pieza tenía contorno en el modelo original (una malla "_outline"
## al lado de la "_fill").
func _has_outline(inst: MeshInstance3D) -> bool:
	var n := String(inst.name)
	if not n.ends_with("_fill"):
		return false
	return inst.get_parent().has_node(n.replace("_fill", "_outline"))


## Contorno estilo "casco invertido" de una malla: la misma malla inflada por sus
## normales, con los triángulos dados vuelta (se ve solo por dentro, detrás de la
## pieza). `to_char` lleva del espacio de la malla al del personaje: el inflado
## mide `width` en el personaje, así el trazo es igual de grueso aunque la pieza
## esté estirada o agrandada. Se agrega a `batch` ([verts, normals, indices]).
static func append_hull(
	batch: Array, verts: PackedVector3Array, normals: PackedVector3Array,
	indices: PackedInt32Array, to_char: Basis, width: float
) -> void:
	var inv := to_char.inverse()
	var normal_to_char := inv.transposed()
	var base := (batch[0] as PackedVector3Array).size()
	for i in verts.size():
		var n_char := (normal_to_char * normals[i]).normalized()
		batch[0].append(verts[i] + inv * (n_char * width))
		batch[1].append(normals[i])
	for t in range(0, indices.size(), 3):
		batch[2].append_array([base + indices[t], base + indices[t + 2], base + indices[t + 1]])


## Crea un nodo colgando de `pivot` dentro de `parent` y le pasa las partes
## cuyos nombres empiezan con alguno de `prefixes` (manteniendo su lugar).
func _rig(parent: Node3D, rig_name: String, pivot: Vector3, prefixes: Array) -> Node3D:
	var rig := Node3D.new()
	rig.name = rig_name
	rig.position = pivot
	var moving: Array[Node3D] = []
	for c in parent.get_children():
		for prefix in prefixes:
			if String(c.name).begins_with(prefix):
				moving.append(c)
				break
	parent.add_child(rig)
	for c in moving:
		var xf := c.transform
		parent.remove_child(c)
		rig.add_child(c)
		c.transform = Transform3D(Basis.IDENTITY, -pivot) * xf
	return rig


func _inside_rig(node: Node, part: Node3D) -> bool:
	if part == hair_rig or part == necklace_rig:
		return false
	var n := node.get_parent()
	while n != null and n != part:
		if n == hair_rig or n == necklace_rig:
			return true
		n = n.get_parent()
	return false


## Transformación de `node` vista desde `ancestor`.
func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor and n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _group(parent: Node3D, group_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	parent.add_child(g)
	return g
