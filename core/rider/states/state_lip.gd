extends RiderState
## En el borde de una ola de borde (modo trucos; ver TrickAttack y
## Swell.lip). Llegó a la cresta desde atrás y la ola lo lleva por el borde:
## avanza a lo largo de la cresta con la tabla en diagonal, raspando (como en
## el derrape), mientras la ola sigue su camino. La cámara sigue detrás, como
## siempre (el rumbo va derecho por la cresta; la diagonal es solo de la tabla).
##
## Minijuego de equilibrio: la ola lo empuja para un lado o el otro y él
## corrige con el stick (izquierda / derecha). Cada vez empuja más fuerte y
## más seguido. Si el equilibrio llega a un extremo, se cae (atrás de la ola).
## Dura lo que le queda de cresta por recorrer (o lo que le falta a la ola
## para disolverse, si es menos): si aguanta hasta el final, sale disparado con
## motivación (y queda en el aire: puede seguir con trucos).
## Al engancharse, un ratito sin empujones (para acomodarse).
const SETTLE_TIME := 1.0
## Cuánto más arriba del agua va la tabla (m): la cresta se dibuja con espuma
## y, pegada al agua, la tabla quedaba tapada.
const RIDE_ABOVE := 0.35
## Velocidad a lo largo de la cresta (m/s).
const SPEED := 12.0
## Empujón de la ola (cuánto corre el equilibrio por segundo): al principio
## suave, al final fuerte.
const PUSH_START := 0.25
const PUSH_END := 0.95
## Inestable: cuanto más corrido, más se corre solo. También crece.
const UNSTABLE_START := 0.2
const UNSTABLE_END := 0.85
## Cuánto corrige el stick al máximo (por segundo): siempre un poco más que
## lo peor que puede hacer la ola, pero al final hay que estar muy atento.
const CONTROL := 2.0
## Cada cuánto cambia el empujón (s): al principio cada tanto, al final seguido.
const PUSH_TIME_START := Vector2(0.9, 1.5)
const PUSH_TIME_END := Vector2(0.3, 0.6)
## Al salir disparado: velocidad hacia arriba (m/s).
const EXIT_UP := 7.0

var wave: Swell
## Lado hacia el que avanza por la cresta (+1 / -1, sobre la perpendicular a
## la dirección de la ola).
var side: float = 1.0
## Dónde está a lo largo de la cresta (m desde el centro de la ola).
var w: float = 0.0
## Equilibrio: 0 en el medio; en -1 o 1 se cae.
var balance: float = 0.0
var ride_time: float = 0.0
## Cuánto dura esta vez (s; ver `ride_time_for`).
var total: float = 1.0
var _push: float = 0.0
var _push_target: float = 0.0
var _push_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func enter(_previous: StringName) -> void:
	wave = rider.lip_wave
	_rng.randomize()
	ride_time = 0.0
	balance = 0.0
	_push = 0.0
	_push_target = 0.0
	_push_timer = SETTLE_TIME
	if wave:
		var p := Vector2(rider.position.x, rider.position.z)
		w = wave.local_coords(p).y
		# Sigue para el lado al que iba (si iba derecho hacia la ola, hacia
		# donde le queda más cresta).
		side = choose_side(wave, w, rider.forward())
		total = maxf(ride_time_for(wave, w, side), 0.5)
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	rider.grounded = true
	rider.vertical_speed = 0.0
	rider.shove = Vector3.ZERO
	rider.turbo_time = 0.0
	rider.reset_steer()
	rider.lip_balance = 0.0
	rider.lip_danger = 0.0
	rider.lip_time_left = total
	rider.lip_progress = 0.0
	rider.lip_entered.emit()


func exit() -> void:
	if wave:
		wave.keep = false
	wave = null
	rider.lip_wave = null
	rider.drift_side = 0
	rider.lip_balance = 0.0
	rider.lip_danger = 0.0
	rider.lip_time_left = 0.0
	rider.lip_progress = 0.0


## Para qué lado sigue por la cresta: para donde iba, si iba claramente para
## un lado; si no, para donde le queda más cresta.
static func choose_side(s: Swell, w_now: float, fwd: Vector3) -> float:
	var perp := Vector2(-s.direction.y, s.direction.x)
	var along := Vector2(fwd.x, fwd.z).dot(perp)
	if absf(along) > 0.4:
		return signf(along)
	return -signf(w_now) if absf(w_now) > 1.0 else 1.0


