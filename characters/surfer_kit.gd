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
## Punto entre los ojos, en el espacio de la cabeza del modelo.
const FACE_LOCAL := Vector3(0.0, 0.1, 0.45)
## Medio tamaño del pecho y de la cadera del modelo (para ubicar collares y estampados).
const CHEST_RADII := Vector3(0.426, 0.326, 0.276)
const HIPS_RADII := Vector3(0.321, 0.326, 0.246)

var character: Node3D
var head: Node3D
var _parts: Dictionary = {}
var _base: Dictionary = {}
## Partes animadas: nombre -> nodo, con su transformación original.
var _nodes: Dictionary = {}
var _base_xf: Dictionary = {}
## Pose actual (suavizada): parte -> {pos, rot}.
var _pose: Dictionary = {}
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
	var head_group := _group(head, "HeadFeatures")
	features.build_head(head_group, data, data.skin_color())
	var torso := character.find_child("Torso", false, false) as Node3D
	var chest_group := _group(torso, "ChestFeatures")
	chest_group.position = Vector3(0.0, 0.24, 0.0)
	features.build_chest(chest_group, data, CHEST_RADII)
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
	var k := 1.0 if snap else 1.0 - exp(-16.0 * delta)
	for part in target_pose:
		var goal: Dictionary = target_pose[part]
		if not _pose.has(part) or snap:
			_pose[part] = {"pos": goal.pos, "rot": goal.rot}
		else:
			var cur: Dictionary = _pose[part]
			cur.pos = (cur.pos as Vector3).lerp(goal.pos, k)
			cur.rot = (cur.rot as Vector3).lerp(goal.rot, k)
	var target_yaw := STANCE_YAW if SurferAnim.is_stance(state.anim) else FRONT_YAW
	_yaw = target_yaw if snap else lerp_angle(_yaw, target_yaw, 1.0 - exp(-10.0 * delta))
	var root: Dictionary = _pose["root"]
	character.transform = Transform3D(
		Basis(Vector3.UP, _yaw) * Basis.from_euler(root.rot), Vector3(0.0, 0.05, 0.0) + root.pos
	)
	for part in _nodes:
		var node := _nodes[part] as Node3D
		var base: Transform3D = _base_xf[part]
		var pp: Dictionary = _pose.get(part, {"pos": Vector3.ZERO, "rot": Vector3.ZERO})
		node.transform = Transform3D(Basis.from_euler(pp.rot) * base.basis, base.origin + pp.pos)


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
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var mat := inst.mesh.surface_get_material(0) as BaseMaterial3D
		var key := mat.resource_name if mat else "skin"
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
	for c in part.get_children():
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
