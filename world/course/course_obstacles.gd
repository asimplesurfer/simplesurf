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
		var rock := Rock.new()
		rock.radius = rng.randf_range(1.4, 2.8)
		rock.height = rock.radius * rng.randf_range(1.0, 1.6)
		rock.rock_seed = placed + 1
		rock.position = pos + Vector3(0.0, -0.6, 0.0)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		course.add_child(rock)
		course.rocks.append(rock)
		placed += 1


static func _too_close(course: Course, pos: Vector3, min_distance: float) -> bool:
	for ring in course.rings:
		if Vector2(ring.position.x - pos.x, ring.position.z - pos.z).length() < min_distance:
			return true
	for rock in course.rocks:
		if Vector2(rock.position.x - pos.x, rock.position.z - pos.z).length() < min_distance:
			return true
	return false
