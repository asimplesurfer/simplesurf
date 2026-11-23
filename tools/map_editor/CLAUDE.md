# Editor de mapas: reglas

El editor lo usa quien arma los mapas, que no programa. Es un artefacto en
Claude: https://claude.ai/artifact/AWpL9C2N5dKRnid5Fdxyo7

## Regla principal: el editor habla como quien arma mapas

Cada control muestra **lo que la persona decide, en sus palabras**. La
traducción a lo que guarda el juego (números, 1/0, semillas, nombres internos)
la hace el editor por detrás. Nunca se le pide a la persona que escriba un
valor interno ni que lea una explicación de qué significa cada número.

Ejemplo: "¿esta isla tiene público?". Antes era un número (1 = sí, 0 = no) con
la explicación al lado. Ahora es una casilla, y el editor guarda 1 o 0.

Cómo elegir el control:

- **Sí o no**: casilla (`bool`; `numbool` si el juego guarda 1 o 0).
- **Pocas opciones**: una lista con nombres (`choice` o `level`), por ejemplo
  playa "Angosta / Normal / Ancha / Muy ancha". Nunca un número para adivinar.
- **Semilla o variante**: el botón "Otra variante" (`variant`). Nunca un número.
- **Colores**: el selector de color.
- **Números**: solo cuando la persona piensa en números (metros, vueltas,
  cables), con la unidad en la etiqueta: "Ancho (m)". Si es una escala de 0
  a 1, mejor niveles con nombre ("Poco / Normal / Mucho").
- **Lo que el juego decide solo** (valores automáticos): se muestra lo que va
  a pasar, dicho en palabras ("Automático: tiene público porque está cerca de
  la pista"), y se puede volver a automático. Ver `auto_near` en
  `MapPiece.editor_entry`.

Textos:

- Cortos, en español rioplatense, como se habla. Sin nombres de variables ni
  jerga (nada de "seed", "bool", "drag", "phase", "lateral", "spawn").
- Las ayudas de las herramientas dicen qué hacer con el mouse ("Clic para
  poner un géiser"); las notas del panel, qué va a pasar en el juego.
- Los avisos de la revisión dicen qué está mal y cómo arreglarlo, con
  palabras del mapa ("Una isla tropical pisa la pista"), nunca un error técnico.
- Los textos de las piezas viven en el código del juego (abajo): solo letras
  Latin-1 (nada de "–", "→", "◀"). Hay un test que lo revisa.

## Dónde están los textos

- **Piezas**: la constante `EDITOR` de cada `world/pieces/*.gd` (nombre,
  ayuda, `fields`). La etiqueta de un parámetro es el comentario `##` de su
  variable: escribilo pensando en quien arma mapas, o poné una etiqueta en
  `EDITOR.fields` (con el control que corresponda). El formato está en
  `MapPiece.editor_entry`.
- **El resto** (mapa, pista, meta, revisión, herramientas generales):
  `editor.src.html`.
- La lista de piezas **no** se escribe en `editor.src.html`: sale sola del
  código del juego. Un test revisa que cada pieza tenga `EDITOR` y que cada
  parámetro tenga etiqueta.

## Armar, probar y publicar

1. `python3 tools/map_editor/build.py` (necesita `godot`). Mete los mapas y las
   piezas en `editor.html`; falla si alguna pieza no carga.
2. Probarlo en Chromium: abrir cada mapa, usar lo que cambió, sin errores en
   la consola. Si cambió cómo se ve algo, sacar una captura.
3. Publicarlo en el mismo link: primero leer entero el artefacto publicado
   (Artifact `read`), después publicar `tools/map_editor/editor.html` con ese
   `url`, sin pasar `capabilities` (conserva `db` y `downloads`).

Se vuelve a publicar después de cada cambio que llegue a `main` y toque mapas,
piezas o el editor.
