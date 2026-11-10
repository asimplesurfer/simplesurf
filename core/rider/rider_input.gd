class_name RiderInput
extends RefCounted
## Lo que el Rider recibe cada frame. Lo genera un PlayerController (mando/teclado)
## o, más adelante, un AIController (bot). El Rider no sabe quién lo controla.

## -1 = izquierda, +1 = derecha.
var steer: float = 0.0
## Botón A mantenido (derrape en el agua). Todavía no se usa.
var drift: bool = false
## Botón A mantenido en el aire (truco). Todavía no se usa.
var trick: bool = false
## Botón B mantenido (turbo). Todavía no se usa.
var turbo: bool = false
## Cuántas veces se pulsó A desde el frame anterior (para levantarse spameando).
var mash_presses: int = 0
## Tecla de prueba para tirarse de la tabla.
var debug_fall: bool = false
