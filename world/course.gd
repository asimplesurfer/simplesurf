class_name Course
extends Node3D
## El circuito. Lee el mapa de la partida (un TrackMap en world/maps/: el
## recorrido, cuántos obstáculos, sus piezas) y lo arma: la pista, el agua
## alrededor, y delega lo demás:
## - CourseMarkers: corcheras, boyas y meta (flotan con el agua).
## - CourseObstacles: círculos de nitro y rocas.
## - las piezas del mapa (world/pieces/: islas, géiseres, arco, cueva...). Cada
##   una se arma sola y hace lo suyo con los surfistas; acá no se sabe qué son.
## Lo que sí hace acá, en pasos fijos: aplicar a cada surfista las piezas, los
## choques con rocas, los círculos y los límites de la pista.

## -1: el mapa elegido en el menú (GameSettings.track_layout).
@export var layout: int = -1

## Datos del mapa (salen del TrackMap; quedan acá porque los usa todo el juego).
## Radio del anillo (solo en los mapas anillo).
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
var rings: Array[NitroRing] = []
var rocks: Array[Rock] = []
## Las piezas del mapa (armadas para esta carrera).
var pieces: Array[MapPiece] = []
## Registro de las piezas: cada una se anota con un tipo para que las otras la
## encuentren (por ejemplo "ground": las que son tierra).
var _registry: Dictionary = {}
## -1: el clima elegido en el menú (GameSettings.weather).
@export var weather: int = -1
## -1: la hora elegida en el menú (GameSettings.time_of_day; ver DayTime).
@export var time_of_day: int = -1
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
	# La hora va primero: las piezas (las guirnaldas) miran si es de noche.
	if time_of_day < 0:
		time_of_day = _session_config().time_of_day
	if get_parent() and get_parent().get_node_or_null("WorldEnvironment"):
		DayTime.apply(get_parent(), time_of_day)

	# Un mapa ya puesto antes de entrar (tests, probar un mapa nuevo) se usa tal cual.
	if map == null:
		map = TrackMap.for_layout(layout)
	half_width = map.half_width
	if map.is_ring():
		track_radius = map.ring_radius
	track = map.make_track()
	pieces = map.make_pieces()
	# Primero todas se preparan (y se anotan: "soy tierra"...), después se
	# construyen: así cada una puede tener en cuenta a las demás. Al prepararse
	# una pieza puede sumar otras (una isla partida en dos por un corte): esas
	# también se preparan.
	var k := 0
	while k < pieces.size():
		pieces[k].prepare(self)
		k += 1
	for piece in pieces:
		piece.build(self)

	if _water:
		# La tierra apaga las olas grandes cerca de la orilla.
		_water.set_land(land_outlines())
		if uses_path():
			_water.set_track(Vector2.ZERO, 0.0, 0.0)
			# Con los caminos alternativos (el agua de la pista es una banda por todos).
			_water.set_track_path((track as PathTrack).all_points(), half_width)
		else:
			_water.set_track(track.center, inner_limit(), outer_limit())
	markers = CourseMarkers.new()
	markers.name = "Markers"
	add_child(markers)
	markers.build(track, half_width, _water)
	CourseObstacles.place(self, map.ring_count, map.rock_count)
	for piece in pieces:
		piece.finish(self)
	# Público: la tribuna de la largada y los barcos con gente (las islas
	# tropicales ya pusieron su gente en la playa).
	CrowdDirector.of(self).build_extras()
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


## Anota algo en el registro de las piezas (ver `_registry`).
func register(kind: String, item: Object) -> void:
	if not _registry.has(kind):
		_registry[kind] = []
	_registry[kind].append(item)


## Lo anotado de un tipo (vacío si no hay nada).
func registered(kind: String) -> Array:
	return _registry.get(kind, [])


## Toda la tierra del mapa, vista desde arriba (las figuras de las piezas
## anotadas como "ground"; ver MapPiece.prepare).
func land_outlines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for g in registered("ground"):
		var o: PackedVector2Array = g.outline()
		if o.size() >= 3:
			out.append(o)
	return out


