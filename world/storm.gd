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
## Lluvia: una cortina por vista.
var rain: Array[ColorRect] = []
var _rain_mat: ShaderMaterial
var _rain_sound: AudioStreamPlayer
## Rayos que cayeron (para los tests).
var strikes: int = 0
## Dónde cayó el último rayo.
var last_strike: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	var main := get_parent().get_parent()
	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
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
		_sun.light_energy = 0.45
		_sun.light_color = Color(0.72, 0.78, 0.9)
		_base_sun = _sun.light_energy
	var water := main.get_node_or_null("Water") as Water
	if water:
		_roughen(water)
	var waves := main.get_node_or_null("WaveManager") as WaveManager
	if waves:
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
	var split := main.get_node_or_null("Views") as SplitScreen
	if split == null:
		return
	for vp in split.views:
		var r := ColorRect.new()
		r.name = "Rain"
		r.material = _rain_mat
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.size = Vector2(vp.size)
		vp.size_changed.connect(func() -> void: r.size = Vector2(vp.size))
		vp.add_child(r)
		rain.append(r)


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
	var w := water.waves.duplicate() as WaveDefinition
	var list: Array[Vector4] = []
	for v in w.waves:
		list.append(Vector4(v.x, v.y, v.z * CHOP_SCALE, v.w * 1.15))
	w.waves = list
	w.speed_scale *= CHOP_SPEED
	water.waves = w
	var mat := water.shader_material()
	w.apply_to(mat)
	mat.set_shader_parameter("deep_color", Color(0.05, 0.15, 0.23))
	mat.set_shader_parameter("shallow_color", Color(0.11, 0.29, 0.37))
	mat.set_shader_parameter("wave_color", Color(0.15, 0.4, 0.44))
	mat.set_shader_parameter("outside_color", Color(0.04, 0.1, 0.16))
	mat.set_shader_parameter("rising_color", Color(0.03, 0.1, 0.17))
	mat.set_shader_parameter("sky_tint", Color(0.5, 0.55, 0.62))
	mat.set_shader_parameter("glow_strength", 0.15)
	# Espuma solo en las crestas más altas (si no, el mar picado se llena de manchas).
	mat.set_shader_parameter("foam_height", 0.42 * CHOP_SCALE * 0.5)


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
