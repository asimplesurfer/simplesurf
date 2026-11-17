class_name Horizon
extends Node3D
## El horizonte del juego: que el mundo chico (la pista y lo que la rodea)
## parezca un archipiélago en medio de un océano enorme, sin que se vea el
## borde ni desde un salto alto.
##
## - Un solo color de horizonte para todo (ver horizon.gdshaderinc): el cielo
##   lo pinta, el agua se funde con él a lo lejos y las siluetas del anillo se
##   tiñen con él. Este nodo copia esos colores del cielo (y el sol) a los demás
##   materiales cada cuadro, así la tormenta los cambia en un solo lugar.
## - Un anillo de islas y montañas lejanas, en silueta (pocos triángulos, sin
##   luz), que acompaña a cada cámara: siempre quedan "lejos", apoyadas sobre
##   el agua y metidas en la bruma.
## - La niebla de siempre (la que da el tono pastel) tiene el mismo color y,
##   a la distancia a la que la cámara deja de dibujar, ya tapa casi todo: las
##   islas lejanas de los mapas no aparecen cortadas.

## Hasta dónde dibuja la cámara (m). El agua llega un poco más allá.
const VIEW_FAR := 520.0
## Distancia del anillo de islas lejanas (m).
const RING_DISTANCE := 430.0

const SHADER := preload("res://world/sky/horizon_ring.gdshader")

var _env: Environment
## La tormenta reemplaza el Environment por una copia con sus colores: se lee
## del WorldEnvironment en cada cuadro.
var _world_env: WorldEnvironment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _water: Water
var _ring_mat: ShaderMaterial
## Un anillo por cámara (cada una lo lleva centrado en ella).
var _rings: Dictionary = {}
var _cams: Array[Camera3D] = []
var _search_clock: float = 0.0


func _ready() -> void:
	add_to_group("horizon")
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = SHADER
	var parent := get_parent()
	for n in parent.get_children():
		if n is WorldEnvironment:
			_world_env = n
		elif n is DirectionalLight3D:
			_sun = n
		elif n is Water:
			_water = n


func _process(delta: float) -> void:
	_search_clock -= delta
	if _search_clock <= 0.0 or _cams.any(func(c: Camera3D) -> bool: return not is_instance_valid(c)):
		_search_clock = 1.0
		_find_cameras()
	_sync_colors()
	for cam in _cams:
		var ring: MeshInstance3D = _rings.get(cam)
		if ring:
			ring.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)


func _find_cameras() -> void:
	_cams.clear()
	var root := get_parent()
	var index := -1
	for n in root.find_children("*", "Camera3D", true, false):
		var cam := n as Camera3D
		if not cam.current:
			continue
		index += 1
		_cams.append(cam)
		cam.far = VIEW_FAR
		if not _rings.has(cam):
			var mi := MeshInstance3D.new()
			mi.name = "HorizonRing"
			mi.mesh = HorizonRing.build()
			mi.material_override = _ring_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Que no lo corte la cámara por estar "fuera" de la caja de la malla.
			mi.extra_cull_margin = RING_DISTANCE
			# Solo lo ve su cámara (en pantalla dividida, cada uno el suyo), con la
			# misma capa que el agua de ese jugador.
			mi.layers = 1 << (Water.FOLLOWER_LAYER_BASE + index)
			add_child(mi)
			_rings[cam] = mi
	for cam in _rings.keys():
		if not is_instance_valid(cam):
			(_rings[cam] as Node).queue_free()
			_rings.erase(cam)


## El color del horizonte (y el sol) del cielo, a los demás.
func _sync_colors() -> void:
	_env = _world_env.environment if is_instance_valid(_world_env) else null
	if _env == null:
		return
	if _env.sky and _env.sky.sky_material is ShaderMaterial:
		_sky_mat = _env.sky.sky_material
	if _sky_mat == null:
		return
	var horizon := _param(_sky_mat, "horizon_color")
	var glow := _param(_sky_mat, "glow_color")
	var island := _param(_sky_mat, "island_color")
	var sun_flat := Vector2(0.5, 0.83)
	if _sun:
		var d := -_sun.global_transform.basis.z
		sun_flat = Vector2(-d.x, -d.z)
	_sky_mat.set_shader_parameter("sun_flat", sun_flat)
	_sky_mat.set_shader_parameter("horizon_glow", glow)
	for mat in [_ring_mat, _water.shader_material() if _water else null]:
		if mat:
			mat.set_shader_parameter("horizon_color", horizon)
			mat.set_shader_parameter("horizon_glow", glow)
			mat.set_shader_parameter("sun_flat", sun_flat)
	_ring_mat.set_shader_parameter("island_color", island)
	if _water:
		var wm := _water.shader_material()
		wm.set_shader_parameter("far_sea_color", _param(_sky_mat, "ocean_color"))
		wm.set_shader_parameter("fog_tint", _env.fog_light_color)
		# Hacia dónde está el sol y cuánto brilla (con tormenta, nada).
		if _sun:
			wm.set_shader_parameter("sun_dir", _sun.global_transform.basis.z)
			wm.set_shader_parameter("sun_glitter", clampf((_sun.light_energy - 0.55) * 2.5, 0.0, 1.0))
		wm.set_shader_parameter("fog_density", _env.fog_density if _env.fog_enabled else 0.0)
	_ring_mat.set_shader_parameter("far_sea_color", _param(_sky_mat, "ocean_color"))
	# La niebla de los objetos es la de siempre (su color ya es el del
	# horizonte; la tormenta lo cambia y lo hace brillar con los rayos): a
	# VIEW_FAR ya tapa casi todo.


## Un color del material (o el valor por defecto del shader si nadie lo puso).
static func _param(mat: ShaderMaterial, key: String) -> Color:
	var v: Variant = mat.get_shader_parameter(key)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), key)
	return v if v is Color else Color.WHITE
