class_name SandboxWorld
extends Node3D
## Modo libre: mar abierto, sin islas ni pista. A lo lejos hay tres circuitos
## de práctica, cada uno marcado con una torre de su color que se ve de lejos:
##   - Slalom (rojo): puertas de boyas en zigzag, hacia adelante de la largada.
##   - Círculos (celeste): una vuelta de círculos de nitro.
##   - Géiseres (naranja): un campo de géiseres rodeado de boyas.

const SLALOM_START := Vector2(0.0, -110.0)
const SLALOM_GATES := 10
const SLALOM_STEP := 22.0
const RING_CENTER := Vector2(175.0, 30.0)
const RING_RADIUS := 45.0
const RING_COUNT := 14
const GEYSER_CENTER := Vector2(-165.0, 70.0)

const RED := Color(0.95, 0.28, 0.25)
const YELLOW := Color(1.0, 0.85, 0.2)
const CYAN := Color(0.25, 0.9, 1.0)
const ORANGE := Color(1.0, 0.55, 0.15)

var rings: Array[NitroRing] = []
var geysers: Array[Geyser] = []
## Boyas y torres que flotan (siguen la altura del agua).
var floaters: Array[Node3D] = []

var _water: Water
var _time: float = 0.0


func _ready() -> void:
	add_to_group("sandbox_world")
	_water = get_tree().get_first_node_in_group("water") as Water
	if _water:
		var none: Array[Vector3] = []
		_water.set_islands(none)
		_water.set_track(Vector2.ZERO, 0.0, 0.0)
	_build_slalom()
	_build_ring_loop()
	_build_geyser_field()


func _build_slalom() -> void:
	_add_tower(SLALOM_START + Vector2(-9.0, 8.0), RED)
	for i in SLALOM_GATES:
		# Las puertas van en zigzag: hay que ir de un lado al otro.
		var side := -1.0 if i % 2 == 0 else 1.0
		var c := SLALOM_START + Vector2(side * 7.0, -SLALOM_STEP * (i + 1))
		var color := RED if i % 2 == 0 else YELLOW
		_add_buoy(c + Vector2(-4.0, 0.0), color)
		_add_buoy(c + Vector2(4.0, 0.0), color)


func _build_ring_loop() -> void:
	_add_tower(RING_CENTER, CYAN)
	for i in RING_COUNT:
		var a := TAU * i / RING_COUNT
		var p := RING_CENTER + Vector2(cos(a), sin(a)) * RING_RADIUS
		var ring := NitroRing.new()
		ring.name = "Ring%d" % i
		ring.position = Vector3(p.x, 0.0, p.y)
		# De frente al sentido de la vuelta (antihorario visto desde arriba).
		var tangent := Vector2(-sin(a), cos(a))
		ring.rotation.y = atan2(-tangent.x, -tangent.y)
		add_child(ring)
		rings.append(ring)


func _build_geyser_field() -> void:
	_add_tower(GEYSER_CENTER, ORANGE)
	var spots: Array[Vector2] = [Vector2(0.0, -16.0)]
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		spots.append(Vector2(cos(a), sin(a)) * 18.0)
	for k in spots.size():
		var g := Geyser.new()
		g.name = "Geyser%d" % k
		g.phase = k * 0.9
		var p := GEYSER_CENTER + spots[k]
		g.position = Vector3(p.x, 0.0, p.y)
		add_child(g)
		geysers.append(g)
	for k in 16:
		var a := TAU * k / 16.0
		_add_buoy(GEYSER_CENTER + Vector2(cos(a), sin(a)) * 34.0, ORANGE if k % 2 == 0 else Color(0.97, 0.97, 0.97))


func _add_buoy(at: Vector2, color: Color) -> void:
	var buoy := Node3D.new()
	buoy.name = "Buoy"
	buoy.position = Vector3(at.x, 0.0, at.y)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.7
	cyl.height = 1.8
	cyl.radial_segments = 10
	cyl.material = ToonMaterial.make(color, 0.04)
	base.mesh = cyl
	base.position.y = 0.45
	buoy.add_child(base)
	var top := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28
	sph.height = 0.56
	sph.radial_segments = 8
	sph.rings = 4
	sph.material = ToonMaterial.make(Color(0.97, 0.97, 0.97), 0.03)
	top.mesh = sph
	top.position.y = 1.45
	buoy.add_child(top)
	add_child(buoy)
	floaters.append(buoy)


## Torre flotante alta con bandera, para encontrar el circuito de lejos.
func _add_tower(at: Vector2, color: Color) -> void:
	var tower := Node3D.new()
	tower.name = "Tower"
	tower.position = Vector3(at.x, 0.0, at.y)
	var float_mesh := MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 1.4
	base.bottom_radius = 1.8
	base.height = 1.2
	base.material = ToonMaterial.make(Color(0.97, 0.97, 0.97), 0.05)
	float_mesh.mesh = base
	float_mesh.position.y = 0.3
	tower.add_child(float_mesh)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.18
	pm.bottom_radius = 0.28
	pm.height = 14.0
	pm.material = ToonMaterial.make(color, 0.05)
	pole.mesh = pm
	pole.position.y = 7.5
	tower.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.2, 1.9, 0.08)
	var flag_mat := ToonMaterial.make(color, 0.05)
	flag_mat.emission_enabled = true
	flag_mat.emission = color * 0.35
	fm.material = flag_mat
	flag.mesh = fm
	flag.position = Vector3(1.75, 13.4, 0.0)
	tower.add_child(flag)
	add_child(tower)
	floaters.append(tower)


func _process(delta: float) -> void:
	_time += delta
	# Lo que flota sigue al agua (solo lo que está cerca de alguien: de lejos
	# no se nota y ahorra cálculos).
	var near: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Node3D
		if r:
			near.append(Vector2(r.position.x, r.position.z))
	for f in floaters:
		if _is_near(near, f.position.x, f.position.z):
			f.position.y = _water_height(f.position.x, f.position.z)
	for ring in rings:
		if _is_near(near, ring.position.x, ring.position.z):
			ring.position.y = _water_height(ring.position.x, ring.position.z) + ring.radius * 0.8
	for node in get_tree().get_nodes_in_group("riders"):
		var rider := node as Rider
		if rider == null:
			continue
		for ring in rings:
			ring.try_collect(rider, _time)
		if rider.grounded and not rider.is_fallen():
			for g in geysers:
				if g.erupting() and g.covers(rider.position.x, rider.position.z):
					rider.geyser_launch(Geyser.LAUNCH_SPEED)
					break


func _is_near(points: Array[Vector2], x: float, z: float) -> bool:
	for p in points:
		if absf(p.x - x) < 90.0 and absf(p.y - z) < 90.0:
			return true
	return false


func _water_height(x: float, z: float) -> float:
	return _water.height_at(x, z) if _water else 0.0
