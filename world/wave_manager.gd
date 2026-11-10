class_name WaveManager
extends Node
## Hace aparecer olas grandes al azar alrededor del jugador (modo "oleadas").
## Nunca aparecen encima del jugador: nacen lejos de él y crecen de a poco.

@export var enabled: bool = true
## Nodo alrededor del cual aparecen (normalmente el Rider).
@export var follow_path: NodePath
## 0 = distinto cada partida.
@export var random_seed: int = 0
@export var spawn_interval_min: float = 2.0
@export var spawn_interval_max: float = 4.5
## Distancia al jugador a la que pueden nacer (m).
@export var spawn_distance_min: float = 30.0
@export var spawn_distance_max: float = 75.0
## Distancia mínima entre el jugador y cualquier parte de la ola al nacer (m).
@export var clearance: float = 12.0
@export var amplitude_min: float = 1.3
@export var amplitude_max: float = 2.3

var _rng := RandomNumberGenerator.new()
var _timer: float = 1.0
var _water: Water
var _follow: Node3D


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_water = get_tree().get_first_node_in_group("water") as Water
	_follow = get_node_or_null(follow_path) as Node3D


func _process(delta: float) -> void:
	if not enabled or _water == null or _follow == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(spawn_interval_min, spawn_interval_max)
	if _water.can_add_swell():
		var s := make_swell()
		if s:
			_water.add_swell(s)


## Crea una ola en una posición válida (o null si no encontró lugar).
func make_swell() -> Swell:
	var player := Vector2(_follow.global_position.x, _follow.global_position.z)
	var forward := Vector2.UP
	if _follow is Rider:
		var f := (_follow as Rider).forward()
		forward = Vector2(f.x, f.z)
	for attempt in 12:
		var s := Swell.new()
		# Más seguido adelante del jugador, para que las vea venir.
		var angle := _rng.randf_range(-1.6, 1.6)
		var dist := _rng.randf_range(spawn_distance_min, spawn_distance_max)
		s.center = player + forward.rotated(angle) * dist
		# Avanza más o menos hacia el jugador.
		s.direction = (player - s.center).normalized().rotated(_rng.randf_range(-0.8, 0.8))
		s.speed = _rng.randf_range(3.0, 6.0)
		s.max_amplitude = _rng.randf_range(amplitude_min, amplitude_max)
		s.width = _rng.randf_range(3.5, 5.0)
		s.half_length = _rng.randf_range(12.0, 24.0)
		s.lifetime = _rng.randf_range(10.0, 16.0)
		if is_clear_of(s, player):
			return s
	return null


## true si el punto está lejos de la ola (ni encima ni pegado).
func is_clear_of(s: Swell, point: Vector2) -> bool:
	var uw := s.local_coords(point)
	var along := absf(uw.x) - s.width * 2.5
	var across := absf(uw.y) - s.half_length
	return along > clearance or across > clearance
