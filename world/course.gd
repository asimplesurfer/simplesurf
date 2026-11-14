class_name Course
extends Node3D
## El circuito. Tres mapas (GameSettings.TrackLayout):
## - Isla: un anillo de agua alrededor de una isla circular.
## - Archipiélago: un recorrido con curvas a izquierda y derecha entre varias
##   islas (siempre se ven islas alrededor).
## - El Atolón: afuera y adentro de un anillo de islas, con un volcán al medio.
## Arma las islas, las corcheras que marcan el borde, la meta, los círculos de
## velocidad y las rocas, y cada frame aplica los choques y los límites.

## Archipiélago: puntos de control del recorrido (x, z), en el sentido de la carrera.
const ARCHIPELAGO_PATH := [
	Vector2(0, -110), Vector2(70, -105), Vector2(115, -60), Vector2(100, 0),
	Vector2(130, 55), Vector2(105, 110), Vector2(45, 115), Vector2(10, 75),
	Vector2(-45, 100), Vector2(-105, 95), Vector2(-125, 35), Vector2(-80, -5),
	Vector2(-115, -60), Vector2(-70, -105),
]
## Archipiélago: islas (x, z, radio). Las primeras están pegadas al recorrido
## (adentro del lazo y en las curvas); las últimas, más lejos, de paisaje.
const ARCHIPELAGO_ISLANDS := [
	Vector3(-20, -35, 26), Vector3(45, 40, 22), Vector3(-55, 45, 14), Vector3(65, -30, 12),
	Vector3(175, 0, 30), Vector3(60, 175, 26), Vector3(-25, 140, 14), Vector3(-170, 110, 24),
	Vector3(-190, -20, 28), Vector3(-60, -60, 10), Vector3(-170, -120, 22), Vector3(40, -175, 30),
	Vector3(155, -130, 18), Vector3(160, 140, 16),
	Vector3(-120, 190, 34), Vector3(240, 80, 40), Vector3(250, -90, 30), Vector3(-90, -220, 38),
	Vector3(120, -240, 28), Vector3(-260, 60, 40), Vector3(20, 250, 36),
]

## El Atolón: un anillo de islas de arrecife con una laguna y un volcán en el
## medio. La pista da media vuelta por afuera (mar abierto, olas grandes),
## entra a la laguna por un paso entre islas, rodea el volcán por adentro
## (agua más calma, curvas cerradas) y sale por el otro paso.
const ATOLL_PATH := [
	Vector2(215, 0), Vector2(200, -85), Vector2(150, -160), Vector2(80, -205), Vector2(30, -200), Vector2(5, -158), Vector2(-6, -112), Vector2(-46, -86), Vector2(-76, -55), Vector2(-87, -10), Vector2(-82, 34), Vector2(-57, 74), Vector2(-20, 102), Vector2(-2, 140), Vector2(4, 182), Vector2(40, 207), Vector2(105, 212), Vector2(170, 168), Vector2(208, 88),
]
## Islas del atolón (x, z, radio): la primera es el volcán; después el anillo
## de arrecife (con dos pasos, al norte y al sur), dos islotes en la laguna y
## las islas lejanas del paisaje.
const ATOLL_ISLANDS := [
	Vector3(0, 0, 40), Vector3(43.9, -143.4, 16), Vector3(98.4, -113.2, 21), Vector3(137, -61, 24),
	Vector3(150, 0, 20), Vector3(137, 61, 23), Vector3(98.4, 113.2, 19), Vector3(43.9, 143.4, 16),
	Vector3(-43.9, 143.4, 16), Vector3(-98.4, 113.2, 22), Vector3(-135.9, 63.4, 19), Vector3(-150, 0, 24),
	Vector3(-137, -61, 20), Vector3(-98.4, -113.2, 22), Vector3(-43.9, -143.4, 16), Vector3(58, -38, 9),
	Vector3(66, 40, 8), Vector3(330, 0, 40), Vector3(250, -245, 35), Vector3(-55, -335, 38),
	Vector3(-300, -170, 40), Vector3(-320, 120, 36), Vector3(-110, 325, 35), Vector3(225, 265, 38),
	Vector3(-245, -30, 24),
]

## -1: el mapa elegido en el menú (GameSettings.track_layout).
@export var layout: int = -1

