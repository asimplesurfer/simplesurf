class_name TrackMap
extends RefCounted
## Los datos de un mapa: el recorrido, las islas, cuántos obstáculos tiene y
## sus piezas (volcán, géiseres, cuevas...: ver world/pieces/map_piece.gd).
## Cada mapa es un archivo .json en world/maps/: agregar un mapa = agregar un
## archivo, no tocar código. Course lo lee y arma todo. El editor de mapas lee y
## escribe este mismo formato (ver world/maps/README.md).
##
## Cada mapa tiene un número fijo (`order`): es el que se guarda en la
## configuración y en los récords de contrarreloj, así que un mapa nuevo va con
## un número nuevo (el siguiente libre) y nunca se cambia el de uno que ya existe.

const FOLDER := "res://world/maps/"
## Versión del formato del archivo.
const FORMAT := 1

## Nombre interno (el del archivo) y el que se ve en el menú.
var id: String = ""
var name: String = ""
## Lugar en la lista de mapas (ver arriba).
var order: int = 0
var laps: int = 3

## Recorrido: puntos (x, z) en el sentido de la carrera, con manijas Bézier
## opcionales (relativas al punto). Una manija que no está (null) es automática:
## la curva pasa suave por los puntos vecinos. Una manija (0, 0) hace esquina.
## Vacío = un anillo alrededor de la primera isla, de radio `ring_radius`.
var path: PackedVector2Array = PackedVector2Array()
var handles_in: Array = []
var handles_out: Array = []
## Cuánto se redondean las curvas del recorrido (pasadas de suavizado).
var smoothing: int = 60
var ring_radius: float = 82.0
## Mitad del ancho de la pista (m).
var half_width: float = 20.0
## Islas: [{x, z, radius, lighthouse, seed}]. La primera es la principal.
var islands: Array[Dictionary] = []
var ring_count: int = 10
var rock_count: int = 12
## Piezas del mapa, tal como vienen en el archivo ({"type": ..., parámetros}).
## Course arma una pieza nueva de cada una en cada carrera.
var pieces: Array[Dictionary] = []

static var _all: Array[TrackMap] = []


## Todos los mapas de la carpeta, en orden. Se leen una sola vez.
static func all() -> Array[TrackMap]:
	if _all.is_empty():
		for file in _list_files():
			var errors := PackedStringArray()
			var m := load_file(FOLDER + file, errors)
			if m == null or not errors.is_empty():
				push_error("Mapa %s: %s" % [file, "; ".join(errors)])
			if m != null:
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


## true si el recorrido es un anillo alrededor de la isla principal.
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
	if m.id.is_empty():
		m.id = file_path.get_file().get_basename()
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
	if not m.path.is_empty() and m.path.size() < 3:
		errors.append("el recorrido necesita al menos 3 puntos")
	for isl in d.get("islands", []):
		if not isl is Dictionary or not isl.has("x") or not isl.has("z") or not isl.has("radius"):
			errors.append("isla mal escrita (necesita x, z y radius): %s" % str(isl))
			continue
		m.islands.append({
			"x": float(isl.x), "z": float(isl.z), "radius": float(isl.radius),
			"lighthouse": bool(isl.get("lighthouse", false)),
			"seed": int(isl.get("seed", -1)),
		})
	if m.path.is_empty() and m.islands.is_empty():
		errors.append("un mapa sin recorrido (anillo) necesita una isla en el medio")
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
		"islands": islands, "pieces": pieces,
	}
	if path.is_empty():
		d["ring_radius"] = ring_radius
	else:
		d["path"] = path_out
		d["smoothing"] = smoothing
	return d


## Arma las piezas del mapa (nuevas, una por carrera).
func make_pieces() -> Array[MapPiece]:
	var out: Array[MapPiece] = []
	for p in pieces:
		var piece := MapPiece.create(p)
		if piece:
			out.append(piece)
	return out


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))
