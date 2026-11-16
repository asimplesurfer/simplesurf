class_name TrackMinimap
extends Control
## Minimapa: la silueta de la pista en blanco (vista desde arriba, igual que en
## el editor de mapas: x a la derecha, z hacia abajo), la meta y un punto por
## surfista. El de este jugador, más grande y amarillo.
##
## La pone la HUD arriba a la derecha. Sin pista (el modo libre en mar
## abierto) no se ve.

const LINE := Color(1, 1, 1, 0.92)
const SHADOW := Color(0, 0, 0, 0.45)
const ME := Color(1.0, 0.85, 0.2)
const OTHERS := Color(1, 1, 1, 0.85)

## La HUD que lo tiene (de ahí salen el jugador y la partida).
var hud: Hud
var _course: Course
## La pista ya pasada a coordenadas del minimapa.
var _line := PackedVector2Array()
var _scale: float = 1.0
var _offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_END


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
	var pad := 8.0
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
	draw_polyline(_line, SHADOW, 6.0, true)
	draw_polyline(_line, LINE, 3.0, true)
	# Meta: una rayita cruzada en la largada.
	var track := _course.track
	var a := _to_map(track.position_at(0.0, -track.half_width * 1.4))
	var b := _to_map(track.position_at(0.0, track.half_width * 1.4))
	draw_line(a, b, SHADOW, 5.0, true)
	draw_line(a, b, Color(1, 1, 1), 2.5, true)
	# Surfistas: los demás primero, el de este jugador encima.
	var me: Rider = hud.rider if hud else null
	var session := hud.session if hud else null
	if session:
		for r in session.racers:
			if r != me and is_instance_valid(r):
				var p := _to_map(r.position)
				draw_circle(p, 4.0, SHADOW)
				draw_circle(p, 3.0, OTHERS)
	if me and is_instance_valid(me):
		var p := _to_map(me.position)
		draw_circle(p, 7.0, SHADOW)
		draw_circle(p, 5.5, ME)
