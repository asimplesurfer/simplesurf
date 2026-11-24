extends RiderState
## Adentro de un tubo (ver TubeWave). El tubo lo lleva a su velocidad (la misma
## para todos los que están adentro) y le va llenando el nitro. El jugador
## mantiene el equilibrio con el stick (izquierda / derecha): la ola lo va
## corriendo de a poco hacia un lado o el otro, y el equilibrio es su lugar en
## la pared de la ola:
##   - muy arriba (hacia la pared), el labio lo tapa;
##   - muy abajo (hacia el lado abierto), lo escupe la espuma.
## En los dos casos se cae (como al chocar) y pierde el nitro que sumó adentro.
## Si aguanta hasta el final, sale por adelante con un turbo y el nitro lleno.

## Al entrar, un ratito sin empujones (para acomodarse).
const SETTLE_TIME := 1.5
## Empujón de la ola (cuánto corre el equilibrio por segundo): al principio
## suave, y de a poco más fuerte hasta el final.
const PUSH_START := 0.18
const PUSH_END := 0.45
## Inestable: cuanto más corrido, más se corre solo (por segundo). También
## crece de a poco.
const UNSTABLE_START := 0.15
const UNSTABLE_END := 0.45
## Cuánto corrige el stick al máximo (por segundo). Siempre puede más que la ola.
const CONTROL := 1.8
## Los últimos segundos (s) la ola ya no empuja (sale derecho).
const EXIT_SETTLE := 0.7
## Cada cuánto cambia el empujón de la ola (s).
const PUSH_MIN_TIME := 0.5
const PUSH_MAX_TIME := 1.3

var tube: TubeWave
## Metros desde la boca del tubo.
var s: float = 0.0
## Equilibrio: 0 en el medio, +1 tapado por el labio, -1 escupido por la espuma.
var balance: float = 0.0
var _push: float = 0.0
var _push_target: float = 0.0
var _push_timer: float = 0.0
var _time: float = 0.0
## Nitro al entrar (si se cae, vuelve a esto).
var _entry_nitro: float = 0.0
## Tiempo que le quedaba al tubo al entrar (para llenar el nitro parejo).
var _entry_left: float = 1.0
var _rng := RandomNumberGenerator.new()


func enter(_previous: StringName) -> void:
	tube = rider.tube
	_rng.randomize()
	s = float(tube.inside.get(rider, 0.0)) if tube else 0.0
	balance = 0.0
	_push = 0.0
	_push_target = 0.0
	_push_timer = SETTLE_TIME
	_time = 0.0
	_entry_nitro = rider.nitro
	_entry_left = maxf(tube.time_left(), 0.5) if tube else 1.0
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	rider.grounded = true
	rider.vertical_speed = 0.0
	rider.drift_side = 0
	rider.shove = Vector3.ZERO
	rider.turbo_time = 0.0
	rider.reset_steer()
	rider.tube_balance = 0.0
	rider.tube_danger = 0.0


func exit() -> void:
	if tube and is_instance_valid(tube):
		tube.leave(rider)
	tube = null
	rider.tube = null
	rider.tube_balance = 0.0
	rider.tube_danger = 0.0


func update(delta: float, input: RiderInput) -> void:
	if tube == null or not is_instance_valid(tube) or tube.phase == TubeWave.Phase.CLOSING:
		state_machine.transition_to(&"riding")
		return
	_time += delta
	s += tube.speed * delta
	tube.inside[rider] = s
	rider.speed = tube.speed

	# Nitro: se va llenando hasta el final.
	var fill := clampf(_time / _entry_left, 0.0, 1.0)
	var target := lerpf(_entry_nitro, Rider.NITRO_MAX, fill)
	if target > rider.nitro and rider.nitro_enabled:
		rider.nitro = target
		rider.nitro_changed.emit(rider.nitro, Rider.NITRO_MAX)

	# Llegando a la salida la ola ya no empuja: baja al medio para salir derecho.
	if tube.time_left() < EXIT_SETTLE:
		balance = move_toward(balance, 0.0, delta * 2.5)
		rider.tube_balance = balance
		rider.tube_danger = 0.0
	else:
		_update_balance(delta, input)
	_place()

	if absf(balance) >= 1.0:
		_wipe_out()
		return
	if tube.time_left() <= 0.0:
		_spit_out()


