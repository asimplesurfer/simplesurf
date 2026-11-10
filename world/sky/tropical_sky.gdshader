// Cielo tropical (estilo Hawái), todo procedural:
// degradé turquesa, brillo cálido en el horizonte, sol con halo, nubes tipo
// cúmulo de dos tonos (estilo toon, como los personajes) que se mueven
// despacio, e islas volcánicas en el horizonte.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.05, 0.38, 0.82);
uniform vec3 sky_color : source_color = vec3(0.25, 0.68, 0.96);
// Igual al color de la niebla del Environment, para que no se note el borde.
uniform vec3 horizon_color : source_color = vec3(0.70, 0.90, 0.98);
uniform vec3 glow_color : source_color = vec3(1.0, 0.80, 0.55);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.70, 0.82, 0.95);
uniform vec3 cloud_warm : source_color = vec3(1.0, 0.90, 0.78);
uniform vec3 island_color : source_color = vec3(0.13, 0.38, 0.36);
uniform vec3 island_far_color : source_color = vec3(0.38, 0.62, 0.70);
uniform vec3 ocean_color : source_color = vec3(0.06, 0.38, 0.62);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_speed = 0.008;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// Un volcán: cono redondeado centrado en el azimut c, de ancho w y alto h.
float volcano(float az, float c, float w, float h) {
	float d = abs(mod(az - c + 3.14159265, 6.28318531) - 3.14159265) / w;
	return h * pow(max(1.0 - d * d, 0.0), 1.6);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.3, 0.6, 0.5));

	// Degradé: horizonte claro -> celeste -> turquesa profundo arriba.
	float t = max(y, 0.0);
	vec3 col = mix(horizon_color, sky_color, smoothstep(0.0, 0.22, t));
	col = mix(col, zenith_color, smoothstep(0.22, 0.95, t));

	// Brillo cálido en el horizonte, más fuerte del lado del sol.
	vec2 dxz = d.xz / max(length(d.xz), 0.0001);
	vec2 sxz = sd.xz / max(length(sd.xz), 0.0001);
	float toward_sun = max(dot(dxz, sxz), 0.0);
	float glow = exp(-t * 10.0) * (0.25 + 0.75 * toward_sun * toward_sun);
	col = mix(col, glow_color, glow * 0.4);

	// Sol: halo suave.
	float sdot = max(dot(d, sd), 0.0);
	col += sun_color * (pow(sdot, 90.0) * 0.6 + pow(sdot, 10.0) * 0.12);

	// Nubes: proyectadas sobre un "techo" plano, más chicas hacia el horizonte.
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.15);
		uv += TIME * cloud_speed * vec2(1.0, 0.35) * 10.0;
		vec2 p = uv * 0.9;
		float n = fbm(p);
		float lim = 1.0 - cloud_coverage;
		float density = smoothstep(lim, lim + 0.06, n);
		// Lado iluminado: comparar con la nube corrida hacia el sol.
		float n_sun = fbm(p + sxz * 0.18);
		float lit = step(n_sun, n + 0.015);
		vec3 c = mix(cloud_shade, cloud_color, lit);
		// Borde cálido del lado del sol.
		c = mix(c, cloud_warm, toward_sun * lit * 0.25);
		// Se desvanecen bajando al horizonte (bruma).
		float fade = smoothstep(0.0, 0.18, y);
		c = mix(horizon_color, c, 0.35 + 0.65 * fade);
		col = mix(col, c, density * smoothstep(0.0, 0.04, y));
	}

	// Disco del sol (encima de las nubes, como en un dibujo).
	col = mix(col, sun_color * 1.25, smoothstep(0.9991, 0.9995, sdot));

	// Islas volcánicas en el horizonte: unas cerca y oscuras, otras lejos y con bruma.
	float az = atan(d.x, d.z);
	float ripple = (noise(vec2(az * 22.0, 0.0)) - 0.5) * 0.004;
	float near_h = max(max(
		volcano(az, 0.9, 0.42, 0.075),
		volcano(az, 1.25, 0.25, 0.045)),
		volcano(az, -2.3, 0.5, 0.06)) + ripple;
	float far_h = max(max(max(
		volcano(az, 2.4, 0.6, 0.05),
		volcano(az, -0.7, 0.35, 0.035)),
		volcano(az, -1.6, 0.3, 0.028)),
		volcano(az, 0.35, 0.22, 0.022)) + ripple * 0.5;
	if (y > -0.02 && y < far_h) {
		col = mix(col, island_far_color, 0.85);
	}
	if (y > -0.02 && y < near_h) {
		// Más claro arriba (sol) y con bruma abajo.
		vec3 ic = mix(island_color, island_color * 1.35, smoothstep(0.0, near_h, y));
		col = mix(horizon_color, ic, 0.55 + 0.45 * smoothstep(0.0, 0.03, y));
	}

	// Debajo del horizonte: mar que se funde con la bruma.
	if (y < -0.02) {
		col = mix(horizon_color, ocean_color, smoothstep(-0.02, -0.25, y));
	}

	COLOR = col;
}
