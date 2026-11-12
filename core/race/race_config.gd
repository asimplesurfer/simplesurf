class_name RaceConfig
extends Resource
## Configuración de una carrera: vueltas y corredores.
## Reiniciar es recargar la escena con la misma configuración.

@export var laps: int = 5
@export var slots: Array[RacerSlot] = []


## `player_count` humanos (con sus personajes guardados) y `bot_count` bots.
static func create(player_count: int, bot_count: int, bot_level: int) -> RaceConfig:
	var config := RaceConfig.new()
	config.laps = GameSettings.laps_for_layout()
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
	var bots := clampi(GameSettings.player_count + GameSettings.bot_count, 2, 4)
	return create(0, bots, GameSettings.bot_level)


## Configuración según lo elegido en el menú (GameSettings).
static func from_settings() -> RaceConfig:
	return create(GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level)
