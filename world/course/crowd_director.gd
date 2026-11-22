class_name CrowdDirector
extends Node3D
## El público de la carrera, como conjunto: los puntos de fiesta (tribuna de
## la largada, carpas de las islas, barcos), cómo reacciona la gente y cómo
## suena.
##
## - Le pasa al shader del público dónde están los surfistas: la gente está
##   tranquila y se entusiasma cuando alguien pasa cerca (y más si hace un
##   truco). Ver crowd_motion.gdshaderinc.
## - Murmullo de público que sube al acercarse a un punto de fiesta, y festejo
##   cuando alguien pasa cerca o hace un truco frente a ellos.
## - Arma la tribuna de bambú junto a la largada y unos barcos anclados con
##   gente afuera de la pista (donde hay lugar: sin islas, rocas ni piezas).

## Cerca de esto (m) de un punto de fiesta se escucha el murmullo.
const HEAR_FROM := 110.0
## Pasar a menos de esto (m) de un punto de fiesta lo hace festejar.
const CHEER_NEAR := 28.0
## Cada punto festeja como mucho una vez cada tanto (s).
const CHEER_COOLDOWN := 5.0
## Barcos con gente por mapa.
const BOATS := 3

var course: Course
## Puntos de fiesta: posición (xz) y cuánto pesan (la tribuna, más).
var _spots: Array[Vector3] = []
var _cooldown: PackedFloat32Array = PackedFloat32Array()
var _murmur: AudioStreamPlayer
var _connected: Dictionary = {}
var _boats: Array[Node3D] = []
var _water: Water


## El de esta pista (lo crea si no está).
static func of(c: Course) -> CrowdDirector:
	var d := c.get_node_or_null("CrowdDirector") as CrowdDirector
	if d == null:
		d = CrowdDirector.new()
		d.name = "CrowdDirector"
		d.course = c
		c.add_child(d)
	return d


## Un punto de fiesta (para el sonido y el festejo). `weight`: qué tan fuerte
## suena (1 una carpa, 1.6 la tribuna).
func add_spot(p: Vector3, weight: float = 1.0) -> void:
	_spots.append(Vector3(p.x, weight, p.z))
	_cooldown.append(0.0)


func spot_count() -> int:
	return _spots.size()


func _ready() -> void:
	_water = GameSession.find_in_scene(self, "water") as Water
	_murmur = AudioStreamPlayer.new()
	_murmur.stream = SfxLoop.make("res://assets/audio/sfx/crowd_loop.wav")
	_murmur.bus = "SFX"
	_murmur.volume_db = -60.0
	add_child(_murmur)


func _process(delta: float) -> void:
	var riders: Array[Rider] = []
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r and is_instance_valid(r) and not r.is_queued_for_deletion():
			riders.append(r)
	_update_shader(riders)
	_update_sound(riders, delta)
	_bob_boats()


## Dónde están los surfistas y cuántas ganas despiertan (1 pasando, 2 con un
## truco en el aire).
func _update_shader(riders: Array[Rider]) -> void:
	var list := PackedVector4Array()
	list.resize(4)
	var n := mini(riders.size(), 4)
	for i in n:
		var r := riders[i]
		var hype := 2.0 if (not r.grounded and r.live_spins > 0) else 1.0
		list[i] = Vector4(r.position.x, r.position.y, r.position.z, hype)
	for mat in BeachCrowd.materials():
		mat.set_shader_parameter("riders", list)
		mat.set_shader_parameter("rider_count", n)


func _update_sound(riders: Array[Rider], delta: float) -> void:
	for i in _cooldown.size():
		_cooldown[i] = maxf(_cooldown[i] - delta, 0.0)
	if _spots.is_empty():
		return
	# Quien escucha: las personas (en la demo, los bots).
	var listeners: Array[Rider] = []
	for r in riders:
		if r.is_human:
			listeners.append(r)
	if listeners.is_empty():
		listeners = riders
	var loud := 0.0
	for l in listeners:
		for s in _spots:
			var d := Vector2(l.position.x, l.position.z).distance_to(Vector2(s.x, s.z))
			loud = maxf(loud, smoothstep(HEAR_FROM, 18.0, d) * s.y)
	_murmur.volume_db = lerpf(-60.0, -11.0 + 4.0 * clampf(loud - 1.0, 0.0, 1.0), clampf(loud, 0.0, 1.0))
	if loud > 0.01 and not _murmur.playing and _murmur.stream:
		_murmur.play()
	elif loud <= 0.01 and _murmur.playing:
		_murmur.stop()
	# Festejo: alguien pasa cerca de un punto de fiesta.
	for r in riders:
		_connect(r)
		for i in _spots.size():
			if _cooldown[i] > 0.0:
				continue
			var s := _spots[i]
			if Vector2(r.position.x, r.position.z).distance_to(Vector2(s.x, s.z)) < CHEER_NEAR:
				_cooldown[i] = CHEER_COOLDOWN
				_cheer(r, -8.0)


