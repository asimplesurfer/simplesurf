class_name TimeTrial
extends Node
## Contrarreloj: J1 solo contra su fantasma (su mejor vuelta... su mejor
## carrera en ese mapa), con las olas siempre en los mismos lugares.
##
## Guarda, por mapa, los 3 mejores tiempos (con el personaje que se usó) y el
## recorrido del mejor (el fantasma), en user://contrarreloj.dat. El fantasma
## siempre tiene el personaje con el que se hizo el récord, aunque después se
## cambie.
##
## Los récords van por el nombre del mapa (su id), con su número (order) al
## lado como salvavidas (ver _map_entry). Y cada récord vale solo en la pista
## donde se hizo: se guarda con la huella de la pista (TrackMap.track_shape).
## Si el mapa cambia de recorrido, de vueltas o de ancho, los récords viejos
## quedan archivados (no se borran, no se muestran y no hay fantasma) y se
## arranca de cero; si la pista vuelve a ser la de antes, vuelven solos.

const SAVE_PATH := "user://contrarreloj.dat"
## Formato del archivo de récords:
## {"format": 2, "maps": {id: {"order": n, "versions": [{"shape": huella,
## "top": [...], "ghost": {...}}, ...]}}}. Sin "format": el de antes (por lugar
## en la lista de mapas), que se pasa a este solo (ver _migrate).
const SAVE_FORMAT := 2
const RIDER_SCENE := preload("res://core/rider/rider.tscn")
## Cuántos tiempos se guardan por mapa.
const TOP := 3
## Muestras por segundo del fantasma (la física va a 60).
const GHOST_RATE := 20
const GHOST_EVERY := 60 / GHOST_RATE
## Datos de cada muestra del fantasma (en este orden).
const GHOST_FIELDS := [
	"x", "y", "z", "heading", "speed", "vy", "grounded", "stage", "trick_angle", "trick_done",
	"steer", "drift_side", "turbo", "kind0", "kind1", "kind2", "charge",
]
## Qué tan transparente se ve el fantasma (0 = sólido, 1 = invisible).
const GHOST_TRANSPARENCY := 0.55

## Se terminó la carrera: el tiempo, en qué puesto quedó entre los mejores
## (0 = el mejor, -1 = no entró) y si es récord nuevo.
signal finished(time: float, rank: int)

var race: RaceManager
var rider: Rider
## Récords de este mapa: [{time, date, character}], del mejor al peor.
var top: Array = []
## Tiempo a batir (o -1 si no hay).
var best_time: float = -1.0
var ghost: Rider

## El mapa de esta contrarreloj.
var _map: TrackMap
var _tick: int = 0
var _frames := PackedFloat32Array()
var _ghost_frames := PackedFloat32Array()
var _ghost_count: int = 0
var _ghost_stage: int = -1
var _transparency_timer: float = 0.0
var _done: bool = false
## Avance en la pista (como RaceManager.progress_of) de cada muestra del
## fantasma: para saber en qué tiempo pasó el récord por donde vamos.
var _ghost_progress := PackedFloat32Array()


func setup(p_race: RaceManager) -> void:
	race = p_race
	rider = race.racers[0]
	_map = race.course.map
	var entry := records_of(_map)
	top = entry.get("top", [])
	if not top.is_empty():
		best_time = float(top[0].time)
	var g: Dictionary = entry.get("ghost", {})
	if g.has("frames") and g.has("character"):
		_ghost_frames = g.frames
		_ghost_count = _ghost_frames.size() / GHOST_FIELDS.size()
		_spawn_ghost(CharacterData.from_dict(g.character))
	race.racer_finished.connect(func(r: Rider, _place: int) -> void:
		if r == rider:
			_on_finished()
	)


# ---------------------------------------------------------------- guardado

## Todo lo guardado, en el formato de ahora (si estaba en el de antes, lo pasa
## y lo guarda así una sola vez).
static func load_data() -> Dictionary:
	var raw := _read()
	if int(raw.get("format", 0)) == SAVE_FORMAT:
		return raw
	var data := _migrate(raw)
	if not raw.is_empty():
		save_data(data)
	return data


