// Público de la playa (gente, sillas, sombrillas y banderas): todo con
// MultiMesh y este shader. Cada instancia trae en INSTANCE_CUSTOM:
//   x: tono del color propio (remera, tela de la silla, sombrilla, bandera)
//   y: tono de piel (elige de skin_tones)
//   z: fase (para que no se muevan todos juntos)
//   w: ganas (cuánto salta y qué tan rápido agita los brazos)
// UV2.x dice qué parte es cada vértice (y UV2.y, el color fijo):
//   0 = color fijo (el rgb del vértice), 0.25 = piel, 0.5 = color propio,
//   0.75 = segundo color (short, gorra), 0.875 = pelo (de la lista),
//   1 = blanco que acompaña (rayas).
// UV.x marca lo que se mueve (ver crowd_motion.gdshaderinc).
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

// Cuánto salta el cuerpo entero (0 = sentados, cosas quietas).
uniform float jump = 0.0;
// Saturación del color propio y del segundo color: baja en la ropa de la gente
// (tonos pastel, que no llamen la atención), un poco más en sillas y sombrillas.
uniform float own_saturation = 0.5;
uniform float accent_saturation = 0.45;
// Colores fijos (BeachCrowd.FIXED_COLORS); UV2.y dice cuál.
uniform vec3 fixed_colors[9];
// Tonos de piel y de pelo (BeachCrowd.SKIN_TONES y HAIR_TONES).
uniform vec3 skin_tones[6];
uniform vec3 hair_tones[6];

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
		col = skin_tones[clamp(int(c.y * 6.0), 0, 5)];
	} else if (part > 0.85 && part < 0.92) {
		col = hair_tones[clamp(int(fract(c.z * 13.7 + c.y * 3.1) * 6.0), 0, 5)];
	} else if (part > 0.4 && part < 0.6) {
		col = hsv(c.x, own_saturation, 0.95);
	} else if (part > 0.65 && part < 0.85) {
		col = hsv(fract(c.x * 7.31 + 0.37), accent_saturation, 0.78);
	} else if (part > 0.95) {
		col = vec3(0.97);
	}
	v_col = pow(col, vec3(2.2));
	VERTEX = crowd_move(VERTEX, UV, c, jump, TIME);
}

void fragment() {
	ALBEDO = v_col;
}
