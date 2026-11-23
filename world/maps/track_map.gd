class_name TrackMap
extends RefCounted
## Los datos de un mapa: el recorrido, cuántos obstáculos tiene y sus piezas
## (islas, géiseres, cuevas...: ver world/pieces/map_piece.gd).
## Cada mapa es un archivo .json en world/maps/: agregar un mapa = agregar un
## archivo, no tocar código. Course lo lee y arma todo. El editor de mapas lee y
## escribe este mismo formato (ver world/maps/README.md).
##
## Cada mapa tiene dos datos que lo identifican:
## - `id`: su nombre interno (el del archivo). Con él se guardan el mapa elegido
##   y los récords de contrarreloj, así que reordenar los mapas no los mezcla.
## - `order`: su número (el lugar en el menú). Se puede cambiar. Es el
##   salvavidas: si le cambian el nombre al archivo, los datos guardados se
##   encuentran por el número y pasan al nombre nuevo solos (ver find y
##   TimeTrial). Dos mapas no pueden tener el mismo número.

const FOLDER := "res://world/maps/"
## Versión del formato del archivo.
const FORMAT := 1
## El mapa que se elige si no hay otro (la primera vez, o si el guardado ya no está).
const DEFAULT_ID := "archipelago"

## Nombre interno (el del archivo) y el que se ve en el menú.
var id: String = ""
var name: String = ""
## Lugar en la lista de mapas (ver arriba).
var order: int = 0
var laps: int = 3

## Recorrido: puntos (x, z) en el sentido de la carrera, con manijas Bézier
## opcionales (relativas al punto). Una manija que no está (null) es automática:
## la curva pasa suave por los puntos vecinos. Una manija (0, 0) hace esquina.
## Vacío = un anillo de radio `ring_radius` alrededor del centro del mapa
## (0, 0). Que haya una isla en el medio es opcional: se dibuja como cualquiera.
var path: PackedVector2Array = PackedVector2Array()
var handles_in: Array = []
var handles_out: Array = []
## Recta de la meta (opcional; ver PathTrack.start_strip). Vacío: la meta va
## en el primer punto del recorrido (como en los primeros mapas).
var start: Dictionary = {}
## Bifurcaciones: caminos alternativos. Cada uno sale de un punto del
## recorrido y vuelve a entrar en otro más adelante: {"from", "to": índices de
## esos puntos en `path` (from < to); "path": sus puntos; "in" / "out": sus
## manijas (como las del recorrido)}. Varios con las mismas puntas = varios
## caminos en el mismo tramo. Ver PathTrack.
var branches: Array[Dictionary] = []
## Cuánto se redondean las curvas del recorrido (pasadas de suavizado).
var smoothing: int = 60
var ring_radius: float = 82.0
## Mitad del ancho de la pista (m).
var half_width: float = 20.0
var ring_count: int = 10
var rock_count: int = 12
## Piezas del mapa, tal como vienen en el archivo ({"type": ..., parámetros}).
## Course arma una pieza nueva de cada una en cada carrera.
var pieces: Array[Dictionary] = []

static var _all: Array[TrackMap] = []


## Todos los mapas de la carpeta, en orden. Se leen una sola vez.
## Un mapa con errores no se carga (así un archivo mal subido nunca rompe el
## juego); el aviso queda en la consola. Antes de publicar, GitHub revisa los
## mapas (tools/validate_maps.gd) y no publica si alguno está mal.
static func all() -> Array[TrackMap]:
	if _all.is_empty():
		var orders := {}
		for file in _list_files():
			var errors := PackedStringArray()
			var m := load_file(FOLDER + file, errors)
			if m != null and orders.has(m.order):
				errors.append("el número de mapa %d ya lo usa %s" % [m.order, orders[m.order]])
			if m == null or not errors.is_empty():
				push_error("Mapa %s (no se carga): %s" % [file, "; ".join(errors)])
				continue
			orders[m.order] = file
			_all.append(m)
		_all.sort_custom(func(a: TrackMap, b: TrackMap) -> bool:
			return a.order < b.order if a.order != b.order else a.id < b.id)
	return _all


