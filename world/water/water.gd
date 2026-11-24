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
## Capa del agua cuando no hay pantalla dividida. El agua nunca está en la capa
## 1: así una luz puede no alumbrarla (ver LIGHT_MASK) y el agua se ilumina
## sola con add_lamp.
const SOLO_LAYER := 14
## Máscara para luces que alumbran todo menos el agua.
const LIGHT_MASK := 0xFFFFF & ~(0b11111 << FOLLOWER_LAYER_BASE)
## Cuántas luces (add_lamp) entiende el shader.
const MAX_LAMPS := 64

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

## Mientras hay tormenta, el agua tiene sus propios colores (los pone y los
## devuelve la tormenta).
var storm_colors: bool = false
## Resolución de la máscara de la pista con curvas (texeles del lado largo).
const TRACK_MASK_SIZE := 512
## Metros en los que el agua de la pista pasa al color de afuera (degradado).
const TRACK_FADE := 16.0
## Distancias (m) de los anillos planos de afuera del agua (hasta el horizonte).
## Llegan más allá de lo que ve la cámara (Horizon.VIEW_FAR), donde el agua ya
## es del color del horizonte (ver `haze` en el shader y horizon.gdshaderinc).
const FAR_RINGS: Array[float] = [180.0, 260.0, 380.0, 560.0]

var _plane: ArrayMesh
var _material: ShaderMaterial
## Cada uno: {node: Node3D, mesh: MeshInstance3D}
var _followers: Array[Dictionary] = []
## Mientras drawn_depth revisa una zona lejos de las islas (ahorra cuentas).
var _far_from_islands: bool = false
var _lamps := PackedVector4Array()
var _lamp_colors := PackedVector4Array()


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
	# Los colores del agua de día (la base de todos los climas: ver WaterPalette).
	WaterPalette.apply_to_water(_material, WaterPalette.DAY, Callable(), palette)

	_plane = _build_mesh()

	var follow := get_node_or_null(follow_path) as Node3D
	if follow:
		add_follower(follow, -1)
	_push_swells()


## Qué agua es: el mar o el río (WaterPalette.SEA / RIVER). La elige el mapa
## (ver Course): con set_palette se cambia y se pintan los colores de día.
var palette: String = WaterPalette.SEA


func set_palette(water: String) -> void:
	palette = water if WaterPalette.WATERS.has(water) else WaterPalette.SEA
	if _material:
		WaterPalette.apply_to_water(_material, WaterPalette.DAY, Callable(), palette)


## El material del agua (la tormenta le cambia colores y olitas).
func shader_material() -> ShaderMaterial:
	return _material


## Colores del agua que levanta la tabla (giros, derrape, estela, salpicones):
## "foam" (lo blanco) y "spray" (el celeste del borde), ya con el brillo del
## clima (spray_light; ver WaterPalette). Salen del material del agua (el
## shader del mar no los usa, pero ahí los ponen la hora y la tormenta, y la
## tormenta los devuelve al irse), así siguen a la hora y al clima de ahora.
func fx_colors() -> Dictionary:
	var base := WaterPalette.base(palette)
	var foam: Variant = _material.get_shader_parameter("foam_color")
	var spray: Variant = _material.get_shader_parameter("spray_color")
	var light: Variant = _material.get_shader_parameter("spray_light")
	var f: Color = foam if foam is Color else base.foam_color
	var s: Color = spray if spray is Color else base.spray_color
	var k: float = float(light) if light != null else 1.0
	return {
		"foam": Color(f.r * k, f.g * k, f.b * k),
		"spray": Color(s.r * k, s.g * k, s.b * k),
	}


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
	# Más allá, anillos planos enormes hasta el horizonte (las olas ya se
	# apagaron en el shader): así desde arriba no se ve dónde termina el agua.
	for far in FAR_RINGS:
		coords.append(far)
		coords.push_front(-far)
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
	mi.layers = 1 << (FOLLOWER_LAYER_BASE + layer_index if layer_index >= 0 else SOLO_LAYER)
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


