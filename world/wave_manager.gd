class_name WaveManager
extends Node
## Maneja las olas grandes según el modo (GameSettings.WaveMode):
## - SURGES: hace aparecer olas grandes al azar alrededor del jugador. Nunca
##   aparecen encima del jugador: nacen lejos de él y crecen de a poco.
## - CONSTANT_LEFT: una ola constante a la izquierda (lado de afuera de la
##   pista), con picos que vienen de frente. No aparecen otras olas grandes.

@export var enabled: bool = true
## 0 = distinto cada partida.
@export var random_seed: int = 0
@export var spawn_interval_min: float = 1.5
@export var spawn_interval_max: float = 3.5
## Distancia al jugador a la que pueden nacer (m).
@export var spawn_distance_min: float = 30.0
@export var spawn_distance_max: float = 70.0
## Distancia mínima entre el jugador y cualquier parte de la ola al nacer (m).
@export var clearance: float = 12.0
@export var amplitude_min: float = 2.5
@export var amplitude_max: float = 4.0
## Probabilidad de que la ola nazca adelante del jugador (por la pista) y venga
## de frente hacia él: lo mejor para usarla de rampa y hacer trucos.
@export_range(0.0, 1.0) var incoming_chance: float = 0.75
## Distancia por la pista a la que nacen las olas que vienen de frente (m).
@export var incoming_distance_min: float = 40.0
@export var incoming_distance_max: float = 75.0
## Ola constante: a cuántos metros del centro de la pista va la cresta
## (+ = hacia afuera, que es la izquierda de quien corre).
@export var constant_lateral: float = 12.0

## Cada cuánto se revisa que cada jugador tenga una ola grande viniendo (s).
@export var ensure_interval: float = 0.4
## Tramo adelante (por la pista, m) en el que siempre tiene que haber una ola.
@export var ahead_min: float = 10.0
@export var ahead_max: float = 95.0

var mode: GameSettings.WaveMode = GameSettings.WaveMode.SURGES
## Modo libre: multiplica la altura de las olas nuevas (0 = no aparecen olas
## grandes; 1 = como en una carrera).
var amplitude_scale: float = 1.0
var _target_scale: float = 1.0
## Qué tan rápido cambia la altura de las olas (escala por segundo).
const SCALE_RATE := 0.35
var _ensure_timer: float = 0.0

var _rng := RandomNumberGenerator.new()
var _timer: float = 1.0
var _water: Water


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_water = get_tree().get_first_node_in_group("water") as Water
	GameSettings.load_settings()
	set_mode(GameSettings.wave_mode)


## Cambia el modo de olas (saca las olas del modo anterior).
func set_mode(new_mode: GameSettings.WaveMode) -> void:
	mode = new_mode
	if _water == null:
		return
	_water.clear_swells()
	# La ola constante da la vuelta a la isla: solo existe en el mapa Isla.
	var course := get_tree().get_first_node_in_group("course") as Course
	if course and course.track is PathTrack and mode == GameSettings.WaveMode.CONSTANT_LEFT:
		mode = GameSettings.WaveMode.SURGES
	if mode == GameSettings.WaveMode.CONSTANT_LEFT:
		_water.set_ring_wave(make_ring_wave())
	else:
		_water.set_ring_wave(null)


## Modo libre: cambia la altura de las olas. Va de a poco (las que ya están
## crecen o se achican durante un par de segundos); con 0 se van todas.
func set_amplitude_scale(value: float) -> void:
	_target_scale = maxf(value, 0.0)


## Altura a la que van las olas (modo libre).
func target_scale() -> float:
	return _target_scale


func _ramp_scale(delta: float) -> void:
	if is_equal_approx(amplitude_scale, _target_scale):
		return
	var next := move_toward(amplitude_scale, _target_scale, SCALE_RATE * delta)
	if _water:
		for s in _water.swells:
			if next <= 0.0:
				s.retire()
			elif amplitude_scale > 0.0:
				var k := next / amplitude_scale
				s.max_amplitude *= k
				s.width *= k
	amplitude_scale = next
	_ensure_timer = 0.0


