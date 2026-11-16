class_name Rider
extends Node3D
## El surfista. Guarda posición, rumbo, velocidad y nitro, y delega el
## comportamiento en la máquina de estados (riding, drifting, airborne, fallen).
## No sabe quién lo controla: pide un RiderInput a su Controller cada frame.
##
## Por ahora se mueve libre sobre el plano (x, z). Cuando exista la isla,
## esto pasa a coordenadas de pista (progress + lateral) con TrackSpace.

signal fell
signal stood_up
signal mash_pressed
signal mash_progress_changed(value: float, stage: RecoveryStage)
signal recovery_stage_changed(stage: RecoveryStage)
signal jumped
signal landed
signal trick_landed(spins: int)
signal trick_failed
signal nitro_changed(value: float, max_value: float)
signal drift_started(side: int)
signal drift_ended
signal drift_hit(victim: Rider)
## Otro surfista lo chocó (strength: 0..1, sale despedido hacia `direction`).
signal bumped(direction: Vector3, strength: float)
## Chocó a otro surfista.
signal bumped_other(victim: Rider)
## Cayó al agua desde un salto alto (strength 0..1): sacudón y salpicón.
signal hard_landed(strength: float)
signal motivation_started
## Atravesó una ola que estaba rompiendo (para la animación, el chapuzón y la cámara).
signal wave_punched
signal turbo_fired
## Apretó turbo y no salió (ya hay una ráfaga en curso, o no tiene carga).
signal turbo_blocked
signal popped
signal ring_collected
signal crashed
## Un géiser lo lanzó al aire.
signal geyser_launched
## Cambió la cantidad de vueltas del truco en curso (en el aire).
signal live_spins_changed(spins: int)

## En qué punto de la recuperación está: en el agua, acostado sobre la tabla o parado.
enum RecoveryStage { IN_WATER, PRONE, STANDING }

const NITRO_MAX := 1.0
## La barra de nitro tiene 3 cargas: cada toque de turbo gasta una.
const TURBO_CHARGES := 3
const TURBO_CHARGE := NITRO_MAX / TURBO_CHARGES

@export var player_index: int = 0
@export var stats: RiderStats
## Nombre que se muestra (J1, J2, Bot...).
@export var display_name: String = "J1"
## true si lo controla una persona (los bots no cuentan para el volumen épico, etc.).
@export var is_human: bool = true