@export var island_radius: float = 45.0
@export var track_radius: float = 82.0
## Mitad del ancho de la pista (m): la pista mide el doble.
@export var half_width: float = 20.0
@export var ring_count: int = 10
@export var rock_count: int = 12
## Separación entre flotadores de las corcheras (m).
@export var float_spacing: float = 2.2
@export var layout_seed: int = 42
## Zona sin obstáculos alrededor de la salida (ángulos, en radianes).
@export var start_clear_from: float = -0.12
@export var start_clear_to: float = 0.45

## Choques con rocas e isla, y círculos de velocidad (los tests lo apagan).
var hazards_enabled: bool = true
## No dejar salir del circuito por afuera.
var bounds_enabled: bool = true

var track: TrackSpace
## La isla principal (en el mapa Isla, la del medio).
var island: Island
var islands: Array[Island] = []
var rings: Array[NitroRing] = []
var rocks: Array[Rock] = []
## Géiseres de la laguna (Atolón).
var geysers: Array[Geyser] = []
## -1: el clima elegido en el menú (GameSettings.weather).
@export var weather: int = -1
## La tormenta, si hay.
var storm: Storm = null

var _buoys: Array[Node3D] = []
## Corcheras: flotadores (MultiMesh) que marcan los bordes de la pista.
var _ropes: Array[MultiMeshInstance3D] = []
## Altura sobre el agua de cada MultiMesh de _ropes.
var _float_offsets: Array[float] = []
## Posición (x, z) de cada flotador de cada MultiMesh de _ropes.
var _float_points: Array[PackedVector2Array] = []
var _water: Water
var _time: float = 0.0


func _ready() -> void:
	add_to_group("course")
	GameSettings.load_settings()
	if layout < 0:
		layout = GameSettings.current_layout()
	_water = get_tree().get_first_node_in_group("water") as Water

	if is_archipelago():
		track = PathTrack.new(PackedVector2Array(ARCHIPELAGO_PATH), half_width)
		ring_count = 14
		rock_count = 16
		for i in ARCHIPELAGO_ISLANDS.size():
			var d: Vector3 = ARCHIPELAGO_ISLANDS[i]
			_add_island(Vector2(d.x, d.y), d.z, i)
	elif is_atoll():
		track = PathTrack.new(PackedVector2Array(ATOLL_PATH), half_width)
		ring_count = 14
		rock_count = 12
		for i in ATOLL_ISLANDS.size():
			var d: Vector3 = ATOLL_ISLANDS[i]
			_add_island(Vector2(d.x, d.y), d.z, i, i == 0)
	else:
		track = TrackSpace.new(track_radius, half_width)
		_add_island(track.center, island_radius, 0)
	island = islands[0]

	if _water:
		var fade: Array[Vector3] = []
		for isl in islands:
			fade.append(Vector3(isl.position.x, isl.position.z, isl.radius + 2.0))
		_water.set_islands(fade)
		if uses_path():
			_water.set_track(Vector2.ZERO, 0.0, 0.0)
		else:
			_water.set_track(track.center, inner_limit(), outer_limit())
	_build_buoys()
	_build_finish_line()
	_place_rings_and_rocks()
	if is_atoll():
		_build_atoll_extras()
	if weather < 0:
		weather = GameSettings.current_weather()
	if weather == GameSettings.Weather.STORM:
		storm = Storm.new()
		storm.name = "Storm"
		add_child(storm)


func is_archipelago() -> bool:
	return layout == GameSettings.TrackLayout.ARCHIPELAGO


func is_atoll() -> bool:
	return layout == GameSettings.TrackLayout.ATOLL


## Mapas con recorrido libre (no el anillo alrededor de la isla).
func uses_path() -> bool:
	return is_archipelago() or is_atoll()


func _add_island(center: Vector2, radius: float, index: int, volcano: bool = false) -> void:
	var isl := Island.new()
	isl.name = "Island%d" % index
	isl.radius = radius
	isl.island_seed = 11 + index * 7
	isl.volcano = volcano
	# Faro solo en las islas grandes (y en la del medio del mapa Isla).
	isl.lighthouse = not volcano and (radius >= 26.0 or not uses_path())
	isl.position = Vector3(center.x, 0.0, center.y)
	add_child(isl)
	islands.append(isl)


