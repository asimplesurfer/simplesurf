extends "res://tests/test_base.gd"
## Mapas: los archivos de mapas y piezas, archipiélago y El Atolón (con tormenta).


func run() -> void:
	_test_map_files()
	_test_pieces()
	_test_editor_catalog()
	_test_bezier()
	_test_start_straight()
	_test_edges_on_border()
	_test_water_palette()
	await _test_cave()
	await _test_cave_map()
	await _test_tropical_island()
	await _test_night()
	await _test_archipelago()
	await _test_atoll()


func _test_map_files() -> void:
	print("Archivos de mapas:")
	var maps := TrackMap.all()
	_check(maps.size() >= 3, "se leen los mapas de la carpeta (%d)" % maps.size())
	_check(
		maps[TrackMap.index_of("classic")].id == "classic"
		and maps[TrackMap.index_of("archipelago")].id == "archipelago"
		and maps[TrackMap.index_of("atoll")].id == "atoll",
		"los primeros mapas conservan su número (récords y configuración guardada)"
	)
	var orders := {}
	var ids := {}
	var all_ok := true
	for m in maps:
		var errors := PackedStringArray()
		TrackMap.load_file(TrackMap.FOLDER + m.id + ".json", errors)
		if not errors.is_empty():
			all_ok = false
			print("    %s: %s" % [m.id, "; ".join(errors)])
		orders[m.order] = true
		ids[m.id] = true
	_check(all_ok, "todos los mapas están bien escritos")
	_check(orders.size() == maps.size() and ids.size() == maps.size(), "cada mapa tiene su número y su nombre propios")
	_check(GameSettings.track_layout_names().size() == maps.size(), "el menú muestra todos los mapas")
	# Ida y vuelta: leer y volver a escribir un mapa da lo mismo.
	var atoll := maps[TrackMap.index_of("atoll")]
	var again := TrackMap.from_dict(JSON.parse_string(JSON.stringify(atoll.to_dict())))
	_check(
		again.path == atoll.path and again.pieces == atoll.pieces
		and again.laps == atoll.laps,
		"un mapa se puede exportar y volver a leer igual"
	)


## Boyas y corcheras: todas en el borde real de la pista. En las curvas
## cerradas el borde de adentro hacía un rulo y dejaba boyas dentro de la pista
## (se atravesaban) y corcheras cruzadas.
func _test_edges_on_border() -> void:
	print("Boyas en el borde:")
	for m in TrackMap.all():
		if m.is_ring():
			continue
		var t := PathTrack.new(m.path, m.half_width, m.handles_in, m.handles_out, m.smoothing, m.start)
		var markers := CourseMarkers.new()
		markers.track = t
		var inside := 0
		var total := 0
		for side in [-1.0, 1.0]:
			var lat: float = side * m.half_width
			var n := int(t.length() / 2.0)
			for i in n:
				var p := t.position_at(TAU * i / n, lat)
				if markers._on_edge(p, lat):
					total += 1
					if absf(t.lateral_of(p)) < m.half_width - 1.0:
						inside += 1
		markers.free()
		_check(inside == 0 and total > 0, "%s: ninguna boya adentro de la pista (%d en el borde)" % [m.name, total])


## Colores del agua: una base (día) y los climas salen de ella.
func _test_water_palette() -> void:
	print("Colores del agua por clima:")
	for climate in WaterPalette.CLIMATES:
		var cols := WaterPalette.colors(climate)
		var own: Dictionary = WaterPalette.CLIMATES[climate].colors
		var all_keys := WaterPalette.BASE.keys().all(func(k: String) -> bool: return cols.has(k))
		# Lo que el clima no decide no queda con el color del día: se ajusta solo.
		var leaked := WaterPalette.BASE.keys().filter(
			func(k: String) -> bool: return not own.has(k) and cols[k] == WaterPalette.BASE[k]
		)
		var own_kept := own.keys().all(func(k: String) -> bool: return cols[k] == own[k])
		_check(all_keys and leaked.is_empty() and own_kept, "%s: todos los colores del agua, propios o sacados de la base %s" % [climate, leaked])
	var sunset_far: Color = WaterPalette.colors(WaterPalette.SUNSET).ocean_color
	_check(sunset_far.r > sunset_far.b + 0.2, "al atardecer el mar lejano es naranja (no celeste)")


