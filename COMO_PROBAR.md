# Cómo probar el juego sin tener Godot instalado

Todo se compila solo en GitHub con **GitHub Actions** (el workflow está en
`.github/workflows/web.yml`). Cada vez que se sube un cambio al repositorio:

1. GitHub descarga Godot en una máquina suya.
2. Corre los tests automáticos (`tests/run_tests.gd`).
3. Exporta el juego para navegador (WebAssembly + WebGL 2).
4. Si el cambio está en la rama `main`, lo publica en **GitHub Pages**.

## Jugar en el navegador (GitHub Pages)

Configuración, una sola vez:

1. En GitHub, abre el repositorio → **Settings** → **Pages**.
2. En **Build and deployment → Source**, elige **GitHub Actions**.
3. Sube algo a `main` (o ve a **Actions → Web build → Run workflow** sobre `main`).

El juego queda en `https://<usuario>.github.io/simplesurf/`.

> GitHub Pages en un repositorio **privado** solo está disponible con un plan pago
> (GitHub Pro / Team). Con la cuenta gratis, el repositorio tiene que ser público.

## Ver si un cambio compila

Pestaña **Actions** del repositorio → el último **Web build**:

- ✅ verde: compila y pasan los tests.
- ❌ rojo: abre el paso que falló (normalmente **Tests**) para ver el error.

Cada build deja también un zip descargable (**simplesurf-web**) en la parte de abajo de la ejecución.
Ojo: ese zip no funciona con doble clic en `index.html`, necesita un servidor web.

## Controles

| Acción | Teclado | Mando |
|---|---|---|
| Girar | A / D o flechas | Stick izquierdo o cruceta |
| Levantarse (spamear) | Espacio | A |
| Caerse (para probar) | R | Y |

Si el teclado no responde, haz clic dentro del juego.

## Qué hay por ahora

- La "pastilla" (personaje) sobre una tabla, en un mar con olas que se mueve.
- El juego empieza con el jugador **caído en el agua**. Spameando A:
  1. se sube a la tabla y queda **acostado** (spameando también rema un poco);
  2. si sigue spameando, **se para** y empieza a avanzar solo. El stick gira.
- Si se pulsa lento (menos de ~3,5 veces por segundo) la barra no sube.
- Los valores de balance están en `core/rider/rider_stats.tres`.
