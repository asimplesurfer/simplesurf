// Prueba (tests/water_match.gd): calcula en la placa de video la superficie
// del agua con EL MISMO código que el shader del agua (el include) en una
// grilla de puntos, y lo escribe en píxeles para compararlo con la física.
// Cada píxel guarda un número con 16 bits (en rojo y verde).
//   filas 0..rows-1: altura · rows..2rows-1: corrimiento x · 2rows..3rows-1:
//   corrimiento z · fila 3rows: valores conocidos (para comprobar la lectura).
shader_type canvas_item;

#include "res://world/water/water_surface.gdshaderinc"

uniform vec2 origin = vec2(0.0);
uniform vec2 spacing = vec2(1.0);
uniform int cols = 1;
uniform int rows = 1;

const float RANGE = 16.0;

vec4 encode(float v) {
	float n = clamp((v + RANGE) / (2.0 * RANGE), 0.0, 1.0);
	float q = floor(n * 65535.0 + 0.5);
	return vec4(floor(q / 256.0) / 255.0, mod(q, 256.0) / 255.0, 0.0, 1.0);
}

void fragment() {
	ivec2 px = ivec2(floor(UV * vec2(float(cols), float(rows * 3 + 1))));
	int ch = px.y / rows;
	int r = px.y - ch * rows;
	if (px.y >= rows * 3) {
		COLOR = encode(3.25 - float(px.x) * 0.1);
	} else {
		vec2 p = origin + vec2(float(px.x), float(r)) * spacing;
		float h;
		vec2 g;
		vec2 disp;
		float ambient_h;
		float body;
		float lip;
		float grow;
		float tube;
		water_surface(p, h, g, disp, ambient_h, body, lip, grow, tube);
		float v = ch == 0 ? h : (ch == 1 ? disp.x : disp.y);
		COLOR = encode(v);
	}
}
