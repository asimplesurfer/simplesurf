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
## Contrarreloj: las olas grandes salen siempre en los mismos lugares de la
## pista (sembradas por mapa), cuando el corredor se acerca. Así cada intento
## tiene las mismas olas y los tiempos se pueden comparar.
var fixed_waves: bool = false
## Olas fijas: [metros donde aparece, metros donde se dispara, lateral,
## altura, ancho (x altura), velocidad, vida, giro].
var _fixed: Array = []
var _next_fixed: int = 0
## Dónde nació cada ola fija (x, z), en orden (para comparar intentos).
var fixed_spawned: Array = []
## Versión de las olas fijas: si cambia la forma de armarlas, los récords
## hechos con las de antes quedan archivados (ver TimeTrial._version).
const FIXED_VERSION := 2
## Las olas fijas vienen en series, como en el mar: de 2 a 4 olas seguidas que
## van creciendo (la última, la más grande, es la mejor rampa), y un respiro
## entre series. Cuántas olas por serie (entre los dos).
const FIXED_SET_SIZE := Vector2i(2, 4)
## Metros de pista entre olas de una misma serie y entre series.
const FIXED_SPACING := Vector2(24.0, 34.0)
const FIXED_SET_GAP := Vector2(42.0, 56.0)
## Altura (m) de la primera ola de una serie y de la última.
const FIXED_FIRST_AMP := Vector2(3.4, 4.2)
const FIXED_LAST_AMP := Vector2(5.0, 6.0)


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_water = GameSession.find_in_scene(self, "water") as Water
	GameSettings.load_settings()
	set_mode(GameSettings.wave_mode)


## Cambia el modo de olas (saca las olas del modo anterior).
func set_mode(new_mode: GameSettings.WaveMode) -> void:
	mode = new_mode
	if _water == null:
		return
	_water.clear_swells()
	# La ola constante da la vuelta a la isla: solo existe en el mapa Isla.
	var course := GameSession.find_in_scene(self, "course") as Course
	if course and course.track is PathTrack and mode == GameSettings.WaveMode.CONSTANT_LEFT:
		mode = GameSettings.WaveMode.SURGES
	if mode == GameSettings.WaveMode.CONSTANT_LEFT:
		_water.set_ring_wave(make_ring_wave())
	else:
		_water.set_ring_wave(null)


## Modo libre: cambia la altura de las olas. Va de a poco (las que ya están
## crecen o se achican durante un par de segundos); con 0 se van todas.
## Con `instant`, sin transición (al arrancar el modo libre en el nivel guardado).
func set_amplitude_scale(value: float, instant: bool = false) -> void:
	_target_scale = maxf(value, 0.0)
	if instant:
		amplitude_scale = _target_scale


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
	var course := GameSession.find_in_scene(self, "course") as Course
	if course:
		rw.center = course.track.center
		rw.radius = course.track.radius + constant_lateral
	return rw


## En pasos fijos: cuándo y dónde nacen las olas no depende de los FPS.
func _physics_process(delta: float) -> void:
	_ramp_scale(delta)
	if not enabled or _water == null or mode != GameSettings.WaveMode.SURGES or amplitude_scale <= 0.0:
		return
	_retire_passed()
	if fixed_waves:
		_update_fixed()
		return
	# Mientras hay una ola tubo no salen olas nuevas (se mezclarían con el tubo y
	# así se ve claro adónde ir).
	if not get_tree().get_nodes_in_group("tube_waves").is_empty():
		return
	# Recién largada: unos segundos de calma (si no, al estar todos juntos les
	# llegan varias olas seguidas antes de poder verlas).
	var race := GameSession.find_in_scene(self, "race_manager") as RaceManager
	if race and (race.state == RaceManager.State.COUNTDOWN or race.race_time < START_CALM):
		return
	# Nunca un rato largo sin olas: cada grupo de corredores (los que van a
	# menos de GROUP_DISTANCE entre sí) tiene que tener una viniendo. Los que
	# van juntos comparten las olas (no una por cada uno).
	_ensure_timer -= delta
	if _ensure_timer <= 0.0:
		_ensure_timer = ensure_interval
		var served: Array[Rider] = []
		for target in _targets():
			var grouped := false
			for other in served:
				if other.global_position.distance_to(target.global_position) < GROUP_DISTANCE:
					grouped = true
					break
			if grouped:
				continue
			served.append(target)
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


