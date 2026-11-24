class_name TrickWorld
extends Node3D
## Mapas del modo trucos (ver TrickAttack): mar abierto con olas como en el
## modo libre y algo en el medio. Por ahora hay uno solo: una isla redonda.
## Subirse a la arena tira al surfista (queda afuera, en el agua).
##
## Cada mapa es una entrada de MAPS: agregar uno = agregar una entrada (y, si
## trae algo nuevo, armarlo en `_build_map`).

## id: nombre interno (con él se guardan los récords). radius: radio de la
## isla (m).
const MAPS: Array[Dictionary] = [
	{"id": "isla", "name": "Isla", "radius": 36.0},
]

const SAND_Y := 0.55
const GRASS_Y := 0.85
const SAND_COLOR := Color("f2d8a0")
const GRASS_COLOR := Color("3f7f2c")
## Ancho de la playa, de la orilla al pasto (m).
const BEACH := 7.0
## Distancia de la orilla a la que tira al surfista (la playa entra al agua).
const SHORE := 1.5
## Puntos del contorno de la isla.
const OUTLINE_POINTS := 96

## El mapa que se armó (una entrada de MAPS).
var map: Dictionary = MAPS[0]
## Radio de la isla (m).
var island_radius: float = 36.0
## Contorno de la isla visto desde arriba.
var outline := PackedVector2Array()

var _water: Water
var _rng := RandomNumberGenerator.new()


static func map_names() -> Array[String]:
	var out: Array[String] = []
	for m in MAPS:
		out.append(String(m.name))
	return out


static func map_for(index: int) -> Dictionary:
	return MAPS[clampi(index, 0, MAPS.size() - 1)]


func _ready() -> void:
	add_to_group("trick_world")
	var session := GameSession.of(self)
	var index := session.config.trick_map if session else GameSettings.trick_map
	map = map_for(index)
	_rng.seed = 7
	_build_map()
	_water = GameSession.find_in_scene(self, "water") as Water
	if _water:
		# Sin pista: el agua de todo el mar es igual. La isla apaga las olas
		# grandes cerca de la orilla.
		_water.set_track(Vector2.ZERO, 0.0, 0.0)
		var land: Array[PackedVector2Array] = [outline]
		_water.set_land(land)


func _build_map() -> void:
	island_radius = float(map.radius)
	outline = _circle(island_radius, 0.6)
	var island := Node3D.new()
	island.name = "Island"
	island.add_to_group("island")
	add_child(island)
	var sand := MeshInstance3D.new()
	sand.name = "Sand"
	sand.mesh = BeachMesh.build(outline, _normals(outline), SAND_Y, -1.8, 9.0, SAND_COLOR, 11)
	island.add_child(sand)
	island.add_child(_grass_mesh(_circle(island_radius - BEACH, 0.9)))
	_add_palms(island)


## Un círculo apenas irregular (que no se vea hecho con compás).
func _circle(radius: float, wobble: float) -> PackedVector2Array:
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.9
	var out := PackedVector2Array()
	for i in OUTLINE_POINTS:
		var a := TAU * i / OUTLINE_POINTS
		var r := radius + noise.get_noise_2d(cos(a), sin(a)) * wobble
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## Normal hacia afuera de cada punto (la isla es casi redonda).
func _normals(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p.normalized())
	return out