## El empujón de la ola cambia cada tanto; el stick lo corrige.
func _update_balance(delta: float, input: RiderInput) -> void:
	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = _rng.randf_range(PUSH_MIN_TIME, PUSH_MAX_TIME)
		# Casi siempre empuja (para un lado o el otro); a veces hacia donde ya está corrido.
		var dir := -1.0 if _rng.randf() < 0.5 else 1.0
		_push_target = dir * _rng.randf_range(0.45, 1.0)
	_push = move_toward(_push, _push_target, delta * 3.0)
	var k := smoothstep(0.0, 1.0, tube.progress())
	var strength := lerpf(PUSH_START, PUSH_END, k)
	var unstable := lerpf(UNSTABLE_START, UNSTABLE_END, k)
	var toward_wall := input.steer * wall_on_right_sign()
	var vel := _push * strength + balance * unstable + toward_wall * CONTROL
	balance = clampf(balance + vel * delta, -1.0, 1.0)
	rider.tube_balance = balance
	rider.tube_danger = smoothstep(0.5, 0.95, absf(balance))
	# Se ladea con el stick (lo visual).
	rider.steer_amount = input.steer * 0.6


## +1 si la pared queda a su derecha (el stick a la derecha lo sube), -1 si a la izquierda.
func wall_on_right_sign() -> float:
	var f: Array = tube.frame_at(s)
	var w: Vector3 = f[1]
	return 1.0 if w.dot(rider.right()) >= 0.0 else -1.0


## Lo pone en su lugar de la pared de la ola.
func _place() -> void:
	var f: Array = tube.frame_at(s)
	var o: Vector3 = f[0]
	var w: Vector3 = f[1]
	var u := balance * TubeWave.BALANCE_REACH
	var p := o + w * u
	if tube.floor_base:
		# El tubo es el agua misma (modo trucos): sobre su piso, donde está.
		p.y = tube.base_height(p)
	else:
		p.y = tube.base_height(o) + TubeWave.face_y(u)
	rider.position = p
	rider.heading = tube.heading_at(s)
	rider.rotation.y = rider.heading
	# La tabla se apoya en la pared (inclinada hacia el lado abierto).
	rider.water_normal = Vector3.UP if tube.floor_base else (Vector3.UP - w * TubeWave.face_slope(u)).normalized()
	rider.grounded = true
	rider.vertical_speed = 0.0


## Se cayó: el labio lo tapó o lo escupió la espuma. Pierde lo que sumó adentro.
func _wipe_out() -> void:
	var lip := balance > 0.0
	rider.nitro = minf(rider.nitro, _entry_nitro)
	rider.nitro_changed.emit(rider.nitro, Rider.NITRO_MAX)
	rider.speed = minf(rider.speed, 4.0)
	# Queda en el agua de abajo, del lado abierto (no adentro de la pared).
	var f: Array = tube.frame_at(s)
	var o: Vector3 = f[0]
	var w: Vector3 = f[1]
	var p := o - w * 1.5
	rider.position = Vector3(p.x, tube.base_height(p), p.z)
	rider.tube_exited.emit(false)
	rider.tube_wiped_out.emit(lip)
	rider.fall()


## Llegó al final: sale disparado con un turbo (no gasta cargas) y el nitro lleno.
func _spit_out() -> void:
	if rider.nitro_enabled:
		rider.nitro = Rider.NITRO_MAX
		rider.nitro_changed.emit(rider.nitro, Rider.NITRO_MAX)
	rider.speed = tube.speed
	rider.turbo_time = rider.stats.turbo_burst_time * TUBE_EXIT_TURBO
	rider.turbo_fired.emit()
	rider.trigger_motivation()
	rider.tube_exited.emit(true)
	state_machine.transition_to(&"riding")


## La salida del tubo es una ráfaga de turbo más larga que la normal.
const TUBE_EXIT_TURBO := 1.4