## Olas fijas de la contrarreloj: cada una aparece adelante del corredor
## cuando llega a su punto de la pista (siempre las mismas, en el mismo orden).
func _update_fixed() -> void:
	var course := GameSession.find_in_scene(self, "course") as Course
	var race := GameSession.find_in_scene(self, "race_manager") as RaceManager
	if course == null or race == null or race.racers.is_empty():
		return
	var track := course.track
	var lap_m := track.length()
	if _fixed.is_empty():
		_build_fixed(course, race.config.laps * lap_m + 200.0)
	var r := race.racers[0]
	var at_m := race.progress_of(r) / TAU * lap_m
	while _next_fixed < _fixed.size() and at_m >= float(_fixed[_next_fixed][1]):
		var f: Array = _fixed[_next_fixed]
		_next_fixed += 1
		var angle: float = float(f[0]) / lap_m * TAU
		var pos := track.position_at(angle, f[2])
		var t := track.tangent_at(angle)
		var s := Swell.new()
		s.center = Vector2(pos.x, pos.z)
		s.direction = -Vector2(t.x, t.z).normalized().rotated(f[7])
		s.half_length = course.half_width + 10.0
		s.max_amplitude = f[3]
		s.width = s.max_amplitude * float(f[4])
		s.speed = f[5]
		s.lifetime = f[6]
		s.grow_time = 2.5
		s.fade_time = 4.0
		if not _far_from_island(s):
			continue
		_free_slot()
		if _water.can_add_swell():
			_water.add_swell(s)
			fixed_spawned.append([snappedf(s.center.x, 0.01), snappedf(s.center.y, 0.01)])