## La ola constante, alrededor de la isla por el lado de afuera de la pista.
func make_ring_wave() -> RingWave:
	var rw := RingWave.new()
	var course := get_tree().get_first_node_in_group("course") as Course
	if course:
		rw.center = course.track.center
		rw.radius = course.track.radius + constant_lateral
	return rw


func _process(delta: float) -> void:
	_ramp_scale(delta)
	if not enabled or _water == null or mode != GameSettings.WaveMode.SURGES or amplitude_scale <= 0.0:
		return
	_retire_passed()
	# Nunca un rato largo sin olas: cada jugador tiene que tener una viniendo.
	_ensure_timer -= delta
	if _ensure_timer <= 0.0:
		_ensure_timer = ensure_interval
		for target in _targets():
			if not has_wave_ahead(target):
				_free_slot()
				if _water.can_add_swell():
					var incoming := _make_incoming_retry(target)
					if incoming:
						_water.add_swell(incoming)
	# Además, olas al azar (más variedad).
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(spawn_interval_min, spawn_interval_max)
	if _water.can_add_swell():
		var s := make_swell()
		if s:
			_water.add_swell(s)


## Jugadores a los que se les garantizan olas: las personas (si no hay, como
## en la demo, todos los corredores).
func _targets() -> Array[Rider]:
	var humans: Array[Rider] = []
	var everyone: Array[Rider] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r and not r.race_finished:
			everyone.append(r)
			if r.is_human:
				humans.append(r)
	return humans if not humans.is_empty() else everyone


## Dirección de la pista donde está el corredor (o su frente, si no hay pista).
func _track_dir(r: Rider) -> Vector2:
	var course := get_tree().get_first_node_in_group("course") as Course
	if course:
		var t := course.track.tangent_at(course.track.angle_of(r.global_position))
		return Vector2(t.x, t.z).normalized()
	var f := r.forward()
	return Vector2(f.x, f.z).normalized()


## true si hay una ola grande (que no se está yendo) adelante del corredor.
func has_wave_ahead(r: Rider) -> bool:
	var pos := Vector2(r.global_position.x, r.global_position.z)
	var dir := _track_dir(r)
	var side := Vector2(-dir.y, dir.x)
	for s in _water.swells:
		if s.max_amplitude < amplitude_min * amplitude_scale * 0.9 or s.lifetime - s.age < 3.0:
			continue
		var rel := s.center - pos
		var along := rel.dot(dir)
		if along > ahead_min and along < ahead_max and absf(rel.dot(side)) < s.half_length + 4.0:
			return true
	return false


## Las olas que ya quedaron atrás de todos se desvanecen (dejan lugar a nuevas).
func _retire_passed() -> void:
	var targets := _targets()
	if targets.is_empty():
		return
	var points: Array[Vector2] = []
	var dirs: Array[Vector2] = []
	for t in targets:
		points.append(Vector2(t.global_position.x, t.global_position.z))
		dirs.append(_track_dir(t))
	for s in _water.swells:
		var useful := false
		for i in points.size():
			var rel := s.center - points[i]
			if rel.dot(dirs[i]) > -s.width * 3.0 and rel.length() < 160.0:
				useful = true
				break
		if not useful:
			s.retire()


## Si no entra otra ola, saca la menos útil (la que ya se está yendo, o la más vieja).
func _free_slot() -> void:
	if _water.can_add_swell() or _water.swells.is_empty():
		return
	var worst: Swell = null
	var worst_score := -INF
	for s in _water.swells:
		var leaving := s.lifetime - s.age < s.fade_time + 0.1
		var score := s.age + (1000.0 if leaving else 0.0) - s.amplitude
		if score > worst_score:
			worst_score = score
			worst = s
	if worst:
		_water.swells.erase(worst)


## Ola de frente, probando a varias distancias (puede caer cerca de una isla).
func _make_incoming_retry(target: Rider) -> Swell:
	var player := Vector2(target.global_position.x, target.global_position.z)
	for attempt in 5:
		var s := _make_incoming(target, player)
		if s:
			return s
	return null


