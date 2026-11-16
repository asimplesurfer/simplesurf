class_name RiverPiece
extends MapPiece
## Un río dibujado como un camino abierto (puntos y manijas Bézier, como la
## pista pero sin cerrar). Corre por arriba de la tierra que encuentre (toda
## pieza anotada como "ground": la isla tropical, por ejemplo) y desemboca en
## el mar donde la tierra se termina. Tiene orillas de arena mojada y agua que
## corre. Las islas dejan libre su cauce (no ponen palmeras ni plantas ahí).
##
## Funciona con cualquier isla que se anote como tierra (ver MapPiece.prepare).

const REQUIRED := ["path"]

## Camino del río: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...]. Va
## de la naciente a la desembocadura (el agua corre en ese sentido).
var path: Array = []
## Ancho del agua (m).
var width: float = 9.0
var color: Color = Color("47c9d6")
var deep_color: Color = Color("1f7f9a")
## Velocidad con la que corre el agua.
var flow_speed: float = 1.0

## Cuántos metros de orilla hay a cada lado del agua.
const BANK := 2.5

var _line := PackedVector2Array()


func prepare(course: Course) -> void:
	_line = BezierShape.parse(path).polyline(3.0)
	if _line.size() >= 2:
		course.register("river", self)


## Distancia (en planta) al centro del río.
func distance_to(p: Vector2) -> float:
	var best := INF
	for i in _line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, _line[i], _line[i + 1])))
	return best


func build(course: Course) -> void:
	if _line.size() < 2:
		push_error("river: el camino necesita al menos 2 puntos")
		return
	var grounds := course.registered("ground")
	# Altura del suelo en cada punto del río (-INF: ahí ya es mar).
	var heights := PackedFloat32Array()
	for p in _line:
		var y := -INF
		for g in grounds:
			y = maxf(y, g.ground_y(p))
		heights.append(y)
	# Tramos sobre tierra (con un pedacito más que entra al mar).
	var root := Node3D.new()
	root.name = "River"
	course.add_child(root, true)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var banks := SurfaceTool.new()
	banks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev: Array = []
	for i in _line.size():
		var on_land := heights[i] > -INF
		var near_land := on_land or (i > 0 and heights[i - 1] > -INF) or (i + 1 < _line.size() and heights[i + 1] > -INF)
		if i > 0:
			along += _line[i].distance_to(_line[i - 1])
		if not near_land:
			prev = []
			continue
		var tangent := (_line[mini(i + 1, _line.size() - 1)] - _line[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		# En el mar, el río baja hasta el agua.
		var y: float = heights[i] if on_land else 0.0
		var half := width * 0.5
		var cur := [
			_line[i] + side * (half + BANK), _line[i] + side * half, _line[i] - side * half, _line[i] - side * (half + BANK),
			y, along,
		]
		if not prev.is_empty():
			_strip(st, prev[1], prev[2], cur[1], cur[2], prev[4] + 0.07, cur[4] + 0.07, prev[5], cur[5])
			_bank(banks, prev[0], prev[1], cur[0], cur[1], prev[4] + 0.04, cur[4] + 0.04)
			_bank(banks, prev[2], prev[3], cur[2], cur[3], prev[4] + 0.04, cur[4] + 0.04)
		prev = cur
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mat.set_shader_parameter("water", color)
	mat.set_shader_parameter("deep", deep_color)
	mat.set_shader_parameter("speed", flow_speed)
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	var bank_mesh := MeshInstance3D.new()
	bank_mesh.name = "Banks"
	var bank_mat := ToonMaterial.make(Color("d9bd84"), 0.0)
	bank_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	banks.set_material(bank_mat)
	bank_mesh.mesh = banks.commit()
	bank_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bank_mesh)


## Un tramo de agua (UV: x de orilla a orilla, y = metros río abajo / ancho).
func _strip(st: SurfaceTool, a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2, ya: float, yb: float, va: float, vb: float) -> void:
	var verts := [
		[a0, ya, Vector2(0, va / width)], [a1, ya, Vector2(1, va / width)], [b1, yb, Vector2(1, vb / width)],
		[a0, ya, Vector2(0, va / width)], [b1, yb, Vector2(1, vb / width)], [b0, yb, Vector2(0, vb / width)],
	]
	for v in verts:
		st.set_normal(Vector3.UP)
		st.set_uv(v[2])
		st.add_vertex(Vector3(v[0].x, v[1], v[0].y))


func _bank(st: SurfaceTool, a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2, ya: float, yb: float) -> void:
	for v in [[a0, ya], [a1, ya], [b1, yb], [a0, ya], [b1, yb], [b0, yb]]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(v[0].x, v[1], v[0].y))


static var _shader_cache: Shader


static func _shader() -> Shader:
	if _shader_cache:
		return _shader_cache
	_shader_cache = Shader.new()
	_shader_cache.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 water : source_color = vec4(0.28, 0.79, 0.84, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.5, 0.6, 1.0);
uniform float speed = 1.0;

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float flow = UV.y - TIME * speed * 0.35;
	// Vetas que bajan con la corriente, un poco onduladas.
	float wave = sin((flow * 5.0 + sin(UV.x * 7.0 + flow * 2.3) * 0.6) * 6.2832);
	float streak = smoothstep(0.75, 1.0, wave * 0.5 + 0.5) * (1.0 - across * 0.6);
	vec3 c = mix(deep.rgb, water.rgb, smoothstep(0.0, 0.9, across));
	c = mix(c, vec3(1.0), streak * 0.3 + smoothstep(0.8, 1.0, across) * 0.45);
	ALBEDO = c;
}
"""
	return _shader_cache
