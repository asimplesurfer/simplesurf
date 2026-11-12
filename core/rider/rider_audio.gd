class_name RiderAudio
extends Node
## Sonidos de un corredor: escucha sus señales y toca los efectos por
## AudioManager (fuertes para las personas, más bajos y por distancia para los
## bots). El derrape tiene su propio sonido que se repite mientras dura.

var rider: Rider
var _drift: AudioStreamPlayer
var _audio: Node
var _air_time: float = 0.0


func setup(p_rider: Rider) -> void:
	rider = p_rider
	_audio = get_node_or_null("/root/AudioManager")
	if _audio == null:
		return
	rider.fell.connect(func() -> void: _play("splash"))
	rider.crashed.connect(func() -> void: _play("crash"))
	rider.popped.connect(func() -> void: _play("pop"))
	rider.jumped.connect(func() -> void: _play("hop", -4.0, randf_range(0.95, 1.1)))
	rider.landed.connect(_on_landed)
	rider.ring_collected.connect(func() -> void: _play("ring", -2.0))
	rider.turbo_fired.connect(func() -> void: _play("turbo", -1.0))
	rider.wave_punched.connect(func() -> void: _play("wave_punch"))
	rider.trick_landed.connect(func(spins: int) -> void:
		_play("trick_ok", -1.0, 1.0 + 0.08 * clampi(spins - 1, 0, 4))
	)
	rider.trick_failed.connect(func() -> void: _play("trick_fail"))
	rider.drift_hit.connect(func(_victim: Rider) -> void: _play("bonk"))
	rider.mash_pressed.connect(func() -> void:
		if rider.is_human:
			_audio.play("mash", -6.0, randf_range(0.9, 1.15))
	)
	# Derrape: siseo en loop, solo para las personas (de los bots sería ruido).
	if rider.is_human:
		_drift = AudioStreamPlayer.new()
		_drift.stream = SfxLoop.make("res://assets/audio/sfx/drift_loop.wav")
		_drift.volume_db = -60.0
		add_child(_drift)


func _play(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_audio.play_for(rider, sfx_name, volume_db, pitch)


func _on_landed() -> void:
	# Solo si estuvo un rato en el aire (el saltito no salpica tanto).
	if _air_time > 0.35:
		_play("land", -4.0)


func _process(delta: float) -> void:
	if rider == null:
		return
	_air_time = 0.0 if rider.grounded else _air_time + delta
	if _drift and _drift.stream:
		var drifting := rider.drift_side != 0 and rider.grounded
		var target := -8.0 if drifting else -60.0
		_drift.volume_db = lerpf(_drift.volume_db, target, 1.0 - exp(-12.0 * delta))
		if drifting and not _drift.playing:
			_drift.play()
		elif not drifting and _drift.playing and _drift.volume_db < -50.0:
			_drift.stop()
