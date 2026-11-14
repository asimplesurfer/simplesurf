class_name AtollExtras
extends RefCounted
## Lo propio de El Atolón (lo arma Course porque lo pide world/maps/atoll.tres):
## géiseres en la laguna, un arco de roca natural sobre el paso norte y un
## barco pirata hundido.


static func build(course: Course) -> void:
	# Géiseres sobre la pista de la laguna (desfasados entre sí).
	var track := course.track
	var spots := [[Vector2(-78, -42), -5.0], [Vector2(-88, 12), 6.0], [Vector2(-62, 66), -4.0], [Vector2(-30, -98), 4.0]]
	for i in spots.size():
		var loc := track.locate(Vector3(spots[i][0].x, 0.0, spots[i][0].y))
		var pos := track.position_at(loc.x, spots[i][1])
		var g := Geyser.new()
		g.name = "Geyser%d" % i
		g.phase = i * 1.7
		g.position = Vector3(pos.x, 0.0, pos.z)
		course.add_child(g)
		course.geysers.append(g)
	# Arco de roca natural sobre el paso norte (se pasa por debajo): piedras
	# facetadas apiladas en semicírculo, cada vez más finas arriba.
	var arch := Node3D.new()
	arch.name = "RockArch"
	arch.position = Vector3(0.0, 0.0, -143.4)
	course.add_child(arch)
	var stone := ToonMaterial.make(Palette.STONE, 0.12)
	var moss := ToonMaterial.make(Palette.MOSS, 0.12)
	var arng := RandomNumberGenerator.new()
	arng.seed = 77
	var steps := 15
	for k in steps + 1:
		var t := float(k) / steps
		var ang := PI * t
		var thick := lerpf(9.0, 5.0, sin(ang))
		var boulder := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = thick
		sm.height = thick * 2.0
		sm.radial_segments = 7
		sm.rings = 4
		sm.material = moss if sin(ang) > 0.93 else stone
		boulder.mesh = sm
		boulder.position = Vector3(cos(ang) * 40.0, sin(ang) * 26.0 - 2.0, arng.randf_range(-1.0, 1.0))
		boulder.rotation = Vector3(arng.randf() * TAU, arng.randf() * TAU, arng.randf() * TAU)
		boulder.scale = Vector3(arng.randf_range(1.0, 1.4), arng.randf_range(0.8, 1.1), arng.randf_range(0.9, 1.2))
		arch.add_child(boulder)
	# Una cascadita de lianas colgando del arco.
	for k in 5:
		var vine := MeshInstance3D.new()
		var vm := CylinderMesh.new()
		vm.top_radius = 0.18
		vm.bottom_radius = 0.1
		vm.height = arng.randf_range(4.0, 8.0)
		vm.material = moss
		vine.mesh = vm
		vine.position = Vector3(-10.0 + k * 5.0 + arng.randf_range(-1.5, 1.5), 22.0 - vm.height * 0.5, arng.randf_range(-2.0, 2.0))
		arch.add_child(vine)
	# Barco pirata hundido en la laguna (de paisaje).
	course.add_child(_shipwreck(Vector3(96.0, 0.0, 4.0)))


## Un barco viejo medio hundido y ladeado, con el mástil roto y la vela rota.
static func _shipwreck(at: Vector3) -> Node3D:
	var ship := Node3D.new()
	ship.name = "Shipwreck"
	ship.position = at
	ship.rotation = Vector3(0.18, 0.7, 0.35)
	ship.scale = Vector3.ONE * 1.5
	var wood := ToonMaterial.make(Palette.WOOD, 0.12)
	var hull := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 3.0
	cap.height = 16.0
	cap.material = wood
	hull.mesh = cap
	hull.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.75))
	hull.position.y = -0.8
	ship.add_child(hull)
	var mast := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.35
	cyl.height = 11.0
	cyl.material = wood
	mast.mesh = cyl
	mast.position = Vector3(0.0, 5.0, -1.5)
	mast.rotation.z = 0.25
	ship.add_child(mast)
	var sail := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(5.0, 4.0, 0.1)
	quad.material = ToonMaterial.make(Palette.SAIL, 0.08)
	sail.mesh = quad
	sail.position = Vector3(0.6, 7.0, -1.5)
	sail.rotation = Vector3(0.0, 0.3, 0.3)
	ship.add_child(sail)
	var flag := MeshInstance3D.new()
	var fq := BoxMesh.new()
	fq.size = Vector3(1.6, 1.0, 0.05)
	fq.material = ToonMaterial.make(Palette.UI_INK, 0.0)
	flag.mesh = fq
	flag.position = Vector3(1.9, 10.4, -1.5)
	ship.add_child(flag)
	return ship
