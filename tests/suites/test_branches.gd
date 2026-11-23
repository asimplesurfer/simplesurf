extends "res://tests/test_base.gd"
## Bifurcaciones: tramos de la pista con más de un camino (ramales).

## Un mapa de prueba: una vuelta con dos tramos con bifurcación. En el
## primero hay cuatro caminos (la principal, uno por afuera, otro por adentro y
## otro que cruza la principal, como una X); en el segundo, dos.
const TEST_MAP := {
	"id": "test_branches", "name": "prueba", "order": 99, "laps": 1, "half_width": 16,
	"start": {"x": 0, "z": 0, "angle": 0},
	"path": [[250, -20], [320, -150], [250, -300], [0, -330], [-180, -250], [-200, -80]],
	"branches": [
		{"from": 1, "to": 3, "path": [[440, -300], [220, -460]]},
		{"from": 1, "to": 3, "path": [[170, -180], [80, -250]]},
		{"from": 4, "to": 5, "path": [[-320, -170]]},
		{"from": 1, "to": 3, "path": [[390, -230], [180, -265]]},
	],
	"ring_count": 10, "rock_count": 8,
}


func run() -> void:
	_test_format()
	_test_geometry()
	_test_variants()
	_test_shape()
	await _test_course()
	await _test_bots()


func _map() -> TrackMap:
	var errors := PackedStringArray()
	var m := TrackMap.from_dict(TEST_MAP.duplicate(true), errors)
	_check(errors.is_empty(), "el mapa de prueba se lee sin errores %s" % str(errors))
	return m


func _test_format() -> void:
	print("Bifurcaciones en el archivo del mapa:")
	var m := _map()
	_check(m.branches.size() == 4, "se leen los 4 caminos alternativos")
	var again := TrackMap.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(again.branches.size() == 4 and again.branches[1].path == m.branches[1].path
		and again.branches[2].from == 4 and again.branches[2].to == 5,
		"se guardan y se vuelven a leer igual")
	# Errores que se avisan.
	var bad := {
		"vuelve para atrás": {"from": 3, "to": 1, "path": [[0, 0]]},
		"sin puntos": {"from": 1, "to": 3, "path": []},
		"fuera del recorrido": {"from": 1, "to": 9, "path": [[0, 0]]},
	}
	for why in bad:
		var d: Dictionary = TEST_MAP.duplicate(true)
		(d.branches as Array).append(bad[why])
		var errors := PackedStringArray()
		TrackMap.from_dict(d, errors)
		_check(not errors.is_empty(), "un camino que %s da error" % why)
	# Caminos que se pisan en parte (uno sale antes de que vuelva otro): valen.
	var over: Dictionary = TEST_MAP.duplicate(true)
	(over.branches as Array).append({"from": 2, "to": 4, "path": [[120, -380]]})
	var over_errors := PackedStringArray()
	TrackMap.from_dict(over, over_errors)
	_check(over_errors.is_empty(), "un camino que se pisa en parte con otro tramo vale %s" % str(over_errors))
	var ring := {"id": "r", "branches": [{"from": 0, "to": 1, "path": [[0, 0]]}]}
	var errors := PackedStringArray()
	TrackMap.from_dict(ring, errors)
	_check(not errors.is_empty(), "una pista anillo no puede tener caminos alternativos")


