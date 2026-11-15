// Llamas sobre la barra de nitro: con turbo (naranja, se consume) y con la
// barra llena (rojo, "a punto de reventar"). Cubre solo la parte llena (fill).
shader_type canvas_item;

#include "res://effects/shaders/noise.gdshaderinc"

// Parte llena de la barra (0..1 del ancho).
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// Ancho / alto de la barra (para que las llamas no se estiren).
uniform float aspect = 14.0;
uniform vec3 cold : source_color = vec3(0.85, 0.2, 0.02);
uniform vec3 hot : source_color = vec3(1.0, 0.85, 0.25);
// Velocidad a la que corren las llamas (hacia la izquierda, consumiendo).
uniform float flow = 3.0;

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	// Solo adentro de la parte llena, con el borde derecho suave.
	float inside = 1.0 - smoothstep(fill - 0.012, fill, UV.x);
	// Lenguas de fuego: ruido que sube y corre hacia la izquierda.
	float n1 = fx_noise(vec2(p.x * 1.6 + TIME * flow, p.y * 2.0 - TIME * 4.0));
	float n2 = fx_noise(vec2(p.x * 3.4 + TIME * flow * 1.7, p.y * 3.0 - TIME * 7.0));
	float flame = n1 * 0.65 + n2 * 0.35;
	// Más caliente abajo y en la punta que se consume.
	float tip = smoothstep(fill - 0.12, fill, UV.x);
	float heat = clamp(flame * 1.2 + (1.0 - UV.y) * 0.35 + tip * 0.5, 0.0, 1.0);
	vec3 col = mix(cold, hot, heat);
	float a = inside * intensity * (0.55 + 0.45 * flame);
	COLOR = vec4(col, a);
}
