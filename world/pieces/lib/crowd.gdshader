// Público de la playa (gente, sillas, sombrillas y banderas): todo con
// MultiMesh y este shader. Cada instancia trae en INSTANCE_CUSTOM:
//   x: tono del color propio (remera, tela de la silla, sombrilla, bandera)
//   y: tono de piel (0 claro .. 1 oscuro)
//   z: fase (para que no se muevan todos juntos)
//   w: ganas (cuánto salta y qué tan rápido agita los brazos)
// UV2.x dice qué parte es cada vértice (y UV2.y, el color fijo):
//   0 = color fijo (el rgb del vértice), 0.25 = piel, 0.5 = color propio,
//   0.75 = segundo color (short, gorra), 1 = blanco que acompaña (rayas).
// UV.x marca lo que se mueve (ver crowd_motion.gdshaderinc).
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

// Cuánto salta el cuerpo entero (0 = sentados, cosas quietas).
uniform float jump = 0.0;
// Colores fijos (BeachCrowd.FIXED_COLORS); UV2.y dice cuál.
uniform vec3 fixed_colors[9];

varying vec3 v_col;

vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

#include "res://world/pieces/lib/crowd_motion.gdshaderinc"

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float part = UV2.x;
	vec3 col = fixed_colors[clamp(int(UV2.y + 0.5), 0, 8)];
	if (part > 0.15 && part < 0.35) {
		col = mix(vec3(0.98, 0.8, 0.66), vec3(0.42, 0.26, 0.16), c.y);
	} else if (part > 0.4 && part < 0.6) {
		col = hsv(c.x, 0.7, 0.97);
	} else if (part > 0.65 && part < 0.85) {
		col = hsv(fract(c.x * 7.31 + 0.37), 0.6, 0.6);
	} else if (part > 0.9) {
		col = vec3(0.97);
	}
	v_col = pow(col, vec3(2.2));
	VERTEX = crowd_move(VERTEX, UV, c, jump, TIME);
}

void fragment() {
	ALBEDO = v_col;
}
