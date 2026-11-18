class_name TrackMinimap
extends Control
## Minimapa (vista desde arriba, igual que en el editor de mapas: x a la
## derecha, z hacia abajo): la pista como un camino celeste con borde blanco,
## la largada a cuadros, un punto por rival y una flechita amarilla para este
## jugador (apunta hacia donde va).
##
## La pone la HUD arriba a la derecha. Sin pista (el modo libre en mar
## abierto) no se ve.

const LINE := Color(1, 1, 1, 0.95)
const SHADOW := Color(0, 0, 0, 0.32)
const ROAD := Color(0.45, 0.82, 0.98, 0.85)
const ME := Color(1.0, 0.85, 0.3)
const OTHERS := Color(1, 1, 1, 0.95)
const INK := Color(0.05, 0.13, 0.2)

## La HUD que lo tiene (de ahí salen el jugador y la partida).
var hud: Hud
var _course: Course
## La pista ya pasada a coordenadas del minimapa.
var _line := PackedVector2Array()
var _scale: float = 1.0
var _offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Todo queda adentro del recuadro.
	clip_contents = true


func _process(_delta: float) -> void:
	if _course == null or not is_instance_valid(_course):
		_course = GameSession.find_in_scene(self, &"course") as Course
		_line.clear()
		if _course == null or _course.track == null:
			visible = false
			return
	if _line.is_empty() or size != _last_size:
		_fit()
	visible = not _line.is_empty()
	queue_redraw()


var _last_size := Vector2.ZERO


## Pasa la pista a coordenadas del minimapa (centrada, sin deformar).
func _fit() -> void:
	_last_size = size
	var track := _course.track
	var pts := PackedVector2Array()
	if track is PathTrack:
		var src := (track as PathTrack).points
		var step := maxi(src.size() / 200, 1)
		for i in range(0, src.size(), step):
			pts.append(src[i])
	else:
		for i in 96:
			var q := track.position_at(-PI + TAU * i / 96.0)
			pts.append(Vector2(q.x, q.z))
	if pts.size() < 3:
		_line.clear()
		return
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := 16.0
	var span := (hi - lo).max(Vector2.ONE)
	_scale = minf((size.x - pad * 2.0) / span.x, (size.y - pad * 2.0) / span.y)
	_offset = size * 0.5 - (lo + hi) * 0.5 * _scale
	_line = PackedVector2Array()
	for p in pts:
		_line.append(p * _scale + _offset)
	_line.append(_line[0])


func _to_map(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z) * _scale + _offset


func _draw() -> void:
	if _line.size() < 3:
		return
	# La pista: sombra, borde blanco y el camino celeste adentro.
	var w := clampf(_course.track.half_width * 2.0 * _scale, 5.0, 9.0)
	var shadow := PackedVector2Array()
	for p in _line:
		shadow.append(p + Vector2(0.0, 2.0))
	draw_polyline(shadow, SHADOW, w + 5.0, true)
	draw_polyline(_line, LINE, w + 3.0, true)
	draw_polyline(_line, ROAD, w, true)
	# Largada: una franjita a cuadros cruzando la pista.
	var track := _course.track
	var a := _to_map(track.position_at(0.0, -track.half_width * 1.6))
	var b := _to_map(track.position_at(0.0, track.half_width * 1.6))
	var across := (b - a)
	var along := across.orthogonal().normalized() * 2.2
	var cells := 6
	draw_line(a, b, INK, 6.5, true)
	for k in cells:
		var p0 := a + across * (float(k) / cells)
		var p1 := a + across * (float(k + 1) / cells)
		for side in [-1.0, 1.0]:
			var white := (k + (1 if side > 0.0 else 0)) % 2 == 0
			var quad := PackedVector2Array([p0, p1, p1 + along * side, p0 + along * side])
			draw_colored_polygon(quad, Color.WHITE if white else INK)
	# Rivales: puntos blancos con borde.
	var me: Rider = hud.rider if hud else null
	var session := hud.session if hud else null
	if session:
		for r in session.racers:
			if r != me and is_instance_valid(r):
				var p := _to_map(r.position)
				draw_circle(p + Vector2(0.0, 1.0), 5.0, SHADOW)
				draw_circle(p, 4.4, INK)
				draw_circle(p, 3.2, OTHERS)
	# Este jugador: una flechita que apunta hacia donde va, con un pulso suave.
	if me and is_instance_valid(me):
		var p := _to_map(me.position)
		var f3 := me.forward()
		var f := Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.01 else Vector2.UP
		var side := f.orthogonal()
		var t := Time.get_ticks_msec() * 0.001
		var ring := 9.0 + 3.0 * fposmod(t * 1.2, 1.0)
		draw_arc(p, ring, 0.0, TAU, 28, Color(ME.r, ME.g, ME.b, 0.6 * (1.0 - fposmod(t * 1.2, 1.0))), 1.6, true)
		var tip := p + f * 8.0
		var back := p - f * 5.0
		var arrow := PackedVector2Array([tip, back + side * 5.5, p - f * 2.0, back - side * 5.5])
		var outline := PackedVector2Array()
		for q in arrow:
			outline.append(p + (q - p) * 1.35)
		draw_colored_polygon(outline, INK)
		draw_colored_polygon(arrow, ME)
