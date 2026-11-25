class_name TrickRecorder
extends Node
## Registro del modo trucos, para analizar después cómo se jugó (ver
## TrickAttack: la tecla L lo descarga como .json, en cualquier momento).
##
## - samples: 10 por segundo, [t, surfistas, cámara, tubo]. Cada surfista: ver
##   RIDER_FIELDS; la cámara: CAMERA_FIELDS; tubo: para la ola grande más cerca,
##   [id de la ola, por qué no engancha el tubo ("" = engancha)].
## - swells: 2 por segundo, [t, olas]. Cada ola: ver SWELL_FIELDS (id: el mismo
##   número toda su vida).
## - events: [t, tipo, datos...] (salto, truco, caída, tubo, borde...).
## - marks: las marcas (tecla Tab). Cada una, numerada desde 1, con todo lo de
##   ese momento: el surfista y la cámara completos, todas las olas con por qué
##   no enganchó el tubo en cada una, el agua donde está, una foto de la
##   pantalla y, a 60 por segundo, los MARK_BEFORE s de antes y MARK_AFTER s
##   de después (surfista y cámara: ver DETAIL_FIELDS).
## - fps: por segundo, [t, fps promedio, cuadro más lento en ms].

const VERSION := 1
## Física a 60 por segundo: muestras cada 6 (10/s); olas cada 30 (2/s).
const SAMPLE_EVERY := 6
const SWELL_EVERY := 30
## Segundos de detalle (a 60/s) antes y después de cada marca.
const MARK_BEFORE := 4.0
const MARK_AFTER := 2.0
## Tamaño de la foto de cada marca (px de ancho).
const SHOT_WIDTH := 480
const RIDER_FIELDS := [
	"x", "y", "z", "speed", "heading", "vy", "state", "grounded", "steer_in", "throttle_in",
	"trick_in", "drift_in", "focus", "water_h", "floor_h", "exotic", "tube_balance", "lip_balance",
]
const CAMERA_FIELDS := ["x", "y", "z", "fwd_x", "fwd_y", "fwd_z", "fov"]
const SWELL_FIELDS := [
	"id", "cx", "cz", "dir_x", "dir_z", "speed", "amplitude", "max_amplitude", "width",
	"half_length", "edge", "breaking", "age", "lifetime", "curl", "peel_w", "peel_dir",
	"peel_from", "barrel_len", "lip_used", "keep", "tube_close", "grown",
]
## Detalle de las marcas: [t, x, y, z, speed, heading, vy, state, grounded,
## steer_in, cam_x, cam_y, cam_z, cam_fwd_x, cam_fwd_y, cam_fwd_z].
const DETAIL_FIELDS := [
	"t", "x", "y", "z", "speed", "heading", "vy", "state", "grounded", "steer_in",
	"cam_x", "cam_y", "cam_z", "cam_fwd_x", "cam_fwd_y", "cam_fwd_z",
]

var session: TrickAttack
var _tick: int = 0
var _time: float = 0.0
var _samples: Array = []
var _swells: Array = []
var _events: Array = []
var _marks: Array = []
var _fps: Array = []
var _fps_acc: float = 0.0
var _fps_frames: int = 0
var _fps_worst: float = 0.0
var _connected: bool = false
## Números de las olas (el mismo toda su vida).
var _ids: Dictionary = {}
var _next_id: int = 1
## Los últimos MARK_BEFORE s a 60/s (para las marcas).
var _recent: Array = []
## Marcas que todavía juntan los MARK_AFTER s de después.
var _open_marks: Array = []


func _physics_process(delta: float) -> void:
	if session == null or session.state == TrickAttack.State.COUNTDOWN:
		return
	if not _connected:
		_connect()
	_time += delta
	_tick += 1
	var me := _human()
	var cam := _camera()
	if me:
		var row := _detail_row(me, cam)
		_recent.append(row)
		while _recent.size() > int(MARK_BEFORE * 60.0):
			_recent.pop_front()
		for m in _open_marks:
			m.after.append(row)
		_open_marks = _open_marks.filter(func(m: Dictionary) -> bool: return m.after.size() < int(MARK_AFTER * 60.0))
	if _tick % SAMPLE_EVERY == 0:
		var riders: Array = []
		for r in session.racers:
			riders.append(_rider_row(r))
		_samples.append([_r(_time), riders, _camera_row(cam), _tube_row(me)])
	if _tick % SWELL_EVERY == 0 and session.water:
		var rows: Array = []
		for s in session.water.swells:
			rows.append(_swell_row(s))
		_swells.append([_r(_time), rows])