## Rumbo en radianes (rotación alrededor de Y). 0 = mirando hacia -Z.
var heading: float = 0.0
var speed: float = 0.0
var vertical_speed: float = 0.0
## true si está apoyado en el agua (no en el aire).
var grounded: bool = true
## Giro aplicado este frame (-1..1), para que la parte visual se incline.
var steer_amount: float = 0.0
var recovery_stage: RecoveryStage = RecoveryStage.STANDING
var water_normal: Vector3 = Vector3.UP
var nitro: float = 0.0
## Carga del salto (0..1) mientras se mantiene ESPACIO en el agua.
var jump_charge: float = 0.0
## Avance del truco en curso (radianes): cada TAU es un "tiempo" de truco
## (TAU / trick_spin_speed segundos). El contador (x1, x2...) y el nitro van
## por tiempo: los trucos largos suman más.
var trick_angle: float = 0.0
## Trucos en el aire: cortos (1 tiempo), medianos (2) y largos (3).
## (Pensados para leerse desde la cámara, que va detrás.)
enum Trick {
	SPIN, KICKFLIP, TRE_FLIP, VARIAL,
	HELICOPTER, BARREL_ROLL, SPIN_FLIP, OVERBOARD,
	HEADSPIN, WINDMILL,
	BACKFLIP, SUPERMAN,
}
## Nombre de cada truco (para el visor de trucos, tecla G).
const TRICK_NAMES: Array[String] = [
	"Giro de tabla", "Kickflip", "360 flip", "Varial",
	"Helicóptero", "Vuelta de costado", "Giro con flip", "Fuera de la tabla",
	"Giro de cabeza", "Molino",
	"Mortal hacia atrás", "Superman",
]
## Velocidad del juego mientras se mira un truco con el visor (cámara lenta).
const TRICK_PREVIEW_TIME_SCALE := 0.35
## Visor de trucos: salta solo y hace este truco, en cámara lenta.
var trick_preview: bool = false
signal trick_preview_started(trick_name: String, index: int, total: int)
## Cuántos tiempos dura cada truco.
const TRICK_UNITS: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 2, 2]
## Trucos del salto actual, en orden (se eligen al empezar cada uno).
var trick_kinds: Array[int] = []
## Ya eligió su primer truco de la partida.
var _did_first_trick: bool = false
## Primeros trucos que ya eligieron los demás surfistas (para no repetirlos).
static var _first_tricks_taken: Array[int] = []
## Tiempos de truco ya completos en este salto (lo lleva el estado del aire).
var trick_units_done: int = 0
## Lado del derrape: -1 izquierda, 1 derecha, 0 sin derrapar.
var drift_side: int = 0
## Entrada del frame actual (la leen los estados al entrar).
var input: RiderInput = RiderInput.new()
## Si es true, el Rider ignora los controles (cuenta regresiva, por ejemplo).
var controls_locked: bool = false
## Tiempo que le queda al mini sprint automático (motivación).
var motivation_timer: float = 0.0
## Empujón de un choque (m/s, de costado): lo desvía y se va apagando.
var shove := Vector3.ZERO
## Choques recientes con cada surfista (para no contar el mismo dos veces).
var _bump_cooldown: Dictionary = {}
## Distancia entre dos surfistas para que se choquen (m).
const BUMP_RADIUS := 1.1
## Del empujón: cuánto se lleva el chocado y cuánto el que choca (casi nada).
const BUMP_VICTIM := 1.15
const BUMP_HITTER := 0.12
## Desde esta velocidad de caída (m/s) el aterrizaje es "fuerte".
const HARD_LAND_SPEED := 11.0
## El empujón se apaga a este ritmo (m/s²).
const SHOVE_DECEL := 7.0
## Cuánto gira (rad) el chocado hacia donde lo empujan, con un choque fuerte.
const BUMP_TURN := 0.5
## true mientras el turbo está empujando (para efectos visuales).
var turbo_active: bool = false
## true cuando ya cruzó la meta (festeja).
var race_finished: bool = false
## Modo olas: tiempo que queda del A apretado subiendo la ola (para el pop).
var pop_buffer: float = 0.0
## Tiempo desde que una ola lo lanzó (-1 si no fue una ola).
var wave_air_time: float = -1.0
## Velocidad hacia arriba con la que lo lanzó la ola (para el pop tardío).
var launch_speed: float = 0.0
## Si ya hizo el pop en este salto.
var did_pop: bool = false
## Si en este salto se puede hacer truco (en el saltito no: no daría el tiempo).
var can_trick: bool = true
## Handicap (0..1): cuánto ayuda el juego por ir atrás. Lo calcula RaceManager.
var catchup: float = 0.0
var water: Water
## Modo libre: sin aceleración automática; quieto o lento, rema acostado.
var free_ride: bool = false
## Vueltas del truco en curso (para el contador del HUD); 0 si no está girando.
var live_spins: int = 0:
	set(value):
		if value != live_spins:
			live_spins = value
			live_spins_changed.emit(value)

## Tiempo que le queda a la ráfaga de turbo en curso (s).
var turbo_time: float = 0.0
## Para no repetir el "atravesar la ola" seguido.
var _punch_cooldown: float = 0.0
## Apretó A fuera de tiempo en esta ola: ya no hay pop hasta la próxima.
var pop_locked: bool = false
## Tiene una pantalla propia que lo sigue (jugador, o bot en la demo).
var has_view: bool = false
## Para repartir entre cuadros el chequeo de los bots sin pantalla.
var _punch_tick: int = 0
## Bots sin pantalla: el chapuzón se revisa cada tantos cuadros (solo se ve
## de lejos en la pantalla de otro).
const PUNCH_CHECK_EVERY_NO_VIEW := 6
## Con pantalla propia, cada tantos cuadros (es la cuenta más cara del juego:
## revisa la malla del agua tal como se dibuja; a 30 por segundo no se nota).
const PUNCH_CHECK_EVERY_VIEW := 2
## Bots sin pantalla: si no hay ninguna persona a esta distancia, ni se revisa
## (nadie ve el chapuzón).
const PUNCH_SEEN_DISTANCE := 60.0
## Tiempo mínimo entre dos chapuzones (s).
const PUNCH_MIN_GAP := 0.3
## La cara estaba adentro de una ola el frame anterior.
var _face_in_wave: bool = false
var _steer_smoothed: float = 0.0

