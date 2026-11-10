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
@export var spawn_interval_min: float = 0.8
@export var spawn_interval_max: float = 2.0
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

var mode: GameSettings.WaveMode = GameSettings.WaveMode.SURGES

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
	if mode == GameSettings.WaveMode.CONSTANT_LEFT:
		_water.set_ring_wave(make_ring_wave())
	else:
		_water.set_ring_wave(null)


## La ola constante, alrededor de la isla por el lado de afuera de la pista.
func make_ring_wave() -> RingWave:
	var rw := RingWave.new()
	var course := get_tree().get_first_node_in_group("course") as Course
	if course:
		rw.center = course.track.center
		rw.radius = course.track.radius + constant_lateral
	return rw


func _process(delta: float) -> void:
	if not enabled or _water == null or mode != GameSettings.WaveMode.SURGES:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(spawn_interval_min, spawn_interval_max)
	if _water.can_add_swell():
		var s := make_swell()
		if s:
			_water.add_swell(s)


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
		s.max_amplitude = _rng.randf_range(amplitude_min, amplitude_max)
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
	s.max_amplitude = _rng.randf_range(amplitude_min, amplitude_max)
	s.width = s.max_amplitude * _rng.randf_range(1.6, 2.0)
	s.lifetime = _rng.randf_range(18.0, 26.0)
	s.grow_time = 2.0
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


## Que la ola no nazca pegada a la isla.
func _far_from_island(s: Swell) -> bool:
	var island := get_tree().get_first_node_in_group("island") as Island
	if island == null:
		return true
	var c := Vector2(island.global_position.x, island.global_position.z)
	return s.center.distance_to(c) > island.radius + s.width * 3.0 + 10.0