## Una luz que ilumina el agua y las olas y se refleja en ellas (las
## guirnaldas de noche). `reach`: hasta dónde llega (m).
func add_lamp(pos: Vector3, color: Color, reach: float, strength: float) -> void:
	if _lamps.size() >= MAX_LAMPS:
		return
	_lamps.append(Vector4(pos.x, pos.y, pos.z, reach))
	_lamp_colors.append(Vector4(color.r, color.g, color.b, strength))
	var l := _lamps.duplicate()
	var c := _lamp_colors.duplicate()
	l.resize(MAX_LAMPS)
	c.resize(MAX_LAMPS)
	_material.set_shader_parameter("lamps", l)
	_material.set_shader_parameter("lamp_colors", c)
	_material.set_shader_parameter("lamp_count", _lamps.size())


func lamp_count() -> int:
	return _lamps.size()


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
	# El color de la bruma del horizonte lo pone Horizon (el mismo que el cielo).
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


## Altura del agua en (x, z) dentro de `dt` segundos: el mar de fondo en ese
## momento y las olas grandes corridas lo que avanzan (aproximado: sin contar
## cuánto crecen). Para prever si algo se va a chocar con el agua.
func height_ahead(x: float, z: float, dt: float) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	for s in swells:
		h += s.height_at(p - s.direction * s.speed * dt)
	if ring_wave:
		h += ring_wave.height_at(p)
	if h != 0.0:
		h *= _island_fade(p)
	return waves.height_at(x, z, time + dt) + h


## Altura que aportan solo las olas grandes (para saber si está sobre una).
func swell_height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 0.0
	var crossing := _crossing_drawn(p)
	if not crossing.is_empty():
		# Dos o más olas del modo trucos que se cruzan (ver _crossing_source).
		var src := _crossing_source(p, crossing)
		for s in swells:
			h += s.amplitude * s.plain_n(src) if crossing.has(s) else s.height_at(p)
		if ring_wave:
			h += ring_wave.height_at(p)
		return h * _island_fade(p) if h != 0.0 else 0.0
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
## water_surface.gdshaderinc (altura de todas las olas y corrimiento del labio).
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
	_far_from_islands = not _near_land(p, limit)
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
	if not _crossing_drawn(p).is_empty():
		# Olas que se cruzan: la pendiente de la superficie que se dibuja.
		var e := 0.3
		var gx := (swell_height_at(x + e, z) - swell_height_at(x - e, z)) / (2.0 * e)
		var gz := (swell_height_at(x, z + e) - swell_height_at(x, z - e)) / (2.0 * e)
		g += Vector2(gx, gz)
		return Vector3(-g.x, 1.0, -g.y).normalized()
	var swell_g := Vector2.ZERO
	for s in swells:
		swell_g += s.gradient_at(p)
	if ring_wave:
		swell_g += ring_wave.gradient_at(p)
	if swell_g != Vector2.ZERO:
		g += swell_g * _island_fade(p)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## Las olas del modo trucos (la física sigue al dibujo: Swell.match_drawn) que
## pueden estar en `p`, si son dos o más (vacío si no se cruzan).
func _crossing_drawn(p: Vector2) -> Array[Swell]:
	var out: Array[Swell] = []
	for s in swells:
		if s.match_drawn and s.reaches(p):
			out.append(s)
	if out.size() < 2:
		out.clear()
	return out


## Pasos para encontrar el punto de la malla que se dibuja en `q` cuando se
## cruzan olas (ver _crossing_source).
const CROSSING_STEPS := 8


## Olas que se cruzan: el dibujo corre cada punto de la malla por la suma de
## los labios de todas (como en water_surface.gdshaderinc), así que lo que se
## ve en `q` viene del punto p con p + corrimiento(p) = q. Se arranca desde lo
## que da cada ola por separado y se ajusta de a poco.
func _crossing_source(q: Vector2, crossing: Array[Swell]) -> Vector2:
	var p := q
	for s in crossing:
		var uw := s.local_coords(q)
		var u0 := s._source_u(uw.x, absf(uw.y))
		p -= s.direction * (uw.x - u0)
	for k in CROSSING_STEPS:
		var disp := Vector2.ZERO
		for s in crossing:
			var n := s.plain_n(p)
			disp += s.direction * (s.lean() * n * n * n)
		p = p.lerp(q - disp, 0.7)
	return p


