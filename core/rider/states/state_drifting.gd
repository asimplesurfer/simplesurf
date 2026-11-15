extends RiderState
## Derrape: frena y tira agua hacia atrás en forma de cono (la tabla sigue
## derecha y se gira con el stick, como siempre). Quien esté dentro del cono (y no esté saltando)
## se cae de su tabla. Se hace mientras se mantiene el botón de derrape.


func enter(_previous: StringName) -> void:
	var side := signf(rider.input.steer)
	if side == 0.0:
		side = signf(rider.current_steer())
	if side == 0.0:
		side = 1.0
	rider.drift_side = int(side)
	rider.drift_started.emit(rider.drift_side)


func exit() -> void:
	rider.drift_side = 0
	rider.drift_ended.emit()


func update(delta: float, input: RiderInput) -> void:
	var stats := rider.stats
	if input.jump_pressed:
		if GameSettings.jump_style == GameSettings.JumpStyle.WAVES:
			rider.hop()
		else:
			rider.jump()
		state_machine.transition_to(&"airborne")
		return
	if not input.drift or rider.speed < stats.drift_end_speed:
		state_machine.transition_to(&"riding")
		return

	rider.speed = move_toward(rider.speed, 0.0, stats.drift_decel * delta)
	rider.apply_steer(input.steer, delta)
	rider.move_forward(delta)
	_hit_riders_in_cone()
	if rider.stick_to_water(delta):
		state_machine.transition_to(&"airborne")


## Comprueba rivales dentro del cono de agua (por posición relativa, sin física).
func _hit_riders_in_cone() -> void:
	var stats := rider.stats
	var back := -rider.forward()
	var side := rider.right()
	var tan_half := tan(deg_to_rad(stats.drift_cone_half_angle))
	for node in rider.get_tree().get_nodes_in_group("riders"):
		var other := node as Rider
		if other == null or other == rider or other.is_fallen() or not other.grounded:
			continue
		var rel := other.global_position - rider.global_position
		rel.y = 0.0
		var dist_back := rel.dot(back)
		if dist_back <= 0.0 or dist_back > stats.drift_range:
			continue
		if absf(rel.dot(side)) <= 0.8 + dist_back * tan_half:
			other.fall()
			rider.drift_hit.emit(other)
			rider.trigger_motivation()
