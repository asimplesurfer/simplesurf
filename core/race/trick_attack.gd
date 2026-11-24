class_name TrickAttack
extends GameSession
## Modo trucos: hacer la mayor cantidad de puntos con trucos antes de que se
## termine el tiempo (cuenta para abajo; por defecto 2 minutos).
##
## - Los trucos dan puntos, no nitro (no hay turbo). La motivación sí queda
##   (derrapar y tirar al de atrás te da velocidad), y completar un truco
##   también la da.
## - Más combo vale más que proporcional (ver `points_for`). Aterrizaje limpio:
##   todo; justo: menos (TIGHT_MULT). Si te caés, perdés los puntos de ese salto.
## - Al terminar: el puntaje y los mejores del mapa (con ese tiempo).
## - Olas: de distintos tamaños a la vez (chicas, medianas y gigantes), que
##   nacen alrededor y van para cualquier lado: hay que buscarlas. Sin techo
##   invisible en los saltos.
## - Cada LIP_EVERY segundos, una ola de borde (larga y alta): si llegás a la
##   cresta desde atrás, te lleva por el borde con un minijuego de equilibrio
##   (ver el estado `lip`). Es un truco exótico (ver ExoticTrick: puntos
##   mientras se hace, música que sube, bonus y motivación al completarlo; si te
##   caés, te quedás con lo juntado). Dura hasta el final de la cresta.
##
## Por ahora se juega solo (J1). Pensado para después: bots y otros jugadores
## (un puntaje por surfista: `scores` ya va por surfista), el clima que cambia
## durante la partida.

signal countdown_tick(value: int)
signal started
## Sumó puntos (gained) con un truco; total es lo que lleva.
signal scored(rider: Rider, gained: int, total: int, clean: bool)
## Salió una ola de borde (el HUD avisa).
signal lip_wave_spawned(wave: Swell)
## Se terminó el tiempo. rank: puesto entre los mejores (-1 = no entró).
signal finished(score: int, rank: int)

enum State { COUNTDOWN, PLAYING, FINISHED }

