# Mapas

> **Para subir un mapa desde el editor sin tocar código: ver [COMO_SUBIR_UN_MAPA.md](COMO_SUBIR_UN_MAPA.md).**

Cada mapa es un archivo `.json` en esta carpeta. **Agregar un mapa = agregar un
archivo**: el juego lee la carpeta y lo muestra en el menú. No hay que tocar
código, salvo que el mapa necesite una pieza que todavía no existe.

El editor de mapas lee y escribe este mismo formato. Es un artefacto en Claude:
https://claude.ai/artifact/AWpL9C2N5dKRnid5Fdxyo7. Su código está en
`tools/map_editor/`. Cuando una pieza nueva entra al juego, se suma también ahí
y se vuelve a publicar.

Para pasar un mapa del editor al juego:

1. En el editor, tocar **Guardar para el juego**.
2. Claude lo lee de la base del editor (colección `maps`, campo `json`), lo
   revisa, lo guarda como `world/maps/<id>.json` y corre los tests.

También se puede usar **Ver JSON** y pegar el archivo a mano. Un mapa de acá se
puede abrir en el editor para cambiarlo.

## El archivo

```jsonc
{
  "format": 1,              // versión del formato
  "id": "atoll",            // nombre interno (igual al del archivo)
  "name": "el atolón",      // como se ve en el menú
  "order": 2,               // número del mapa (ver abajo)
  "laps": 3,
  "path": [                 // recorrido, en el sentido de la carrera
    [215, 0],                                        // punto con curva automática
    {"p": [200, -85], "in": [10, -20], "out": [-10, 20]}  // punto con manijas
  ],
  "smoothing": 60,          // cuánto se redondean las curvas
  "half_width": 20,         // mitad del ancho de la pista (m)
  "ring_count": 14,         // círculos de nitro
  "rock_count": 12,         // rocas sobre la pista
  "islands": [
    {"x": 330, "z": 0, "radius": 40, "lighthouse": true, "seed": 130}
  ],
  "pieces": [
    {"type": "volcano", "x": 0, "z": 0, "radius": 40},
    {"type": "geyser", "x": -85.2, "z": -44.4, "phase": 0}
  ]
}
```

- **Coordenadas**: metros, vistas desde arriba. `x` hacia la derecha, `z` hacia abajo.
- **Nombre del archivo y `order`**: el juego guarda el mapa elegido y los
  récords de contrarreloj por el nombre del archivo, con el número (`order`) al
  lado como salvavidas. Se puede cambiar el número (reordenar el menú) o el
  nombre del archivo, de a uno por vez: el otro sirve para encontrar los datos
  y se actualizan solos. Dos mapas no pueden tener el mismo número; uno nuevo
  lleva el siguiente libre.
- **Récords y cambios de pista**: un récord vale solo en la pista donde se hizo.
  Si cambian el recorrido (más de unos 3 m), las vueltas o el ancho, los
  récords de antes quedan archivados y se empieza de cero; si la pista vuelve a
  ser la de antes, vuelven. Las islas, piezas, rocas y aros no cuentan.
- **Recorrido**: es cerrado (el último punto se une con el primero). La largada
  está en el primer punto. Cada punto puede tener manijas Bézier, relativas al
  punto, como en Illustrator o Figma:
  - Sin `in`/`out`: la manija es automática y la curva pasa suave por los vecinos.
  - `[0, 0]`: sin manija, el tramo llega recto (esquina).
  - Otro valor: el tramo se curva hacia donde apunta la manija.

  Después, el juego redondea un poco todo (`smoothing`), para que no queden
  esquinas imposibles de doblar.
- **Recta de la meta** (`start`, opcional, recomendada): `{"x", "z", "angle",
  "back", "front", "bend"}`. La largada va en una recta de `back` metros antes
  y `front` después de la meta (40 y 60 por defecto), en la dirección `angle`
  (grados: 0 = +x, 90 = -z). `bend` (de -10 a 10 grados) la curva apenas. La
  pista sale de la punta de adelante, pasa por los puntos de `path` y vuelve
  por la de atrás. El suavizado no toca la recta, así los surfistas arrancan
  mirando hacia donde va la pista. Sin `start`, la meta va en el primer punto.
- **Sin `path`**: la pista es un anillo de radio `ring_radius` alrededor de la
  primera isla (el mapa "isla").
- **Islas**: `lighthouse` pone un faro. `seed` cambia dónde salen las palmeras;
  si no está, sale del lugar de la isla.

## Piezas

Una pieza es algo especial que el mapa pone en un lugar. Cada una es un archivo
en `world/pieces/`, y `type` es el nombre de ese archivo. Los demás valores son
sus parámetros: lo que no se escribe queda con su valor por defecto. La misma
pieza se puede repetir todas las veces que haga falta.

