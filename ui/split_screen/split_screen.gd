class_name SplitScreen
extends Control
## Pantalla dividida: una vista por jugador humano. Por defecto lado a lado
## (vertical); con GameSettings.split_vertical = false, una arriba de la otra.
## Cada vista es un SubViewport sobre el mismo mundo, con su cámara, su HUD,
## sus rayas de velocidad y su propio plano de agua.

@export var race_manager_path: NodePath
@export var water_path: NodePath

var views: Array[SubViewport] = []
var cameras: Array[ChaseCamera] = []
var huds: Array[Hud] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var race_manager := get_node(race_manager_path) as RaceManager
	var water := get_node_or_null(water_path) as Water

	# Una vista por persona; si no hay personas (demo), una por corredor (hasta 4).
	var humans := race_manager.humans()
	var spectating := humans.is_empty()
	if spectating:
		humans = race_manager.racers.slice(0, 4)

	# 3 o 4 vistas: grilla de 2x2. Si no, lado a lado o una arriba de la otra.
	var box: Container
	if humans.size() >= 3:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		box = grid
	elif GameSettings.split_vertical:
		box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
	else:
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_tune_shadows(humans.size())
	for i in humans.size():
		var rider := humans[i]
		var container := SubViewportContainer.new()
		container.name = "View%d" % (i + 1)
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(container)

		var vp := SubViewport.new()
		vp.audio_listener_enable_3d = i == 0
		container.add_child(vp)
		views.append(vp)

		var cam := ChaseCamera.new()
		cam.target = rider
		cam.far = 320.0
		cam.cull_mask = Water.camera_cull_mask(i)
		vp.add_child(cam)
		cam.current = true
		cameras.append(cam)

		var hud := Hud.new()
		hud.rider = rider
		hud.race_manager = race_manager
		hud.show_help = humans.size() == 1 and not spectating
		hud.demo = spectating
		hud.compact = humans.size() >= 3
		hud.free_ride = race_manager.free_ride()
		vp.add_child(hud)
		huds.append(hud)

		rider.has_view = true
		if water:
			water.add_follower(rider, i)


## Sombras del sol: cada vista vuelve a dibujar la escena para cada "corte" de
## sombra. Con 1-2 vistas, 2 cortes; con 3-4, uno solo y más corto (se nota poco
## en pantallas chicas y ahorra mucho).
func _tune_shadows(view_count: int) -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	if view_count >= 3:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 30.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 50.0
