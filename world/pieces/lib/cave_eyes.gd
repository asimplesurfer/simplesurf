class_name CaveEyes
extends Node
## Los ojos que se acostumbran a la oscuridad, para cada cámara (cada jugador
## lo siente según dónde está él). Al entrar a una cueva se ve casi negro y de
## a poco aparece todo; al salir hay un fogonazo de luz que se va bajando.
##
## Hay uno solo por mapa (lo crea la primera cueva). Cada cueva se anota en
## `caves` y dice qué tan oscuro está en un lugar (darkness_at) y qué tan
## rápido se acostumbran los ojos (adapt_time).

var caves: Array = []
var _cams: Array[Camera3D] = []
## Por cámara: {"adapted": luz a la que se acostumbró, "env": su Environment}.
var _state: Dictionary = {}
var _search_clock: float = 0.0


static func of(course: Node) -> CaveEyes:
	var eyes := course.get_node_or_null("CaveEyes") as CaveEyes
	if eyes == null:
		eyes = CaveEyes.new()
		eyes.name = "CaveEyes"
		course.add_child(eyes)
	return eyes


func _process(delta: float) -> void:
	_search_clock -= delta
	if _search_clock <= 0.0 or _cams.any(func(c: Camera3D) -> bool: return not is_instance_valid(c)):
		_search_clock = 1.0
		_cams.clear()
		for n in get_tree().root.find_children("*", "Camera3D", true, false):
			if n is ChaseCamera:
				_cams.append(n)
	for cam in _cams:
		_update_camera(cam, delta)


## Brillo que se ve (1 = normal) para la luz de ahora y a la que se acostumbró.
static func seen_brightness(light: float, adapted: float) -> float:
	return clampf(light / pow(maxf(adapted, 0.05), 0.85), 0.12, 3.0)


func _update_camera(cam: Camera3D, delta: float) -> void:
	var p := cam.global_position
	var dark := 0.0
	var adapt := 1.6
	for cave in caves:
		var d: float = cave.darkness_at(p)
		if d > dark:
			dark = d
			adapt = cave.adapt_time
	var light := 1.0 - dark
	var st: Dictionary = _state.get(cam, {"adapted": 1.0, "env": null})
	# A la luz los ojos se acostumbran más rápido que a la oscuridad.
	var t: float = adapt if light < st.adapted else adapt * 0.45
	st.adapted += (light - st.adapted) * (1.0 - exp(-delta / maxf(t, 0.05)))
	var seen := seen_brightness(light, st.adapted)
	_state[cam] = st
	if absf(seen - 1.0) < 0.01 and dark == 0.0:
		# Afuera y acostumbrado: la cámara vuelve a usar la luz del mundo.
		if st.env != null:
			cam.environment = null
			st.env = null
		return
	if st.env == null:
		var base := cam.get_world_3d().environment
		if base == null:
			return
		st.env = base.duplicate()
		st.env.set_meta("base_exposure", base.tonemap_exposure)
		cam.environment = st.env
	st.env.tonemap_exposure = float(st.env.get_meta("base_exposure")) * seen
