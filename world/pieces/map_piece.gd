class_name MapPiece
extends RefCounted
## Una pieza de un mapa: algo que el mapa pone en un lugar (un volcán, un
## géiser, un arco de roca, una cueva...). Cada pieza es un archivo en
## world/pieces/ y sabe hacer todo lo suyo: construirse y, si afecta al juego,
## qué le pasa a un surfista que la toca. Course no sabe qué hace cada una.
##
## El mapa (world/maps/*.json) la pide por el nombre del archivo y le pasa sus
## valores. Por ejemplo {"type": "geyser", "x": -78, "z": -42, "phase": 0}
## crea la pieza de world/pieces/geyser.gd con esos valores. Las variables de
## la pieza son sus parámetros: lo que el mapa no dice queda con el valor que
## tiene acá (por defecto). Los que no tienen un valor por defecto razonable
## van en una constante REQUIRED de la pieza (const REQUIRED := ["shape"]) y el
## mapa tiene que darlos.
##
## Agregar una pieza nueva = agregar un archivo acá (no se toca nada más).

const FOLDER := "res://world/pieces/"

## Nombre de la pieza (el nombre del archivo, sin .gd).
var type: String = ""


## Arma la pieza a partir de lo que dice el mapa. Si algo no está bien (pieza
## que no existe, parámetro desconocido o que falta), lo anota en `errors` y
## devuelve null.
static func create(data: Dictionary, errors: PackedStringArray = PackedStringArray()) -> MapPiece:
	var t := str(data.get("type", ""))
	var path := FOLDER + t + ".gd"
	if t.is_empty() or t == "map_piece" or not ResourceLoader.exists(path):
		errors.append("pieza desconocida: \"%s\"" % t)
		return null
	var script := load(path) as GDScript
	var piece := script.new() as MapPiece
	if piece == null:
		errors.append("%s no es una pieza (tiene que heredar de MapPiece)" % path)
		return null
	piece.type = t
	piece.apply(data, errors)
	return piece


## Los parámetros de la pieza (sus variables), con su tipo: {nombre: tipo}.
func params() -> Dictionary:
	var out := {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(p.name).begins_with("_") and p.name != "type":
			out[p.name] = p.type
	return out


## Copia los valores del mapa a las variables de la pieza (convirtiendo lo que
## viene de JSON: [x, z] a Vector2, "#rrggbb" a Color, etc.).
func apply(data: Dictionary, errors: PackedStringArray = PackedStringArray()) -> void:
	var known := params()
	for key in data:
		if key == "type" or String(key).begins_with("_"):
			continue
		if not known.has(key):
			errors.append("%s: parámetro desconocido \"%s\"" % [type, key])
			continue
		set(key, from_json(data[key], known[key]))
	for key in (get_script() as GDScript).get_script_constant_map().get("REQUIRED", []):
		if not data.has(key):
			errors.append("%s: falta el parámetro \"%s\"" % [type, key])


## Lo contrario de apply: los parámetros de la pieza como JSON.
func to_dict() -> Dictionary:
	var out := {"type": type}
	for key in params():
		out[key] = to_json(get(key))
	return out


## Se llama antes de construir ninguna pieza. Acá una pieza calcula lo que
## otras necesitan saber y se anota en el registro de Course:
## - "ground": es tierra; tiene que tener ground_y(p: Vector2) -> float (la
##   altura del suelo en ese punto, o -INF si ahí no hay tierra).
## - "river": es un río; tiene que tener distance_to(p: Vector2) -> float y
##   la variable width.
## Así un río funciona con cualquier isla que se anote como tierra, y una
## isla deja libre el cauce de cualquier río.
func prepare(_course: Course) -> void:
	pass


## Se llama apenas está el recorrido (antes que las islas del mapa). Acá se
## construye todo lo de la pieza (como hijos de `course`).
func build(_course: Course) -> void:
	pass


## Se llama cuando el mapa ya está entero (islas, círculos y rocas puestos),
## por si la pieza necesita ver lo demás.
func finish(_course: Course) -> void:
	pass


## En cada paso de física, para cada surfista (después de chocar islas y antes
## de los límites de la pista). Devuelve true si le pasó algo que corta el
## resto del paso (por ejemplo, se cayó).
func affect_rider(_course: Course, _rider: Rider) -> bool:
	return false


## En cada paso de física (una vez, no por surfista).
func update(_course: Course, _delta: float) -> void:
	pass


static func from_json(v: Variant, t: int) -> Variant:
	match t:
		TYPE_FLOAT:
			return float(v)
		TYPE_INT:
			return int(v)
		TYPE_BOOL:
			return bool(v)
		TYPE_STRING:
			return str(v)
		TYPE_VECTOR2:
			return Vector2(float(v[0]), float(v[1]))
		TYPE_VECTOR3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		TYPE_COLOR:
			if v is String:
				return Color.html(v)
			return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
		TYPE_PACKED_VECTOR2_ARRAY:
			var arr := PackedVector2Array()
			for p in v:
				arr.append(Vector2(float(p[0]), float(p[1])))
			return arr
	return v


static func to_json(v: Variant) -> Variant:
	if v is Vector2:
		return [v.x, v.y]
	if v is Vector3:
		return [v.x, v.y, v.z]
	if v is Color:
		return "#" + (v as Color).to_html(v.a < 1.0)
	if v is PackedVector2Array:
		var out := []
		for p in v:
			out.append([p.x, p.y])
		return out
	return v
