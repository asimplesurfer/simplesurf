class_name BoardTrail
extends MeshInstance3D
## Estela que sigue a la tabla y deja su recorrido sobre el agua.
## Guarda puntos por donde pasó la cola de la tabla y cada frame arma una cinta
## que se abre con el tiempo (forma de "V") y se desvanece. La cinta se pega
## a la altura del agua, así sube y baja con las olas.

const SHADER := preload("res://effects/shaders/board_trail.gdshader")

## Cuánto dura la estela (s).
@export var lifetime: float = 2.6
## Cada cuántos metros se guarda un punto.
@export var sample_distance: float = 0.7
## Ancho (a cada lado) recién hecha (m).
@export var start_width: float = 0.32
## Cuánto se abre por segundo (m).
@export var spread_speed: float = 0.9
## Altura sobre el agua (m), para que no se meta adentro de las olitas.
@export var height_offset: float = 0.09

var rider: Rider

## Cada punto: {pos: Vector2, side: Vector2, time: float, strength: float, start: bool}
var _points: Array[Dictionary] = []
var _time: float = 0.0
var _emitting: bool = false
var _last_pos: Vector2 = Vector2.ZERO
var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()
## Para repartir entre cuadros la altura del agua de los puntos (cada punto
## guarda la suya y se actualiza uno de cada REFRESH_EVERY por cuadro).
var _frame: int = 0
const REFRESH_EVERY := 4
## Sin nadie que la vea a esta distancia (bots lejos), no se arma.
const SEEN_DISTANCE := 90.0


func setup(p_rider: Rider) -> void:
	rider = p_rider
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	_material.shader = SHADER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La cinta se arma en coordenadas del mundo y puede estar lejos del origen.
	extra_cull_margin = 16384.0


## Color del agua de ahora (ver Water.fx_colors).
func set_water_colors(foam: Color, _spray: Color) -> void:
	_material.set_shader_parameter("color", foam)


func _process(delta: float) -> void:
	if rider == null:
		return
	_time += minf(delta, 0.1)
	_frame += 1
	while not _points.is_empty() and _time - float(_points[0].time) > lifetime:
		_points.pop_front()
	if not rider.has_view and not _watched():
		if not _points.is_empty():
			clear()
		return

	var on_water := (
		rider.grounded
		and rider.recovery_stage == Rider.RecoveryStage.STANDING
		and rider.speed > 1.5
	)
	var head := _make_point(not _emitting)
	if on_water:
		if not _emitting or head.pos.distance_to(_last_pos) >= sample_distance:
			_points.append(head)
			_last_pos = head.pos
		_emitting = true
	else:
		_emitting = false
	_rebuild(head if _emitting else {})


func _watched() -> bool:
	for node in rider.get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r and r.has_view and r.position.distance_squared_to(rider.position) < SEEN_DISTANCE * SEEN_DISTANCE:
			return true
	return false


func clear() -> void:
	_points.clear()
	_emitting = false
	_mesh.clear_surfaces()


func _make_point(start: bool) -> Dictionary:
	var tail := rider.global_position - rider.forward() * 0.95
	var side := rider.right()
	var strength := 0.5 + 0.5 * absf(rider.steer_amount)
	if rider.drift_side != 0:
		strength = 1.0
	strength *= clampf(rider.speed / 6.0, 0.3, 1.0)
	return {
		"pos": Vector2(tail.x, tail.z),
		"side": Vector2(side.x, side.z),
		"time": _time,
		"strength": strength,
		"start": start,
	}


func _rebuild(head: Dictionary) -> void:
	_mesh.clear_surfaces()
	var pts: Array[Dictionary] = _points.duplicate()
	if not head.is_empty() and not pts.is_empty() and pts[-1].time != head.time:
		head.start = false
		pts.append(head)

	# Pares de puntos consecutivos que forman un tramo (los cortes empiezan con start).
	var segments: Array[int] = []
	for i in range(1, pts.size()):
		if not pts[i].start:
			segments.append(i)
	if segments.is_empty():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	var edges := {}
	for i in segments:
		if not edges.has(i - 1):
			edges[i - 1] = _edge_vertices(pts[i - 1], i - 1)
		if not edges.has(i):
			edges[i] = _edge_vertices(pts[i], i)
		var a: Array = edges[i - 1]
		var b: Array = edges[i]
		# Dos triángulos: a.izq, a.der, b.izq / a.der, b.der, b.izq
		_vertex(a, 0)
		_vertex(a, 1)
		_vertex(b, 0)
		_vertex(a, 1)
		_vertex(b, 1)
		_vertex(b, 0)
	_mesh.surface_end()


## Devuelve [pos_izq, pos_der, edad (0..1), intensidad].
func _edge_vertices(p: Dictionary, index: int) -> Array:
	var age: float = _time - float(p.time)
	var k := clampf(age / lifetime, 0.0, 1.0)
	var width := start_width + age * spread_speed
	var pos: Vector2 = p.pos
	var side: Vector2 = p.side
	var left := pos - side * width
	var right := pos + side * width
	# La altura del agua se guarda en el punto y se actualiza de a tandas.
	if not p.has("yl") or (index + _frame) % REFRESH_EVERY == 0:
		p["yl"] = _water_y(left)
		p["yr"] = _water_y(right)
	return [
		Vector3(left.x, float(p.yl), left.y), Vector3(right.x, float(p.yr), right.y), k, float(p.strength)
	]


func _vertex(edge: Array, which: int) -> void:
	_mesh.surface_set_color(Color(1.0, 1.0, 1.0, edge[3]))
	_mesh.surface_set_uv(Vector2(float(which), edge[2]))
	_mesh.surface_add_vertex(edge[which])


## El agua donde anda la tabla: adentro de un tubo, el piso (no el techo
## del labio, que queda arriba).
func _water_y(p: Vector2) -> float:
	var y := height_offset
	if rider.water:
		y += rider.water.floor_height_at(p.x, p.y)
	return y
