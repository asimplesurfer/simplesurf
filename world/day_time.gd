class_name DayTime
extends Node
## La hora de la partida (GameSettings.TimeOfDay): de día no cambia nada; al
## atardecer el sol baja y todo se pone dorado y rosado; de noche el cielo es
## azul oscuro con estrellas y luna, la luz es fría y tenue y el mar refleja
## la luna. Las guirnaldas de luces (LightStringPiece) se prenden de noche.
##
## Como la tormenta, cambia copias del ambiente, el cielo y el agua (no los
## recursos de la escena). Va antes que la tormenta: si hay las dos, la
## tormenta se oscurece según `darkness` (ver Storm).

var time: GameSettings.TimeOfDay = GameSettings.TimeOfDay.DAY


## Pone la hora en la escena `main` (con WorldEnvironment, Sun y Water).
## Devuelve el nodo (o null si es de día).
static func apply(main: Node, t: int) -> DayTime:
	main.set_meta("time_of_day", t)
	if t == GameSettings.TimeOfDay.DAY:
		# De día, el mar lejano de la base (el agua ya la pone Water: ver WaterPalette).
		var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if world_env and world_env.environment and world_env.environment.sky:
			var sky_mat := world_env.environment.sky.sky_material as ShaderMaterial
			if sky_mat:
				sky_mat.set_shader_parameter("ocean_color", WaterPalette.base(_water_of(main)).ocean_color)
		return null
	var d := DayTime.new()
	d.name = "DayTime"
	d.time = t as GameSettings.TimeOfDay
	main.add_child.call_deferred(d)
	d._paint(main)
	return d


## La hora de la escena de `node` (DAY si nadie la puso).
static func of(node: Node) -> int:
	var n := node
	while n:
		if n.has_meta("time_of_day"):
			return int(n.get_meta("time_of_day"))
		n = n.get_parent()
	return GameSettings.TimeOfDay.DAY


static func is_night(node: Node) -> bool:
	return of(node) == GameSettings.TimeOfDay.NIGHT


## Cuánto se oscurece todo (0 de día, 1 de noche).
static func darkness(node: Node) -> float:
	match of(node):
		GameSettings.TimeOfDay.NIGHT:
			return 1.0
		GameSettings.TimeOfDay.SUNSET:
			return 0.35
	return 0.0


func _paint(main: Node) -> void:
	var night := time == GameSettings.TimeOfDay.NIGHT
	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		var env := world_env.environment.duplicate() as Environment
		if night:
			env.ambient_light_color = Color(0.42, 0.5, 0.85)
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.07, 0.09, 0.18)
			env.fog_density = 0.005
		else:
			env.ambient_light_color = Color(1.0, 0.78, 0.7)
			env.ambient_light_energy = 0.42
			env.fog_light_color = Color(0.98, 0.72, 0.6)
		if env.sky:
			env.sky = env.sky.duplicate() as Sky
			var sky := env.sky.sky_material.duplicate() as ShaderMaterial
			env.sky.sky_material = sky
			for k in (_NIGHT_SKY if night else _SUNSET_SKY):
				sky.set_shader_parameter(k, (_NIGHT_SKY if night else _SUNSET_SKY)[k])
			# El mar lejano es un color del agua (ver WaterPalette).
			sky.set_shader_parameter("ocean_color", WaterPalette.colors(climate(), _water_of(main)).ocean_color)
		world_env.environment = env
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		if night:
			# La luna: luz fría, tenue y alta.
			sun.light_color = Color(0.62, 0.72, 1.0)
			sun.light_energy = 0.42
			sun.rotation = Vector3(-1.05, -0.9, 0.0)
		else:
			# El sol bajo, del lado de enfrente de la largada.
			sun.light_color = Color(1.0, 0.72, 0.5)
			sun.light_energy = 0.95
			sun.rotation = Vector3(-0.32, 0.61, 0.0)
	var water := main.get_node_or_null("Water") as Water
	if water:
		WaterPalette.apply_to_water(water.shader_material(), climate(), Callable(), water.palette)


## Qué agua tiene la escena (el mar o el río; ver Water.palette).
static func _water_of(main: Node) -> String:
	var water := main.get_node_or_null("Water") as Water
	return water.palette if water else WaterPalette.SEA


## Nombre del clima del agua para esta hora (ver WaterPalette).
func climate() -> String:
	return WaterPalette.NIGHT if time == GameSettings.TimeOfDay.NIGHT else WaterPalette.SUNSET


const _NIGHT_SKY := {
	"zenith_color": Color(0.02, 0.03, 0.09),
	"sky_color": Color(0.04, 0.07, 0.17),
	"horizon_color": Color(0.1, 0.12, 0.24),
	"glow_color": Color(0.2, 0.2, 0.38),
	"sun_color": Color(0.88, 0.92, 1.0),
	"cloud_color": Color(0.2, 0.23, 0.36),
	"cloud_shade": Color(0.08, 0.09, 0.17),
	"cloud_warm": Color(0.26, 0.28, 0.42),
	"island_color": Color(0.03, 0.05, 0.09),
	"island_far_color": Color(0.07, 0.09, 0.17),
	"cloud_coverage": 0.3,
	"stars": 1.0,
	"moon": 1.0,
}
const _SUNSET_SKY := {
	"zenith_color": Color(0.28, 0.3, 0.6),
	"sky_color": Color(0.85, 0.55, 0.55),
	"horizon_color": Color(1.0, 0.7, 0.52),
	"glow_color": Color(1.0, 0.55, 0.3),
	"sun_color": Color(1.0, 0.72, 0.42),
	"cloud_color": Color(1.0, 0.78, 0.62),
	"cloud_shade": Color(0.62, 0.42, 0.55),
	"cloud_warm": Color(1.0, 0.6, 0.38),
	"island_color": Color(0.36, 0.3, 0.42),
	"island_far_color": Color(0.7, 0.55, 0.6),
}