@onready var controller: BaseController = $Controller
@onready var state_machine: RiderStateMachine = $StateMachine
@onready var visual: RiderVisual = $Visual


func _ready() -> void:
	add_to_group("riders")
	if stats == null:
		stats = RiderStats.new()
	water = GameSession.find_in_scene(self, "water") as Water
	heading = rotation.y
	position.y = water_height()
	# Remar acostado (modo libre).
	var paddling := RiderState.new()
	paddling.set_script(preload("res://core/rider/states/state_paddling.gd"))
	paddling.name = "Paddling"
	state_machine.add_child(paddling)
	visual.setup(self)
	state_machine.setup(self)
	var sounds := RiderAudio.new()
	sounds.name = "Audio"
	add_child(sounds)
	sounds.setup(self)


func _physics_process(delta: float) -> void:
	# La física va en pasos fijos (1/60 s, ver project.godot): la misma altura,
	# velocidad y distancia con cualquier cantidad de FPS. Lo visual (animación,
	# cámara, HUD) se dibuja en _process y solo lee este estado.
	input = controller.get_input(delta)
	if controls_locked:
		input = RiderInput.new()
	motivation_timer = maxf(0.0, motivation_timer - delta)
	if pop_buffer > 0.0:
		pop_buffer = maxf(0.0, pop_buffer - delta)
		# Apretó y la ola no lo lanzó a tiempo: se le pasó el momento.
		if pop_buffer <= 0.0 and grounded:
			pop_locked = true
	# Fuera de las olas grandes se vuelve a poder (para la próxima ola).
	if grounded and pop_locked and not on_big_wave(0.1):
		pop_locked = false
	_punch_cooldown = maxf(0.0, _punch_cooldown - delta)
	# Handicap: nitro de a poco.
	if catchup > 0.0 and not controls_locked:
		add_nitro(stats.catchup_nitro_trickle * catchup * delta)
	_top_up_first_charge(delta)
	# Turbo en ráfagas: cada toque dispara una (mantener no hace nada).
	turbo_time = maxf(0.0, turbo_time - delta)
	if input.turbo_pressed and not is_fallen() and not fire_turbo():
		turbo_blocked.emit()
	if wave_air_time >= 0.0:
		wave_air_time += delta
	turbo_active = false
	state_machine.update(delta, input)
	_bump_riders()
	if shove != Vector3.ZERO:
		position += shove * delta
		shove = shove.move_toward(Vector3.ZERO, SHOVE_DECEL * delta)
	rotation.y = heading
	_check_wave_punch()


## Elige el próximo truco del salto: al azar entre los que duran como mucho
## `max_units` tiempos (los que llegan a terminarse antes de caer), nunca el
## mismo que el anterior. Devuelve false si no entra ninguno.
func choose_next_trick(max_units: int) -> bool:
	var options: Array[int] = []
	var last: int = trick_kinds[-1] if not trick_kinds.is_empty() else -1
	for k in Trick.size():
		if TRICK_UNITS[k] <= max_units and k != last:
			options.append(k)
	if options.is_empty():
		return false
	if not _did_first_trick:
		# El primer truco de cada surfista es distinto del primero de los demás
		# (si no, en la largada saltan todos juntos y pueden hacer el mismo).
		var fresh := options.filter(func(k: int) -> bool: return not k in _first_tricks_taken)
		if fresh.is_empty():
			_first_tricks_taken.clear()
		else:
			options.assign(fresh)
	var pick: int = options[randi() % options.size()]
	if not _did_first_trick:
		_did_first_trick = true
		_first_tricks_taken.append(pick)
	trick_kinds.append(pick)
	return true


## Tiempos de truco hechos en este salto, contando el que está en curso.
func trick_units_now() -> float:
	return trick_units_done + trick_angle / TAU


## Truco que cubre el tiempo `u` del salto: [índice, tiempo de inicio, largo].
## Índice -1 si todavía no se eligió ninguno para ese momento.
func trick_at(u: float) -> Array:
	var start := 0
	for i in trick_kinds.size():
		var units: int = TRICK_UNITS[trick_kinds[i]]
		if u < start + units - 0.0001:
			return [i, start, units]
		start += units
	return [-1, start, 0]


