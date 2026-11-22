extends SceneTree
## Revisa todos los mapas de world/maps/ antes de publicar el juego. Lo corre
## GitHub (Web build): si algún mapa tiene un error, no se publica (queda la
## versión anterior en la web) y en el resumen de la corrida dice qué está mal.
##
##   godot --headless --path . --script res://tools/validate_maps.gd
##
## Termina con "MAPAS OK" o con "MAPAS CON ERRORES".

var _errors: Array[String] = []


func _initialize() -> void:
	var orders := {}
	var count := 0
	for file in TrackMap._list_files():
		count += 1
		var errors := PackedStringArray()
		var m := TrackMap.load_file(TrackMap.FOLDER + file, errors)
		for e in errors:
			_fail(file, e)
		if m == null:
			continue
		if not file.get_basename().is_valid_identifier():
			_fail(file, "el nombre del archivo solo puede tener letras sin tildes, números y _ (por ejemplo mi_mapa.json)")
		if orders.has(m.order):
			_fail(file, "el número de mapa (order) %d lo usan %s y %s: cada mapa necesita su propio número" % [m.order, orders[m.order], file])
		else:
			orders[m.order] = file
		if errors.is_empty():
			_check_track(file, m)
		print("  %s: \"%s\", mapa número %d" % [file, m.name, m.order])
	if count == 0:
		_fail("world/maps", "no hay ningún mapa")
	if _errors.is_empty():
		print("MAPAS OK (%d)" % count)
		quit(0)
	else:
		for e in _errors:
			print(e)
		print("MAPAS CON ERRORES")
		quit(1)


## La pista se puede armar y nada la tapa (islas, volcanes, islas tropicales).
func _check_track(file: String, m: TrackMap) -> void:
	var track := m.make_track()
	if track.length() < 150.0:
		_fail(file, "la vuelta es muy corta (%.0f m)" % track.length())
		return
	var samples := PackedVector2Array()
	for i in 300:
		var p := track.position_at(-PI + TAU * i / 300.0)
		samples.append(Vector2(p.x, p.z))
	var round_things: Array = []
	for i in m.islands.size():
		var isl: Dictionary = m.islands[i]
		round_things.append(["la isla %d" % (i + 1), Vector2(isl.x, isl.z), float(isl.radius)])
	for d in m.pieces:
		if d.get("type") == "volcano":
			round_things.append(["el volcán", Vector2(float(d.x), float(d.z)), float(d.get("radius", 40.0))])
		elif d.get("type") == "tropical_island":
			var poly := BezierShape.parse(d.get("shape", [])).polygon(4.0)
			for q in samples:
				if poly.size() >= 3 and Geometry2D.is_point_in_polygon(q, poly):
					_fail(file, "una isla tropical tapa la pista cerca de (%d, %d)" % [roundi(q.x), roundi(q.y)])
					break
	if m.is_ring():
		return
	for t in round_things:
		for q in samples:
			if q.distance_to(t[1]) < float(t[2]) + 2.0:
				_fail(file, "%s tapa la pista cerca de (%d, %d)" % [t[0], roundi(q.x), roundi(q.y)])
				break


func _fail(file: String, message: String) -> void:
	_errors.append("::error title=Mapa %s::%s" % [file, message])
