class_name WaveMinimap
extends Control
## Modo trucos: un minimapa redondo (como un radar), abajo a la izquierda, para
## encontrar las olas que importan:
##   - las grandes (TrickAttack.TUBE_MIN_HEIGHT m o más: las que pueden
##     romper en tubo), como una raya celeste en la cresta con una flechita
##     hacia donde avanzan;
##   - la que está rompiendo en tubo: el hombro todavía entero, el tubo abierto
##     en naranja (titila) y lo que ya se cayó como espuma.
## Las chicas no se dibujan, así se lee de un vistazo.
##
## El surfista va en el medio (flecha amarilla) y el mapa gira con la cámara:
## arriba es hacia donde mira. Una ola fuera del radio (RANGE) deja una marca
## en el borde, del lado donde está. La isla, de arena.

## Metros del centro al borde del mapa.
const RANGE := 110.0
const BG := Color(0.05, 0.13, 0.2, 0.72)
const RIM := Color(1.0, 1.0, 1.0, 0.55)
const INK := Color(0.05, 0.13, 0.2, 0.9)
## Celeste y naranja de COLORES.md.
const BIG := Color(0.45, 0.9, 1.0)
const TUBE := Color(1.0, 0.6, 0.2)
const TUBE_FLASH := Color(1.0, 0.9, 0.5)
const FOAM := Color(1.0, 1.0, 1.0, 0.7)
const ME := Color(1.0, 0.84, 0.35)
const SAND := Color(0.93, 0.85, 0.62)
## Grosor de la cresta (px): ola gigante y tubo abierto.
const CREST := 5.0
const TUBE_CREST := 8.0
## En cuántos tramos se mira la cresta de una ola que rompe en tubo.
const TUBE_SAMPLES := 64

## La HUD que lo tiene (de ahí salen el surfista y la partida).
var hud: Hud
var _t: float = 0.0
## Centro y radio del círculo (px).
var _c := Vector2.ZERO
var _r: float = 1.0
## De metros a píxeles, y hacia dónde mira la cámara (en el plano x, z).
var _px: float = 1.0
var _fwd := Vector2(0.0, -1.0)
var _origin := Vector2.ZERO
var _world: TrickWorld


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Las olas que se dibujan: grandes (pueden romper en tubo) o rompiendo.
static func shows(s: Swell) -> bool:
	return s.curl > 0.0 or s.max_amplitude >= TrickAttack.TUBE_MIN_HEIGHT


## Dónde queda `world` (x, z) visto desde `origin` mirando hacia `fwd`, en
## metros: x a la derecha, y hacia abajo (adelante = y negativo, arriba).
static func map_offset(world: Vector2, origin: Vector2, fwd: Vector2) -> Vector2:
	var d := world - origin
	var right := Vector2(-fwd.y, fwd.x)
	return Vector2(d.dot(right), -d.dot(fwd))


## De un punto del mundo (x, z) al minimapa (px).
func to_map(world: Vector2) -> Vector2:
	return _c + map_offset(world, _origin, _fwd) * _px


func _draw() -> void:
	var tricks := hud.session as TrickAttack if hud else null
	var me: Rider = hud.rider if hud else null
	if tricks == null or me == null or not is_instance_valid(me):
		return
	_c = size * 0.5
	_r = minf(size.x, size.y) * 0.5 - 2.0
	_px = _r / RANGE
	_origin = Vector2(me.global_position.x, me.global_position.z)
	var cam := get_viewport().get_camera_3d()
	var f: Vector3 = -cam.global_basis.z if cam else me.forward()
	if Vector2(f.x, f.z).length() > 0.01:
		_fwd = Vector2(f.x, f.z).normalized()

	draw_circle(_c, _r, BG)
	_draw_island()
	if tricks.water:
		for s in tricks.water.swells:
			if shows(s) and s.amplitude > 0.0:
				_draw_wave(s, tricks)
	draw_arc(_c, _r, 0.0, TAU, 64, RIM, 2.0, true)
	_draw_me(me)


func _draw_island() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = GameSession.find_in_scene(self, &"trick_world") as TrickWorld
	var world := _world
	if world == null or world.outline.size() < 3:
		return
	var at := Vector2(world.global_position.x, world.global_position.z)
	if at.distance_to(_origin) > RANGE + world.island_radius + 2.0:
		return
	var pts := PackedVector2Array()
	for p in world.outline:
		pts.append(to_map(at + p))
	# Recortada al círculo.
	var disk := PackedVector2Array()
	for i in 48:
		disk.append(_c + Vector2.RIGHT.rotated(TAU * i / 48.0) * (_r - 1.0))
	for poly in Geometry2D.intersect_polygons(pts, disk):
		if poly.size() >= 3:
			draw_colored_polygon(poly, SAND)