## Visor de trucos: salta bien alto y hace el truco `kind` solo, en cámara
## lenta, para mirarlo con calma. Al aterrizar todo vuelve a la normalidad.
func preview_trick(kind: int) -> void:
	if is_fallen():
		return
	var unit_time := TAU / stats.trick_spin_speed
	# Aire suficiente para el truco y un margen (sin el freno del aire fino).
	var air := TRICK_UNITS[kind] * unit_time + stats.trick_hold_delay + 0.5
	position.y = water_height() + 0.3
	vertical_speed = stats.gravity * air * 0.5
	grounded = false
	can_trick = true
	did_pop = false
	wave_air_time = -1.0
	# Primero el estado (al salir de uno se apaga el visor), después el visor.
	state_machine.transition_to(&"airborne")
	trick_preview = true
	trick_kinds.assign([kind])
	trick_units_done = 0
	Engine.time_scale = TRICK_PREVIEW_TIME_SCALE
	trick_preview_started.emit(TRICK_NAMES[kind], kind, Trick.size())


## Termina el visor de trucos (al aterrizar o caerse).
func end_trick_preview() -> void:
	if trick_preview:
		trick_preview = false
		Engine.time_scale = 1.0


## Truco en curso (-1 si no está haciendo ninguno).
func current_trick() -> int:
	if trick_angle <= 0.0:
		return -1
	var t := trick_at(trick_units_now())
	return trick_kinds[t[0]] if t[0] >= 0 else -1


## Cuánto va del truco en curso (0..1).
func current_trick_phase() -> float:
	var u := trick_units_now()
	var t := trick_at(u)
	if t[0] < 0:
		return 0.0
	return clampf((u - float(t[1])) / float(t[2]), 0.0, 1.0)


## trick_angle en el que termina el truco en curso (el giro se completa hasta ahí).
func trick_end_angle() -> float:
	var t := trick_at(trick_units_now())
	if t[0] < 0:
		return ceilf(trick_angle / TAU - 0.001) * TAU
	return float(t[1] + t[2] - trick_units_done) * TAU


## Choques entre surfistas: si dos se tocan, el que va hacia el otro lo empuja
## (más fuerte cuanto más rápido lo choca) y casi no se desvía. El chocado sale
## despedido hacia el otro lado y gira para ese lado (su cámara también), pero
## no se cae. Cada par lo resuelve uno solo de los dos (el de id más chico).
func _bump_riders() -> void:
	for k in _bump_cooldown.keys():
		_bump_cooldown[k] = float(_bump_cooldown[k]) - get_physics_process_delta_time()
		if _bump_cooldown[k] <= 0.0:
			_bump_cooldown.erase(k)
	if is_fallen():
		return
	for node in get_tree().get_nodes_in_group("riders"):
		var other := node as Rider
		if other == null or other == self or other.is_fallen() or other.get_instance_id() < get_instance_id():
			continue
		# Solo los de la misma partida (en los tests puede haber varias abiertas).
		if other.water != water:
			continue
		var rel := other.position - position
		if absf(rel.y) > 1.6:
			continue
		rel.y = 0.0
		var dist := rel.length()
		if dist >= BUMP_RADIUS or dist < 0.001:
			continue
		var n := rel / dist
		# Se separan (sin quedar uno adentro del otro).
		var overlap := BUMP_RADIUS - dist
		position -= n * overlap * 0.5
		other.position += n * overlap * 0.5
		var va := forward() * speed + shove
		var vb := other.forward() * other.speed + other.shove
		var closing := (va - vb).dot(n)
		if closing < 0.6 or _bump_cooldown.has(other) or other._bump_cooldown.has(self):
			continue
		_bump_cooldown[other] = 0.45
		# El que más va hacia el otro es el que choca.
		var a_in := va.dot(n)
		var b_in := -vb.dot(n)
		if a_in >= b_in:
			_shove_pair(self, other, n, closing)
		else:
			_shove_pair(other, self, -n, closing)


static func _shove_pair(hitter: Rider, victim: Rider, n: Vector3, closing: float) -> void:
	victim.shove += n * closing * BUMP_VICTIM
	hitter.shove -= n * closing * BUMP_HITTER
	# El chocado gira hacia donde sale despedido (si lo chocan de la derecha,
	# hacia la izquierda).
	var strength := clampf(closing / 10.0, 0.0, 1.0)
	var side := signf(n.dot(victim.right()))
	victim.heading -= side * BUMP_TURN * strength
	victim.bumped.emit(n, strength)
	hitter.bumped_other.emit(victim)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


