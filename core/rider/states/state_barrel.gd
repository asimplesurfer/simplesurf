extends RiderState
## Adentro del tubo de una ola que rompe de a poco (modo trucos; ver
## Swell.peel_w y TrickAttack). Es un truco exótico (ExoticTrick.Kind.TUBE).
##
## La ola sigue avanzando y el punto de rotura corre a lo largo de la cresta:
## el surfista va con él, adentro del tubo abierto, un poco detrás de donde el
## labio se está tirando (el "bolsillo", POCKET). Si entró más atrás, alcanza
## el bolsillo de a poco.
##
## Equilibrio (como en el tubo de carrera): la ola lo empuja hacia un lado o el
## otro y él corrige con el stick. Muy hacia la pared, lo tapa el labio; muy
## hacia afuera, lo escupe la espuma. En los dos casos se cae (se queda con lo
## que juntó). Si aguanta hasta que el tubo llega a la punta de la ola, sale
## disparado por adelante (bonus y motivación).

## Dónde va, respecto del punto de rotura (m, negativo = detrás).
const POCKET := -7.0
## Con qué velocidad alcanza el bolsillo si entró más atrás (m/s de más).
const CATCH_UP := 4.0
## Termina cuando el bolsillo llega a esta distancia (m) del final de la ola
## (antes de las puntas, donde la ola se achica).
const END_MARGIN := 4.0
## Por dónde va adentro (veces la altura, hacia adelante desde el centro de
## la ola): en el medio del hueco, debajo del labio, donde el piso es plano
## (más atrás el piso se curva para arriba hasta la pared y la tabla quedaba
## tapada). Y cuánto se corre de costado con el equilibrio al máximo (veces
## la altura): ni con el equilibrio al máximo llega al pie de la pared.
const LINE := 1.6
const REACH := 0.2
## Al final, el ojo: cuando le faltan EXIT_RUSH_AT m acelera (EXIT_RUSH m/s de
## más) hasta pasar adelante del punto de rotura más allá de donde el labio se
## achica (EXIT_REL m: más que Swell.BARREL_THROAT), donde la ola queda abierta
## (ver Swell.BARREL_SHOULDER_HOLD), y sale derecho y rápido por ahí, apenas
## hacia afuera (EXIT_TURN rad): no atraviesa la cortina del labio.
const EXIT_RUSH_AT := 30.0
const EXIT_RUSH := 16.0
const EXIT_REL := 11.0
const EXIT_TURN := 0.15
## Al caerse, la ola lo escupe hasta esta distancia (m) más allá de la punta
## del labio.
const SPIT_MARGIN := 3.0
## Al entrar, un ratito sin empujones (para acomodarse).
const SETTLE_TIME := 1.0
## Al entrar, de dónde venía (por la cara de adelante) pasa a su línea adentro
## del tubo de a poco, a medida que el labio se cierra encima (s), y gira
## hacia donde corre la rotura (s).
const ENTRY_TIME := 0.9
const TURN_TIME := 0.4
## Mientras el labio se forma, la cara de adelante se infla y enseguida se
## abre el piso del tubo: la ola lo levanta (sube con la cara, apenas más
## suave) y él cae adentro del tubo, sin golpe (m/s para arriba y para abajo).
const ENTRY_RISE := 28.0
const ENTRY_DROP := 14.0
## Desde qué forma (Swell.curl) el tubo ya está armado: hasta ahí la ola no lo
## empuja (se está formando encima).
const FORMED := 0.9
## El espacio de adentro es el que se ve (Swell.tube_band): con el equilibrio
## al máximo toca la pared (o queda bajo la punta del labio). BODY_MARGIN: la
## mitad del ancho del surfista (m). Se recalcula cada BAND_EVERY s y se sigue
## suave (BAND_RATE 1/s).
const BODY_MARGIN := 0.6
const BAND_EVERY := 0.1
const BAND_RATE := 6.0
## Mientras más dura adentro, más se cierra el tubo (Swell.tube_close): al
## final, CLOSE_MAX (el labio baja y la pared se acerca: hay menos lugar).
const CLOSE_MAX := 0.7
## Empujón de la ola y lo inestable (como en el tubo de carrera): crecen de a
## poco hasta el final.
const PUSH_START := 0.2
const PUSH_END := 0.55
const UNSTABLE_START := 0.15
const UNSTABLE_END := 0.5
const CONTROL := 1.8
const PUSH_MIN_TIME := 0.5
const PUSH_MAX_TIME := 1.3

