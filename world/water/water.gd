class_name Water
extends Node3D
## Plano de agua que sigue a cada jugador (parece infinito) y se ondula.
## Con pantalla dividida hay un plano por jugador, cada uno en su propia capa
## de render, y cada cámara ve solo el suyo.
## Altura = olas de fondo (WaveDefinition) + olas grandes (Swell) que maneja WaveManager.
## Ofrece height_at() / normal_at() para que las cosas floten justo sobre lo que se ve.

const SHADER := preload("res://world/water/water.gdshader")
## Cantidad de olas grandes que entiende el shader (swell_a0..swell_a7).
const MAX_SWELLS := 8

## Primera capa de render (índice desde 0) para los planos de cada jugador.
const FOLLOWER_LAYER_BASE := 10

@export var waves: WaveDefinition
## Nodo al que sigue el plano si nadie llama a add_follower (opcional).
@export var follow_path: NodePath
@export var size: float = 260.0
@export var subdivisions: int = 170

## Tiempo de las olas; se comparte con el shader.
var time: float = 0.0
var swells: Array[Swell] = []
## Modo "ola constante a la izquierda" (null = sin ola constante).
var ring_wave: RingWave = null
## Islas: las olas grandes se apagan cerca de la orilla. Cada una (x, z, radio).
var islands: Array[Vector3] = []
## Islas que entiende el shader (islands[0..15]).
const MAX_ISLANDS := 16
## Grilla fina: celdas a cada lado del centro de la malla (~40 m). Después,
## MID_CELLS celdas de 2 pasos y el resto de 4 pasos hasta el borde.
const FINE_HALF_CELLS := 26
const MID_CELLS := 10
## Solo para diagnóstico: revisar sin atajos.
static var debug_exact: bool = false
## Cuánto tiene que quedar la cara debajo del agua dibujada para que cuente (m).
const FACE_MIN_DEPTH := 0.02
## Altura mínima de una ola para que atravesarla cuente como chapuzón (m).
const BIG_WAVE_MIN := 1.0

var _plane: ArrayMesh
var _material: ShaderMaterial
## Cada uno: {node: Node3D, mesh: MeshInstance3D}
var _followers: Array[Dictionary] = []
## Mientras drawn_depth revisa una zona lejos de las islas (ahorra cuentas).
var _far_from_islands: bool = false


func _ready() -> void:
	add_to_group("water")
	# Se procesa antes que el resto para que todos usen el mismo estado en el frame.
	process_priority = -10
	process_physics_priority = -10
	if waves == null:
		waves = WaveDefinition.new()

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	waves.apply_to(_material)

	_plane = _build_mesh()

	var follow := get_node_or_null(follow_path) as Node3D
	if follow:
		add_follower(follow, -1)
	_push_swells()


## El material del agua (la tormenta le cambia colores y olitas).
func shader_material() -> ShaderMaterial:
	return _material


## Paso de la grilla fina del agua (m). Los vértices finos están siempre en
## (n + 0,5) · step del mundo, para todas las cámaras.
func grid_step() -> float:
	return size / float(subdivisions + 1)