func _process(delta: float) -> void:
	if session == null or session.state == TrickAttack.State.COUNTDOWN:
		return
	_fps_acc += delta
	_fps_frames += 1
	_fps_worst = maxf(_fps_worst, delta)
	if _fps_acc >= 1.0:
		_fps.append([_r(_time), _r(_fps_frames / _fps_acc, 10.0), _r(_fps_worst * 1000.0, 10.0)])
		_fps_acc = 0.0
		_fps_frames = 0
		_fps_worst = 0.0


## Cuántas marcas hay.
func mark_count() -> int:
	return _marks.size()


## Marca (tecla Tab): guarda todo lo de este momento. Devuelve la marca (su
## número en "n" y, en "tube", por qué no enganchó el tubo la ola más cerca).
func mark() -> Dictionary:
	var me := _human()
	var cam := _camera()
	var m := {
		"n": _marks.size() + 1,
		"t": _r(_time),
		"clock": _r(session.time_left),
		"state": TrickAttack.State.keys()[session.state],
		"score": session.score_of(me) if me else 0,
		"rider": _rider_full(me) if me else {},
		"camera": _camera_full(cam),
		"water": _water_here(me),
		"swells": [],
		"barrel_wave": _id(session.barrel_wave) if session.barrel_wave else 0,
		"tube": "",
		"before": _recent.duplicate(),
		"after": [],
	}
	var near := _nearest_swell(me)
	var all: Array[Swell] = session.water.swells if session.water else ([] as Array[Swell])
	for s in all:
		var row := _swell_full(s)
		if me:
			var check := session.tube_check(me, s)
			var wave_problem := session.tube_wave_problem(s)
			var why: String = wave_problem if wave_problem != "" else str(check.problem)
			if session.barrel_wave != null and session.barrel_wave != s:
				why = "ya hay otro tubo"
			elif me.barrel_wave == s:
				why = "estás adentro de su tubo"
			row["tube"] = why if why != "" else "engancha"
			row["tube_check"] = _rounded(check)
			if s == near:
				m.tube = "ola de %.1f m: %s" % [s.max_amplitude, row.tube]
		m.swells.append(row)
	if near == null:
		m.tube = "no hay olas cerca"
	m["screenshot_jpg_base64"] = _screenshot()
	_marks.append(m)
	_open_marks.append(m)
	return m


func _human() -> Rider:
	var people := session.humans()
	return people[0] if not people.is_empty() else null


func _camera() -> Camera3D:
	var views := session.get_parent().get_node_or_null("Views") as SplitScreen if session.get_parent() else null
	if views and not views.cameras.is_empty():
		return views.cameras[0]
	return get_viewport().get_camera_3d()


## El id de una ola (el mismo toda su vida).
func _id(s: Swell) -> int:
	if not _ids.has(s):
		_ids[s] = _next_id
		_next_id += 1
	return _ids[s]


## La ola grande (de las que pueden ser tubo) con la cresta más cerca de `r`.
func _nearest_swell(r: Rider) -> Swell:
	if r == null or session.water == null:
		return null
	var p := Vector2(r.position.x, r.position.z)
	var best: Swell = null
	var best_d := 120.0
	for s in session.water.swells:
		if s.max_amplitude < TrickAttack.TUBE_MIN_HEIGHT * 0.6 or s.amplitude <= 0.0:
			continue
		var uw := s.local_coords(p)
		var du := uw.x - s.crest_u()
		var dw := maxf(absf(uw.y) - s.half_length, 0.0)
		var d := Vector2(du, dw).length()
		if d < best_d:
			best_d = d
			best = s
	return best


func _rider_row(r: Rider) -> Array:
	var w := r.water
	var input := r.input if r.input else RiderInput.new()
	return [
		_r(r.position.x), _r(r.position.y), _r(r.position.z), _r(r.speed),
		_r(wrapf(r.heading, -PI, PI), 1000.0), _r(r.vertical_speed), String(r.state_machine.current_name),
		1 if r.grounded else 0, _r(input.steer), _r(input.throttle), 1 if input.trick else 0,
		1 if input.drift else 0, _r(r.focus), _r(w.height_at(r.position.x, r.position.z)) if w else 0.0,
		_r(w.floor_height_at(r.position.x, r.position.z)) if w else 0.0, int(r.exotic),
		_r(r.tube_balance), _r(r.lip_balance),
	]


func _detail_row(r: Rider, cam: Camera3D) -> Array:
	var row := [
		_r(_time), _r(r.position.x), _r(r.position.y), _r(r.position.z), _r(r.speed),
		_r(wrapf(r.heading, -PI, PI), 1000.0), _r(r.vertical_speed), String(r.state_machine.current_name),
		1 if r.grounded else 0, _r(r.input.steer if r.input else 0.0),
	]
	row.append_array(_camera_row(cam).slice(0, 6))
	return row


