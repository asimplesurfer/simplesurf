# MVP – Juego de surf (friend slop 3D)

## Contexto
Friend slop 3D muy simple, en la línea de Just Volleyball, pensado para Nintendo Switch (un Joy-Con por jugador, pocos botones). Estética de personajes tipo Mii/Wii Sports, con contorno negro grueso y colores planos. Se desarrolla en PC; motor preferido: Godot (a confirmar).

## Alcance
- 1 mapa: una isla circular, 2 vueltas alrededor.
- 1 modo: carrera. Gana el primero en cruzar la meta.

## Terreno
- **Obstáculos:** chocar con uno tira al jugador de la tabla.
- **Círculos de velocidad:** pasar por dentro carga nitro y da motivación.
- **Olas:** frecuencia aún sin definir. Para el MVP hay dos variantes posibles:
  - Una ola constante a la izquierda.
  - Olas pequeñas que aparecen por oleadas y se aprovechan para hacer trucos.

## Estados
- **Motivación:** mini sprint que se activa solo tras una acción del jugador. El jugador no decide cuándo usarlo y no aparece en el HUD.

## Visual
- Con motivación o turbo activos, salen rayas a los lados de la pantalla como efecto de velocidad.

## Mecánicas

### Derrape
- Se puede hacer hacia los dos lados.
- La tabla se pone de costado con una animación, y levanta algo visible detrás, en forma de cono hacia atrás y no muy lejano.
- Exige una velocidad mínima y ralentiza a quien lo hace.
- No tiene cooldown: el de atrás puede esquivarlo, y el camino es lo bastante ancho para hacerlo.
- Si le da a alguien dentro del rango, ese jugador cae de su tabla y quien derrapó gana motivación, así que acelera después de tirar a alguien.

### Trucos
- Subir a una ola y moverse por encima con suficiente velocidad impulsa al jugador al aire. Cuanta más velocidad antes de la cresta, más alto salta y más tiempo tiene para el truco.
- Mientras se mantiene pulsado un botón, la tabla gira bajo el jugador y se va cargando el turbo.
- Al soltar el botón, el giro termina hasta que la tabla queda mirando al frente, como normalmente.
- Si toca el agua sin haber terminado el giro, el truco falla, el jugador cae al agua y el turbo vuelve a 0.
- Mucho tiempo en el aire sube el volumen de la música de fondo para darle épica; al volver al agua, vuelve a la normalidad.

### Caer de la tabla
- Se muestra al personaje acostado y la UI indica qué botón pulsar repetidamente.
- Al llegar a una velocidad mínima, el personaje se para sobre la tabla y el botón desaparece de la UI.

## Multijugador
- Pantalla dividida, una por jugador.

## Bot
Existe para poder testear el juego sin otros jugadores. Tiene niveles de dificultad.
- Pasa por dentro de los círculos de nitro.
- Cuando hay olas, hace trucos para cargar nitro, con posibilidad de fallar según la dificultad.
- Si un rival está delante y cerca, evita quedar directamente detrás, previendo un derrape.
- Si él va adelante y cerca de un rival, trata de ponerse frente a él para desestabilizarlo con el derrape, según la dificultad.
- Sin importar la dificultad, al caer siempre spamea a la velocidad máxima para levantarse.
- **Criterio de terminado:** debe ganarle al menos una carrera al desarrollador.

## Sistema
- Compatible con mando y teclado; fácil de llevar a Switch 2, con pocos botones.
- Menú: elegir personaje, personalizar, empezar, resultado final y botón de reinicio.
- HUD: turbo, vuelta actual, nitro y posición.
- Música de fondo durante la carrera (la canción ya está disponible).