func move_forward(delta: float) -> void:
	position += forward() * speed * delta


## Gira con algo de inercia; cuesta más girar a poca velocidad.
func apply_steer(amount: float, delta: float, factor: float = 1.0) -> void:
	_steer_smoothed = move_toward(_steer_smoothed, amount, stats.steer_response * delta)
	steer_amount = _steer_smoothed * factor
	var speed_factor := clampf(0.35 + speed / stats.max_speed, 0.35, 1.0)
	heading -= _steer_smoothed * stats.turn_speed * factor * speed_factor * delta


func reset_steer() -> void:
	_steer_smoothed = 0.0
	steer_amount = 0.0


## Steer suavizado actual (-1..1).
func current_steer() -> float:
	return _steer_smoothed


## Acelera / frena según el acelerador. El turbo (si hay nitro) y la
## motivación suben la velocidad máxima.
func apply_throttle(throttle: float, delta: float, turbo: bool = false) -> void:
	var top := stats.max_speed * speed_mult()
	var target := top * maxf(throttle, 0.0)
	var rate := stats.acceleration
	if motivation_timer > 0.0:
		target = maxf(target, top * stats.motivation_speed_mult)
		rate *= 2.0
	if turbo_request(turbo):
		turbo_active = true
		target = maxf(target, top * stats.turbo_speed_mult)
		rate = stats.acceleration * stats.turbo_accel_mult
	if speed > target:
		rate = stats.brake_decel if throttle < -0.1 else stats.coast_decel
	speed = move_toward(speed, target, rate * delta)


## true mientras hay una ráfaga de turbo en curso.
func turbo_request(_pressed: bool = false) -> bool:
	return turbo_time > 0.0


## Cargas de turbo completas que tiene (0..3).
func turbo_charges() -> int:
	return int(floor((nitro + 0.0001) / TURBO_CHARGE))


## Dispara una ráfaga de turbo si tiene una carga. Mientras dura una ráfaga no
## se puede disparar otra (no gasta cargas de más). Devuelve true si salió.
func fire_turbo() -> bool:
	if turbo_charges() < 1 or turbo_time > 0.0:
		return false
	add_nitro(-TURBO_CHARGE)
	turbo_time = stats.turbo_burst_time
	turbo_fired.emit()
	return true


## Mini sprint automático tras pasar por un círculo o tirar a alguien.
func trigger_motivation() -> void:
	if motivation_timer <= 0.0:
		motivation_started.emit()
	motivation_timer = stats.motivation_time


## Un géiser explota abajo: sale volando hacia arriba (puede hacer trucos).
func geyser_launch(speed: float) -> void:
	if is_fallen() or not grounded:
		return
	position.y += 0.2
	vertical_speed = maxf(vertical_speed, speed)
	grounded = false
	can_trick = true
	did_pop = false
	wave_air_time = 0.0
	state_machine.transition_to(&"airborne")
	geyser_launched.emit()


## Choque (roca, isla): se cae y queda en `safe_position`, fuera del obstáculo.
func crash(safe_position: Vector3) -> void:
	position.x = safe_position.x
	position.z = safe_position.z
	speed = minf(speed, 3.0)
	crashed.emit()
	if not is_fallen():
		fall()


func water_height() -> float:
	if water == null:
		return 0.0
	return water.height_at(position.x, position.z)


## Pega al Rider a la superficie. Devuelve true si la ola lo lanzó al aire:
## pasa cuando la superficie "se cae" más rápido que la gravedad (al pasar la
## cresta con velocidad). Cuanto más rápido sube, más alto sale.
func stick_to_water(delta: float, allow_launch: bool = true) -> bool:
	var h := water_height()
	var ballistic_y := position.y + vertical_speed * delta - 0.5 * stats.gravity * delta * delta
	# Solo las olas grandes lanzan; las olitas de fondo son decorado.
	if (
		allow_launch
		and vertical_speed > stats.min_launch_speed
		and ballistic_y > h
		and on_big_wave(0.3)
	):
		position.y = ballistic_y
		var boost := stats.wave_launch_boost * jump_mult()
		if turbo_active:
			boost *= stats.turbo_launch_mult
		vertical_speed = (vertical_speed - stats.gravity * delta) * boost
		launch_speed = vertical_speed
		jump_charge = 0.0
		grounded = false
		wave_air_time = 0.0
		did_pop = false
		can_trick = true
		if pop_buffer > 0.0:
			do_pop()
		return true
	vertical_speed = clampf((h - position.y) / delta, -30.0, 30.0)
	position.y = h
	grounded = true
	if water:
		water_normal = water.normal_at(position.x, position.z)
	return false


