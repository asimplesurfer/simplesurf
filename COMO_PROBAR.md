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

| Acción | J1 teclado | J2 teclado (con 2 jugadores) | Mando |
|---|---|---|---|
| Frenar (automático) · acelerar/frenar (manual) | S · W / S | ↓ · ↑ / ↓ | Stick o cruceta |
| Girar | A / D | ← / → | Stick o cruceta |
| Saltar · truco (en el aire, mantener) | Espacio | Enter | Botón de abajo (A / ✕) |
| Derrapar (mantener) | Shift | . | Botón izquierdo (X / □) o RB |
| Turbo (gasta nitro) | E | - | Botón derecho (B / ○) |
| Levantarse (spamear) | Espacio | Enter | Botón de abajo |
| Caerse (para probar) | F | Retroceso | Botón de arriba (Y / △) |

Con 1 jugador, J1 también puede usar las flechas.

| Tecla | Qué hace |
|---|---|
| 1 / 2 | Cantidad de jugadores (reinicia la carrera). Con mando: Select |
| R | Otra carrera (al terminar). Con mando: Start |
| V | Pantalla dividida: lado a lado (por defecto) o arriba y abajo |
| G | Avance: automático (por defecto; atrás frena) o manual (adelante acelera) |
| O | Salto: de olas (por defecto) o libre |
| M | Distribución del mando: estándar o genérico (tipo PlayStation) |
| H | Ocultar la ayuda |

Si el teclado no responde, haz clic dentro del juego.

## Cómo se juega una carrera

1. **Menú de personaje** (pantalla inicial): cada jugador arma su surfista y aprieta
   ESPACIO / A para marcar "listo". J1 también elige cuántos bots (0 a 3) y su dificultad.
   - Arriba / abajo: elegir fila · Izquierda / derecha: cambiar · E / B: volver a editar.
   - Peso: de Musculoso a Cervecero (6 etapas). Piel: incluye alien verde y azul.
   - Teclas 1 / 2 (o Select): 1 o 2 jugadores (pantalla dividida).
2. **Carrera**: cuenta regresiva, 5 vueltas alrededor de la isla.
3. **Resultados**: R o Start para otra carrera; C o Esc para volver al menú.

## Qué hay por ahora

- **Personajes** armados por piezas (AvatarCore), con animaciones que comparten todos:
  agitar los brazos al caer, mantenerse a flote, subirse a la tabla, remar, pararse,
  equilibrio al girar, agacharse para saltar, truco, derrape, festejo y saludo en el menú.
- **Bots** con dificultad Fácil / Normal / Difícil: se levantan, esquivan rocas, buscan
  círculos, derrapan al que tienen detrás, hacen trucos y usan turbo. Cada uno sigue uno
  de 5 caminos distintos (cambia en cada vuelta) y llegando a la meta va derecho al punto
  más cercano de la línea.
- **Carrera:** isla en el medio, 5 vueltas alrededor. Cuenta regresiva, vueltas,
  posición, aviso de "¡Al revés!", llegada y resultados.
- **Largada:** todos parados en la tabla. Si te caés (choque, truco fallido, derrape de otro), una sola barra: la primera mitad te sube a la tabla y la segunda te para.
- **Pantalla dividida** para 2 jugadores (teclas 1 / 2).
- **Salto (modo olas, por defecto):** la altura la dan las olas. En agua plana, A hace un
  saltito; apretando A al subir una ola (o justo al salir) hacés el **pop** y salís mucho
  más alto. Con O se cambia al salto libre (A salta alto en cualquier lado).
- **Truco:** en el aire, mantener gira la tabla y carga nitro. Si toca el agua girando: se cae y pierde el nitro.
- **Derrape:** tabla de costado, frena y tira una cortina de agua hacia atrás que hace caer a quien esté detrás.
- **Nitro y turbo:** los círculos de velocidad y los trucos cargan nitro; el turbo lo gasta. Si una ola te lanza con el turbo puesto, salís mucho más alto, y en el aire el turbo te sigue subiendo (cada vez más fuerte) para tener más tiempo de trucos.
- **Handicap:** cuanto más lejos del primero, el nitro se carga más rápido (hasta ×2,5,
  y muy atrás también se carga solo) los saltos son más altos (hasta +35%), va hasta un 20% más rápido y
  hay tolerancia al caer de un truco. El tope es a 120 m del primero (medido por la
  pista, sumando vueltas: con una vuelta de atraso, el handicap es el máximo). La barra muestra "NITRO ×1.8" cuando hay ayuda.
- **Motivación:** mini sprint automático al pasar por un círculo o tirar a alguien.
- **Rocas:** chocarlas tira de la tabla (saltando se esquivan). Chocar la isla también.
- **Olas grandes:** la mayoría nacen adelante tuyo (por la pista) y vienen de frente hacia vos, para usarlas de rampa; el resto aparecen al azar. Subirlas rápido te lanza al aire.
- Rayas de velocidad con turbo o motivación.
- **Música** de fondo (`assets/audio/simple_surf.ogg`, convertida del WAV original que
  está en `assets/audio/source/`). Sube de volumen cuando alguien pasa mucho tiempo en el
  aire. En el navegador empieza a sonar después de tocar una tecla o la pantalla.
- **Demo:** si nadie toca el menú por 10 s, arranca una carrera de 4 bots en Difícil
  con la pantalla en 4 (una vista por bot) (sirve para mirarlo en una tablet). Cualquier toque vuelve al menú.
- Los valores de balance están en `core/rider/rider_stats.tres`.