func _grass_mesh(poly: PackedVector2Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := GRASS_COLOR.darkened(0.12)
	var n := poly.size()
	for i in n:
		var j := (i + 1) % n
		var a0 := Vector3(poly[i].x, GRASS_Y, poly[i].y)
		var b0 := Vector3(poly[j].x, GRASS_Y, poly[j].y)
		var ai := poly[i] + poly[i].normalized() * 0.7
		var bj := poly[j] + poly[j].normalized() * 0.7
		var a1 := Vector3(ai.x, SAND_Y + 0.02, ai.y)
		var b1 := Vector3(bj.x, SAND_Y + 0.02, bj.y)
		for v in [a0, b0, b1, a0, b1, a1]:
			st.set_normal(Vector3.UP)
			st.set_color(side)
			st.add_vertex(v)
	for k in Geometry2D.triangulate_polygon(poly):
		st.set_normal(Vector3.UP)
		st.set_color(GRASS_COLOR)
		st.add_vertex(Vector3(poly[k].x, GRASS_Y, poly[k].y))
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Grass"
	mi.mesh = st.commit()
	return mi


## Palmeras: altas e inclinadas hacia el mar en la orilla del pasto, y más
## chicas y derechas adentro. Unas pocas palmeras modelo repetidas (MultiMesh).
func _add_palms(root: Node3D) -> void:
	var models: Array[Mesh] = []
	for i in 4:
		var h := _rng.randf_range(8.5, 12.0)
		models.append(PalmMesh.build(31 + i, h, lerpf(0.35, 0.9, i / 3.0)))
	var inner: Array[Mesh] = []
	for i in 2:
		inner.append(PalmMesh.build(57 + i, _rng.randf_range(6.5, 9.0), _rng.randf_range(0.0, 0.25), 0.5))
	var lists: Array = []
	for i in models.size() + inner.size():
		lists.append([] as Array[Transform3D])
	# Orilla: una vuelta de palmeras con huecos.
	var ring := island_radius - BEACH - 1.0
	var count := 22
	for k in count:
		if _rng.randf() < 0.25:
			continue
		var a := TAU * (k + _rng.randf_range(-0.3, 0.3)) / count
		var out := Vector2(cos(a), sin(a))
		var p := out * (ring + _rng.randf_range(-1.5, 0.8))
		var dir := out.rotated(_rng.randf_range(-0.5, 0.5))
		lists[_rng.randi() % models.size()].append(_placed(p, dir, _rng.randf_range(0.8, 1.2)))
	# Adentro: unas cuantas más, desparramadas.
	for k in 14:
		var a := _rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * (ring - 5.0)
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		lists[models.size() + _rng.randi() % inner.size()].append(_placed(p, dir, _rng.randf_range(0.8, 1.15)))
	var all: Array[Mesh] = models + inner
	for i in all.size():
		var items: Array[Transform3D] = lists[i]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = all[i]
		mm.instance_count = items.size()
		for j in items.size():
			mm.set_instance_transform(j, items[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Palms%d" % i
		mmi.multimesh = mm
		root.add_child(mmi)


## Una palmera modelo en `p`, inclinada hacia `dir` (los modelos se arman
## inclinados hacia +X).
func _placed(p: Vector2, dir: Vector2, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x)).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(p.x, GRASS_Y - 0.25, p.y))


## Dónde arranca el surfista: en el agua, lejos de la isla y apuntando casi
## hacia ella (la ve adelante, a la derecha); de largo pasa al costado, sin
## chocarla. Devuelve [posición, rumbo].
## Cuánto se desvía del centro de la isla (rad).
const SPAWN_ANGLE := 0.49


func spawn_point(index: int, count: int) -> Array:
	var r := island_radius + 60.0 + (index - (count - 1) * 0.5) * 6.0
	# En +Z: rumbo 0 mira hacia -Z (al centro); se gira un poco hacia -X.
	return [Vector3(0.0, 0.0, r), SPAWN_ANGLE]


## true si (x, z) está sobre la isla (con la playa que entra al agua).
func covers(x: float, z: float) -> bool:
	return Vector2(x, z).length() < island_radius + SHORE


func _physics_process(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group("riders"):
		var rider := node as Rider
		if rider == null or rider.is_fallen() or rider.in_tube():
			continue
		if covers(rider.position.x, rider.position.z):
			# Se subió a la arena: se cae y queda afuera, en el agua.
			var out := Vector2(rider.position.x, rider.position.z)
			out = out.normalized() if out.length() > 0.01 else Vector2.RIGHT
			var safe := out * (island_radius + SHORE + 3.0)
			rider.crash(Vector3(safe.x, rider.position.y, safe.y))
			# Al levantarse sigue de costado a la orilla (para el lado al que
			# iba), no de nuevo contra la isla.
			var f := rider.forward()
			var tangent := Vector2(-out.y, out.x)
			if tangent.dot(Vector2(f.x, f.z)) < 0.0:
				tangent = -tangent
			rider.heading = atan2(-tangent.x, -tangent.y)