func _test_geometry() -> void:
	print("Forma de los caminos:")
	var track := _map().make_track() as PathTrack
	_check(track.route_count() == 5, "5 caminos (la principal y 4 alternativos)")
	var joins := true
	var far := true
	var smooth := true
	for k in track.branches.size():
		var b := track.branches[k]
		var a0 := track.position_at(b.s_from / track.length() * TAU)
		var a1 := track.position_at(b.s_to / track.length() * TAU)
		var first := b.points[0]
		var last := b.points[b.points.size() - 1]
		joins = joins and first.distance_to(Vector2(a0.x, a0.z)) < 0.5 and last.distance_to(Vector2(a1.x, a1.z)) < 0.5
		# En el medio se separa de la principal (más que el ancho de la pista).
		var mid := track.branch_position(b, b.length * 0.5)
		var main_mid := track._project(Vector2(mid.x, mid.z))
		far = far and sqrt(main_mid.z) > track.half_width * 2.0
		# Sin quiebres donde se separa y donde vuelve: la dirección cambia poco
		# de una muestra a la otra.
		for i in range(1, b.points.size() - 1):
			if i > 20 and i < b.points.size() - 21:
				continue
			var d0 := (b.points[i] - b.points[i - 1]).normalized()
			var d1 := (b.points[i + 1] - b.points[i]).normalized()
			smooth = smooth and absf(d0.angle_to(d1)) < deg_to_rad(8.0)
	_check(joins, "cada camino sale de la principal y vuelve a entrar en ella")
	_check(far, "en el medio, cada camino va lejos de la principal")
	_check(smooth, "los caminos salen y vuelven a entrar sin quiebres")
	# Ubicarse: sobre un camino alternativo se sabe por cuál va, y el avance
	# es el del tramo que reemplaza.
	var b := track.branches[0]
	var ok_route := true
	var ok_angle := true
	var prev := -INF
	for i in range(1, 20):
		var s := b.length * i / 20.0
		var p := track.branch_position(b, s, 3.0)
		var loc := track.locate_route(p)
		ok_route = ok_route and int(loc.z) == 1 and absf(loc.y - 3.0) < 0.5
		var a := wrapf(loc.x, 0.0, TAU)
		ok_angle = ok_angle and a > prev and a >= b.s_from / track.length() * TAU - 0.001 and a <= b.s_to / track.length() * TAU + 0.001
		prev = a
		var back := track.position_on(1, loc.x, loc.y)
		ok_route = ok_route and back.distance_to(p) < 0.5
	_check(ok_route, "en el camino alternativo se sabe por cuál va y a qué distancia del medio")
	_check(ok_angle, "el avance por el camino alternativo crece parejo dentro de su tramo")
	# Un camino que cruza la principal (una X): pasa de un lado al otro.
	var cross := track.branches[3]
	var sides := {}
	for i in range(0, cross.points.size(), 3):
		var pr := track._project(cross.points[i])
		if sqrt(pr.z) > track.half_width * 1.5:
			sides[signf(pr.y)] = true
	_check(sides.size() == 2, "el camino en X pasa de un lado al otro de la principal")
	var on_main := track.position_at(TAU * 0.05, -4.0)
	_check(int(track.locate_route(on_main).z) == 0, "fuera de los tramos se está en la principal")


func _test_variants() -> void:
	print("Vueltas por cada camino:")
	var track := _map().make_track() as PathTrack
	var choices := track.all_choices()
	_check(choices.size() == 8, "hay 8 combinaciones de caminos (%d)" % choices.size())
	var ok := true
	for c in choices:
		var v := track.variant(c)
		var expected := track.length()
		for r in c:
			expected += track.route_extra(r)
		ok = ok and absf(v.length() - expected) < expected * 0.02
		ok = ok and v.position_at(0.0).distance_to(track.position_at(0.0)) < 1.0
	_check(ok, "cada vuelta mide lo que suman sus caminos y empieza en la meta")
	_check(track.variant([]) == track.variant([]), "cada vuelta se arma una sola vez")
	var lengths: Array[float] = [track.main_span(1), track.branches[0].length, track.branches[1].length]
	_check(lengths[2] < lengths[0] and lengths[0] < lengths[1],
		"el camino de adentro es el más corto y el de afuera el más largo (%d / %d / %d m)" % [lengths[2], lengths[0], lengths[1]])
	# Caminos que se pisan en parte: una vuelta toma uno o el otro, nunca los dos.
	var over: Dictionary = TEST_MAP.duplicate(true)
	(over.branches as Array).append({"from": 2, "to": 4, "path": [[120, -380]]})
	var ot := TrackMap.from_dict(over).make_track() as PathTrack
	var both := false
	var alone := false
	for c in ot.all_choices():
		var has5 := (c as Array).has(5)
		var crossing := false
		for r in c:
			if int(r) != 5 and has5 and ot.branches[int(r) - 1].s_from < ot.branches[4].s_to and ot.branches[4].s_from < ot.branches[int(r) - 1].s_to:
				crossing = true
		both = both or crossing
		alone = alone or has5
	_check(alone and not both, "con caminos que se pisan, cada vuelta toma uno solo de ellos")
	var v5 := ot.variant([5])
	_check(absf(v5.length() - (ot.length() + ot.route_extra(5))) < ot.length() * 0.02, "la vuelta por el camino que se pisa mide lo que tiene que medir")


func _test_shape() -> void:
	print("Récords con caminos alternativos:")
	var m := _map()
	var shape := m.track_shape()
	_check(TrackMap.same_shape(shape, _map().track_shape()), "la misma pista es la misma")
	var d: Dictionary = TEST_MAP.duplicate(true)
	d.branches[0].path[0] = [500, -300]
	_check(not TrackMap.same_shape(shape, TrackMap.from_dict(d).track_shape()), "mover un camino alternativo es otra pista")
	d = TEST_MAP.duplicate(true)
	(d.branches as Array).remove_at(2)
	_check(not TrackMap.same_shape(shape, TrackMap.from_dict(d).track_shape()), "sacar un camino alternativo también")
	var atoll := TrackMap.for_layout(TrackMap.index_of("atoll"))
	_check(not atoll.track_shape().has("branches"), "los mapas sin bifurcaciones guardan la huella de siempre")


## Arma una carrera en el mapa de prueba (bots con los niveles pedidos).
func _start(levels: Array) -> Node:
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for level in levels:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("Course") as Course).map = _map()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	return m