## Atolón: géiseres en la laguna, un arco de roca sobre el paso norte y un
## barco pirata hundido.
func _build_atoll_extras() -> void:
	# Géiseres sobre la pista de la laguna (desfasados entre sí).
	var spots := [[Vector2(-78, -42), -5.0], [Vector2(-88, 12), 6.0], [Vector2(-62, 66), -4.0], [Vector2(-30, -98), 4.0]]
	for i in spots.size():
		var loc := track.locate(Vector3(spots[i][0].x, 0.0, spots[i][0].y))
		var pos := track.position_at(loc.x, spots[i][1])
		var g := Geyser.new()
		g.name = "Geyser%d" % i
		g.phase = i * 1.7
		g.position = Vector3(pos.x, 0.0, pos.z)
		add_child(g)
		geysers.append(g)
	# Arco de roca natural sobre el paso norte (se pasa por debajo): piedras
	# facetadas apiladas en semicírculo, cada vez más finas arriba.
	var arch := Node3D.new()
	arch.name = "RockArch"
	arch.position = Vector3(0.0, 0.0, -143.4)
	add_child(arch)
	var stone := ToonMaterial.make(Color(0.5, 0.42, 0.36), 0.12)
	var moss := ToonMaterial.make(Color(0.36, 0.55, 0.3), 0.12)
	var arng := RandomNumberGenerator.new()
	arng.seed = 77
	var steps := 15
	for k in steps + 1:
		var t := float(k) / steps
		var ang := PI * t
		var thick := lerpf(9.0, 5.0, sin(ang))
		var boulder := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = thick
		sm.height = thick * 2.0
		sm.radial_segments = 7
		sm.rings = 4
		sm.material = moss if sin(ang) > 0.93 else stone
		boulder.mesh = sm
		boulder.position = Vector3(cos(ang) * 40.0, sin(ang) * 26.0 - 2.0, arng.randf_range(-1.0, 1.0))
		boulder.rotation = Vector3(arng.randf() * TAU, arng.randf() * TAU, arng.randf() * TAU)
		boulder.scale = Vector3(arng.randf_range(1.0, 1.4), arng.randf_range(0.8, 1.1), arng.randf_range(0.9, 1.2))
		arch.add_child(boulder)
	# Una cascadita de lianas colgando del arco.
	for k in 5:
		var vine := MeshInstance3D.new()
		var vm := CylinderMesh.new()
		vm.top_radius = 0.18
		vm.bottom_radius = 0.1
		vm.height = arng.randf_range(4.0, 8.0)
		vm.material = moss
		vine.mesh = vm
		vine.position = Vector3(-10.0 + k * 5.0 + arng.randf_range(-1.5, 1.5), 22.0 - vm.height * 0.5, arng.randf_range(-2.0, 2.0))
		arch.add_child(vine)
	# Barco pirata hundido en la laguna (de paisaje).
	add_child(_shipwreck(Vector3(96.0, 0.0, 4.0)))


## Un barco viejo medio hundido y ladeado, con el mástil roto y la vela rota.
func _shipwreck(at: Vector3) -> Node3D:
	var ship := Node3D.new()
	ship.name = "Shipwreck"
	ship.position = at
	ship.rotation = Vector3(0.18, 0.7, 0.35)
	ship.scale = Vector3.ONE * 1.5
	var wood := ToonMaterial.make(Color(0.42, 0.27, 0.15), 0.12)
	var hull := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 3.0
	cap.height = 16.0
	cap.material = wood
	hull.mesh = cap
	hull.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.75))
	hull.position.y = -0.8
	ship.add_child(hull)
	var mast := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.35
	cyl.height = 11.0
	cyl.material = wood
	mast.mesh = cyl
	mast.position = Vector3(0.0, 5.0, -1.5)
	mast.rotation.z = 0.25
	ship.add_child(mast)
	var sail := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(5.0, 4.0, 0.1)
	quad.material = ToonMaterial.make(Color(0.92, 0.88, 0.78), 0.08)
	sail.mesh = quad
	sail.position = Vector3(0.6, 7.0, -1.5)
	sail.rotation = Vector3(0.0, 0.3, 0.3)
	ship.add_child(sail)
	var flag := MeshInstance3D.new()
	var fq := BoxMesh.new()
	fq.size = Vector3(1.6, 1.0, 0.05)
	fq.material = ToonMaterial.make(Color(0.08, 0.08, 0.1), 0.0)
	flag.mesh = fq
	flag.position = Vector3(1.9, 10.4, -1.5)
	ship.add_child(flag)
	return ship


## Distancia a la que la orilla de la isla principal tira al jugador.
func island_crash_radius() -> float:
	return island_radius + 2.0


## Borde de afuera de la pista (corchera de afuera).
func outer_limit() -> float:
	return track_radius + half_width


## Borde de adentro de la pista (corchera de adentro, del lado de la isla).
func inner_limit() -> float:
	return track_radius - half_width