## Elige al azar un jugador humano alrededor del cual crear la ola
## (si solo hay bots, como en la demo, cualquiera).
func _pick_target() -> Rider:
	var humans: Array[Rider] = []
	var everyone: Array[Rider] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r:
			everyone.append(r)
			if r.is_human:
				humans.append(r)
	var pool := humans if not humans.is_empty() else everyone
	if pool.is_empty():
		return null
	return pool[_rng.randi() % pool.size()]


## Crea una ola en una posición válida (o null si no encontró lugar).
func make_swell() -> Swell:
	var target := _pick_target()
	if target == null:
		return null
	var player := Vector2(target.global_position.x, target.global_position.z)
	var f := target.forward()
	var forward := Vector2(f.x, f.z)
	if _rng.randf() < incoming_chance:
		var incoming := _make_incoming(target, player)
		if incoming:
			return incoming
	for attempt in 12:
		var s := Swell.new()
		# Más seguido adelante del jugador, para que las vea venir.
		var angle := _rng.randf_range(-1.6, 1.6)
		var dist := _rng.randf_range(spawn_distance_min, spawn_distance_max)
		s.center = player + forward.rotated(angle) * dist
		# Avanza más o menos hacia el jugador.
		s.direction = (player - s.center).normalized().rotated(_rng.randf_range(-0.8, 0.8))
		s.speed = _rng.randf_range(2.5, 5.0)
		s.max_amplitude = _rng.randf_range(amplitude_min, amplitude_max) * amplitude_scale
		# Más alta = más ancha, para que se pueda subir.
		s.width = s.max_amplitude * _rng.randf_range(1.6, 2.0)
		s.half_length = _rng.randf_range(22.0, 40.0)
		s.lifetime = _rng.randf_range(22.0, 32.0)
		s.grow_time = 3.0
		s.fade_time = 4.0
		if is_clear_of(s, player) and _far_from_island(s):
			return s
	return null


## Ola que nace adelante del jugador, siguiendo la pista, y viene de frente
## hacia él (cruza todo el ancho de la pista).
func _make_incoming(target: Rider, player: Vector2) -> Swell:
	var course := get_tree().get_first_node_in_group("course") as Course
	var s := Swell.new()
	var dist := _rng.randf_range(incoming_distance_min, incoming_distance_max)
	if course:
		var track := course.track
		var angle := track.angle_of(target.global_position)
		var lateral := track.lateral_of(target.global_position)
		var ahead_angle := angle + dist / maxf(track.radius + lateral, 10.0)
		var pos := track.position_at(ahead_angle, lateral + _rng.randf_range(-4.0, 4.0))
		var t := track.tangent_at(ahead_angle)
		s.center = Vector2(pos.x, pos.z)
		s.direction = -Vector2(t.x, t.z).normalized().rotated(_rng.randf_range(-0.15, 0.15))
		s.half_length = course.half_width + 10.0
	else:
		var f := target.forward()
		s.center = player + Vector2(f.x, f.z) * dist
		s.direction = (player - s.center).normalized()
		s.half_length = 30.0
	s.speed = _rng.randf_range(4.0, 6.5)
	s.max_amplitude = _rng.randf_range(amplitude_min, amplitude_max) * amplitude_scale
	s.width = s.max_amplitude * _rng.randf_range(1.6, 2.0)
	s.lifetime = _rng.randf_range(18.0, 26.0)
	# Crece mientras se acerca (se ve venir) y rompe más o menos cuando llega.
	s.grow_time = 2.5
	s.fade_time = 4.0
	if is_clear_of(s, player) and _far_from_island(s):
		return s
	return null


## true si el punto está lejos de la ola (ni encima ni pegado).
func is_clear_of(s: Swell, point: Vector2) -> bool:
	var uw := s.local_coords(point)
	var along := absf(uw.x) - s.width * 2.5
	var across := absf(uw.y) - s.half_length
	return along > clearance or across > clearance


## Que la ola no nazca pegada a una isla.
func _far_from_island(s: Swell) -> bool:
	for node in get_tree().get_nodes_in_group("island"):
		var island := node as Island
		if island == null:
			continue
		var c := Vector2(island.global_position.x, island.global_position.z)
		if s.center.distance_to(c) <= island.radius + s.width * 1.5 + 6.0:
			return false
	return true