## Salta con la fuerza que indica jump_charge (0 = toque, 1 = cargado al máximo).
## En el modo "tocar para saltar" la altura es fija.
func jump() -> void:
	var jump_speed := lerpf(stats.jump_speed_min, stats.jump_speed_max, jump_charge)
	if GameSettings.jump_mode == GameSettings.JumpMode.TAP:
		jump_speed = stats.jump_speed_tap
	vertical_speed = maxf(vertical_speed, 0.0) + jump_speed * jump_mult()
	jump_charge = 0.0
	grounded = false
	can_trick = true
	jumped.emit()


## "Atraviesa la ola" (animación y chapuzón) cuando la cara del modelo entra al
## agua de una ola grande tal como se dibuja (no los pies ni el cuerpo), de pie
## o en el aire. Caído o nadando no cuenta.
func _check_wave_punch() -> void:
	if water == null or visual == null:
		return
	_punch_tick += 1
	var every := PUNCH_CHECK_EVERY_VIEW if has_view else PUNCH_CHECK_EVERY_NO_VIEW
	if (_punch_tick + get_instance_id()) % every != 0:
		return
	if not has_view and not _someone_watching():
		_face_in_wave = false
		return
	# Solo atravesando una ola grande de pie o en el aire: caerse al agua o
	# nadar no cuenta (aunque la cabeza se moje).
	if is_fallen():
		_face_in_wave = false
		return
	var face := visual.face_position()
	var inside := water.face_in_wave(face) and water.big_wave_near(face)
	# Cada vez que la cara entra al agua (un mínimo de tiempo entre una y otra
	# para que el borde de la superficie no lo dispare a cada cuadro).
	if inside and not _face_in_wave and _punch_cooldown <= 0.0:
		_punch_cooldown = PUNCH_MIN_GAP
		wave_punched.emit()
	_face_in_wave = inside


## true si algún surfista con pantalla propia está cerca (para ver este).
func _someone_watching() -> bool:
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r and r.has_view and r.position.distance_squared_to(position) < PUNCH_SEEN_DISTANCE * PUNCH_SEEN_DISTANCE:
			return true
	return false


## Modo olas: true en el momento justo para el pop (subiendo una ola grande o
## apenas la ola lo lanzó). El HUD muestra el botón.
func pop_ready() -> bool:
	if GameSettings.jump_style != GameSettings.JumpStyle.WAVES or did_pop or is_fallen() or pop_locked:
		return false
	if grounded:
		return (
			on_big_wave(0.8)
			and vertical_speed > stats.pop_min_climb + 1.0
			and pop_buffer <= 0.0
			and crest_soon()
		)
	return wave_air_time >= 0.0 and wave_air_time < stats.pop_coyote


## true si está sobre una ola grande (o la ola constante) de al menos esa altura.
func on_big_wave(min_height: float) -> bool:
	return water != null and water.swell_height_at(position.x, position.z) > min_height


## true si la cresta llega dentro de la ventana del pop: un poco más adelante
## la ola ya casi no sube (o baja).
func crest_soon() -> bool:
	if water == null:
		return false
	var ahead := position + forward() * speed * stats.pop_window
	var rise := water.height_at(ahead.x, ahead.z) - water_height()
	return rise < vertical_speed * stats.pop_window * 0.5


## Segundos hasta tocar el agua si sigue cayendo así (estimado, agua quieta).
func time_to_land() -> float:
	var above := maxf(position.y - water_height(), 0.0)
	return (vertical_speed + sqrt(vertical_speed * vertical_speed + 2.0 * stats.gravity * above)) / stats.gravity


## Modo olas: saltito en agua plana (no alcanza para un truco).
func hop() -> void:
	# Siempre igual de alto (no suma lo que sube la olita de abajo).
	vertical_speed = stats.hop_speed * jump_mult()
	grounded = false
	wave_air_time = -1.0
	did_pop = false
	can_trick = false
	jumped.emit()