| Pieza | Qué es | Parámetros |
|---|---|---|
| `volcano` | Isla volcán (se choca como una isla) | `x`, `z`, `radius`; `island_seed` |
| `geyser` | Géiser que explota cada tanto y lanza al que pasa | `x`, `z`; `phase`, `calm`, `warn`, `erupt` (s), `launch_speed` |
| `rock_arch` | Arco de roca de paisaje, se pasa por debajo | `x`, `z`; `angle` (grados), `span`, `height`, `shape_seed`, `stone_color`, `moss_color` |
| `shipwreck` | Barco hundido de paisaje | `x`, `z`; `angle` (grados), `size` |
| `waterfall` | Cascada que se atraviesa: moja la pantalla y frena un poco | `x`, `z`; `angle` (grados), `width`, `height`, `color`, `drag` |
| `tropical_island` | Isla tropical dibujada como figura: arena, selva, palmeras, helechos y arbustos. Se choca | `shape`; `beach_width`, `palm_density`, `rocks`, `crowd`, `sand_color`, `grass_color`, `leaf_color`, `shape_seed` |
| `light_string` | Guirnalda de luces entre dos islas tropicales: cables atados a palmeras de cada una, con focos que se prenden de noche (y al atardecer) | `a`, `b` (un punto en cada isla); `lines` (1 a 20), `style` (`"calida"`, `"fria"` o `"navidad"`) |
| `island_split` | Dividir isla: línea abierta que parte en dos (o más) las islas tropicales que cruza, con mar en el medio | `path`; `width` |
| `rock_formation` | Roca o cueva dibujada como figura (ver abajo) | `shape`; `height`, `ceiling`, `opening`, `opening_width`, `skylights`, `stone_low`, `stone_high`, `grass_color`, `moss_color`, `glow_color`, `darkness`, `adapt_time`, `shape_seed` |

Los colores se escriben como en la web: `"#8a6d5a"`.

Si un mapa pide una pieza que no existe, le falta un parámetro obligatorio o
tiene uno mal escrito, el juego lo avisa al cargar. Los tests (`test_maps`)
revisan que todos los mapas de la carpeta estén bien escritos.

### Rocas y cuevas (`rock_formation`)

Se dibujan como una figura cerrada, con los mismos puntos y manijas que el
recorrido (`shape`). Lo que hacen depende de dónde se dibujan:

- **Si tapan la pista**, esa parte es una cueva:
  - Un túnel del ancho de la pista, con techo a `ceiling` metros.
  - Agua turquesa que brilla y paredes oscuras teñidas de turquesa abajo.
  - Haces de sol por los agujeros del techo (`skylights`: puntos [x, z]).
  - Los ojos se acostumbran: al entrar se ve casi negro y de a poco aparece
    todo; al salir hay un fogonazo de luz. Es por jugador.
  - Con el techo bajo no se puede saltar hasta el techo: se sube más despacio y
    se frena antes de tocarlo.
- **Si no tocan la pista**, es una roca grande de paisaje. Con `opening: true`
  tiene un arco abajo por donde se ve el mar.
- **Si la tocan un poco**, las dos cosas a la vez.

El túnel siempre es del ancho de la pista: el borde de la figura no la angosta
(por ahora).

**Estilo buscado.** Las referencias son fotos de acantilados, arcos naturales y
cuevas marinas, llevadas al estilo low-poly del juego:

- **Afuera**: piedra en capas, rojiza y ocre abajo, clara (beige o gris) arriba,
  con un poco de pasto arriba y musgo o algas en la base. Formas de peñasco
  alto, o arcos con el mar del otro lado.
- **Boca**: un arco irregular, bien oscuro adentro.
- **Adentro**: el agua es la luz. Turquesa brillante que tiñe las paredes de
  abajo; arriba la piedra queda cálida. Si hay agujeros en el techo, haces de sol.
- **Luz**: el contraste al entrar y al salir es parte de la experiencia (los ojos
  que se acostumban), en todas las cuevas de todos los mapas.

Para cambiar el clima de una cueva (de hielo, volcánica...) se usan sus colores.

### Islas tropicales y cortes

La isla tropical se dibuja como figura cerrada. Toda la figura es arena; más
adentro (a `beach_width` de la orilla, un poco irregular) empieza la selva.
Del lado que da a la pista la vegetación va tupida; atrás, más rala (pesa
menos y casi no se ve). En la orilla que mira a la pista hay público (gente
alentando, sillas, reposeras, toallas, sombrillas y banderas): `crowd` dice
cuánto (1 normal, 0 nadie, 2 el doble).

Para partir una isla en dos se dibuja un corte (`island_split`): una línea
abierta que cruce la isla de mar a mar. Cada isla tropical que cruza queda
partida en islas independientes (cada una con su playa, su selva y sus
palmeras) y en el medio queda mar de `width` metros. Si la línea entra desde
el mar sin cruzarla entera, le hace una bahía. No importa en qué lugar de la
lista de piezas esté el corte: las islas lo buscan al prepararse (ver
`TropicalIslandPiece.prepare`).

### Hacer una pieza nueva

1. Crear `world/pieces/<nombre>.gd`, que herede de `MapPiece`.
2. Sus variables son sus parámetros. Los que el mapa tiene que dar sí o sí van en
   `const REQUIRED := ["x", "z"]`.
3. Hacer lo que necesite, todo dentro de la pieza:
   - `build(course)`: construirse. Se llama apenas está el recorrido, antes que
     las islas del mapa.
   - `finish(course)`: si necesita ver el mapa entero.
   - `affect_rider(course, rider)`: qué le pasa a un surfista que la toca.
     Devuelve `true` si eso corta el resto del paso, por ejemplo si se cayó.
   - `update(course, delta)`: algo que haga sola en cada paso.
4. Sumarla a la tabla de arriba y al editor de mapas.

`Course` no sabe qué hace cada pieza: solo las arma y las llama.
