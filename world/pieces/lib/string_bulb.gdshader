// Focos de las guirnaldas. INSTANCE_CUSTOM: rgb = color del foco, a = fase
// (para titilar). De día son vidrio de color; de noche brillan.
shader_type spatial;
render_mode unshaded, cull_back;

// 0 de día, 1 de noche.
uniform float lit = 0.0;
// Cuánto titilan (las navideñas, más).
uniform float twinkle = 0.15;

varying vec4 v_c;

void vertex() {
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	float tw = 1.0 - twinkle * (0.5 + 0.5 * sin(TIME * 2.2 + v_c.a * 6.2831));
	vec3 day = mix(v_c.rgb, vec3(1.0), 0.25) * 0.75;
	vec3 night = v_c.rgb * 1.6 * tw + vec3(0.25) * tw;
	ALBEDO = mix(day, night, lit);
}
