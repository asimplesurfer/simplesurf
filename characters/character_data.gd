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
	Color("#e8892c"),
]
const SKIN_NAMES := [
	"Clara", "Trigueña", "Morena", "Canela", "Oscura",
	"Insolado", "Zombi", "Alien verde", "Alien azul", "Violeta", "Bronceado",
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
const SHORTS_PATTERNS := [
	"Liso", "Flores", "Lunares", "Rayas", "Hawaiano", "Tie-dye", "Tres franjas", "Cuadros", "Olas",
	"Rayas verticales", "Estrellas", "Llamas", "Camuflaje", "Zigzag", "Flores grandes", "Franjas al costado",
]
## Abajo: short (con piernas) o bikini (solo la cadera, con ribete).
const BOTTOMS := ["Short", "Bikini"]
const BIKINI := 1
const BOARD_COLORS := [
	Color("#fff1c9"),
	Color(1.0, 0.86, 0.3),
	Color(0.95, 0.95, 0.95),
	Color(0.35, 0.75, 1.0),
	Color(1.0, 0.5, 0.35),
	Color(0.55, 0.9, 0.4),
	Color(0.9, 0.5, 1.0),
	Color("#2b2b2b"),
	Color("#e23a32"),
]
const BOARD_NAMES := ["Crema", "Amarilla", "Blanca", "Celeste", "Naranja", "Verde", "Lila", "Negra", "Roja"]
const BOARD_DESIGNS := [
	"Lisa", "Dos rayas", "Raya al medio", "Punta pintada", "Lunares", "Llamas", "Tres franjas", "Cuadros",
	"Olas", "Rayo", "Tie-dye", "Estrellas", "Mitad y mitad", "Flor hawaiana", "Zigzag",
]
## Colores para estampados, diseños de tabla y gorros.
const ACCENT_COLORS := [
	Color("#e8302a"),
	Color("#ff9b1f"),
	Color("#ffd23f"),
	Color("#2fa84f"),
	Color("#2fc4b2"),
	Color("#6cc6ff"),
	Color("#2f5fd6"),
	Color("#8a4fd1"),
	Color("#ff6fb5"),
	Color("#f6f6f2"),
	Color("#1b1b22"),
	Color("#7a4a24"),
]
const ACCENT_NAMES := [
	"Rojo", "Naranja", "Amarillo", "Verde", "Turquesa", "Celeste", "Azul", "Violeta", "Rosa", "Blanco",
	"Negro", "Marrón",
]
## Estampados / diseños que usan el segundo color.
const SHORTS_TWO_COLORS := [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
const BOARD_TWO_COLORS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]

const HEAD_SHAPES := ["Normal", "Ancha", "Alargada", "Chata", "Redonda", "Ovalada", "Suave"]
## Silueta: normal (la de la barra) o flaca (todo más finito, sin músculos).
const BUILDS := ["Normal", "Flaca"]
const SLIM := 1
## Escala de la cabeza (x, y, z) para cada forma (el tamaño va aparte, en la barra).
const HEAD_SCALES := [
	Vector3(1.0, 1.0, 1.0),
	Vector3(1.3, 0.92, 1.1),
	Vector3(0.85, 1.28, 0.92),
	Vector3(1.15, 0.78, 1.15),
	# Redonda, Ovalada y Suave: la forma la da el perfil de la cara (ver
	# AvatarFeatures.HEAD_PROFILES), no la escala.
	Vector3(1.0, 1.0, 1.0),
	Vector3(0.96, 1.04, 0.98),
	Vector3(1.0, 1.0, 1.0),
]
const HAIR_STYLES := [
	"Pelado", "Rapado", "Melena surfer", "Rulos", "Cresta", "Pinchos", "Moño", "Peluquín",
	"Pelo largo", "Colita", "Dos colitas", "Carré", "Afro", "Rodetes", "Rastas", "Despeinado",
	"Colita alta", "Melena ondulada",
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
	Color("#9a521c"),
]
const HAIR_COLOR_NAMES := ["Rubio", "Castaño", "Negro", "Colorado", "Canoso", "Rosa", "Verde", "Azul", "Caramelo"]
const EYES := [
	"Puntitos", "Saltones", "Bizcos", "Dormidos", "Desparejos",
	"Con pestañas", "Brillosos", "Felices", "Guiño", "Enojados", "Grandes con cejas",
	"Claros y tiernos",
]
const GLASSES := [
	"Ninguno", "De sol", "Antiparras", "Redondos", "Monóculo",
	"Aviador", "Corazones", "Estrellas", "Visera", "Parche pirata", "Snorkel", "Redondos de sol",
	"Lentes de color", "Envolventes",
]
const NOSES := ["Ninguna", "Botón", "Narigón", "De payaso", "Larga", "Con protector solar"]
const MOUTHS := [
	"Ninguna", "Sonrisa", "De costado", "Abierta", "Dientes de conejo", "Mueca",
	"Labios pintados", "Lengua afuera", "Silbando", "Sonrisota", "Sonrisa abierta",
	"Canchera", "Sonrisa ancha", "Pícara",
]
const FACE_EXTRAS := [
	"Nada", "Bigote", "Barba", "Uniceja", "Cejas gruesas", "Chivita", "Bigote y chivita", "Barba tupida",
	"Bigotón", "Pecas",
]
const EARS := ["Sin orejas", "Normales", "Grandes", "Dumbo", "Con aritos"]
const NECKLACES := [
	"Nada", "Perlas", "Collar de flores", "Cadena de oro", "Dientes de tiburón", "Silbato", "Caracol",
	"Cuentas rasta", "Paz y amor", "Cuellito blanco", "Dije",
]
## Sombreros y gorros (de playa y de mar).
const HATS := [
	"Nada", "Sombrero de paja", "Sombrero pirata", "Gorra de capitán", "Gorro de tiburón",
	"Pañuelo", "Gorra", "Gorro de lana", "Corona de flores", "Gorro rasta", "Bandana rasta",
	"Vincha hippie", "Vincha deportiva",
]
## Sombreros a los que se les puede cambiar el color (el de paja, no).
const HAT_COLORABLE := [5, 6, 7, 11, 12]
## Ropa de arriba (bikini y musculosa del color del short; la lycra tiene sus
## propios colores: el cuerpo y una franja).
const LYCRA := 3
const TOPS := ["Nada", "Bikini", "Musculosa", "Lycra de surf"]

## Estilos armados (el primero es el surfista original del modelo 3D).
const PRESET_NAMES := ["Surfista rubio", "Rasta", "Despeinado", "Pelirroja"]
const PRESETS := [
	{"weight": 0.0, "skin": 2, "head": 0, "hair": 2, "hair_color": 0,
		"eyes": 0, "glasses": 1, "nose": 0, "mouth": 2, "extra": 0, "ears": 0, "neck": 1, "shorts": 0,
		"shorts_pattern": 1, "board": 0, "board_design": 1},
	{"board": 7, "board_design": 10, "board_design_color": 3, "board_design_color2": 0, "ears": 0, "extra": 0,
		"eyes": 3, "glasses": 0, "hair": 14, "hair_color": 2, "hat": 9, "hat_color": 1, "head": 1, "mouth": 5,
		"neck": 4, "nose": 0, "shorts": 3, "shorts_pattern": 8, "shorts_pattern_color": 0,
		"shorts_pattern_color2": 3, "skin": 3, "top": 0, "weight": 0.2},
	{"board": 2, "board_design": 5, "board_design_color": 0, "board_design_color2": 1, "bottom": 0, "build": 0,
		"ears": 0, "extra": 0, "eyes": 0, "glasses": 13, "hair": 15, "hair_color": 1, "hat": 0, "hat_color": 1,
		"head": 0, "mouth": 13, "neck": 10, "nose": 5, "shorts": 1, "shorts_pattern": 14, "shorts_pattern_color": 9,
		"shorts_pattern_color2": 2, "skin": 1, "top": 0, "top_color": 4, "top_color2": 2,
		"trim_color": 0, "weight": 0.0},
	{"board": 6, "board_design": 4, "board_design_color": 2, "board_design_color2": 5, "bottom": 1, "build": 1,
		"ears": 0, "extra": 9, "eyes": 11, "glasses": 0, "hair": 17, "hair_color": 3, "hat": 1, "hat_color": 1,
		"head": 6, "mouth": 0, "neck": 0, "nose": 1, "shorts": 8, "shorts_pattern": 14, "shorts_pattern_color": 0,
		"shorts_pattern_color2": 2, "skin": 0, "top": 1, "top_color": 4, "top_color2": 2,
		"trim_color": 0, "weight": 0.1},
]

## Barra de cuerpo (0..1): 0 = musculoso ... 0.5 = normal ... 1 = panzón.
@export_range(0.0, 1.0) var weight: float = 0.0
## Ya no se usan (los músculos salen de `weight` y la cabeza tiene un solo
## tamaño); quedan para leer personajes guardados antes.
@export_range(0.0, 1.0) var muscle: float = 1.0
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
@export var hat_index: int = 0
@export var top_index: int = 0
@export var hat_color_index: int = 1
@export var shorts_pattern_color_index: int = 9
@export var shorts_pattern_color2_index: int = 2
@export var board_design_color_index: int = 0
@export var board_design_color2_index: int = 4
@export var bottom_index: int = 0
@export var build_index: int = 0
@export var trim_color_index: int = 0
@export var top_color_index: int = 4
@export var top_color2_index: int = 2

## Nombre del campo -> [propiedad, lista de opciones] (para el menú y el guardado).
## Barras: nombre -> propiedad.
const SLIDERS := {"weight": "weight", "muscle": "muscle", "head_size": "head_size"}
const FIELDS := {
	"skin": ["skin_index", SKIN_NAMES],
	"head": ["head_index", HEAD_SHAPES],
	"build": ["build_index", BUILDS],
	"hair": ["hair_index", HAIR_STYLES],
	"hair_color": ["hair_color_index", HAIR_COLOR_NAMES],
	"eyes": ["eyes_index", EYES],
	"glasses": ["glasses_index", GLASSES],
	"nose": ["nose_index", NOSES],
	"mouth": ["mouth_index", MOUTHS],
	"extra": ["extra_index", FACE_EXTRAS],
	"ears": ["ears_index", EARS],
	"neck": ["neck_index", NECKLACES],
	"hat": ["hat_index", HATS],
	"hat_color": ["hat_color_index", ACCENT_NAMES],
	"top": ["top_index", TOPS],
	"top_color": ["top_color_index", ACCENT_NAMES],
	"top_color2": ["top_color2_index", ACCENT_NAMES],
	"shorts": ["shorts_index", SHORTS_NAMES],
	"shorts_pattern": ["shorts_pattern_index", SHORTS_PATTERNS],
	"shorts_pattern_color": ["shorts_pattern_color_index", ACCENT_NAMES],
	"shorts_pattern_color2": ["shorts_pattern_color2_index", ACCENT_NAMES],
	"bottom": ["bottom_index", BOTTOMS],
	"trim_color": ["trim_color_index", ACCENT_NAMES],
	"board": ["board_index", BOARD_NAMES],
	"board_design": ["board_design_index", BOARD_DESIGNS],
	"board_design_color": ["board_design_color_index", ACCENT_NAMES],
	"board_design_color2": ["board_design_color2_index", ACCENT_NAMES],
}


func skin_color() -> Color:
	return SKIN_COLORS[posmod(skin_index, SKIN_COLORS.size())]


func shorts_color() -> Color:
	return SHORTS_COLORS[posmod(shorts_index, SHORTS_COLORS.size())]


func board_color() -> Color:
	return BOARD_COLORS[posmod(board_index, BOARD_COLORS.size())]


func hair_color() -> Color:
	return HAIR_COLORS[posmod(hair_color_index, HAIR_COLORS.size())]


## Color de la lista de acentos elegido en el campo (gorro, estampado, tabla).
func accent(field: String) -> Color:
	return ACCENT_COLORS[get_option(field)]


## Si la fila del campo tiene sentido con lo elegido (por ejemplo, el color del
## gorro de paja no se cambia; sin estampado no hay color de estampado).
func field_applies(field: String) -> bool:
	match field:
		"hat_color":
			return get_option("hat") in HAT_COLORABLE
		"top_color", "top_color2":
			return get_option("top") == LYCRA
		"trim_color":
			return get_option("top") == 1 or get_option("bottom") == BIKINI
		"shorts_pattern_color":
			return get_option("shorts_pattern") != 0
		"shorts_pattern_color2":
			return get_option("shorts_pattern") in SHORTS_TWO_COLORS
		"board_design_color":
			return get_option("board_design") != 0
		"board_design_color2":
			return get_option("board_design") in BOARD_TWO_COLORS
	return true


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
	var defaults := CharacterData.new()
	for field in FIELDS:
		set(FIELDS[field][0], int(p.get(field, defaults.get(FIELDS[field][0]))))


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


## Personaje por defecto para cada jugador: el surfista rubio, con un short
## de otro color para cada uno.
static func default_for_player(player_index: int) -> CharacterData:
	var c := CharacterData.new()
	c.apply_preset(0)
	c.shorts_index = [0, 1, 3, 4][player_index % 4]
	return c


## Texto para copiar y pegar: todos los campos del personaje (para guardarlo
## como estilo armado).
func export_text() -> String:
	var d := to_dict()
	d.erase("muscle")
	d.erase("head_size")
	return JSON.stringify(d)