## Semilla para algo que no la trae: sale de dónde está, así no cambia si se
## agregan o sacan otras cosas del mapa.
static func seed_for(pos: Vector2) -> int:
	return absi(int(round(pos.x)) * 73856093 ^ int(round(pos.y)) * 19349663) % 100000 + 1




## Borde de afuera de la pista (corchera de afuera).
func outer_limit() -> float:
	return track_radius + half_width


## Borde de adentro de la pista (corchera de adentro, del lado del centro).
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
	# Adentro de un tubo lo lleva la ola: nada del mapa lo toca.
	if rider.in_tube():
		return
	# Lo que hacen las piezas del mapa (una isla que se choca, un géiser que
	# lanza, una cueva...).
	for piece in pieces:
		if piece.affect_rider(self, rider):
			return

	# Las corcheras no dejan salir de la pista (por ningún lado).
	if bounds_enabled:
		# Sobre el camino más cercano (en una bifurcación, por el que va).
		var loc := track.locate_route(rider.position)
		var route := int(loc.z)
		var limit := half_width - 0.6
		if absf(loc.y) > limit:
			var p := track.position_on(route, loc.x, clampf(loc.y, -limit, limit))
			rider.position.x = p.x
			rider.position.z = p.z
			_slide_along_edge(rider, Vector2(loc.x, loc.y), signf(loc.y), route)
		elif absf(loc.y) < limit - 1.5:
			_leave_edge(rider)

	if not hazards_enabled:
		return

	for rock in rocks:
		# Las que esconde un tubo no están.
		if rock.visible and not rider.is_fallen() and rock.is_hitting(rider, _water):
			_crash(rider, _safe_position_beside(rock, rider))
			return

	if not rider.is_fallen():
		for ring in rings:
			if ring.visible:
				ring.try_collect(rider, _time)


## Contra la corchera: nunca se traba. Lo endereza hacia donde avanza la
## carrera (un poquito hacia adentro), le da un rebote hacia el centro y lo deja
## resbalar pegado al borde. Frena solo un poco y una sola vez, al primer toque
## (seguir apretando contra la corchera no lo frena más). La cámara sigue sola
## el rumbo nuevo.
func _slide_along_edge(rider: Rider, loc: Vector2, side: float, route: int = 0) -> void:
	var edge := track.position_on(route, loc.x, side * half_width)
	var center := track.position_on(route, loc.x, 0.0)
	var out := Vector2(edge.x - center.x, edge.z - center.z).normalized()
	var f := rider.forward()
	var fwd := Vector2(f.x, f.z)
	var into := fwd.dot(out)
	var first_touch := not rider.has_meta("on_edge")
	rider.set_meta("on_edge", true)
	if into <= 0.0:
		return
	# Hacia donde avanza la carrera, apenas hacia adentro (así se despega).
	var t := track.tangent_on(route, loc.x)
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
## carrera (para no volver a chocarlo apenas se levanta). Lo usan también las
## piezas que se chocan (una isla tropical).
func crash(rider: Rider, safe_position: Vector3) -> void:
	_crash(rider, safe_position)


## Seguro: un choque nunca lleva al surfista a más de MAX_CRASH_SHIFT metros
## de donde estaba (el lugar "afuera" de una roca o de la orilla queda siempre
## cerca). Si da más lejos, algo salió mal: no cuenta como choque.
const MAX_CRASH_SHIFT := 10.0


func _crash(rider: Rider, safe_position: Vector3) -> void:
	var shift := Vector2(safe_position.x - rider.position.x, safe_position.z - rider.position.z).length()
	if shift > MAX_CRASH_SHIFT:
		push_warning("choque ignorado: lo mandaba %.0f m lejos" % shift)
		return
	rider.crash(safe_position)
	var loc := track.locate_route(rider.position)
	rider.heading = track.heading_on(int(loc.z), loc.x)


## Al lado de la roca, hacia adentro o afuera de la pista (del lado donde estaba
## el Rider). Así, al seguir en el sentido de la carrera, se aleja de la roca.
func _safe_position_beside(rock: Rock, rider: Rider) -> Vector3:
	# Dirección "de costado" de la pista donde está la roca.
	var loc := track.locate_route(rock.position)
	var side_dir := track.position_on(int(loc.z), loc.x, 1.0) - track.position_on(int(loc.z), loc.x, 0.0)
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
