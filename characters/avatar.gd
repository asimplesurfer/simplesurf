class_name Avatar
extends Node3D
## El personaje: el cuerpo del surfista original con las barras y los
## accesorios de `data` (ver SurferKit), animado con las poses de SurferAnim.
## Mira hacia +Z y los pies están en y = 0 (escalar el nodo para el tamaño).
##
## Se elige la animación con `anim` y se ajusta con los demás valores (los
## pone RiderVisual en cada cuadro). Las poses se suavizan solas.

## Animaciones disponibles.
const ANIMS := [
	&"idle",       # parado tranquilo (menú)
	&"ride",       # sobre la tabla: rodillas flexionadas, brazos de equilibrio
	&"air",        # en el aire: recogido al subir, abierto al bajar
	&"trick",      # truco: bien recogido agarrando la tabla
	&"drift",      # derrape: agachado, una mano rozando el agua
	&"duck",       # atraviesa una ola: se tapa la cabeza
	&"flail",      # recién caído: manotea y patalea
	&"tread",      # en el agua: braza para mantenerse a flote
	&"climb",      # se sube a la tabla
	&"paddle",     # acostado: rema (crol)
	&"pop_up",     # se para de un salto
	&"celebrate",  # festeja
]

var data: CharacterData

## Animación actual (ver ANIMS).
var anim: StringName = &"idle"
## 0..1: cuánto está cargando el salto (se agacha).
var charge: float = 0.0
## -1..1: hacia dónde gira.
var steer: float = 0.0
## Lado del derrape (-1 / 1).
var drift_side: int = 1
## 0..1: esfuerzo (remar o patalear más rápido).
var effort: float = 0.0
## 0..1: velocidad (rodillas más flexionadas y más rebote cuanto más rápido).
var speed: float = 0.0
## Velocidad vertical (m/s): en el aire, subiendo se recoge y bajando se estira.
var vertical_speed: float = 0.0
## Turbo encendido (se agacha aerodinámico).
var turbo: bool = false

## Golpes cortos que se van apagando solos: recién aterrizó / recién despegó.
var _land: float = 0.0
var _pop: float = 0.0
var _shake: float = 0.0
var _time: float = 0.0
var _anim_time: float = 0.0
var _last_anim: StringName = &""
var _features := AvatarFeatures.new()
var _kit: SurferKit


func _ready() -> void:
	if data == null:
		data = CharacterData.new()
	rebuild()


## Vuelve a armar el personaje (llamar al cambiar algo de `data`).
func rebuild() -> void:
	if _kit:
		_kit.free_model()
	_kit = SurferKit.new()
	_kit.build(self, data, _features)
	_kit.animate(_state(), 0.0, true)


## Aterrizó: amortigua flexionando las rodillas.
func land(strength: float = 1.0) -> void:
	_land = maxf(_land, clampf(strength, 0.0, 1.0))


## Despegó (salto o la ola lo lanzó): se estira y tira los brazos arriba.
func pop() -> void:
	_pop = 1.0


## Se seca la cara (después de atravesar una ola): sacude la cabeza y se pasa
## la mano por los ojos.
func shake_off() -> void:
	_shake = 1.0


## Centro de la cabeza (en el espacio del Avatar), para encuadrarla.
func head_center() -> Vector3:
	if _kit and _kit.head and is_inside_tree():
		return to_local(_kit.head.global_position)
	return Vector3(0.0, 2.1, 0.0)


func head_radius() -> float:
	if _kit and _kit.head:
		return 0.53 * _kit.head.basis.get_scale().y
	return 0.53


## Punto de la cara en el mundo (entre los ojos).
func face_position() -> Vector3:
	if _kit and _kit.head and _kit.head.is_inside_tree():
		return _kit.face_position()
	return global_position


func _process(delta: float) -> void:
	_time += delta
	if anim != _last_anim:
		_last_anim = anim
		_anim_time = 0.0
	_anim_time += delta
	_land = move_toward(_land, 0.0, delta / 0.35)
	_pop = move_toward(_pop, 0.0, delta / 0.25)
	_shake = move_toward(_shake, 0.0, delta / 1.0)
	if _kit:
		_kit.animate(_state(), delta)


func _state() -> Dictionary:
	return {
		"anim": anim,
		"t": _anim_time,
		"time": _time,
		"steer": steer,
		"charge": charge,
		"drift_side": drift_side,
		"effort": effort,
		"speed": speed,
		"vy": vertical_speed,
		"land": _land,
		"pop": _pop,
		"turbo": turbo,
		"shake": _shake,
	}
