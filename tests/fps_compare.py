#!/usr/bin/env python3
"""Corre tests/fps_check.gd a varios FPS y comprueba que la física da lo mismo
(distancia, velocidad, altura y tiempo del salto) con una tolerancia chica.

Uso: python3 tests/fps_compare.py <godot>
"""
import json
import subprocess
import sys

GODOT = sys.argv[1] if len(sys.argv) > 1 else "godot"
FPS = [20, 30, 60, 144]
KEYS = ["speed_push", "dist_push", "dist_coast", "jump_h", "air"]
TOLERANCE = 0.02  # 2 %

results = {}
for fps in FPS:
    out = subprocess.run(
        [GODOT, "--headless", "--path", ".", "--fixed-fps", str(fps),
         "--script", "res://tests/fps_check.gd", "--", str(fps)],
        capture_output=True, text=True, timeout=300,
    ).stdout
    line = next((l for l in out.splitlines() if l.startswith("FPS_CHECK ")), None)
    if line is None:
        print(out)
        sys.exit(f"Sin resultado a {fps} FPS")
    results[fps] = json.loads(line[len("FPS_CHECK "):])
    print(fps, results[fps])

base = results[60]
bad = []
for fps, r in results.items():
    if not r["landed"]:
        bad.append(f"a {fps} FPS no aterrizó")
    for k in KEYS:
        ref = base[k]
        if abs(r[k] - ref) > max(abs(ref) * TOLERANCE, 0.015):
            bad.append(f"{k} a {fps} FPS: {r[k]} (a 60 FPS: {ref})")
if bad:
    print("LA FÍSICA DEPENDE DE LOS FPS:")
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("FÍSICA IGUAL A CUALQUIER FPS")
