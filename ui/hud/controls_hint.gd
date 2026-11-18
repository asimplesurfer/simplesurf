extends Control
## Guía chiquita de controles (abajo a la derecha, arriba del puesto): un ícono
## y qué hace cada botón. Con mando, los botones en rombo con su forma (✕ ○ □);
## con teclado, la tecla. La HUD decide cuándo se ve (ver Hud._update_hint) y
## la desliza hacia la derecha para esconderla.

## true: íconos de mando; false: teclas.
var pad: bool = true:
	set(value):
		if value != pad:
			pad = value
			queue_redraw()

## [botón del mando, tecla, qué hace].
const ROWS := [
	["bottom", "ESPACIO", "Saltar · trucos"],
	["right", "E", "Nitro"],
	["left", "S", "Derrape"],
	["stick", "A  D", "Girar"],
]
const ROW_H := 30.0
const ICON := 28.0
const TEXT_SIZE := 17

const INK := Color(0.05, 0.13, 0.2)
const WHITE := Color(1.0, 1.0, 1.0)
const DIM := Color(1.0, 1.0, 1.0, 0.3)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(230.0, ROW_H * ROWS.size())


func _draw() -> void:
	var font := get_theme_default_font()
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var y := i * ROW_H + ROW_H * 0.5
		# El texto a la izquierda, alineado a la derecha; el ícono al final.
		var icon_w := ICON if pad else maxf(ICON, font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0)
		var icon_c := Vector2(size.x - icon_w * 0.5, y)
		var label: String = row[2]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
		var tp := Vector2(size.x - icon_w - 10.0 - tw, y + font.get_ascent(TEXT_SIZE) * 0.36)
		draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, 5, Color(0.0, 0.0, 0.0, 0.55))
		draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, WHITE)
		if pad:
			_draw_pad(icon_c, row[0])
		else:
			_draw_key(icon_c, icon_w, row[1], font)


## Los cuatro botones en rombo, con el que corresponde lleno y su forma; o el
## stick.
func _draw_pad(c: Vector2, which: String) -> void:
	var r := ICON * 0.5
	if which == "stick":
		draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.35))
		draw_arc(c, r, 0.0, TAU, 28, WHITE, 1.6, true)
		draw_circle(c, r * 0.48, WHITE)
		# Flechitas a los costados (izquierda / derecha).
		for s in [-1.0, 1.0]:
			var tip := c + Vector2(s * r * 0.92, 0.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s * 4.0, -3.5), tip + Vector2(-s * 4.0, 3.5)]), WHITE)
		return
	var offs := {"top": Vector2(0, -1), "right": Vector2(1, 0), "bottom": Vector2(0, 1), "left": Vector2(-1, 0)}
	var d := r * 0.6
	var br := r * 0.38
	for k in offs:
		var p: Vector2 = c + offs[k] * d
		if k == which:
			continue
		draw_circle(p, br * 0.8, DIM)
	# El botón que toca: más grande, blanco, con su forma en oscuro.
	var p: Vector2 = c + offs[which] * d
	var big := br * 1.5
	draw_circle(p, big + 1.5, Color(0.0, 0.0, 0.0, 0.45))
	draw_circle(p, big, WHITE)
	var s := big * 0.5
	match which:
		"bottom":
			draw_line(p + Vector2(-s, -s), p + Vector2(s, s), INK, 1.8, true)
			draw_line(p + Vector2(-s, s), p + Vector2(s, -s), INK, 1.8, true)
		"right":
			draw_arc(p, s * 1.05, 0.0, TAU, 20, INK, 1.6, true)
		"left":
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), INK, false, 1.6)


## Una tecla con su nombre.
func _draw_key(c: Vector2, w: float, text: String, font: Font) -> void:
	var h := ICON
	var rect := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.border_color = WHITE
	box.set_border_width_all(2)
	box.border_width_bottom = 4
	box.set_corner_radius_all(5)
	draw_style_box(box, rect)
	var fs := 13
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - tw * 0.5, c.y + font.get_ascent(fs) * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE)
