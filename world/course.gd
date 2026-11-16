class_name Course
extends Node3D
## El circuito. Lee el mapa de la partida (un TrackMap en world/maps/: el
## recorrido, las islas, cuántos obstáculos, sus piezas) y lo arma: la pista,
## las islas, el agua alrededor, y delega lo demás:
## - CourseMarkers: corcheras, boyas y meta (flotan con el agua).
## - CourseObstacles: círculos de nitro y rocas.
## - las piezas del mapa (world/pieces/: volcán, géiseres, arco, cueva...). Cada
##   una se arma sola y hace lo suyo con los surfistas; acá no se sabe qué son.
## Lo que sí hace acá, en pasos fijos: aplicar a cada surfista los choques
## (islas, rocas), las piezas, los círculos y los límites de la pista.

## -1: el mapa elegido en el menú (GameSettings.track_layout).
@export var layout: int = -1

## Datos del mapa (salen del TrackMap; quedan acá porque los usa todo el juego).
var island_radius: float = 45.0
var track_radius: float = 82.0
## Mitad del ancho de la pista (m): la pista mide el doble.
var half_width: float = 20.0
var map: TrackMap
@export var layout_seed: int = 42
## Zona sin obstáculos alrededor de la salida (ángulos, en radianes).
@export var start_clear_from: float = -0.12
@export var start_clear_to: float = 0.45

## Choques con rocas e isla, y círculos de velocidad (los tests lo apagan).
var hazards_enabled: bool = true
## No dejar salir del circuito por afuera.
var bounds_enabled: bool = true

var track: TrackSpace
## La isla principal (en el mapa Isla, la del medio).
var island: Island
var islands: Array[Island] = []
var rings: Array[NitroRing] = []
var rocks: Array[Rock] = []
## Las piezas del mapa (armadas para esta carrera).
var pieces: Array[MapPiece] = []
## -1: el clima elegido en el menú (GameSettings.weather).
@export var weather: int = -1
## La tormenta, si hay.
var storm: Storm = null

var markers: CourseMarkers
var _water: Water
var _time: float = 0.0
## Corcheras: cuánto hacia adentro sale después de tocarlas (0 = paralelo), cuánta
## velocidad pierde al pegarles de frente y qué tan fuerte rebota.
const EDGE_INWARD := 0.12
const EDGE_SPEED_LOSS := 0.2
const EDGE_BOUNCE := 0.35


func _ready() -> void:
	add_to_group("course")
	GameSettings.load_settings()
	if layout < 0:
		layout = _session_config().layout
	_water = GameSession.find_in_scene(self, "water") as Water

	# Un mapa ya puesto antes de entrar (tests, probar un mapa nuevo) se usa tal cual.
	if map == null:
		map = TrackMap.for_layout(layout)
	half_width = map.half_width
	if map.is_ring():
		track_radius = map.ring_radius
		island_radius = map.islands[0].radius
		track = TrackSpace.new(track_radius, half_width)
	else:
		track = PathTrack.new(map.path, half_width, map.handles_in, map.handles_out, map.smoothing)
	# Las piezas van antes que las islas del mapa: una pieza que es una isla
	# (el volcán) queda primera, y el agua alrededor de las primeras islas se
	# dibuja con más detalle.
	pieces = map.make_pieces()
	for piece in pieces:
		piece.build(self)
	for i in map.islands.size():
		_add_map_island(map.islands[i], i)
	island = islands[0] if not islands.is_empty() else null

	if _water:
		var fade: Array[Vector3] = []
		for isl in islands:
			fade.append(Vector3(isl.position.x, isl.position.z, isl.radius + 2.0))
		_water.set_islands(fade)
		if uses_path():
			_water.set_track(Vector2.ZERO, 0.0, 0.0)
			_water.set_track_path((track as PathTrack).points, half_width)
		else:
			_water.set_track(track.center, inner_limit(), outer_limit())
	markers = CourseMarkers.new()
	markers.name = "Markers"
	add_child(markers)
	markers.build(track, half_width, _water)
	CourseObstacles.place(self, map.ring_count, map.rock_count)
	for piece in pieces:
		piece.finish(self)
	if weather < 0:
		weather = _session_config().weather
	if weather == GameSettings.Weather.STORM:
		storm = Storm.new()
		storm.name = "Storm"
		add_child(storm)


## Configuración de la partida (mapa, clima). Sin partida (una pista suelta en
## un test), la del menú.
func _session_config() -> RaceConfig:
	var session := GameSession.of(self)
	return session.config if session else RaceConfig.from_settings()


## Mapas con recorrido libre (no el anillo alrededor de la isla).
func uses_path() -> bool:
	return map != null and not map.is_ring()


## Una isla común del mapa ({x, z, radius, lighthouse, seed}).
func _add_map_island(d: Dictionary, index: int) -> void:
	var isl := Island.new()
	isl.name = "Island%d" % index
	isl.radius = d.radius
	var pos := Vector2(d.x, d.z)
	isl.island_seed = d.seed if d.seed >= 0 else seed_for(pos)
	isl.lighthouse = d.lighthouse
	isl.position = Vector3(pos.x, 0.0, pos.y)
	add_island(isl)


## Suma una isla al mapa (se choca con la orilla y el agua la rodea). La usan
## también las piezas que son islas (el volcán).
func add_island(isl: Island) -> void:
	add_child(isl, true)
	islands.append(isl)


## Semilla de palmeras para una isla sin semilla propia: sale de dónde está,
## así no cambia si se agregan o sacan otras islas.
static func seed_for(pos: Vector2) -> int:
	return absi(int(round(pos.x)) * 73856093 ^ int(round(pos.y)) * 19349663) % 100000 + 1




