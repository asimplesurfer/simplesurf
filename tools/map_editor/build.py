#!/usr/bin/env python3
"""Arma el editor de mapas (editor.html) con los mapas actuales del juego adentro.

    python3 tools/map_editor/build.py

El editor se publica como artefacto en Claude (lo hace Claude con el editor.html
que sale de acá). Si se agrega una pieza nueva al juego, sumarla a PIECES en
editor.src.html y volver a armarlo.
"""
import json
import pathlib

here = pathlib.Path(__file__).resolve().parent
maps_dir = here.parent.parent / "world" / "maps"
maps = sorted((json.loads(p.read_text()) for p in maps_dir.glob("*.json")), key=lambda m: m.get("order", 0))
src = (here / "editor.src.html").read_text()
out = src.replace("/*MAPS*/", json.dumps(maps, ensure_ascii=False, separators=(",", ":")))
(here / "editor.html").write_text(out)
print(f"editor.html armado con {len(maps)} mapas")
