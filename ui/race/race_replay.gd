class_name RaceReplay
extends Control
## Repetición de la carrera en el minimapa (arriba de los resultados): la
## carrera entera en unos segundos, cada corredor con su color y la estela de
## por dónde fue, y arriba quién iba primero en cada momento. Se repite sola.
##
## Sale del registro de la carrera (RaceRecorder): posición y puesto de cada
## uno, 10 veces por segundo.

## Lo que dura la repetición (s) y la pausa al final antes de empezar de nuevo.
const PLAY_TIME := 8.0
const HOLD_TIME := 1.6
## Cuántos segundos de carrera deja de estela cada uno.
const TRAIL_SECONDS := 6.0

const LINE := Color(1, 1, 1, 0.9)
const ROAD := Color(0.45, 0.82, 0.98, 0.55)
const INK := Color(0.05, 0.13, 0.2)
const SHADOW := Color(0, 0, 0, 0.32)
## Colores de los corredores (los pastel del juego; ver COLORES.md). Las
## personas van primero, en amarillo.
const ME := Color(1.0, 0.85, 0.3)
const COLORS: Array[Color] = [
	Color(0.45, 0.9, 1.0),
	Color(0.5, 1.0, 0.5),
	Color(1.0, 0.6, 0.2),
	Color(1.0, 0.62, 0.93),
	Color(1.0, 0.32, 0.3),
	Color(1.0, 1.0, 1.0),
	Color(0.75, 0.6, 1.0),
]

var _course: Course
var _names: Array[String] = []
var _colors: Array[Color] = []
## Por corredor, sus posiciones (x, z) en el minimapa; y el puesto en cada muestra.
var _paths: Array[PackedVector2Array] = []
var _places: Array[PackedInt32Array] = []
var _times := PackedFloat32Array()
var _line := PackedVector2Array()
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## Arma la repetición con lo que grabó `recorder` hasta ahora.
func setup(race: RaceManager) -> void:
	_course = race.course
	_names.clear()
	_colors.clear()
	_paths.clear()
	_places.clear()
	_times = PackedFloat32Array()
	var human_color := 0
	var other := 0
	for r in race.racers:
		_names.append(r.display_name)
		if r.is_human:
			_colors.append(ME if human_color == 0 else COLORS[(COLORS.size() - human_color) % COLORS.size()])
			human_color += 1
		else:
			_colors.append(COLORS[other % COLORS.size()])
			other += 1
		_paths.append(PackedVector2Array())
		_places.append(PackedInt32Array())
	var x_at := RaceRecorder.RIDER_FIELDS.find("x")
	var z_at := RaceRecorder.RIDER_FIELDS.find("z")
	var place_at := RaceRecorder.RIDER_FIELDS.find("place")
	if race.recorder:
		for sample in race.recorder._samples:
			_times.append(float(sample[0]))
			var rows: Array = sample[1]
			for i in mini(rows.size(), _paths.size()):
				var row: Array = rows[i]
				_paths[i].append(Vector2(float(row[x_at]), float(row[z_at])))
				_places[i].append(int(row[place_at]))
	_t = 0.0
	_fit()
	queue_redraw()


func sample_count() -> int:
	return _times.size()


func _process(delta: float) -> void:
	if _times.size() < 2:
		return
	_t = fmod(_t + delta, PLAY_TIME + HOLD_TIME)
	queue_redraw()


## Pista y recorridos pasados a coordenadas del recuadro (centrados, sin deformar).
var _scale: float = 1.0
var _offset := Vector2.ZERO


func _fit() -> void:
	_line = PackedVector2Array()
	if _course == null or _course.track == null:
		return
	var track := _course.track
	var pts := PackedVector2Array()
	for i in 160:
		var q := track.position_at(-PI + TAU * i / 160.0)
		pts.append(Vector2(q.x, q.z))
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var box := size if size.x > 10.0 else custom_minimum_size
	var top := 30.0
	var pad := 14.0
	var span := (hi - lo).max(Vector2.ONE)
	_scale = minf((box.x - pad * 2.0) / span.x, (box.y - top - pad * 2.0) / span.y)
	_offset = Vector2(box.x * 0.5, top + (box.y - top) * 0.5) - (lo + hi) * 0.5 * _scale
	for p in pts:
		_line.append(p * _scale + _offset)
	_line.append(_line[0])


func _resized_fit() -> void:
	if _course:
		_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_resized_fit()


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.17, 0.3, 0.9)
	bg.set_corner_radius_all(12)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	if _line.size() < 3:
		return
	var w := clampf(_course.track.half_width * 2.0 * _scale, 4.0, 10.0)
	draw_polyline(_line, LINE, w + 3.0, true)
	draw_polyline(_line, ROAD, w, true)
	var n := _times.size()
	if n < 2:
		return
	# Hasta qué muestra va la repetición.
	var k := clampf(_t / PLAY_TIME, 0.0, 1.0) * (n - 1)
	var i := int(k)
	var trail := int(TRAIL_SECONDS * 10.0)
	var font := get_theme_default_font()
	for r in _paths.size():
		var path := _paths[r]
		if path.size() < 2:
			continue
		var col := _colors[r]
		var from := maxi(0, i - trail)
		var pts := PackedVector2Array()
		for j in range(from, mini(i, path.size() - 1) + 1):
			pts.append(path[j] * _scale + _offset)
		var head := path[mini(i, path.size() - 1)].lerp(path[mini(i + 1, path.size() - 1)], k - i) * _scale + _offset
		pts.append(head)
		if pts.size() >= 2:
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.6), 2.5, true)
		draw_circle(head + Vector2(0.0, 1.0), 5.5, SHADOW)
		draw_circle(head, 5.0, INK)
		draw_circle(head, 3.8, col)
	# Arriba: quién va primero en este momento.
	var leader := -1
	for r in _places.size():
		if _places[r].size() > i and _places[r][i] == 1:
			leader = r
	if leader >= 0:
		var text := "Va 1º: %s" % _names[leader]
		var pos := Vector2(12.0, 22.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 18, 5, INK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 18, _colors[leader])
	# El tiempo de carrera que se está viendo.
	var t_text := ResultsPanel.format_time(_times[i])
	var tw := font.get_string_size(t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string_outline(font, Vector2(size.x - tw - 12.0, 22.0), t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, INK)
	draw_string(font, Vector2(size.x - tw - 12.0, 22.0), t_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


## El color de cada corredor (para la lista de resultados).
func color_of(index: int) -> Color:
	return _colors[index] if index < _colors.size() else Color.WHITE