static func _list_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(FOLDER):
		# En el juego exportado algunos archivos quedan como "x.json.remap".
		var file := f.trim_suffix(".remap")
		if file.get_extension() == "json" and not out.has(file):
			out.append(file)
	return out


static func for_layout(layout: int) -> TrackMap:
	var maps := all()
	return maps[clampi(layout, 0, maps.size() - 1)]


static func count() -> int:
	return all().size()


static func names() -> Array[String]:
	var out: Array[String] = []
	for m in all():
		out.append(m.name)
	return out


## Lugar en la lista del mapa con ese id (-1 si no está).
static func index_of(map_id: String) -> int:
	var maps := all()
	for i in maps.size():
		if maps[i].id == map_id:
			return i
	return -1


## true si el recorrido es un anillo (ver `path`).
func is_ring() -> bool:
	return path.is_empty()


static func load_file(file_path: String, errors: PackedStringArray = PackedStringArray()) -> TrackMap:
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		errors.append("no se pudo leer %s" % file_path)
		return null
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		errors.append("%s no es un JSON válido" % file_path)
		return null
	var m := from_dict(data, errors)
	# El nombre del archivo manda (así renombrar el archivo no rompe nada).
	m.id = file_path.get_file().get_basename()
	if m.name.is_empty():
		m.name = m.id
	return m


static func from_dict(d: Dictionary, errors: PackedStringArray = PackedStringArray()) -> TrackMap:
	var m := TrackMap.new()
	if int(d.get("format", FORMAT)) > FORMAT:
		errors.append("el mapa es de una versión más nueva del formato (%s)" % d.format)
	m.id = str(d.get("id", ""))
	m.name = str(d.get("name", m.id))
	m.order = int(d.get("order", 0))
	m.laps = int(d.get("laps", 3))
	m.half_width = float(d.get("half_width", 20.0))
	m.ring_radius = float(d.get("ring_radius", 82.0))
	m.smoothing = int(d.get("smoothing", 60))
	m.ring_count = int(d.get("ring_count", 10))
	m.rock_count = int(d.get("rock_count", 12))
	for node in d.get("path", []):
		# Un punto es [x, z] (manijas automáticas) o {"p": [x, z], "in": [dx, dz], "out": [dx, dz]}.
		if node is Array:
			m.path.append(Vector2(float(node[0]), float(node[1])))
			m.handles_in.append(null)
			m.handles_out.append(null)
		elif node is Dictionary and node.has("p"):
			m.path.append(_vec(node.p))
			m.handles_in.append(_vec(node["in"]) if node.get("in") != null else null)
			m.handles_out.append(_vec(node["out"]) if node.get("out") != null else null)
		else:
			errors.append("punto del recorrido mal escrito: %s" % str(node))
	var st: Variant = d.get("start")
	if st is Dictionary and not (st as Dictionary).is_empty():
		for key in ["x", "z", "angle"]:
			if not (st as Dictionary).has(key):
				errors.append("a la recta de la meta le falta \"%s\"" % key)
		m.start = st
	if not m.path.is_empty() and m.path.size() < (1 if not m.start.is_empty() else 3):
		errors.append("el recorrido necesita al menos 3 puntos")
	var spans: Array[Vector2i] = []
	for i in (d.get("branches", []) as Array).size():
		var bd: Variant = d.branches[i]
		var label := "el camino alternativo %d" % (i + 1)
		if not bd is Dictionary:
			errors.append("%s está mal escrito" % label)
			continue
		var br := {"from": int(bd.get("from", -1)), "to": int(bd.get("to", -1)),
			"path": PackedVector2Array(), "in": [], "out": []}
		for node in bd.get("path", []):
			if node is Array:
				br.path.append(Vector2(float(node[0]), float(node[1])))
				br["in"].append(null)
				br["out"].append(null)
			elif node is Dictionary and node.has("p"):
				br.path.append(_vec(node.p))
				br["in"].append(_vec(node["in"]) if node.get("in") != null else null)
				br["out"].append(_vec(node["out"]) if node.get("out") != null else null)
			else:
				errors.append("punto de %s mal escrito: %s" % [label, str(node)])
		if m.path.is_empty():
			errors.append("%s necesita un recorrido (no va en una pista anillo)" % label)
			continue
		if br.from < 0 or br.to >= m.path.size() or br.from >= br.to:
			errors.append("%s tiene que salir de un punto del recorrido y volver en uno de más adelante" % label)
			continue
		if (br.path as PackedVector2Array).is_empty():
			errors.append("%s no tiene puntos" % label)
			continue
		var span := Vector2i(br.from, br.to)
		for other in spans:
			if other != span and span.x < other.y and other.x < span.y:
				errors.append("%s se cruza con otro tramo de caminos: los que se pisan tienen que salir y volver de los mismos puntos" % label)
				break
		spans.append(span)
		m.branches.append(br)
	var round_islands: Variant = d.get("islands")
	if round_islands is Array and not (round_islands as Array).is_empty():
		errors.append("las islas redondas ya no existen: las islas son piezas \"tropical_island\"")
	for p in d.get("pieces", []):
		if not p is Dictionary:
			errors.append("pieza mal escrita: %s" % str(p))
			continue
		# Se prueba armarla para avisar ya si algo está mal.
		MapPiece.create(p, errors)
		m.pieces.append(p)
	return m