func _process(_delta: float) -> void:
	# Boyas y corcheras flotan con el agua. Solo las que están cerca de algún
	# corredor (las lejanas casi no se ven y calcular todas es caro).
	var near: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Node3D
		if r:
			near.append(Vector2(r.position.x, r.position.z))
	for b in _buoys:
		if _is_near(near, b.position.x, b.position.z):
			b.position.y = _water_height(b.position.x, b.position.z)
	for k in _ropes.size():
		var mm := _ropes[k].multimesh
		var y_offset := _float_offsets[k]
		var pts := _float_points[k]
		for i in pts.size():
			var q := pts[i]
			if _is_near(near, q.x, q.y):
				var y := _water_height(q.x, q.y) + y_offset
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(q.x, y, q.y)))


## Lo que afecta al juego (círculos, choques, géiseres, límites) va en pasos
## fijos, igual que la física de los surfistas.
func _physics_process(delta: float) -> void:
	_time += delta
	for ring in rings:
		ring.position.y = _water_height(ring.position.x, ring.position.z) + ring.radius * 0.8
	for node in get_tree().get_nodes_in_group("riders"):
		var rider := node as Rider
		if rider:
			_apply_to_rider(rider)


func _apply_to_rider(rider: Rider) -> void:
	var flat := Vector2(rider.position.x, rider.position.z)

	# Islas: la orilla tira de la tabla.
	if hazards_enabled and not rider.is_fallen():
		for isl in islands:
			var c := Vector2(isl.position.x, isl.position.z)
			var crash_r := isl.radius + 2.0
			var d := flat.distance_to(c)
			if d < crash_r:
				var dir := (flat - c) / d if d > 0.01 else Vector2.RIGHT
				var safe := c + dir * (crash_r + 2.0)
				_crash(rider, Vector3(safe.x, rider.position.y, safe.y))
				return

	# Géiser explotando abajo: sale volando.
	if hazards_enabled and rider.grounded and not rider.is_fallen():
		for g in geysers:
			if g.erupting() and g.covers(rider.position.x, rider.position.z):
				rider.geyser_launch(Geyser.LAUNCH_SPEED)
				break

	# Las corcheras no dejan salir de la pista (por ningún lado).
	if bounds_enabled:
		var loc := track.locate(rider.position)
		var limit := half_width - 0.6
		if absf(loc.y) > limit:
			var p := track.position_at(loc.x, clampf(loc.y, -limit, limit))
			rider.position.x = p.x
			rider.position.z = p.z
			_slide_along_edge(rider, loc, signf(loc.y))

	if not hazards_enabled:
		return

	for rock in rocks:
		if not rider.is_fallen() and rock.is_hitting(rider):
			_crash(rider, _safe_position_beside(rock, rider))
			return

	if not rider.is_fallen():
		for ring in rings:
			ring.try_collect(rider, _time)


## Contra la corchera: se desliza a lo largo de ella. Se le saca solo la parte
## del rumbo que va hacia afuera (sigue avanzando) y pierde un poco de velocidad
## una sola vez al tocarla, no en cada frame.
func _slide_along_edge(rider: Rider, loc: Vector2, side: float) -> void:
	var edge := track.position_at(loc.x, side * half_width)
	var center := track.position_at(loc.x, 0.0)
	var out := Vector2(edge.x - center.x, edge.z - center.z).normalized()
	var f := rider.forward()
	var fwd := Vector2(f.x, f.z)
	var into := fwd.dot(out)
	if into <= 0.0:
		return
	var slide := fwd - out * into
	if slide.length() < 0.05:
		# De frente contra la corchera: seguir en el sentido de la carrera.
		var t := track.tangent_at(loc.x)
		slide = Vector2(t.x, t.z)
	slide = slide.normalized()
	rider.heading = atan2(-slide.x, -slide.y)
	# Pierde velocidad según qué tan de frente pegó (de refilón casi nada).
	rider.speed *= 1.0 - 0.35 * into


## Choque: se cae, queda fuera del obstáculo y mirando en el sentido de la
## carrera (para no volver a chocarlo apenas se levanta).
func _crash(rider: Rider, safe_position: Vector3) -> void:
	rider.crash(safe_position)
	rider.heading = track.heading_at(track.angle_of(rider.position))


