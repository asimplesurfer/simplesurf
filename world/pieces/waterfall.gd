class_name WaterfallPiece
extends MapPiece
## Una cascada: una cortina de agua que cae desde `height` metros hasta el mar,
## con espuma y rocío abajo. Se puede pasar por detrás o atravesarla: el que la
## atraviesa queda con la pantalla mojada (como al pasar por una ola que rompe)
## y pierde un poco de velocidad.
##
## Lo ideal es ponerla en la salida de una cueva (rock_formation), cruzando la
## pista: así se sale de la cueva por detrás de la cascada.

const REQUIRED := ["x", "z"]

## Cómo se ve en el editor de mapas (ver MapPiece.editor_entry).
const EDITOR := {
	"name": "Cascada", "place": "point",
	"hint": "Clic para poner una cascada. Ponela en la salida de una cueva, cruzando la pista; el puntito del extremo la gira.",
	"fields": {
		"angle": "Ángulo (°)", "width": "Ancho (m)", "height": "Altura (m)",
		"color": "Agua", "drag": "Cuánto frena (0 a 1)",
	},
}

## Centro de la cortina (al nivel del agua).
var x: float = 0.0
var z: float = 0.0
## Hacia dónde va la cortina (grados): con 0 se extiende en X (se la cruza
## yendo en Z).
var angle: float = 0.0
## Ancho de la cortina y altura desde la que cae (m).
var width: float = 50.0
var height: float = 34.0
## Color del agua que cae.
var color: Color = Color("bdf3ff")
## Cuánto frena al atravesarla (0: nada, 1: para).
var drag: float = 0.12

var _root: Node3D
var _along := Vector2.RIGHT
var _across := Vector2.DOWN
## Por surfista: de qué lado de la cortina estaba en el paso anterior.
var _side: Dictionary = {}


func build(course: Course) -> void:
	var a := deg_to_rad(angle)
	_along = Vector2(cos(a), -sin(a))
	_across = Vector2(-_along.y, _along.x)
	_root = Node3D.new()
	_root.name = "Waterfall"
	_root.position = Vector3(x, 0.0, z)
	_root.rotation.y = a
	course.add_child(_root, true)
	_root.add_child(_curtain())
	_root.add_child(_foam())
	_root.add_child(_spray())


## Cruzar la cortina: pantalla mojada, sonido de agua y un poco de freno.
func affect_rider(_course: Course, rider: Rider) -> bool:
	var rel := Vector2(rider.position.x - x, rider.position.z - z)
	var along := rel.dot(_along)
	var side := signf(rel.dot(_across))
	var before: float = _side.get(rider, side)
	_side[rider] = side
	if absf(along) > width * 0.5 or side == before or rider.position.y > height:
		return false
	# La HUD y la tabla ya saben mostrar "me pasó agua por encima".
	rider.wave_punched.emit()
	rider.speed *= 1.0 - drag
	var audio := rider.get_tree().root.get_node_or_null("AudioManager")
	if audio:
		audio.play_for(rider, "splash")
	return false


## La cortina: un plano vertical con agua que corre para abajo (y se abre un
## poco abajo, donde golpea el agua).
func _curtain() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 12
	var rows := 8
	for r in rows:
		for c in cols:
			var quad: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for k in [[c, r], [c + 1, r], [c + 1, r + 1], [c, r + 1]]:
				var u := float(k[0]) / cols
				var v := float(k[1]) / rows
				# Arriba sale un poco hacia afuera (el borde de la roca) y abajo se abre.
				var out := 1.5 * (1.0 - v) * (1.0 - v) + 2.5 * v * v
				var spread := 1.0 + 0.12 * v
				quad.append(Vector3((u - 0.5) * width * spread, height * (1.0 - v) - 0.5, out))
				uvs.append(Vector2(u, v))
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[i])
				st.add_vertex(quad[i])
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mat.set_shader_parameter("water", color)
	mat.set_shader_parameter("width", width)
	var mi := MeshInstance3D.new()
	mi.name = "Curtain"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _shader_cache: Shader


static func _shader() -> Shader:
	if _shader_cache:
		return _shader_cache
	_shader_cache = Shader.new()
	_shader_cache.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 water : source_color = vec4(0.74, 0.95, 1.0, 1.0);
uniform float width = 50.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	// Chorros: columnas de distinto ancho que bajan a distinta velocidad.
	float cols = width * 0.6;
	float col = floor(UV.x * cols);
	float speed = 0.9 + hash(col) * 0.8;
	float flow = fract(UV.y * 2.5 - TIME * speed + hash(col + 7.0));
	float streak = smoothstep(0.55, 1.0, flow);
	float edge = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);
	vec3 base = mix(water.rgb * 0.82, vec3(1.0), streak * 0.65 + UV.y * 0.25);
	ALBEDO = base;
	ALPHA = edge * clamp(0.55 + streak * 0.35 + hash(col + 3.0) * 0.15, 0.0, 0.95);
}
"""
	return _shader_cache


## Espuma blanca donde cae el agua.
func _foam() -> MeshInstance3D:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.1
	disc.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.7)
	disc.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Foam"
	mi.mesh = disc
	mi.scale = Vector3(width * 0.6, 1.0, 7.0)
	mi.position = Vector3(0.0, 0.25, 3.0)
	return mi


## Rocío que salta donde golpea el agua.
func _spray() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Spray"
	var m := SphereMesh.new()
	m.radius = 0.6
	m.height = 1.2
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.55)
	m.material = mat
	p.mesh = m
	p.amount = 70
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.45, 0.5, 2.0)
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 35.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.position = Vector3(0.0, 0.3, 2.5)
	return p
