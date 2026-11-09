class_name WaveDefinition
extends Resource
## Define las olas UNA sola vez, para que el shader del agua (lo que se ve) y
## los scripts (la altura donde flota la tabla) usen exactamente la misma fórmula.
## Es una suma de senoidales; cada una viaja en su dirección.

const GRAVITY := 9.8
## Cantidad de olas que entiende water.gdshader (wave_0 .. wave_3).
const MAX_WAVES := 4

## Cada ola: x, y = dirección (en el plano XZ); z = amplitud (m); w = longitud de onda (m).
@export var waves: Array[Vector4] = [
	Vector4(1.0, 0.3, 0.32, 24.0),
	Vector4(-0.4, 1.0, 0.2, 13.0),
	Vector4(0.7, -0.8, 0.1, 7.5),
	Vector4(-1.0, -0.2, 0.05, 4.3),
]
## Multiplica la velocidad de todas las olas.
@export var speed_scale: float = 1.0


func height_at(x: float, z: float, t: float) -> float:
	var h := 0.0
	for i in mini(waves.size(), MAX_WAVES):
		var w: Vector4 = waves[i]
		if w.w <= 0.0:
			continue
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var omega := sqrt(GRAVITY * k) * speed_scale
		h += w.z * sin(k * (d.x * x + d.y * z) - omega * t)
	return h


## Derivadas de la altura: (dh/dx, dh/dz).
func gradient_at(x: float, z: float, t: float) -> Vector2:
	var g := Vector2.ZERO
	for i in mini(waves.size(), MAX_WAVES):
		var w: Vector4 = waves[i]
		if w.w <= 0.0:
			continue
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var omega := sqrt(GRAVITY * k) * speed_scale
		g += d * (w.z * k * cos(k * (d.x * x + d.y * z) - omega * t))
	return g


func normal_at(x: float, z: float, t: float) -> Vector3:
	var g := gradient_at(x, z, t)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## Pasa los parámetros al shader del agua.
func apply_to(material: ShaderMaterial) -> void:
	for i in MAX_WAVES:
		var w := Vector4(1.0, 0.0, 0.0, 0.0)
		if i < waves.size():
			w = waves[i]
		var d := Vector2(w.x, w.y).normalized()
		material.set_shader_parameter("wave_%d" % i, Vector4(d.x, d.y, w.z, w.w))
	material.set_shader_parameter("speed_scale", speed_scale)
