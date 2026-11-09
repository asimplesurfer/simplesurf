# MVP – Juego de surf (friend slop 3D)

## Contexto
Friend slop 3D muy simple, en la línea de Just Volleyball, pensado para Nintendo Switch 2 (si se puede, que también corra en Switch 1, pero no es un limitante). Un Joy-Con por jugador, pocos botones. Estética de personajes tipo Mii/Wii Sports, con contorno negro grueso y colores planos. Se desarrolla en PC con **Godot 4**.

## Alcance
- 1 mapa: una isla circular, 2 vueltas alrededor.
- 1 modo: carrera. Gana el primero en cruzar la meta.

## Controles
- **Stick:** girar.
- **Botón A:** derrapar en tierra / hacer truco y giro en el aire.
- **Botón B:** usar el turbo.
- Al caer de la tabla, se spamea un botón para levantarse.
- Compatible con mando y teclado.

## Recursos del jugador

### Nitro (turbo)
- Turbo y nitro son **lo mismo**: una sola barra.
- Se carga pasando por los círculos de velocidad y haciendo trucos.
- **El jugador decide cuándo usarlo** y tiene su propio botón (B).
- Un truco fallido la deja en 0.

### Motivación
- Mini sprint **automático** tras una acción del jugador (derrape exitoso, pasar por un círculo).
- El jugador **no** decide cuándo usarla y **no** aparece en el HUD.
- No gasta nitro.

## Terreno
- **Obstáculos:** chocar con uno tira al jugador de la tabla.
- **Círculos de velocidad:** pasar por dentro carga nitro y da motivación.
- **Olas:** se implementan las dos variantes, seleccionables:
  - Una ola constante a la izquierda.
  - Olas pequeñas que aparecen por oleadas y se aprovechan para hacer trucos.

## Visual
- Con motivación o turbo activos, salen rayas a los lados de la pantalla como efecto de velocidad.

## Mecánicas

### Derrape
- Se puede hacer hacia los dos lados.
- La tabla se pone de costado con una animación y levanta algo visible detrás, en forma de cono hacia atrás y no muy lejano.
- Exige una velocidad mínima y ralentiza a quien lo hace.
- No tiene cooldown: el de atrás puede esquivarlo, y el camino es lo bastante ancho para hacerlo.
- Si le da a alguien dentro del rango, ese jugador cae de su tabla y quien derrapó gana motivación, así que acelera después de tirar a alguien.
- Tras aterrizar de un truco manteniendo A, no se dispara un derrape solo (exige pulsación nueva o un margen corto).

### Trucos
- Subir a una ola y moverse por encima con suficiente velocidad impulsa al jugador al aire. Cuanta más velocidad antes de la cresta, más alto salta y más tiempo tiene para el truco.
- Mientras se mantiene pulsado el botón, la tabla gira bajo el jugador y se va cargando el nitro.
- Al soltar el botón, el giro termina hasta que la tabla queda mirando al frente, como normalmente.
- Si toca el agua sin haber terminado el giro, el truco falla, el jugador cae al agua y el nitro vuelve a 0.
- Mucho tiempo en el aire sube el volumen de la música de fondo para darle épica; al volver al agua, vuelve a la normalidad.
- Con pantalla dividida, el volumen épico lo dispara el humano con más tiempo en el aire (los bots no cuentan).

### Caer de la tabla
- Se muestra al personaje acostado y la UI indica qué botón pulsar repetidamente.
- Al llegar a una velocidad mínima de pulsaciones, el personaje se para sobre la tabla y el botón desaparece de la UI.

## Multijugador
- Pantalla dividida, una por jugador. Cada pantalla tiene su propio HUD y sus propias rayas de velocidad.

## Bot
Existe para poder testear el juego sin otros jugadores. Tiene niveles de dificultad.
- Pasa por dentro de los círculos de nitro.
- Cuando hay olas, hace trucos para cargar nitro, con posibilidad de fallar según la dificultad.
- Esquiva obstáculos.
- Si un rival está delante y cerca, evita quedar directamente detrás, previendo un derrape.
- Si él va adelante y cerca de un rival, trata de ponerse frente a él para desestabilizarlo con el derrape, según la dificultad.
- Sin importar la dificultad, al caer siempre spamea a la velocidad máxima para levantarse.
- **Criterio de terminado:** debe ganarle al menos una carrera al desarrollador.

## Sistema
- Menú: elegir personaje, personalizar, empezar, resultado final y botón de reinicio.
- HUD: nitro (turbo), vuelta actual y posición.
- Música de fondo durante la carrera (la canción ya está disponible).

## Decisiones tomadas
- Motor: Godot 4 (GDScript).
- Movimiento por **coordenadas de pista** (progreso + desvío lateral), no física libre.
- Turbo y nitro son un solo recurso; la motivación es aparte y automática.
- Ambas variantes de olas en el MVP.

## Pendiente de verificar
- Estado actual del soporte de Switch 2 en los ports de Godot (W4 Games, Lone Wolf u otros).
- Renderer: Mobile como punto medio razonable; confirmarlo antes de avanzar mucho.
