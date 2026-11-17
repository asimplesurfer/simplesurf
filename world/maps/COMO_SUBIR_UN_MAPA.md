# Cómo subir un mapa al juego (sin pedírselo a Claude)

Cada mapa es un archivo `.json` en esta carpeta (`world/maps/`). Todo lo que
esté acá aparece en el menú del juego. Cuando un archivo entra a `main`,
GitHub revisa los mapas, arma el juego y lo publica en la web solo. No hace
falta tocar código ni correr nada a mano.

## 1. Armar el mapa en el editor

Editor: https://claude.ai/artifact/AWpL9C2N5dKRnid5Fdxyo7

- **Mapa nuevo**: en la lista de arriba elegí **+ Mapa nuevo**.
- **Cambiar uno que ya está**: elegilo en la lista. Si no aparece, tocá
  **Importar** y pegá el contenido de su archivo.

Antes de bajarlo, fijate dos cosas:

1. En **Revisión** (a la derecha) no tiene que haber ningún **Error**. Los
   **Ojo** son avisos: se puede publicar igual.
2. En el panel **Mapa** (tocá el agua vacía para verlo):
   - **Nombre en el menú**: como lo vas a ver en el juego.
   - **Número de mapa**: tiene que ser distinto al de los otros mapas. Un mapa
     nuevo lleva el siguiente número libre (el editor lo pone solo). Si estás
     cambiando un mapa que ya existe, **no le cambies el número**: es el de sus
     récords de contrarreloj.

## 2. Descargar el archivo

Tocá **Descargar mapa** (arriba). Se baja un archivo con el nombre del mapa,
por ejemplo `tropical.json`.

- El nombre del archivo es el nombre interno del mapa. Para cambiar un mapa
  que ya está, el archivo tiene que llamarse **igual** que el que está en esta
  carpeta (así lo reemplaza). Para uno nuevo, cualquier nombre que no exista.
- Solo letras sin tildes, números y `_` (por ejemplo `isla_grande.json`).
- Si el botón no descarga: tocá **Ver JSON**, **Copiar**, y guardalo en un
  archivo de texto con ese nombre.

## 3. Subirlo a GitHub

1. Entrá a https://github.com/asimplesurfer/simplesurf/tree/main/world/maps
2. Arriba a la derecha: **Add file → Upload files**.
3. Arrastrá el archivo `.json` (si ya existe uno con ese nombre, lo reemplaza).
4. Abajo, en **Commit changes**: escribí qué cambiaste (por ejemplo "Tropical:
   más islas"), dejá marcado **Commit directly to the main branch** y tocá
   **Commit changes**.

Desde el celular también se puede, desde github.com en el navegador.

## 4. Esperar a que se publique

Apenas subís el archivo arranca solo el **Web build**:

1. Entrá a https://github.com/asimplesurfer/simplesurf/actions y abrí la
   corrida que dice el nombre de tu commit.
2. El paso **publish** tarda 1 o 2 minutos. Cuando tiene el tilde verde, el
   juego ya está online.
3. En el resumen de la corrida dice el número de build. En el menú del juego
   (arriba a la derecha) tiene que decir ese número. Si ves uno menor,
   recargá con **Cmd+Shift+R** (o Ctrl+Shift+R).
4. Elegí tu mapa en el menú y listo.

El otro trabajo de esa corrida, **tests**, tarda unos 10 minutos más. No frena
la publicación.

## Si algo sale mal

- **El paso "Revisar los mapas" quedó en rojo**: tu mapa tiene un error y
  **no se publicó nada** (en la web sigue la versión anterior, que anda). En
  el resumen de la corrida dice qué archivo y qué está mal; por ejemplo:
  - *"el número de mapa 4 lo usan tropical.json y mi_mapa.json"*: cambiale el
    número a uno de los dos.
  - *"una isla tropical tapa la pista cerca de (120, -40)"*: movela en el
    editor (las coordenadas se ven abajo a la derecha del editor).
  - *"pieza desconocida"*: el archivo no salió del editor o está editado a
    mano; volvé a descargarlo del editor.

  Arreglalo en el editor, descargalo de nuevo y volvé a subirlo (paso 3).
- **No aparece en el menú**: fijate que el build del menú sea el nuevo (paso 4).
- **Querés sacar un mapa**: abrí su archivo en GitHub, tocá los tres puntitos
  (…) → **Delete file** → **Commit changes**.

## Para Claude

Este flujo no necesita a Claude. Si después le pedís a Claude algo de mapas,
el editor puede quedar con la lista de mapas vieja hasta que Claude lo vuelva
a armar (`python3 tools/map_editor/build.py`); mientras tanto, para abrir un
mapa nuevo en el editor, usá **Importar**.