## Al aterrizar un truco cerca de un punto de fiesta, festejo más fuerte.
func _connect(r: Rider) -> void:
	if _connected.has(r):
		return
	_connected[r] = true
	r.trick_landed.connect(func(_spins: int) -> void:
		if is_instance_valid(r) and near_spot(r.position, CHEER_NEAR * 1.6):
			_cheer(r, -3.0)
	)


func near_spot(p: Vector3, radius: float) -> bool:
	for s in _spots:
		if Vector2(p.x, p.z).distance_to(Vector2(s.x, s.z)) < radius:
			return true
	return false


func _cheer(r: Rider, volume_db: float) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_for(r, "cheer", volume_db, randf_range(0.95, 1.05))


# ---------------------------------------------------------------- tribuna y barcos

## Arma la tribuna junto a la largada y los barcos (si hay lugar).
func build_extras() -> void:
	var track := course.track
	var rng := RandomNumberGenerator.new()
	rng.seed = Course.seed_for(Vector2(track.position_at(0.0).x, track.position_at(0.0).z)) + 17
	_build_grandstand(rng)
	for k in BOATS:
		_build_boat(rng, float(k + 1) / (BOATS + 1))


## Lugar libre para algo de radio `r` en `p` (fuera de la pista, sin islas,
## rocas ni piezas encima). `ends`: puntas de algo largo (la tribuna) que
## tampoco pueden pisar la pista.
func is_clear(p: Vector3, r: float, ends: Array[Vector3] = []) -> bool:
	for q in [p] + ends:
		if absf(course.track.lateral_of(q)) < course.half_width + 3.0:
			return false
	for rock in course.rocks:
		if is_instance_valid(rock) and rock.position.distance_to(Vector3(p.x, rock.position.y, p.z)) < r + 8.0:
			return false
	for piece in course.pieces:
		if not piece.has_method("covers"):
			continue
		for k in 9:
			var q := p
			if k > 0:
				var a := TAU * k / 8.0
				q += Vector3(cos(a), 0.0, sin(a)) * (r + 4.0)
			if piece.covers(q.x, q.z):
				return false
	return true


## Busca un lugar a un costado de la pista cerca de `angle`, a `gap` metros del
## borde. Devuelve [posición, mirando a la pista (yaw)] o [] si no hay.
func _spot_beside(angle: float, gap: float, r: float, rng: RandomNumberGenerator) -> Array:
	var track := course.track
	var per_meter := TAU / maxf(track.length(), 1.0)
	var first_side := 1.0 if rng.randf() < 0.5 else -1.0
	for step in 12:
		var along := (step / 2 + 1) * 6.0 * (1.0 if step % 2 == 0 else -1.0) if step > 0 else 0.0
		for side in [first_side, -first_side]:
			var a := angle + along * per_meter
			var p := track.position_at(a, side * (course.half_width + gap))
			var tangent := (track.position_at(a + per_meter, side * (course.half_width + gap)) - p).normalized()
			var ends: Array[Vector3] = [p + tangent * r, p - tangent * r]
			if is_clear(p, r, ends):
				var center := track.position_at(a, 0.0)
				return [p, atan2(center.x - p.x, center.z - p.z)]
	return []


