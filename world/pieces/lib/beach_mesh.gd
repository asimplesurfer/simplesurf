class_name BeachMesh
extends RefCounted
## Arena de una isla vista de cerca: arriba plana (seca) y una playa que baja
## suave hasta adentro del agua. Cerca del agua la arena está mojada (más
## oscura), y la marca de lo mojado sube a distinta altura en cada tramo de la
## orilla (no es una línea pareja alrededor de la isla). La pendiente no tiene
## un borde marcado: las normales se suavizan entre la parte plana y la playa.
##
## La usan las islas tropicales (TropicalIslandPiece).

## Cuánto más oscura es la arena mojada.
const WET_SHADE := 0.74
## Altura (sobre el agua quieta) hasta donde llega lo mojado: entre WET_LOW y
## WET_HIGH según el tramo.
const WET_LOW := 0.08
const WET_HIGH := 0.48
## Ancho del paso de mojado a seco (m de altura).
const WET_BLEND := 0.1
## Forma de la playa: (fracción del ancho, fracción de la caída). Empieza casi
## plana (sin borde) y después baja más rápido.
const PROFILE := [
	[0.0, 0.0], [0.04, 0.01], [0.08, 0.03], [0.12, 0.055], [0.16, 0.085], [0.2, 0.12],
	[0.25, 0.165], [0.31, 0.225], [0.38, 0.32],
	[0.52, 0.48], [0.7, 0.68], [1.0, 1.0],
]


## `outline`: el borde de arriba (figura cerrada). `normals`: hacia afuera en
## cada punto. La playa baja de `top_y` a `bottom_y` en `width` metros.
static func build(outline: PackedVector2Array, normals: PackedVector2Array, top_y: float, bottom_y: float,
		width: float, sand: Color, noise_seed: int, with_top: bool = true) -> ArrayMesh:
	var wet := Color(sand.r * WET_SHADE, sand.g * WET_SHADE * 0.97, sand.b * WET_SHADE * 0.9)
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.045
	var n := outline.size()
	# Altura de lo mojado en cada punto del borde (cambia a lo largo de la orilla).
	var wet_line := PackedFloat32Array()
	var along := 0.0
	for i in n:
		if i > 0:
			along += outline[i].distance_to(outline[i - 1])
		var k := noise.get_noise_1d(along) * 0.5 + 0.5
		k = clampf(k * 0.8 + 0.6 * (noise.get_noise_1d(along * 3.1 + 77.0) * 0.5 + 0.5) - 0.3, 0.0, 1.0)
		wet_line.append(lerpf(WET_LOW, WET_HIGH, k))
	# Triángulos (posición y color por vértice), todos mirando para arriba: si
	# la tapa y la playa quedaran al revés entre sí, al suavizar las normales
	# aparece una raya oscura en el borde.
	var verts: Array[Vector3] = []
	var colors: Array[Color] = []
	var rings := PROFILE.size()
	for r in rings - 1:
		for i in n:
			var j := (i + 1) % n
			for q in [[i, r], [j, r], [j, r + 1], [i, r], [j, r + 1], [i, r + 1]]:
				var p := _point(outline, normals, q[0], PROFILE[q[1]], top_y, bottom_y, width)
				verts.append(p)
				colors.append(_color(p.y, wet_line[q[0]], sand, wet))
	if with_top:
		for k in Geometry2D.triangulate_polygon(outline):
			verts.append(Vector3(outline[k].x, top_y, outline[k].y))
			colors.append(_color(top_y, wet_line[k], sand, wet))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, verts.size(), 3):
		var order := [0, 1, 2]
		# En Godot el frente es el sentido horario visto desde afuera: la
		# normal (b - a) x (c - a) apunta para adentro de la cara.
		if (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).y > 0.0:
			order = [0, 2, 1]
		for o in order:
			st.set_color(colors[t + o])
			st.add_vertex(verts[t + o])
	st.index()
	st.generate_normals()
	var mat := ToonMaterial.make(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()


static func _point(outline: PackedVector2Array, normals: PackedVector2Array, i: int, prof: Array,
		top_y: float, bottom_y: float, width: float) -> Vector3:
	var q: Vector2 = outline[i] + normals[i] * width * float(prof[0])
	return Vector3(q.x, lerpf(top_y, bottom_y, float(prof[1])), q.y)


static func _color(y: float, wet_y: float, sand: Color, wet: Color) -> Color:
	return sand.lerp(wet, smoothstep(wet_y + WET_BLEND, wet_y - WET_BLEND * 0.4, y))