func _test_pieces() -> void:
	print("Piezas de mapa:")
	var errors := PackedStringArray()
	var g := MapPiece.create({"type": "geyser", "x": 5, "z": -3, "calm": 2.0}, errors)
	_check(errors.is_empty() and g is GeyserPiece, "una pieza se arma por el nombre de su archivo")
	_check(
		is_equal_approx(g.x, 5.0) and is_equal_approx(g.calm, 2.0) and is_equal_approx(g.warn, Geyser.WARN),
		"toma los valores del mapa y deja por defecto los que no dice"
	)
	_check(g.to_dict().type == "geyser" and is_equal_approx(g.to_dict().calm, 2.0), "y se puede volver a escribir")
	errors.clear()
	MapPiece.create({"type": "no_existe"}, errors)
	_check(errors.size() == 1, "avisa si la pieza no existe")
	errors.clear()
	MapPiece.create({"type": "geyser", "x": 1}, errors)
	_check(errors.size() == 1 and errors[0].contains("\"z\""), "avisa si falta un dato obligatorio (%s)" % ", ".join(errors))
	errors.clear()
	MapPiece.create({"type": "geyser", "x": 1, "z": 1, "fuerza": 3}, errors)
	_check(errors.size() == 1 and errors[0].contains("fuerza"), "avisa si un dato no existe (mal escrito)")
	errors.clear()
	var arch := MapPiece.create({"type": "rock_arch", "x": 0, "z": 0, "stone_color": "#ff8000"}, errors)
	_check(errors.is_empty() and arch.stone_color == Color8(255, 128, 0), "los colores se escriben como en la web (#rrggbb)")