func _build_grandstand(rng: RandomNumberGenerator) -> void:
	var start := RaceManager.START_ANGLE + 30.0 * TAU / maxf(course.track.length(), 1.0)
	var found := _spot_beside(start, 9.0, BeachCrowd.STAND_LENGTH * 0.5, rng)
	if found.is_empty():
		return
	var p: Vector3 = found[0]
	var yaw: float = found[1]
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.z))
	var root := Node3D.new()
	root.name = "Grandstand"
	add_child(root)
	var hue := rng.randf()
	var stand: Array[Transform3D] = [xf]
	var stand_c: Array[Color] = [BeachCrowd.custom(rng, hue)]
	var big := BeachCrowd.multimesh("Stand", "grandstand", stand, stand_c)
	big.visibility_range_end = 0.0
	root.add_child(big)
	# Gente en las gradas (parados, haciendo la ola) y banderas arriba.
	var people := {}
	for spot in BeachCrowd.grandstand_spots():
		if rng.randf() < 0.12:
			continue
		var model := "stand%d" % (rng.randi() % BeachCrowd.STANDING)
		if not people.has(model):
			people[model] = [[] as Array[Transform3D], [] as Array[Color]]
		var t := xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), spot)
		people[model][0].append(t)
		people[model][1].append(BeachCrowd.custom(rng, hue))
	var ola := Vector2(cos(yaw), -sin(yaw))
	for model in people:
		root.add_child(BeachCrowd.multimesh("Stand_" + model, model, people[model][0], people[model][1], ola))
	var flags: Array[Transform3D] = []
	var flag_c: Array[Color] = []
	var roof := BeachCrowd.STAND_FLOOR + BeachCrowd.STAND_TIERS * BeachCrowd.STAND_STEP.x + 2.6
	for x in [-BeachCrowd.STAND_LENGTH * 0.5, 0.0, BeachCrowd.STAND_LENGTH * 0.5]:
		flags.append(xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, roof - 0.2, 0.0)))
		flag_c.append(BeachCrowd.custom(rng, hue + 0.5))
	root.add_child(BeachCrowd.multimesh("Stand_flags", "flag", flags, flag_c))
	add_spot(Vector3(p.x, 0.0, p.z), 1.6)


func _build_boat(rng: RandomNumberGenerator, fraction: float) -> void:
	var angle := RaceManager.START_ANGLE + TAU * fraction
	var found := _spot_beside(angle, rng.randf_range(14.0, 22.0), 5.0, rng)
	if found.is_empty():
		return
	var p: Vector3 = found[0]
	var boat := Node3D.new()
	boat.name = "Boat%d" % _boats.size()
	# De costado a la pista (así se ve la gente a lo largo).
	boat.rotation.y = float(found[1]) + PI * 0.5 + rng.randf_range(-0.3, 0.3)
	boat.position = Vector3(p.x, 0.0, p.z)
	add_child(boat)
	var hue := rng.randf()
	var hull: Array[Transform3D] = [Transform3D.IDENTITY]
	var hull_c: Array[Color] = [BeachCrowd.custom(rng, hue)]
	var mesh := BeachCrowd.multimesh("Hull", "boat", hull, hull_c)
	mesh.visibility_range_end = 0.0
	boat.add_child(mesh)
	var people := {}
	for spot in BeachCrowd.boat_spots():
		var model := "stand%d" % (rng.randi() % BeachCrowd.STANDING)
		if not people.has(model):
			people[model] = [[] as Array[Transform3D], [] as Array[Color]]
		# Mirando a la pista (que queda a la izquierda del barco, -X).
		people[model][0].append(Transform3D(Basis(Vector3.UP, -PI * 0.5 + rng.randf_range(-0.4, 0.4)), spot))
		people[model][1].append(BeachCrowd.custom(rng, hue + 0.5))
	for model in people:
		boat.add_child(BeachCrowd.multimesh("People_" + model, model, people[model][0], people[model][1]))
	boat.set_meta("phase", rng.randf() * TAU)
	_boats.append(boat)
	add_spot(boat.position, 0.8)


## Los barcos suben y bajan con el agua y se mecen un poco.
func _bob_boats() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for boat in _boats:
		var ph: float = boat.get_meta("phase", 0.0)
		var h := _water.height_at(boat.position.x, boat.position.z) if _water else 0.0
		boat.position.y = h * 0.85
		boat.rotation.x = sin(t * 0.9 + ph) * 0.03
		boat.rotation.z = sin(t * 0.7 + ph * 1.7) * 0.05
