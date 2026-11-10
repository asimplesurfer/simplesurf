extends Node
## Música de fondo y volumen dinámico (autoload "AudioManager").
##
## - La música suena durante la carrera (y la demo), en bucle, y sigue sonando
##   entre carreras sin cortarse.
## - Volumen épico: si una persona pasa mucho tiempo en el aire, la música sube;
##   al volver al agua, baja de nuevo. Con pantalla dividida manda el que más
##   tiempo lleva en el aire. Los bots no cuentan.
## Los Riders no conocen el audio: esto solo mira su estado.

const MUSIC := preload("res://assets/audio/simple_surf.ogg")
const NORMAL_DB := -8.0
const EPIC_DB := -1.0
const MENU_DB := -16.0
## Segundos en el aire para que empiece a subir la música.
const EPIC_AIRTIME := 0.5

var player: AudioStreamPlayer
## Volumen objetivo actual (se suaviza).
var target_db: float = NORMAL_DB
## true mientras la música está en modo épico.
var epic: bool = false

var _airtime: Dictionary = {}
var _in_race: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = MUSIC.duplicate()
	stream.loop = true
	player.stream = stream
	player.volume_db = -40.0
	add_child(player)


## Llamado por RaceManager al cargar una carrera.
func race_started() -> void:
	_in_race = true
	if not player.playing:
		player.play()


## Llamado por el menú.
func menu_opened() -> void:
	_in_race = false
	if not player.playing:
		player.play()


func _process(delta: float) -> void:
	var max_air := 0.0
	for node in get_tree().get_nodes_in_group("riders"):
		var r := node as Rider
		if r == null or not r.is_human:
			continue
		var air: float = _airtime.get(r, 0.0)
		air = air + delta if not r.grounded else 0.0
		_airtime[r] = air
		max_air = maxf(max_air, air)
	# Limpiar Riders que ya no existen.
	for r in _airtime.keys():
		if not is_instance_valid(r):
			_airtime.erase(r)

	epic = _in_race and max_air > EPIC_AIRTIME
	if not _in_race:
		target_db = MENU_DB
	elif epic:
		target_db = EPIC_DB
	else:
		target_db = NORMAL_DB
	# Sube rápido y baja más despacio.
	var rate := 6.0 if target_db > player.volume_db else 2.0
	player.volume_db = lerpf(player.volume_db, target_db, 1.0 - exp(-rate * delta))
