class_name LipMeter
extends Control
## Modo trucos, ola de borde: la barra de equilibrio (la bolita se va para los
## lados; se la vuelve al medio con el stick) y los segundos que le quedan a la
## ola. Ver el estado `lip`.

const WIDTH := 440.0
const BAR_HEIGHT := 26.0
const SAFE := Color(0.45, 0.95, 0.55)
const WARN := Color(1.0, 0.85, 0.2)
const DANGER := Color(1.0, 0.25, 0.2)
const INK := Color(0.05, 0.13, 0.2)

## -1..1 (en los extremos se cae).
var balance: float = 0.0
## 0..1: qué tan cerca está de caerse.
var danger: float = 0.0
## Segundos que le quedan a la ola.
var time_left: float = 0.0


func _draw() -> void:
	var font := get_theme_default_font()
	var cx := size.x * 0.5
	var bar := Rect2(cx - WIDTH * 0.5, size.y - BAR_HEIGHT - 6.0, WIDTH, BAR_HEIGHT)
	# Los segundos que le quedan a la ola, arriba de la barra.
	var secs := str(ceili(maxf(time_left - 0.0001, 0.0)))
	var fs := 40
	var tw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(cx - tw * 0.5, bar.position.y - 14.0)
	draw_string_outline(font, at, secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, INK)
	draw_string(font, at, secs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# Fondo: verde en el medio, amarillo y rojo hacia los extremos.
	draw_rect(bar.grow(4.0), INK)
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var x := bar.position.x + t0 * bar.size.x
		var off := absf((t0 + 0.5 / steps) * 2.0 - 1.0)
		var col := SAFE.lerp(WARN, smoothstep(0.35, 0.65, off)).lerp(DANGER, smoothstep(0.7, 0.95, off))
		col.a = 0.85
		draw_rect(Rect2(x, bar.position.y, bar.size.x / steps + 0.5, bar.size.y), col)
	# La bolita (el equilibrio).
	var bx := cx + clampf(balance, -1.0, 1.0) * (WIDTH * 0.5 - 12.0)
	var by := bar.position.y + bar.size.y * 0.5
	var r := 15.0 + danger * 4.0
	draw_circle(Vector2(bx, by), r + 3.0, INK)
	draw_circle(Vector2(bx, by), r, Color.WHITE.lerp(DANGER, danger))
