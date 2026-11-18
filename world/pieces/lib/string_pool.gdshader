// Reflejo de las guirnaldas en el mar: una franja ancha debajo del cable que
// se suma al agua. Más fuerte en el medio, se apaga hacia los costados y las
// puntas, y tiembla un poco como el reflejo en el agua que se mueve.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.6);
uniform float strength = 0.4;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	// Muy suave: se va apagando de a poco hacia los costados y las puntas.
	float ends = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.65, UV.y);
	float g = exp(-across * across * 2.2) * (1.0 - across) * ends;
	// Un vaivén lento y amplio (el agua que se mueve), sin rayas marcadas.
	float ripple = 0.9 + 0.1 * sin(v_world.x * 0.12 + v_world.z * 0.09 + TIME * 0.8);
	ALBEDO = tint * g * strength * ripple;
}
