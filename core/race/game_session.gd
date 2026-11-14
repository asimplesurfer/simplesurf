class_name GameSession
extends Node
## Base de una partida: lo que tienen en común la carrera (RaceManager) y el
## modo libre (Sandbox). Crea los surfistas según su RaceConfig, y maneja
## reiniciar, volver al menú y las teclas generales.
##
## La configuración de la partida (modo, mapa, clima, jugadores, bots) llega
## armada en `config`, la pone quien abre la escena (ver `launch`). Si la escena
## se abre sola (tests, editor), se arma con las opciones del menú.
##
## SplitScreen y Hud dependen solo de esto: `racers`, `humans()` y `free_ride()`.

const RIDER_SCENE := preload("res://core/rider/rider.tscn")
const MENU_SCENE := "res://ui/menus/character_select.tscn"

@export var config: RaceConfig
@export var riders_path: NodePath

var racers: Array[Rider] = []


func _enter_tree() -> void:
	# Antes que el _ready de cualquier nodo de la escena (la pista lee el mapa y
	# el clima de acá).
	add_to_group("session")
	GameSettings.load_settings()
	if config == null:
		config = default_config()


## Configuración si nadie la pasó (la escena se abrió sola).
func default_config() -> RaceConfig:
	return RaceConfig.from_settings()


## La partida de la escena de `node` (o null si no hay): se busca entre los
## hermanos de su escena, no en todo el juego (en los tests puede haber más de
## una escena abierta).
static func of(node: Node) -> GameSession:
	var scene_root := node.owner if node.owner else node.get_parent()
	if scene_root == null:
		return null
	for child in scene_root.get_children():
		if child is GameSession:
			return child as GameSession
	return null


## Abre `scene_path` con esta configuración en lugar de `old` (por defecto, la
## escena actual).
static func launch(tree: SceneTree, scene_path: String, session_config: RaceConfig, old: Node = null) -> void:
	if old == null:
		old = tree.current_scene
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	for child in scene.get_children():
		if child is GameSession:
			(child as GameSession).config = session_config
	tree.root.add_child(scene)
	if old == tree.current_scene or tree.current_scene == null:
		tree.current_scene = scene
	if old:
		old.queue_free()


## true en el modo libre (sin vueltas, posiciones ni llegada).
func free_ride() -> bool:
	return false


func humans() -> Array[Rider]:
	var result: Array[Rider] = []
	for r in racers:
		if r.is_human:
			result.append(r)
	return result


## Crea un surfista según su lugar en la partida, en `position` mirando a `heading`.
func spawn_rider(slot: RacerSlot, position: Vector3, heading: float, initial_state: StringName) -> Rider:
	var parent := get_node_or_null(riders_path)
	if parent == null:
		parent = self
	var rider: Rider = RIDER_SCENE.instantiate()
	rider.name = slot.display_name
	rider.player_index = slot.player_index
	rider.display_name = slot.display_name
	rider.is_human = slot.kind == RacerSlot.Kind.HUMAN
	(rider.get_node("Visual") as RiderVisual).character = slot.character
	(rider.get_node("StateMachine") as RiderStateMachine).initial_state = initial_state
	if slot.kind == RacerSlot.Kind.BOT:
		# El bot reemplaza al control de mando/teclado.
		var old := rider.get_node("Controller")
		rider.remove_child(old)
		old.free()
		var ai := AIController.new()
		ai.name = "Controller"
		ai.difficulty = slot.difficulty
		rider.add_child(ai)
	rider.position = position
	rider.rotation.y = heading
	_before_add(rider)
	parent.add_child(rider)
	racers.append(rider)
	return rider


## Para que cada modo ajuste el surfista antes de que entre a la escena.
func _before_add(_rider: Rider) -> void:
	pass


## Las acciones de mando y teclado de las personas de la partida.
func _setup_input() -> void:
	var humans_count := 0
	for slot in config.slots:
		if slot.kind == RacerSlot.Kind.HUMAN:
			InputSetup.ensure_player_actions(slot.player_index)
			humans_count += 1
	InputSetup.apply_keyboard_layout(humans_count)


## La misma partida otra vez, con la misma configuración (reemplaza su propia
## escena, sea o no la escena actual del juego).
func restart() -> void:
	var own_scene := owner if owner else get_parent()
	launch(get_tree(), own_scene.scene_file_path, config, own_scene)


func back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Cambia la cantidad de personas y vuelve a empezar (con la configuración
## de este modo armada de nuevo).
func set_player_count(count: int) -> void:
	count = clampi(count, 1, 2)
	if count == GameSettings.player_count:
		return
	GameSettings.player_count = count
	GameSettings.save_settings()
	config = config_for_players()
	restart()


## Configuración de este modo con la cantidad de personas actual.
func config_for_players() -> RaceConfig:
	return RaceConfig.from_settings()


## Cualquier tecla, botón o toque (la demo vuelve al menú con eso).
static func is_any_press(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		return event.is_pressed()
	if event is InputEventAction:
		return event.is_pressed()
	return false


## Teclas generales. Devuelve true si la usó.
func _handle_common_key(key: InputEventKey) -> bool:
	match key.physical_keycode:
		KEY_1:
			set_player_count(1)
		KEY_2:
			set_player_count(2)
		KEY_C, KEY_ESCAPE:
			back_to_menu()
		KEY_F7:
			# Cámara lenta (para mirar animaciones y efectos).
			Engine.time_scale = 1.0 if Engine.time_scale < 1.0 else 0.08
		KEY_P:
			# Contador de FPS en el HUD (para ver si anda lento).
			Hud.show_fps = not Hud.show_fps
		KEY_V:
			# Pantalla dividida: lado a lado <-> arriba y abajo.
			GameSettings.split_vertical = not GameSettings.split_vertical
			GameSettings.save_settings()
			if humans().size() > 1 or humans().is_empty():
				restart()
		_:
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		_handle_common_key(key)
		return
	for slot in config.slots:
		var p := InputSetup.prefix(slot.player_index)
		if InputMap.has_action(p + "select") and event.is_action_pressed(p + "select"):
			set_player_count(2 if GameSettings.player_count == 1 else 1)
			return