func _camera_row(cam: Camera3D) -> Array:
	if cam == null:
		return []
	var p := cam.global_position
	var f := -cam.global_basis.z
	return [_r(p.x), _r(p.y), _r(p.z), _r(f.x, 1000.0), _r(f.y, 1000.0), _r(f.z, 1000.0), _r(cam.fov)]


func _tube_row(r: Rider) -> Array:
	var s := _nearest_swell(r)
	if s == null:
		return []
	var why := session.tube_wave_problem(s)
	if why == "":
		why = str(session.tube_check(r, s).problem)
	if session.barrel_wave != null and session.barrel_wave != s:
		why = "ya hay otro tubo"
	elif r.barrel_wave == s:
		why = "estás adentro de su tubo"
	return [_id(s), why]


func _swell_row(s: Swell) -> Array:
	return [
		_id(s), _r(s.center.x), _r(s.center.y), _r(s.direction.x, 1000.0), _r(s.direction.y, 1000.0),
		_r(s.speed), _r(s.amplitude), _r(s.max_amplitude), _r(s.width), _r(s.half_length), _r(s.edge),
		_r(s.breaking), _r(s.age), _r(s.lifetime), _r(s.curl), _r(s.peel_w) if s.curl > 0.0 else 0.0,
		s.peel_dir, _r(s.peel_from) if not is_inf(s.peel_from) else null, _r(s.barrel_len),
		1 if s.lip_used else 0, 1 if s.keep else 0, _r(s.tube_close), _r(s.grown),
	]


func _swell_full(s: Swell) -> Dictionary:
	var out := {}
	var row := _swell_row(s)
	for i in SWELL_FIELDS.size():
		out[SWELL_FIELDS[i]] = row[i]
	out["crest_u"] = _r(s.crest_u())
	out["match_drawn"] = s.match_drawn
	out["lip"] = s.lip
	return out


func _rider_full(r: Rider) -> Dictionary:
	var input := r.input if r.input else RiderInput.new()
	var out := {
		"position": _v3(r.position), "heading": _r(r.heading, 1000.0),
		"forward": _v3(r.forward(), 1000.0), "speed": _r(r.speed), "vy": _r(r.vertical_speed),
		"state": String(r.state_machine.current_name), "grounded": r.grounded,
		"recovery_stage": Rider.RecoveryStage.keys()[r.recovery_stage],
		"controls_locked": r.controls_locked, "in_tube": r.in_tube(), "on_lip": r.on_lip(),
		"exotic": int(r.exotic), "focus": _r(r.focus), "trick_angle": _r(r.trick_angle),
		"steer_amount": _r(r.steer_amount), "water_normal": _v3(r.water_normal, 1000.0),
		"input": {
			"steer": _r(input.steer), "throttle": _r(input.throttle), "trick": input.trick,
			"drift": input.drift, "turbo": input.turbo,
		},
		"tube_balance": _r(r.tube_balance), "lip_balance": _r(r.lip_balance),
	}
	var st := r.state_machine.current
	if st and r.state_machine.current_name == &"barrel":
		out["barrel"] = {
			"rel": _r(float(st.get("rel"))), "balance": _r(float(st.get("balance"))),
			"t_in": _r(float(st.get("_t_in"))), "entry_u": _r(float(st.get("_entry_u"))),
		}
	return out


func _camera_full(cam: Camera3D) -> Dictionary:
	if cam == null:
		return {}
	var out := {
		"position": _v3(cam.global_position), "forward": _v3(-cam.global_basis.z, 1000.0),
		"up": _v3(cam.global_basis.y, 1000.0), "fov": _r(cam.fov),
	}
	var chase := cam as ChaseCamera
	if chase:
		out["looking_back"] = chase.looking_back
		out["boost"] = _r(chase._boost)
		out["ride_y"] = _r(chase._ride_y)
		out["air_k"] = _r(chase._air_k)
	return out


## El agua donde está el surfista: arriba (lo más alto que se dibuja), el
## piso (adentro de un tubo), lo que tiene debajo, si tiene techo encima.
func _water_here(r: Rider) -> Dictionary:
	var w := session.water
	if w == null or r == null:
		return {}
	var x := r.position.x
	var z := r.position.z
	return {
		"time": _r(w.time), "height": _r(w.height_at(x, z)), "floor": _r(w.floor_height_at(x, z)),
		"below": _r(w.height_below(x, z, r.position.y)), "under_roof": w.under_roof(x, z, r.position.y),
		"swell_height": _r(w.swell_height_at(x, z)), "grid_step": _r(w.grid_step()),
	}