var wave: Swell
## Dónde está respecto del punto de rotura (m a lo largo de la cresta, hacia
## donde avanza; negativo = detrás).
var rel: float = POCKET
## Equilibrio: 0 en el medio, +1 tapado por el labio, -1 escupido por la espuma.
var balance: float = 0.0
## Dónde empezó y dónde termina (punto de rotura + rel, a lo largo de la
## cresta): para el progreso.
var _from: float = 0.0
var _push: float = 0.0
## Por dónde venía al entrar (m hacia adelante de la ola) y hacia dónde
## miraba; cuánto hace que entró (s).
var _entry_u: float = 0.0
var _entry_heading: float = 0.0
var _t_in: float = 0.0
## Cuando el tubo ya está armado, un ratito sin caerse (ver ExoticGrace).
var _grace := ExoticGrace.new()
## El espacio de adentro (u desde el centro de la ola: de la pared a la punta
## del labio), el que se sigue y el último que se midió.
var _band := Vector2.ZERO
var _band_target := Vector2.ZERO
var _band_timer: float = 0.0
var _push_target: float = 0.0
var _push_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func enter(_previous: StringName) -> void:
	wave = rider.barrel_wave
	_rng.randomize()
	balance = 0.0
	_push = 0.0
	_push_target = 0.0
	_push_timer = SETTLE_TIME
	_t_in = 0.0
	_entry_heading = rider.heading
	_grace.start(rider.input.steer if rider.input else 0.0)
	_band = Vector2.ZERO
	_band_target = Vector2.ZERO
	_band_timer = 0.0
	if wave:
		var uw := wave.local_coords(Vector2(rider.position.x, rider.position.z))
		rel = clampf((uw.y - wave.peel_w) * wave.peel_dir, -wave.barrel_len, 0.0)
		_entry_u = uw.x
		_from = _along()
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	rider.grounded = true
	rider.vertical_speed = 0.0
	rider.drift_side = 0
	rider.shove = Vector3.ZERO
	rider.turbo_time = 0.0
	rider.reset_steer()
	rider.tube_balance = balance
	rider.tube_danger = 0.0
	rider.start_exotic(ExoticTrick.Kind.TUBE)
	rider.tube_entered.emit()


func exit() -> void:
	# Si salió de otra forma (reinicio, la ola se fue): como caerse.
	rider.finish_exotic(false)
	rider.barrel_wave = null
	wave = null
	rider.tube_balance = 0.0
	rider.tube_danger = 0.0


func update(delta: float, input: RiderInput) -> void:
	if wave == null or wave.curl <= 0.0 or rider.water == null or not rider.water.swells.has(wave):
		state_machine.transition_to(&"riding")
		return
	_t_in += delta
	# Mientras más dura, más se cierra el tubo.
	wave.tube_close = maxf(wave.tube_close, CLOSE_MAX * smoothstep(0.0, 1.0, progress()))
	_update_band(delta)
	# Alcanza el bolsillo (si entró más atrás) y va con la rotura; al final
	# acelera hacia el ojo.
	if rushing():
		rel = move_toward(rel, EXIT_REL, EXIT_RUSH * delta)
	else:
		rel = move_toward(rel, POCKET, CATCH_UP * delta)
	rider.update_exotic(progress())
	_update_balance(delta, input)
	_place(delta)
	if absf(balance) >= 1.0:
		_wipe_out()
		return
	if _along() >= _end():
		_complete()


## Dónde está a lo largo de la cresta (m desde el medio, hacia donde avanza la rotura).
func _along() -> float:
	return wave.peel_w * wave.peel_dir + rel


## El espacio de adentro donde está (ver Swell.tube_band), seguido suave.
func _update_band(delta: float) -> void:
	_band_timer -= delta
	if _band_timer <= 0.0:
		_band_timer = BAND_EVERY
		var b := wave.tube_band(wave.peel_w + rel * wave.peel_dir)
		if b.y - b.x > BODY_MARGIN * 2.0:
			_band_target = b
	if _band_target == Vector2.ZERO:
		return
	if _band == Vector2.ZERO:
		_band = _band_target
	else:
		_band = _band.lerp(_band_target, 1.0 - exp(-BAND_RATE * delta))


## Por dónde va adentro (u desde el centro de la ola) según el equilibrio:
## +1 contra la pared, -1 bajo la punta del labio.
func line_u() -> float:
	var a := wave.max_amplitude
	if _band == Vector2.ZERO:
		return LINE * a - balance * REACH * a
	var center := (_band.x + _band.y) * 0.5
	var half := maxf((_band.y - _band.x) * 0.5 - BODY_MARGIN, 0.3)
	return center - balance * half


## true en el tramo final: acelera hacia el ojo del tubo.
func rushing() -> bool:
	return wave != null and _end() - _along() < EXIT_RUSH_AT and wave.curl >= FORMED


## Hasta dónde llega (antes de la punta de la ola).
func _end() -> float:
	return wave.half_length - wave.edge - END_MARGIN


## 0 al entrar .. 1 al llegar a la punta.
func progress() -> float:
	var span := maxf(_end() - _from, 1.0)
	return clampf((_along() - _from) / span, 0.0, 1.0)


