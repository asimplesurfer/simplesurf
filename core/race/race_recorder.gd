class_name RaceRecorder
extends Node
## Registro de una carrera para analizarla después (cómo jugó cada uno, cómo
## venían las olas, los FPS). Se descarga al terminar ("Descargar registro" o
## la tecla L) como un archivo .json.
##
## Formato (pensado para que pese poco): arrays con los campos en el orden de
## `fields` del encabezado.
## - samples: cada SAMPLE_EVERY cuadros de física, [t, corredores, olas].
##   Cada corredor: ver RIDER_FIELDS. Cada ola grande: ver SWELL_FIELDS.
## - events: [t, corredor, tipo, datos...] (pop, truco, caída, turbo...).
## - fps: por segundo, [t, fps promedio, cuadro más lento en ms].

## Muestras por segundo: física a 60 / 6 = 10.
const SAMPLE_EVERY := 6
const VERSION := 1
const RIDER_FIELDS := [
	"progress", "lateral", "x", "z", "y", "speed", "heading", "vy", "state", "grounded",
	"nitro", "turbo_active", "steer_in", "throttle_in", "drift_in", "trick_in", "water_h",
	"swell_h", "place", "catchup",
]
const SWELL_FIELDS := [
	"cx", "cz", "dir_x", "dir_z", "speed", "amplitude", "max_amplitude", "width", "half_length",
	"breaking", "age", "lifetime",
]
## Código de estado (state en RIDER_FIELDS).
const STATES := ["riding", "airborne", "drifting", "fallen", "paddling"]

var race: RaceManager
var _tick: int = 0
var _time: float = 0.0
var _samples: Array = []
var _events: Array = []
var _fps: Array = []
var _fps_acc: float = 0.0
var _fps_frames: int = 0
var _fps_worst: float = 0.0
var _fps_t: float = 0.0
var _connected: bool = false


func _physics_process(delta: float) -> void:
	if race == null:
		return
	if not _connected:
		_connect_riders()
	if race.state == RaceManager.State.COUNTDOWN:
		return
	_time += delta
	_tick += 1
	if _tick % SAMPLE_EVERY != 0:
		return
	var riders: Array = []
	var ranking := race.ranking()
	for r in race.racers:
		riders.append(_rider_row(r, ranking.find(r) + 1))
	var swells: Array = []
	var water := race.course._water if race.course else null
	if water:
		for s in water.swells:
			swells.append([
				_r(s.center.x), _r(s.center.y), _r(s.direction.x, 1000.0), _r(s.direction.y, 1000.0),
				_r(s.speed), _r(s.amplitude), _r(s.max_amplitude), _r(s.width), _r(s.half_length),
				_r(s.breaking), _r(s.age), _r(s.lifetime),
			])
	_samples.append([_r(_time), riders, swells])


func _process(delta: float) -> void:
	if race == null or race.state == RaceManager.State.COUNTDOWN:
		return
	_fps_acc += delta
	_fps_frames += 1
	_fps_worst = maxf(_fps_worst, delta)
	if _fps_acc >= 1.0:
		_fps.append([_r(_time), _r(_fps_frames / _fps_acc, 10.0), _r(_fps_worst * 1000.0, 10.0)])
		_fps_acc = 0.0
		_fps_frames = 0
		_fps_worst = 0.0


func _rider_row(r: Rider, place: int) -> Array:
	var loc := race.course.track.locate(r.position)
	var water_h := r.water.height_at(r.position.x, r.position.z) if r.water else 0.0
	var swell_h := r.water.swell_height_at(r.position.x, r.position.z) if r.water else 0.0
	var input := r.input if r.input else RiderInput.new()
	return [
		_r(race.progress_of(r) / TAU, 10000.0), _r(loc.y), _r(r.position.x), _r(r.position.z), _r(r.position.y),
		_r(r.speed), _r(wrapf(r.heading, -PI, PI), 1000.0), _r(r.vertical_speed),
		maxi(STATES.find(String(r.state_machine.current_name)), -1), 1 if r.grounded else 0,
		_r(r.nitro), 1 if r.turbo_active else 0, _r(input.steer), _r(input.throttle),
		1 if input.drift else 0, 1 if input.trick else 0, _r(water_h), _r(swell_h), place, _r(r.catchup),
	]


