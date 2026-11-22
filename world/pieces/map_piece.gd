class_name MapPiece
extends RefCounted
## Una pieza de un mapa: algo que el mapa pone en un lugar (una isla, un
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
## Agregar una pieza nueva = agregar un archivo acá (no se toca nada más; el
## editor de mapas la toma sola, ver EDITOR más abajo).

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
##   altura del suelo en ese punto, o -INF si ahí no hay tierra) y
##   outline() -> PackedVector2Array (su figura vista desde arriba: con ella el
##   agua apaga las olas grandes cerca de la orilla, y las olas no salen ahí).
## Una pieza también puede mirar las otras en course.pieces (así una isla
## tropical encuentra los cortes que la dividen) y sumar piezas nuevas ahí.
func prepare(_course: Course) -> void:
	pass


## Para el validador de mapas (tools/validate_maps.gd), sin armar nada: el
## primer punto de la pista (`samples`: su línea central cada pocos metros) que
## esta pieza tapa, o null si no tapa ninguno. Las piezas que se atraviesan
## (cuevas, cascadas) o que van fuera de la pista no tapan.
func blocks_track(_samples: PackedVector2Array) -> Variant:
	return null


## Se llama apenas está el recorrido. Acá se construye todo lo de la pieza
## (como hijos de `course`).
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


# ------------------------------------------------------------ editor de mapas

## El editor de mapas (tools/map_editor) arma sus herramientas con lo que dice
## cada pieza: no hay que tocarlo para sumar una. Cada pieza tiene su
## constante EDITOR := {...}:
## - "name": cómo se llama ("Géiser").
## - "place": cómo se pone: "point" (un clic: x, z), "shape" (figura cerrada),
##   "path" (línea abierta) o "two_points" (dos puntas: a, b).
## - "key": para "shape" y "path", la variable con los puntos (por defecto
##   "shape" o "path").
## - "solid": true si se choca (el editor avisa si pisa la pista).
## - "what": cómo se nombra mientras se dibuja ("una isla").
## - "hint": la ayuda que se ve al elegir la herramienta.
## - "fields": opcional, por parámetro, cuando lo automático no alcanza: un
##   texto (la etiqueta) o {"label", "kind", "options"}. Lo automático: la
##   etiqueta es el comentario ## de la variable y el campo sale de su tipo.
##   "kind" puede ser num, int, bool, color, text, choice o level (una lista
##   de opciones [valor, nombre]), numbool (sí/no que se guarda 1 o 0) o
##   variant (semilla con botón para sortear otra).
const PLACES := ["point", "shape", "path", "two_points"]
## Tipos de variable que son campos del editor, y el campo de cada uno.
const FIELD_KINDS := {TYPE_FLOAT: "num", TYPE_INT: "int", TYPE_BOOL: "bool", TYPE_COLOR: "color", TYPE_STRING: "text"}


## Todas las piezas de world/pieces/, como las ve el editor (ver editor_entry).
static func editor_catalog() -> Array:
	var out := []
	var files := DirAccess.get_files_at(FOLDER)
	files.sort()
	for f in files:
		var file := f.trim_suffix(".remap")
		if file.get_extension() != "gd" or file == "map_piece.gd":
			continue
		# Faltan los parámetros obligatorios, pero para leerla alcanza.
		var piece := create({"type": file.get_basename()})
		if piece:
			out.append(piece.editor_entry())
	return out


## Esta pieza para el editor: {type, name, place, key, solid, what, hint,
## required, params: [[nombre, etiqueta, campo, valor por defecto, opciones?]]}.
func editor_entry() -> Dictionary:
	var script := get_script() as GDScript
	var consts := script.get_script_constant_map()
	var ed: Dictionary = consts.get("EDITOR", {})
	var place := str(ed.get("place", ""))
	var key := str(ed.get("key", "path" if place == "path" else "shape"))
	var fields: Dictionary = ed.get("fields", {})
	var comments := _var_comments(script.source_code)
	# Lo que dice dónde está la pieza no es un campo: se edita en el mapa.
	var skip: Array = {"point": ["x", "z"], "two_points": ["a", "b"], "shape": [key], "path": [key]}.get(place, [])
	var rows := []
	var known := params()
	for name in known:
		if skip.has(name) or not FIELD_KINDS.has(known[name]):
			continue
		var f: Variant = fields.get(name, {})
		if f is String:
			f = {"label": f}
		var row := [
			name, str(f.get("label", comments.get(name, String(name).capitalize()))),
			str(f.get("kind", FIELD_KINDS[known[name]])), to_json(get(name)),
		]
		if f.has("options"):
			row.append(f.options)
		rows.append(row)
	var entry := {
		"type": type, "name": str(ed.get("name", type.capitalize())), "place": place,
		"solid": bool(ed.get("solid", false)), "what": str(ed.get("what", "")),
		"hint": str(ed.get("hint", "")), "required": consts.get("REQUIRED", []), "params": rows,
	}
	if place == "shape" or place == "path":
		entry["key"] = key
	return entry


## La primera línea del comentario ## que está justo arriba de cada variable
## (sin el punto final): {nombre: texto}.
static func _var_comments(source: String) -> Dictionary:
	var out := {}
	var pending := ""
	for line in source.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("##"):
			if pending.is_empty():
				pending = l.trim_prefix("##").strip_edges()
			continue
		if l.begins_with("var ") and not pending.is_empty():
			var name := l.trim_prefix("var ").get_slice(":", 0).get_slice("=", 0).strip_edges()
			out[name] = pending.trim_suffix(".")
		pending = ""
	return out


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
