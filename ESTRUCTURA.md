# Estructura del proyecto – Juego de surf (Godot 4)

## Principios de arquitectura

1. **El Rider no sabe quién lo controla.** Recibe un `RiderInput` (steer, drift, trick, turbo, mash) que genera un `PlayerController` (mando/teclado) o un `AIController` (bot). Ambos heredan de `base_controller`.
2. **Movimiento por coordenadas de pista.** El Rider no tiene una posición 3D propia: tiene `progress` (cuánto avanzó por el camino) y `lateral` (desvío izquierda/derecha del centro). `TrackSpace` convierte esos dos números a una posición y orientación en el mundo usando el `Path3D` de la isla. La altura (olas, saltos) se maneja aparte.
3. **Máquina de estados** en el Rider: `riding`, `drifting`, `airborne` (incluye el truco), `fallen`.
4. **Motivación no es un estado.** Es un timer en el Rider que se superpone a los estados y no gasta nada.
5. **Nitro y turbo son un solo recurso:** una variable `nitro`, cargada por aros y trucos, gastada con el botón de turbo.
6. **`RiderVisual` separado de la lógica.** Modelo, animaciones, outline y personalización viven en otro nodo.
7. **Datos en Resources:** `RiderStats`, `CharacterData`, `AIDifficulty`, `RaceConfig`/`RacerSlot`. Todo lo que se balancea se edita sin tocar código.
8. **`RaceManager` es un nodo de la escena de carrera**, no un autoload. Nace y muere con ella; reiniciar es recargar la escena con el mismo config.
9. **Todo nace con `player_index`:** input (`p1_`, `p2_`), cámara, HUD y viewport, desde el primer día.
10. **Los estados no conocen el audio ni los efectos.** Emiten señales y otros nodos reaccionan.

## Árbol de carpetas

```
res://
├── project.godot
├── autoload/
│   ├── game_manager.gd         # flujo: menús → selección → carrera → resultados
│   └── audio_manager.gd        # música, volumen dinámico por señales
├── core/
│   ├── rider/
│   │   ├── rider.tscn
│   │   ├── rider.gd            # Node3D: progress, lateral, speed, nitro, motivation_timer
│   │   ├── rider_input.gd      # steer, drift, trick, turbo, mash
│   │   ├── rider_stats.tres    # Resource de balance
│   │   ├── rider_visual.tscn   # mesh, animaciones, outline, personalización
│   │   └── states/
│   │       ├── state_machine.gd
│   │       ├── state.gd
│   │       ├── state_riding.gd
│   │       ├── state_drifting.gd   # cono por progreso/desvío relativo a rivales
│   │       ├── state_airborne.gd   # truco; emite señales de tiempo en el aire
│   │       └── state_fallen.gd     # spam de botón para levantarse
│   ├── controllers/
│   │   ├── base_controller.gd      # get_input(delta) -> RiderInput
│   │   ├── player_controller.gd    # mando/teclado con prefijos p1_, p2_
│   │   └── ai_controller.gd
│   ├── track/
│   │   └── track_space.gd          # (progress, lateral) <-> posición/orientación 3D
│   └── race/
│       ├── race_config.gd          # Resource: lista de corredores
│       ├── racer_slot.gd           # Resource: tipo, player_index, personaje, dificultad
│       ├── race_manager.gd         # vueltas, posiciones, meta, ranking
│       ├── checkpoint.gd           # validación secundaria de progreso
│       └── finish_line.gd
├── world/
│   ├── island/
│   │   └── island.tscn             # Path3D del circuito, terreno, puntos de aparición
│   ├── nitro_ring.gd               # carga nitro y da motivación
│   ├── obstacle.gd                 # tira al rider (por coordenadas de pista)
│   ├── wave_manager.gd             # modos CONSTANT_LEFT y SURGES
│   ├── wave.gd                     # zona que lanza al aire
│   └── water/
│       ├── wave_definition.gd      # parámetros de ola compartidos shader/script
│       └── water.gdshader          # plano de agua falso
├── characters/
│   ├── character_data.gd           # Resource: nombre, malla, colores
│   └── data/                       # .tres por personaje
├── ai/
│   └── ai_difficulty.gd            # Resource: reacción, fallo de trucos, agresividad
├── effects/                        # cono del derrape, estela de truco
├── ui/
│   ├── split_screen/
│   │   ├── split_screen.tscn       # 1 o 2 SubViewports
│   │   └── player_viewport.tscn    # SubViewport + cámara + HUD + rayas de velocidad
│   └── menus/
│       ├── main_menu.tscn
│       ├── character_select.tscn
│       └── results.tscn
└── assets/
    ├── audio/
    ├── models/
    └── shaders/                    # outline (casco invertido), speed_lines
```

