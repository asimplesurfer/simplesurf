class_name AvatarCore
extends RefCounted
## Núcleo del creador de personajes (port de avatar_core.js).
## Uso: var parts = AvatarCore.get_avatar(0.5)
##      -> Array de Dictionary { id, color: Color, pos: Vector3, radii: Vector3 }
## Cada pieza = MeshInstance3D con SphereMesh (radius 1, height 2), scale = radii, position = pos.
## Convención: Y arriba, el personaje mira hacia +Z, los pies tocan y = 0.
## t = 0.0 Musculoso ... t = 1.0 Cervecero. Ocultar la pieza si min(radii) < 0.05.
##
## Para el juego final el objetivo es una sola malla con blend shapes; esto
## define las proporciones y sirve de placeholder mientras tanto.

const STAGE_T := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
const STAGE_NAMES := ["Musculoso", "Fuerte", "Delgado", "Relleno", "Gordo", "Cervecero"]
const SKIN := Color("#b07a4e")
const SHORTS := Color("#1c2b66")
## Alto total aproximado (de los pies a la punta de la cabeza).
const HEIGHT := 2.7

## Filas: [px, py, pz, rx, ry, rz] por etapa (mismo orden que STAGE_T).
## mirror = true -> se crean dos piezas (_L y _R), espejadas en X.
const PARTS := [
	{"id": "head", "color": "skin", "mirror": false, "rows": [
		[0, 2.18, 0.02, 0.5, 0.4, 0.46],
		[0, 2.168, 0.02, 0.5, 0.4, 0.46],
		[0, 2.156, 0.02, 0.5, 0.4, 0.46],
		[0, 2.144, 0.02, 0.5, 0.4, 0.46],
		[0, 2.124, 0.02, 0.5, 0.4, 0.46],
		[0, 2.1, 0.02, 0.5, 0.4, 0.46]]},
	{"id": "chest", "color": "skin", "mirror": false, "rows": [
		[0, 1.4, 0, 0.4, 0.26, 0.24],
		[0, 1.488, 0, 0.416, 0.299, 0.257],
		[0, 1.576, 0, 0.432, 0.338, 0.274],
		[0, 1.564, 0, 0.378, 0.332, 0.256],
		[0, 1.544, 0, 0.376, 0.33, 0.262],
		[0, 1.52, 0, 0.4, 0.33, 0.28]]},
	{"id": "belly", "color": "skin", "mirror": false, "rows": [
		[0, 1.12, 0.02, 0.22, 0.2, 0.17],
		[0, 1.178, 0.02, 0.248, 0.244, 0.189],
		[0, 1.236, 0.02, 0.276, 0.288, 0.208],
		[0, 1.224, 0.02, 0.264, 0.282, 0.202],
		[0, 1.183, 0.08, 0.336, 0.326, 0.283],
		[0, 1.146, 0.155, 0.426, 0.378, 0.365]]},
	{"id": "hips", "color": "shorts", "mirror": false, "rows": [
		[0, 0.8, 0, 0.38, 0.22, 0.26],
		[0, 0.878, 0, 0.376, 0.239, 0.262],
		[0, 0.956, 0, 0.372, 0.258, 0.264],
		[0, 0.944, 0, 0.348, 0.252, 0.246],
		[0, 0.924, 0, 0.356, 0.25, 0.256],
		[0, 0.9, 0, 0.38, 0.25, 0.28]]},
	# Piernas del short (tipo bermuda).
	{"id": "thigh", "color": "shorts", "mirror": true, "rows": [
		[0.19, 0.62, 0, 0.17, 0.16, 0.19],
		[0.19, 0.698, 0, 0.165, 0.15, 0.185],
		[0.19, 0.776, 0, 0.16, 0.14, 0.18],
		[0.18, 0.764, 0, 0.15, 0.14, 0.17],
		[0.19, 0.744, 0, 0.16, 0.14, 0.18],
		[0.2, 0.72, 0, 0.17, 0.14, 0.19]]},
	{"id": "leg", "color": "skin", "mirror": true, "rows": [
		[0.3, 0.34, 0, 0.1, 0.3, 0.1],
		[0.276, 0.428, 0, 0.126, 0.36, 0.126],
		[0.252, 0.516, 0, 0.152, 0.42, 0.152],
		[0.228, 0.504, 0, 0.128, 0.42, 0.128],
		[0.22, 0.484, 0, 0.128, 0.404, 0.132],
		[0.22, 0.46, 0, 0.14, 0.38, 0.15]]},
	{"id": "foot", "color": "skin", "mirror": true, "rows": [
		[0.32, 0.07, 0.08, 0.11, 0.07, 0.17],
		[0.3, 0.084, 0.09, 0.132, 0.084, 0.208],
		[0.28, 0.098, 0.1, 0.154, 0.098, 0.246],
		[0.25, 0.092, 0.1, 0.136, 0.092, 0.234],
		[0.24, 0.09, 0.1, 0.138, 0.09, 0.234],
		[0.24, 0.09, 0.1, 0.15, 0.09, 0.24]]},
	{"id": "delt", "color": "skin", "mirror": true, "rows": [
		[0.45, 1.52, 0, 0.17, 0.17, 0.17],
		[0.475, 1.586, 0, 0.149, 0.149, 0.149],
		[0.5, 1.652, 0, 0.128, 0.128, 0.128],
		[0.44, 1.628, 0, 0.033, 0.033, 0.033],
		[0.42, 1.596, 0, 0.001, 0.001, 0.001],
		[0.42, 1.56, 0, 0.001, 0.001, 0.001]]},
	{"id": "hand", "color": "skin", "mirror": true, "rows": [
		[0.68, 1.08, 0.12, 0.14, 0.14, 0.14],
		[0.846, 1.196, 0.15, 0.152, 0.152, 0.152],
		[1.012, 1.312, 0.18, 0.164, 0.164, 0.164],
		[0.988, 1.288, 0.18, 0.161, 0.161, 0.161],
		[0.988, 1.256, 0.188, 0.164, 0.164, 0.164],
		[1.0, 1.22, 0.2, 0.17, 0.17, 0.17]]},
]


