# SimpleSurf: cómo trabajar en este repo

Juego de surf en Godot 4.5.1 (GDScript), publicado en
https://asimplesurfer.github.io/simplesurf/ por GitHub Actions ("Web build").

## Con el usuario

- Respondé en español rioplatense.
- Cuando termines un cambio: hacé el PR y **mergealo vos** (no esperes al CI).
- Después revisá el CI del merge en `main` (unos 10 minutos) y arreglá lo que falle.
- **Siempre decile el número de build** que tiene que ver para probar el cambio:
  "para ver esto tiene que decir **build N**" (arriba a la derecha en el menú).
  - N es el `run_number` de la corrida de "Web build" que disparó tu merge en `main`
    (por ejemplo, con `mcp__github__actions_list` → `list_workflow_runs`, rama `main`).
  - Avisale cuando esa corrida termine bien: recién ahí está online.
  - Si en el menú ve un número menor, tiene una versión vieja (Cmd+Shift+R para recargar).
- El número lo pone el CI en `core/build_info.gd` (`const BUILD := 0` se reemplaza al
  publicar). No cambies esa línea a mano: en local dice "build local".

## Antes de commitear

- Tests: `godot --headless --path . --fixed-fps 60 --script res://tests/run_tests.gd`.
  Commiteá solo si termina en `TESTS OK`.
- Si fallan "por defecto el mapa..." o "por defecto el salto...", es un
  `settings.cfg` viejo en `~/.local/share/godot/app_userdata/SimpleSurf/`: borralo y
  volvé a correr (en el CI no pasa).
- Si agregás un `class_name` nuevo, corré `godot --headless --path . --import` antes
  de los tests.
- Nada de force-push: si la rama quedó atrás, mergeá `origin/main`.

## Reglas del juego

- Textos de la interfaz: solo caracteres Latin-1 (la fuente web no tiene ◀ ▶ ← → etc.;
  hay un test que lo revisa).
- Personajes y accesorios de cultura pop: inspirados o genéricos, nunca copias.
- Si algo está roto, arreglalo; no lo saques sin preguntar.
- Las animaciones nuevas se revisan con capturas (de costado también), no solo con tests.