## Puntos por cada tiempo de truco (×1). Ver `points_for`.
const BASE_POINTS := 100
## Aterrizaje justo: esta parte de los puntos.
const TIGHT_MULT := 0.5
const COUNTDOWN_TIME := 3.0
## Olas de borde: con LIP_ANY_WAVE, toda ola de LIP_MIN_HEIGHT m o más (por
## ahora 0: todas) se engancha si se llega a su cresta desde atrás (y dura lo
## que le queda de cresta, o de vida). Si no da para recorrerla LIP_MIN_TIME
## segundos, lanza por arriba. Con LIP_SPECIAL_WAVES, además sale cada
## LIP_EVERY segundos una ola de borde especial (larga, con rocío). Por ahora:
## todas, sin la especial (para probar cómo queda).
const LIP_ANY_WAVE := true
const LIP_SPECIAL_WAVES := false
const LIP_MIN_HEIGHT := 0.0
## Hace falta poder recorrerla al menos esto (s) para engancharse.
const LIP_MIN_TIME := 1.5
## Ola de borde: la primera a los LIP_FIRST segundos, después cada LIP_EVERY.
const LIP_FIRST := 10.0
const LIP_EVERY := 20.0
## Para probar: una flecha en el borde de la pantalla apunta a la ola de borde
## (y un cartel cuando sale). La idea es sacarla: con el rocío de la cresta
## (LipWaveSpray) ya se tiene que reconocer.
const SHOW_LIP_POINTER := true
## Tubos: una ola de TUBE_MIN_HEIGHT m o más, después de TUBE_AFTER segundos
## entera, rompe en tubo de a poco, como una ola de verdad: el punto de rotura
## corre por la cresta (PEEL_SPEED) desde una punta hasta la otra, con el tubo
## abierto detrás (BARREL_LEN) y la ola que se cae más atrás (ver
## Swell.peel_w). Pasando por debajo del labio se entra (estado `barrel`): es
## un truco exótico (ver ExoticTrick).
const TUBE_MIN_HEIGHT := 10.0
const TUBE_AFTER := 6.0
const PEEL_SPEED := 10.0
const BARREL_LEN := 28.0
## Cuánto tarda en empezar a romper (s: el labio crece de a poco) y en
## deshacerse al final.
const BARREL_START := 1.0
const TUBE_FADE := 2.5
## Concentración: yendo hacia una ola más o menos en línea recta (a menos de
## FOCUS_RANGE m; hacia algún punto de su cresta, sin desviarse más de
## FOCUS_ANGLE rad), se va cargando: al segundo (FOCUS_DELAY) la velocidad
## empieza a subir y en FOCUS_RAMP segundos llega al doble (Rider.focus y
## FOCUS_SPEED_MULT); con ella aparecen las rayas de velocidad y la cámara se
## aleja. Hasta FOCUS_STRICT_AT (×1,5) hay tolerancia: moverse apenas para
## los costados no la corta (solo girar más de FOCUS_STEER). Desde ahí, solo
## se mantiene yendo totalmente recto (girar más de FOCUS_STEER_STRICT la
## corta). Al cortarse se descarga de a poco (FOCUS_DRAIN veces más rápido de
## lo que carga), no de golpe.
const FOCUS_RANGE := 220.0
const FOCUS_ANGLE := 0.6
const FOCUS_STEER := 0.85
const FOCUS_STEER_STRICT := 0.06
const FOCUS_STRICT_AT := 0.5
const FOCUS_DELAY := 1.0
const FOCUS_RAMP := 4.0
const FOCUS_DRAIN := 2.5
## Para engancharse: en la parte de atrás de la ola, cerca de la cresta (esta
## parte de la altura, o más) y a no más de LIP_CATCH_HEIGHT m del agua.
const LIP_CATCH_UP := 0.7
## Hasta dónde de la cara de adelante engancha (veces el ancho de la ola):
## llegando de costado por la cara, al tocar la espuma de arriba.
const LIP_CATCH_FRONT := 0.35
const LIP_CATCH_HEIGHT := 2.0
## Récords: los mejores TOP puntajes de cada mapa y duración.
const SAVE_PATH := "user://trucos.cfg"
const TOP := 3

@export var world_path: NodePath

var state: State = State.COUNTDOWN
## Segundos que quedan (cuenta para abajo).
var time_left: float = 120.0
## Puntos de cada surfista.
var scores: Dictionary = {}
## Mejores puntajes del mapa con esta duración (al terminar, ya con el nuevo).
var top: Array = []
var world: Node3D
var _countdown: float = COUNTDOWN_TIME
var _last_tick: int = -1
var waves: WaveManager
var water: Water
## La ola de borde de ahora (null si no hay) y cuánto falta para la próxima.
var lip_wave: Swell = null
var _lip_timer: float = LIP_FIRST
## Puntos del borde que todavía no llegan a uno entero (por surfista).
## Trucos exóticos (ver ExoticTrick): puntos que todavía no llegan a uno
## entero (por surfista).
var _exotic_points: Dictionary = {}
## Una ola gigante empieza a romper en tubo (el HUD avisa).
signal barrel_started(wave: Swell)
## La ola que está rompiendo en tubo (null si no hay).
var barrel_wave: Swell = null
## Concentración: cuánto hace que va derecho hacia una ola (por surfista).
var _focus_time: Dictionary = {}
## Empezó la concentración (el HUD avisa).
signal focus_started(rider: Rider)


func default_config() -> RaceConfig:
	return RaceConfig.tricks()


func config_for_players() -> RaceConfig:
	return RaceConfig.tricks()


