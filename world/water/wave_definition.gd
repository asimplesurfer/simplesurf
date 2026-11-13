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


## Para que el oleaje no forme un enrejado que se repite, cada onda se tuerce
## (sus crestas se curvan) y crece y baja por zonas, cada una distinto. Mismos
## números que water.gdshader.
const WARP_A: Array[Vector2] = [Vector2(0.023, 0.031), Vector2(-0.033, 0.017), Vector2(0.027, -0.026), Vector2(-0.019, -0.035)]
const WARP_B: Array[Vector2] = [Vector2(-0.029, 0.021), Vector2(0.018, 0.034), Vector2(-0.031, -0.022), Vector2(0.036, -0.012)]
const GROUP: Array[Vector2] = [Vector2(0.011, 0.014), Vector2(-0.016, 0.008), Vector2(0.009, -0.015), Vector2(-0.013, -0.012)]
const SEED: Array[float] = [0.0, 2.1, 4.3, 1.2]


func height_at(x: float, z: float, t: float) -> float:
	var h := 0.0
	var p := Vector2(x, z)
	for i in mini(waves.size(), MAX_WAVES):
		var w: Vector4 = waves[i]
		if w.w <= 0.0:
			continue
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var omega := sqrt(GRAVITY * k) * speed_scale
		var wa := 0.22 * w.w
		var q := p + wa * Vector2(sin(p.dot(WARP_A[i]) + SEED[i]), sin(p.dot(WARP_B[i]) + SEED[i] * 1.37))
		var m := 0.65 + 0.35 * sin(p.dot(GROUP[i]) + SEED[i] * 1.7)
		h += w.z * m * sin(k * d.dot(q) - omega * t)
	return h


## Lo más alto que pueden llegar las olitas de fondo (suma de amplitudes).
func max_height() -> float:
	var total := 0.0
	for w in waves:
		total += absf(w.z)
	return total


## Derivadas de la altura: (dh/dx, dh/dz).
func gradient_at(x: float, z: float, t: float) -> Vector2:
	var g := Vector2.ZERO
	var p := Vector2(x, z)
	for i in mini(waves.size(), MAX_WAVES):
		var w: Vector4 = waves[i]
		if w.w <= 0.0:
			continue
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var omega := sqrt(GRAVITY * k) * speed_scale
		var wa := 0.22 * w.w
		var s1 := p.dot(WARP_A[i]) + SEED[i]
		var s2 := p.dot(WARP_B[i]) + SEED[i] * 1.37
		var q := p + wa * Vector2(sin(s1), sin(s2))
		var phase := k * d.dot(q) - omega * t
		var dphase := k * (d + d.x * wa * cos(s1) * WARP_A[i] + d.y * wa * cos(s2) * WARP_B[i])
		var sg := p.dot(GROUP[i]) + SEED[i] * 1.7
		var m := 0.65 + 0.35 * sin(sg)
		var dm := 0.35 * cos(sg) * GROUP[i]
		g += w.z * (dm * sin(phase) + m * cos(phase) * dphase)
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