## Malla del agua: grilla con paso fino cerca del centro (donde está el jugador)
## y celdas de 2 y 4 pasos más lejos. Es una sola grilla (filas y columnas
## enteras), así que no quedan grietas entre zonas. Los triángulos se arman
## igual que PlaneMesh (drawn_depth cuenta con eso).
func _build_mesh() -> ArrayMesh:
	var step := grid_step()
	var half := size * 0.5
	var coords: Array[float] = []
	for k in range(-FINE_HALF_CELLS, FINE_HALF_CELLS):
		coords.append((k + 0.5) * step)
	var edge := (FINE_HALF_CELLS - 0.5) * step
	for m in MID_CELLS:
		edge += step * 2.0
		coords.append(edge)
		coords.push_front(-edge)
	while edge < half - 0.001:
		edge += step * 4.0
		coords.append(edge)
		coords.push_front(-edge)
	var n := coords.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for j in n:
		for i in n:
			verts[j * n + i] = Vector3(coords[i], 0.0, coords[j])
			normals[j * n + i] = Vector3.UP
	var indices := PackedInt32Array()
	for j in range(1, n):
		for i in range(1, n):
			var a := (j - 1) * n + i - 1
			var b := (j - 1) * n + i
			var c := j * n + i - 1
			var e := j * n + i
			indices.append_array([a, b, c, b, e, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


## Agrega un plano de agua que sigue a `node`. layer_index = -1: capa normal (1);
## si no, usa la capa FOLLOWER_LAYER_BASE + layer_index (para pantalla dividida).
func add_follower(node: Node3D, layer_index: int = -1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Surface%d" % _followers.size()
	mi.mesh = _plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0
	if layer_index >= 0:
		mi.layers = 1 << (FOLLOWER_LAYER_BASE + layer_index)
	add_child(mi)
	_followers.append({"node": node, "mesh": mi})
	_snap(mi, node)
	return mi


## Máscara de render para la cámara del jugador `layer_index`: todo menos el
## agua de los demás jugadores.
static func camera_cull_mask(layer_index: int, max_players: int = 4) -> int:
	var mask := 0xFFFFF
	for i in max_players:
		if i != layer_index:
			mask &= ~(1 << (FOLLOWER_LAYER_BASE + i))
	return mask


## El agua avanza en pasos fijos, igual que la física de los surfistas (así la
## altura que "sienten" no depende de los FPS).
func _physics_process(delta: float) -> void:
	time += delta
	_push_time()

	for i in range(swells.size() - 1, -1, -1):
		swells[i].update(delta)
		if swells[i].is_dead():
			swells.remove_at(i)
	if ring_wave:
		ring_wave.update(delta)
	_push_swells()


## Reloj de los efectos del shader (espuma, destellos, lluvia): da la vuelta cada
## tanto para que nunca sea un número grande.
const FX_WRAP := 1200.0


func _push_time() -> void:
	_material.set_shader_parameter("fx_time", fmod(time, FX_WRAP))
	for i in WaveDefinition.MAX_WAVES:
		_material.set_shader_parameter("wave_phase_%d" % i, waves.phase(i, time))


func _process(_delta: float) -> void:
	for f in _followers:
		if is_instance_valid(f.node):
			_snap(f.mesh, f.node)


## Mueve el plano en pasos del tamaño de una celda para que la malla no "nade".
func _snap(mi: MeshInstance3D, node: Node3D) -> void:
	# En pasos de la celda más grande: así todos los vértices (finos y gruesos)
	# quedan siempre en el mismo lugar del mundo y la malla no "nada".
	var step := grid_step() * 4.0
	var p := node.global_position
	mi.global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))


func can_add_swell() -> bool:
	return swells.size() < MAX_SWELLS


func add_swell(swell: Swell) -> void:
	if can_add_swell():
		swells.append(swell)


func clear_swells() -> void:
	swells.clear()
	_push_swells()


## Pone (o saca, con null) la ola constante.
func set_ring_wave(rw: RingWave) -> void:
	ring_wave = rw
	_push_swells()


func height_at(x: float, z: float) -> float:
	return waves.height_at(x, z, time) + swell_height_at(x, z)


## Altura que aportan solo las olas grandes (para saber si está sobre una).
func swell_height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	for s in swells:
		h += s.height_at(p)
	if ring_wave:
		h += ring_wave.height_at(p)
	if h == 0.0:
		return 0.0
	return h * _island_fade(p)


## Qué tanto está rompiendo la ola grande que hay en ese punto (0 si no hay).
func breaking_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for s in swells:
		if s.breaking > best and s.height_at(p) > s.max_amplitude * 0.35:
			best = s.breaking
	return best


## true si el punto (la cara de alguien) está debajo del agua TAL COMO SE DIBUJA.
func face_in_wave(q: Vector3) -> bool:
	return drawn_depth(q) > FACE_MIN_DEPTH


## true si hay una ola grande (o la ola constante) que puede tapar el punto q:
## el agua que lo cubre es de la ola, no el mar de fondo.
func big_wave_near(q: Vector3) -> bool:
	if ring_wave and ring_wave.height_at(Vector2(q.x, q.z)) > BIG_WAVE_MIN:
		return true
	var p := Vector2(q.x, q.z)
	for s in swells:
		if s.amplitude < BIG_WAVE_MIN:
			continue
		var uw := s.local_coords(p)
		if absf(uw.y) < s.half_length + 2.0 and uw.x > -s.width * 3.0 - 2.0 and uw.x < s.width * 3.0 + s.lean() + 2.0:
			return true
	return false


## Vértice de la malla del agua en el punto de grilla p, movido igual que en
## water.gdshader (altura de todas las olas y corrimiento del labio).
func drawn_vertex(p: Vector2) -> Vector3:
	var h := waves.height_at(p.x, p.y, time)
	var sh := 0.0
	var disp := Vector2.ZERO
	for s in swells:
		if s.amplitude <= 0.0:
			continue
		var uw := s.local_coords(p)
		var aw := absf(uw.y)
		if aw >= s.half_length or absf(uw.x) > s.width * 4.0:
			continue
		var n := exp(-(uw.x * uw.x) / (s.width * s.width)) * s._edge(aw)
		sh += s.amplitude * n
		disp += s.direction * (s.lean() * n * n * n)
	if ring_wave:
		sh += ring_wave.height_at(p)
	if sh == 0.0 and disp == Vector2.ZERO:
		return Vector3(p.x, h, p.y)
	var fade := 1.0 if _far_from_islands else _island_fade(p)
	disp *= fade
	return Vector3(p.x + disp.x, h + sh * fade, p.y + disp.y)


## Cuánto está q debajo del agua tal como se dibuja (0 si está afuera).
## Usa la misma malla que se ve: vértices cada `step` metros (en la misma
## grilla del mundo para todas las cámaras), corridos por el labio de la ola,
## y los triángulos como los arma PlaneMesh. Cuenta las capas de agua que hay
## arriba del punto (impar = adentro; debajo del rulo pero en el aire da par).
func drawn_depth(q: Vector3) -> float:
	var step := grid_step()
	var p := Vector2(q.x, q.z)
	# Olas que pueden correr vértices hasta acá.
	var near := step * 1.5
	var relevant: Array[Swell] = []
	var total_lean := 0.0
	# (Otra ola puede traer hasta acá vértices de una ola que no llega sola.)
	var max_lean := 0.0
	for s in swells:
		max_lean = maxf(max_lean, s.lean())
	for s in swells:
		if s.amplitude <= 0.0:
			continue
		var lean := s.lean()
		var uw := s.local_coords(p)
		var margin := step * 2.0 + max_lean
		if absf(uw.y) >= s.half_length + margin:
			continue
		if uw.x < -s.width * 4.0 - margin or uw.x > s.width * 4.0 + lean + margin:
			continue
		relevant.append(s)
		total_lean += lean
	# Los vértices que terminan en q vienen de a lo sumo `reach` metros (lo que
	# los puede correr el labio). Se achica: cada ola solo corre de verdad cerca
	# de su cresta (n³), así que con la zona más chica el corrimiento máximo
	# también baja. Cada paso sigue siendo una cota segura.
	var reach := total_lean + near
	if debug_exact:
		reach = 12.0
	var leans: Array[float] = []
	var nmax: Array[float] = []
	leans.resize(relevant.size())
	nmax.resize(relevant.size())
	for it in 3:
		var next := near
		for k in relevant.size():
			var s := relevant[k]
			var uw := s.local_coords(p)
			var u_near := clampf(0.0, uw.x - reach, uw.x + reach)
			var w_near := maxf(absf(uw.y) - reach, 0.0)
			nmax[k] = exp(-(u_near * u_near) / (s.width * s.width)) * s._edge(w_near)
			leans[k] = s.lean() * nmax[k] * nmax[k] * nmax[k]
			next += leans[k]
		if next >= reach or debug_exact:
			break
		reach = next
	# Techo: lo más alto que puede estar el agua dibujada justo acá.
	var ceiling := waves.max_height() + (ring_wave.amplitude if ring_wave else 0.0)
	for k in relevant.size():
		ceiling += relevant[k].amplitude * nmax[k]
	if q.y > ceiling + 0.05 and not debug_exact:
		return 0.0
	var i0 := floori((p.x - reach - near) / step)
	var i1 := ceili((p.x + reach + near) / step)
	var j0 := floori((p.y - reach - near) / step)
	var j1 := ceili((p.y + reach + near) / step)
	var limit := reach + near
	# Lejos de toda isla el apagado de las olas es 1 en toda la zona.
	_far_from_islands = true
	for isl in islands:
		if p.distance_to(Vector2(isl.x, isl.y)) - limit < isl.z + 28.0:
			_far_from_islands = false
			break
	var cache := {}
	var above: Array[float] = []
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			# Celda con esquinas en los vértices (i-1..i, j-1..j); su centro sin
			# mover está en (i, j) * step. Solo sirven las que el corrimiento
			# puede traer hasta q.
			# Sirve si el corrimiento (suma de cada ola en su dirección, entre 0 y
			# su máximo acá) puede llevar la celda hasta q.
			var d := p - Vector2(i * step, j * step)
			var dist := d.length()
			var useful := dist < near
			if not useful and dist < limit:
				for k in relevant.size():
					var others := reach - near - leans[k]
					var dir := relevant[k].direction
					var along := d.dot(dir)
					var perp := absf(d.x * dir.y - d.y * dir.x)
					if (
						along > -near - others and along < leans[k] + near + others
						and perp < near + others
					):
						useful = true
						break
			if not useful:
				continue
			var a := _cached_vertex(cache, i - 1, j - 1, step)
			var b := _cached_vertex(cache, i, j - 1, step)
			var c := _cached_vertex(cache, i - 1, j, step)
			var e := _cached_vertex(cache, i, j, step)
			# Igual que PlaneMesh: (a, b, c) y (b, e, c).
			var y1 := _tri_height(p, a, b, c)
			if not is_nan(y1) and y1 > q.y:
				above.append(y1)
			var y2 := _tri_height(p, b, e, c)
			if not is_nan(y2) and y2 > q.y:
				above.append(y2)
	_far_from_islands = false
	if above.size() % 2 == 0:
		return 0.0
	return above.min() - q.y


func _cached_vertex(cache: Dictionary, i: int, j: int, step: float) -> Vector3:
	var key := Vector2i(i, j)
	if cache.has(key):
		return cache[key]
	var v := drawn_vertex(Vector2((i + 0.5) * step, (j + 0.5) * step))
	cache[key] = v
	return v


## Altura del triángulo (a, b, c) en el punto p (visto desde arriba), o NAN si
## p cae afuera.
static func _tri_height(p: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var v0 := Vector2(b.x - a.x, b.z - a.z)
	var v1 := Vector2(c.x - a.x, c.z - a.z)
	var v2 := Vector2(p.x - a.x, p.y - a.z)
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return NAN
	var u := (v2.x * v1.y - v1.x * v2.y) / den
	var v := (v0.x * v2.y - v2.x * v0.y) / den
	if u < 0.0 or v < 0.0 or u + v > 1.0:
		return NAN
	return a.y + u * (b.y - a.y) + v * (c.y - a.y)


func normal_at(x: float, z: float) -> Vector3:
	var g := waves.gradient_at(x, z, time)
	var p := Vector2(x, z)
	var swell_g := Vector2.ZERO
	for s in swells:
		swell_g += s.gradient_at(p)
	if ring_wave:
		swell_g += ring_wave.gradient_at(p)
	if swell_g != Vector2.ZERO:
		g += swell_g * _island_fade(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## 0 pegado a la isla, 1 lejos: las olas grandes no se meten en la playa.
## (Igual que island_fade en water.gdshader.)
func _island_fade(p: Vector2) -> float:
	var fade := 1.0
	for i in mini(islands.size(), MAX_ISLANDS):
		var isl := islands[i]
		var d := p.distance_to(Vector2(isl.x, isl.y))
		fade *= smoothstep(isl.z + 4.0, isl.z + 28.0, d)
	return fade


## Pista (anillo): el agua de afuera se ve más oscura, para que se note el borde.
func set_track(center: Vector2, inner: float, outer: float) -> void:
	_material.set_shader_parameter("track_band", Vector4(center.x, center.y, inner, outer))


func set_island(center: Vector2, radius: float) -> void:
	var list: Array[Vector3] = [Vector3(center.x, center.y, radius)]
	set_islands(list)


## Islas (x, z, radio): las olas grandes se apagan cerca de cada orilla.
## El shader entiende hasta MAX_ISLANDS (las primeras de la lista).
func set_islands(list: Array[Vector3]) -> void:
	islands = list.duplicate()
	var packed := PackedVector3Array()
	packed.resize(MAX_ISLANDS)
	for i in MAX_ISLANDS:
		packed[i] = list[i] if i < list.size() else Vector3.ZERO
	_material.set_shader_parameter("islands", packed)
	_material.set_shader_parameter("island_count", mini(list.size(), MAX_ISLANDS))


func _push_swells() -> void:
	for i in MAX_SWELLS:
		var a := Vector4(0.0, 0.0, 1.0, 0.0)
		var b := Vector4.ZERO
		if i < swells.size():
			a = swells[i].shader_a()
			b = swells[i].shader_b()
		_material.set_shader_parameter("swell_a%d" % i, a)
		_material.set_shader_parameter("swell_b%d" % i, b)
	var ra := Vector4(0.0, 0.0, 1.0, 1.0)
	var rb := Vector4.ZERO
	if ring_wave:
		ra = ring_wave.shader_a()
		rb = ring_wave.shader_b()
	_material.set_shader_parameter("ring_a", ra)
	_material.set_shader_parameter("ring_b", rb)