static func _read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = f.get_var()
	return v if v is Dictionary else {}


## El formato de antes guardaba por lugar en la lista de mapas ("0", "1"...).
## Pasan al mapa que hoy está en ese lugar, con la huella de su pista de hoy
## (es la pista donde se hicieron: hasta acá no había forma de que fuera otra).
static func _migrate(old: Dictionary) -> Dictionary:
	var data := {"format": SAVE_FORMAT, "maps": {}}
	var maps := TrackMap.all()
	for key in old:
		var entry: Variant = old[key]
		if not str(key).is_valid_int() or not entry is Dictionary:
			continue
		var i := int(str(key))
		if i < 0 or i >= maps.size():
			continue
		var version := {"shape": maps[i].track_shape(), "top": (entry as Dictionary).get("top", [])}
		if (entry as Dictionary).has("ghost"):
			version["ghost"] = entry.ghost
		data.maps[maps[i].id] = {"order": maps[i].order, "versions": [version]}
	return data


## Los récords de un mapa en `data`, buscados por su nombre. Si no está por
## nombre (le cambiaron el nombre al archivo), adopta los de un mapa con su
## mismo número que ya no existe y los pasa al nombre nuevo. El número
## guardado se actualiza al de hoy (por si se reordenaron los mapas).
## Con `create`, si no hay nada lo arma vacío; si no, devuelve {}.
static func _map_entry(data: Dictionary, map: TrackMap, create: bool) -> Dictionary:
	if not data.has("maps"):
		data["maps"] = {}
	var maps: Dictionary = data.maps
	if not maps.has(map.id):
		var live := {}
		for m in TrackMap.all():
			live[m.id] = true
		for key in maps.keys():
			if not live.has(key) and int(maps[key].get("order", -1)) == map.order:
				maps[map.id] = maps[key]
				maps.erase(key)
				break
	if not maps.has(map.id):
		if not create:
			return {}
		maps[map.id] = {"order": map.order, "versions": []}
	var entry: Dictionary = maps[map.id]
	entry["order"] = map.order
	if not entry.has("versions"):
		entry["versions"] = []
	return entry


## Los récords de la pista de hoy del mapa (la versión con la misma huella).
## Las versiones con otra huella quedan archivadas.
static func _version(data: Dictionary, map: TrackMap, create: bool) -> Dictionary:
	var entry := _map_entry(data, map, create)
	if entry.is_empty():
		return {}
	var shape := map.track_shape()
	for v in entry.versions:
		if TrackMap.same_shape(v.get("shape", {}), shape):
			return v
	if not create:
		return {}
	var version := {"shape": shape, "top": []}
	entry.versions.append(version)
	return version


## Los récords que valen hoy en ese mapa: {"top": [...], "ghost": {...}} (o {}).
static func records_of(map: TrackMap) -> Dictionary:
	return _version(load_data(), map, false)


