class_name Rock
extends Node3D
## Roca gris oscura. Chocarla tira al jugador de la tabla.
## (Saltando por encima se esquiva.)

@export var radius: float = 1.8
@export var height: float = 2.4
@export var rock_seed: int = 0

const COLOR := Color(0.32, 0.33, 0.36)


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _build_mesh()
	add_child(mi)


## Parte de la altura que tiene que tapar el agua para que la roca no cuente
## (lo poco que asoma no se llega a ver detrás de la ola).
const HIDDEN_AT := 0.7


## true si el Rider está chocando la roca (cerca y no por encima). Si una ola la
## tapa, no cuenta: no se ve, y el que pasa va por encima del agua.
func is_hitting(rider: Rider, water: Water = null) -> bool:
	var d := Vector2(rider.position.x - position.x, rider.position.z - position.z).length()
	if d >= radius + 0.45 or rider.position.y >= position.y + height * 0.85:
		return false
	return not is_covered(water)


## true si el agua (con las olas) tapa casi toda la roca.
func is_covered(water: Water) -> bool:
	return water != null and water.height_at(position.x, position.z) > position.y + height * HIDDEN_AT


## Lugar fuera de la roca en la dirección del Rider.
func safe_position_for(rider: Rider) -> Vector3:
	var dir := Vector2(rider.position.x - position.x, rider.position.z - position.z)
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized() * (radius + 1.8)
	return Vector3(position.x + dir.x, rider.position.y, position.z + dir.y)


## Esfera deformada al azar (siempre igual para la misma semilla) y aplastada.
func _build_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var s := float(rock_seed) * 1.7
	for i in verts.size():
		var v := verts[i]
		var bump := (
			0.22 * sin(v.x * 3.1 + s) * cos(v.z * 2.7 + s * 0.5)
			+ 0.15 * sin(v.y * 4.3 + s * 1.3)
		)
		v *= 1.0 + bump
		verts[i] = Vector3(v.x * radius, v.y * height * 0.6 + height * 0.25, v.z * radius * 0.9)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	st.set_material(ToonMaterial.make(COLOR, 0.05))
	return st.commit()
