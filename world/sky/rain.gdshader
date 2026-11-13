// Velo gris de la tormenta sobre cada vista (apenas oscurece) y el destello
// del relámpago. Las gotas son 3D (ver storm.gd), no van acá.
shader_type canvas_item;

uniform float flash = 0.0;
uniform vec4 veil : source_color = vec4(0.12, 0.15, 0.2, 0.16);

void fragment() {
	vec4 col = veil;
	col.rgb = mix(col.rgb, vec3(0.92, 0.95, 1.0), flash * 0.5);
	col.a = max(col.a, flash * 0.18);
	COLOR = col;
}