func _ready() -> void:
	world = get_node_or_null(world_path) as Node3D
	_setup_input()
	time_left = float(config.trick_seconds)
	top = top_scores(map_id(), config.trick_seconds)
	var tw := world as TrickWorld
	var n := config.slots.size()
	for i in n:
		var spot: Array = tw.spawn_point(i, n) if tw else [Vector3(i * 6.0, 0.0, 0.0), 0.0]
		var r := spawn_rider(config.slots[i], spot[0], spot[1], &"riding")
		scores[r] = 0
		r.controls_locked = true
		r.trick_landed.connect(_on_trick_landed.bind(r))
		r.exotic_finished.connect(_on_exotic_finished.bind(r))
		r.lip_exited.connect(_on_lip_exited.bind(r))
	water = get_parent().get_node_or_null("Water") as Water
	waves = get_parent().get_node_or_null("WaveManager") as WaveManager
	if waves:
		waves.set_mode(GameSettings.WaveMode.SURGES)
		waves.trick_mode = true
		# Los tamaños son los del modo trucos (TRICK_SIZES), sin escalar.
		waves.set_amplitude_scale(1.0, true)
	DayTime.apply(get_parent(), config.time_of_day)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.race_started()
		audio.connect_race(self)


## Sin nitro (los trucos dan puntos), sin techo invisible en los saltos, y
## las olas lanzan según su tamaño (también pasándolas por arriba desde atrás).
func _before_add(rider: Rider) -> void:
	rider.nitro_enabled = false
	rider.air_ceiling = false
	rider.wave_sized_launch = true


## Nombre interno del mapa (para los récords).
func map_id() -> String:
	return String(TrickWorld.map_for(config.trick_map).id)




## Puntos de un salto con `spins` tiempos de truco: cada tiempo vale más que
## el anterior (×1 = 100, ×2 = 300, ×3 = 600, ×5 = 1500, ×10 = 5500). Con
## aterrizaje justo, la mitad.
static func points_for(spins: int, clean: bool) -> int:
	if spins <= 0:
		return 0
	var p := BASE_POINTS * spins * (spins + 1) / 2
	return p if clean else roundi(p * TIGHT_MULT)


func score_of(rider: Rider) -> int:
	return int(scores.get(rider, 0))


func _on_trick_landed(spins: int, rider: Rider) -> void:
	if state != State.PLAYING:
		return
	var clean := rider.last_landing_clean
	# Completar un truco (sin caerse) da motivación: un rato más rápido.
	rider.trigger_motivation()
	var gained := points_for(spins, clean)
	scores[rider] = score_of(rider) + gained
	scored.emit(rider, gained, score_of(rider), clean)


## En pasos fijos: la cuenta regresiva y el reloj, igual con cualquier FPS.
func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown -= delta
			var tick := ceili(_countdown)
			if tick != _last_tick and tick > 0:
				_last_tick = tick
				countdown_tick.emit(tick)
			if _countdown <= 0.0:
				start()
		State.PLAYING:
			time_left = maxf(time_left - delta, 0.0)
			_update_exotic(delta)
			_update_lip(delta)
			_update_tubes(delta)
			for r in racers:
				_update_focus(r, delta)
			if time_left <= 0.0:
				finish()


## Ola de borde: sale cada LIP_EVERY segundos (si no hay otra), engancha a
## quien llega a su cresta desde atrás y da puntos mientras lo lleva.
func _update_lip(delta: float) -> void:
	if lip_wave and (lip_wave.is_dead() or water == null or not water.swells.has(lip_wave)):
		lip_wave = null
	_lip_timer -= delta
	if LIP_SPECIAL_WAVES and _lip_timer <= 0.0:
		_lip_timer = LIP_EVERY
		var people := humans()
		if lip_wave == null and waves and not people.is_empty():
			var p := people[0].global_position
			lip_wave = waves.spawn_lip_wave(Vector2(p.x, p.z))
			if lip_wave == null:
				# No hubo lugar: prueba de nuevo enseguida.
				_lip_timer = 1.0
			else:
				add_lip_spray(lip_wave)
				lip_wave_spawned.emit(lip_wave)
	for r in racers:
		if r.on_lip():
			continue
		elif lip_wave and try_catch_lip(r, lip_wave):
			pass
		elif LIP_ANY_WAVE and water:
			for s in water.swells:
				if try_catch_lip(r, s):
					break


## El rocío de la cresta, para reconocer la ola de borde (ver LipWaveSpray).
func add_lip_spray(wave: Swell) -> LipWaveSpray:
	var spray := LipWaveSpray.new()
	spray.name = "LipSpray"
	spray.add_to_group("lip_spray")
	get_parent().add_child(spray)
	spray.setup(wave, water)
	return spray


