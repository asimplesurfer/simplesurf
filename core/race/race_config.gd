class_name RaceConfig
extends Resource
## Configuración de una partida: modo, mapa, clima, vueltas y corredores.
## La arma el menú y se la pasa a la escena (GameSession.launch); reiniciar es
## abrir la escena otra vez con la misma configuración. No depende de nada
## global mientras dura la partida.

## RACE: carrera normal. DEMO: carrera de bots que arranca sola desde el menú
## (cualquier tecla vuelve). SANDBOX: modo libre (mar abierto).
enum Mode { RACE, DEMO, SANDBOX }

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
	# Cuerpos bien distintos: cada bot de una etapa de peso diferente.
	var weights := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
	weights.shuffle()
	var skins := range(CharacterData.SKIN_COLORS.size())
	skins.shuffle()
	for i in bot_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.player_index = -1
		slot.display_name = "Bot %d" % (i + 1)
		slot.character = CharacterData.random(rng)
		slot.character.weight = clampf(weights[i % weights.size()] + rng.randf_range(-0.05, 0.05), 0.0, 1.0)
		slot.character.skin_index = skins[i % skins.size()]
		slot.difficulty = AIDifficulty.preset(bot_level)
		config.slots.append(slot)
	return config


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


## Configuración según lo elegido en el menú (GameSettings).
static func from_settings() -> RaceConfig:
	return create(GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level)
