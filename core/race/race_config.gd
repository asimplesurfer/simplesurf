class_name RaceConfig
extends Resource
## Configuración de una partida: modo, mapa, clima, vueltas y corredores.
## La arma el menú y se la pasa a la escena (GameSession.launch); reiniciar es
## abrir la escena otra vez con la misma configuración. No depende de nada
## global mientras dura la partida.

## RACE: carrera normal. DEMO: carrera de bots que arranca sola desde el menú
## (cualquier tecla vuelve). SANDBOX: modo libre (mar abierto). TIME_TRIAL:
## contrarreloj (solo J1 contra su fantasma, con las mismas olas siempre).
enum Mode { RACE, DEMO, SANDBOX, TIME_TRIAL }

@export var mode: Mode = Mode.RACE
@export var layout: GameSettings.TrackLayout = GameSettings.TrackLayout.ARCHIPELAGO
@export var weather: GameSettings.Weather = GameSettings.Weather.SUNNY
@export var laps: int = 5
@export var slots: Array[RacerSlot] = []


## Una configuración nueva arranca con el mapa y el clima elegidos en el menú.
func _init() -> void:
	layout = GameSettings.track_layout
	weather = GameSettings.weather


## `player_count` humanos (con sus personajes guardados) y `bot_count` bots.
static func create(player_count: int, bot_count: int, bot_level: int) -> RaceConfig:
	var config := RaceConfig.new()
	config.layout = GameSettings.track_layout
	config.weather = GameSettings.weather
	config.laps = GameSettings.laps_for(config.layout)
	for i in player_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.HUMAN
		slot.player_index = i
		slot.display_name = "J%d" % (i + 1)
		slot.character = GameSettings.character_for(i)
		config.slots.append(slot)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var styles := bot_styles(config.slots, bot_count, rng)
	for i in bot_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.player_index = -1
		slot.display_name = "Bot %d" % (i + 1)
		if i < styles.size():
			slot.character = CharacterData.new()
			slot.character.apply_preset(styles[i])
		else:
			slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(bot_level)
		config.slots.append(slot)
	return config


## Estilos armados para los bots: sin repetir, y sin el que ya tiene alguna
## persona (si alcanzan; si no, se repiten los que usan las personas antes que
## quedarse sin estilo). En orden al azar.
static func bot_styles(humans: Array, count: int, rng: RandomNumberGenerator) -> Array[int]:
	var taken := {}
	for slot in humans:
		var style := style_of((slot as RacerSlot).character)
		if style >= 0:
			taken[style] = true
	var free: Array[int] = []
	var used: Array[int] = []
	for i in CharacterData.PRESET_NAMES.size():
		if taken.has(i):
			used.append(i)
		else:
			free.append(i)
	_shuffle(free, rng)
	_shuffle(used, rng)
	free.append_array(used)
	return free.slice(0, mini(count, free.size()))


## Qué estilo armado es el personaje (-1 si está armado a gusto).
static func style_of(character: CharacterData) -> int:
	if character == null:
		return -1
	var mine := character.to_dict()
	for i in CharacterData.PRESET_NAMES.size():
		var p := CharacterData.new()
		p.apply_preset(i)
		if p.to_dict() == mine:
			return i
	return -1


static func _shuffle(list: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := list[i]
		list[i] = list[j]
		list[j] = t


## Demo: la misma carrera que está armada en el menú, pero todos bots:
## un bot por cada jugador y bot elegidos (mínimo 2), en la dificultad elegida.
## Ej.: 1 jugador + 1 bot -> 1 vs 1 de bots; 1 jugador + 3 bots -> 4 bots.
static func demo() -> RaceConfig:
	var config := create(0, GameSettings.DEMO_BOTS, GameSettings.DEMO_LEVEL)
	config.mode = Mode.DEMO
	config.layout = GameSettings.DEMO_LAYOUT
	config.weather = GameSettings.DEMO_WEATHER
	config.laps = GameSettings.laps_for(config.layout)
	return config


## Modo libre: solo las personas, sin bots; el clima arranca como en el menú.
static func sandbox() -> RaceConfig:
	var config := create(GameSettings.player_count, 0, 0)
	config.mode = Mode.SANDBOX
	config.laps = 1
	return config


## Contrarreloj: J1 solo, en el mapa elegido, de día y con olas grandes que
## salen siempre en los mismos lugares (así los tiempos se pueden comparar).
static func time_trial() -> RaceConfig:
	var config := create(1, 0, 0)
	config.mode = Mode.TIME_TRIAL
	config.weather = GameSettings.Weather.SUNNY
	return config


func is_time_trial() -> bool:
	return mode == Mode.TIME_TRIAL


## Configuración según lo elegido en el menú (GameSettings).
static func from_settings() -> RaceConfig:
	return create(GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level)
