class_name Storm
extends Node3D
## Tormenta eléctrica: cielo gris y cerrado, luz apagada, mar mucho más picado
## y rayos que caen a lo lejos (con relámpago y trueno que llega después,
## según la distancia).
##
## Course la agrega cuando el clima elegido es "tormenta". Cambia copias del
## ambiente, el cielo y el agua (no los recursos de la escena), así la próxima
## carrera con sol arranca limpia.

## Segundos entre rayos.
const STRIKE_MIN := 1.8
const STRIKE_MAX := 5.0
## Distancia de los rayos al centro del mapa (m): siempre lejos.
const DIST_MIN := 420.0
const DIST_MAX := 650.0
const SOUND_SPEED := 343.0
const BOLT_TIME := 0.42
## Olitas de fondo: cuánto más altas y rápidas.
const CHOP_SCALE := 2.4
const CHOP_SPEED := 1.25
const RAIN_SHADER := preload("res://world/sky/rain.gdshader")
const CURTAIN_SHADER := preload("res://world/sky/rain_curtain.gdshader")
const DROP_SHADER := preload("res://world/sky/rain_drop.gdshader")
## Dirección en la que caen las gotas (con un poco de viento).
const FALL_DIR := Vector3(0.22, -1.0, 0.08)
## Gotas 3D cerca de cada cámara (menos con muchas pantallas).
const DROPS := 1400
const DROPS_MANY_VIEWS := 700

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
var _timer: float = 1.5
var _bolt_on: bool = false
var _bolt_age: float = 0.0
var _thunder_in: Array[float] = []
var _base_ambient: float = 0.0
var _base_sun: float = 0.0
var _base_fog: Color
## Brillo del relámpago (0..1), para los tests.
var flash: float = 0.0
## Lluvia de cada vista (gotas 3D + cortinas), colgada de su cámara.
var rain: Array[Node3D] = []
## Velo gris + destello de cada vista.
var veils: Array[ColorRect] = []
var _rain_mat: ShaderMaterial
var _split: SplitScreen
var _curtain_mats: Array[ShaderMaterial] = []
var _drop_mat: ShaderMaterial
var _drop_mesh: QuadMesh
var _rain_clock: float = 0.0
var _rain_sound: AudioStreamPlayer
## Rayos que cayeron (para los tests).
var strikes: int = 0
## Dónde cayó el último rayo.
var last_strike: Vector3 = Vector3.ZERO

# Lo que había antes de la tormenta (para dejar todo igual con stop()).
var _world_env: WorldEnvironment
var _orig_env: Environment
var _orig_sun_energy: float = 0.0
var _orig_sun_color: Color = Color.WHITE
var _water: Water
var _orig_waves: WaveDefinition
var _orig_params: Dictionary = {}
var _wave_manager: WaveManager
var _orig_amp: Vector2 = Vector2.ZERO
var _stopped: bool = false


func _ready() -> void:
	_rng.randomize()
	var main := get_parent().get_parent()
	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		_world_env = world_env
		_orig_env = world_env.environment
		_env = world_env.environment.duplicate() as Environment
		_env.ambient_light_color = Color(0.62, 0.66, 0.74)
		_env.ambient_light_energy = 0.5
		_env.fog_light_color = Color(0.42, 0.46, 0.52)
		_env.fog_density = 0.0065
		if _env.sky:
			_env.sky = _env.sky.duplicate() as Sky
			_sky_mat = _env.sky.sky_material.duplicate() as ShaderMaterial
			_env.sky.sky_material = _sky_mat
			_paint_sky()
		world_env.environment = _env
		_base_ambient = _env.ambient_light_energy
		_base_fog = _env.fog_light_color
	_sun = main.get_node_or_null("Sun") as DirectionalLight3D
	if _sun:
		_orig_sun_energy = _sun.light_energy
		_orig_sun_color = _sun.light_color
		_sun.light_energy = 0.45
		_sun.light_color = Color(0.72, 0.78, 0.9)
		_base_sun = _sun.light_energy
	var water := main.get_node_or_null("Water") as Water
	if water:
		_roughen(water)
	var waves := main.get_node_or_null("WaveManager") as WaveManager
	if waves:
		_wave_manager = waves
		_orig_amp = Vector2(waves.amplitude_min, waves.amplitude_max)
		waves.amplitude_min *= 1.25
		waves.amplitude_max *= 1.35
	# Lluvia y viento (las vistas se arman después que la pista).
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RAIN_SHADER
	_add_rain.call_deferred(main)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = SfxLoop.make("res://assets/audio/sfx/rain_loop.wav")
	_rain_sound.volume_db = -11.0
	add_child(_rain_sound)
	if _rain_sound.stream:
		_rain_sound.play()


