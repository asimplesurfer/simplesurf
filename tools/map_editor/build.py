#!/usr/bin/env python3
"""Arma el editor de mapas (editor.html) con los mapas y las piezas actuales del juego.

    python3 tools/map_editor/build.py

- Los mapas: los world/maps/*.json.
- Las piezas: las arma Godot con lo que dice cada world/pieces/*.gd (su
  constante EDITOR; ver MapPiece.editor_entry). Una pieza nueva aparece sola en
  el editor, sin tocar editor.src.html. Hace falta `godot` en el PATH (o en la
  variable GODOT).

El editor se publica como artefacto en Claude (lo hace Claude con el editor.html
que sale de acá, después de cada cambio en mapas o piezas).
"""
import json
import os
import pathlib
import subprocess
import sys

here = pathlib.Path(__file__).resolve().parent
root = here.parent.parent
maps_dir = root / "world" / "maps"
maps = sorted((json.loads(p.read_text()) for p in maps_dir.glob("*.json")), key=lambda m: m.get("order", 0))

godot = os.environ.get("GODOT", "godot")
run = subprocess.run(
    [godot, "--headless", "--path", str(root), "--script", "res://tools/export_pieces.gd"],
    capture_output=True, text=True, timeout=300,
)
line = next((l for l in run.stdout.splitlines() if l.startswith("PIECES_JSON ")), None)
if line is None:
    sys.exit("No se pudo leer el catálogo de piezas de Godot:\n" + run.stdout[-2000:] + run.stderr[-2000:])
pieces = json.loads(line[len("PIECES_JSON "):])
if not pieces:
    sys.exit("El catálogo de piezas salió vacío")

src = (here / "editor.src.html").read_text()
for mark in ("/*MAPS*/", "/*PIECES*/"):
    if src.count(mark) != 1:
        sys.exit(f"editor.src.html tiene que tener {mark} una vez")
out = src.replace("/*MAPS*/", json.dumps(maps, ensure_ascii=False, separators=(",", ":")))
out = out.replace("/*PIECES*/", json.dumps(pieces, ensure_ascii=False, separators=(",", ":")))
(here / "editor.html").write_text(out)
print(f"editor.html armado con {len(maps)} mapas y {len(pieces)} piezas")