static func save_data(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(data)


## Los mejores tiempos guardados del mapa (para el menú y los tests).
static func top_times(layout: int) -> Array:
	return records_of(TrackMap.for_layout(layout)).get("top", [])


func _on_finished() -> void:
	if _done:
		return
	_done = true
	var time: float = race.finish_times.get(rider, race.race_time)
	var record := {
		"time": time,
		"date": Time.get_datetime_string_from_system(),
		"character": (rider.get_node("Visual") as RiderVisual).character.to_dict(),
	}
	var rank := TOP
	for i in top.size():
		if time < float(top[i].time):
			rank = i
			break
	if rank >= TOP and top.size() < TOP:
		rank = top.size()
	if rank < TOP:
		top.insert(rank, record)
		top.resize(mini(top.size(), TOP))
		var data := load_data()
		var entry := _version(data, _map, true)
		entry["top"] = top
		if rank == 0:
			# Récord nuevo: este recorrido pasa a ser el fantasma (con este personaje).
			entry["ghost"] = {"time": time, "character": record.character, "frames": _frames}
		save_data(data)
	finished.emit(time, rank if rank < TOP else -1)


# ---------------------------------------------------------------- grabar

func _physics_process(_delta: float) -> void:
	if race == null or race.state == RaceManager.State.COUNTDOWN:
		_play_ghost(0.0)
		return
	_tick += 1
	if not _done and _tick % GHOST_EVERY == 0:
		_record()
	_play_ghost(race.race_time)


func _record() -> void:
	var r := rider
	var kinds := r.trick_kinds
	_frames.append_array(PackedFloat32Array([
		r.position.x, r.position.y, r.position.z, r.heading, r.speed, r.vertical_speed,
		1.0 if r.grounded else 0.0, float(r.recovery_stage), r.trick_angle, float(r.trick_units_done),
		r.steer_amount, float(r.drift_side), 1.0 if r.turbo_active else 0.0,
		float(kinds[0]) if kinds.size() > 0 else -1.0,
		float(kinds[1]) if kinds.size() > 1 else -1.0,
		float(kinds[2]) if kinds.size() > 2 else -1.0,
		r.jump_charge,
	]))


## Diferencia con el récord en este punto de la pista (s): negativa si vamos
## mejor, positiva si vamos peor. NAN si no hay récord con el que comparar.
func gap() -> float:
	if race == null or _ghost_count < 2:
		return NAN
	if _ghost_progress.is_empty():
		_build_ghost_progress()
	var mine := race.progress_of(rider)
	# Primera muestra del récord que llegó a donde estamos (búsqueda binaria).
	var lo := 0
	var hi := _ghost_progress.size() - 1
	if mine > _ghost_progress[hi]:
		return NAN
	while lo < hi:
		var mid := (lo + hi) / 2
		if _ghost_progress[mid] < mine:
			lo = mid + 1
		else:
			hi = mid
	var t := float(lo) / GHOST_RATE
	if lo > 0:
		var a := _ghost_progress[lo - 1]
		var b := _ghost_progress[lo]
		if b > a:
			t -= (b - mine) / (b - a) / GHOST_RATE
	return race.race_time - t


func _build_ghost_progress() -> void:
	var track := race.course.track
	var n := GHOST_FIELDS.size()
	var progress := RaceManager.START_ANGLE
	var last := progress
	var best := progress
	for i in _ghost_count:
		var p := Vector3(_ghost_frames[i * n], 0.0, _ghost_frames[i * n + 2])
		var angle := track.angle_of(p)
		progress += wrapf(angle - last, -PI, PI)
		last = angle
		# Siempre creciente (si el récord retrocedió un poco, cuenta lo mejor).
		best = maxf(best, progress)
		_ghost_progress.append(best)


# ---------------------------------------------------------------- fantasma

func _spawn_ghost(character: CharacterData) -> void:
	ghost = RIDER_SCENE.instantiate()
	ghost.name = "Fantasma"
	ghost.display_name = "Récord"
	ghost.player_index = -1
	ghost.is_human = false
	(ghost.get_node("Visual") as RiderVisual).character = character
	var old := ghost.get_node("Controller")
	ghost.remove_child(old)
	old.free()
	var ctrl := BaseController.new()
	ctrl.name = "Controller"
	ghost.add_child(ctrl)
	if _ghost_count > 0:
		ghost.position = Vector3(_ghost_frames[0], _ghost_frames[1], _ghost_frames[2])
		ghost.rotation.y = _ghost_frames[3]
	ghost.ready.connect(func() -> void:
		# Solo se ve: no choca, no corre, no lo siguen las olas ni las boyas.
		ghost.set_physics_process(false)
		ghost.remove_from_group("riders")
		ghost.add_to_group("ghosts")
		_set_transparency()
	, CONNECT_ONE_SHOT)
	# (La escena todavía se está armando: se agrega al final del cuadro.)
	race.get_parent().add_child.call_deferred(ghost)


## El fantasma se ve semitransparente: cada material se cambia por una copia
## con transparencia (los de shader, como la tabla y el short, por su color
## liso). En la web no sirve la transparencia por objeto.
func _set_transparency() -> void:
	if ghost == null:
		return
	for node in ghost.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gi.material_override:
			gi.material_override = _ghost_material(gi.material_override)
		var mi := gi as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i)
			if mat == null:
				mat = mi.mesh.surface_get_material(i)
			if mat:
				mi.set_surface_override_material(i, _ghost_material(mat))