## Lo que tarda en recorrer lo que le queda de cresta hacia `side_now`, o lo
## que le falta a la ola para empezar a disolverse, lo que sea menos (s).
static func ride_time_for(s: Swell, w_now: float, side_now: float) -> float:
	var limit := maxf(s.half_length - s.edge - 2.0, 0.0)
	var crest_left := maxf(limit - w_now * side_now, 0.0)
	var life_left := maxf(s.lifetime - s.age - s.fade_time, 0.0)
	return minf(crest_left / SPEED, life_left)


func update(delta: float, input: RiderInput) -> void:
	if wave == null or wave.is_dead() or rider.water == null or not rider.water.swells.has(wave):
		state_machine.transition_to(&"riding")
		return
	ride_time += delta
	rider.lip_time_left = maxf(total - ride_time, 0.0)
	rider.lip_progress = progress()
	_update_balance(delta, input)
	# Avanza por la cresta; al llegar a la punta (o cuando la ola se empieza a
	# disolver) termina: completado.
	var limit := maxf(wave.half_length - wave.edge - 2.0, 0.0)
	w = clampf(w + side * SPEED * delta, -limit, limit)
	rider.speed = SPEED
	_place()
	if absf(balance) >= 1.0:
		_wipe_out()
		return
	if ride_time >= total or absf(w) >= limit:
		_complete()


## Perpendicular a la dirección de la ola (a lo largo de la cresta).
func _perp() -> Vector2:
	return Vector2(-wave.direction.y, wave.direction.x)


## Progreso (0 al engancharse .. 1 al terminar).
func progress() -> float:
	return clampf(ride_time / total, 0.0, 1.0)


## El empujón de la ola cambia cada tanto (cada vez más seguido y más fuerte);
## el stick lo corrige.
func _update_balance(delta: float, input: RiderInput) -> void:
	var k := smoothstep(0.0, 1.0, progress())
	_push_timer -= delta
	if _push_timer <= 0.0:
		var lo := lerpf(PUSH_TIME_START.x, PUSH_TIME_END.x, k)
		var hi := lerpf(PUSH_TIME_START.y, PUSH_TIME_END.y, k)
		_push_timer = _rng.randf_range(lo, hi)
		var dir := -1.0 if _rng.randf() < 0.5 else 1.0
		_push_target = dir * _rng.randf_range(0.5, 1.0)
	_push = move_toward(_push, _push_target, delta * 3.0)
	var strength := lerpf(PUSH_START, PUSH_END, k)
	var unstable := lerpf(UNSTABLE_START, UNSTABLE_END, k)
	var vel := _push * strength + balance * unstable + input.steer * CONTROL
	balance = clampf(balance + vel * delta, -1.0, 1.0)
	rider.lip_balance = balance
	rider.lip_danger = smoothstep(0.5, 0.95, absf(balance))
	# Se ladea según el equilibrio (lo visual).
	rider.steer_amount = balance * 0.8


## Lo pone arriba de la cresta tal como se dibuja (corrida hacia adelante por
## el labio), con la tabla en diagonal raspando.
func _place() -> void:
	var perp := _perp()
	var top := wave.center + perp * w + wave.direction * wave.crest_u()
	var h := rider.water.height_at(top.x, top.y) + RIDE_ABOVE
	rider.position = Vector3(top.x, h, top.y)
	# Mira hacia donde avanza por la cresta: la cámara queda justo detrás,
	# como siempre. La diagonal es solo de la tabla (la pose de raspar, abajo).
	var d := perp * side
	rider.heading = atan2(-d.x, -d.y)
	rider.rotation.y = rider.heading
	# Raspando: la tabla de costado, levantando agua (como el derrape).
	var right := rider.right()
	rider.drift_side = 1 if Vector2(right.x, right.z).dot(wave.direction) < 0.0 else -1
	rider.water_normal = Vector3.UP
	rider.grounded = true
	rider.vertical_speed = 0.0


## Perdió el equilibrio: cae atrás de la ola. Se queda con los puntos que hizo.
func _wipe_out() -> void:
	var p := wave.center + _perp() * w + wave.direction * (wave.crest_u() - wave.width * 1.6)
	rider.position = Vector3(p.x, rider.water.height_at(p.x, p.y), p.y)
	rider.speed = minf(rider.speed, 3.0)
	wave.keep = false
	wave.retire()
	rider.lip_exited.emit(false)
	rider.fall()


## Aguantó hasta el final (la punta de la cresta, o la ola que se disuelve):
## sale disparado (con motivación) y queda en el aire.
func _complete() -> void:
	wave.keep = false
	rider.trigger_motivation()
	rider.speed = rider.stats.max_speed * rider.stats.motivation_speed_mult
	rider.vertical_speed = EXIT_UP
	rider.grounded = false
	rider.can_trick = true
	rider.wave_air_time = -1.0
	rider.lip_exited.emit(true)
	state_machine.transition_to(&"airborne")
