class_name LipPointer
extends Control
## Modo trucos (para probar; ver TrickAttack.SHOW_LIP_POINTER): una flecha en
## el borde de la pantalla que apunta hacia la ola de borde cuando no se la
## ve, con la distancia.

const COLOR := Color(1.0, 0.86, 0.2)
const INK := Color(0.05, 0.13, 0.2)
## Distancia de la flecha al borde de la pantalla (px).
const MARGIN := 70.0
const ARROW := 26.0

## Hacia dónde apunta (en la pantalla, normalizado) y a cuántos metros está.
var dir := Vector2.RIGHT
var meters: float = 0.0


## Pone la flecha según dónde queda `target` para la cámara `cam`. Si se ve en
## pantalla, no hay flecha.
func point_to(cam: Camera3D, target: Vector3, from: Vector3) -> void:
	meters = Vector2(target.x - from.x, target.z - from.z).length()
	var local := cam.global_transform.affine_inverse() * target
	var rect := get_viewport_rect().grow(-MARGIN)
	if local.z < 0.0:
		var on_screen := cam.unproject_position(target)
		if rect.has_point(on_screen):
			visible = false
			return
	visible = true
	# La cámara mira hacia -Z: x a la derecha, y hacia arriba (en la pantalla, abajo).
	var d := Vector2(local.x, -local.y)
	if local.z > 0.0 and absf(d.x) < 0.001:
		d.x = 1.0
	if local.z > 0.0:
		# Atrás: apunta para el costado por donde hay que girar.
		d = Vector2(signf(d.x), 0.0)
	dir = d.normalized() if d.length() > 0.001 else Vector2.RIGHT
	queue_redraw()


func _draw() -> void:
	var size_v := get_viewport_rect().size
	var c := size_v * 0.5
	var half := c - Vector2(MARGIN, MARGIN)
	# Donde la dirección toca el rectángulo del borde.
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var tip := c + dir * k
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip + dir * ARROW, tip - dir * ARROW * 0.6 + side * ARROW, tip - dir * ARROW * 0.6 - side * ARROW])
	var outline := PackedVector2Array([tip + dir * (ARROW + 5.0), tip - dir * (ARROW * 0.6 + 4.0) + side * (ARROW + 6.0),
		tip - dir * (ARROW * 0.6 + 4.0) - side * (ARROW + 6.0)])
	draw_colored_polygon(outline, INK)
	draw_colored_polygon(pts, COLOR)
	var font := get_theme_default_font()
	var text := "Ola de borde  %d m" % roundi(meters)
	var fs := 22
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := tip - dir * (ARROW + 34.0) - Vector2(tw * 0.5, -8.0)
	at.x = clampf(at.x, 8.0, size_v.x - tw - 8.0)
	at.y = clampf(at.y, 24.0, size_v.y - 8.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, INK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COLOR)