## Modo olas: A apretado en una ola grande. Cuenta solo si la cresta está por
## llegar (o recién lo lanzó); si es antes de tiempo, se pierde el pop de esta ola.
func try_pop_press() -> void:
	if pop_locked or did_pop:
		return
	if grounded:
		if crest_soon() and vertical_speed > stats.pop_min_climb:
			pop_buffer = stats.pop_window
		else:
			pop_locked = true
	elif wave_air_time >= 0.0 and wave_air_time < stats.pop_coyote:
		do_pop()
	else:
		pop_locked = true


## Modo olas: apretar A en la ola hace salir mucho más alto.
func do_pop() -> void:
	if did_pop or pop_locked:
		return
	did_pop = true
	pop_buffer = 0.0
	if grounded or wave_air_time < 0.0:
		vertical_speed = pop_speed(maxf(vertical_speed, 0.0))
	else:
		# Pop tardío (coyote time): sale igual que si lo hubiera hecho justo al
		# despegar; solo descuenta lo que ya frenó la gravedad desde entonces.
		var lost := launch_speed - vertical_speed
		vertical_speed = pop_speed(maxf(launch_speed, 0.0)) - lost
	popped.emit()


## Velocidad hacia arriba con pop, saliendo de la ola a `speed`. En los saltos
## que ya son enormes (con turbo) el pop suma menos, hasta un 75 %.
func pop_speed(speed: float) -> float:
	var gain := speed * (stats.pop_mult - 1.0) + stats.pop_extra
	var big := smoothstep(stats.pop_big_from, stats.pop_big_to, speed)
	return speed + gain * lerpf(1.0, stats.pop_big_scale, big)


## Mueve en el aire. Devuelve true cuando toca el agua.
func update_air(delta: float) -> bool:
	vertical_speed -= stats.gravity * delta
	position.y += vertical_speed * delta
	var h := water_height()
	# Toca el agua al bajar. En el saltito, también si una ola lo alcanza
	# desde abajo (así entra a la ola normal, sin trucos raros).
	if position.y <= h and (vertical_speed <= 0.0 or not can_trick):
		position.y = h
		grounded = true
		wave_air_time = -1.0
		pop_locked = false
		var impact := -vertical_speed
		landed.emit()
		if impact > HARD_LAND_SPEED:
			hard_landed.emit(clampf((impact - HARD_LAND_SPEED) / 12.0, 0.15, 1.0))
		return true
	return false


## Multiplicador del nitro que se gana por el handicap.
func nitro_gain_mult() -> float:
	return 1.0 + catchup * (stats.catchup_nitro_mult - 1.0)


## Multiplicador de la velocidad máxima por el handicap.
func speed_mult() -> float:
	return 1.0 + catchup * stats.catchup_speed_bonus


## Radianes que le pueden faltar a un truco al caer para que igual cuente (handicap).
func trick_grace() -> float:
	return catchup * stats.catchup_trick_grace


## Multiplicador de la altura de los saltos por el handicap.
func jump_mult() -> float:
	return 1.0 + catchup * stats.catchup_jump_bonus


## Suma nitro. Lo que se gana se multiplica por el handicap (lo que se gasta no).
func add_nitro(amount: float) -> void:
	if amount > 0.0:
		amount *= nitro_gain_mult()
	nitro = clampf(nitro + amount, 0.0, NITRO_MAX)
	nitro_changed.emit(nitro, NITRO_MAX)


## La primera barra de nitro, pasada cierta parte, se termina de llenar sola
## (solo la primera, y ahí queda): quedarse a nada de poder usar el turbo frustra.
func _top_up_first_charge(delta: float) -> void:
	if controls_locked or is_fallen():
		return
	if nitro >= TURBO_CHARGE * stats.first_charge_autofill and nitro < TURBO_CHARGE:
		nitro = minf(nitro + TURBO_CHARGE * stats.first_charge_fill_rate * delta, TURBO_CHARGE)
		nitro_changed.emit(nitro, NITRO_MAX)


func reset_nitro() -> void:
	nitro = 0.0
	nitro_changed.emit(nitro, NITRO_MAX)


func fall() -> void:
	shove = Vector3.ZERO
	state_machine.transition_to(&"fallen")


func is_fallen() -> bool:
	return state_machine.current_name == &"fallen"


func set_recovery_stage(stage: RecoveryStage) -> void:
	if stage == recovery_stage:
		return
	recovery_stage = stage
	recovery_stage_changed.emit(stage)
