class_name ToonMaterial
extends RefCounted
## Materiales de colores planos con contorno negro (estética tipo Mii / Wii Sports).

const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")


## Cuánto ilumina la escena de día (sol + luz ambiente) la cara iluminada de un
## objeto. El color que se pide es el que se VE iluminado: se divide por esto,
## así los tonos pastel no se queman a blanco.
const LIT := 1.35


## Material con sombreado tipo cartoon y contorno. outline_width = 0 lo quita.
## `color` es como se ve con luz de día.
static func make(color: Color, outline_width: float = 0.035) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r / LIT, color.g / LIT, color.b / LIT, color.a)
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
