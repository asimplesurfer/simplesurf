class_name SplitScreen
extends Control
## Pantalla dividida: una vista por jugador humano, una arriba de la otra.
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

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var humans := race_manager.humans()
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
		hud.show_help = humans.size() == 1
		vp.add_child(hud)
		huds.append(hud)

		if water:
			water.add_follower(rider, i)
