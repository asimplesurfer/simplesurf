// Cuadros blanco y negro (bandera de meta), en coordenadas del objeto.
shader_type spatial;
render_mode diffuse_toon;

uniform float squares_per_meter = 0.8;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = floor(v_local * squares_per_meter);
	float c = mod(p.x + p.y + p.z, 2.0);
	ALBEDO = mix(vec3(0.05), vec3(0.97), c);
}
