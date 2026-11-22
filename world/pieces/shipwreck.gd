class_name ShipwreckPiece
extends MapPiece
## Un barco viejo medio hundido y ladeado, con el mástil roto y la vela rota.
## Es de paisaje: no se choca.

const REQUIRED := ["x", "z"]

## Cómo se ve en el editor de mapas (ver MapPiece.editor_entry).
const EDITOR := {
	"name": "Barco hundido", "place": "point",
	"hint": "Clic para poner un barco hundido.",
	"fields": {"angle": "Ángulo (°)", "size": "Tamaño"},
}

var x: float = 0.0
var z: float = 0.0
## Hacia dónde apunta la proa (grados).
var angle: float = 40.107
var size: float = 1.5


func build(course: Course) -> void:
	var ship := Node3D.new()
	ship.name = "Shipwreck"
	ship.position = Vector3(x, 0.0, z)
	ship.rotation = Vector3(0.18, deg_to_rad(angle), 0.35)
	ship.scale = Vector3.ONE * size
	var wood := ToonMaterial.make(Color(0.42, 0.27, 0.15), 0.12)
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
	quad.material = ToonMaterial.make(Color(0.92, 0.88, 0.78), 0.08)
	sail.mesh = quad
	sail.position = Vector3(0.6, 7.0, -1.5)
	sail.rotation = Vector3(0.0, 0.3, 0.3)
	ship.add_child(sail)
	var flag := MeshInstance3D.new()
	var fq := BoxMesh.new()
	fq.size = Vector3(1.6, 1.0, 0.05)
	fq.material = ToonMaterial.make(Color(0.08, 0.08, 0.1), 0.0)
	flag.mesh = fq
	flag.position = Vector3(1.9, 10.4, -1.5)
	ship.add_child(flag)
	course.add_child(ship, true)
