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


## La pista se puede armar y nada la tapa (islas y cualquier pieza que se choque).
func _check_track(file: String, m: TrackMap) -> void:
	var track := m.make_track()
	if track.length() < 150.0:
		_fail(file, "la vuelta es muy corta (%.0f m)" % track.length())
		return
	var samples := PackedVector2Array()
	for i in 300:
		var p := track.position_at(-PI + TAU * i / 300.0)
		samples.append(Vector2(p.x, p.z))
	# Cada pieza sabe si tapa la pista (ver MapPiece.blocks_track).
	for d in m.pieces:
		var piece := MapPiece.create(d)
		if piece == null:
			continue
		var q: Variant = piece.blocks_track(samples)
		if q is Vector2:
			_fail(file, "%s tapa la pista cerca de (%d, %d)" % [_piece_name(piece.type), roundi(q.x), roundi(q.y)])


## Cómo se llama una pieza en los avisos (para quien sube el mapa).
func _piece_name(type: String) -> String:
	match type:
		"tropical_island":
			return "una isla tropical"
	return "una pieza \"%s\"" % type


func _fail(file: String, message: String) -> void:
	_errors.append("::error title=Mapa %s::%s" % [file, message])
