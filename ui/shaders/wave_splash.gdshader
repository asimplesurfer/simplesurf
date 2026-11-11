// Salir de atravesar una ola: la imagen se ve borrosa, con gotas en la "lente"
// y un tono de agua, y se aclara en medio segundo (amount va de 1 a 0).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	// Gotas: algunas celdas de una grilla tienen una gota redonda que refracta.
	// Se deslizan un poco hacia abajo mientras se aclara.
	vec2 grid = vec2(uv.x * 11.0 * aspect, uv.y * 11.0 - (1.0 - amount) * 1.5);
	vec2 cell = floor(grid);
	vec2 f = fract(grid) - 0.5;
	float h = hash(cell);
	vec2 off = vec2(hash(cell + 1.7), hash(cell + 9.3)) - 0.5;
	float r = mix(0.18, 0.42, hash(cell + 4.1)) * step(0.5, h);
	vec2 to_center = f - off * 0.35;
	float d = length(to_center);
	float drop = 1.0 - smoothstep(r * 0.82, r, d);
	vec2 refraction = -to_center * drop * 0.05 * amount;

	// Borroso: promedio de 9 muestras alrededor (más fuerte al principio).
	float b = 0.007 * amount;
	vec3 col = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			col += texture(screen_tex, uv + refraction + vec2(float(i), float(j)) * b).rgb;
		}
	}
	col /= 9.0;

	// Tono de agua y brillo en el borde de las gotas.
	col = mix(col, col * vec3(0.78, 0.95, 1.05) + vec3(0.02, 0.07, 0.11), 0.4 * amount);
	col += vec3(0.35) * drop * smoothstep(r * 0.55, r * 0.9, d) * amount;
	COLOR = vec4(col, 1.0);
}
