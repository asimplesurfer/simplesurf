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


## Tira a los rivales que quedan adentro de la cortina de agua TAL COMO SE VE
## (su forma y su tamaño de ese momento: al empezar el derrape todavía es chica).
## Al costado de la tabla, fuera de la cortina, no pega.
func _hit_riders_in_cone() -> void:
	var spray: DriftSpray = rider.visual.drift_spray() if rider.visual else null
	for node in rider.get_tree().get_nodes_in_group("riders"):
		var other := node as Rider
		if other == null or other == rider or other.is_fallen() or not other.grounded or other.in_tube():
			continue
		var hit := false
		if spray:
			hit = spray.covers(other.global_position, VICTIM_RADIUS)
		else:
			hit = _in_cone(other)
		if hit:
			other.fall()
			rider.drift_hit.emit(other)
			rider.trigger_motivation()


## Medio ancho del cuerpo del rival (m): lo toca si la cortina le llega al cuerpo.
const VICTIM_RADIUS := 0.3


## Sin parte visual (no debería pasar): el cono de las estadísticas.
func _in_cone(other: Rider) -> bool:
	var stats := rider.stats
	var rel := other.global_position - rider.global_position
	rel.y = 0.0
	var dist_back := rel.dot(-rider.forward())
	if dist_back <= 0.0 or dist_back > stats.drift_range:
		return false
	return absf(rel.dot(rider.right())) <= 0.5 + dist_back * tan(deg_to_rad(stats.drift_cone_half_angle))
