extends "res://tests/test_base.gd"
## Personajes: piezas, accesorios y contorno parejo.


func run() -> void:
	_test_avatar()
	_test_outline_width()
	_test_customization()


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
	# Una sola barra de cuerpo: los hombros solo del lado musculoso (y
	# grandes); la cabeza siempre del mismo tamaño.
	var radii: Array[float] = []
	var face := Vector3.ZERO
	for w in [0.0, 0.5, 1.0]:
		var body := CharacterData.new()
		body.weight = w
		body.head_size = 1.0 if w > 0.7 else 0.0
		var av2 := Avatar.new()
		av2.data = body
		root.add_child(av2)
		radii.append(av2.head_radius())
		if w == 0.5:
			face = av2.face_position()
		av2.free()
	_check(SurferKit.muscle_for(0.0) >= SurferKit.SHOULDERS_FROM, "musculoso: con hombros")
	_check(
		SurferKit.muscle_for(0.5) < SurferKit.SHOULDERS_FROM and SurferKit.muscle_for(1.0) < SurferKit.SHOULDERS_FROM,
		"normal y panzón: sin hombros (nada de hombritos chicos)"
	)
	_check(is_equal_approx(radii[0], radii[2]), "la cabeza es siempre del mismo tamaño (%.2f / %.2f)" % [radii[0], radii[2]])
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


## Rastas, collares, estampados, colores y exportar.
func _test_customization() -> void:
	print("Personalización:")
	# Rastas: ninguna pieza dentro de la cabeza, con cualquier forma de cabeza
	# y con el pelo sacudido al máximo (para atrás y de costado).
	var worst := 99.0
	for shape in CharacterData.HEAD_SHAPES.size():
		var d := CharacterData.new()
		d.hair_index = AvatarFeatures.DREADS
		d.head_index = shape
		var av := Avatar.new()
		av.data = d
		root.add_child(av)
		for group_name in ["HairFeatures"]:
			var g := av.find_child(group_name, true, false) as Node3D
			for mi in g.find_children("*", "MeshInstance3D", false, false):
				var mesh := (mi as MeshInstance3D).mesh
				var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var swings := [Vector3.ZERO, Vector3(0.5, 0, 0.07), Vector3(0.5, 0, -0.07), Vector3(-0.02, 0, 0.07), Vector3(-0.02, 0, -0.07)]
				for sw in swings:
					var rot := Basis.from_euler(sw)
					for v in verts:
						# Del grupo del pelo a la cabeza: gira en el pivote.
						var hv: Vector3 = v
						if group_name == "HairFeatures":
							hv = SurferKit.HAIR_PIVOT + rot * (v - SurferKit.HAIR_PIVOT)
						# Solo la parte de la cabeza (de la frente a la pera).
						if hv.y < -0.5 or hv.y > 0.5:
							continue
						var k := Vector3(hv.x / 0.48, hv.y / 0.5, hv.z / 0.44).length()
						worst = minf(worst, k)
		av.free()
	_check(worst > 0.98, "las rastas no atraviesan ninguna cabeza (lo más cerca: %.2f)" % worst)
	# Collares: dan toda la vuelta (también se ven por detrás).
	var all_around := true
	for neck in range(2, CharacterData.NECKLACES.size()):
		var d := CharacterData.new()
		d.neck_index = neck
		var av := Avatar.new()
		av.data = d
		root.add_child(av)
		var g := av.find_child("ChestFeatures", true, false) as Node3D
		var behind := 0
		for mi in g.find_children("*", "MeshInstance3D", false, false):
			for v in ((mi as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if v.z < -0.2:
					behind += 1
		if behind < 20:
			all_around = false
		av.free()
	_check(all_around, "todos los collares rodean el cuello (se ven por detrás)")
	# Estampado del short: pintado (sin piezas con relieve).
	var flat := true
	for pattern in CharacterData.SHORTS_PATTERNS.size():
		var d := CharacterData.new()
		d.shorts_pattern_index = pattern
		var av := Avatar.new()
		av.data = d
		root.add_child(av)
		var hips := av.find_child("HipsFeatures", true, false)
		if hips and int(hips.get_meta("pieces", 0)) > 0:
			flat = false
		if av.find_child("Flower*", true, false) != null:
			flat = false
		av.free()
	_check(flat, "los estampados del short son planos (sin piezas encima)")
	# Colores: el gorro de lana cambia, el de paja no; sin estampado no hay color.
	var c := CharacterData.new()
	c.hat_index = 7
	_check(c.field_applies("hat_color"), "el gorro de lana cambia de color")
	c.hat_index = 1
	_check(not c.field_applies("hat_color"), "el sombrero de paja no cambia de color")
	c.shorts_pattern_index = 0
	_check(not c.field_applies("shorts_pattern_color"), "short liso: sin color de estampado")
	c.shorts_pattern_index = 4
	_check(c.field_applies("shorts_pattern_color2"), "hawaiano: con dos colores")
	_check(CharacterData.PRESET_NAMES[0] == "Surfista rubio", "el primer estilo armado es el surfista rubio")
	_check(CharacterData.PRESETS.size() == CharacterData.PRESET_NAMES.size(), "cada estilo armado tiene nombre")
	var rasta := CharacterData.new()
	rasta.apply_preset(CharacterData.PRESET_NAMES.find("Rasta"))
	_check(rasta.get_option("hair") == AvatarFeatures.DREADS and rasta.get_option("hat") == 9,
		"estilo Rasta: rastas y gorro rasta")
	var shaggy_style := CharacterData.new()
	shaggy_style.apply_preset(CharacterData.PRESET_NAMES.find("Despeinado"))
	_check(shaggy_style.option_name("hair") == "Despeinado" and shaggy_style.option_name("glasses") == "Envolventes"
		and shaggy_style.option_name("nose") == "Con protector solar", "estilo Despeinado: pelo, anteojos y protector")
	var red_style := CharacterData.new()
	red_style.apply_preset(CharacterData.PRESET_NAMES.find("Pelirroja"))
	_check(red_style.option_name("hair") == "Melena ondulada" and red_style.option_name("hat") == "Sombrero de paja"
		and red_style.option_name("head") == "Suave", "estilo Pelirroja: melena, sombrero de paja y cabeza suave")
	_check(CharacterData.MOUTHS.has("Canchera") and CharacterData.MOUTHS.has("Sonrisa ancha")
		and CharacterData.MOUTHS.has("Pícara"), "sonrisas confiadas de una línea")
	# Piezas del despeinado (pelo, anteojos y cuellito). Un personaje guardado
	# con el cordón del short (que ya no está) se sigue leyendo.
	var shaggy := CharacterData.from_dict({"hair": 15, "glasses": 13, "neck": 9, "shorts_tie": 1})
	_check(shaggy.option_name("hair") == "Despeinado" and shaggy.option_name("glasses") == "Envolventes"
		and not CharacterData.FIELDS.has("shorts_tie"), "despeinado: pelo y anteojos (y ya no hay cordón)")
	var red := CharacterData.from_dict({"weight": 0.3, "build": 1, "hair": 17, "eyes": 11, "neck": 10,
		"hat": 1, "top": 1, "bottom": 1, "shorts": 8, "shorts_pattern": 2, "shorts_pattern_color": 10})
	_check(red.option_name("hair") == "Melena ondulada" and red.option_name("bottom") == "Bikini"
		and red.option_name("build") == "Flaca", "piezas nuevas: melena, bikini y silueta flaca")
	# Bikini abajo: no se arman las piernas del short.
	var av_red := Avatar.new()
	av_red.data = red
	root.add_child(av_red)
	var sleeve := av_red.find_child("SleeveL", true, false)
	_check(sleeve != null and sleeve.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"bikini: sin piernas de short")
	av_red.free()
	var mar := CharacterData.from_dict({"weight": 0.4, "head": 1, "hair": 16, "eyes": 10, "mouth": 10,
		"extra": 9, "ears": 4, "top": 3, "top_color": 4, "top_color2": 2})
	_check(mar.option_name("hair") == "Colita alta" and mar.option_name("top") == "Lycra de surf"
		and mar.option_name("mouth") == "Sonrisa abierta" and mar.option_name("ears") == "Con aritos",
		"piezas nuevas: colita alta, lycra, sonrisa abierta y aritos")
	_check(mar.field_applies("top_color") and not CharacterData.new().field_applies("top_color"),
		"el color de la lycra solo aparece con la lycra puesta")
	# Con la lycra, el torso es de tela (otro material que la piel).
	var av := Avatar.new()
	av.data = mar
	root.add_child(av)
	var torso := av.find_child("Torso", true, false)
	var has_top := false
	for mi in torso.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m and m.albedo_color.is_equal_approx(mar.accent("top_color")):
				has_top = true
	_check(has_top, "lycra: el torso se pinta del color de la lycra")
	av.free()
	var groups := {}
	for g in ["head", "hair", "chest", "hips"]:
		groups[g] = Node3D.new()
	var feats := AvatarFeatures.new()
	feats.build_head(groups.head, groups.hair, shaggy, shaggy.skin_color())
	feats.build_chest(groups.chest, shaggy, SurferKit.CHEST_RADII)
	feats.build_hips(groups.hips, shaggy, SurferKit.HIPS_RADII)
	_check(int(groups.hair.get_meta("pieces", 0)) >= 10, "despeinado: cáscara, mechones y flequillo")
	var plain := CharacterData.new()
	var plain_hips := Node3D.new()
	feats.build_hips(plain_hips, plain, SurferKit.HIPS_RADII)
	_check(int(groups.hips.get_meta("pieces", 0)) == 0 and int(plain_hips.get_meta("pieces", 0)) == 0,
		"el short no tiene cordón")
	for g in groups.values():
		(g as Node3D).free()
	plain_hips.free()
	# Exportar: el texto vuelve a dar el mismo personaje.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var r := CharacterData.random(rng)
	var parsed: Variant = JSON.parse_string(r.export_text())
	var back := CharacterData.from_dict(parsed)
	var same := true
	for f in CharacterData.FIELDS:
		if back.get_option(f) != r.get_option(f):
			same = false
	_check(same and absf(back.weight - r.weight) < 0.001, "exportar: el texto copiado arma el mismo personaje")
