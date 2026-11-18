// Movimiento del público (lo comparten el cuerpo y el contorno, así el
// contorno acompaña). c = INSTANCE_CUSTOM (ver crowd.gdshader).
// UV.x: 1 mano izquierda, 2 mano derecha, 3 bandera; UV.y: cuánto se mueve.
//
// La gente está tranquila (manos abajo, un vaivén) y se entusiasma cuando un
// surfista pasa cerca: levanta las manos, las agita y algunos saltan. Si el
// que pasa está haciendo un truco, más. En la tribuna además hacen "la ola".

// Cuánto salta el cuerpo entero (0 = sentados, cosas quietas).
uniform float jump = 0.0;
// Surfistas: xyz = posición, w = ganas que despierta (1 pasando, 2 con truco).
// Los pone CrowdDirector en cada cuadro.
uniform vec4 riders[4];
uniform int rider_count = 0;
// Cuánto bajan las manos al estar tranquilos (x: hacia adentro, y: abajo).
uniform vec2 hand_rest = vec2(0.15, 1.1);
// La ola de la tribuna: xy = dirección a lo largo de la tribuna, z = fuerza.
uniform vec3 ola = vec3(0.0);

// 0 = tranquilo, 1 = alentando, más de 1 = con todo.
float crowd_excite(vec3 origin) {
	float e = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= rider_count) {
			break;
		}
		float d = distance(origin.xz, riders[i].xz);
		e = max(e, smoothstep(45.0, 14.0, d) * riders[i].w);
	}
	if (ola.z > 0.0) {
		float along = dot(origin.xz, ola.xy);
		e = max(e, ola.z * smoothstep(0.75, 1.0, sin(TIME * 1.4 - along * 0.35)));
	}
	return e;
}

vec3 crowd_move(vec3 v, vec2 uv, vec4 c, float excite, float time) {
	float e = clamp(excite, 0.0, 1.0);
	float hype = clamp(excite - 1.0, 0.0, 1.0);
	// Dos ritmos fijos (tranquilo y alentando) que se mezclan: si el ritmo
	// dependiera de las ganas, que cambian todo el tiempo, multiplicado por el
	// reloj daría saltos de fase (manos que tiemblan y se agitan raro).
	float phase = c.z * 6.2831;
	float t_calm = time * (1.4 + c.w * 0.8) + phase;
	float t_cheer = time * (3.2 + c.w * 1.6) + phase;
	// Manos: tranquilos, abajo al costado del cuerpo; alentando, arriba y
	// agitándolas (subiendo y abriéndose).
	if (uv.x > 0.5 && uv.x < 2.5) {
		float side = uv.x > 1.5 ? 1.0 : -1.0;
		float rest = 1.0 - e;
		v.x -= side * hand_rest.x * rest * uv.y;
		v.y -= hand_rest.y * rest * uv.y;
		float wave = mix(sin(t_calm * 2.0 + side * 1.3), sin(t_cheer * 2.0 + side * 1.3), e);
		v.x += side * wave * (0.02 + 0.1 * e) * uv.y;
		v.y += (wave * 0.5 + 0.5) * (0.02 + 0.12 * e + 0.08 * hype) * uv.y;
	}
	// Banderas: flamean con el viento.
	if (uv.x > 2.5) {
		v.z += sin(time * 7.0 + c.z * 6.2831 + uv.y * 3.0) * 0.12 * uv.y;
	}
	// Saltitos de festejo (los que están parados): cuando pasan cerca, los más
	// entusiasmados; con un truco, casi todos.
	float jumper = max(smoothstep(0.5, 1.0, c.w) * e, hype * smoothstep(0.15, 0.6, c.w));
	v.y += jump * max(0.0, sin(t_cheer)) * 0.2 * jumper;
	return v;
}
