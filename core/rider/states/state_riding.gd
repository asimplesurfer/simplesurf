extends RiderState
## Movimiento normal sobre la tabla: W / stick arriba acelera, el stick gira.
## Salto según GameSettings.jump_mode:
##   CHARGE: mantener A carga el salto (se agacha); al soltar, o al llegar al
##           máximo, salta. Más carga, más alto.
##   TAP: tocar A salta enseguida.
## El botón de derrape pasa a `drifting`. Una ola con velocidad lo lanza al aire.

## Tras pararse, A no salta por un momento (el spam para levantarse no debe hacerte saltar).
var _jump_lock: float = 0.0
var _charging: bool = false


func enter(previous: StringName) -> void:
	rider.set_recovery_stage(Rider.RecoveryStage.STANDING)
	_jump_lock = 0.0
	_charging = false
	rider.jump_charge = 0.0
	if previous == &"fallen":
		_jump_lock = rider.stats.stand_jump_lock
		rider.stood_up.emit()


func update(delta: float, input: RiderInput) -> void:
	_jump_lock = maxf(0.0, _jump_lock - delta)
	if _charging:
		if input.trick:
			rider.jump_charge = minf(1.0, rider.jump_charge + delta / rider.stats.jump_charge_time)
		if not input.trick or rider.jump_charge >= 1.0:
			_charging = false
			rider.jump()
			state_machine.transition_to(&"airborne")
			return
	elif input.jump_pressed and _jump_lock <= 0.0:
		if GameSettings.jump_mode == GameSettings.JumpMode.TAP:
			rider.jump()
			state_machine.transition_to(&"airborne")
			return
		_charging = true
		rider.jump_charge = 0.0

	if input.drift and rider.speed >= rider.stats.drift_min_speed:
		_charging = false
		rider.jump_charge = 0.0
		state_machine.transition_to(&"drifting")
		return

	rider.apply_throttle(input.throttle, delta, input.turbo)
	rider.apply_steer(input.steer, delta)
	rider.move_forward(delta)
	if rider.stick_to_water(delta):
		_charging = false
		state_machine.transition_to(&"airborne")
