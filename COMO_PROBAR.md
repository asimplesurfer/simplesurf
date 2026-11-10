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
| Acelerar / frenar | W / S o flechas | Stick izquierdo o cruceta |
| Girar | A / D o flechas | Stick izquierdo o cruceta |
| Saltar (mantener = cargar, hasta 1 s) | Espacio | Botón de abajo (A / ✕) |
| Truco (en el aire, mantener) | Espacio | Botón de abajo |
| Derrapar (mantener) | Shift | Botón izquierdo (X / □) o RB |
| Levantarse (spamear) | Espacio | Botón de abajo |
| Caerse (para probar) | R | Botón de arriba (Y / △) |
| Cambiar distribución del mando | M | — |

Si el teclado no responde, haz clic dentro del juego.

**Mandos genéricos:** algunos mandos USB genéricos, en el navegador, tienen los botones
en otro orden. El juego intenta detectarlo solo; si los botones no coinciden, apreta **M**
para cambiar entre "estándar" y "genérico (tipo PlayStation)". La elección se guarda.

## Qué hay por ahora

- La "pastilla" (personaje) sobre una tabla, en un mar con olas que se mueve.
- El juego empieza con el jugador **caído en el agua**. Spameando A:
  1. se sube a la tabla y queda **acostado** (spameando también rema un poco);
  2. si sigue spameando, **se para**. Con W / stick arriba avanza.
- Si se pulsa lento (menos de ~3,5 veces por segundo) la barra no sube.
- **Salto:** mantener carga (se agacha) y al soltar salta; más carga, más alto.
- **Truco:** en el aire, mantener el botón gira la tabla y carga nitro. Al soltar
  termina el giro. Si toca el agua girando: se cae y pierde el nitro.
- **Derrape:** la tabla se pone de costado, frena y tira un cono de agua hacia atrás.
  Si alcanza a otro jugador, lo tira de la tabla.
- **Olas grandes:** aparecen al azar (nunca encima del jugador). Subirlas rápido te lanza al aire.
- Los valores de balance están en `core/rider/rider_stats.tres`.