func _update_balance(delta: float, input: RiderInput) -> void:
	var formed := wave.curl >= FORMED
	# El stick que cuenta (ver ExoticGrace: la gracia corre con el tubo armado).
	var steer := _grace.steer(input.steer, delta, formed)
	rider.steer_amount = input.steer * 0.6
	if not formed:
		# Mientras el tubo se forma encima: el equilibrio quieto (se acomoda).
		_push_timer = maxf(_push_timer, SETTLE_TIME * 0.5)
		rider.tube_balance = balance
		rider.tube_danger = 0.0
		return
	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = _rng.randf_range(PUSH_MIN_TIME, PUSH_MAX_TIME)
		var dir := -1.0 if _rng.randf() < 0.5 else 1.0
		_push_target = dir * _rng.randf_range(0.45, 1.0)
	_push = move_toward(_push, _push_target, delta * 3.0)
	var k := smoothstep(0.0, 1.0, progress())
	var strength := lerpf(PUSH_START, PUSH_END, k)
	var unstable := lerpf(UNSTABLE_START, UNSTABLE_END, k)
	var toward_wall := steer * wall_on_right_sign()
	var vel := _push * strength + balance * unstable + toward_wall * CONTROL
	balance = _grace.clamp_balance(clampf(balance + vel * delta, -1.0, 1.0))
	rider.tube_balance = balance
	rider.tube_danger = smoothstep(0.5, 0.95, absf(balance))


## +1 si la pared (el cuerpo de la ola, hacia atrás) queda a su derecha.
func wall_on_right_sign() -> float:
	if wave == null:
		return 1.0
	var r := rider.right()
	return 1.0 if Vector2(r.x, r.z).dot(-wave.direction) >= 0.0 else -1.0


## Lo pone en su lugar: sobre el piso de adentro del tubo, mirando hacia
## donde avanza la rotura. Recién entrado, todavía cerca de por donde venía
## (el labio se está cerrando encima).
func _place(delta: float) -> void:
	var perp := Vector2(-wave.direction.y, wave.direction.x)
	var w := wave.peel_w + rel * wave.peel_dir
	var k := minf(smoothstep(0.0, ENTRY_TIME, _t_in), smoothstep(0.2, 0.9, wave.curl))
	var u := lerpf(_entry_u, line_u(), k)
	var p := wave.center + wave.direction * u + perp * w
	var y := rider.water.floor_height_at(p.x, p.y)
	if _t_in < ENTRY_TIME or wave.curl < FORMED:
		y = clampf(y, rider.position.y - ENTRY_DROP * delta, rider.position.y + ENTRY_RISE * delta)
	rider.position = Vector3(p.x, y, p.y)
	var f := perp * wave.peel_dir
	rider.heading = lerp_angle(_entry_heading, atan2(-f.x, -f.y), smoothstep(0.0, TURN_TIME, _t_in))
	rider.rotation.y = rider.heading
	rider.speed = wave.peel_speed + (EXIT_RUSH if rushing() else 0.0)
	rider.water_normal = Vector3.UP
	rider.grounded = true
	rider.vertical_speed = 0.0


## Se cayó: el labio lo tapó (hacia la pared) o lo escupió la espuma (hacia
## afuera). En los dos casos la ola lo escupe al agua de adelante, afuera del
## tubo (no queda nadando debajo del labio). Se queda con lo que juntó.
func _wipe_out() -> void:
	var lip := balance > 0.0
	var a := wave.max_amplitude
	var uw := wave.local_coords(Vector2(rider.position.x, rider.position.z))
	# Más allá de la punta del labio.
	var u := (1.35 + Swell.TUBE_RX) * a + SPIT_MARGIN
	var p := wave.center + wave.direction * u + Vector2(-wave.direction.y, wave.direction.x) * uw.y
	var tries := 0
	while rider.water.under_roof(p.x, p.y, rider.water.floor_height_at(p.x, p.y)) and tries < 8:
		p += wave.direction * 2.0
		tries += 1
	rider.position = Vector3(p.x, rider.water.height_at(p.x, p.y), p.y)
	rider.speed = minf(rider.speed, 4.0)
	rider.finish_exotic(false)
	rider.tube_exited.emit(false)
	rider.tube_wiped_out.emit(lip)
	rider.fall()


## Llegó a la punta: sale disparado por el ojo, derecho (apenas hacia afuera).
func _complete() -> void:
	var f := Vector2(-wave.direction.y, wave.direction.x) * wave.peel_dir
	var a1 := f.rotated(EXIT_TURN)
	var a2 := f.rotated(-EXIT_TURN)
	var out := a1 if a1.dot(wave.direction) > a2.dot(wave.direction) else a2
	rider.heading = atan2(-out.x, -out.y)
	rider.speed = rider.stats.max_speed * rider.stats.motivation_speed_mult
	rider.finish_exotic(true)
	rider.tube_exited.emit(true)
	state_machine.transition_to(&"riding")