## Tubos: una ola gigante que ya lleva un rato entera rompe en tubo (una a la
## vez). Mientras rompe, el que pasa por debajo del labio entra. Cuando la
## rotura llega a la otra punta, la ola se deshace.
func _update_tubes(delta: float) -> void:
	if water == null:
		return
	if barrel_wave != null:
		if not water.swells.has(barrel_wave):
			barrel_wave = null
			return
		barrel_wave.curl = move_toward(barrel_wave.curl, 1.0, delta / BARREL_START)
		for r in racers:
			try_enter_barrel(r)
		# Ya rompió toda: se deshace (si nadie sigue adentro).
		var done_at := barrel_wave.half_length + Swell.BARREL_THROAT
		var someone := false
		for r in racers:
			if r.barrel_wave == barrel_wave:
				someone = true
		if barrel_wave.peel_w * barrel_wave.peel_dir > done_at and not someone:
			barrel_wave.keep = false
			barrel_wave.fade_time = TUBE_FADE
			barrel_wave.retire()
			barrel_wave = null
		return
	for sw in water.swells:
		if ready_for_tube(sw):
			start_barrel(sw)
			return


## Entrar al tubo: el que anda por el piso de adentro, debajo del labio (pasó
## por el hueco de adelante, o la rotura le pasó por encima).
func try_enter_barrel(r: Rider) -> bool:
	var s := barrel_wave
	if s == null or s.curl < 0.9 or r.in_tube() or r.on_lip():
		return false
	if r.is_fallen() or not r.grounded or r.controls_locked:
		return false
	var uw := s.local_coords(Vector2(r.position.x, r.position.z))
	var rel := (uw.y - s.peel_w) * s.peel_dir
	if rel < -s.barrel_len + 2.0 or rel > 1.0:
		return false
	# Que todavía quede tubo por recorrer.
	if s.peel_w * s.peel_dir + rel > s.half_length - s.edge - 8.0:
		return false
	if not water.under_roof(r.position.x, r.position.z, r.position.y):
		return false
	r.barrel_wave = s
	r.state_machine.transition_to(&"barrel")
	return true


## true si la ola ya puede romper en tubo.
func ready_for_tube(s: Swell) -> bool:
	return (
		s.max_amplitude >= TUBE_MIN_HEIGHT
		and not s.keep
		and not s.lip_used
		and s.age >= s.grow_time + TUBE_AFTER
		and s.amplitude >= s.max_amplitude * 0.95
		and s.breaking >= 1.0
		and s.lifetime - s.age > s.fade_time + 1.0
	)


## Empieza a romper en tubo: la rotura arranca en una punta y va hacia el lado
## donde está el surfista (así el tubo le llega). Dura lo que tarda en
## recorrer la ola.
func start_barrel(s: Swell) -> void:
	barrel_wave = s
	s.keep = true
	s.lip_used = true
	s.curl = 0.01
	s.peel_speed = PEEL_SPEED
	s.barrel_len = BARREL_LEN
	var side := 1.0
	var near := INF
	for r in racers:
		var p := Vector2(r.position.x, r.position.z)
		var d := p.distance_to(s.center)
		if d < near:
			near = d
			var w := s.local_coords(p).y
			side = signf(w) if absf(w) > 1.0 else 1.0
	s.peel_dir = side
	s.peel_w = -side * (s.half_length - s.edge * 0.5)
	var travel := 2.0 * s.half_length + Swell.BARREL_THROAT + BARREL_LEN + Swell.BARREL_COLLAPSE
	s.lifetime = maxf(s.lifetime, s.age + travel / PEEL_SPEED + s.fade_time + 2.0)
	# La espuma que salta donde cae el labio y en la garganta.
	var spray := BarrelSpray.new()
	spray.name = "BarrelSpray"
	get_parent().add_child(spray)
	spray.setup(s, water)
	barrel_started.emit(s)


## Dónde está el bolsillo del tubo (adonde ir), en el mundo.
func barrel_pocket() -> Vector3:
	var s := barrel_wave
	var perp := Vector2(-s.direction.y, s.direction.x)
	var w := s.peel_w - 7.0 * s.peel_dir
	var p := s.center + s.direction * (1.4 * s.max_amplitude) + perp * w
	return Vector3(p.x, s.max_amplitude * 0.5, p.y)


