// Cortina de agua del derrape: un abanico translúcido que sale de la cola de
// la tabla hacia atrás, con vetas que corren y bordes deshilachados.
// UV.x = de un lado al otro del abanico, UV.y = distancia desde la tabla (0..1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

uniform vec3 color : source_color = vec3(0.9, 0.97, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float s = UV.y;
	float t = abs(UV.x * 2.0 - 1.0);
	float flow = TIME * 7.0;
	float streaks = fx_noise(vec2(UV.x * 16.0, s * 3.0 - flow));
	float spots = fx_noise(vec2(UV.x * 34.0, s * 11.0 - flow * 1.6));
	float side = 1.0 - smoothstep(0.55, 1.0, t);
	float along = smoothstep(0.0, 0.1, s) * (1.0 - smoothstep(0.5, 1.0, s));
	// Se va rompiendo más hacia la punta.
	float breakup = smoothstep(0.15 + 0.55 * s, 0.35 + 0.55 * s, streaks * 0.7 + spots * 0.5);
	float a = side * along * mix(0.5, 1.0, streaks) * mix(1.0, breakup, 0.75);
	ALBEDO = color * (0.88 + 0.12 * spots);
	ALPHA = clamp(a * intensity * 1.5, 0.0, 0.95);
}
