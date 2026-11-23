class_name WaterPalette
extends RefCounted
## Colores del agua de todos los climas, en un solo lugar.
##
## BASE es el agua de día: es la que se toca para cambiar "el agua".
## Cada clima (atardecer, noche, tormenta) anota solo los colores que decide
## él. Todo color que un clima NO anota sale solo de la base, con el cambio
## general de ese clima (cuánto sube o baja cada canal rojo / verde / azul,
## calculado a partir de los colores que sí anotó). Así:
## - un color nuevo del agua (o uno que un clima se olvidó) nunca queda del
##   color de otro clima (por ejemplo arrecifes turquesa al atardecer);
## - cambiar un color anotado de un clima cambia solo ese clima;
## - cambiar la base cambia el día y lo que los climas sacan de ella, y la
##   cuenta se rehace sola (no hay que retocar los climas a mano).
##
## "ocean_color" es el mar lejano (hasta el horizonte): lo lee el cielo y
## Horizon se lo pasa al agua.
##
## "spray_color" es el celeste del agua que levanta la tabla (el borde de la
## pared al girar, de las gotas); lo blanco de ese agua es "foam_color". Esos
## efectos no reciben luz (son "unshaded"), así que además cada clima los
## oscurece con "spray_light" (1 de día). Los lee Water.fx_colors().
##
## Hay dos aguas: el mar (SEA, la de siempre) y el río (RIVER: más oscura,
## verdosa, para los mapas de selva). Cada mapa elige la suya (TrackMap.water).
## El río tiene su propia base (RIVER_BASE) y los climas la cambian igual que
## al mar: con el cambio general de cada clima (grade), sacado de sus colores
## propios del mar. Así un atardecer o una tormenta oscurecen y tiñen el río
## de la misma manera que el mar, sin anotar colores aparte para cada uno.

const DAY := "dia"
const SUNSET := "atardecer"
const NIGHT := "noche"
const STORM := "tormenta"

## Las aguas que puede elegir un mapa.
const SEA := "mar"
const RIVER := "rio"
const WATERS := [SEA, RIVER]

## El agua de día.
const BASE := {
	"deep_color": Color(0.03, 0.2, 0.34),
	"shallow_color": Color(0.08, 0.35, 0.48),
	"wave_color": Color(0.14, 0.55, 0.6),
	"rising_color": Color(0.02, 0.14, 0.28),
	"outside_color": Color(0.03, 0.15, 0.27),
	"sky_tint": Color(0.6, 0.76, 0.86),
	"reef_color": Color(0.33, 0.78, 0.76),
	"foam_color": Color(0.93, 0.98, 1.0),
	"glow_color": Color(0.25, 0.95, 0.8),
	"ocean_color": Color(0.4, 0.72, 0.84),
	"spray_color": Color(0.62, 0.9, 1.0),
}

## Los ajustes de día (los climas cambian los que anotan en "values").
const BASE_VALUES := {
	"spray_light": 1.0,
}

## El agua de río de día: más oscura que el mar y verdosa (agua de selva).
const RIVER_BASE := {
	"deep_color": Color(0.03, 0.11, 0.11),
	"shallow_color": Color(0.07, 0.2, 0.17),
	"wave_color": Color(0.12, 0.32, 0.26),
	"rising_color": Color(0.02, 0.08, 0.08),
	"outside_color": Color(0.03, 0.09, 0.08),
	"sky_tint": Color(0.5, 0.62, 0.6),
	"reef_color": Color(0.24, 0.44, 0.34),
	"foam_color": Color(0.86, 0.9, 0.84),
	"glow_color": Color(0.2, 0.7, 0.55),
	"ocean_color": Color(0.26, 0.45, 0.44),
	"spray_color": Color(0.58, 0.76, 0.68),
}


## La base de un agua (el mar si no la conoce).
static func base(water: String = SEA) -> Dictionary:
	return RIVER_BASE if water == RIVER else BASE


