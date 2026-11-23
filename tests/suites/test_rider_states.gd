extends "res://tests/test_base.gd"
## Transiciones raras del surfista.


func run() -> void:
	await _test_rare_transitions()


## Transiciones raras del surfista: que ninguna deje cosas "pegadas".
func _test_rare_transitions() -> void:
	print("Transiciones raras del surfista:")
	var saved := [GameSettings.player_count, GameSettings.bot_count]
	GameSettings.player_count = 1
	GameSettings.bot_count = 0
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var race := m.get_node("RaceManager") as RaceManager
	race.skip_countdown()
	var r: Rider = race.humans()[0]
	_rider = r
	(m.get_node("Water") as Water).clear_swells()
	(m.get_node("WaveManager") as WaveManager).enabled = false
	await _wait(1.0)

	# 1. Caerse en el aire, girando: queda en el agua, sin truco ni contador.
	r.vertical_speed = 9.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	r.trick_angle = 2.0
	r.live_spins = 1
	r.fall()
	await process_frame
	_check(
		_state() == &"fallen" and r.trick_angle == 0.0 and r.live_spins == 0,
		"caerse en el aire girando no deja el truco ni el contador pegados"
	)
	await _wait(1.5)
	_check(r.position.y - r.water_height() < 0.3, "y cae al agua (no se queda flotando en el aire)")

	# 2. Levantarse con el botón apretado: no salta de una.
	await _mash_until_standing(12.0, 6.0)
	_check(_state() == &"riding", "se levanta spameando")
	_set_action(&"p1_a", true)
	for i in 6:
		await process_frame
	_check(_state() == &"riding" and r.grounded, "con el botón todavía apretado no sale saltando")
	_set_action(&"p1_a", false)
	await _wait(0.6)

	# 3. Chocar en medio de un derrape: el derrape termina bien.
	var ended := [false]
	r.drift_ended.connect(func() -> void: ended[0] = true, CONNECT_ONE_SHOT)
	r.speed = 12.0
	r.state_machine.transition_to(&"drifting")
	await process_frame
	r.crash(r.position)
	await process_frame
	_check(_state() == &"fallen" and r.drift_side == 0 and ended[0], "chocar derrapando termina el derrape (sin lado pegado)")
	_check(r.speed <= 3.0, "y frena")

	# 4. Un géiser no lanza a alguien caído.
	r.geyser_launch(Geyser.LAUNCH_SPEED)
	_check(_state() == &"fallen" and r.grounded, "un géiser no lanza a alguien caído")
	await _mash_until_standing(12.0, 6.0)

	# 5. Dos transiciones en el mismo cuadro: gana la última y queda limpia.
	r.vertical_speed = 8.0
	r.grounded = false
	r.state_machine.transition_to(&"airborne")
	r.fall()
	_check(_state() == &"fallen" and r.trick_angle == 0.0, "saltar y caerse en el mismo cuadro termina caído y limpio")
	await _mash_until_standing(12.0, 6.0)

	# 6. Truco: dos vueltas completas cuentan una sola vez al aterrizar.
	var landed_spins: Array[int] = []
	r.trick_landed.connect(func(spins: int) -> void: landed_spins.append(spins))
	# Sin el freno del aire fino, para que entren dos trucos seguro.
	var saved_stats := r.stats
	r.stats = r.stats.duplicate()
	r.stats.air_soft_height = 50.0
	r.stats.air_max_height = 60.0
	r.position.y += 1.0
	r.vertical_speed = 20.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	var max_live := 0
	for i in int(3.0 * FPS):
		max_live = maxi(max_live, r.live_spins)
		if r.live_spins >= 2:
			break
		await process_frame
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 4.0)
	await _wait(0.2)
	r.stats = saved_stats
	_check(
		landed_spins.size() == 1 and landed_spins[0] >= 2,
		"un truco de %d vueltas cuenta una sola vez al aterrizar (%s)" % [max_live, str(landed_spins)]
	)

	# 7. Aterrizar a mitad de una vuelta: se cae y pierde el nitro.
	r.add_nitro(Rider.NITRO_MAX)
	r.position.y += 0.5
	r.vertical_speed = 9.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	r.trick_angle = 1.0
	_set_action(&"p1_a", true)
	await _wait_until_state(&"fallen", 3.0)
	_set_action(&"p1_a", false)
	_check(_state() == &"fallen" and r.nitro == 0.0, "aterrizar a mitad de una vuelta: se cae y pierde el nitro")
	await _mash_until_standing(12.0, 6.0)

	# 8. Trucos SOLTAR. Soltar justo antes de tocar el agua, a mitad de un
	# truco: aterriza bien y cuenta solo lo completado (lo que mostraba el
	# contador).
	var saved_style := Rider.trick_style
	Rider.trick_style = Rider.TrickStyle.SOLTAR
	landed_spins.clear()
	r.position.y += 1.0
	r.vertical_speed = 9.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	var shown := 0
	var partial := false
	for i in int(4.0 * FPS):
		await process_frame
		if _state() != &"airborne" or r.time_to_land() < 0.05:
			break
		shown = r.live_spins
		partial = r.trick_angle > 0.0 and fmod(r.trick_units_now(), 1.0) > 0.05
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 3.0)
	_check(_state() == &"riding", "soltar justo antes de tocar el agua: aterriza bien (aunque el truco iba a medias: %s)" % partial)
	_check(
		shown >= 1 and landed_spins.size() == 1 and landed_spins[0] == shown,
		"cuenta lo que mostraba el contador al soltar (%d, %s)" % [shown, str(landed_spins)]
	)

	# 9. Trucos TERMINAR. Soltar a mitad de un truco justo antes de tocar el
	# agua: no llega a terminarlo y se cae.
	Rider.trick_style = Rider.TrickStyle.TERMINAR
	r.position.y += 1.0
	r.vertical_speed = 9.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	var late := false
	for i in int(4.0 * FPS):
		await process_frame
		if _state() != &"airborne":
			break
		late = r.trick_angle > 0.0 and fmod(r.trick_units_now(), 1.0) > 0.3
		if late and r.time_to_land() < 0.05:
			break
	_set_action(&"p1_a", false)
	await _wait(1.0)
	_check(late and _state() == &"fallen", "trucos TERMINAR: soltar a mitad de un truco justo antes del agua te tira")
	await _mash_until_standing(12.0, 6.0)

	# 10. Trucos LIMPIO_JUSTO. Soltar a mitad de un truco justo antes de
	# tocar el agua: no se cae, pero aterriza justo (pierde velocidad).
	Rider.trick_style = Rider.TrickStyle.LIMPIO_JUSTO
	var sloppy := [0]
	r.sloppy_landed.connect(func() -> void: sloppy[0] += 1)
	landed_spins.clear()
	await _wait(1.0)
	r.position.y += 1.0
	r.vertical_speed = 9.0
	r.speed = 10.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	var air_speed := 0.0
	late = false
	for i in int(4.0 * FPS):
		await process_frame
		if _state() != &"airborne":
			break
		air_speed = r.speed
		late = r.trick_angle > 0.0 and fmod(r.trick_units_now(), 1.0) > 0.3
		if late and r.time_to_land() < 0.05:
			break
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 3.0)
	_check(
		late and _state() == &"riding" and sloppy[0] == 1 and not r.last_landing_clean,
		"trucos LIMPIO_JUSTO: soltar justo antes del agua a mitad de un truco no te tira, pero es justo"
	)
	_check(r.speed < air_speed * 0.8, "el aterrizaje justo frena (%.1f -> %.1f m/s)" % [air_speed, r.speed])
	_check(landed_spins.size() == 1, "y los trucos completados igual cuentan (%s)" % str(landed_spins))
	await _wait(1.0)

	# 11. Trucos LIMPIO_JUSTO. Soltar con tiempo: el truco termina en el aire y
	# el aterrizaje es limpio.
	r.position.y += 1.0
	r.vertical_speed = 12.0
	r.grounded = false
	r.can_trick = true
	r.state_machine.transition_to(&"airborne")
	_set_action(&"p1_a", true)
	for i in int(2.0 * FPS):
		await process_frame
		if r.live_spins >= 1 or _state() != &"airborne":
			break
	_set_action(&"p1_a", false)
	await _wait_until_state(&"riding", 4.0)
	_check(
		_state() == &"riding" and sloppy[0] == 1 and r.last_landing_clean,
		"trucos LIMPIO_JUSTO: soltar con tiempo es un aterrizaje limpio"
	)
	Rider.trick_style = saved_style

	m.queue_free()
	await process_frame
	GameSettings.player_count = saved[0]
	GameSettings.bot_count = saved[1]
