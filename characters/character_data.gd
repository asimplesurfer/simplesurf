class_name CharacterData
extends Resource
## Cómo se ve un corredor: cuerpo, cara, pelo, accesorios, short y tabla.
## Todo es un índice dentro de una lista (o el peso, de 0 a 1), así se guarda
## fácil y se elige con ← → en el menú.

## Colores de piel (los últimos son de chiste).
const SKIN_COLORS := [
	Color("#f3d0b0"),
	Color("#e0ac80"),
	Color("#b97b45"),
	Color("#8a5a3b"),
	Color("#5c3a24"),
	Color("#f08a7a"),
	Color("#9aa58f"),
	Color("#7bd16a"),
	Color("#8fb8ff"),
	Color("#b58be0"),
]
const SKIN_NAMES := [
	"Clara", "Trigueña", "Morena", "Canela", "Oscura",
	"Insolado", "Zombi", "Alien verde", "Alien azul", "Violeta",
]
const SHORTS_COLORS := [
	Color("#14306b"),
	Color("#d23c3c"),
	Color("#f2b630"),
	Color("#1f9e8f"),
	Color("#8a4fd1"),
	Color("#222222"),
	Color("#f07ab0"),
	Color("#4fb84a"),
	Color("#f0f0f0"),
]
const SHORTS_NAMES := ["Azul", "Rojo", "Amarillo", "Turquesa", "Violeta", "Negro", "Rosa", "Verde", "Blanco"]
const SHORTS_PATTERNS := ["Liso", "Flores", "Lunares", "Rayas", "Hawaiano"]
const BOARD_COLORS := [
	Color("#fff1c9"),
	Color(1.0, 0.86, 0.3),
	Color(0.95, 0.95, 0.95),
	Color(0.35, 0.75, 1.0),
	Color(1.0, 0.5, 0.35),
	Color(0.55, 0.9, 0.4),
	Color(0.9, 0.5, 1.0),
	Color("#2b2b2b"),
]
const BOARD_NAMES := ["Crema", "Amarilla", "Blanca", "Celeste", "Naranja", "Verde", "Lila", "Negra"]
const BOARD_DESIGNS := ["Lisa", "Dos rayas", "Raya al medio", "Punta pintada", "Lunares"]

const HEAD_SHAPES := ["Normal", "Ancha", "Alargada", "Chata"]
## Escala de la cabeza (x, y, z) para cada forma (el tamaño va aparte, en la barra).
const HEAD_SCALES := [
	Vector3(1.0, 1.0, 1.0),
	Vector3(1.3, 0.92, 1.1),
	Vector3(0.85, 1.28, 0.92),
	Vector3(1.15, 0.78, 1.15),
]
const HAIR_STYLES := [
	"Pelado", "Rapado", "Melena surfer", "Rulos", "Cresta", "Pinchos", "Moño", "Peluquín",
]
const HAIR_COLORS := [
	Color("#f0c13a"),
	Color("#7a4a24"),
	Color("#222222"),
	Color("#d2552b"),
	Color("#e8e8e8"),
	Color("#ff7ac2"),
	Color("#3fd16a"),
	Color("#3b7bff"),
]
const HAIR_COLOR_NAMES := ["Rubio", "Castaño", "Negro", "Colorado", "Canoso", "Rosa", "Verde", "Azul"]
const EYES := ["Puntitos", "Saltones", "Bizcos", "Dormidos", "Desparejos"]
const GLASSES := ["Ninguno", "De sol", "Antiparras", "Redondos", "Monóculo"]
const NOSES := ["Ninguna", "Botón", "Narigón", "De payaso", "Larga"]
const MOUTHS := ["Ninguna", "Sonrisa", "De costado", "Abierta", "Dientes de conejo", "Mueca"]
const FACE_EXTRAS := ["Nada", "Bigote", "Barba", "Uniceja", "Cejas gruesas"]
const EARS := ["Sin orejas", "Normales", "Grandes", "Dumbo"]
const NECKLACES := ["Nada", "Perlas", "Collar de flores", "Cadena de oro"]

## Estilos armados (el primero es el surfista original del modelo 3D).
const PRESET_NAMES := ["Surfista rubio", "Abuelo playero", "Payaso", "Nerd", "Alien", "Insolado"]
const PRESETS := [
	{"weight": 0.0, "muscle": 1.0, "head_size": 0.5, "skin": 2, "head": 0, "hair": 2, "hair_color": 0,
		"eyes": 0, "glasses": 1, "nose": 0, "mouth": 2, "extra": 0, "ears": 0, "neck": 1, "shorts": 0,
		"shorts_pattern": 1, "board": 0, "board_design": 1},
	{"weight": 0.9, "muscle": 0.1, "head_size": 0.45, "skin": 0, "head": 0, "hair": 7, "hair_color": 4,
		"eyes": 3, "glasses": 3, "nose": 2, "mouth": 1, "extra": 1, "ears": 2, "neck": 0, "shorts": 1,
		"shorts_pattern": 4, "board": 2, "board_design": 0},
	{"weight": 0.6, "muscle": 0.3, "head_size": 0.85, "skin": 0, "head": 1, "hair": 3, "hair_color": 3,
		"eyes": 1, "glasses": 0, "nose": 3, "mouth": 3, "extra": 0, "ears": 3, "neck": 2, "shorts": 2,
		"shorts_pattern": 2, "board": 6, "board_design": 4},
	{"weight": 0.35, "muscle": 0.0, "head_size": 0.7, "skin": 1, "head": 2, "hair": 1, "hair_color": 2,
		"eyes": 2, "glasses": 3, "nose": 1, "mouth": 4, "extra": 3, "ears": 2, "neck": 0, "shorts": 3,
		"shorts_pattern": 3, "board": 3, "board_design": 2},
	{"weight": 0.2, "muscle": 0.4, "head_size": 0.95, "skin": 7, "head": 2, "hair": 0, "hair_color": 6,
		"eyes": 1, "glasses": 0, "nose": 0, "mouth": 3, "extra": 0, "ears": 0, "neck": 0, "shorts": 4,
		"shorts_pattern": 2, "board": 5, "board_design": 3},
	{"weight": 0.75, "muscle": 0.6, "head_size": 0.6, "skin": 5, "head": 1, "hair": 6, "hair_color": 3,
		"eyes": 2, "glasses": 4, "nose": 2, "mouth": 5, "extra": 4, "ears": 3, "neck": 3, "shorts": 6,
		"shorts_pattern": 1, "board": 4, "board_design": 1},
]

