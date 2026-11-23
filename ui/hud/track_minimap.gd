class_name TrackMinimap
extends Control
## Minimapa (vista desde arriba, igual que en el editor de mapas: x a la
## derecha, z hacia abajo), minimalista: la pista como una línea blanca finita
## con un contorno oscuro, un punto blanco por rival y uno amarillo para este
## jugador.
##
## La pone la HUD arriba a la derecha. Sin pista (el modo libre en mar
## abierto) no se ve.

const LINE := Color(1, 1, 1)
const OUTLINE := Color(0.05, 0.13, 0.2, 0.6)
const ME := Color(1.0, 0.84, 0.35)
const OTHERS := Color(1, 1, 1)

## La HUD que lo tiene (de ahí salen el jugador y la partida).
var hud: Hud
var _course: Course
## La pista ya pasada a coordenadas del minimapa.
var _line := PackedVector2Array()
## Caminos alternativos (bifurcaciones), en coordenadas del minimapa.
var _branch_lines: Array[PackedVector2Array] = []
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
	var branch_src: Array[PackedVector2Array] = []
	if track is PathTrack:
		for b in (track as PathTrack).branches:
			branch_src.append(b.points)
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	for bl in branch_src:
		for p in bl:
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
	_branch_lines.clear()
	for bl in branch_src:
		var line := PackedVector2Array()
		for i in range(0, bl.size(), maxi(bl.size() / 60, 1)):
			line.append(bl[i] * _scale + _offset)
		line.append(bl[bl.size() - 1] * _scale + _offset)
		_branch_lines.append(line)


func _to_map(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z) * _scale + _offset


func _draw() -> void:
	if _line.size() < 3:
		return
	# La pista: una línea blanca finita con un contorno oscuro (se lee sobre el
	# cielo y el agua claros).
	var lines: Array[PackedVector2Array] = [_line]
	lines.append_array(_branch_lines)
	for line in lines:
		draw_polyline(line, OUTLINE, 4.0, true)
	for line in lines:
		draw_polyline(line, LINE, 1.8, true)
	# Rivales: puntos blancos con borde; este jugador, amarillo y un poco más grande.
	var me: Rider = hud.rider if hud else null
	var session := hud.session if hud else null
	if session:
		for r in session.racers:
			if r != me and is_instance_valid(r):
				var p := _to_map(r.position)
				draw_circle(p, 3.6, OUTLINE)
				draw_circle(p, 2.5, OTHERS)
	if me and is_instance_valid(me):
		var p := _to_map(me.position)
		draw_circle(p, 5.0, OUTLINE)
		draw_circle(p, 3.8, ME)