## Lo que cada clima decide por su cuenta. "colors": colores propios (los que
## faltan salen de la base); "values": otros ajustes del agua.
const CLIMATES := {
	SUNSET: {
		"colors": {
			"deep_color": Color(0.06, 0.13, 0.27),
			"shallow_color": Color(0.16, 0.25, 0.4),
			"wave_color": Color(0.3, 0.42, 0.52),
			"outside_color": Color(0.05, 0.1, 0.22),
			"sky_tint": Color(0.95, 0.65, 0.55),
			# Arrecifes: apenas más claros que el mar, con el reflejo cálido del cielo.
			"reef_color": Color(0.64, 0.56, 0.56),
			"foam_color": Color(1.0, 0.9, 0.85),
			# Mar lejano: naranja como el horizonte (no celeste).
			"ocean_color": Color(0.96, 0.64, 0.5),
		},
		"values": {"spray_light": 0.8},
	},
	NIGHT: {
		"colors": {
			# Mar de noche con luz de luna: azul profundo pero que se lee bien (no negro).
			"deep_color": Color(0.06, 0.13, 0.26),
			"shallow_color": Color(0.11, 0.23, 0.38),
			"wave_color": Color(0.15, 0.34, 0.47),
			"outside_color": Color(0.05, 0.11, 0.22),
			"rising_color": Color(0.05, 0.12, 0.24),
			"sky_tint": Color(0.28, 0.36, 0.6),
			"reef_color": Color(0.16, 0.36, 0.45),
			"foam_color": Color(0.7, 0.78, 0.92),
			"glow_color": Color(0.2, 0.55, 0.75),
			"ocean_color": Color(0.04, 0.07, 0.15),
			# Agua levantada: azul de luna (con la cuenta general queda gris).
			"spray_color": Color(0.42, 0.6, 0.88),
		},
		"values": {"glow_strength": 0.18, "spray_light": 0.85},
	},
	STORM: {
		"colors": {
			"deep_color": Color(0.05, 0.15, 0.23),
			"shallow_color": Color(0.11, 0.29, 0.37),
			"wave_color": Color(0.15, 0.4, 0.44),
			"outside_color": Color(0.04, 0.1, 0.16),
			"rising_color": Color(0.03, 0.1, 0.17),
			"sky_tint": Color(0.5, 0.55, 0.62),
			"reef_color": Color(0.2, 0.32, 0.35),
			"foam_color": Color(0.93, 0.98, 1.0),
			"ocean_color": Color(0.1, 0.15, 0.2),
			"spray_color": Color(0.5, 0.68, 0.74),
		},
		"values": {"glow_strength": 0.15, "sky_reflect": 0.6, "spray_light": 0.9},
	},
}


## Todos los colores del agua de un clima (DAY = la base). `water`: el mar
## o el río (ver RIVER_BASE).
static func colors(climate: String, water: String = SEA) -> Dictionary:
	if water == RIVER:
		return _river(climate)
	var out := BASE.duplicate()
	if not CLIMATES.has(climate):
		return out
	var own: Dictionary = CLIMATES[climate].colors
	var gain := grade(climate)
	for k in BASE:
		if own.has(k):
			out[k] = own[k]
		else:
			var b: Color = BASE[k]
			out[k] = Color(
				clampf(b.r * gain.x, 0.0, 1.0), clampf(b.g * gain.y, 0.0, 1.0), clampf(b.b * gain.z, 0.0, 1.0)
			)
	return out


## El río con un clima: su base con el cambio general del clima (el mismo que
## le aplica al mar).
static func _river(climate: String) -> Dictionary:
	var out := RIVER_BASE.duplicate()
	if not CLIMATES.has(climate):
		return out
	var gain := grade(climate)
	for k in out:
		var b: Color = out[k]
		out[k] = Color(clampf(b.r * gain.x, 0.0, 1.0), clampf(b.g * gain.y, 0.0, 1.0), clampf(b.b * gain.z, 0.0, 1.0))
	return out


## Los otros ajustes del agua del clima (brillo, reflejo...): los de la base
## (BASE_VALUES) con los que anota el clima encima.
static func values(climate: String) -> Dictionary:
	var out := BASE_VALUES.duplicate()
	if CLIMATES.has(climate):
		out.merge(CLIMATES[climate].values, true)
	return out


## El cambio general del clima respecto de la base: cuánto se multiplica cada
## canal (x = rojo, y = verde, z = azul). Se calcula de sus colores propios
## (mínimos cuadrados: el que mejor lleva la base a esos colores).
static func grade(climate: String) -> Vector3:
	if not CLIMATES.has(climate):
		return Vector3.ONE
	var own: Dictionary = CLIMATES[climate].colors
	var num := Vector3.ZERO
	var den := Vector3.ZERO
	for k in own:
		if not BASE.has(k):
			continue
		var b: Color = BASE[k]
		var c: Color = own[k]
		num += Vector3(b.r * c.r, b.g * c.g, b.b * c.b)
		den += Vector3(b.r * b.r, b.g * b.g, b.b * b.b)
	return Vector3(
		num.x / den.x if den.x > 0.0 else 1.0,
		num.y / den.y if den.y > 0.0 else 1.0,
		num.z / den.z if den.z > 0.0 else 1.0
	)


## Pone en el material del agua los colores y ajustes del clima (menos el mar
## lejano, que va en el cielo). spray_color y spray_light no los usa el shader
## del mar: quedan en el material para el agua que levanta la tabla (ver
## Water.fx_colors). `setter` (opcional) hace el cambio en vez de
## ponerlo directo: lo usa la tormenta para recordar lo que había.
static func apply_to_water(mat: ShaderMaterial, climate: String, setter: Callable = Callable(), water: String = SEA) -> void:
	var all := colors(climate, water)
	all.erase("ocean_color")
	all.merge(values(climate), true)
	for k in all:
		if setter.is_valid():
			setter.call(mat, k, all[k])
		else:
			mat.set_shader_parameter(k, all[k])