## Arma la lista de olas fijas para `total_m` metros de pista (semilla por
## mapa: sale de su nombre, así reordenar los mapas no las cambia).
func _build_fixed(course: Course, total_m: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (course.map.id.hash() % 100000 + 1) + 31
	var d := 45.0
	while d < total_m:
		var count := rng.randi_range(FIXED_SET_SIZE.x, FIXED_SET_SIZE.y)
		var first := rng.randf_range(FIXED_FIRST_AMP.x, FIXED_FIRST_AMP.y)
		var last := rng.randf_range(FIXED_LAST_AMP.x, FIXED_LAST_AMP.y)
		# La serie entra de un mismo lado (cada ola corrida un poco).
		var side := rng.randf_range(-5.0, 5.0)
		for i in count:
			if d >= total_m:
				break
			var ahead := rng.randf_range(incoming_distance_min, incoming_distance_max)
			var amp := lerpf(first, last, float(i) / float(count - 1))
			_fixed.append([
				d, d - ahead, clampf(side + rng.randf_range(-2.0, 2.0), -6.0, 6.0), amp,
				rng.randf_range(1.6, 2.0), rng.randf_range(4.0, 6.5), rng.randf_range(16.0, 22.0),
				rng.randf_range(-0.15, 0.15),
			])
			d += rng.randf_range(FIXED_SPACING.x, FIXED_SPACING.y)
		d += rng.randf_range(FIXED_SET_GAP.x, FIXED_SET_GAP.y) - FIXED_SPACING.x
	_next_fixed = 0


## Corredores a los que se les garantizan olas: todos, personas y bots (antes
## solo las personas, y los bots que quedaban lejos no tenían ninguna ola:
## no saltaban, no juntaban nitro y quedaban muy atrás).
func _targets() -> Array[Rider]:
	var everyone: Array[Rider] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r and not r.race_finished:
			everyone.append(r)
	return everyone


## Dirección de la pista donde está el corredor (o su frente, si no hay pista).
func _track_dir(r: Rider) -> Vector2:
	var course := GameSession.find_in_scene(self, "course") as Course
	if course:
		var loc := course.track.locate_route(r.global_position)
		var t := course.track.tangent_on(int(loc.z), loc.x)
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


## Las olas que ya no le sirven a nadie se desvanecen (dejan lugar a nuevas).
## Una ola sirve si algún corredor la tiene adelante y cerca, o si alguna
## persona la puede estar viendo (así nunca se ve desaparecer una ola).
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
		if _seen_by_people(s):
			continue
		var useful := false
		for i in points.size():
			var rel := s.center - points[i]
			if rel.dot(dirs[i]) > -s.width * 3.0 and rel.length() < 160.0:
				useful = true
				break
		if not useful:
			s.retire()


## Distancia hasta la que una persona puede ver una ola (m): la cámara ve hasta
## ~320 m, con bruma desde ~170.
const SEEN_DISTANCE := 260.0
## Una ola a la que le queda menos que esto (s) ya casi no se ve.
const ALMOST_GONE := 0.8
## Desvanecido rápido (s) cuando hay que hacer lugar y todas se ven.
const QUICK_FADE := 1.5


## true si alguna persona (o la cámara de la demo) puede estar viendo la ola:
## la tiene adelante y no muy lejos (las de atrás no se ven).
func _seen_by_people(s: Swell) -> bool:
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r == null or not r.has_view:
			continue
		var p := Vector2(r.global_position.x, r.global_position.z)
		var rel := s.center - p
		# Adelante (donde mira la cámara) y dentro de lo que llega a verse.
		if rel.length() - s.half_length < SEEN_DISTANCE and rel.dot(_track_dir(r)) > -s.width * 3.0 - 8.0:
			return true
	return false


## Si no entra otra ola, saca la menos útil que nadie esté viendo (la que ya
## se está yendo, o la más vieja). Si todas se ven, no saca ninguna de golpe:
## la menos útil empieza a desvanecerse y la nueva espera.
func _free_slot() -> void:
	if _water.can_add_swell() or _water.swells.is_empty():
		return
	var worst: Swell = null
	var worst_score := -INF
	var worst_seen: Swell = null
	var worst_seen_score := -INF
	for s in _water.swells:
		var leaving := s.lifetime - s.age < s.fade_time + 0.1
		var score := s.age + (1000.0 if leaving else 0.0) - s.amplitude
		if _seen_by_people(s):
			if score > worst_seen_score:
				worst_seen_score = score
				worst_seen = s
		elif score > worst_score:
			worst_score = score
			worst = s
	if worst:
		_water.swells.erase(worst)
		return
	# Todas se ven: sale una que ya casi terminó de desvanecerse (no se nota);
	# si no hay, la menos útil se desvanece rápido (nunca de golpe).
	for sw in _water.swells:
		if sw.lifetime - sw.age < ALMOST_GONE:
			_water.swells.erase(sw)
			return
	if worst_seen:
		worst_seen.fade_time = minf(worst_seen.fade_time, QUICK_FADE)
		worst_seen.retire()


## Corredores a menos de esto (m) comparten las olas.
const GROUP_DISTANCE := 35.0
## Distancia mínima (m) entre una ola nueva y las que ya hay: siempre se llega a
## ver la siguiente antes de que llegue.
const MIN_WAVE_GAP := 30.0
## Segundos de calma (sin olas grandes nuevas) al largar.
const START_CALM := 3.0


## true si la ola nueva queda lejos de las que ya hay.
func _spaced(s: Swell) -> bool:
	for other in _water.swells:
		if other.lifetime - other.age < other.fade_time:
			continue
		if other.center.distance_to(s.center) < MIN_WAVE_GAP:
			return false
	return true


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
		if is_clear_of(s, player) and _far_from_island(s) and _spaced(s):
			return s
	return null


## Ola que nace adelante del jugador, siguiendo la pista, y viene de frente
## hacia él (cruza todo el ancho de la pista).
func _make_incoming(target: Rider, player: Vector2) -> Swell:
	var course := GameSession.find_in_scene(self, "course") as Course
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
	if is_clear_of(s, player) and _far_from_island(s) and _spaced(s):
		return s
	return null


## true si el punto está lejos de la ola (ni encima ni pegado).
func is_clear_of(s: Swell, point: Vector2) -> bool:
	var uw := s.local_coords(point)
	var along := absf(uw.x) - s.width * 2.5
	var across := absf(uw.y) - s.half_length
	return along > clearance or across > clearance


## Que la ola no nazca pegada a una isla (a menos de unos 28 m de la orilla,
## donde el agua ya apaga las olas grandes).
func _far_from_island(s: Swell) -> bool:
	return _water == null or _water.land_fade(s.center) >= 0.999
