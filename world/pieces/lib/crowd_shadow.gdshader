// Sombra redonda y suave debajo de cada cosa del público (gente, sillas,
// sombrillas): así quedan apoyados en la arena y no parecen flotar.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.32;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.12, 0.09, 0.05);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r));
}