var _ghost_mats: Dictionary = {}


func _ghost_material(mat: Material) -> Material:
	if mat.has_meta("ghost"):
		return mat
	if _ghost_mats.has(mat):
		return _ghost_mats[mat]
	var out: BaseMaterial3D
	if mat is BaseMaterial3D:
		out = (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	else:
		# Shader (tabla, short): su color de base, liso.
		out = StandardMaterial3D.new()
		out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var base: Variant = null
		if mat is ShaderMaterial:
			base = (mat as ShaderMaterial).get_shader_parameter("board_color")
			if base == null:
				base = (mat as ShaderMaterial).get_shader_parameter("base_color")
		out.albedo_color = base if base is Color else Color(0.8, 0.9, 1.0)
	out.next_pass = null
	out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	var c := out.albedo_color
	# El contorno (negro) más suave todavía.
	var alpha := 1.0 - GHOST_TRANSPARENCY
	if c.v < 0.1:
		alpha *= 0.5
	out.albedo_color = Color(c.r, c.g, c.b, alpha)
	out.set_meta("ghost", true)
	_ghost_mats[mat] = out
	return out


func _play_ghost(t: float) -> void:
	if ghost == null or _ghost_count == 0 or not ghost.is_inside_tree():
		return
	# Cada tanto se vuelve a poner transparente (el personaje arma piezas nuevas).
	_transparency_timer -= get_physics_process_delta_time()
	if _transparency_timer <= 0.0:
		_transparency_timer = 1.0
		_set_transparency()
	var f := t * GHOST_RATE
	var i := clampi(int(f), 0, _ghost_count - 1)
	var j := mini(i + 1, _ghost_count - 1)
	var k := clampf(f - i, 0.0, 1.0)
	# Terminó su carrera: se queda en la llegada y se va desvaneciendo.
	ghost.visible = f < _ghost_count + GHOST_RATE * 2.0
	var n := GHOST_FIELDS.size()
	var a := i * n
	var b := j * n
	var fr := _ghost_frames
	ghost.position = Vector3(lerpf(fr[a], fr[b], k), lerpf(fr[a + 1], fr[b + 1], k), lerpf(fr[a + 2], fr[b + 2], k))
	ghost.heading = lerp_angle(fr[a + 3], fr[b + 3], k)
	ghost.rotation.y = ghost.heading
	ghost.speed = lerpf(fr[a + 4], fr[b + 4], k)
	ghost.vertical_speed = lerpf(fr[a + 5], fr[b + 5], k)
	ghost.grounded = fr[a + 6] > 0.5
	var stage := int(fr[a + 7])
	if stage != _ghost_stage:
		_ghost_stage = stage
		ghost.set_recovery_stage(stage as Rider.RecoveryStage)
	# El giro del truco: sin interpolar al cambiar de truco (vuelve a 0).
	ghost.trick_angle = lerpf(fr[a + 8], fr[b + 8], k) if fr[b + 8] >= fr[a + 8] else fr[a + 8]
	ghost.trick_units_done = int(fr[a + 9])
	ghost.steer_amount = lerpf(fr[a + 10], fr[b + 10], k)
	ghost.drift_side = int(fr[a + 11])
	ghost.turbo_active = fr[a + 12] > 0.5
	var kinds: Array[int] = []
	for q in 3:
		if fr[a + 13 + q] >= 0.0:
			kinds.append(int(fr[a + 13 + q]))
	ghost.trick_kinds = kinds
	ghost.jump_charge = fr[a + 16]
	if ghost.water:
		ghost.water_normal = ghost.water.normal_at(ghost.position.x, ghost.position.z)
