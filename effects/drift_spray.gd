class_name DriftSpray
extends Node3D
## Agua que levanta el derrape: una cortina translúcida en abanico que sale de
## la cola de la tabla hacia atrás y afuera, más bruma de gotas.
## La cortina está armada para tirar el agua hacia -X (afuera, derrapando a la
## derecha); para el otro lado se espeja con scale.x = -1.

const SHEET_SHADER := preload("res://effects/shaders/spray_sheet.gdshader")

## Largo de la cortina hacia atrás (m).
@export var length: float = 4.2
## Altura máxima de la cortina (m).
@export var height: float = 2.4

var _sheet: MeshInstance3D
var _sheet_material := ShaderMaterial.new()
var _mist: CPUParticles3D
var _amount: float = 0.0
var _side: int = 1


func _ready() -> void:
	_sheet_material.shader = SHEET_SHADER
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	_sheet.mesh = _build_sheet_mesh()
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.visible = false
	add_child(_sheet)

	_mist = WaterFx.soft_particles(110, 0.9, 0.75)
	_mist.name = "Mist"
	_mist.initial_velocity_min = 4.5
	_mist.initial_velocity_max = 8.5
	_mist.spread = 24.0
	add_child(_mist)


## Llamar cada frame. side = lado del derrape (-1 / 1), 0 si no derrapa.
func update_spray(side: int, strength: float, delta: float) -> void:
	var active := side != 0
	if active:
		_side = side
	var target := clampf(strength, 0.0, 1.0) if active else 0.0
	var rate := 6.0 if target > _amount else 3.5
	_amount = move_toward(_amount, target, rate * delta)

	_sheet.visible = _amount > 0.01
	# Crece desde la tabla al empezar y se achica al terminar.
	_sheet.scale = Vector3(float(_side) * (0.6 + 0.4 * _amount), _amount, 0.4 + 0.6 * _amount)
	_sheet_material.set_shader_parameter("intensity", _amount)

	_mist.emitting = active
	_mist.direction = Vector3(-_side * 0.55, 0.75, 1.0).normalized()


## Abanico: s = distancia desde la tabla (0..1), t = de un lado al otro (-1..1).
func _build_sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 14
	var cols := 10
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for r in rows + 1:
		var s := float(r) / rows
		for c in cols + 1:
			var t := float(c) / cols * 2.0 - 1.0
			var x := -(0.5 * s + 0.9 * s * s) + t * (0.2 + 1.5 * s)
			var y := height * sin(PI * 0.85 * s) * (1.0 - 0.35 * absf(t))
			var z := length * s
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(float(c) / cols, s))
	for r in rows:
		for c in cols:
			var i0 := r * (cols + 1) + c
			var i1 := i0 + 1
			var i2 := i0 + cols + 1
			var i3 := i2 + 1
			for i in [i0, i2, i1, i1, i2, i3]:
				st.set_uv(uvs[i])
				st.add_vertex(verts[i])
	st.set_material(_sheet_material)
	return st.commit()
