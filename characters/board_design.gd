class_name BoardDesign
extends RefCounted
## Material de la tabla con su diseño pintado arriba (rayas, llamas, cuadros...),
## con los colores que eligió el jugador. Ver board_design.gdshader.

const SHADER := preload("res://characters/board_design.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")


## Material para una tabla cápsula de `length` x `width` (la cápsula va a lo
## largo de su Y, acostada sobre Z con la punta hacia -Z).
static func material(data: CharacterData, length: float, width: float, outline_width: float = 0.04) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("board_color", data.board_color())
	m.set_shader_parameter("color1", data.accent("board_design_color"))
	m.set_shader_parameter("color2", data.accent("board_design_color2"))
	m.set_shader_parameter("design", data.get_option("board_design"))
	m.set_shader_parameter("half_w", width * 0.5)
	m.set_shader_parameter("half_l", length * 0.5)
	if outline_width > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("outline_width", outline_width)
		m.next_pass = outline
	return m
