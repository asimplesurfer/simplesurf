class_name ToonMaterial
extends RefCounted
## Materiales de colores planos con contorno negro (estética tipo Mii / Wii Sports).

const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")


## Material con sombreado tipo cartoon y contorno. outline_width = 0 lo quita.
static func make(color: Color, outline_width: float = 0.035) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.8
	if outline_width > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("outline_width", outline_width)
		m.next_pass = outline
	return m


## Material de color plano sin luz (ojos, detalles).
static func flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
