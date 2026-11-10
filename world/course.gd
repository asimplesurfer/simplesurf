class_name Course
extends Node3D
## El circuito: una isla circular en el medio y un anillo de agua alrededor.
## Arma la isla, las boyas que marcan el borde, la meta, los círculos de
## velocidad y las rocas, y cada frame aplica los choques y los límites.

@export var island_radius: float = 45.0
@export var track_radius: float = 95.0
@export var half_width: float = 36.0
@export var ring_count: int = 10
@export var rock_count: int = 18
@export var layout_seed: int = 42
## Zona sin obstáculos alrededor de la salida (ángulos, en radianes).
@export var start_clear_from: float = -0.12
@export var start_clear_to: float = 0.45

## Choques con rocas e isla, y círculos de velocidad (los tests lo apagan).
var hazards_enabled: bool = true
## No dejar salir del circuito por afuera.
var bounds_enabled: bool = true

var track: TrackSpace
var island: Island
var rings: Array[NitroRing] = []
var rocks: Array[Rock] = []

var _buoys: Array[Node3D] = []
var _water: Water
var _time: float = 0.0


func _ready() -> void:
	add_to_group("course")
	track = TrackSpace.new(track_radius, half_width)
	_water = get_tree().get_first_node_in_group("water") as Water

	island = Island.new()
	island.name = "Island"
	island.radius = island_radius
	add_child(island)

	if _water:
		_water.set_island(track.center, island_radius + 2.0)
	_build_buoys()
	_build_finish_line()
	_place_rings_and_rocks()


## Distancia a la que la orilla tira al jugador.
func island_crash_radius() -> float:
	return island_radius + 2.0


func outer_limit() -> float:
	return track_radius + half_width + 3.0


func _process(delta: float) -> void:
	_time += delta
	for b in _buoys:
		b.position.y = _water_height(b.position.x, b.position.z)
	for ring in rings:
		ring.position.y = _water_height(ring.position.x, ring.position.z) + ring.radius * 0.8

	for node in get_tree().get_nodes_in_group("riders"):
		var rider := node as Rider
		if rider:
			_apply_to_rider(rider)


func _apply_to_rider(rider: Rider) -> void:
	var flat := Vector2(rider.position.x, rider.position.z) - track.center
	var r := flat.length()

	if bounds_enabled and r > outer_limit():
		var p := track.center + flat.normalized() * outer_limit()
		rider.position.x = p.x
		rider.position.z = p.y
		rider.speed *= 0.97

	if not hazards_enabled:
		return

	if r < island_crash_radius() and not rider.is_fallen():
		var safe := track.center + flat.normalized() * (island_crash_radius() + 2.0)
		_crash(rider, Vector3(safe.x, rider.position.y, safe.y))
		return

	for rock in rocks:
		if not rider.is_fallen() and rock.is_hitting(rider):
			_crash(rider, _safe_position_beside(rock, rider))
			return

	if not rider.is_fallen():
		for ring in rings:
			ring.try_collect(rider, _time)


## Choque: se cae, queda fuera del obstáculo y mirando en el sentido de la
## carrera (para no volver a chocarlo apenas se levanta).
func _crash(rider: Rider, safe_position: Vector3) -> void:
	rider.crash(safe_position)
	rider.heading = track.heading_at(track.angle_of(rider.position))


## Al lado de la roca, hacia adentro o afuera de la pista (del lado donde estaba
## el Rider). Así, al seguir en el sentido de la carrera, se aleja de la roca.
func _safe_position_beside(rock: Rock, rider: Rider) -> Vector3:
	var radial := (Vector2(rock.position.x, rock.position.z) - track.center).normalized()
	var rel := Vector2(rider.position.x - rock.position.x, rider.position.z - rock.position.z)
	var side := 1.0 if rel.dot(radial) >= 0.0 else -1.0
	var p := Vector2(rock.position.x, rock.position.z) + radial * side * (rock.radius + 2.0)
	return Vector3(p.x, rider.position.y, p.y)


func _water_height(x: float, z: float) -> float:
	return _water.height_at(x, z) if _water else 0.0


func _in_start_zone(angle: float) -> bool:
	return angle > start_clear_from and angle < start_clear_to


