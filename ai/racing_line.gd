class_name RacingLine
extends RefCounted
## La línea más corta de una pista, dentro de la banda de ±`lane` metros: como
## una banda elástica que se tensa por adentro de la pista (corta las curvas por
## adentro y va derecho en las rectas). Es la línea que hacen los que mejor
## juegan (en los registros, la persona hacía ~745 m por vuelta en el
## Archipiélago y los bots que no la seguían, ~850 m).
##
## Se calcula una vez por pista: desvío lateral cada STEP metros.

const STEP := 4.0
const ITERATIONS := 600

static var _cache: Dictionary = {}

var laterals := PackedFloat32Array()
var count: int = 0


static func for_track(track: TrackSpace, lane: float) -> RacingLine:
	var key := "%d:%.1f" % [track.get_instance_id(), lane]
	if not _cache.has(key):
		_cache[key] = RacingLine.new(track, lane)
	return _cache[key]


func _init(track: TrackSpace, lane: float) -> void:
	count = maxi(int(track.length() / STEP), 16)
	var centers := PackedVector2Array()
	var normals := PackedVector2Array()
	centers.resize(count)
	normals.resize(count)
	laterals.resize(count)
	for i in count:
		var a := i * TAU / count
		var c := track.position_at(a, 0.0)
		var side := track.position_at(a, 1.0) - c
		centers[i] = Vector2(c.x, c.z)
		normals[i] = Vector2(side.x, side.z).normalized()
		laterals[i] = 0.0
	# Cada punto va al medio de sus vecinos (sobre su recta de costado), sin
	# salirse de la banda: así se tensa hasta la línea más corta.
	for it in ITERATIONS:
		for i in count:
			var ip := (i - 1 + count) % count
			var inn := (i + 1) % count
			var prev := centers[ip] + normals[ip] * laterals[ip]
			var next := centers[inn] + normals[inn] * laterals[inn]
			var mid := (prev + next) * 0.5
			laterals[i] = clampf((mid - centers[i]).dot(normals[i]), -lane, lane)


## Desvío lateral de la línea en ese ángulo de la pista.
func lateral_at(angle: float) -> float:
	var f := wrapf(angle, 0.0, TAU) / TAU * count
	var i := int(f) % count
	var j := (i + 1) % count
	return lerpf(laterals[i], laterals[j], f - floorf(f))
