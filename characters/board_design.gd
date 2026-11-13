class_name BoardDesign
extends RefCounted
## Dibujo de arriba de la tabla (rayas, punta pintada, lunares). Se agrega
## encima de la tabla, que va a lo largo de Z con la punta hacia -Z.


## Agrega el diseño de `data` a `parent`. length / width: medidas de la tabla;
## top_y: altura de su cara de arriba.
static func add_to(parent: Node3D, data: CharacterData, length: float, width: float, top_y: float) -> void:
	var y := top_y + 0.004
	match data.get_option("board_design"):
		1:
			# Dos rayas a lo largo (roja y turquesa).
			_stripe(parent, -width * 0.12, y, width * 0.07, length * 0.8, Color("#e2513b"))
			_stripe(parent, width * 0.04, y, width * 0.07, length * 0.8, Color("#2fae9b"))
		2:
			_stripe(parent, 0.0, y, width * 0.14, length * 0.78, Color(0.2, 0.55, 0.95))
		3:
			var tip := _flat(Color("#e2513b"))
			var mi := MeshInstance3D.new()
			var m := SphereMesh.new()
			m.radius = 1.0
			m.height = 2.0
			m.material = tip
			mi.mesh = m
			mi.scale = Vector3(width * 0.36, 0.006, length * 0.16)
			mi.position = Vector3(0.0, y, -length * 0.33)
			parent.add_child(mi)
		4:
			var dot := SphereMesh.new()
			dot.radius = 1.0
			dot.height = 2.0
			dot.material = _flat(Color("#ff5a8a"))
			for i in 7:
				var mi := MeshInstance3D.new()
				mi.mesh = dot
				var x := (fmod(i * 0.618, 1.0) - 0.5) * width * 0.55
				var z := (i / 6.0 - 0.5) * length * 0.7
				mi.scale = Vector3(width * 0.07, 0.006, width * 0.07)
				mi.position = Vector3(x, y, z)
				parent.add_child(mi)


static func _stripe(parent: Node3D, x: float, y: float, w: float, l: float, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(w, 0.01, l)
	box.material = _flat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(x, y, 0.0)
	parent.add_child(mi)


static func _flat(color: Color) -> StandardMaterial3D:
	return ToonMaterial.make(color, 0.0)
