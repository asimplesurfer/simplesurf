class_name CarveSpray
extends Node3D
## Agua que levanta el canto de la tabla al girar rápido (solo se ve: no tumba
## a nadie). Estilo cartoon, como el resto del juego:
## - una pared de agua con bordes nítidos en dos tonos que se abre hacia afuera
##   de la curva y se rompe en pedazos en la punta;
## - gotas gordas y definidas que salen en arco y caen;
## - espuma que queda en el agua marcando la curva.
## El nodo se ubica en el canto de afuera de la tabla, apuntando hacia afuera
## y atrás (+Z local).

const SHEET_SHADER := preload("res://effects/shaders/carve_sheet.gdshader")

@export var length: float = 3.8
@export var height: float = 1.3

var _sheet: MeshInstance3D
var _sheet_material := ShaderMaterial.new()
var _drops: CPUParticles3D
var _foam: CPUParticles3D
var _amount: float = 0.0
var _flow: float = 0.0
## Los dibujos de las gotas y de la espuma (se pintan con el agua de ahora).
var _drop_shape: Gradient
var _foam_shape: Gradient


func _ready() -> void:
	_sheet_material.shader = SHEET_SHADER
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	_sheet.mesh = _build_sheet_mesh()
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.visible = false
	add_child(_sheet)
	_drops = _toon_particles(90, 0.75, 0.26, false)
	_drops.name = "Drops"
	_drops.direction = Vector3(0.0, 0.8, 1.0).normalized()
	_drops.spread = 34.0
	_drops.initial_velocity_min = 4.0
	_drops.initial_velocity_max = 8.5
	_drops.gravity = Vector3(0.0, -16.0, 0.0)
	_drops.position = Vector3(0.0, 0.5, length * 0.45)
	add_child(_drops)
	_foam = _toon_particles(40, 1.1, 0.9, true)
	_foam.name = "Foam"
	_foam.gravity = Vector3.ZERO
	_foam.initial_velocity_min = 0.3
	_foam.initial_velocity_max = 1.2
	_foam.direction = Vector3(0.0, 0.0, 1.0)
	_foam.spread = 30.0
	_foam.position = Vector3(0.0, 0.04, 0.3)
	add_child(_foam)
	set_water_colors(WaterPalette.BASE.foam_color, WaterPalette.BASE.spray_color)


## Colores del agua de ahora (ver Water.fx_colors): lo blanco y el celeste del borde.
func set_water_colors(foam: Color, spray: Color) -> void:
	_sheet_material.set_shader_parameter("foam", foam)
	_sheet_material.set_shader_parameter("water", spray)
	_drop_shape.colors = _drop_colors(foam, spray)
	_foam_shape.colors = _foam_colors(foam)


## Gota: centro blanco y borde celeste, nítidos.
static func _drop_colors(foam: Color, spray: Color) -> PackedColorArray:
	var edge := Color(spray, 1.0)
	return PackedColorArray([Color(foam, 1.0), Color(foam, 1.0), edge, edge, Color(spray, 0.0)])


## Espuma: un anillo (el centro más claro que el borde, como una burbuja abierta).
static func _foam_colors(foam: Color) -> PackedColorArray:
	return PackedColorArray([Color(foam, 0.35), Color(foam, 0.35), Color(foam, 1.0), Color(foam, 1.0), Color(foam, 0.0)])


## Llamar cada frame. active: si está girando rápido; strength 0..1.
func update_spray(active: int, strength: float, delta: float) -> void:
	var target := clampf(strength, 0.0, 1.0) if active != 0 else 0.0
	var rate := 5.0 if target > _amount else 3.0
	_amount = move_toward(_amount, target, rate * delta)
	_flow = fmod(_flow + delta, 100.0)
	_sheet.visible = _amount > 0.01
	# Crece hacia arriba y hacia afuera con la fuerza del giro.
	_sheet.scale = Vector3(0.7 + 0.3 * _amount, 0.25 + 0.75 * _amount, 0.5 + 0.5 * _amount)
	_sheet_material.set_shader_parameter("intensity", _amount)
	_sheet_material.set_shader_parameter("flow_time", _flow)
	WaterFx.emit(_drops, active != 0 and _amount > 0.2)
	_drops.initial_velocity_max = 5.0 + 5.0 * _amount
	WaterFx.emit(_foam, active != 0 and _amount > 0.1)


## Partículas con forma nítida (un círculo blanco con borde celeste, sin
## difuminar; con los colores del agua de ahora). `flat`: acostadas sobre el agua (espuma) en vez de mirar a la cámara.
func _toon_particles(amount: int, lifetime: float, size: float, flat: bool) -> CPUParticles3D:
	# Los colores los pone set_water_colors (el agua de ahora).
	var gradient := Gradient.new()
	if flat:
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.5, 0.8, 0.86])
		gradient.colors = _foam_colors(Color.WHITE)
		_foam_shape = gradient
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.66, 0.84, 0.88])
		gradient.colors = _drop_colors(Color.WHITE, Color.WHITE)
		_drop_shape = gradient
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = tex
	if flat:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# Las gotas que no están volando tienen escala 0: así no se dibujan
		# (si no, quedan como un punto negro en el origen).
		material.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	if flat:
		quad.orientation = PlaneMesh.FACE_Y
	quad.material = material
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var grow := Curve.new()
	if flat:
		grow.add_point(Vector2(0.0, 0.4))
		grow.add_point(Vector2(1.0, 1.6))
	else:
		grow.add_point(Vector2(0.0, 1.0))
		grow.add_point(Vector2(1.0, 0.6))
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.visible = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.scale_amount_min = 0.3
	p.scale_amount_max = 1.6
	# Sin sombra (si no, cada gota deja un punto negro en el agua).
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.scale_amount_curve = grow
	p.color_ramp = fade
	return p


## Pared que sale del canto: s = distancia (0..1), t = de un lado al otro
## (-1..1). Sube, se abre y la punta se curva hacia afuera (como un abanico).
func _build_sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 16
	var cols := 10
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for r in rows + 1:
		var s := float(r) / rows
		for c in cols + 1:
			var t := float(c) / cols * 2.0 - 1.0
			var x := t * (0.35 + length * s * 0.32)
			var rise := height * sin(PI * 0.9 * s)
			var y := rise * (1.0 - 0.3 * absf(t)) + 0.05
			# La punta se curva hacia afuera (+Z) y un poco hacia abajo.
			var z := length * s + 0.35 * height * s * s
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