## Concentración: si va derecho hacia una ola, la velocidad sube de a poco.
func _update_focus(r: Rider, delta: float) -> void:
	var t: float = _focus_time.get(r, 0.0)
	if heading_to_wave(r):
		var was := t
		t = minf(t + delta, FOCUS_DELAY + FOCUS_RAMP)
		if was < FOCUS_DELAY and t >= FOCUS_DELAY:
			focus_started.emit(r)
	else:
		t = maxf(t - delta * FOCUS_DRAIN, 0.0)
	r.focus = clampf((t - FOCUS_DELAY) / FOCUS_RAMP, 0.0, 1.0)
	_focus_time[r] = t


## Concentración cargada (0..1): 0,5 = recién empieza a subir la velocidad,
## 1 = al máximo. Para el HUD.
func focus_charge(r: Rider) -> float:
	return clampf(float(_focus_time.get(r, 0.0)) / (FOCUS_DELAY + FOCUS_RAMP), 0.0, 1.0)


## true si va andando (parado en la tabla, sin girar mucho) derecho hacia la
## cresta de una ola cercana.
func heading_to_wave(r: Rider) -> bool:
	if water == null or not r.grounded or r.is_fallen() or r.on_lip() or r.in_tube() or r.controls_locked:
		return false
	var max_steer := FOCUS_STEER_STRICT if r.focus >= FOCUS_STRICT_AT else FOCUS_STEER
	if absf(r.steer_amount) > max_steer or r.speed < 4.0:
		return false
	var p := Vector2(r.position.x, r.position.z)
	var f := Vector2(r.forward().x, r.forward().z)
	for s in water.swells:
		if s.amplitude < s.max_amplitude * 0.6:
			continue
		# El punto de la cresta más cerca.
		var perp := Vector2(-s.direction.y, s.direction.x)
		var crest := s.center + s.direction * s.crest_u()
		var along := clampf((p - crest).dot(perp), -s.half_length + s.edge, s.half_length - s.edge)
		var to := crest + perp * along - p
		var d := to.length()
		if d < 6.0 or d > FOCUS_RANGE:
			continue
		if f.dot(to / d) > cos(FOCUS_ANGLE):
			return true
	return false


## Si `r` llegó a la cresta de la ola de borde desde atrás, la ola lo engancha.
func try_catch_lip(r: Rider, s: Swell) -> bool:
	if s.lip_used or r.is_fallen() or r.in_tube() or r.on_lip() or r.trick_angle > 0.0 or water == null:
		return false
	if s.amplitude < s.max_amplitude * 0.8:
		return false
	# Las chicas no (esas lanzan); la ola de borde especial, siempre.
	if not s.lip and s.max_amplitude < LIP_MIN_HEIGHT:
		return false
	var p := Vector2(r.position.x, r.position.z)
	var uw := s.local_coords(p)
	# Tocando la espuma de la cresta: un poco atrás o un poco adelante de lo
	# más alto (la ola avanza hacia +u), y no en las puntas.
	var from_crest := uw.x - s.crest_u()
	if from_crest > s.width * LIP_CATCH_FRONT or from_crest < -s.width * 0.8 or absf(uw.y) > s.half_length - s.edge - 4.0:
		return false
	# Desde atrás o de costado (no de frente contra la ola: ahí quiere saltar).
	var f := r.forward()
	if Vector2(f.x, f.z).dot(s.direction) < -0.3:
		return false
	# Que se pueda recorrer un rato.
	var lip_state := preload("res://core/rider/states/state_lip.gd")
	var side: float = lip_state.choose_side(s, uw.y, f)
	if lip_state.ride_time_for(s, uw.y, side) < LIP_MIN_TIME:
		return false
	if s.height_at(p) < s.amplitude * LIP_CATCH_UP:
		return false
	if r.position.y - water.height_at(p.x, p.y) > LIP_CATCH_HEIGHT:
		return false
	s.lip_used = true
	s.keep = true
	r.lip_wave = s
	r.state_machine.transition_to(&"lip")
	return true


