class_name CategoryIcon
extends Control
## Ícono minimalista de una categoría del creador de personaje: una silueta
## de un solo color, sin texto (se entiende sin leer).
##   0 estilos (estrella), 1 cuerpo, 2 piel (gota), 3 pelo, 4 cara,
##   5 accesorios (anteojos), 6 short, 7 tabla.

enum Kind { STYLES, BODY, SKIN, HAIR, FACE, ACCESSORIES, SHORTS, BOARD }

var kind: Kind = Kind.STYLES:
	set(value):
		kind = value
		queue_redraw()
var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
## Color de los "huecos" (ojos, boca, rayas): el fondo del botón.
var hole: Color = Color(0.2, 0.25, 0.45):
	set(value):
		hole = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y) * 0.8
	var c := size * 0.5
	match kind:
		Kind.STYLES:
			_star(c, s * 0.5, s * 0.21)
		Kind.BODY:
			_body(c, s)
		Kind.SKIN:
			_drop(c, s)
		Kind.HAIR:
			_hair(c, s)
		Kind.FACE:
			_face(c, s)
		Kind.ACCESSORIES:
			_glasses(c, s)
		Kind.SHORTS:
			_shorts(c, s)
		Kind.BOARD:
			_board(c, s)


func _star(c: Vector2, outer: float, inner: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)


func _body(c: Vector2, s: float) -> void:
	draw_circle(c + Vector2(0.0, -s * 0.32), s * 0.14, color)
	var torso := PackedVector2Array([
		c + Vector2(-s * 0.2, -s * 0.14), c + Vector2(s * 0.2, -s * 0.14),
		c + Vector2(s * 0.14, s * 0.14), c + Vector2(-s * 0.14, s * 0.14),
	])
	draw_colored_polygon(torso, color)
	# Brazos y piernas.
	draw_line(c + Vector2(-s * 0.19, -s * 0.12), c + Vector2(-s * 0.33, s * 0.1), color, s * 0.09, true)
	draw_line(c + Vector2(s * 0.19, -s * 0.12), c + Vector2(s * 0.33, s * 0.1), color, s * 0.09, true)
	draw_line(c + Vector2(-s * 0.08, s * 0.12), c + Vector2(-s * 0.11, s * 0.45), color, s * 0.11, true)
	draw_line(c + Vector2(s * 0.08, s * 0.12), c + Vector2(s * 0.11, s * 0.45), color, s * 0.11, true)


func _drop(c: Vector2, s: float) -> void:
	var r := s * 0.27
	var center := c + Vector2(0.0, s * 0.12)
	draw_circle(center, r, color)
	var tip := PackedVector2Array([
		center + Vector2(-r * 0.92, -r * 0.4), c + Vector2(0.0, -s * 0.45), center + Vector2(r * 0.92, -r * 0.4),
	])
	draw_colored_polygon(tip, color)


func _hair(c: Vector2, s: float) -> void:
	# Melena: una cúpula con flequillo en puntas.
	var pts := PackedVector2Array()
	var r := s * 0.42
	var base := c + Vector2(0.0, s * 0.08)
	for i in 13:
		var a := PI + i * PI / 12.0
		pts.append(base + Vector2(cos(a) * r, sin(a) * r * 0.95))
	var spikes := 5
	for i in spikes + 1:
		var x := r - i * (2.0 * r / spikes)
		pts.append(base + Vector2(x, s * 0.08 if i % 2 == 0 else s * 0.3))
	draw_colored_polygon(pts, color)


func _face(c: Vector2, s: float) -> void:
	draw_circle(c, s * 0.42, color)
	draw_circle(c + Vector2(-s * 0.14, -s * 0.08), s * 0.055, hole)
	draw_circle(c + Vector2(s * 0.14, -s * 0.08), s * 0.055, hole)
	draw_arc(c + Vector2(0.0, s * 0.04), s * 0.2, PI * 0.2, PI * 0.8, 16, hole, s * 0.06, true)


func _glasses(c: Vector2, s: float) -> void:
	var w := s * 0.36
	var h := s * 0.26
	for side in [-1.0, 1.0]:
		var rc := Rect2(c + Vector2(side * s * 0.22 - w * 0.5, -h * 0.5), Vector2(w, h))
		draw_rect(rc, color)
		draw_circle(rc.position + Vector2(w * 0.5, h), w * 0.5, color)
	draw_line(c + Vector2(-s * 0.05, -h * 0.25), c + Vector2(s * 0.05, -h * 0.25), color, s * 0.06, true)
	draw_line(c + Vector2(-s * 0.4, -h * 0.4), c + Vector2(-s * 0.48, -h * 0.55), color, s * 0.05, true)
	draw_line(c + Vector2(s * 0.4, -h * 0.4), c + Vector2(s * 0.48, -h * 0.55), color, s * 0.05, true)


func _shorts(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-s * 0.36, -s * 0.3), c + Vector2(s * 0.36, -s * 0.3),
		c + Vector2(s * 0.44, s * 0.32), c + Vector2(s * 0.08, s * 0.32),
		c + Vector2(0.0, -s * 0.02), c + Vector2(-s * 0.08, s * 0.32),
		c + Vector2(-s * 0.44, s * 0.32),
	])
	draw_colored_polygon(pts, color)
	draw_line(c + Vector2(-s * 0.36, -s * 0.2), c + Vector2(s * 0.36, -s * 0.2), hole, s * 0.04, true)


func _board(c: Vector2, s: float) -> void:
	# Tabla de surf en diagonal, con su raya.
	var pts := PackedVector2Array()
	var length := s * 0.5
	var width := s * 0.15
	var axis := Vector2(1.0, -1.0).normalized()
	var across := Vector2(axis.y, -axis.x)
	for i in 24:
		var a := i * TAU / 24.0
		var along := cos(a)
		# Punta más fina adelante.
		var w := width * sin(a) * (0.75 if along > 0.0 else 1.0)
		pts.append(c + axis * along * length + across * w)
	draw_colored_polygon(pts, color)
	draw_line(c - axis * length * 0.7, c + axis * length * 0.75, hole, s * 0.035, true)
