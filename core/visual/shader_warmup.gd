class_name ShaderWarmup
extends Node
## Prepara los shaders de la partida durante la cuenta regresiva (sin tirones
## en la carrera). En el navegador cada material se compila la primera vez que
## se dibuja: los efectos que todavía no se ven (espuma del derrape, turbo,
## salpicones, partículas) trababan el juego la primera vez que aparecían.
##
## Dibuja una vez cada material de la escena delante de cada cámara, todos en
## el mismo punto y tan chiquitos que ocupan menos de un píxel (antes se veía
## una columna de cuadraditos de colores al arrancar), y las partículas
## emitiendo un instante. Después se borra. Para compilar un shader alcanza
## con que se mande a dibujar, aunque no pinte ningún píxel.

## Cuadros que espera antes de empezar (que la escena termine de armarse).
const START_DELAY_FRAMES := 3
## Tamaño de lo que se dibuja (m, a 1 m de la cámara): menos de un píxel.
const WARM_SIZE := 0.00002
## Cuánto quedan dibujados (s).
const HOLD_TIME := 0.8

var _frames: int = 0
var _time: float = 0.0
var _started: bool = false
var _nodes: Array[Node] = []


func _process(delta: float) -> void:
	_frames += 1
	if not _started:
		if _frames >= START_DELAY_FRAMES:
			_started = true
			_warm()
		return
	_time += delta
	if _time >= HOLD_TIME:
		for n in _nodes:
			if is_instance_valid(n):
				n.queue_free()
		_nodes.clear()
		queue_free()


func _scene_root() -> Node:
	var n: Node = self
	while n.get_parent() and n.get_parent() != get_tree().root:
		n = n.get_parent()
	return n


func _warm() -> void:
	var root := _scene_root()
	var materials := {}
	var particles: Array[GPUParticles3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.material_override:
			_add_material(materials, gi.material_override)
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					_add_material(materials, mi.get_surface_override_material(s))
					_add_material(materials, mi.mesh.surface_get_material(s))
		elif gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm and mm.mesh:
				for s in mm.mesh.get_surface_count():
					_add_material(materials, mm.mesh.surface_get_material(s))
		elif gi is GPUParticles3D:
			particles.append(gi as GPUParticles3D)
	var cameras := root.find_children("*", "Camera3D", true, false)
	var quad := QuadMesh.new()
	quad.size = Vector2(WARM_SIZE, WARM_SIZE)
	for cam in cameras:
		var holder := Node3D.new()
		holder.name = "Warmup"
		holder.position = Vector3(0.0, 0.0, -1.0)
		(cam as Node3D).add_child(holder)
		_nodes.append(holder)
		var i := 0
		for mat in materials:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3.ZERO
			holder.add_child(mi)
			i += 1
		# Partículas: una copia que emite un instante (su shader de proceso
		# también se compila recién al emitir).
		for p in particles:
			var copy := p.duplicate() as GPUParticles3D
			copy.position = Vector3.ZERO
			copy.scale = Vector3.ONE * WARM_SIZE
			copy.emitting = true
			copy.visible = true
			holder.add_child(copy)
	# Shaders de la pantalla (el fuego del turbo, etc.): un cuadradito de 1 px.
	for node in root.find_children("*", "CanvasItem", true, false):
		var item := node as CanvasItem
		if not item.material is ShaderMaterial or item.is_visible_in_tree():
			continue
		var rect := ColorRect.new()
		rect.size = Vector2(1.0, 1.0)
		rect.material = item.material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.get_viewport().add_child(rect)
		_nodes.append(rect)


func _add_material(materials: Dictionary, mat: Material) -> void:
	while mat != null and not materials.has(mat):
		materials[mat] = true
		mat = mat.next_pass