## 0 pegado a la tierra, 1 lejos: las olas grandes no se meten en la playa.
## (Igual que island_fade en water_surface.gdshaderinc; tests/water_match.gd lo comprueba.)
func _island_fade(p: Vector2) -> float:
	return _land_at(p) if _land_w > 0 else 1.0


## Cuánto quedan las olas grandes en p (1 mar abierto, 0 sobre la tierra; baja
## de 28 a 4 m de la orilla). Lo usan también las olas para no salir en la playa.
func land_fade(p: Vector2) -> float:
	return _island_fade(p)


## La tierra (las figuras de las islas): una máscara de cuánto quedan las olas
## grandes en cada punto (1 mar abierto, 0 sobre la isla, y en el medio va
## bajando de 28 a 4 m de la orilla). La usan la física (_land_at) y el shader
## (land_mask), con el mismo filtro.
const LAND_TEXEL := 2.5
const LAND_MAX := 512
var _land := PackedByteArray()
var _land_w: int = 0
var _land_h: int = 0
var _land_lo := Vector2.ZERO
var _land_texel: float = LAND_TEXEL


## Pone la tierra (figuras cerradas, vistas desde arriba). Vacío = sin tierra.
func set_land(polys: Array[PackedVector2Array]) -> void:
	_land_w = 0
	if polys.is_empty():
		_material.set_shader_parameter("land_rect", Vector4.ZERO)
		return
	var lo := polys[0][0]
	var hi := polys[0][0]
	for poly in polys:
		for q in poly:
			lo = lo.min(q)
			hi = hi.max(q)
	var margin := 32.0
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var size := hi - lo
	var texel := maxf(LAND_TEXEL, maxf(size.x, size.y) / LAND_MAX)
	var w := int(ceil(size.x / texel))
	var h := int(ceil(size.y / texel))
	# Distancia a la tierra (en celdas): 0 adentro, después un barrido de ida y
	# vuelta (distancia "chaflán", casi la real).
	var far := 1e6
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(far)
	for j in h:
		var y := lo.y + (j + 0.5) * texel
		var xs: Array[float] = []
		for poly in polys:
			var n := poly.size()
			for k in n:
				var a := poly[k]
				var b := poly[(k + 1) % n]
				if (a.y <= y) != (b.y <= y):
					xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var i0 := maxi(int(ceil((xs[k] - lo.x) / texel - 0.5)), 0)
			var i1 := mini(int(floor((xs[k + 1] - lo.x) / texel - 0.5)), w - 1)
			for i in range(i0, i1 + 1):
				dist[j * w + i] = 0.0
	var diag := 1.4142
	for j in h:
		for i in w:
			var v := dist[j * w + i]
			if v == 0.0:
				continue
			if i > 0:
				v = minf(v, dist[j * w + i - 1] + 1.0)
			if j > 0:
				v = minf(v, dist[(j - 1) * w + i] + 1.0)
				if i > 0:
					v = minf(v, dist[(j - 1) * w + i - 1] + diag)
				if i < w - 1:
					v = minf(v, dist[(j - 1) * w + i + 1] + diag)
			dist[j * w + i] = v
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var v := dist[j * w + i]
			if v == 0.0:
				continue
			if i < w - 1:
				v = minf(v, dist[j * w + i + 1] + 1.0)
			if j < h - 1:
				v = minf(v, dist[(j + 1) * w + i] + 1.0)
				if i < w - 1:
					v = minf(v, dist[(j + 1) * w + i + 1] + diag)
				if i > 0:
					v = minf(v, dist[(j + 1) * w + i - 1] + diag)
			dist[j * w + i] = v
	_land = PackedByteArray()
	_land.resize(w * h)
	for k in w * h:
		# El borde de la celda de tierra está a media celda.
		var meters := maxf(dist[k] - 0.5, 0.0) * texel if dist[k] > 0.0 else 0.0
		_land[k] = roundi(smoothstep(4.0, 28.0, meters) * 255.0)
	_land_w = w
	_land_h = h
	_land_lo = lo
	_land_texel = texel
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, _land)
	_material.set_shader_parameter("land_mask", ImageTexture.create_from_image(img))
	_material.set_shader_parameter("land_rect", Vector4(lo.x, lo.y, w * texel, h * texel))