func _test_bezier() -> void:
	print("Recorrido con manijas (Bézier):")
	var square := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)])
	var auto := PathTrack.new(square, 20.0)
	var none := [null, null, null, null]
	var same := PathTrack.new(square, 20.0, none, none)
	_check(auto.points == same.points, "sin manijas, la curva es la de siempre (pasa suave por los puntos)")
	# Manijas en cero: esquinas (sin suavizado, los lados quedan rectos).
	var zero := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var corners := PathTrack.new(square, 20.0, zero, zero, 0)
	_check(absf(corners.length() - 800.0) < 1.0, "manijas en cero: lados rectos (%.0f m)" % corners.length())
	# Una manija larga hacia afuera en un lado: ese lado se curva (más largo).
	var outs := [Vector2(60, -80), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var ins := [Vector2.ZERO, Vector2(-60, -80), Vector2.ZERO, Vector2.ZERO]
	var bent := PathTrack.new(square, 20.0, ins, outs, 0)
	var bulge := bent.position_at(TAU * 0.125)
	_check(bent.length() > 830.0 and bulge.z < -30.0, "girando las manijas, el tramo se curva (%.0f m)" % bent.length())


## Recta de la meta: la largada siempre en un tramo recto (40 m antes y 60
## después por defecto) que no se suaviza; los surfistas arrancan mirando
## hacia donde va la pista.
func _test_start_straight() -> void:
	print("Recta de la meta:")
	var control := PackedVector2Array([Vector2(200, 80), Vector2(120, 220), Vector2(-80, 200)])
	var start := {"x": 0.0, "z": 0.0, "angle": 30.0, "back": 40.0, "front": 60.0}
	var t := PathTrack.new(control, 20.0, [], [], 40, start)
	var p0 := t.position_at(0.0)
	_check(Vector2(p0.x, p0.z).length() < 0.5, "la meta está en la recta (y la vuelta empieza ahí)")
	var dir := Vector2(cos(deg_to_rad(30.0)), -sin(deg_to_rad(30.0)))
	var straight := true
	for m in range(-36, 57, 3):
		var tg := t.tangent_at(float(m) / t.length() * TAU)
		if absf(Vector2(tg.x, tg.z).angle_to(dir)) > deg_to_rad(0.5):
			straight = false
	_check(straight, "40 m antes y 60 m después la pista es recta (no la redondea el suavizado)")
	var h := t.heading_at(RaceManager.START_ANGLE)
	_check(Vector2(-sin(h), -cos(h)).dot(dir) > 0.999, "en la largada se mira hacia donde va la pista")
	var q := t.position_at(TAU * 0.5)
	_check(absf(t.lateral_of(q)) < 0.5 and t.length() > 600.0, "la recta empalma con el resto de la pista (%.0f m)" % t.length())
	# Curva leve: gira de punta a punta lo que se pidió.
	start["bend"] = 8.0
	var tb := PathTrack.new(control, 20.0, [], [], 40, start)
	var a0 := tb.tangent_at(-36.0 / tb.length() * TAU)
	var a1 := tb.tangent_at(56.0 / tb.length() * TAU)
	var turn := rad_to_deg(absf(Vector2(a0.x, a0.z).angle_to(Vector2(a1.x, a1.z))))
	_check(turn > 5.0 and turn < 9.0, "con curva leve, la recta gira apenas (%.1f grados)" % turn)
	# El archivo del mapa la guarda y la lee igual.
	var d := TrackMap.from_dict({"id": "x", "path": [[200, 80]], "start": start}).to_dict()
	_check(d.get("start", {}).get("bend") == 8.0, "el mapa guarda la recta de la meta")


## El archipiélago con una cueva dibujada sobre la pista y una roca de paisaje.
func _test_cave() -> void:
	print("Cueva y roca dibujadas:")
	GameSettings.track_layout = TrackMap.index_of("archipelago")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/maps/archipelago.json"))
	d.pieces = [
		{"type": "rock_formation", "shape": [[55, -125], [100, -140], [145, -95], [138, -50], [105, -52], [85, -85], [50, -92]],
			"ceiling": 9.0, "skylights": [[118, -88]]},
		{"type": "rock_formation", "shape": [[280, 0], [320, -10], [330, 30], [300, 50], [275, 35]], "opening": true},
	]
	var errors := PackedStringArray()
	var map := TrackMap.from_dict(d, errors)
	_check(errors.is_empty(), "la cueva se escribe como una pieza más (%s)" % ", ".join(errors))
	var m: Node = load("res://main.tscn").instantiate()
	var course := m.get_node("Course") as Course
	course.map = map
	root.add_child(m)
	var race := m.get_node("RaceManager") as RaceManager
	await process_frame
	await process_frame
	await process_frame
	var cave: RockFormationPiece = course.pieces[0]
	var rock: RockFormationPiece = course.pieces[1]
	_check(cave.is_cave() and not rock.is_cave(), "si tapa la pista es cueva; si no, roca de paisaje")
	_check(
		course.get_node_or_null("Cave/Rock") != null and course.get_node_or_null("RockFormation/Rock") != null,
		"las dos se arman (roca tallada)"
	)
	# Un punto de la pista adentro de la cueva.
	var inside := Vector3.ZERO
	for i in 400:
		var p := course.track.position_at(-PI + TAU * i / 400.0)
		if cave.covers(p.x, p.z) and BezierShape.distance_to_edge(cave._outline, Vector2(p.x, p.z)) > 15.0:
			inside = p
			break
	_check(inside != Vector3.ZERO, "la pista pasa por adentro de la cueva")
	_check(cave.darkness_at(inside + Vector3.UP * 2.0) > 0.6 and cave.darkness_at(Vector3(0, 2, 300)) == 0.0, "adentro está oscuro y afuera no")
	# Con el techo a 9 m no se sube más que el techo, aunque algo lo lance fuerte.
	race.skip_countdown()
	await process_frame
	var r: Rider = race.racers[0]
	var top := -100.0
	for i in int(1.5 * FPS):
		if i == 0:
			r.position = Vector3(inside.x, r.position.y, inside.z)
			r.geyser_launch(30.0)
		r.position.x = inside.x
		r.position.z = inside.z
		top = maxf(top, r.position.y)
		await process_frame
	_check(top > 2.0 and top < 9.0 - 2.0, "con techo bajo el salto no llega al techo (%.1f m)" % top)
	# Los ojos: al entrar se ve oscuro y después se acostumbran; al salir, fogonazo.
	var dark := 1.0 - cave.darkness
	_check(CaveEyes.seen_brightness(dark, 1.0) < 0.35, "al entrar a la cueva se ve casi negro")
	_check(CaveEyes.seen_brightness(dark, dark) > 0.7, "con los ojos acostumbrados se ve")
	_check(CaveEyes.seen_brightness(1.0, dark) > 2.0, "al salir hay un fogonazo de luz")
	_check(is_equal_approx(CaveEyes.seen_brightness(1.0, 1.0), 1.0), "y afuera todo vuelve a lo normal")
	m.queue_free()
	await process_frame
	GameSettings.track_layout = TrackMap.index_of("classic")


## El mapa La cueva: se entra a la cueva, se sale por detrás de la cascada y
## los bots dan la vuelta.
func _test_cave_map() -> void:
	print("Mapa la cueva:")
	var idx := TrackMap.index_of("cave")
	_check(idx >= 0, "el mapa de la cueva está en la lista")
	GameSettings.track_layout = idx
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for level in [2, 1]:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var cave: RockFormationPiece = null
	var fall: WaterfallPiece = null
	for p in course.pieces:
		if p is RockFormationPiece and p.is_cave():
			cave = p
		if p is WaterfallPiece:
			fall = p
	_check(cave != null and course.get_node_or_null("Cave/Rock") != null, "hay una cueva sobre la pista")
	_check(fall != null and course.get_node_or_null("Waterfall/Curtain") != null, "hay una cascada")
	_check(_land_clear_of_track(course, 0.5), "las islas no pisan la pista")
	# La cascada cruza la pista en la salida de la cueva.
	var on_track := absf(course.track.lateral_of(Vector3(fall.x, 0, fall.z))) < 6.0
	var at_exit := false
	for i in 12:
		var q := Vector3(fall.x, 0, fall.z) - Vector3(fall._across.x, 0, fall._across.y) * float(i)
		if cave.covers(q.x, q.z):
			at_exit = true
	_check(on_track and at_exit, "la cascada está en la salida de la cueva, cruzando la pista")
	# Atravesarla moja la pantalla.
	race.skip_countdown()
	await process_frame
	var r: Rider = race.racers[0]
	var wet := [false]
	r.wave_punched.connect(func() -> void: wet[0] = true)
	var c := Vector2(fall.x, fall.z)
	for i in 6:
		var q := c + fall._across * (6.0 - 2.4 * i)
		r.position = Vector3(q.x, r.position.y, q.y)
		await process_frame
	_check(wet[0], "atravesar la cascada moja (como una ola que rompe)")
	# Los bots dan la vuelta (pasando por la cueva).
	var finished := false
	for i in int(200.0 * FPS):
		if race.state == RaceManager.State.FINISHED:
			finished = true
			break
		await process_frame
	var all_done := true
	for rr in race.racers:
		if not race.finished(rr):
			all_done = false
	_check(finished or all_done, "los bots completan la vuelta de la cueva")
	m.queue_free()
	await process_frame
	GameSettings.track_layout = TrackMap.index_of("classic")


## Isla larga e irregular, al este del archipiélago, con la panza hacia la pista.
const ISLAND_SHAPE := [[200, -110], [232, -128], [256, -95], [246, -45], [264, 5], [252, 60], [216, 90], [194, 55], [212, 5], [194, -52]]


## De noche: cielo oscuro con estrellas y luna, luz tenue y las guirnaldas
## prendidas (con su halo de luz).
func _test_night() -> void:
	print("De noche:")
	var saved := GameSettings.time_of_day
	GameSettings.time_of_day = GameSettings.TimeOfDay.NIGHT
	GameSettings.track_layout = TrackMap.index_of("archipelago")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/maps/archipelago.json"))
	d.pieces = [
		{"type": "tropical_island", "shape": ISLAND_SHAPE},
		{"type": "island_split", "path": [[170, -20], [290, -20]], "width": 14},
		{"type": "light_string", "a": [225, -60], "b": [225, 10], "lines": 2, "style": "fria"},
	]
	var m: Node = load("res://main.tscn").instantiate()
	(m.get_node("Course") as Course).map = TrackMap.from_dict(d)
	root.add_child(m)
	await process_frame
	await process_frame
	var env := (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := env.sky.sky_material as ShaderMaterial
	var sun := m.get_node("Sun") as DirectionalLight3D
	_check(float(sky.get_shader_parameter("stars")) > 0.5 and float(sky.get_shader_parameter("moon")) > 0.5
		and sun.light_energy < 0.6 and env.fog_light_color.v < 0.3, "cielo oscuro con estrellas y luna, luz tenue")
	var lights := m.find_child("LightString", true, false)
	var glow := lights.get_node_or_null("Glow") if lights else null
	_check(glow != null and float((glow as MultiMeshInstance3D).material_override.get_shader_parameter("strength")) > 0.3,
		"las guirnaldas están prendidas (con halo de luz)")
	m.queue_free()
	await process_frame
	GameSettings.time_of_day = saved
	GameSettings.track_layout = TrackMap.index_of("classic")


## Una isla tropical dibujada: arena, selva y palmeras (todo en pocas
## MultiMesh) y se choca como una isla.
func _test_tropical_island() -> void:
	print("Isla tropical dibujada:")
	GameSettings.track_layout = TrackMap.index_of("archipelago")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/maps/archipelago.json"))
	d.pieces = [
		{"type": "tropical_island", "shape": ISLAND_SHAPE},
		{"type": "island_split", "path": [[170, -20], [290, -20]], "width": 14},
		{"type": "light_string", "a": [225, -60], "b": [225, 10], "lines": 4, "style": "navidad"},
	]
	var m: Node = load("res://main.tscn").instantiate()
	var course := m.get_node("Course") as Course
	course.map = TrackMap.from_dict(d)
	root.add_child(m)
	var race := m.get_node("RaceManager") as RaceManager
	await process_frame
	await process_frame
	var isl := course.get_node_or_null("TropicalIsland")
	_check(isl != null and isl.get_node_or_null("Sand") != null and isl.get_node_or_null("Grass") != null, "tiene arena y pasto")
	var palms := 0
	var in_sand := 0
	for p in course.pieces:
		if p is TropicalIslandPiece:
			var piece := p as TropicalIslandPiece
			palms += piece.palm_count()
			# Ninguna palmera en medio de la playa (solo en el pasto o pegadas a él).
			for node in course.find_children("*Palms*", "MultiMeshInstance3D", true, false):
				var mm := (node as MultiMeshInstance3D).multimesh
				for k in mm.instance_count:
					var o := mm.get_instance_transform(k).origin
					var q := Vector2(o.x, o.z)
					if Geometry2D.is_point_in_polygon(q, piece._outline) and not piece._near_grass(q, TropicalIslandPiece.PALM_SAND_REACH + 0.5):
						in_sand += 1
	_check(in_sand == 0, "ninguna palmera en medio de la playa (%d)" % in_sand)
	var draws := 0
	for c in isl.get_children():
		if (c is MultiMeshInstance3D or c is MeshInstance3D) and not String(c.name).begins_with("Crowd_"):
			draws += 1
	_check(palms > 50 and draws <= 20, "palmeras en pocas mallas (%d palmeras, %d mallas)" % [palms, draws])
	_check(
		(isl.get_node("Ferns0") as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"los helechos no hacen sombra"
	)
	# El corte parte la isla en dos islas, con mar en el medio (sin palmeras).
	var parts: Array[TropicalIslandPiece] = []
	for p in course.pieces:
		if p is TropicalIslandPiece:
			parts.append(p)
	_check(parts.size() == 2 and course.get_node_or_null("TropicalIsland2") != null,
		"el corte divide la isla en dos islas (%d)" % parts.size())
	var in_channel := 0
	for node in course.get_children():
		if not String(node.name).begins_with("TropicalIsland"):
			continue
		for c in node.get_children():
			if c is MultiMeshInstance3D and String(c.name).contains("Palms"):
				var mm: MultiMesh = c.multimesh
				for k in mm.instance_count:
					var o := mm.get_instance_transform(k).origin
					if absf(o.z + 20.0) < 7.0 and o.x > 180.0 and o.x < 280.0:
						in_channel += 1
	_check(in_channel == 0, "no hay palmeras en el mar del corte")
	# Público: en la orilla (no en el medio de la isla), sin chocarse, en pocas mallas.
	var spots := 0
	var far_from_shore := 0
	var crowd_meshes := 0
	for node in course.get_children():
		if String(node.name).begins_with("TropicalIsland"):
			for c in node.get_children():
				if c is MultiMeshInstance3D and String(c.name).begins_with("Crowd_"):
					crowd_meshes += 1
	for p in parts:
		for spot in p._crowd_spots:
			spots += 1
			if BezierShape.distance_to_edge(p._outline, spot) > TropicalIslandPiece.CROWD_DEPTH + 1.0:
				far_from_shore += 1
	# Las olas grandes no pasan por encima de las islas tropicales: se apagan
	# sobre la isla y cerca de la orilla.
	var water := m.get_node("Water") as Water
	var on_isle := water._island_fade(Vector2(225, -60))
	var shore := water._island_fade(Vector2(255, -60))
	var open_sea := water._island_fade(Vector2(320, -20))
	_check(on_isle < 0.01 and shore < 0.3 and open_sea > 0.99,
		"las olas grandes se apagan sobre las islas tropicales (isla %.2f, orilla %.2f, mar %.2f)" % [on_isle, shore, open_sea])
	# Guirnalda entre las dos mitades: cada cable sale atado a una palmera de
	# una isla y llega a una palmera de la otra, sin cruzarse.
	var ls: LightStringPiece = null
	for p in course.pieces:
		if p is LightStringPiece:
			ls = p
	var tied := 0
	for cab in ls.cables if ls else []:
		var ok_a := false
		var ok_b := false
		for t in ls.island_a.palm_ties:
			ok_a = ok_a or (t[0] as Vector3).distance_to(cab[0]) < 1.5
		for t in ls.island_b.palm_ties:
			ok_b = ok_b or (t[0] as Vector3).distance_to(cab[1]) < 1.5
		if ok_a and ok_b and (cab[0] as Vector3).y > 4.0 and (cab[1] as Vector3).y > 4.0:
			tied += 1
	var side := Vector2(1, 0)
	var ordered := true
	if ls:
		for k in range(1, ls.cables.size()):
			var prev: Array = ls.cables[k - 1]
			var cur: Array = ls.cables[k]
			if (cur[0].x - prev[0].x) * (cur[1].x - prev[1].x) < -0.01:
				ordered = false
	_check(ls != null and ls.island_a != ls.island_b and ls.cables.size() == 4 and tied == 4 and ordered
		and course.get_node_or_null("LightString") != null,
		"guirnalda: 4 cables atados de palmera a palmera entre las dos islas, sin cruzarse (%d atados)" % tied)
	# Puntos de fiesta: uno por isla como mucho; la gente se entera de dónde
	# están los surfistas (para entusiasmarse cuando pasan cerca).
	var director := course.get_node_or_null("CrowdDirector") as CrowdDirector
	var parties := 0
	for p in parts:
		parties += p.party_spots.size()
	await process_frame
	var mats := BeachCrowd.materials()
	_check(director != null and director.spot_count() >= parties and parties <= parts.size()
		and not mats.is_empty() and int(mats[0].get_shader_parameter("rider_count")) >= 1,
		"puntos de fiesta (%d) y la gente sabe dónde están los surfistas" % parties)
	_check(spots > 4 and far_from_shore == 0 and crowd_meshes <= 2 * (BeachCrowd.STANDING + BeachCrowd.SITTING + 5),
		"público en la orilla que da a la pista (%d cosas, %d lejos del agua, %d mallas)" % [spots, far_from_shore, crowd_meshes])
	var covered := func(x: float, z: float) -> bool:
		for p in parts:
			if p.covers(x, z):
				return true
		return false
	_check(not covered.call(225.0, -20.0) and covered.call(225.0, 10.0) and covered.call(225.0, -60.0),
		"en el medio hay mar; a cada lado, isla")
	var piece: TropicalIslandPiece = course.pieces[0]
	_check(piece.ground_y(Vector2(0, 0)) == -INF, "la isla dice dónde hay tierra")
	# Un corte que no llega a la isla no la cambia; uno que la tapa entera la borra.
	var whole := IslandSplitPiece.cut(BezierShape.parse(ISLAND_SHAPE).polygon(4.0), [] as Array[MapPiece])
	_check(whole.size() == 1, "sin cortes la isla queda entera")
	var eat := MapPiece.create({"type": "island_split", "path": [[230, -140], [230, 100]], "width": 200})
	_check(IslandSplitPiece.cut(whole[0], [eat] as Array[MapPiece]).is_empty(), "un corte que la tapa entera la borra")
	race.skip_countdown()
	await process_frame
	var r: Rider = race.racers[0]
	# Esta isla está lejos de la pista (a más de 100 m): no se puede alcanzar,
	# así que no choca.
	_check(parts.all(func(p: TropicalIslandPiece) -> bool: return not p._solid),
		"las islas lejos de la pista no chocan")
	for p in parts:
		p._solid = true
	# Seguro: un choque que lo mandaría lejos no cuenta.
	var before := r.position
	course._crash(r, before + Vector3(40, 0, 0))
	_check(not r.is_fallen() and r.position.distance_to(before) < 0.1, "un choque nunca lo manda lejos")
	# Entra por la orilla (como en el juego): justo pasando el borde.
	var z := -20.0
	while z < 10.0 and not covered.call(225.0, z):
		z += 0.25
	r.position = Vector3(225, r.position.y, z + 0.5)
	await process_frame
	await process_frame
	_check(r.is_fallen() and not covered.call(r.position.x, r.position.z), "subirse a la isla tira al surfista y lo deja en el agua")

	m.queue_free()
	await process_frame
	GameSettings.track_layout = TrackMap.index_of("classic")


func _test_archipelago() -> void:
	print("Mapa archipiélago:")
	GameSettings.track_layout = TrackMap.index_of("archipelago")
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for level in [2, 2, 1]:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var track := course.track
	_check(track is PathTrack, "el recorrido no es un círculo")
	_check(course.registered("ground").size() >= 12, "hay muchas islas (%d)" % course.registered("ground").size())
	_check(
		track.length() > 700.0 and track.length() < 1000.0,
		"una vuelta mide %.0f m" % track.length()
	)
	_check(config.laps == 1 and GameSettings.laps_for(TrackMap.index_of("archipelago")) == 3, "en el archipiélago se corren 3 vueltas")

	# Ida y vuelta: posición <-> (ángulo, lateral).
	var roundtrip := true
	for i in 40:
		var a := -PI + TAU * i / 40.0
		var lat := -15.0 + 30.0 * (i % 7) / 6.0
		var p := track.position_at(a, lat)
		var back := track.locate(p)
		if absf(wrapf(back.x - a, -PI, PI)) > 0.02 or absf(back.y - lat) > 0.6:
			roundtrip = false
			print("    ida y vuelta: %.2f, %.1f -> %.2f, %.1f" % [a, lat, back.x, back.y])
	_check(roundtrip, "posiciones y coordenadas de pista coinciden")

	# Curvas a la izquierda y a la derecha.
	var lefts := 0
	var rights := 0
	for i in 200:
		var a := -PI + TAU * i / 200.0
		var t0 := track.tangent_at(a)
		var t1 := track.tangent_at(a + 0.05)
		var turn := t0.x * t1.z - t0.z * t1.x
		if turn > 0.01:
			lefts += 1
		elif turn < -0.01:
			rights += 1
	_check(lefts > 10 and rights > 10, "hay curvas a los dos lados (%d / %d)" % [lefts, rights])

	# Ninguna isla pisa la pista.
	_check(_land_clear_of_track(course, 4.0), "las islas no pisan la pista")
	# Desde cualquier lugar de la pista se ven islas cerca.
	var always_islands := true
	for i in 30:
		var p := track.position_at(-PI + TAU * i / 30.0)
		var near := 0
		for o in course.land_outlines():
			if BezierShape.distance_to_edge(o, Vector2(p.x, p.z)) < 110.0:
				near += 1
		if near < 2:
			always_islands = false
	_check(always_islands, "siempre hay islas a la vista")

	# Los bots dan la vuelta sin chocar islas.
	var island_crashes := [0]
	for r in race.racers:
		r.crashed.connect(func() -> void:
			if _distance_to_land(course, Vector2(r.position.x, r.position.z)) < 8.0:
				island_crashes[0] += 1
		)
	var finished := false
	var waves := m.get_node("WaveManager") as WaveManager
	var lead: Rider = race.racers[0]
	var gap := 0.0
	var longest_gap := 0.0
	var racing_time := 0.0
	for i in int(150.0 * FPS):
		if race.state == RaceManager.State.FINISHED:
			finished = true
			break
		# (Los primeros segundos de la largada son de calma a propósito.)
		if race.state == RaceManager.State.RACING and not race.finished(lead) and race.race_time > WaveManager.START_CALM + 1.0:
			racing_time += 1.0 / FPS
			if waves.has_wave_ahead(lead):
				gap = 0.0
			else:
				gap += 1.0 / FPS
				longest_gap = maxf(longest_gap, gap)
		await process_frame
	_check(
		racing_time > 10.0 and longest_gap < 3.0,
		"siempre hay una ola grande viniendo (el rato más largo sin ola: %.1f s)" % longest_gap
	)
	var all_done := true
	for r in race.racers:
		if not race.finished(r):
			all_done = false
	_check(finished or all_done, "los bots completan la vuelta del archipiélago")
	_check(island_crashes[0] <= 1, "casi sin chocar islas (%d)" % island_crashes[0])
	m.queue_free()
	await process_frame
	GameSettings.track_layout = TrackMap.index_of("classic")


func _test_atoll() -> void:
	print("Mapa el atolón (con tormenta):")
	GameSettings.track_layout = TrackMap.index_of("atoll")
	GameSettings.weather = GameSettings.Weather.STORM
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var config := RaceConfig.new()
	config.laps = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for level in [2, 2, 1]:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = "Bot %d" % level
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var m: Node = load("res://main.tscn").instantiate()
	var race := m.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(m)
	await process_frame
	await process_frame
	var course := m.get_node("Course") as Course
	var track := course.track
	_check(track is PathTrack, "el atolón tiene recorrido propio")
	_check(
		track.length() > 1000.0 and track.length() < 1300.0,
		"una vuelta mide %.0f m" % track.length()
	)
	_check(_distance_to_land(course, Vector2.ZERO) == 0.0, "hay una isla en el medio de la laguna")
	_check(course.get_node_or_null("RockArch") != null, "hay un arco de roca sobre el paso norte")
	_check(course.get_node_or_null("Shipwreck") != null, "hay un barco hundido en la laguna")
	_check(_land_clear_of_track(course, 0.5), "las islas no pisan la pista")
	var geysers := _geysers(course)
	_check(geysers.size() >= 3, "hay géiseres en la laguna (%d)" % geysers.size())
	# Tormenta: cielo gris, poca luz, mar picado, rayos con trueno.
	var storm := course.storm
	_check(storm != null, "con clima tormenta hay tormenta")
	var env := (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var zenith: Color = env.sky.sky_material.get_shader_parameter("zenith_color")
	_check(zenith.s < 0.3 and zenith.v < 0.35, "el cielo está gris y oscuro")
	_check((m.get_node("Sun") as DirectionalLight3D).light_energy < 0.7, "hay menos luz de sol")
	var water := m.get_node("Water") as Water
	_check(water.waves.max_height() > 1.4, "el mar está mucho más picado (%.1f m)" % water.waves.max_height())
	var wm := water.shader_material()
	_check(
		wm.get_shader_parameter("deep_color") == Color(0.05, 0.15, 0.23)
		and wm.get_shader_parameter("sky_tint") == Color(0.5, 0.55, 0.62)
		and is_equal_approx(wm.get_shader_parameter("sky_reflect"), 0.6),
		"el agua de la tormenta tiene sus colores propios (no depende del día)"
	)
	storm.strike()
	var flashed := false
	var thunder := false
	for i in int(3.0 * FPS):
		if storm.flash > 0.3:
			flashed = true
		if root.get_node("AudioManager").recent_sfx.has("thunder"):
			thunder = true
		await process_frame
	_check(flashed, "un rayo ilumina todo")
	_check(thunder, "y después suena el trueno")
	_check(storm.last_strike.length() > 400.0, "los rayos caen lejos")
	_check(storm.rain.size() == (m.get_node("Views") as SplitScreen).views.size(), "llueve en cada pantalla")
	var drops := storm.rain[0].get_node("Drops") as CPUParticles3D
	_check(drops.emitting and not drops.local_coords, "la lluvia son gotas 3D que caen en el mundo")
	# Si una vista pierde la lluvia, vuelve sola.
	var lost := storm.rain[0]
	lost.get_parent().remove_child(lost)
	lost.free()
	await process_frame
	await process_frame
	_check(
		storm.rain.size() == (m.get_node("Views") as SplitScreen).views.size()
		and storm.rain[0].get_node_or_null("Drops") != null,
		"si se pierde la lluvia de una vista, vuelve"
	)
	_check(storm._rain_clock >= 0.0 and storm._rain_clock < 1.0, "el reloj de la lluvia no crece sin parar")
	_check(storm._rain_sound.playing, "se escucha la lluvia")
	var on_track := true
	for g in geysers:
		if absf(track.lateral_of(g.position)) > track.half_width - 2.0:
			on_track = false
	_check(on_track, "los géiseres están sobre la pista")

	# Un géiser que explota lanza al que pasa por arriba.
	var g0: Geyser = geysers[0]
	var r0: Rider = race.racers[0]
	race.skip_countdown()
	await process_frame
	g0._t = Geyser.CALM - 0.05
	var launched := [false]
	r0.geyser_launched.connect(func() -> void: launched[0] = true)
	var max_y := -100.0
	for i in int(2.5 * FPS):
		if not launched[0]:
			r0.position = Vector3(g0.position.x, r0.position.y, g0.position.z)
		max_y = maxf(max_y, r0.position.y)
		await process_frame
	_check(launched[0], "el géiser lanza al que está arriba cuando explota")
	_check(max_y > 4.0, "y lo manda alto (%.1f m)" % max_y)

	# Los bots dan la vuelta sin chocar islas.
	var island_crashes := [0]
	for r in race.racers:
		r.crashed.connect(func() -> void:
			if _distance_to_land(course, Vector2(r.position.x, r.position.z)) < 8.0:
				island_crashes[0] += 1
		)
	var finished := false
	for i in int(200.0 * FPS):
		if race.state == RaceManager.State.FINISHED:
			finished = true
			break
		await process_frame
	var all_done := true
	for r in race.racers:
		if not race.finished(r):
			all_done = false
	_check(finished or all_done, "los bots completan la vuelta del atolón")
	_check(island_crashes[0] <= 1, "casi sin chocar islas (%d)" % island_crashes[0])
	m.queue_free()
	await process_frame
	# La próxima carrera con sol arranca limpia.
	GameSettings.weather = GameSettings.Weather.SUNNY
	var sunny: Node = load("res://main.tscn").instantiate()
	root.add_child(sunny)
	await process_frame
	var sunny_env := (sunny.get_node("WorldEnvironment") as WorldEnvironment).environment
	# La luz ambiente de día, tal como viene en la escena.
	var fresh: Node = load("res://main.tscn").instantiate()
	var day_ambient: float = (fresh.get_node("WorldEnvironment") as WorldEnvironment).environment.ambient_light_energy
	fresh.free()
	_check(
		(sunny.get_node("Course") as Course).storm == null and sunny_env.sky.sky_material.get_shader_parameter("zenith_color") == null
		and absf(sunny_env.ambient_light_energy - day_ambient) < 0.01
		and (sunny.get_node("Water") as Water).waves.max_height() < 1.0,
		"con sol, sin tormenta (cielo azul y mar normal)"
	)
	sunny.queue_free()
	await process_frame
	GameSettings.track_layout = TrackMap.index_of("classic")


func _geysers(course: Course) -> Array[Geyser]:
	var out: Array[Geyser] = []
	for n in course.get_tree().get_nodes_in_group("geyser"):
		if course.is_ancestor_of(n):
			out.append(n as Geyser)
	return out


## Distancia de p a la tierra más cercana (0 si está encima).
func _distance_to_land(course: Course, p: Vector2) -> float:
	var best := INF
	for o in course.land_outlines():
		if Geometry2D.is_point_in_polygon(p, o):
			return 0.0
		best = minf(best, BezierShape.distance_to_edge(o, p))
	return best


## Ninguna isla llega a menos de `margin` metros del borde de la pista.
func _land_clear_of_track(course: Course, margin: float) -> bool:
	var ok := true
	for i in 300:
		var p := course.track.position_at(-PI + TAU * i / 300.0)
		var d := _distance_to_land(course, Vector2(p.x, p.z))
		if d < course.half_width + margin:
			ok = false
			print("    isla a %.1f m del centro de la pista en (%d, %d)" % [d, p.x, p.z])
			break
	return ok


## Cada pieza dice cómo se ve en el editor de mapas (su constante EDITOR), así
## el editor la toma sola (ver MapPiece.editor_entry).
func _test_editor_catalog() -> void:
	var catalog := MapPiece.editor_catalog()
	var files := 0
	for f in DirAccess.get_files_at(MapPiece.FOLDER):
		if f.trim_suffix(".remap").get_extension() == "gd" and not f.begins_with("map_piece"):
			files += 1
	_check(catalog.size() == files and files > 0, "el editor conoce todas las piezas (%d de %d)" % [catalog.size(), files])
	var kinds := ["num", "int", "bool", "color", "text", "choice", "level", "numbool", "variant"]
	var problems: Array[String] = []
	for c in catalog:
		var piece := MapPiece.create({"type": c.type})
		var vars := piece.params()
		var place: String = c.place
		if not MapPiece.PLACES.has(place):
			problems.append("%s: EDITOR sin \"place\" válido" % c.type)
			continue
		var need: Array = {"point": ["x", "z"], "two_points": ["a", "b"], "shape": [c.get("key", "")], "path": [c.get("key", "")]}[place]
		for k in need:
			if not vars.has(k):
				problems.append("%s: para \"%s\" le falta la variable %s" % [c.type, place, k])
		for row in c.params:
			if not kinds.has(row[2]):
				problems.append("%s.%s: campo \"%s\" desconocido" % [c.type, row[0], row[2]])
			if row[1] == String(row[0]).capitalize():
				problems.append("%s.%s: sin etiqueta (un comentario ## arriba o en EDITOR.fields)" % [c.type, row[0]])
			if (row[2] == "choice" or row[2] == "level") and row.size() < 5:
				problems.append("%s.%s: le faltan las opciones" % [c.type, row[0]])
	for pr in problems:
		print("    " + pr)
	_check(problems.is_empty(), "cada pieza dice cómo se pone y cada parámetro tiene su etiqueta en el editor")
