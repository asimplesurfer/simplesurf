class_name ButtonPrompt
extends Control
## Ícono de qué tocar, sin texto (como en las consolas):
## - FACE_BOTTOM: los 4 botones en rombo, el de abajo en negro.
## - STICK_UP: una palanca que se tira hacia arriba de golpe, en loop.
## - KEY: una tecla con su nombre (para teclado).

enum Kind { FACE_BOTTOM, STICK_UP, KEY }

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
## Duración de un ciclo de la animación de la palanca (s).
const STICK_CYCLE := 0.9

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
		Kind.STICK_UP:
			_draw_stick()
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


func _draw_stick() -> void:
	var c := size * 0.5 + Vector2(0.0, size.y * 0.12)
	var r := minf(size.x, size.y) * 0.5
	var base_r := r * 0.62
	draw_circle(c, base_r, BACK)
	draw_arc(c, base_r, 0.0, TAU, 40, DIM, 3.0, true)
	# Quieta, golpe rápido arriba, un momento arriba y vuelve.
	var t := fmod(_time, STICK_CYCLE) / STICK_CYCLE
	var up := 0.0
	if t < 0.25:
		up = 0.0
	elif t < 0.35:
		up = ease((t - 0.25) / 0.1, 0.4)
	elif t < 0.7:
		up = 1.0
	elif t < 0.85:
		up = 1.0 - (t - 0.7) / 0.15
	var knob := c + Vector2(0.0, -base_r * 0.5 * up)
	# Flecha arriba (bien separada de la palanca): se ilumina con el golpe.
	var tip := c + Vector2(0.0, -r * 1.12)
	var w := r * 0.27
	var arrow := Color(RIM, 0.3 + 0.7 * up)
	draw_colored_polygon(
		PackedVector2Array([tip, tip + Vector2(w, w * 1.1), tip + Vector2(-w, w * 1.1)]), arrow
	)
	# Rayitas de movimiento mientras sube rápido.
	var swish := clampf(1.0 - absf(t - 0.33) / 0.08, 0.0, 1.0)
	if swish > 0.0:
		for dx in [-0.16, 0.16]:
			var x: float = knob.x + r * float(dx)
			draw_line(
				Vector2(x, knob.y + r * 0.42), Vector2(x, knob.y + r * 0.85),
				Color(RIM, 0.8 * swish), 3.0, true
			)
	var knob_r := r * 0.34
	draw_circle(knob + Vector2(0.0, 3.0), knob_r, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(knob, knob_r, INK)
	draw_arc(knob, knob_r, 0.0, TAU, 32, RIM, 3.0, true)


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