## La máscara de tierra en p, con el mismo filtro lineal que la GPU.
func _land_at(p: Vector2) -> float:
	var u := (p.x - _land_lo.x) / _land_texel
	var v := (p.y - _land_lo.y) / _land_texel
	if u <= 0.0 or v <= 0.0 or u >= _land_w or v >= _land_h:
		return 1.0
	var fx := u - 0.5
	var fy := v - 0.5
	var x0 := clampi(int(floor(fx)), 0, _land_w - 1)
	var y0 := clampi(int(floor(fy)), 0, _land_h - 1)
	var x1 := mini(x0 + 1, _land_w - 1)
	var y1 := mini(y0 + 1, _land_h - 1)
	var tx := clampf(fx - floor(fx), 0.0, 1.0) if fx >= 0.0 else 0.0
	var ty := clampf(fy - floor(fy), 0.0, 1.0) if fy >= 0.0 else 0.0
	var a := lerpf(_land[y0 * _land_w + x0], _land[y0 * _land_w + x1], tx)
	var b := lerpf(_land[y1 * _land_w + x0], _land[y1 * _land_w + x1], tx)
	return lerpf(a, b, ty) / 255.0


## true si p está a menos de `margin` de la máscara de tierra.
func _near_land(p: Vector2, margin: float) -> bool:
	if _land_w == 0:
		return false
	return p.x > _land_lo.x - margin and p.y > _land_lo.y - margin \
		and p.x < _land_lo.x + _land_w * _land_texel + margin and p.y < _land_lo.y + _land_h * _land_texel + margin


## Pista (anillo): el agua de afuera se ve más oscura, para que se note el borde.
func set_track(center: Vector2, inner: float, outer: float) -> void:
	_material.set_shader_parameter("track_band", Vector4(center.x, center.y, inner, outer))


## Pista con curvas: el agua fuera de la banda de `half_width` alrededor de los
## puntos del recorrido se ve más oscura (para que se note por dónde ir). Se
## arma una máscara vista desde arriba (una textura chica).
func set_track_path(points: PackedVector2Array, half_width: float) -> void:
	if points.is_empty():
		_material.set_shader_parameter("track_mask_rect", Vector4.ZERO)
		return
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var margin := half_width + TRACK_FADE + 6.0
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var size := hi - lo
	var res := TRACK_MASK_SIZE
	var texel := maxf(size.x, size.y) / res
	var w := clampi(int(ceil(size.x / texel)), 8, res)
	var h := clampi(int(ceil(size.y / texel)), 8, res)
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	# Un disco por cada muestra del recorrido (se superponen: una banda). Afuera
	# de la banda, el agua pasa de a poco al color de afuera: se dibujan bandas
	# cada vez más angostas y más claras, de la más ancha (casi negra) a la de
	# la pista (blanca); cada pasada tapa a la anterior, así queda el máximo.
	var passes := 8
	for k in range(passes, -1, -1):
		var extra := TRACK_FADE * float(k) / passes
		var value := 1.0 - float(k) / passes
		_draw_band(img, points, lo, texel, half_width + 0.5 + extra, Color(value, value, value))
	_material.set_shader_parameter("track_mask", ImageTexture.create_from_image(img))
	_material.set_shader_parameter("track_mask_rect", Vector4(lo.x, lo.y, w * texel, h * texel))


## Dibuja en la máscara un disco de radio `radius` (m) en cada muestra del recorrido.
func _draw_band(img: Image, points: PackedVector2Array, lo: Vector2, texel: float, radius: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var r := radius / texel
	var r2 := r * r
	var step := maxi(1, int(r * texel * 0.4 / 2.0))
	for i in range(0, points.size(), step):
		var c := (points[i] - lo) / texel
		for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 1)):
			var dy := y + 0.5 - c.y
			var half := sqrt(maxf(r2 - dy * dy, 0.0))
			var x0 := maxi(0, int(c.x - half + 0.5))
			var x1 := mini(w - 1, int(c.x + half - 0.5))
			if x1 >= x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), color)


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