func _build_buoys() -> void:
	var inner_r := track_radius - half_width - 1.0
	var outer_r := track_radius + half_width + 1.0
	_add_buoy_circle(inner_r, Color(1.0, 0.82, 0.2), 16.0)
	_add_buoy_circle(outer_r, Color(0.95, 0.28, 0.25), 16.0)


func _add_buoy_circle(r: float, color: Color, spacing: float) -> void:
	var count := int(TAU * r / spacing)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.3
	base_mesh.bottom_radius = 0.5
	base_mesh.height = 1.0
	base_mesh.material = ToonMaterial.make(color, 0.04)
	var top_mesh := SphereMesh.new()
	top_mesh.radius = 0.25
	top_mesh.height = 0.5
	top_mesh.material = ToonMaterial.make(Color(0.97, 0.97, 0.97), 0.03)
	for i in count:
		var a := TAU * i / count
		var buoy := Node3D.new()
		var p := track.position_at(a, r - track_radius)
		buoy.position = p
		var base := MeshInstance3D.new()
		base.mesh = base_mesh
		base.position.y = 0.25
		buoy.add_child(base)
		var top := MeshInstance3D.new()
		top.mesh = top_mesh
		top.position.y = 0.85
		buoy.add_child(top)
		add_child(buoy)
		_buoys.append(buoy)


## Meta en el ángulo 0: dos postes y una bandera a cuadros que cruza el circuito.
func _build_finish_line() -> void:
	var inner := track.position_at(0.0, -half_width)
	var outer := track.position_at(0.0, half_width)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.5
	pole_mesh.bottom_radius = 0.6
	pole_mesh.height = 11.0
	pole_mesh.material = ToonMaterial.make(Color(0.95, 0.95, 0.95), 0.06)
	for p in [inner, outer]:
		var pole := MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.position = p + Vector3(0.0, 4.5, 0.0)
		add_child(pole)

	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(inner.distance_to(outer), 2.4, 0.3)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/shaders/checker.gdshader")
	banner_mesh.material = mat
	var banner := MeshInstance3D.new()
	banner.name = "FinishBanner"
	banner.mesh = banner_mesh
	banner.position = (inner + outer) * 0.5 + Vector3(0.0, 9.0, 0.0)
	# El banner va a lo ancho del circuito (dirección radial en ángulo 0 = eje X).
	add_child(banner)

	# Boyas a cuadros sobre el agua marcando la línea.
	var small := SphereMesh.new()
	small.radius = 0.35
	small.height = 0.7
	small.material = mat
	var steps := int(half_width * 2.0 / 4.0)
	for i in steps + 1:
		var buoy := MeshInstance3D.new()
		buoy.mesh = small
		buoy.position = track.position_at(0.0, -half_width + i * 4.0)
		add_child(buoy)
		_buoys.append(buoy)


func _place_rings_and_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var lane := half_width - 7.0

	for i in ring_count:
		var angle := TAU * (i + 0.5) / ring_count + rng.randf_range(-0.15, 0.15)
		angle = wrapf(angle, -PI, PI)
		if _in_start_zone(angle):
			angle += 0.6
		var ring := NitroRing.new()
		ring.position = track.position_at(angle, rng.randf_range(-lane, lane))
		ring.rotation.y = track.heading_at(angle)
		add_child(ring)
		rings.append(ring)

	var placed := 0
	var attempts := 0
	while placed < rock_count and attempts < 500:
		attempts += 1
		var angle := rng.randf_range(-PI, PI)
		if _in_start_zone(angle):
			continue
		var pos := track.position_at(angle, rng.randf_range(-lane, lane))
		if _too_close(pos, 10.0):
			continue
		var rock := Rock.new()
		rock.radius = rng.randf_range(1.4, 2.8)
		rock.height = rock.radius * rng.randf_range(1.0, 1.6)
		rock.rock_seed = placed + 1
		rock.position = pos + Vector3(0.0, -0.6, 0.0)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		add_child(rock)
		rocks.append(rock)
		placed += 1


func _too_close(pos: Vector3, min_distance: float) -> bool:
	for ring in rings:
		if Vector2(ring.position.x - pos.x, ring.position.z - pos.z).length() < min_distance:
			return true
	for rock in rocks:
		if Vector2(rock.position.x - pos.x, rock.position.z - pos.z).length() < min_distance:
			return true
	return false
