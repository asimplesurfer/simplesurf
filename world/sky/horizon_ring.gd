class_name HorizonRing
extends RefCounted
## La malla del anillo de islas lejanas: dos filas de siluetas (islas bajas
## con loma, volcanes, montañas largas) alrededor del origen, a la distancia
## de Horizon.RING_DISTANCE. Muy pocos triángulos; se arma una sola vez.

static var _mesh: ArrayMesh


static func build() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	# Fila de atrás: montañas largas y altas (casi del color del horizonte).
	_row(st, rng, Horizon.RING_DISTANCE + 35.0, 1.0, 9, Vector2(0.35, 0.7), Vector2(16.0, 34.0))
	# Fila de adelante: islas más chicas y separadas, con huecos de mar abierto.
	_row(st, rng, Horizon.RING_DISTANCE, 0.0, 13, Vector2(0.12, 0.3), Vector2(7.0, 20.0))
	_mesh = st.commit()
	return _mesh


## Una fila de `count` siluetas repartidas alrededor (con huecos al azar).
## width: ancho (en radianes, mín y máx). height: alto (m, mín y máx).
static func _row(st: SurfaceTool, rng: RandomNumberGenerator, radius: float, far: float, count: int,
		width: Vector2, height: Vector2) -> void:
	var a := rng.randf() * TAU
	for i in count:
		var w := rng.randf_range(width.x, width.y)
		var h := rng.randf_range(height.x, height.y)
		var kind := rng.randi() % 3
		_silhouette(st, rng, radius + rng.randf_range(-25.0, 25.0), a, w, h, kind, far)
		a += w + rng.randf_range(0.08, 0.5)


## Una silueta: un perfil (alto según el azimut) levantado desde un poco abajo
## del agua. kind 0: loma de isla; 1: volcán; 2: cordillera con picos.
static func _silhouette(st: SurfaceTool, rng: RandomNumberGenerator, radius: float, start: float,
		width: float, height: float, kind: int, far: float) -> void:
	var steps := 18
	var seed := rng.randf() * 100.0
	var prev_b := Vector3.ZERO
	var prev_t := Vector3.ZERO
	var prev_u := 0.0
	for k in steps + 1:
		var s := float(k) / steps
		var ang := start + width * s
		var edge := sin(PI * s)
		var prof: float
		match kind:
			0:
				prof = pow(edge, 0.7) * (0.85 + 0.15 * sin(s * 9.0 + seed))
			1:
				prof = pow(maxf(1.0 - absf(s - 0.5) * 2.0, 0.0), 1.4) * (1.0 + 0.04 * sin(s * 40.0))
			_:
				prof = pow(edge, 0.6) * (0.7 + 0.3 * absf(sin(s * 5.0 + seed)))
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var bottom := dir * (radius + 6.0) + Vector3.DOWN * 3.0
		var top := dir * radius + Vector3.UP * (height * prof)
		var up := clampf(prof, 0.0, 1.0)
		if k > 0:
			_v(st, prev_b, far, 0.0)
			_v(st, prev_t, far, prev_u)
			_v(st, top, far, up)
			_v(st, prev_b, far, 0.0)
			_v(st, top, far, up)
			_v(st, bottom, far, 0.0)
		prev_b = bottom
		prev_t = top
		prev_u = up


static func _v(st: SurfaceTool, p: Vector3, far: float, up: float) -> void:
	st.set_color(Color(far, up, 0.0))
	st.add_vertex(p)
