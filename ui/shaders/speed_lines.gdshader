// Rayas de velocidad a los lados de la pantalla (turbo / motivación).
shader_type canvas_item;

#include "res://effects/shaders/noise.gdshaderinc"

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float ang = atan(uv.y, uv.x);
	float r = length(uv * vec2(1.4, 1.0));
	// Cada raya es un "sector" angular que aparece y desaparece rápido.
	float sector = floor(ang * 70.0);
	float flick = floor(TIME * 16.0);
	float on = step(0.8, fx_hash(vec2(sector, flick)));
	float len = fx_hash(vec2(sector + 13.0, flick));
	float mask = smoothstep(0.62 - 0.2 * len, 0.75, r);
	COLOR = vec4(1.0, 1.0, 1.0, on * mask * intensity * 0.6);
}
