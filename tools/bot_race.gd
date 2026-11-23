extends SceneTree
## Carrera de bots sin pantalla, para balancear la IA. Guarda el mismo registro
## que se descarga al terminar una carrera (RaceRecorder), así se compara con
## los de las personas.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/bot_race.gd -- \
##       mapa=tropical vueltas=2 bots=4 nivel=4 semilla=1 salida=/tmp/bots.json
##
## nivel: 0 Fácil .. 4 Imposible. Sin handicap (son todos bots).

const FPS := 60


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if root.get_node_or_null("AudioManager") == null:
		var audio: Node = load("res://autoload/audio_manager.gd").new()
		audio.name = "AudioManager"
		root.add_child(audio)
	var args := {"mapa": "tropical", "vueltas": "2", "bots": "4", "nivel": "4", "semilla": "1", "salida": "user://bots.json"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	seed(int(args.semilla))
	GameSettings.jump_style = GameSettings.JumpStyle.WAVES
	GameSettings.wave_mode = GameSettings.WaveMode.SURGES
	var layout := TrackMap.index_of(args.mapa)
	GameSettings.track_layout = layout
	var config := RaceConfig.new()
	config.layout = layout
	config.laps = int(args.vueltas)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.semilla)
	for i in int(args.bots):
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.player_index = -1
		slot.display_name = "Bot %d" % (i + 1)
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(int(args.nivel))
		config.slots.append(slot)
	var main: Node = load("res://main.tscn").instantiate()
	var race := main.get_node("RaceManager") as RaceManager
	race.config = config
	race.catchup_enabled = false
	root.add_child(main)
	await process_frame
	await process_frame
	race.skip_countdown()
	var frames := 0
	var limit := int(150.0 * config.laps * FPS)
	while race.finish_times.size() < race.racers.size() and frames < limit:
		await physics_frame
		frames += 1
	var text := JSON.stringify(race.recorder.to_dict())
	var f := FileAccess.open(args.salida, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	for r in race.racers:
		print("%s: %s" % [r.display_name, "%.1f s" % race.finish_times[r] if race.finish_times.has(r) else "no llegó"])
	quit(0)