## Una foto chica de la pantalla (JPEG en base64; vacía sin pantalla).
func _screenshot() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var tex := get_viewport().get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null or img.is_empty():
		return ""
	var h := maxi(1, int(SHOT_WIDTH * float(img.get_height()) / float(img.get_width())))
	img.resize(SHOT_WIDTH, h, Image.INTERPOLATE_BILINEAR)
	return Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.75))


func _connect() -> void:
	_connected = true
	for r in session.racers:
		r.jumped.connect(func() -> void: _event("jump", [_r(r.speed), _r(r.vertical_speed)]))
		r.popped.connect(func() -> void: _event("pop", [_r(r.speed), _r(r.vertical_speed)]))
		r.landed.connect(func() -> void: _event("land", [_r(r.speed)]))
		r.trick_landed.connect(func(spins: int) -> void: _event("trick_ok", [spins]))
		r.trick_failed.connect(func() -> void: _event("trick_fail", []))
		r.fell.connect(func() -> void: _event("fall", [_r(r.speed)]))
		r.stood_up.connect(func() -> void: _event("stand_up", []))
		r.tube_entered.connect(func() -> void: _event("tube_in", [_id(r.barrel_wave) if r.barrel_wave else 0]))
		r.tube_exited.connect(func(ok: bool) -> void: _event("tube_out", [ok]))
		r.tube_wiped_out.connect(func(lip: bool) -> void: _event("tube_wipeout", ["labio" if lip else "espuma"]))
		r.lip_entered.connect(func() -> void: _event("lip_in", [_id(r.lip_wave) if r.lip_wave else 0]))
		r.lip_exited.connect(func(ok: bool) -> void: _event("lip_out", [ok]))
		r.wave_punched.connect(func() -> void: _event("wave_punch", []))
		r.bumped.connect(func(_d: Vector3, strength: float) -> void: _event("bumped", [_r(strength)]))
	session.barrel_started.connect(func(s: Swell) -> void: _event("barrel_start", [_id(s), _r(s.peel_from), s.peel_dir]))
	session.focus_started.connect(func(_r0: Rider) -> void: _event("focus", []))
	session.scored.connect(func(_r0: Rider, gained: int, total: int, clean: bool) -> void: _event("score", [gained, total, clean]))


func _event(kind: String, data: Array) -> void:
	var row := [_r(_time), kind]
	row.append_array(data)
	_events.append(row)


static func _r(v: float, scale: float = 100.0) -> float:
	return roundf(v * scale) / scale


static func _v3(v: Vector3, scale: float = 100.0) -> Array:
	return [_r(v.x, scale), _r(v.y, scale), _r(v.z, scale)]


## Los números de un diccionario, redondeados (para el .json).
static func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = _r(d[k]) if d[k] is float else d[k]
	return out


## Todo el registro como diccionario (para el .json).
func to_dict() -> Dictionary:
	var me := _human()
	var world := GameSession.find_in_scene(session, &"trick_world") as TrickWorld
	return {
		"version": VERSION,
		"mode": "trucos",
		"build": BuildInfo.BUILD,
		"date": Time.get_datetime_string_from_system(),
		"config": {
			"map": session.map_id(), "seconds": session.config.trick_seconds,
			"tube_min_height": TrickAttack.TUBE_MIN_HEIGHT, "tube_catch_front": TrickAttack.TUBE_CATCH_FRONT,
			"tube_catch_low": TrickAttack.TUBE_CATCH_LOW, "tube_catch_angle": TrickAttack.TUBE_CATCH_ANGLE,
			"tube_room": TrickAttack.TUBE_ROOM, "barrel_start": TrickAttack.BARREL_START,
			"peel_speed": TrickAttack.PEEL_SPEED, "barrel_len": TrickAttack.BARREL_LEN,
		},
		"island_radius": world.island_radius if world else 0.0,
		"rider": me.display_name if me else "",
		"score": session.score_of(me) if me else 0,
		"fields": {
			"rider": RIDER_FIELDS, "camera": CAMERA_FIELDS, "swell": SWELL_FIELDS, "detail": DETAIL_FIELDS,
			"sample": ["t", "riders", "camera", "tube [ola, por qué no engancha]"],
		},
		"marks": _marks,
		"events": _events,
		"samples": _samples,
		"swells": _swells,
		"fps": _fps,
	}


## Nombre del archivo: trucos-AAAA-MM-DD-HHMM.json
func file_name() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "trucos-%04d-%02d-%02d-%02d%02d.json" % [d.year, d.month, d.day, d.hour, d.minute]


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