## Distancia a la que la orilla de la isla principal tira al jugador.
func island_crash_radius() -> float:
	return island_radius + 2.0


## Borde de afuera de la pista (corchera de afuera).
func outer_limit() -> float:
	return track_radius + half_width


## Borde de adentro de la pista (corchera de adentro, del lado de la isla).
func inner_limit() -> float:
	return track_radius - half_width



## Lo que afecta al juego (círculos, choques, géiseres, límites) va en pasos
## fijos, igual que la física de los surfistas.
func _physics_process(delta: float) -> void:
	_time += delta
	for ring in rings:
		ring.position.y = _water_height(ring.position.x, ring.position.z) + ring.radius * 0.8
	for piece in pieces:
		piece.update(self, delta)
	for node in get_tree().get_nodes_in_group("riders"):
		var rider := node as Rider
		if rider:
			_apply_to_rider(rider)


func _apply_to_rider(rider: Rider) -> void:
	var flat := Vector2(rider.position.x, rider.position.z)

	# Islas: la orilla tira de la tabla.
	if hazards_enabled and not rider.is_fallen():
		for isl in islands:
			var c := Vector2(isl.position.x, isl.position.z)
			var crash_r := isl.radius + 2.0
			var d := flat.distance_to(c)
			if d < crash_r:
				var dir := (flat - c) / d if d > 0.01 else Vector2.RIGHT
				var safe := c + dir * (crash_r + 2.0)
				_crash(rider, Vector3(safe.x, rider.position.y, safe.y))
				return

	# Lo que hacen las piezas del mapa (un géiser que lanza, una cueva...).
	for piece in pieces:
		if piece.affect_rider(self, rider):
			return

	# Las corcheras no dejan salir de la pista (por ningún lado).
	if bounds_enabled:
		var loc := track.locate(rider.position)
		var limit := half_width - 0.6
		if absf(loc.y) > limit:
			var p := track.position_at(loc.x, clampf(loc.y, -limit, limit))
			rider.position.x = p.x
			rider.position.z = p.z
			_slide_along_edge(rider, loc, signf(loc.y))
		elif absf(loc.y) < limit - 1.5:
			_leave_edge(rider)

	if not hazards_enabled:
		return

	for rock in rocks:
		if not rider.is_fallen() and rock.is_hitting(rider, _water):
			_crash(rider, _safe_position_beside(rock, rider))
			return

	if not rider.is_fallen():
		for ring in rings:
			ring.try_collect(rider, _time)


## Contra la corchera: nunca se traba. Lo endereza hacia donde avanza la
## carrera (un poquito hacia adentro), le da un rebote hacia el centro y lo deja
## resbalar pegado al borde. Frena solo un poco y una sola vez, al primer toque
## (seguir apretando contra la corchera no lo frena más). La cámara sigue sola
## el rumbo nuevo.
func _slide_along_edge(rider: Rider, loc: Vector2, side: float) -> void:
	var edge := track.position_at(loc.x, side * half_width)
	var center := track.position_at(loc.x, 0.0)
	var out := Vector2(edge.x - center.x, edge.z - center.z).normalized()
	var f := rider.forward()
	var fwd := Vector2(f.x, f.z)
	var into := fwd.dot(out)
	var first_touch := not rider.has_meta("on_edge")
	rider.set_meta("on_edge", true)
	if into <= 0.0:
		return
	# Hacia donde avanza la carrera, apenas hacia adentro (así se despega).
	var t := track.tangent_at(loc.x)
	var race_dir := Vector2(t.x, t.z).normalized()
	var dir := (race_dir - out * EDGE_INWARD).normalized()
	rider.heading = atan2(-dir.x, -dir.y)
	if first_touch:
		# Pierde algo de velocidad según qué tan de frente pegó (de refilón, casi nada).
		rider.speed *= 1.0 - EDGE_SPEED_LOSS * into
		# Rebote hacia el centro de la pista.
		var push := -out * rider.speed * into * EDGE_BOUNCE
		rider.shove += Vector3(push.x, 0.0, push.y)


## Al alejarse del borde se vuelve a poder "tocar" (el próximo toque frena).
func _leave_edge(rider: Rider) -> void:
	if rider.has_meta("on_edge"):
		rider.remove_meta("on_edge")


## Choque: se cae, queda fuera del obstáculo y mirando en el sentido de la
## carrera (para no volver a chocarlo apenas se levanta).
func _crash(rider: Rider, safe_position: Vector3) -> void:
	rider.crash(safe_position)
	rider.heading = track.heading_at(track.angle_of(rider.position))


## Al lado de la roca, hacia adentro o afuera de la pista (del lado donde estaba
## el Rider). Así, al seguir en el sentido de la carrera, se aleja de la roca.
func _safe_position_beside(rock: Rock, rider: Rider) -> Vector3:
	# Dirección "de costado" de la pista donde está la roca.
	var a := track.angle_of(rock.position)
	var side_dir := track.position_at(a, 1.0) - track.position_at(a, 0.0)
	var radial := Vector2(side_dir.x, side_dir.z).normalized()
	var rel := Vector2(rider.position.x - rock.position.x, rider.position.z - rock.position.z)
	var side := 1.0 if rel.dot(radial) >= 0.0 else -1.0
	var p := Vector2(rock.position.x, rock.position.z) + radial * side * (rock.radius + 2.0)
	return Vector3(p.x, rider.position.y, p.y)






## Zona sin obstáculos alrededor de la salida.
func in_start_zone(angle: float) -> bool:
	return angle > start_clear_from and angle < start_clear_to










func _water_height(x: float, z: float) -> float:
	return _water.height_at(x, z) if _water else 0.0
