class_name RaceConfig
extends Resource
## Configuración de una carrera: vueltas y corredores.
## Reiniciar es recargar la escena con la misma configuración.

@export var laps: int = 2
@export var slots: Array[RacerSlot] = []


## `player_count` humanos (con sus personajes guardados) y `bot_count` bots.
static func create(player_count: int, bot_count: int, bot_level: int) -> RaceConfig:
	var config := RaceConfig.new()
	for i in player_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.HUMAN
		slot.player_index = i
		slot.display_name = "J%d" % (i + 1)
		slot.character = GameSettings.character_for(i)
		config.slots.append(slot)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in bot_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.player_index = -1
		slot.display_name = "Bot %d" % (i + 1)
		slot.character = CharacterData.random(rng)
		slot.difficulty = AIDifficulty.preset(bot_level)
		config.slots.append(slot)
	return config


## Demo: 2 bots en la dificultad máxima.
static func demo() -> RaceConfig:
	return create(0, 2, 2)


## Configuración según lo elegido en el menú (GameSettings).
static func from_settings() -> RaceConfig:
	return create(GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level)
