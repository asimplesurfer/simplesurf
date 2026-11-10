class_name RaceConfig
extends Resource
## Configuración de una carrera: vueltas y corredores.
## Reiniciar es recargar la escena con la misma configuración.

const PLAYER_COLORS := [
	[Color(0.98, 0.5, 0.32), Color(1.0, 0.86, 0.3)],
	[Color(0.35, 0.7, 1.0), Color(0.95, 0.95, 0.95)],
	[Color(0.55, 0.9, 0.4), Color(1.0, 0.55, 0.75)],
	[Color(0.8, 0.5, 1.0), Color(0.4, 1.0, 0.9)],
]

@export var laps: int = 2
@export var slots: Array[RacerSlot] = []


## Configuración por defecto: `player_count` humanos.
static func for_players(player_count: int) -> RaceConfig:
	var config := RaceConfig.new()
	for i in player_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.HUMAN
		slot.player_index = i
		slot.display_name = "J%d" % (i + 1)
		slot.body_color = PLAYER_COLORS[i % PLAYER_COLORS.size()][0]
		slot.board_color = PLAYER_COLORS[i % PLAYER_COLORS.size()][1]
		config.slots.append(slot)
	return config
