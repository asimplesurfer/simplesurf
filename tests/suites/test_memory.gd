extends "res://tests/test_base.gd"
## Memoria: varias carreras seguidas sin acumular nada.


func run() -> void:
	await _test_memory()


## Varias carreras seguidas: nada se tiene que ir acumulando (ni entre
## carreras ni durante una carrera).
func _test_memory() -> void:
	print("Memoria (varias carreras seguidas):")
	var rows: Array[Dictionary] = []
	var in_race_growth := 0
	for round_i in 4:
		var m: Node = load("res://main.tscn").instantiate()
		# Carrera de bots normal (no modo demo: en la demo cualquier tecla
		# vuelve al menú), en la isla y con sol, como siempre midió este test.
		var cfg := RaceConfig.demo()
		cfg.mode = RaceConfig.Mode.RACE
		cfg.layout = GameSettings.TrackLayout.CLASSIC
		cfg.weather = GameSettings.Weather.SUNNY
		(m.get_node("RaceManager") as RaceManager).config = cfg
		root.add_child(m)
		await _wait(5.0)
		var nodes_a := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objs_a := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		await _wait(10.0)
		var nodes_b := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objs_b := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		in_race_growth = maxi(in_race_growth, objs_b - objs_a)
		print("    carrera %d: nodos %d -> %d, objetos %d -> %d" % [round_i + 1, nodes_a, nodes_b, objs_a, objs_b])
		m.queue_free()
		for i in 5:
			await process_frame
		var row := {
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		}
		rows.append(row)
		print("    después de cerrarla: %s" % row)
	# El menú se rearma con cada opción (V, G, O...): tampoco debe acumular.
	var menu: CharacterSelect = load("res://ui/menus/character_select.tscn").instantiate()
	menu.auto_start = false
	root.add_child(menu)
	await process_frame
	for i in 10:
		menu._build()
		await process_frame
	await process_frame
	var menu_nodes := menu.get_child_count()
	menu.queue_free()
	for i in 5:
		await process_frame
	var after_menu := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("    después del menú rearmado 10 veces: nodos %d" % after_menu)

	var first: Dictionary = rows[1]
	var last: Dictionary = rows[3]
	_check(last.nodes - first.nodes <= 2, "entre carreras no se acumulan nodos (%d -> %d)" % [first.nodes, last.nodes])
	_check(
		last.objects - first.objects <= 50,
		"entre carreras no se acumulan objetos (%d -> %d)" % [first.objects, last.objects]
	)
	_check(
		last.resources - first.resources <= 20,
		"entre carreras no se acumulan recursos (%d -> %d)" % [first.resources, last.resources]
	)
	_check(last.orphans <= first.orphans, "no quedan nodos sueltos (%d -> %d)" % [first.orphans, last.orphans])
	_check(in_race_growth <= 200, "durante la carrera no crece la memoria (+%d objetos en 10 s)" % in_race_growth)
	_check(menu_nodes <= 5 and after_menu <= last.nodes + 2, "el menú no se acumula al rearmarse (%d hijos: fondo, miniaturas, pantalla, demo y build)" % menu_nodes)
