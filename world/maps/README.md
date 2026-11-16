# Mapas

Cada mapa es un archivo `.json` en esta carpeta. **Agregar un mapa = agregar un
archivo**: el juego lee la carpeta y lo muestra en el menú. No hay que tocar
código, salvo que el mapa necesite una pieza que todavía no existe.

El editor de mapas (artefacto en Claude) lee y escribe este mismo formato: se
exporta desde ahí, se copia acá y listo. También se puede abrir un mapa de acá
en el editor para cambiarlo.

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
- **`order`**: el juego guarda el mapa elegido y los récords de contrarreloj por
  este número. Un mapa nuevo lleva el siguiente número libre, y **nunca se le
  cambia el número a un mapa que ya existe**.
- **Recorrido**: es cerrado (el último punto se une con el primero). La largada
  está en el primer punto. Cada punto puede tener manijas Bézier, relativas al
  punto, como en Illustrator o Figma:
  - Sin `in`/`out`: la manija es automática y la curva pasa suave por los vecinos.
  - `[0, 0]`: sin manija, el tramo llega recto (esquina).
  - Otro valor: el tramo se curva hacia donde apunta la manija.

  Después, el juego redondea un poco todo (`smoothing`), para que no queden
  esquinas imposibles de doblar.
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

Los colores se escriben como en la web: `"#8a6d5a"`.

Si un mapa pide una pieza que no existe, le falta un parámetro obligatorio o
tiene uno mal escrito, el juego lo avisa al cargar. Los tests (`test_maps`)
revisan que todos los mapas de la carpeta estén bien escritos.

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