func to_dict() -> Dictionary:
	var path_out := []
	for i in path.size():
		if handles_in[i] == null and handles_out[i] == null:
			path_out.append([path[i].x, path[i].y])
		else:
			var node := {"p": [path[i].x, path[i].y]}
			if handles_in[i] != null:
				node["in"] = [handles_in[i].x, handles_in[i].y]
			if handles_out[i] != null:
				node["out"] = [handles_out[i].x, handles_out[i].y]
			path_out.append(node)
	var d := {
		"format": FORMAT, "id": id, "name": name, "order": order, "laps": laps,
		"half_width": half_width, "ring_count": ring_count, "rock_count": rock_count,
		"pieces": pieces,
	}
	if path.is_empty():
		d["ring_radius"] = ring_radius
	else:
		d["path"] = path_out
		d["smoothing"] = smoothing
		if not start.is_empty():
			d["start"] = start
		if not branches.is_empty():
			var out := []
			for br in branches:
				var pts := []
				for i in (br.path as PackedVector2Array).size():
					var q: Vector2 = br.path[i]
					var hi: Variant = br["in"][i]
					var ho: Variant = br["out"][i]
					if hi == null and ho == null:
						pts.append([q.x, q.y])
					else:
						var node := {"p": [q.x, q.y]}
						if hi != null:
							node["in"] = [hi.x, hi.y]
						if ho != null:
							node["out"] = [ho.x, ho.y]
						pts.append(node)
				out.append({"from": br.from, "to": br.to, "path": pts})
			d["branches"] = out
	return d


## Arma las piezas del mapa (nuevas, una por carrera).
func make_pieces() -> Array[MapPiece]:
	var out: Array[MapPiece] = []
	for p in pieces:
		var piece := MapPiece.create(p)
		if piece:
			out.append(piece)
	return out


# ------------------------------------------------------------- identidad

## Busca un mapa por su nombre interno y, si no está (le cambiaron el nombre
## al archivo), por su número. Devuelve su lugar en la lista, o el del mapa
## por defecto si no aparece ninguno de los dos.
static func find(map_id: String, map_order: int = -1) -> int:
	var i := index_of(map_id)
	if i >= 0:
		return i
	var maps := all()
	for k in maps.size():
		if maps[k].order == map_order:
			return k
	return default_index()


## Lugar en la lista del mapa por defecto (el archipiélago, o el primero).
static func default_index() -> int:
	return maxi(index_of(DEFAULT_ID), 0)


# ------------------------------------------------------- forma de la pista

## La pista de este mapa (las coordenadas de carrera).
func make_track() -> TrackSpace:
	if is_ring():
		return TrackSpace.new(ring_radius, half_width)
	return PathTrack.new(path, half_width, handles_in, handles_out, smoothing, start, branches)


## Separación entre los puntos de la huella (m).
const SHAPE_STEP := 6.0
## Cuánto se puede mover la pista (m) y seguir siendo "la misma" para los récords.
const SHAPE_TOLERANCE := 3.0

var _shape: Dictionary = {}


