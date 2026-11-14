// Gota de lluvia (una por partícula): una raya corta y fina, estirada en la
// dirección en que cae y girada solo alrededor de ese eje para mirar a la
// cámara (así nunca se ve de canto ni "acostada"). La punta de abajo es la más
// clara y la cola se desvanece, como una gota que pasa rápido.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 fall_dir = vec3(0.22, -1.0, 0.08);
// Largo y ancho de la raya (m).
uniform float drop_length = 0.38;
uniform float drop_width = 0.022;
uniform vec4 tint : source_color = vec4(0.88, 0.92, 0.98, 0.8);
uniform float flash = 0.0;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 up = -normalize(fall_dir);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(up, to_cam));
	vec3 wp = center + side * VERTEX.x * drop_width + up * VERTEX.y * drop_length * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	// UV.y: 0 arriba (cola) .. 1 abajo (punta).
	float along = UV.y;
	float head = smoothstep(0.0, 1.0, along) * (1.0 - smoothstep(0.9, 1.0, along));
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = mix(tint.rgb, vec3(1.0), flash * 0.6);
	ALPHA = tint.a * head * across * (1.0 + flash);
}
