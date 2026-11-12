class_name RiderInput
extends RefCounted
## Lo que el Rider recibe cada frame. Lo genera un PlayerController (mando/teclado)
## o, más adelante, un AIController (bot). El Rider no sabe quién lo controla.

## -1 = izquierda, +1 = derecha.
var steer: float = 0.0
## -1 = frenar, +1 = acelerar a fondo.
var throttle: float = 0.0
## Botón A pulsado este frame (saltar).
var jump_pressed: bool = false
## Botón A mantenido (en el aire: truco).
var trick: bool = false
## Botón de derrape mantenido.
var drift: bool = false
## Botón B mantenido (turbo). Todavía no se usa.
var turbo: bool = false
## Cuántas veces se pulsó A desde el frame anterior (para levantarse spameando).
var mash_presses: int = 0
## Tecla de prueba para tirarse de la tabla.
var debug_fall: bool = false

## Mirar hacia atrás (gatillo izquierdo / Q): solo cambia la cámara.
var look_back: bool = false

## Tocó el turbo este frame (cada toque dispara una ráfaga).
var turbo_pressed: bool = false
