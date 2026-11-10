extends SceneTree
## Compara carreras de bots con y sin handicap (no es un test que falle: mide).
##   godot --headless --fixed-fps 60 --script res://tests/bot_balance.gd
## Corre RACES carreras de cada tipo con 3 bots (Fácil, Normal, Difícil) y
## muestra la diferencia de tiempo entre el primero y el último.

const FPS := 60
const RACES := 4
const LAPS := 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	GameSettings.load_settings()
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	var results := {}
	for handicap in [false, true]:
		var spreads: Array[float] = []
		var lines: Array[String] = []
		for i in RACES:
			var times: Dictionary = await _race(handicap, 100 + i)
			var vals: Array = times.values()
			var spread: float = vals.max() - vals.min()
			spreads.append(spread)
			lines.append(
				"    carrera %d: Fácil %.1f  Normal %.1f  Difícil %.1f  -> diferencia %.1f s"
				% [i + 1, times["Fácil"], times["Normal"], times["Difícil"], spread]
			)
		var avg := 0.0
		for s in spreads:
			avg += s
		avg /= spreads.size()
		results[handicap] = avg
		print("%s handicap:" % ("CON" if handicap else "SIN"))
		for l in lines:
			print(l)
		print("    promedio de diferencia primero-último: %.1f s" % avg)
	print("")
	print(
		"RESULTADO: sin handicap %.1f s, con handicap %.1f s (%+.0f%%)"
		% [results[false], results[true], (results[true] / results[false] - 1.0) * 100.0]
	)
	quit(0)


## Corre una carrera y devuelve {nombre: tiempo}.
func _race(handicap: bool, seed_value: int) -> Dictionary:
	seed(seed_value)
	var config := RaceConfig.new()
	config.laps = LAPS
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for level in 3:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.display_name = AIDifficulty.NAMES[level]
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(level)
		config.slots.append(slot)
	var main: Node = load("res://main.tscn").instantiate()
	var race := main.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = handicap
	(main.get_node("WaveManager") as WaveManager).random_seed = seed_value
	root.add_child(main)
	await process_frame
	race.skip_countdown()
	var frames := 0
	while race.state != RaceManager.State.FINISHED and frames < 300 * FPS:
		await process_frame
		frames += 1
	var times := {}
	for r in race.racers:
		times[r.display_name] = race.finish_times.get(r, 300.0)
	main.queue_free()
	await process_frame
	await process_frame
	return times