## La huella de la pista: un dibujo chico de la línea central (un punto cada
## SHAPE_STEP metros, desde la meta), las vueltas y el ancho. Va guardada con
## los récords de contrarreloj: un récord vale solo en la pista donde se hizo
## (ver same_shape). No cuenta islas, piezas, rocas ni aros.
func track_shape() -> Dictionary:
	if _shape.is_empty():
		var track := make_track()
		var total := track.length()
		var n := maxi(int(total / SHAPE_STEP), 16)
		var pts := PackedVector2Array()
		for i in n:
			var p := track.position_at(TAU * i / n)
			pts.append(Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))
		_shape = {"points": pts, "length": snappedf(total, 0.1), "laps": laps, "half_width": half_width}
		# Los caminos alternativos también son parte de la pista.
		if track is PathTrack and not (track as PathTrack).branches.is_empty():
			var bs := []
			for b in (track as PathTrack).branches:
				var bp := PackedVector2Array()
				var k := maxi(int(b.length / SHAPE_STEP), 2)
				for i in k + 1:
					var q := (track as PathTrack).branch_position(b, b.length * i / k)
					bp.append(Vector2(snappedf(q.x, 0.1), snappedf(q.z, 0.1)))
				bs.append(bp)
			_shape["branches"] = bs
	return _shape


## true si las dos huellas son la misma pista: mismas vueltas y ancho, la meta
## en el mismo lugar y mirando para el mismo lado, y ningún punto de una más
## lejos que SHAPE_TOLERANCE de la otra (así un retoque chiquito en el editor
## no cuenta como pista nueva).
static func same_shape(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("laps", -1)) != int(b.get("laps", -2)):
		return false
	if absf(float(a.get("half_width", 0.0)) - float(b.get("half_width", 0.0))) > 0.5:
		return false
	var pa: PackedVector2Array = a.get("points", PackedVector2Array())
	var pb: PackedVector2Array = b.get("points", PackedVector2Array())
	if pa.size() < 2 or pb.size() < 2:
		return false
	if pa[0].distance_to(pb[0]) > SHAPE_TOLERANCE:
		return false
	var la := float(a.get("length", 0.0))
	var lb := float(b.get("length", 0.0))
	if absf(la - lb) > maxf(la, lb) * 0.05:
		return false
	if (pa[1] - pa[0]).normalized().dot((pb[1] - pb[0]).normalized()) < 0.8:
		return false
	if not (_farthest(pa, pb) <= SHAPE_TOLERANCE and _farthest(pb, pa) <= SHAPE_TOLERANCE):
		return false
	# Caminos alternativos: los mismos, en el mismo orden y casi en el mismo lugar.
	var ba: Array = a.get("branches", [])
	var bb: Array = b.get("branches", [])
	if ba.size() != bb.size():
		return false
	for i in ba.size():
		var la2: PackedVector2Array = ba[i]
		var lb2: PackedVector2Array = bb[i]
		if _farthest_open(la2, lb2) > SHAPE_TOLERANCE or _farthest_open(lb2, la2) > SHAPE_TOLERANCE:
			return false
	return true


## La mayor distancia de un punto de `a` a la línea abierta `b`.
static func _farthest_open(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if b.size() < 2:
		return INF
	var worst := 0.0
	for p in a:
		var best := INF
		for i in b.size() - 1:
			best = minf(best, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, b[i], b[i + 1])))
		worst = maxf(worst, best)
	return sqrt(worst)


## La mayor distancia de un punto de `a` a la línea (cerrada) de `b`. Las dos
## van desde la meta y tienen casi el mismo largo: para cada punto se busca
## solo en la parte de `b` que le corresponde (más o menos un octavo).
static func _farthest(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst := 0.0
	var n := b.size()
	var window := maxi(n / 8, 8)
	for k in a.size():
		var p := a[k]
		var mid := int(float(k) * n / a.size())
		var best := INF
		for j in range(mid - window, mid + window + 1):
			var i := posmod(j, n)
			var q := Geometry2D.get_closest_point_to_segment(p, b[i], b[(i + 1) % n])
			best = minf(best, p.distance_squared_to(q))
		worst = maxf(worst, best)
	return sqrt(worst)


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))
