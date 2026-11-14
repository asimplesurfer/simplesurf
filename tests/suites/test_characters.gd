extends "res://tests/test_base.gd"
## Personajes: piezas, accesorios y contorno parejo.


func run() -> void:
	_test_avatar()
	_test_outline_width()


func _test_avatar() -> void:
	print("Personaje:")
	var parts := AvatarCore.get_avatar(0.0)
	_check(parts.size() == 14, "el personaje tiene 14 piezas, con las piernas del short (%d)" % parts.size())
	_check(AvatarCore.stage_name(0.0) == "Musculoso", "t=0 es Musculoso")
	_check(AvatarCore.stage_name(1.0) == "Cervecero", "t=1 es Cervecero")
	_check(AvatarCore.stage_name(0.45) == "Delgado", "t=0.45 es Delgado")
	var fat := AvatarCore.get_avatar(1.0)
	var delt_hidden := false
	var belly_big := false
	for p in fat:
		var r: Vector3 = p.radii
		if p.id == "delt_L" and minf(r.x, minf(r.y, r.z)) < 0.05:
			delt_hidden = true
		if p.id == "belly" and r.z > 0.3:
			belly_big = true
	_check(delt_hidden, "Cervecero: los hombros desaparecen")
	_check(belly_big, "Cervecero: panza grande")
	var green := AvatarCore.get_avatar(0.5, CharacterData.SKIN_COLORS[5])
	_check(green[0].color == CharacterData.SKIN_COLORS[5], "se puede cambiar el color de piel")
	# Creador: estilos, guardado y opciones de chiste.
	var c := CharacterData.new()
	c.apply_preset(0)
	var back := CharacterData.from_dict(c.to_dict())
	_check(back.to_dict() == c.to_dict(), "el personaje se guarda y se carga igual")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var all_ok := true
	for i in 30:
		var r := CharacterData.random(rng)
		var av := Avatar.new()
		av.data = r
		root.add_child(av)
		if av.find_child("HeadFeatures", true, false) == null:
			all_ok = false
		av.free()
	_check(all_ok, "30 personajes al azar se arman sin errores")
	var big := CharacterData.new()
	big.head_size = 1.0
	var av2 := Avatar.new()
	av2.data = big
	root.add_child(av2)
	var head_r := av2.head_radius()
	var face := av2.face_position()
	av2.free()
	_check(head_r > 0.65, "cabezón: la cabeza es más grande (%.2f)" % head_r)
	_check(face.z > 0.3 and face.y > 1.9, "la cara está adelante de la cabeza (%s)" % face)


## El contorno mide siempre lo mismo, aunque la pieza esté estirada o agrandada.
func _test_outline_width() -> void:
	print("Contorno parejo:")
	var sphere := SphereMesh.new()
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var worst := 0.0
	for scale in [Vector3.ONE, Vector3(2.2, 1.4, 2.7), Vector3(0.4, 0.4, 0.4)]:
		var to_char := Basis.from_scale(scale) * Basis(Vector3.UP, 0.7)
		var hull := [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		SurferKit.append_hull(hull, verts, normals, indices, to_char, SurferKit.OUTLINE_WIDTH)
		for i in range(0, verts.size(), 7):
			var gap := (to_char * (hull[0] as PackedVector3Array)[i]).distance_to(to_char * verts[i])
			worst = maxf(worst, absf(gap - SurferKit.OUTLINE_WIDTH))
	_check(worst < 0.002, "el trazo tiene el mismo grosor en piezas chicas, grandes y estiradas (error %.4f)" % worst)
	# Un personaje gordo y cabezón: todo su contorno sale del mismo grosor.
	var d := CharacterData.new()
	d.weight = 1.0
	d.head_size = 1.0
	var a := Avatar.new()
	a.data = d
	root.add_child(a)
	var outlines := 0
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for k in mesh.get_surface_count():
			var m := mesh.surface_get_material(k) as BaseMaterial3D
			if m and m.albedo_color.v < 0.15 and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX].size() > 30:
				outlines += 1
	_check(outlines > 5, "el personaje tiene sus contornos (%d)" % outlines)
	a.queue_free()
