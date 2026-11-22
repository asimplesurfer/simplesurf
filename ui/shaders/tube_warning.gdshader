shader_type canvas_item;
// Aviso del tubo: el borde de la pantalla se tiñe cuando el surfista está por
// perder el equilibrio (más fuerte y más rojo cuanto más cerca de caerse).
// `side`: de qué lado se está yendo (-1 izquierda, 1 derecha, 0 parejo).

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.35, 0.2, 1.0);
uniform float side = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 uv = UV;
	// Distancia al borde (0 en el borde, 0.5 en el medio).
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y) * 1.4);
	float width = 0.05 + 0.1 * amount;
	float glow = 1.0 - smoothstep(0.0, width, edge);
	// Más fuerte del lado hacia donde se va.
	float lean = side > 0.0 ? uv.x : 1.0 - uv.x;
	glow *= mix(1.0, 0.35 + 1.1 * lean, abs(side));
	float a = glow * amount * (0.75 + 0.25 * pulse);
	COLOR = vec4(color.rgb, clamp(a, 0.0, 0.9));
}
