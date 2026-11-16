class_name RockArchPiece
extends MapPiece
## Arco de roca natural (se pasa por debajo): piedras facetadas apiladas en
## semicírculo, cada vez más finas arriba, con lianas colgando. Es de paisaje:
## no se choca.

const REQUIRED := ["x", "z"]

## Centro del arco (al nivel del agua).
var x: float = 0.0
var z: float = 0.0
## Hacia dónde mira el arco (grados): con 0, las patas quedan a los lados en X
## y se pasa por debajo yendo en Z.
var angle: float = 0.0
## Distancia del centro a cada pata y altura del arco (m).
var span: float = 40.0
var height: float = 26.0
## Semilla de la forma de las piedras.
var shape_seed: int = 77
var stone_color: Color = Color(0.5, 0.42, 0.36)
var moss_color: Color = Color(0.36, 0.55, 0.3)


func build(course: Course) -> void:
	var arch := Node3D.new()
	arch.name = "RockArch"
	arch.position = Vector3(x, 0.0, z)
	arch.rotation.y = deg_to_rad(angle)
	course.add_child(arch, true)
	var stone := ToonMaterial.make(stone_color, 0.12)
	var moss := ToonMaterial.make(moss_color, 0.12)
	var arng := RandomNumberGenerator.new()
	arng.seed = shape_seed
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
		boulder.position = Vector3(cos(ang) * span, sin(ang) * height - 2.0, arng.randf_range(-1.0, 1.0))
		boulder.rotation = Vector3(arng.randf() * TAU, arng.randf() * TAU, arng.randf() * TAU)
		boulder.scale = Vector3(arng.randf_range(1.0, 1.4), arng.randf_range(0.8, 1.1), arng.randf_range(0.9, 1.2))
		arch.add_child(boulder)
	# Lianas colgando del arco.
	for k in 5:
		var vine := MeshInstance3D.new()
		var vm := CylinderMesh.new()
		vm.top_radius = 0.18
		vm.bottom_radius = 0.1
		vm.height = arng.randf_range(4.0, 8.0)
		vm.material = moss
		vine.mesh = vm
		vine.position = Vector3(-10.0 + k * 5.0 + arng.randf_range(-1.5, 1.5), height - 4.0 - vm.height * 0.5, arng.randf_range(-2.0, 2.0))
		arch.add_child(vine)
