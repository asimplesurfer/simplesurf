class_name RingWave
extends RefCounted
## Modo "ola constante a la izquierda": una loma que da toda la vuelta a la
## isla por el lado de afuera de la pista (a la izquierda de quien corre).
## No desaparece nunca. Por la cresta avanzan picos más altos en contra del
## sentido de la carrera: vienen de frente y sirven de rampa.
## La misma fórmula está en water.gdshader (add_ring).
##
## altura = amplitud * (base + (1 - base) * pico(ángulo)) * exp(-(d/ancho)²)
## d = distancia (radial) a la línea de la cresta.
## pico = ((1 + cos(lóbulos * ángulo + fase)) / 2) ^ SHARPNESS

## Qué tan angostos son los picos (fijo, igual que en el shader).
const SHARPNESS := 6.0

var center: Vector2 = Vector2.ZERO
## Radio de la línea de la cresta (m).
var radius: float = 94.0
## Ancho de la loma (m). Más chico = más empinada.
var width: float = 5.0
## Altura de los picos (m).
var max_amplitude: float = 4.5
## Altura de la cresta entre picos, como fracción de la de los picos.
var base: float = 0.4
## Cantidad de picos en la vuelta.
var lobes: float = 10.0
## Velocidad de los picos sobre la cresta (m/s), en contra de la carrera.
var peak_speed: float = 6.0
## Tiempo en que la ola crece al empezar (s).
var grow_time: float = 2.0

var age: float = 0.0
var amplitude: float = 0.0
var phase: float = 0.0


## Ola lista (ya crecida); para las pruebas.
func settle() -> void:
	age = grow_time
	amplitude = max_amplitude


func update(delta: float) -> void:
	age += delta
	amplitude = max_amplitude * smoothstep(0.0, 1.0, minf(age / maxf(grow_time, 0.001), 1.0))
	# Fase creciente => los picos se mueven hacia ángulos menores (de frente).
	phase = wrapf(phase + peak_speed * lobes / radius * delta, 0.0, TAU)


func _peak(angle: float) -> float:
	return pow(0.5 + 0.5 * cos(lobes * angle + phase), SHARPNESS)


func _peak_derivative(angle: float) -> float:
	var c := 0.5 + 0.5 * cos(lobes * angle + phase)
	return SHARPNESS * pow(c, SHARPNESS - 1.0) * (-0.5 * sin(lobes * angle + phase)) * lobes


func height_at(p: Vector2) -> float:
	if amplitude <= 0.0:
		return 0.0
	var rel := p - center
	var r := rel.length()
	var d := r - radius
	if absf(d) > width * 4.0:
		return 0.0
	var a := atan2(rel.y, rel.x)
	return amplitude * (base + (1.0 - base) * _peak(a)) * exp(-(d * d) / (width * width))


## Derivadas de la altura en el mundo: (dh/dx, dh/dz).
func gradient_at(p: Vector2) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var rel := p - center
	var r := rel.length()
	var d := r - radius
	if absf(d) > width * 4.0 or r < 0.001:
		return Vector2.ZERO
	var a := atan2(rel.y, rel.x)
	var g := exp(-(d * d) / (width * width))
	var m := base + (1.0 - base) * _peak(a)
	var dh_dr := amplitude * m * (-2.0 * d / (width * width)) * g
	var dh_da := amplitude * (1.0 - base) * _peak_derivative(a) * g
	var radial := rel / r
	var tangential := Vector2(-radial.y, radial.x)
	return radial * dh_dr + tangential * (dh_da / r)


## Ángulo (alrededor del centro) del pico más cercano por delante de `angle`
## en el sentido de la carrera (ángulo creciente).
func next_peak_angle(angle: float) -> float:
	# Picos donde lobes * a + phase = 2πk.
	var k := ceilf((lobes * angle + phase) / TAU)
	return (TAU * k - phase) / lobes


## Parámetros empaquetados para el shader.
func shader_a() -> Vector4:
	return Vector4(center.x, center.y, radius, width)


func shader_b() -> Vector4:
	return Vector4(amplitude, base, lobes, phase)