func _add_rain(main: Node) -> void:
	if _stopped:
		return
	_split = main.get_node_or_null("Views") as SplitScreen
	# Gotas: rayas cortas y finas que miran a la cámara (ver rain_drop.gdshader).
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = DROP_SHADER
	_drop_mat.set_shader_parameter("fall_dir", FALL_DIR)
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2.ONE
	_drop_mesh.material = _drop_mat
	for spec in [[16.0, 90.0, 0.4], [38.0, 170.0, 0.3]]:
		var m := ShaderMaterial.new()
		m.shader = CURTAIN_SHADER
		m.set_shader_parameter("columns", spec[1])
		m.set_shader_parameter("tint", Color(0.78, 0.83, 0.9, spec[2]))
		_curtain_mats.append(m)
	_ensure_rain()


## Pone la lluvia en cada vista que no la tenga (si las vistas se rearman,
## vuelve a aparecer sola).
func _ensure_rain() -> void:
	if _split == null:
		return
	var many := _split.cameras.size() >= 3
	for i in _split.cameras.size():
		var cam := _split.cameras[i]
		if is_instance_valid(cam) and cam.get_node_or_null("Rain") == null:
			var rig := _rain_rig(i, DROPS_MANY_VIEWS if many else DROPS)
			cam.add_child(rig)
			rain.append(rig)
		var vp := _split.views[i]
		if is_instance_valid(vp) and vp.get_node_or_null("Veil") == null:
			var r := ColorRect.new()
			r.name = "Veil"
			r.material = _rain_mat
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.set_anchors_preset(Control.PRESET_FULL_RECT)
			vp.add_child(r)
			veils.append(r)
	for i in range(rain.size() - 1, -1, -1):
		if not is_instance_valid(rain[i]):
			rain.remove_at(i)
	for i in range(veils.size() - 1, -1, -1):
		if not is_instance_valid(veils[i]):
			veils.remove_at(i)


## Lluvia de una vista: solo la ve esa cámara (capa propia).
func _rain_rig(view: int, amount: int) -> Node3D:
	var layer := 1 << (Water.FOLLOWER_LAYER_BASE + view)
	var rig := Node3D.new()
	rig.name = "Rain"
	# Gotas cerca: caen en el mundo (no se mueven con la cámara), un poco
	# adelante para que no falten cuando se avanza rápido.
	var drops := CPUParticles3D.new()
	drops.name = "Drops"
	drops.mesh = _drop_mesh
	drops.amount = amount
	drops.lifetime = 0.75
	drops.preprocess = 0.75
	drops.local_coords = false
	drops.position = Vector3(0.0, 3.0, -9.0)
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(13.0, 7.0, 13.0)
	drops.direction = FALL_DIR
	drops.spread = 3.0
	drops.gravity = Vector3.ZERO
	drops.initial_velocity_min = 22.0
	drops.initial_velocity_max = 28.0
	drops.scale_amount_min = 0.7
	drops.scale_amount_max = 1.25
	drops.layers = layer
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(drops)
	# Cortinas: siguen la posición de la cámara pero no su giro (al girar se
	# ve que la lluvia está en el mundo).
	for m in _curtain_mats:
		var cyl := CylinderMesh.new()
		var radius: float = 16.0 if m == _curtain_mats[0] else 38.0
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 44.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 24
		cyl.rings = 1
		cyl.material = m
		var mi := MeshInstance3D.new()
		mi.name = "Curtain"
		mi.mesh = cyl
		mi.top_level = true
		mi.layers = layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(mi)
	return rig


func _paint_sky() -> void:
	var p := {
		"zenith_color": Color(0.17, 0.19, 0.24),
		"sky_color": Color(0.3, 0.33, 0.39),
		"horizon_color": Color(0.42, 0.46, 0.52),
		"glow_color": Color(0.45, 0.47, 0.52),
		"sun_color": Color(0.5, 0.53, 0.58),
		"cloud_color": Color(0.5, 0.53, 0.58),
		"cloud_shade": Color(0.24, 0.26, 0.31),
		"cloud_warm": Color(0.42, 0.44, 0.5),
		"island_color": Color(0.12, 0.17, 0.18),
		"island_far_color": Color(0.3, 0.35, 0.4),
		"ocean_color": Color(0.1, 0.15, 0.2),
		"cloud_coverage": 0.86,
		"cloud_speed": 0.06,
	}
	for k in p:
		_sky_mat.set_shader_parameter(k, p[k])


func _roughen(water: Water) -> void:
	_water = water
	_orig_waves = water.waves
	var w := water.waves.duplicate() as WaveDefinition
	var list: Array[Vector4] = []
	for v in w.waves:
		list.append(Vector4(v.x, v.y, v.z * CHOP_SCALE, v.w * 1.15))
	w.waves = list
	w.speed_scale *= CHOP_SPEED
	water.waves = w
	var mat := water.shader_material()
	w.apply_to(mat)
	_set_water(mat, "deep_color", Color(0.05, 0.15, 0.23))
	_set_water(mat, "shallow_color", Color(0.11, 0.29, 0.37))
	_set_water(mat, "wave_color", Color(0.15, 0.4, 0.44))
	_set_water(mat, "outside_color", Color(0.04, 0.1, 0.16))
	_set_water(mat, "rising_color", Color(0.03, 0.1, 0.17))
	_set_water(mat, "sky_tint", Color(0.5, 0.55, 0.62))
	_set_water(mat, "glow_strength", 0.15)
	_set_water(mat, "sky_reflect", 0.6)
	# Espuma solo en las crestas más altas (si no, el mar picado se llena de manchas).
	_set_water(mat, "foam_height", 0.42 * CHOP_SCALE * 0.5)
	# Las gotas pegan en el mar: circulitos que se abren y salpicaduras.
	_set_water(mat, "rain_ripples", 1.0)