## Scripts clave

**`Rider`:** guarda `progress`, `lateral`, `speed`, `nitro`, `motivation_timer`, altura y velocidad vertical. Reglas compartidas: aplicar velocidad, activar motivación, gastar nitro con el turbo, caerse. Señales: `fell`, `lap_completed`, `trick_failed`, `trick_landed`, `nitro_changed(value, max)`, `airtime_changed`.

**`TrackSpace`:** a partir del `Path3D`/`Curve3D` de la isla, convierte (progress, lateral) a transform 3D. Expone también el largo total del circuito.

**Estados:**
- `riding`: movimiento normal; pasa a `drifting` con velocidad mínima y botón A; lee `turbo` para gastar nitro.
- `drifting`: desliza el desvío lateral, frena un poco, y cada frame comprueba rivales dentro del cono (diferencia de progreso y de desvío, sin colisionadores físicos). Si impacta, llama `rival.fall()` y se da motivación.
- `airborne`: se entra desde una ola con impulso proporcional a la velocidad. Mientras A esté mantenido, gira y carga nitro. Al aterrizar sin haber terminado el giro, nitro a 0 y pasa a `fallen`. Exige pulsación nueva de A para derrapar tras aterrizar.
- `fallen`: animación, `mash_prompt` y conteo de pulsaciones por segundo; vuelve a `riding` al pasar el umbral.

**`RaceManager`:** el orden de carrera sale de `lap * track_length + progress`. Los checkpoints solo validan que nadie haga atajos. Emite `race_finished(ranking)`.

**Bot (`AIController`):** base = elegir un desvío objetivo sobre el camino. Prioridades: levantarse (spam máximo) → evitar quedar detrás de un rival cercano → ponerse delante para derrapar → ir al siguiente aro → trucos en olas. Esquiva obstáculos comparando coordenadas. La dificultad viene de `AIDifficulty`.

**Agua y olas:** la altura del agua se calcula con una función, y la ola se define una sola vez (`wave_definition.gd`) para que `water.gdshader` y el script usen los mismos parámetros y la tabla no flote ni se hunda respecto a lo visible.

**Pantalla dividida:** un `SubViewport` por jugador sobre el mismo `World3D`, cada uno con su cámara, su HUD y sus rayas de velocidad. El costo real es renderizar la escena dos veces; se controla con materiales simples y, si hace falta, resolución reducida.

**Audio:** `AudioManager` escucha `airtime_changed` de los humanos activos y hace tween del volumen según el mayor tiempo en el aire. Los bots no cuentan.

## Orden de construcción

1. Rider sobre el camino con `TrackSpace`, teclado, y `player_index` + dos viewports desde ya (aunque el segundo sea un bot).
2. Isla circular, `RaceManager`, vueltas, meta y posiciones: ya hay carrera jugable.
3. Aros de nitro, motivación, turbo con botón y obstáculos.
4. Estado `fallen` con spam.
5. Derrape.
6. Olas y trucos, con audio por señales.
7. Bot: primero siguiendo el camino, después las reglas.
8. Menús, `RaceConfig`, personajes, HUD, outline, rayas de velocidad, pulido.

## Testeo automático de bots

- Correr con `--headless` y bots contra bots, con semilla fija para el azar y resultados a CSV.
- Cuidado con `Engine.time_scale` alto: puede romper la lógica; subirlo poco o simular con pasos fijos.
- El criterio "ganarle al desarrollador" se vuelve medible: tiempo de vuelta por dificultad contra el mejor tiempo propio.

## Pendiente de verificar

- Renderer: Mobile como punto medio para Switch 2 / Switch 1; confirmar antes de avanzar mucho.
- Estado actual del soporte de Switch 2 en los ports de Godot.