static func _sample_rows(rows: Array, t: float) -> Array:
	t = clampf(t, 0.0, 1.0)
	var n := STAGE_T.size()
	var i := 0
	while i < n - 2 and t > STAGE_T[i + 1]:
		i += 1
	var k: float = (t - STAGE_T[i]) / (STAGE_T[i + 1] - STAGE_T[i])
	var out := []
	for c in 6:
		out.append(lerpf(rows[i][c], rows[i + 1][c], k))
	return out


## Piezas del personaje para el peso `t`. skin / shorts permiten cambiar colores.
static func get_avatar(t: float, skin: Color = SKIN, shorts: Color = SHORTS) -> Array:
	var out := []
	for p in PARTS:
		var r := _sample_rows(p["rows"], t)
		var col: Color = skin if p["color"] == "skin" else shorts
		var radii := Vector3(r[3], r[4], r[5])
		if not p["mirror"]:
			out.append({"id": p["id"], "color": col, "pos": Vector3(r[0], r[1], r[2]), "radii": radii})
		else:
			out.append(
				{"id": p["id"] + "_L", "color": col, "pos": Vector3(r[0], r[1], r[2]), "radii": radii}
			)
			out.append(
				{"id": p["id"] + "_R", "color": col, "pos": Vector3(-r[0], r[1], r[2]), "radii": radii}
			)
	return out


static func stage_name(t: float) -> String:
	var best := 0
	for i in STAGE_T.size():
		if absf(STAGE_T[i] - t) < absf(STAGE_T[best] - t):
			best = i
	return STAGE_NAMES[best]