func _test_course() -> void:
	print("Pista con bifurcaciones:")
	var m := _start([1])
	await _wait(0.1)
	var course := m.get_node("Course") as Course
	var track := course.track as PathTrack
	var hw := course.half_width
	# Corcheras: en los bordes de verdad (donde se abre un camino no hay
	# corchera cruzando la entrada).
	var inside := 0
	var total := 0
	var per_route := {}
	var mk := course.markers
	for route in track.route_count():
		for side in [-1.0, 1.0]:
			var lat: float = side * hw
			var n := int(mk._edge_length(lat, route) / 2.0)
			for i in n:
				var p := mk._edge_point(i, n, lat, route)
				if not mk._on_edge(p, lat):
					continue
				total += 1
				per_route[route] = true
				if absf(track.lateral_of(p)) < hw - 1.0:
					inside += 1
	_check(inside == 0, "ninguna boya ni corchera queda adentro de un camino (%d de %d)" % [inside, total])
	_check(per_route.size() == 5, "los caminos alternativos tienen sus corcheras")
	var branch_rings := 0
	for ring in course.rings:
		if int(track.locate_route(ring.position).z) > 0:
			branch_rings += 1
	_check(branch_rings >= 3, "hay aros en los caminos alternativos (%d)" % branch_rings)
	# Un surfista en un camino alternativo se queda ahí (los límites son los de
	# ese camino, no lo mandan a la principal).
	var race := m.get_node("RaceManager") as RaceManager
	var r: Rider = race.racers[0]
	var b := track.branches[1]
	var spot := track.branch_position(b, b.length * 0.5, 4.0)
	r.position = Vector3(spot.x, r.position.y, spot.z)
	await _wait(0.2)
	var loc := track.locate_route(r.position)
	_check(int(loc.z) == 2 and Vector2(r.position.x - spot.x, r.position.z - spot.z).length() < 1.0,
		"en un camino alternativo no lo mueven a la principal")
	# Afuera del borde: vuelve al borde de ese camino.
	var out := track.branch_position(b, b.length * 0.4, hw + 4.0)
	r.position = Vector3(out.x, r.position.y, out.z)
	await _wait(0.05)
	loc = track.locate_route(r.position)
	_check(int(loc.z) == 2 and absf(loc.y) <= hw, "las corcheras del camino alternativo no lo dejan salir")
	m.queue_free()
	await process_frame


func _test_bots() -> void:
	print("Bots con bifurcaciones:")
	# Eligen distinto según su estilo (y no siempre lo mismo).
	var track := _map().make_track() as PathTrack
	var course := Course.new()
	course.track = track
	var counts := {}
	for level in [0, 4]:
		var ai := AIController.new()
		ai.course = course
		ai.difficulty = AIDifficulty.preset(level)
		ai._rng.seed = 3
		var shortest := 0
		for i in 200:
			ai.pick_routes()
			# Lo que eligió en el primer tramo (0: la principal).
			var first := 0
			for r in ai.route_choices:
				if track.branches[int(r) - 1].from_index == 1:
					first = int(r)
			counts[first] = true
			if first == 2:
				shortest += 1
		counts["corto_%d" % level] = shortest
		ai.free()
	course.free()
	_check(counts.has(0) and counts.has(1) and counts.has(2), "los bots usan los tres caminos")
	_check(int(counts.corto_4) > int(counts.corto_0),
		"los mejores van más por el camino corto (%d contra %d de 200)" % [counts.corto_4, counts.corto_0])
	# Una carrera: cada bot va por los caminos que eligió y termina.
	var m := _start([1, 2, 3])
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	var plans := [[1], [2, 3], [4, 3]]
	var seen := {}
	for i in race.racers.size():
		var ai := race.racers[i].controller as AIController
		ai.route_choices = plans[i].duplicate()
		ai._routes_picked = true
		seen[race.racers[i]] = {}
	race.skip_countdown()
	var t := race.course.track
	var frames := 0
	while race.state != RaceManager.State.FINISHED and frames < 200 * FPS:
		await process_frame
		frames += 1
		if frames % 10 == 0:
			for r in race.racers:
				var loc := t.locate_route(r.position)
				if absf(loc.y) < race.course.half_width:
					seen[r][int(loc.z)] = true
	_check(race.state == RaceManager.State.FINISHED, "terminan la carrera (%.0f s)" % (frames / float(FPS)))
	var followed := true
	for i in race.racers.size():
		var r: Rider = race.racers[i]
		for route in plans[i]:
			if route > 0 and not seen[r].has(route):
				followed = false
				print("        %s no pasó por el camino %d (vio %s)" % [r.display_name, route, str(seen[r].keys())])
	_check(followed, "cada bot pasa por los caminos que eligió")
	m.queue_free()
	await process_frame
