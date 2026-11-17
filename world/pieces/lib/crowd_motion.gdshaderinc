// Movimiento del público (lo comparten el cuerpo y el contorno, así el
// contorno acompaña). c = INSTANCE_CUSTOM (ver crowd.gdshader).
// UV.x: 1 mano izquierda, 2 mano derecha, 3 bandera; UV.y: cuánto se mueve.
vec3 crowd_move(vec3 v, vec2 uv, vec4 c, float jump_amount, float time) {
	float t = time * (1.6 + c.w * 2.2) + c.z * 6.2831;
	// Manos: suben y bajan, y se abren un poco (aplauden o agitan).
	if (uv.x > 0.5 && uv.x < 2.5) {
		float side = uv.x > 1.5 ? 1.0 : -1.0;
		float wave = sin(t * 2.0 + side * 1.3);
		v.x += side * wave * (0.04 + 0.08 * c.w) * uv.y;
		v.y += (wave * 0.5 + 0.5) * (0.03 + 0.1 * c.w) * uv.y;
	}
	// Banderas: flamean con el viento.
	if (uv.x > 2.5) {
		v.z += sin(time * 7.0 + c.z * 6.2831 + uv.y * 3.0) * 0.12 * uv.y;
	}
	// Saltitos de festejo: solo los más entusiasmados (los que están parados).
	v.y += jump_amount * max(0.0, sin(t)) * 0.16 * smoothstep(0.55, 1.0, c.w);
	return v;
}