## Barras (0..1). Panza: 0 = Musculoso ... 1 = Cervecero.
@export_range(0.0, 1.0) var weight: float = 0.0
## Músculos: 0 = flaquito ... 1 = musculoso (hombros grandes, pectorales).
@export_range(0.0, 1.0) var muscle: float = 1.0
## Tamaño de cabeza: 0 = cabecita ... 0.5 = normal ... 1 = cabezón.
@export_range(0.0, 1.0) var head_size: float = 0.5
@export var skin_index: int = 2
@export var shorts_index: int = 0
@export var board_index: int = 0
@export var head_index: int = 0
@export var hair_index: int = 0
@export var hair_color_index: int = 0
@export var eyes_index: int = 0
@export var glasses_index: int = 0
@export var nose_index: int = 0
@export var mouth_index: int = 1
@export var extra_index: int = 0
@export var ears_index: int = 0
@export var neck_index: int = 0
@export var shorts_pattern_index: int = 0
@export var board_design_index: int = 0

## Nombre del campo -> [propiedad, lista de opciones] (para el menú y el guardado).
## Barras: nombre -> propiedad.
const SLIDERS := {"weight": "weight", "muscle": "muscle", "head_size": "head_size"}
const FIELDS := {
	"skin": ["skin_index", SKIN_NAMES],
	"head": ["head_index", HEAD_SHAPES],
	"hair": ["hair_index", HAIR_STYLES],
	"hair_color": ["hair_color_index", HAIR_COLOR_NAMES],
	"eyes": ["eyes_index", EYES],
	"glasses": ["glasses_index", GLASSES],
	"nose": ["nose_index", NOSES],
	"mouth": ["mouth_index", MOUTHS],
	"extra": ["extra_index", FACE_EXTRAS],
	"ears": ["ears_index", EARS],
	"neck": ["neck_index", NECKLACES],
	"shorts": ["shorts_index", SHORTS_NAMES],
	"shorts_pattern": ["shorts_pattern_index", SHORTS_PATTERNS],
	"board": ["board_index", BOARD_NAMES],
	"board_design": ["board_design_index", BOARD_DESIGNS],
}


func skin_color() -> Color:
	return SKIN_COLORS[posmod(skin_index, SKIN_COLORS.size())]


func shorts_color() -> Color:
	return SHORTS_COLORS[posmod(shorts_index, SHORTS_COLORS.size())]


func board_color() -> Color:
	return BOARD_COLORS[posmod(board_index, BOARD_COLORS.size())]


func hair_color() -> Color:
	return HAIR_COLORS[posmod(hair_color_index, HAIR_COLORS.size())]


func head_scale() -> Vector3:
	return HEAD_SCALES[posmod(head_index, HEAD_SCALES.size())]


## Índice del campo (ver FIELDS), siempre dentro de la lista.
func get_option(field: String) -> int:
	var f: Array = FIELDS[field]
	return posmod(int(get(f[0])), (f[1] as Array).size())


## Pasa a la opción siguiente / anterior del campo.
func step_option(field: String, step: int) -> void:
	var f: Array = FIELDS[field]
	set(f[0], posmod(int(get(f[0])) + step, (f[1] as Array).size()))


func option_name(field: String) -> String:
	return (FIELDS[field][1] as Array)[get_option(field)]


func apply_preset(index: int) -> void:
	var p: Dictionary = PRESETS[posmod(index, PRESETS.size())]
	for slider in SLIDERS:
		set(SLIDERS[slider], float(p.get(slider, get(SLIDERS[slider]))))
	for field in FIELDS:
		set(FIELDS[field][0], int(p.get(field, 0)))


func to_dict() -> Dictionary:
	var d := {}
	for slider in SLIDERS:
		d[slider] = get(SLIDERS[slider])
	for field in FIELDS:
		d[field] = get_option(field)
	return d


static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	for slider in SLIDERS:
		if d.has(slider):
			c.set(SLIDERS[slider], clampf(float(d[slider]), 0.0, 1.0))
	for field in FIELDS:
		if d.has(field):
			c.set(FIELDS[field][0], int(d[field]))
	return c


## Personaje al azar (para los bots y el botón "Sorpresa"): cualquier
## combinación, así salen personajes de todo tipo (y bastante feos).
static func random(rng: RandomNumberGenerator) -> CharacterData:
	var c := CharacterData.new()
	c.weight = rng.randf()
	c.muscle = rng.randf()
	c.head_size = rng.randf_range(0.2, 1.0)
	for field in FIELDS:
		var options: Array = FIELDS[field][1]
		c.set(FIELDS[field][0], rng.randi() % options.size())
	return c


## Personaje por defecto para cada jugador (un estilo distinto cada uno).
static func default_for_player(player_index: int) -> CharacterData:
	var c := CharacterData.new()
	c.apply_preset([0, 2, 3, 4][player_index % 4])
	return c
