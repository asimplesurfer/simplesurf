class_name ExoticGrace
extends RefCounted
## Período de gracia al empezar un truco exótico (la ola de borde, el tubo):
## un salvavidas para no entrar y caerse enseguida.
##   - Durante TIME s no se cae: el equilibrio no pasa de LIMIT.
##   - El stick que ya venía apretado al empezar no cuenta mientras dura la
##     gracia (venía doblando para agarrar la ola): hay tiempo de acomodarlo.
##     Apenas se lo suelta (o se lo mueve para el otro lado) vuelve a contar.
## Lo usan los estados `lip` y `barrel` (ver `steer` y `clamp_balance`).

const TIME := 1.0
const LIMIT := 0.7
## Por debajo de esto el stick cuenta como suelto.
const RELEASE := 0.25

## Cuánto hace que corre la gracia (s).
var time: float = 0.0
## Hacia dónde venía apretado el stick al empezar (0: suelto o ya lo soltó).
var _held: float = 0.0


## Empieza: `steer_now` es el stick en ese momento.
func start(steer_now: float) -> void:
	time = 0.0
	_held = signf(steer_now) if absf(steer_now) > RELEASE else 0.0


## true mientras dura la gracia.
func active() -> bool:
	return time < TIME


## El stick que cuenta: el que venía apretado de antes no, mientras dura la
## gracia. `running`: si la gracia corre (el tubo la empieza cuando ya está
## armado; mientras se forma solo se mira si soltó el stick).
func steer(raw: float, delta: float, running: bool = true) -> float:
	if running:
		time += delta
	if _held != 0.0 and (absf(raw) < RELEASE or signf(raw) != _held):
		_held = 0.0
	if _held != 0.0 and active():
		return 0.0
	return raw


## El equilibrio, sin pasar de LIMIT mientras dura la gracia.
func clamp_balance(balance: float) -> float:
	return clampf(balance, -LIMIT, LIMIT) if active() else balance