func _draw_wave(s: Swell, tricks: TrickAttack) -> void:
	var alpha := clampf(s.amplitude / maxf(s.max_amplitude, 0.01), 0.0, 1.0)
	var perp := Vector2(-s.direction.y, s.direction.x)
	var crest := s.center + s.direction * s.crest_u()
	var half := maxf(s.half_length - s.edge * 0.5, 1.0)
	var a := to_map(crest - perp * half)
	var b := to_map(crest + perp * half)
	var col := BIG
	col.a = alpha
	# Todo afuera: una marca en el borde, del lado de la ola.
	var near := crest + perp * clampf(s.local_coords(_origin).y, -half, half)
	if to_map(near).distance_to(_c) > _r:
		_draw_rim_mark(to_map(near), s.curl > 0.0, alpha)
		return
	var ink := INK
	ink.a *= alpha
	if s.curl <= 0.0:
		_segment(a, b, CREST + 3.0, ink)
		_segment(a, b, CREST, col)
		_draw_heading(s, crest, col, ink)
		return
	# Rompiendo en tubo: por tramos a lo ancho (w), según cuánto hace que
	# rompió cada parte (Swell.peel_s; puede romper para los dos lados).
	var tube := _tube_color()
	tube.a = alpha
	var foam := FOAM
	foam.a *= alpha
	var runs := [[], [], []]
	var kind := -1
	var t0 := 0.0
	for i in TUBE_SAMPLES + 1:
		var t := float(i) / TUBE_SAMPLES
		var ps := s.peel_s(-half + 2.0 * half * t)
		var k := 0 if ps > 0.0 else (1 if ps > -s.barrel_len else 2)
		if i == TUBE_SAMPLES or (k != kind and kind >= 0):
			if kind >= 0:
				runs[kind].append(Vector2(t0, t))
			t0 = t
		kind = k
	# Lo que ya se cayó, espuma finita; el hombro (todavía entero) y el tubo
	# abierto, encima.
	for r in runs[2]:
		_part(a, b, r.x, r.y, CREST * 0.6, foam, ink)
	for r in runs[0]:
		_part(a, b, r.x, r.y, CREST, col, ink)
	for r in runs[1]:
		_part(a, b, r.x, r.y, TUBE_CREST, tube, ink)
	_draw_heading(s, crest, col, ink)
	# El cartel, detrás del tubo que sigue el surfista (del lado de donde
	# viene la ola).
	if s == tricks.barrel_wave and not runs[1].is_empty():
		var w_mid := clampf(s.peel_w - s.peel_dir * s.barrel_len * 0.5, -half, half)
		var mid := a.lerp(b, (w_mid + half) / (2.0 * half))
		var back := (to_map(crest - s.direction * 10.0) - to_map(crest)).normalized()
		_label("TUBO", mid + back * 16.0, TUBE)


## Un tramo de la cresta (de t0 a t1, 0..1 de punta a punta), con contorno.
func _part(a: Vector2, b: Vector2, t0: float, t1: float, width: float, col: Color, ink: Color) -> void:
	if absf(t1 - t0) < 0.001:
		return
	var p0 := a.lerp(b, minf(t0, t1))
	var p1 := a.lerp(b, maxf(t0, t1))
	_segment(p0, p1, width + 3.0, ink)
	_segment(p0, p1, width, col)


## Una raya recortada al círculo.
func _segment(p0: Vector2, p1: Vector2, width: float, col: Color) -> void:
	var r := _r - width * 0.5 - 1.0
	var d := p1 - p0
	var f := p0 - _c
	var aa := d.dot(d)
	if aa < 0.0001:
		return
	var bb := 2.0 * f.dot(d)
	var cc := f.dot(f) - r * r
	var disc := bb * bb - 4.0 * aa * cc
	if disc <= 0.0:
		return
	var sq := sqrt(disc)
	var t0 := maxf((-bb - sq) / (2.0 * aa), 0.0)
	var t1 := minf((-bb + sq) / (2.0 * aa), 1.0)
	if t1 <= t0:
		return
	draw_line(p0 + d * t0, p0 + d * t1, col, width, true)


## Flechita delante de la cresta: hacia dónde avanza la ola.
func _draw_heading(s: Swell, crest: Vector2, col: Color, ink: Color) -> void:
	var base := to_map(crest)
	var ahead := to_map(crest + s.direction * 10.0) - base
	if ahead.length() < 0.01:
		return
	var dir := ahead.normalized()
	var tip := base + dir * 11.0
	if tip.distance_to(_c) > _r - 5.0:
		return
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, tip - dir * 6.0 + side * 5.0, tip - dir * 6.0 - side * 5.0])
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), ink, 3.0, true)
	draw_colored_polygon(pts, col)


## Una ola fuera del mapa: un triangulito en el borde, apuntando hacia ella.
func _draw_rim_mark(toward: Vector2, is_tube: bool, alpha: float) -> void:
	var dir := (toward - _c).normalized()
	var tip := _c + dir * (_r + 1.0)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, tip - dir * 9.0 + side * 6.0, tip - dir * 9.0 - side * 6.0])
	var c := _tube_color() if is_tube else BIG
	c.a = alpha
	var ink := INK
	ink.a *= alpha
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), ink, 3.0, true)
	draw_colored_polygon(pts, c)


func _draw_me(me: Rider) -> void:
	var f := me.forward()
	var dir := to_map(_origin + Vector2(f.x, f.z)) - _c
	dir = dir.normalized() if dir.length() > 0.0001 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([_c + dir * 9.0, _c - dir * 6.0 + side * 6.5, _c - dir * 3.0, _c - dir * 6.0 - side * 6.5])
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), INK, 3.5, true)
	draw_colored_polygon(pts, ME)


## El tubo titila entre naranja y amarillo claro (llama la atención sin
## apagarse).
func _tube_color() -> Color:
	return TUBE.lerp(TUBE_FLASH, 0.5 + 0.5 * sin(_t * 9.0))


## Un cartelito centrado en `at` (corrido hacia adentro si toca el borde).
func _label(text: String, at: Vector2, col: Color) -> void:
	var font := get_theme_default_font()
	var fs := 14
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var d := at - _c
	var room := _r - w * 0.5 - 6.0
	if d.length() > room:
		at = _c + d.normalized() * room
	var p := at + Vector2(-w * 0.5, fs * 0.35)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, INK)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
