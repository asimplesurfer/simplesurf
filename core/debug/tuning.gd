class_name Tuning
extends RefCounted
## Valores para probar en el momento (panel de ajustes, F9). Arranca siempre en
## el valor elegido y no se guarda: lo que se mueva en el panel dura la partida.

## Agua: 0 = el color original, 1 = azul marino oscuro. Elegido: 0.6.
const WATER_DARK_DEFAULT := 0.6

static var water_dark: float = WATER_DARK_DEFAULT
## Se ve el panel (escondido de entrada; F9 lo muestra).
static var panel_visible: bool = false
