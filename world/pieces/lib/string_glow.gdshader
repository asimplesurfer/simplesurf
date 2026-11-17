// Halo de luz alrededor de cada foco de noche: un cuadrado que siempre mira a
// la cámara, con un brillo redondo que se suma a lo de atrás.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.55;
uniform float twinkle = 0.15;

varying vec4 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	// Siempre de frente a la cámara (en el lugar de la instancia).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float tw = 1.0 - twinkle * (0.5 + 0.5 * sin(TIME * 2.2 + v_c.a * 6.2831));
	float g = pow(max(1.0 - r, 0.0), 2.2);
	ALBEDO = v_c.rgb * g * strength * tw;
}