## Cambia un parámetro del agua, recordando el que tenía (para stop()).
func _set_water(mat: ShaderMaterial, param: String, value: Variant) -> void:
	if not _orig_params.has(param):
		_orig_params[param] = mat.get_shader_parameter(param)
	mat.set_shader_parameter(param, value)


## Se va la tormenta: deja el cielo, la luz, el agua y las olas como estaban y
## saca la lluvia de todas las vistas. Después se puede liberar el nodo.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	set_process(false)
	if is_instance_valid(_world_env) and _orig_env:
		_world_env.environment = _orig_env
	if is_instance_valid(_sun):
		_sun.light_energy = _orig_sun_energy
		_sun.light_color = _orig_sun_color
	if is_instance_valid(_water) and _orig_waves:
		_water.waves = _orig_waves
		var mat := _water.shader_material()
		_orig_waves.apply_to(mat)
		for param in _orig_params:
			mat.set_shader_parameter(param, _orig_params[param])
	if is_instance_valid(_wave_manager):
		_wave_manager.amplitude_min = _orig_amp.x
		_wave_manager.amplitude_max = _orig_amp.y
	for r in rain:
		if is_instance_valid(r):
			r.queue_free()
	for v in veils:
		if is_instance_valid(v):
			v.queue_free()
	rain.clear()
	veils.clear()
	if _rain_sound:
		_rain_sound.stop()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		strike()
		# A veces cae otro enseguida (doble rayo).
		_timer = 0.55 if _rng.randf() < 0.25 else _rng.randf_range(STRIKE_MIN, STRIKE_MAX)
	# Trueno: llega tarde, según la distancia.
	for i in range(_thunder_in.size() - 1, -1, -1):
		_thunder_in[i] -= delta
		if _thunder_in[i] <= 0.0:
			_thunder_in.remove_at(i)
			var am := get_node_or_null("/root/AudioManager")
			if am:
				am.play("thunder", _rng.randf_range(-12.0, -5.0), _rng.randf_range(0.85, 1.1))
	# Relámpago: dos o tres parpadeos y se apaga.
	var bolt := 0.0
	if _bolt_on:
		_bolt_age += delta
		var k := _bolt_age / BOLT_TIME
		flash = clampf(1.0 - k, 0.0, 1.0) * (0.55 + 0.45 * absf(sin(_bolt_age * 46.0)))
		bolt = 1.0 if k < 0.25 or (k > 0.4 and k < 0.6) else 0.0
		if k >= 1.0:
			_bolt_on = false
			flash = 0.0
	if _env:
		_env.ambient_light_energy = _base_ambient + flash * 1.4
		_env.fog_light_color = _base_fog.lerp(Color(0.85, 0.88, 1.0), flash * 0.6)
	if _sky_mat:
		_sky_mat.set_shader_parameter("bolt_strength", bolt)
		_sky_mat.set_shader_parameter("cloud_color", Color(0.5, 0.53, 0.58).lerp(Color(0.92, 0.94, 1.0), flash))
	if _sun:
		_sun.light_energy = _base_sun + flash * 0.9
	if _rain_mat:
		_rain_mat.set_shader_parameter("flash", flash)
	if _drop_mat:
		_drop_mat.set_shader_parameter("flash", flash)
	# Lluvia: reloj que da la vuelta cada segundo (sin saltos ni números grandes).
	_rain_clock = fmod(_rain_clock + delta, 1.0)
	for m in _curtain_mats:
		m.set_shader_parameter("rain_time", _rain_clock)
	_ensure_rain()
	for r in rain:
		var cam := r.get_parent() as Node3D
		for c in r.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).global_position = cam.global_position + Vector3(0.0, 6.0, 0.0)


## Cae un rayo lejos (en una dirección al azar). Se dibuja en el cielo, así
## se ve desde todas las cámaras sin importar qué tan lejos miren.
func strike() -> void:
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(DIST_MIN, DIST_MAX)
	last_strike = Vector3(sin(ang) * dist, 0.0, cos(ang) * dist)
	_bolt_on = true
	_bolt_age = 0.0
	strikes += 1
	if _sky_mat:
		_sky_mat.set_shader_parameter("bolt_az", ang)
		_sky_mat.set_shader_parameter("bolt_seed", float(_rng.randi_range(0, 9999)))
	_thunder_in.append(dist / SOUND_SPEED * 0.5 + _rng.randf_range(0.2, 0.6))
