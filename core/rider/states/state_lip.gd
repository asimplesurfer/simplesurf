extends RiderState
## En el borde de una ola de borde (modo trucos; ver TrickAttack y
## Swell.lip). Llegó a la cresta desde atrás y la ola lo lleva por el borde:
## avanza a lo largo de la cresta con la tabla en diagonal, raspando (como en
## el derrape), mientras la ola sigue su camino.
##
## Minijuego de equilibrio: la ola lo empuja para un lado o el otro y él
## corrige con el stick (izquierda / derecha). Cada vez empuja más fuerte y
## más seguido. Si el equilibrio llega a un extremo, se cae (atrás de la ola).
## La ola dura LIP_TIME segundos: si aguanta hasta que se disuelve, sale
## disparado con motivación (y queda en el aire: puede seguir con trucos).

## Cuánto dura la ola una vez que lo engancha (s).
const LIP_TIME := 12.0
## Al engancharse, un ratito sin empujones (para acomodarse).
const SETTLE_TIME := 1.0
## Velocidad a lo largo de la cresta (m/s).
const SPEED := 12.0
## La tabla va en diagonal: cuánto apunta hacia el frente de la ola (rad).
const DIAGONAL := 0.4
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
		var f := rider.forward()
		var perp := _perp()
		var along := Vector2(f.x, f.z).dot(perp)
		if absf(along) > 0.15:
			side = signf(along)
		else:
			side = -signf(w) if absf(w) > 1.0 else 1.0
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	rider.grounded = true
	rider.vertical_speed = 0.0
	rider.shove = Vector3.ZERO
	rider.turbo_time = 0.0
	rider.reset_steer()
	rider.lip_balance = 0.0
	rider.lip_danger = 0.0
	rider.lip_time_left = LIP_TIME
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


func update(delta: float, input: RiderInput) -> void:
	if wave == null or wave.is_dead() or rider.water == null or not rider.water.swells.has(wave):
		state_machine.transition_to(&"riding")
		return
	ride_time += delta
	rider.lip_time_left = maxf(LIP_TIME - ride_time, 0.0)
	_update_balance(delta, input)
	# Avanza por la cresta (sin pasarse de las puntas, donde la ola se achica).
	var limit := maxf(wave.half_length - wave.edge - 2.0, 0.0)
	w = clampf(w + side * SPEED * delta, -limit, limit)
	rider.speed = SPEED
	_place()
	if absf(balance) >= 1.0:
		_wipe_out()
		return
	if ride_time >= LIP_TIME:
		_complete()


## Perpendicular a la dirección de la ola (a lo largo de la cresta).
func _perp() -> Vector2:
	return Vector2(-wave.direction.y, wave.direction.x)


## Progreso de la ola (0 al engancharse .. 1 al disolverse).
func progress() -> float:
	return clampf(ride_time / LIP_TIME, 0.0, 1.0)


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
	var on_crest := wave.center + perp * w
	var top := on_crest + wave.direction * wave.lean() * 0.9
	var h := rider.water.height_at(on_crest.x, on_crest.y)
	rider.position = Vector3(top.x, h, top.y)
	# Hacia donde avanza por la cresta, un poco hacia el frente de la ola.
	var d := (perp * side).rotated(DIAGONAL * side).normalized()
	if d.dot(wave.direction) < 0.0:
		d = (perp * side).rotated(-DIAGONAL * side).normalized()
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
	var p := wave.center + _perp() * w - wave.direction * wave.width * 1.6
	rider.position = Vector3(p.x, rider.water.height_at(p.x, p.y), p.y)
	rider.speed = minf(rider.speed, 3.0)
	wave.keep = false
	wave.retire()
	rider.lip_exited.emit(false)
	rider.fall()


## Aguantó hasta que la ola se disolvió: sale disparado (con motivación) y
## queda en el aire.
func _complete() -> void:
	wave.keep = false
	wave.fade_time = minf(wave.fade_time, 1.5)
	wave.retire()
	rider.trigger_motivation()
	rider.speed = rider.stats.max_speed * rider.stats.motivation_speed_mult
	rider.vertical_speed = EXIT_UP
	rider.grounded = false
	rider.can_trick = true
	rider.wave_air_time = -1.0
	rider.lip_exited.emit(true)
	state_machine.transition_to(&"airborne")
