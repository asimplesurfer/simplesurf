class_name RaceConfig
extends Resource
## Configuración de una partida: modo, mapa, clima, vueltas y corredores.
## La arma el menú y se la pasa a la escena (GameSession.launch); reiniciar es
## abrir la escena otra vez con la misma configuración. No depende de nada
## global mientras dura la partida.

## RACE: carrera normal. DEMO: carrera de bots que arranca sola desde el menú
## (cualquier tecla vuelve). SANDBOX: modo libre (mar abierto). TIME_TRIAL:
## contrarreloj (solo J1 contra su fantasma, con las mismas olas siempre).
## EXPLORE: modo libre dentro del mapa elegido (sin bots, sin carrera; ver
## ExploreMode).
enum Mode { RACE, DEMO, SANDBOX, TIME_TRIAL, EXPLORE }

@export var mode: Mode = Mode.RACE
@export var layout: GameSettings.TrackLayout = GameSettings.TrackLayout.ARCHIPELAGO
@export var weather: GameSettings.Weather = GameSettings.Weather.SUNNY
@export var time_of_day: GameSettings.TimeOfDay = GameSettings.TimeOfDay.DAY
@export var laps: int = 5
@export var slots: Array[RacerSlot] = []


## Una configuración nueva arranca con el mapa y el clima elegidos en el menú.
func _init() -> void:
	layout = GameSettings.track_layout
	weather = GameSettings.weather
	time_of_day = GameSettings.time_of_day


## `player_count` humanos (con sus personajes guardados) y `bot_count` bots.
static func create(player_count: int, bot_count: int, bot_level: int) -> RaceConfig:
	var config := RaceConfig.new()
	config.layout = GameSettings.track_layout
	config.weather = GameSettings.weather
	config.time_of_day = GameSettings.time_of_day
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
	# Estilos que ya tiene alguien: si un bot tiene que repetir uno (hay más
	# corredores que estilos), lo repite con otros colores (nunca igual a una
	# persona ni a otro bot).
	var used := {}
	for slot in config.slots:
		var st := style_of((slot as RacerSlot).character)
		if st >= 0:
			used[st] = true
	for i in bot_count:
		var slot := RacerSlot.new()
		slot.kind = RacerSlot.Kind.BOT
		slot.player_index = -1
		slot.display_name = "Bot %d" % (i + 1)
		var style := styles[i % styles.size()] if not styles.is_empty() else -1
		if style >= 0:
			slot.character = CharacterData.new()
			slot.character.apply_preset(style)
			if used.has(style):
				recolor(slot.character, rng)
			used[style] = true
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


## Lo que hace reconocible un estilo (la forma, no los colores): un estilo
## con otros colores o algún detalle cambiado sigue siendo ese estilo.
const STYLE_KEYS := ["hair", "hat", "glasses", "head", "top", "bottom", "neck", "extra", "shorts_pattern",
	"board_design"]
## Cuántas de esas tienen que coincidir (además del pelo).
const STYLE_MATCH := 7


## Qué estilo armado es el personaje (-1 si está armado a gusto): el mismo,
## o uno que se le parece mucho (mismo pelo y casi todo lo demás igual; por
## ejemplo, el Rasta con el short de otro color).
static func style_of(character: CharacterData) -> int:
	if character == null:
		return -1
	var mine := character.to_dict()
	var best := -1
	var best_score := 0
	for i in CharacterData.PRESET_NAMES.size():
		var p := CharacterData.new()
		p.apply_preset(i)
		var theirs := p.to_dict()
		if theirs == mine:
			return i
		if theirs.get("hair") != mine.get("hair"):
			continue
		var score := 0
		for k in STYLE_KEYS:
			if theirs.get(k) == mine.get(k):
				score += 1
		if score >= STYLE_MATCH and score > best_score:
			best = i
			best_score = score
	return best


## Otros colores (pelo, ropa, tabla) para un estilo repetido.
static func recolor(c: CharacterData, rng: RandomNumberGenerator) -> void:
	for key in ["hair_color", "shorts", "shorts_pattern_color", "top_color", "hat_color", "board",
			"board_design_color"]:
		if not CharacterData.FIELDS.has(key):
			continue
		var field: Array = CharacterData.FIELDS[key]
		var count: int = (field[1] as Array).size()
		var now: int = c.get(field[0])
		c.set(field[0], (now + rng.randi_range(1, maxi(count - 1, 1))) % count)


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
	config.time_of_day = GameSettings.TimeOfDay.DAY
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


## Modo libre dentro del mapa elegido: las personas solas, sin carrera (no
## termina nunca), con el clima del menú.
static func explore() -> RaceConfig:
	var config := create(GameSettings.player_count, 0, 0)
	config.mode = Mode.EXPLORE
	config.laps = 999
	return config


func is_explore() -> bool:
	return mode == Mode.EXPLORE


func is_time_trial() -> bool:
	return mode == Mode.TIME_TRIAL


## Configuración según lo elegido en el menú (GameSettings).
static func from_settings() -> RaceConfig:
	return create(GameSettings.player_count, GameSettings.bot_count, GameSettings.bot_level)