func _connect_riders() -> void:
	_connected = true
	for i in race.racers.size():
		var r := race.racers[i]
		var k := i
		r.jumped.connect(func() -> void: _event(k, "jump", [_r(r.speed), _r(r.vertical_speed)]))
		r.popped.connect(func() -> void:
			var sh := r.water.swell_height_at(r.position.x, r.position.z) if r.water else 0.0
			_event(k, "pop", [_r(r.speed), _r(r.vertical_speed), _r(sh)])
		)
		r.landed.connect(func() -> void: _event(k, "land", [_r(r.speed)]))
		r.trick_landed.connect(func(spins: int) -> void: _event(k, "trick_ok", [spins, r.trick_kinds.duplicate()]))
		r.trick_failed.connect(func() -> void: _event(k, "trick_fail", [r.trick_kinds.duplicate()]))
		r.crashed.connect(func() -> void: _event(k, "crash", [_r(r.speed)]))
		r.fell.connect(func() -> void: _event(k, "fall", [_r(r.speed)]))
		r.stood_up.connect(func() -> void: _event(k, "stand_up", []))
		r.turbo_fired.connect(func() -> void: _event(k, "turbo", [_r(r.speed), _r(r.nitro)]))
		r.drift_started.connect(func(side: int) -> void: _event(k, "drift", [side, _r(r.speed)]))
		r.drift_hit.connect(func(victim: Rider) -> void: _event(k, "drift_hit", [race.racers.find(victim)]))
		r.ring_collected.connect(func() -> void: _event(k, "ring", []))
		r.wave_punched.connect(func() -> void: _event(k, "wave_punch", []))
		r.geyser_launched.connect(func() -> void: _event(k, "geyser", []))
		r.bumped.connect(func(_d: Vector3, strength: float) -> void: _event(k, "bumped", [_r(strength)]))
	race.lap_started.connect(func(r: Rider, lap: int) -> void: _event(race.racers.find(r), "lap", [lap]))
	race.racer_finished.connect(func(r: Rider, place: int) -> void:
		_event(race.racers.find(r), "finish", [place, _r(race.finish_times.get(r, 0.0))])
	)


func _event(rider_index: int, kind: String, data: Array) -> void:
	if race == null or race.state == RaceManager.State.COUNTDOWN:
		return
	var row := [_r(_time), rider_index, kind]
	row.append_array(data)
	_events.append(row)


static func _r(v: float, scale: float = 100.0) -> float:
	return roundf(v * scale) / scale


## Todo el registro como diccionario (para el .json).
func to_dict() -> Dictionary:
	var racers: Array = []
	for i in race.racers.size():
		var r := race.racers[i]
		var info := {"name": r.display_name, "human": r.is_human, "player": r.player_index}
		if r.controller is AIController:
			info["difficulty"] = (r.controller as AIController).difficulty.display_name
		racers.append(info)
	var course := race.course
	var track := {"half_width": course.half_width, "layout": course.layout, "map": course.map.id}
	if course.track is PathTrack:
		var pts: Array = []
		var src := (course.track as PathTrack).points
		for i in range(0, src.size(), 5):
			pts.append([_r(src[i].x), _r(src[i].y)])
		track["path"] = pts
	else:
		track["center"] = [_r(course.track.center.x), _r(course.track.center.y)]
		track["radius"] = course.track.radius
	var rocks: Array = []
	for rock in course.rocks:
		if is_instance_valid(rock):
			rocks.append([_r(rock.position.x), _r(rock.position.z)])
	var rings: Array = []
	for ring in course.rings:
		if is_instance_valid(ring):
			rings.append([_r(ring.position.x), _r(ring.position.z)])
	var geysers: Array = []
	for g in course.get_tree().get_nodes_in_group("geyser"):
		if course.is_ancestor_of(g):
			geysers.append([_r(g.position.x), _r(g.position.z)])
	return {
		"version": VERSION,
		"date": Time.get_datetime_string_from_system(),
		"config": {
			"laps": race.config.laps, "weather": GameSettings.Weather.keys()[race.config.weather],
			"wave_mode": GameSettings.wave_mode_name(), "layout": course.layout,
		},
		"racers": racers,
		"track": track,
		"rocks": rocks,
		"rings": rings,
		"geysers": geysers,
		"finish_times": _finish_times(),
		"fields": {"rider": RIDER_FIELDS, "swell": SWELL_FIELDS, "states": STATES},
		"samples": _samples,
		"events": _events,
		"fps": _fps,
	}


func _finish_times() -> Dictionary:
	var out := {}
	for r in race.finish_times:
		out[str(race.racers.find(r))] = _r(race.finish_times[r])
	return out


## Nombre del archivo: registro-AAAA-MM-DD-HHMM.json
func file_name() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "registro-%04d-%02d-%02d-%02d%02d.json" % [d.year, d.month, d.day, d.hour, d.minute]


## Descarga el registro (en el navegador baja el archivo; en la compu lo guarda
## en user://registros). Devuelve dónde quedó.
func download() -> String:
	var text := JSON.stringify(to_dict())
	var name := file_name()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), name, "application/json")
		return name
	DirAccess.make_dir_recursive_absolute("user://registros")
	var path := "user://registros/" + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	return ProjectSettings.globalize_path(path)
