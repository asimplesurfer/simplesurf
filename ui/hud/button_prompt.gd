class_name ButtonPrompt
extends Control
## Ícono de qué tocar, sin texto (como en las consolas):
## - FACE_BOTTOM: los 4 botones en rombo, el de abajo en negro.
## - KEY: una tecla con su nombre (para teclado).

enum Kind { FACE_BOTTOM, KEY }

var kind: Kind = Kind.FACE_BOTTOM:
	set(value):
		kind = value
		queue_redraw()
var key_text: String = "ESPACIO":
	set(value):
		key_text = value
		queue_redraw()
## 0..1: agranda el botón un instante (al apretarlo).
var pulse: float = 0.0

const INK := Color(0.06, 0.07, 0.09)
const RIM := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(1.0, 1.0, 1.0, 0.28)
const BACK := Color(0.0, 0.0, 0.0, 0.35)

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(110.0, 110.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.FACE_BOTTOM:
			_draw_face()
		Kind.KEY:
			_draw_key()


func _draw_face() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, BACK)
	var d := r * 0.56
	var br := r * 0.27
	for off in [Vector2(0.0, -d), Vector2(d, 0.0), Vector2(-d, 0.0)]:
		draw_circle(c + off, br, DIM)
		draw_arc(c + off, br, 0.0, TAU, 32, RIM, 2.0, true)
	# El de abajo: en negro, con borde marcado y latiendo.
	var beat := 0.06 * sin(_time * 10.0)
	var rr := br * (1.0 + beat + 0.25 * pulse)
	var p := c + Vector2(0.0, d)
	draw_circle(p, rr, INK)
	draw_arc(p, rr, 0.0, TAU, 32, RIM, 3.0, true)


func _draw_key() -> void:
	var font := get_theme_default_font()
	var fs := 26
	var text_w := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var w := maxf(text_w + 36.0, 64.0) * (1.0 + 0.12 * pulse)
	var h := 58.0 * (1.0 + 0.12 * pulse)
	var rect := Rect2(size * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.border_color = RIM
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.border_width_bottom = 7
	draw_style_box(box, rect)
	var baseline := rect.position.y + h * 0.5 + font.get_ascent(fs) * 0.35
	draw_string(
		font, Vector2(rect.position.x, baseline), key_text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, RIM
	)
