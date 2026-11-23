# Ola tubo (guardada para más adelante)

Handicap "elegante" para el que va último: le aparece una ola grande que forma un
tubo; si entra, va más rápido, carga nitro y sale escupido con turbo. Adentro hay
que mantener el equilibrio con el stick.

**Estado: apagada** (`TubeDirector.ENABLED = false` en `core/race/tube_director.gd`).
El concepto gustó, pero la ola todavía se ve mal (forma y color) y llevaba mucho
tiempo: se retoma más adelante. Todo el código sigue en el repo y no hace nada
mientras está apagada.

## Cómo volver a probarla

1. `core/race/tube_director.gd`: `const ENABLED := true`.
2. `tests/run_tests.gd`: sumar `"res://tests/suites/test_tube.gd"` a `SUITES`.
3. En carrera o en el modo libre, la tecla **Y** hace aparecer una ola adelante de J1
   (para probar sin tener que ir último). Volver a poner la línea de ayuda de la Y
   en `ui/hud/hud.gd` (`_update_help`, modo libre).

## Lo que se decidió con el usuario

1. Equilibrio = tu lugar en la pared de la ola (arriba te tapa el labio, abajo te
   escupe la espuma). Sin indicador: el borde de la pantalla avisa con color.
2. Si fallás: caída directa (como un obstáculo) y perdés el nitro que sumaste adentro.
3. Duración: base según qué tan atrás estás (8 a 12 s) ± 1 s al azar.
4. Se ve cuánto falta: luz al final del tubo.
5. Velocidad adentro calculada para recuperar bastante (70 % de la distancia).
6. El nitro se llena del todo adentro.
7. Aparece si vas último **y** lejos del primero (55 m); una vez por vuelta, no en la
   largada ni cerca de la meta.
8. Es un portal: los que vienen cerca también pueden entrar; adentro no se chocan.
9. Los bots también la usan (fallan según la dificultad).
10. Aros y rocas del tramo desaparecen mientras está.
11. Modo libre: sin lógica propia todavía (solo la tecla Y).
12. Contrarreloj: nunca.
13. Salida: turbo, chorro de espuma y golpe de cámara.
14. Después del primer intento: que nazca lejos (afuera de la pista) y se forme
    el tubo al entrar a la pista; que se mueva a lo ancho mientras nadie entra;
    sin olas comunes mientras está; más fácil al principio; sin curvas cerradas;
    colores del mar.

## Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| La ola (forma, recorrido suavizado, portal, partículas) | `world/tube/tube_wave.gd` |
| Su shader (colores copiados del agua) | `world/tube/tube_wave.gdshader` |
| Cuándo aparece en carrera, tecla Y | `core/race/tube_director.gd`, `core/race/race_manager.gd` |
| Estado del surfista adentro (equilibrio, nitro, salida/caída) | `core/rider/states/state_tube.gd` |
| Señales y `in_tube()` del surfista | `core/rider/rider.gd` |
| Pose adentro (agachado, mano en la pared) | `characters/surfer_anim.gd` (`_tube`), `core/rider/rider_visual.gd` |
| Cámara adentro y llegando a la boca | `core/camera/chase_camera.gd` (`_tube_view`) |
| Bot: ir a la boca y equilibrio | `ai/ai_controller.gd` (`_tube_target`, `_tube`) |
| Aviso en el borde del HUD | `ui/shaders/tube_warning.gdshader`, `ui/hud/hud.gd` |
| Sin olas comunes mientras hay tubo | `world/wave_manager.gd` |
| Tests | `tests/suites/test_tube.gd` (fuera de la corrida mientras está apagada) |

## Herramientas para verla

- Capturas desde varios ángulos: `tools/shot_tube.gd`.
- Video de un tubo de principio a fin con la cámara del juego (un bot maneja a J1),
  un PNG por cuadro: `tools/video_tube.gd`. Imprime dónde está la cámara respecto
  de la ola en cada cuadro (sirve para encontrar cuándo atraviesa la malla).

```
xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-driver opengl3 \
  --resolution 960x540 --fixed-fps 30 --script res://tools/video_tube.gd -- carpeta
ffmpeg -framerate 30 -i carpeta/f%04d.png -pix_fmt yuv420p tubo.mp4
```

(Con la ola apagada, las herramientas igual la crean a mano: no dependen de `ENABLED`,
salvo la tecla Y y el director, que video_tube usa con `spawn_test`.)

## Lo que falta / ideas para cuando se retome

- **Lo visual es lo que no convenció.** La ola es una malla armada a mano
  (un perfil 2D extruido a lo largo de la pista) con un shader propio: desde
  afuera se ve como un bloque y los colores no terminan de integrarse con el mar.
  Alternativas a probar:
  - Hacer la ola **con el agua misma** (deformar la malla del agua en ese tramo,
    como las olas grandes de `water_surface.gdshaderinc`) y sumar aparte solo el
    labio que se curva. Así comparte color, luz y espuma con el mar.
  - Un modelo hecho a mano (Blender) con la forma de un tubo, estirado a lo largo.
  - Mirar referencias de juegos de surf estilizados para la forma del labio.
- Desde atrás, antes de entrar, la boca se lee mal (no se entiende que es un tubo).
- La jugabilidad funciona pero falta ajustar (el usuario lo marcó como menor).
