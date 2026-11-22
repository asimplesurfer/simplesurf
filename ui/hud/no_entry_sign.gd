extends Control
## Señal de prohibido (círculo rojo con una barra cruzada): el aviso de ir
## al revés. Se dibuja (la letra del juego no tiene ese símbolo) y late un poco.

const RED := Color(0.93, 0.2, 0.18)
const OUTLINE := Color(0.05, 0.13, 0.2)
const RING := 0.16
const BAR := 0.2

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * (1.0 + 0.04 * sin(_t * 8.0))
	var ring := r * RING
	var edge := maxf(3.0, r * 0.05)
	# Fondo blanco translúcido adentro, para que se lea sobre el agua.
	draw_circle(c, r - ring * 0.5, Color(1.0, 1.0, 1.0, 0.35))
	# Contorno oscuro (como los textos), aro rojo y barra cruzada.
	var dir := Vector2(cos(PI * 0.25), sin(PI * 0.25))
	var half := dir * (r - ring)
	draw_line(c - half, c + half, OUTLINE, r * BAR + edge * 2.0, true)
	draw_arc(c, r - ring * 0.5, 0.0, TAU, 64, OUTLINE, ring + edge * 2.0, true)
	draw_arc(c, r - ring * 0.5, 0.0, TAU, 64, RED, ring, true)
	draw_line(c - half, c + half, RED, r * BAR, true)
