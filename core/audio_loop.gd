class_name SfxLoop
extends RefCounted
## Carga un .wav y lo deja repitiéndose sin cortes (para el mar de fondo y el derrape).


static func make(path: String) -> AudioStreamWAV:
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		return null
	stream = stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream
