class_name CourseObstacles
extends RefCounted
## Reparte los círculos de nitro y las rocas por la pista (con una semilla fija:
## el mismo mapa siempre tiene los mismos obstáculos), lejos de la largada y sin
## pegarse entre sí.


static func place(course: Course, ring_count: int, rock_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = course.layout_seed
	var lane := course.half_width - 5.0

	for i in ring_count:
		var angle := TAU * (i + 0.5) / ring_count + rng.randf_range(-0.15, 0.15)
		angle = wrapf(angle, -PI, PI)
		if course.in_start_zone(angle):
			angle += 0.6
		var ring := NitroRing.new()
		ring.position = course.track.position_at(angle, rng.randf_range(-lane, lane))
		ring.rotation.y = course.track.heading_at(angle)
		course.add_child(ring)
		course.rings.append(ring)

	var placed := 0
	var attempts := 0
	while placed < rock_count and attempts < 500:
		attempts += 1
		var angle := rng.randf_range(-PI, PI)
		if course.in_start_zone(angle):
			continue
		var pos := course.track.position_at(angle, rng.randf_range(-lane, lane))
		if _too_close(course, pos, 10.0):
			continue
		_add_rock(course, rng, pos, placed + 1)
		placed += 1

	# Caminos alternativos: aros y rocas en la misma proporción que la
	# principal (según su largo). Van después, así los mapas sin bifurcaciones
	# siguen con los obstáculos de siempre.
	var track := course.track as PathTrack
	if track == null:
		return
	for b in track.branches:
		var share := b.length / maxf(track.length(), 1.0)
		var rings_here := roundi(ring_count * share)
		for i in rings_here:
			var s := b.length * (i + 0.5) / rings_here + rng.randf_range(-6.0, 6.0)
			var ring := NitroRing.new()
			ring.position = track.branch_position(b, s, rng.randf_range(-lane, lane))
			var d := track.branch_position(b, s + 1.0) - track.branch_position(b, s)
			ring.rotation.y = atan2(-d.x, -d.z)
			course.add_child(ring)
			course.rings.append(ring)
		var rocks_here := roundi(rock_count * share)
		var done := 0
		var tries := 0
		while done < rocks_here and tries < 200:
			tries += 1
			# Lejos de las puntas (ahí se abre de la principal).
			var s := rng.randf_range(25.0, maxf(b.length - 25.0, 26.0))
			var pos := track.branch_position(b, s, rng.randf_range(-lane, lane))
			if _too_close(course, pos, 10.0):
				continue
			_add_rock(course, rng, pos, course.rocks.size() + 1)
			done += 1


static func _add_rock(course: Course, rng: RandomNumberGenerator, pos: Vector3, rock_seed: int) -> void:
	var rock := Rock.new()
	rock.radius = rng.randf_range(1.4, 2.8)
	rock.height = rock.radius * rng.randf_range(1.0, 1.6)
	rock.rock_seed = rock_seed
	rock.position = pos + Vector3(0.0, -0.6, 0.0)
	rock.rotation.y = rng.randf_range(0.0, TAU)
	course.add_child(rock)
	course.rocks.append(rock)


static func _too_close(course: Course, pos: Vector3, min_distance: float) -> bool:
	for ring in course.rings:
		if Vector2(ring.position.x - pos.x, ring.position.z - pos.z).length() < min_distance:
			return true
	for rock in course.rocks:
		if Vector2(rock.position.x - pos.x, rock.position.z - pos.z).length() < min_distance:
			return true
	return false
