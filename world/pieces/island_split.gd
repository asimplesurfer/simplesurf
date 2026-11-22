class_name IslandSplitPiece
extends MapPiece
## Divide islas: un corte dibujado como camino abierto (puntos y manijas
## Bézier, como la pista pero sin cerrar). Toda isla tropical que cruce queda
## partida en islas independientes, con mar en el medio (cada parte tiene su
## playa, su selva y sus palmeras). Si el corte entra desde el mar pero no la
## cruza entera, le hace una bahía; si queda todo adentro de la isla, no hace
## nada.
##
## Las islas buscan los cortes en Course.pieces al prepararse (ver
## TropicalIslandPiece.prepare): no importa en qué orden estén en el mapa.

const REQUIRED := ["path"]

## Cómo se ve en el editor de mapas (ver MapPiece.editor_entry).
const EDITOR := {
	"name": "Dividir isla", "place": "path", "what": "un corte",
	"hint": "Dibujá una línea que cruce una isla tropical de mar a mar (clic: punto, arrastrar: curva). Enter o doble clic para terminar: la isla queda partida en dos.",
	"fields": {"width": "Ancho del mar en el medio (m)"},
}

## Camino del corte: [[x, z], {"p": [x, z], "in": [..], "out": [..]}, ...].
var path: Array = []
## Ancho del mar que queda entre las partes (m, de orilla a orilla).
var width: float = 14.0

var _channel: Array[PackedVector2Array] = []
var _ready_channel: bool = false


## La franja de mar del corte (una o más figuras cerradas).
func channel() -> Array[PackedVector2Array]:
	if not _ready_channel:
		_ready_channel = true
		var line := BezierShape.parse(path).polyline(3.0)
		if line.size() >= 2:
			for poly in Geometry2D.offset_polyline(line, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
				_channel.append(poly)
	return _channel


func prepare(_course: Course) -> void:
	if channel().is_empty():
		push_error("island_split: el corte necesita al menos 2 puntos")


## Corta una figura con todos los cortes de `pieces`. Devuelve las partes que
## quedan (vacío si el corte se la come entera).
static func cut(outline: PackedVector2Array, pieces: Array[MapPiece]) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [outline]
	for piece in pieces:
		var split := piece as IslandSplitPiece
		if split == null:
			continue
		for band in split.channel():
			var next: Array[PackedVector2Array] = []
			for part in parts:
				var pieces_left := Geometry2D.clip_polygons(part, band)
				for p in pieces_left:
					# Un agujero (el corte entero adentro de la isla) no es una
					# parte: queda la isla sin agujero.
					if _is_hole(p, pieces_left):
						continue
					if p.size() >= 3 and absf(_area(p)) > 4.0:
						next.append(p)
			parts = next
	# Las puntas del corte no quedan en ángulo: se redondean un poco.
	var rounded: Array[PackedVector2Array] = []
	for part in parts:
		rounded.append(_rounded(part, CORNER))
	return rounded


## Radio con el que se redondean las puntas que deja el corte (m).
const CORNER := 2.5


static func _rounded(p: PackedVector2Array, r: float) -> PackedVector2Array:
	var inner := Geometry2D.offset_polygon(p, -r, Geometry2D.JOIN_ROUND)
	if inner.size() != 1:
		return p
	var outer := Geometry2D.offset_polygon(inner[0], r, Geometry2D.JOIN_ROUND)
	return outer[0] if outer.size() == 1 and outer[0].size() >= 3 else p


static func _is_hole(p: PackedVector2Array, all: Array[PackedVector2Array]) -> bool:
	for other in all:
		if other != p and Geometry2D.is_point_in_polygon(p[0], other):
			return true
	return false


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5
