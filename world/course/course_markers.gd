class_name CourseMarkers
extends Node3D
## Lo que marca la pista: una corchera continua a cada lado, boyas grandes cada
## tanto y la meta. Corcheras y boyas flotan con el agua (solo las que están
## cerca de algún corredor: las lejanas casi no se ven y calcularlas es caro).

## Distancia a la que todavía se mueven boyas y corcheras (m).
const FLOAT_UPDATE_DISTANCE := 90.0
## Separación entre flotadores de las corcheras (m).
const FLOAT_SPACING := 2.2

var track: TrackSpace
var half_width: float = 20.0
var float_spacing: float = FLOAT_SPACING

var _buoys: Array[Node3D] = []
## Cuánto puede alejarse una boya o corchera del borde real (m) antes de saltearla.
const EDGE_TOLERANCE := 1.0
## Corcheras: flotadores (MultiMesh) que marcan los bordes de la pista.
var _ropes: Array[MultiMeshInstance3D] = []
## Altura sobre el agua de cada MultiMesh de _ropes.
var _float_offsets: Array[float] = []
## Posición (x, z) de cada flotador de cada MultiMesh de _ropes.
var _float_points: Array[PackedVector2Array] = []
var _water: Water
## Grilla de flotadores (celda -> índices k * ROPE_STRIDE + i), para buscar
## solo los cercanos a cada corredor sin recorrer todos.
var _cells: Dictionary = {}
var _cells_built: bool = false
var _frame: int = 0
## Tamaño de celda de la grilla (m).
const CELL := 30.0
const ROPE_STRIDE := 1000000


func build(p_track: TrackSpace, p_half_width: float, water: Water) -> void:
	track = p_track
	half_width = p_half_width
	_water = water
	_build_buoys()
	_build_finish_line()


func _process(_delta: float) -> void:
	# Boyas y corcheras flotan con el agua. Solo las que están cerca de algún
	# corredor (las lejanas casi no se ven y calcular todas es caro).
	# Solo alrededor de quien tiene pantalla (los bots lejos nadie los ve);
	# sin pantallas (tests), alrededor de todos.
	var near: Array[Vector2] = []
	var all_near: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r:
			all_near.append(Vector2(r.position.x, r.position.z))
			if r.has_view:
				near.append(Vector2(r.position.x, r.position.z))
	if near.is_empty():
		near = all_near
	for b in _buoys:
		if _is_near(near, b.position.x, b.position.z):
			b.position.y = _water_height(b.position.x, b.position.z)
	# Corcheras: cada 2 cuadros (a 30 por segundo el vaivén se ve igual) y solo
	# las celdas cerca de algún corredor.
	_frame += 1
	if _frame % 2 != 0:
		return
	if not _cells_built:
		_build_cells()
	var reach := int(ceil(FLOAT_UPDATE_DISTANCE / CELL))
	var seen := {}
	for p in near:
		var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var key := Vector2i(c.x + dx, c.y + dz)
				if seen.has(key) or not _cells.has(key):
					continue
				seen[key] = true
				for code in (_cells[key] as PackedInt32Array):
					var k := code / ROPE_STRIDE
					var i := code % ROPE_STRIDE
					var q := _float_points[k][i]
					var y := _water_height(q.x, q.y) + _float_offsets[k]
					_ropes[k].multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(q.x, y, q.y)))


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
	# Caminos alternativos: sus bordes, con los mismos colores. Donde se abren
	# de la principal, cada corchera se corta sola (ver _on_edge).
	for route in range(1, track.route_count()):
		_add_rope(-half_width, yellow, route)
		_add_rope(half_width, red, route)
		_add_buoy_circle(-half_width, yellow, 24.0, route)
		_add_buoy_circle(half_width, red, 24.0, route)


## Largo del borde a esa distancia de la línea central.
func _edge_length(lateral: float, route: int = 0) -> float:
	if route > 0:
		return (track as PathTrack).branches[route - 1].length
	return track.length() * maxf(1.0 + lateral / track.radius, 0.2)


## Punto del borde número i de `count` (de una vuelta, o de punta a punta del
## camino alternativo `route`).
func _edge_point(i: int, count: int, lateral: float, route: int) -> Vector3:
	if route > 0:
		var b: PathTrack.Branch = (track as PathTrack).branches[route - 1]
		return (track as PathTrack).branch_position(b, b.length * i / maxf(count - 1, 1), lateral)
	return track.position_at(TAU * i / count, lateral)


## Corchera: muchos flotadores chicos alternando color y blanco.
func _add_rope(lateral: float, color: Color, route: int = 0) -> void:
	var count := int(_edge_length(lateral, route) / float_spacing)
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
	var kept: Array[Vector3] = []
	var colors: Array[Color] = []
	for i in count:
		var p := _edge_point(i, count, lateral, route)
		if not _on_edge(p, lateral):
			continue
		kept.append(p)
		colors.append(color if (i / 2) % 2 == 0 else Color(0.97, 0.97, 0.97))
	mm.instance_count = kept.size()
	for i in kept.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, kept[i]))
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rope"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4.0
	add_child(mmi)
	_ropes.append(mmi)
	_float_offsets.append(0.05)
	_float_points.append(_points_of(mm))


## true si el punto quedó de verdad en el borde de la pista. En las curvas más
## cerradas que el ancho de la pista, correr la línea del centro hacia adentro
## hace un rulo: esos puntos caen DENTRO de la pista (boyas que se atraviesan y
## corcheras cruzadas), y se saltean. El borde real es donde se cruzan los dos
## tramos del rulo.
func _on_edge(p: Vector3, lateral: float) -> bool:
	var lat := track.lateral_of(p)
	return signf(lat) == signf(lateral) and absf(absf(lat) - absf(lateral)) < EDGE_TOLERANCE


func _add_buoy_circle(lateral: float, color: Color, spacing: float, route: int = 0) -> void:
	var count := int(_edge_length(lateral, route) / spacing)
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
		var p := _edge_point(i, count, lateral, route)
		if _on_edge(p, lateral):
			points.append(p)
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


func _build_cells() -> void:
	_cells_built = true
	_cells.clear()
	for k in _float_points.size():
		var pts := _float_points[k]
		for i in pts.size():
			var key := Vector2i(floori(pts[i].x / CELL), floori(pts[i].y / CELL))
			# (Los Packed se copian: se saca, se agrega y se vuelve a guardar.)
			var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
			list.append(k * ROPE_STRIDE + i)
			_cells[key] = list


func _is_near(points: Array[Vector2], x: float, z: float) -> bool:
	for p in points:
		if absf(p.x - x) < FLOAT_UPDATE_DISTANCE and absf(p.y - z) < FLOAT_UPDATE_DISTANCE:
			return true
	return false


func _water_height(x: float, z: float) -> float:
	return _water.height_at(x, z) if _water else 0.0
