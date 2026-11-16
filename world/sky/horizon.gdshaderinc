// El color del horizonte en una dirección (lo que se ve "lejos" para ese lado).
// Lo usan el cielo (justo en la línea del horizonte), la bruma del agua y las
// siluetas del anillo de islas lejanas: así todo se funde en el mismo color y
// desde ninguna altura se ve la costura entre el agua y el cielo.
//
// Los colores los pone Horizon (world/sky/horizon.gd) en todos los
// materiales a la vez, y la tormenta los cambia ahí.

uniform vec3 horizon_color : source_color = vec3(0.93, 0.9, 0.96);
// El brillo cálido del horizonte del lado del sol (en el cielo: glow_color).
uniform vec3 horizon_glow : source_color = vec3(1.0, 0.8, 0.74);
// Hacia dónde está el sol (en el plano: x, z).
uniform vec2 sun_flat = vec2(0.5, 0.83);

vec3 horizon_at(vec2 dir_flat) {
	vec2 dxz = dir_flat / max(length(dir_flat), 0.0001);
	vec2 sxz = sun_flat / max(length(sun_flat), 0.0001);
	float toward_sun = max(dot(dxz, sxz), 0.0);
	// Brillo cálido, más fuerte del lado del sol (igual que en el cielo).
	float glow = 0.25 + 0.75 * toward_sun * toward_sun;
	return mix(horizon_color, horizon_glow, glow * 0.4);
}