## Salió de la ola de borde: ya no hay ola de borde (la sacó él).
func _on_lip_exited(_success: bool, rider: Rider) -> void:
	if lip_wave and rider.lip_wave == lip_wave:
		lip_wave = null


## Trucos exóticos (ver ExoticTrick): mientras se hacen, se juntan puntos.
func _update_exotic(delta: float) -> void:
	for r in racers:
		if r.exotic == ExoticTrick.Kind.NONE:
			continue
		var acc: float = float(_exotic_points.get(r, 0.0)) + ExoticTrick.points_per_sec(r.exotic) * delta
		var whole := int(acc)
		_exotic_points[r] = acc - whole
		scores[r] = score_of(r) + whole


## Terminó un truco exótico: si lo completó, el bonus (si se cayó, se queda
## con lo que juntó). La motivación la da el surfista (Rider.finish_exotic).
func _on_exotic_finished(kind: ExoticTrick.Kind, success: bool, rider: Rider) -> void:
	_exotic_points[rider] = 0.0
	if not success or state != State.PLAYING:
		return
	var b := ExoticTrick.bonus(kind)
	scores[rider] = score_of(rider) + b
	scored.emit(rider, b, score_of(rider), true)


## Arranca (termina la cuenta regresiva).
func start() -> void:
	if state != State.COUNTDOWN:
		return
	state = State.PLAYING
	for r in racers:
		r.controls_locked = false
	countdown_tick.emit(0)
	started.emit()


## Se terminó el tiempo: todos quietos, se guarda el puntaje.
func finish() -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	time_left = 0.0
	for r in racers:
		r.controls_locked = true
	var people := humans()
	var score := score_of(people[0]) if not people.is_empty() else 0
	var rank := save_score(map_id(), config.trick_seconds, score)
	top = top_scores(map_id(), config.trick_seconds)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play("finish", -1.0)
	finished.emit(score, rank)


# ---------------------------------------------------------------- récords

static func _key(id: String, seconds: int) -> String:
	return "%s_%d" % [id, seconds]


## Los mejores puntajes de un mapa con esa duración (de mayor a menor).
static func top_scores(id: String, seconds: int) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return []
	var list: Variant = cfg.get_value("top", _key(id, seconds), [])
	return (list as Array).duplicate() if list is Array else []


## Guarda un puntaje. Devuelve su puesto entre los mejores (-1 si no entró).
static func save_score(id: String, seconds: int, score: int) -> int:
	if score <= 0:
		return -1
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var list: Array = top_scores(id, seconds)
	var rank := list.size()
	for i in list.size():
		if score > int(list[i]):
			rank = i
			break
	if rank >= TOP:
		return -1
	list.insert(rank, score)
	list.resize(mini(list.size(), TOP))
	cfg.set_value("top", _key(id, seconds), list)
	cfg.save(SAVE_PATH)
	return rank


## El puntaje con separador de miles (12.400).
static func format_score(score: int) -> String:
	var s := str(absi(score))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if score < 0 else "") + s + out


## El reloj en minutos y segundos (1:05). Redondea para arriba: muestra 0:00
## recién cuando se terminó.
static func format_clock(t: float) -> String:
	var s := ceili(maxf(t, 0.0) - 0.0001)
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- teclas

## Teclas: la pausa y el FPS, como en carrera; al terminar, R / Start: otra
## vez y C: al menú. (Sin teclas de prueba: el visor de trucos o la cámara
## lenta harían trampa; tampoco cambiar la cantidad de jugadores, por ahora.)
func _handle_common_key(key: InputEventKey) -> bool:
	if state == State.FINISHED:
		match key.physical_keycode:
			KEY_R, KEY_ENTER, KEY_KP_ENTER:
				restart()
				return true
			KEY_C:
				back_to_menu()
				return true
	return super(key)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		_handle_common_key(key)
		return
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if InputMap.has_action(p + "start") and event.is_action_pressed(p + "start"):
			if state == State.FINISHED:
				restart()
			else:
				toggle_pause()
			return