## Al lado de la roca, hacia adentro o afuera de la pista (del lado donde estaba
## el Rider). Así, al seguir en el sentido de la carrera, se aleja de la roca.
func _safe_position_beside(rock: Rock, rider: Rider) -> Vector3:
	# Dirección "de costado" de la pista donde está la roca.
	var a := track.angle_of(rock.position)
	var side_dir := track.position_at(a, 1.0) - track.position_at(a, 0.0)
	var radial := Vector2(side_dir.x, side_dir.z).normalized()
	var rel := Vector2(rider.position.x - rock.position.x, rider.position.z - rock.position.z)
	var side := 1.0 if rel.dot(radial) >= 0.0 else -1.0
	var p := Vector2(rock.position.x, rock.position.z) + radial * side * (rock.radius + 2.0)
	return Vector3(p.x, rider.position.y, p.y)


## Distancia a la que todavía se mueven boyas y corcheras (m).
const FLOAT_UPDATE_DISTANCE := 90.0


func _is_near(points: Array[Vector2], x: float, z: float) -> bool:
	for p in points:
		if absf(p.x - x) < FLOAT_UPDATE_DISTANCE and absf(p.y - z) < FLOAT_UPDATE_DISTANCE:
			return true
	return false


func _water_height(x: float, z: float) -> float:
	return _water.height_at(x, z) if _water else 0.0


func _in_start_zone(angle: float) -> bool:
	return angle > start_clear_from and angle < start_clear_to


## Bordes de la pista: una corchera continua a cada lado (flotadores cada
## pocos metros, de dos colores) y boyas grandes cada tanto para verlas de lejos.
func _build_buoys() -> void:
	var yellow := Color(1.0, 0.82, 0.2)
	var red := Color(0.95, 0.28, 0.25)
	# Adentro (derecha del que corre) amarilla; afuera (izquierda) roja.
	_add_rope(-half_width, yellow)
	_add_rope(half_width, red)
	_add_buoy_circle(-half_width, yellow, 24.0)
	_add_buoy_circle(half_width, red, 24.0)


## Largo del borde a esa distancia de la línea central.
func _edge_length(lateral: float) -> float:
	return track.length() * maxf(1.0 + lateral / track.radius, 0.2)


## Corchera: muchos flotadores chicos alternando color y blanco.
func _add_rope(lateral: float, color: Color) -> void:
	var count := int(_edge_length(lateral) / float_spacing)
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.45
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.roughness = 0.8
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var a := TAU * i / count
		var p := track.position_at(a, lateral)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		mm.set_instance_color(i, color if (i / 2) % 2 == 0 else Color(0.97, 0.97, 0.97))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rope"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4.0
	add_child(mmi)
	_ropes.append(mmi)
	_float_offsets.append(0.05)
	_float_points.append(_points_of(mm))


func _add_buoy_circle(lateral: float, color: Color, spacing: float) -> void:
	var count := int(_edge_length(lateral) / spacing)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.35
	base_mesh.bottom_radius = 0.6
	base_mesh.height = 1.6
	base_mesh.radial_segments = 10
	base_mesh.material = ToonMaterial.make(color, 0.04)
	var top_mesh := SphereMesh.new()
	top_mesh.radius = 0.25
	top_mesh.height = 0.5
	top_mesh.radial_segments = 8
	top_mesh.rings = 4
	top_mesh.material = ToonMaterial.make(Color(0.97, 0.97, 0.97), 0.03)
	# Todas las boyas de un borde en dos MultiMesh (base y punta): pocas
	# llamadas de dibujo. Flotan igual que las corcheras.
	var points: Array[Vector3] = []
	for i in count:
		points.append(track.position_at(TAU * i / count, lateral))
	_add_floating_multimesh(base_mesh, points, 0.4, "BuoyBases")
	_add_floating_multimesh(top_mesh, points, 1.2, "BuoyTops")


func _add_floating_multimesh(mesh: Mesh, points: Array[Vector3], y_offset: float, node_name: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i] + Vector3(0.0, y_offset, 0.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4.0
	add_child(mmi)
	_ropes.append(mmi)
	_float_offsets.append(y_offset)
	_float_points.append(_points_of(mm))


func _points_of(mm: MultiMesh) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(mm.instance_count)
	for i in mm.instance_count:
		var o := mm.get_instance_transform(i).origin
		pts[i] = Vector2(o.x, o.z)
	return pts


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
	# Sin sombra: si no, deja una franja oscura enorme justo en la largada.
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	banner.position = (inner + outer) * 0.5 + Vector3(0.0, 9.0, 0.0)
	# El banner va a lo ancho del circuito: mirando en el sentido de la carrera.
	banner.rotation.y = track.heading_at(0.0)
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
	var lane := half_width - 5.0

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
