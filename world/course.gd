class_name Course
extends Node3D
## El circuito. Lee el mapa de la partida (un TrackMap en world/maps/: el
## recorrido, las islas, cuántos obstáculos) y lo arma: la pista, las islas, el
## agua alrededor, y delega lo demás:
## - CourseMarkers: corcheras, boyas y meta (flotan con el agua).
## - CourseObstacles: círculos de nitro y rocas.
## - el script `extras` del mapa (en El Atolón: géiseres, arco y barco).
## Lo que sí hace acá, en pasos fijos: aplicar a cada surfista los choques
## (islas, rocas), los géiseres, los círculos y los límites de la pista.

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
## Géiseres de la laguna (Atolón).
var geysers: Array[Geyser] = []
## -1: el clima elegido en el menú (GameSettings.weather).
@export var weather: int = -1
## La tormenta, si hay.
var storm: Storm = null

var markers: CourseMarkers
var _water: Water
var _time: float = 0.0


func _ready() -> void:
	add_to_group("course")
	GameSettings.load_settings()
	if layout < 0:
		layout = _session_config().layout
	_water = GameSession.find_in_scene(self, "water") as Water

	map = TrackMap.for_layout(layout)
	half_width = map.half_width
	if map.is_ring():
		track_radius = map.ring_radius
		island_radius = map.islands[0].z
		track = TrackSpace.new(track_radius, half_width)
		_add_island(track.center, island_radius, 0)
	else:
		track = PathTrack.new(map.path, half_width)
		for i in map.islands.size():
			var d := map.islands[i]
			_add_island(Vector2(d.x, d.y), d.z, i, i == map.volcano_index)
	island = islands[0]

	if _water:
		var fade: Array[Vector3] = []
		for isl in islands:
			fade.append(Vector3(isl.position.x, isl.position.z, isl.radius + 2.0))
		_water.set_islands(fade)
		if uses_path():
			_water.set_track(Vector2.ZERO, 0.0, 0.0)
		else:
			_water.set_track(track.center, inner_limit(), outer_limit())
	markers = CourseMarkers.new()
	markers.name = "Markers"
	add_child(markers)
	markers.build(track, half_width, _water)
	CourseObstacles.place(self, map.ring_count, map.rock_count)
	if map.extras:
		map.extras.call("build", self)
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


func is_archipelago() -> bool:
	return layout == GameSettings.TrackLayout.ARCHIPELAGO


func is_atoll() -> bool:
	return layout == GameSettings.TrackLayout.ATOLL


## Mapas con recorrido libre (no el anillo alrededor de la isla).
func uses_path() -> bool:
	return map != null and not map.is_ring()


func _add_island(center: Vector2, radius: float, index: int, volcano: bool = false) -> void:
	var isl := Island.new()
	isl.name = "Island%d" % index
	isl.radius = radius
	isl.island_seed = 11 + index * 7
	isl.volcano = volcano
	# Faro solo en las islas grandes (y en la del medio del mapa Isla).
	isl.lighthouse = not volcano and (radius >= 26.0 or not uses_path())
	isl.position = Vector3(center.x, 0.0, center.y)
	add_child(isl)
	islands.append(isl)




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

	# Géiser explotando abajo: sale volando.
	if hazards_enabled and rider.grounded and not rider.is_fallen():
		for g in geysers:
			if g.erupting() and g.covers(rider.position.x, rider.position.z):
				rider.geyser_launch(Geyser.LAUNCH_SPEED)
				break

	# Las corcheras no dejan salir de la pista (por ningún lado).
	if bounds_enabled:
		var loc := track.locate(rider.position)
		var limit := half_width - 0.6
		if absf(loc.y) > limit:
			var p := track.position_at(loc.x, clampf(loc.y, -limit, limit))
			rider.position.x = p.x
			rider.position.z = p.z
			_slide_along_edge(rider, loc, signf(loc.y))

	if not hazards_enabled:
		return

	for rock in rocks:
		if not rider.is_fallen() and rock.is_hitting(rider, _water):
			_crash(rider, _safe_position_beside(rock, rider))
			return

	if not rider.is_fallen():
		for ring in rings:
			ring.try_collect(rider, _time)


## Contra la corchera: se desliza a lo largo de ella. Se le saca solo la parte
## del rumbo que va hacia afuera (sigue avanzando) y pierde un poco de velocidad
## una sola vez al tocarla, no en cada frame.
func _slide_along_edge(rider: Rider, loc: Vector2, side: float) -> void:
	var edge := track.position_at(loc.x, side * half_width)
	var center := track.position_at(loc.x, 0.0)
	var out := Vector2(edge.x - center.x, edge.z - center.z).normalized()
	var f := rider.forward()
	var fwd := Vector2(f.x, f.z)
	var into := fwd.dot(out)
	if into <= 0.0:
		return
	var slide := fwd - out * into
	if slide.length() < 0.05:
		# De frente contra la corchera: seguir en el sentido de la carrera.
		var t := track.tangent_at(loc.x)
		slide = Vector2(t.x, t.z)
	slide = slide.normalized()
	rider.heading = atan2(-slide.x, -slide.y)
	# Pierde velocidad según qué tan de frente pegó (de refilón casi nada).
	rider.speed *= 1.0 - 0.35 * into


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
