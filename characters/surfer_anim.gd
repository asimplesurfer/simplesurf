class_name SurferAnim
extends RefCounted
## Poses del surfista (las partes del modelo de SurferKit), en el espacio del
## personaje: +Z = el pecho (para donde mira el cuerpo), Y arriba, X a lo largo
## de la tabla con la punta hacia -X (el pie de adelante es el izquierdo).
## Parado sobre la tabla el cuerpo queda de costado (postura de surf); en el
## agua, nadando o festejando, de frente.
##
## pose() devuelve, para cada parte, cuánto se corre (pos) y cuánto gira (rot,
## en radianes, ángulos de Euler) desde su lugar en el modelo, y lo mismo para
## todo el cuerpo ("root", girando sobre los pies).
##
## Estado (Dictionary): anim, t (tiempo de la animación), time, steer (-1..1),
## charge (0..1), drift_side, effort (0..1), speed (0..1), vy (velocidad
## vertical), land (0..1, recién aterrizó), pop (0..1, recién despegó), turbo,
## shake (0..1, se está secando la cara después de un chapuzón).

const PARTS := [
	"Head", "Torso", "ShortsHips", "SleeveL", "SleeveR", "ThighL", "ThighR", "ShinL", "ShinR",
	"FootL", "FootR", "HandL", "HandR",
]
## Lugar de cada parte en el modelo (para calcular hacia dónde llevar las manos).
const BASE := {
	"Head": Vector3(-0.12, 2.06, 0.06),
	"Torso": Vector3(0.0, 1.18, 0.0),
	"ShortsHips": Vector3(0.0, 0.82, 0.0),
	"HandL": Vector3(-1.1, 1.42, 0.5),
	"HandR": Vector3(0.82, 1.02, -0.1),
	"FootL": Vector3(-0.48, 0.06, 0.07),
	"FootR": Vector3(0.46, 0.06, 0.07),
}
## Hacia dónde mira la cara (la cabeza del modelo está girada hacia la punta).
const FACE_DIR := Vector3(-0.773, 0.022, 0.552)
## Cadera: punto sobre el que se dobla el torso.
const WAIST := Vector3(0.0, 1.0, 0.0)

## Animaciones de pie sobre la tabla (cuerpo de costado).
const STANCE := [&"idle", &"ride", &"air", &"trick", &"drift", &"duck", &"pop_up"]


static func is_stance(anim: StringName) -> bool:
	return anim in STANCE


static func pose(s: Dictionary) -> Dictionary:
	var p := {}
	for part in PARTS:
		p[part] = {"pos": Vector3.ZERO, "rot": Vector3.ZERO}
	p["root"] = {"pos": Vector3.ZERO, "rot": Vector3.ZERO}
	match s.anim:
		&"ride":
			_ride(p, s)
		&"drift":
			_drift(p, s)
		&"air":
			_air(p, s, false)
		&"trick":
			_air(p, s, true)
		&"duck":
			_duck(p, s)
		&"pop_up":
			_pop_up(p, s)
		&"flail":
			_flail(p, s)
		&"tread":
			_tread(p, s)
		&"climb":
			_climb(p, s)
		&"paddle":
			_paddle(p, s)
		&"celebrate":
			_celebrate(p, s)
		_:
			_idle(p, s)
	# Después del chapuzón: sacude la cabeza y se pasa la mano por los ojos.
	if is_stance(s.anim) and s.get("shake", 0.0) > 0.0:
		_shake_off(p, s)
	# Recién aterrizado: amortigua flexionando fuerte (aunque la animación cambie).
	if is_stance(s.anim) and s.land > 0.0:
		_crouch(p, s.land * 0.7)
		_move(p, "HandL", Vector3(0.0, -0.2, 0.1) * s.land)
		_move(p, "HandR", Vector3(0.0, -0.2, 0.1) * s.land)
	return p


# ---------------------------------------------------------------- de pie

## Parado tranquilo (menú): respira y mira alrededor.
static func _idle(p: Dictionary, s: Dictionary) -> void:
	var t: float = s.time
	_crouch(p, 0.12 + sin(t * 1.8) * 0.03)
	_turn(p, "Head", Vector3(0.0, sin(t * 0.7) * 0.25, 0.0))
	_move(p, "HandL", Vector3(0.0, sin(t * 2.0) * 0.05, 0.0))
	_move(p, "HandR", Vector3(0.0, sin(t * 2.0 + 1.2) * 0.05, 0.0))


## Andando: rodillas flexionadas que suben y bajan con la tabla (más con
## velocidad), el brazo de adelante apuntando a la punta y el de atrás bajo.
## En la curva el cuerpo se inclina hacia adentro y los hombros giran.
static func _ride(p: Dictionary, s: Dictionary) -> void:
	var t: float = s.time
	var speed: float = s.speed
	var steer: float = s.steer
	var bob := sin(t * (5.0 + speed * 4.0)) * (0.07 + speed * 0.06)
	var c: float = 0.45 + speed * 0.25 + bob + absf(steer) * 0.2 + s.charge * 0.55
	# Subiendo una ola: "bombea" (se comprime).
	if s.vy > 1.0:
		c += clampf(s.vy * 0.06, 0.0, 0.3)
	if s.turbo:
		c += 0.3
	c -= s.pop * 0.6
	_crouch(p, c)
	# Inclinado hacia adelante, más en la curva (hacia las puntas o los
	# talones), con los hombros girando hacia adentro.
	_bend(p, Vector3(0.22 + steer * 0.45 + s.charge * 0.3, steer * 0.35, 0.3 if s.turbo else 0.0))
	_turn(p, "Head", Vector3(0.0, -steer * 0.25, 0.0))
	if s.turbo:
		# Turbo: aerodinámico, los dos brazos atrás.
		_reach(p, "HandL", Vector3(0.35, 1.05, -0.3), 0.9)
		_reach(p, "HandR", Vector3(1.05, 0.9, -0.35), 0.9)
	else:
		# Brazo de adelante estirado hacia la punta; el de atrás abierto hacia
		# la cola. En la curva barren hacia adentro.
		var front := Vector3(-1.25, 1.5 + bob * 0.8 + steer * 0.15, 0.3 + steer * 0.45)
		var back := Vector3(1.05, 1.05 - bob * 0.5 - steer * 0.15, -0.1 - steer * 0.35)
		_reach(p, "HandL", front + p["Torso"].pos, 0.85)
		_reach(p, "HandR", back + p["Torso"].pos, 0.85)
	# Al despegar, los brazos se disparan hacia arriba.
	if s.pop > 0.0:
		_move(p, "HandL", Vector3(0.0, 0.8, 0.0) * s.pop)
		_move(p, "HandR", Vector3(0.0, 0.9, 0.0) * s.pop)


## Derrape: muy agachado, echado hacia los talones, con la mano de atrás
## rozando el agua y la de adelante arriba.
static func _drift(p: Dictionary, s: Dictionary) -> void:
	var t: float = s.time
	_crouch(p, 0.75 + sin(t * 9.0) * 0.03)
	_bend(p, Vector3(-0.45, 0.25, 0.0))
	_reach(p, "HandR", Vector3(0.55, 0.12, -0.55), 1.0)
	_reach(p, "HandL", Vector3(-0.75, 1.85, 0.25), 0.9)
	_turn(p, "Head", Vector3(0.15, 0.0, 0.0))


## En el aire. Subiendo: piernas recogidas y brazos arriba. Bajando: se estira
## para el aterrizaje con los brazos abiertos. En el truco: bien recogido y
## agarrando la tabla con la mano de atrás.
static func _air(p: Dictionary, s: Dictionary, trick: bool) -> void:
	var t: float = s.time
	var up := clampf(0.5 + s.vy * 0.12, 0.0, 1.0)
	var tuck := lerpf(0.2, 1.0, up)
	if trick:
		tuck = 1.1
	_crouch(p, tuck)
	_bend(p, Vector3(0.2 * up + (0.3 if trick else 0.0), 0.0, 0.0))
	var wiggle := sin(t * 8.0) * 0.08
	if trick:
		# Grab: la mano de atrás agarra el borde de la tabla, la otra arriba.
		_reach(p, "HandR", Vector3(0.15, 0.35, 0.5), 1.0)
		_reach(p, "HandL", Vector3(-1.0, 2.1 + wiggle, 0.25), 1.0)
		_turn(p, "Head", Vector3(0.3, 0.0, 0.0))
	elif up > 0.5:
		# Subiendo: brazos bien arriba.
		var w := (up - 0.5) * 2.0
		_reach(p, "HandL", Vector3(-0.8, 2.45 + wiggle, 0.25), w)
		_reach(p, "HandR", Vector3(0.8, 2.35 - wiggle, 0.15), w)
	else:
		# Bajando: brazos bien abiertos para el equilibrio, mira el agua y
		# estira las piernas para el aterrizaje.
		var down := 1.0 - up * 2.0
		_reach(p, "HandL", Vector3(-1.35, 1.75 + wiggle, 0.25), down)
		_reach(p, "HandR", Vector3(1.3, 1.65 - wiggle, 0.0), down)
		_turn(p, "Head", Vector3(0.35 * down, 0.0, 0.0))


## Atravesando una ola: agachado y con los brazos tapándose la cabeza.
static func _duck(p: Dictionary, _s: Dictionary) -> void:
	_crouch(p, 0.9)
	_bend(p, Vector3(0.5, 0.0, 0.0))
	_reach(p, "HandL", Vector3(-0.25, 1.95, 0.4), 1.0)
	_reach(p, "HandR", Vector3(0.1, 1.95, 0.45), 1.0)
	_turn(p, "Head", Vector3(0.45, 0.0, 0.0))


## Se para de un salto: empuja con las manos y queda en la postura.
static func _pop_up(p: Dictionary, s: Dictionary) -> void:
	var k := clampf(s.t / 0.3, 0.0, 1.0)
	var push := sin(k * PI)
	_crouch(p, 0.9 - 0.6 * k)
	_reach(p, "HandL", Vector3(-0.4, 0.5, 0.35), push)
	_reach(p, "HandR", Vector3(0.4, 0.5, 0.35), push)


## Se seca la cara: primero sacude la cabeza de lado a lado (como un perro) y
## después se pasa la mano por los ojos. `shake` va de 1 a 0 en ~1 s.
static func _shake_off(p: Dictionary, s: Dictionary) -> void:
	var k: float = 1.0 - s.shake
	var t: float = s.time
	# Sacudón (primera mitad), con el cuerpo acompañando un poco.
	if k < 0.55:
		var env := sin(k / 0.55 * PI)
		_turn(p, "Head", Vector3(0.1 * env, sin(t * 32.0) * 0.6 * env, sin(t * 32.0 + 1.0) * 0.2 * env))
		_turn(p, "Torso", Vector3(0.0, sin(t * 32.0 + 0.5) * 0.12 * env, 0.0))
	# Mano por los ojos (segunda mitad): pasa por delante de la cara.
	if k > 0.4:
		var w := sin(clampf((k - 0.4) / 0.6, 0.0, 1.0) * PI)
		var head: Vector3 = BASE["Head"] + p["Head"].pos
		var slide := lerpf(0.25, -0.3, clampf((k - 0.4) / 0.6, 0.0, 1.0))
		var eyes := head + FACE_DIR * 0.62 + Vector3(slide * 0.55, 0.08, slide * -0.4)
		_reach(p, "HandL", eyes, w)


# ---------------------------------------------------------------- en el agua

## Recién caído: manotea por encima de la cabeza, patalea y sacude la cabeza.
static func _flail(p: Dictionary, s: Dictionary) -> void:
	var t: float = s.t
	var f: float = 13.0 + s.effort * 6.0
	_reach(p, "HandL", Vector3(-0.55 + sin(t * f) * 0.35, 2.85 + sin(t * f * 1.3) * 0.35, 0.3), 1.0)
	_reach(p, "HandR", Vector3(0.55 + sin(t * f + 2.0) * 0.35, 2.85 + sin(t * f * 1.3 + 1.0) * 0.35, 0.3), 1.0)
	_turn(p, "Head", Vector3(-0.25, sin(t * 9.0) * 0.5, sin(t * 7.0) * 0.25))
	_kick(p, t * 14.0, 0.22)
	_turn(p, "Torso", Vector3(0.0, sin(t * 6.0) * 0.25, 0.0))


## Flotando: brazada de pecho a la altura del agua (las manos abren hacia los
## costados y vuelven al pecho), patada de bicicleta y la cabeza que sube y baja.
static func _tread(p: Dictionary, s: Dictionary) -> void:
	var ph: float = s.time * (3.0 + s.effort * 5.0)
	var sweep := (sin(ph) + 1.0) * 0.5
	for side in [-1.0, 1.0]:
		var hand := "HandL" if side < 0.0 else "HandR"
		var target := Vector3(side * (0.3 + 0.75 * sweep), 1.78 + cos(ph) * 0.1, 0.65 - 0.45 * sweep)
		_reach(p, hand, target, 1.0)
	_move(p, "Head", Vector3(0.0, 0.08 + sin(ph) * 0.06, 0.0))
	_turn(p, "Head", Vector3(-0.2, sin(ph * 0.5) * 0.15, 0.0))
	_kick(p, s.time * (6.0 + s.effort * 8.0), 0.18)


## Se sube a la tabla: estira los brazos hacia adelante y tira, pataleando.
static func _climb(p: Dictionary, s: Dictionary) -> void:
	var k := clampf(s.t / 0.45, 0.0, 1.0)
	var reach := sin(k * PI)
	_reach(p, "HandL", Vector3(-0.35, 1.9, 0.6 + 0.3 * reach), 1.0)
	_reach(p, "HandR", Vector3(0.35, 1.9, 0.6 + 0.3 * reach), 1.0)
	_bend(p, Vector3(0.4 * reach, 0.0, 0.0))
	_kick(p, s.t * 16.0, 0.22)


## Acostado sobre la tabla remando: crol, cada brazo hace un círculo grande
## (adelante por arriba, tira por el agua hacia atrás), el cuerpo rola con la
## brazada, la cabeza mira hacia adelante y las piernas patean.
## (Acostado boca abajo, en el espacio del personaje: +Y es hacia adelante y
## +Z hacia el agua.)
static func _paddle(p: Dictionary, s: Dictionary) -> void:
	var ph: float = s.time * (2.6 + s.effort * 7.0)
	for i in 2:
		var hand := "HandL" if i == 0 else "HandR"
		var side := -1.0 if i == 0 else 1.0
		var a := ph + PI * i
		# Adelante (+Y) por arriba (-Z), atrás por el agua (+Z), bien grande.
		var target := Vector3(side * 0.48, 1.7 + cos(a) * 0.95, -sin(a) * 0.6 + 0.2)
		_reach(p, hand, target, 1.0)
	_turn(p, "Torso", Vector3(0.0, sin(ph) * 0.3, 0.0))
	_turn(p, "Head", Vector3(-0.6, sin(ph) * 0.12, 0.0))
	_kick(p, s.time * (9.0 + s.effort * 6.0), 0.14)


## Festeja: salta con los brazos arriba.
static func _celebrate(p: Dictionary, s: Dictionary) -> void:
	var t: float = s.time
	var hop := absf(sin(t * 6.0))
	p["root"].pos += Vector3(0.0, hop * 0.25, 0.0)
	_crouch(p, (1.0 - hop) * 0.3)
	_reach(p, "HandL", Vector3(-0.45, 2.75 + sin(t * 12.0) * 0.08, 0.15), 1.0)
	_reach(p, "HandR", Vector3(0.45, 2.75 + sin(t * 12.0 + 2.0) * 0.08, 0.15), 1.0)
	_turn(p, "Head", Vector3(-0.25, 0.0, sin(t * 6.0) * 0.15))


# ---------------------------------------------------------------- piezas

static func _move(p: Dictionary, part: String, v: Vector3) -> void:
	p[part].pos += v


static func _turn(p: Dictionary, part: String, r: Vector3) -> void:
	p[part].rot += r


## Lleva una mano hacia `target` (en el espacio del personaje), con peso w.
static func _reach(p: Dictionary, hand: String, target: Vector3, w: float) -> void:
	var base: Vector3 = BASE[hand]
	var cur: Vector3 = base + p[hand].pos
	p[hand].pos += (target - cur) * clampf(w, 0.0, 1.0)


## Flexiona las rodillas: baja la cadera y todo lo de arriba; las rodillas van
## hacia adelante (puntas) y un poco abiertas; los pies quedan en la tabla.
static func _crouch(p: Dictionary, c: float) -> void:
	var drop := 0.42 * c
	for part in ["Head", "Torso", "HandL", "HandR"]:
		_move(p, part, Vector3(0.0, -drop, 0.0))
	_move(p, "ShortsHips", Vector3(0.0, -drop * 0.92, -0.04 * c))
	for side in ["L", "R"]:
		var out := -1.0 if side == "L" else 1.0
		_move(p, "Sleeve" + side, Vector3(out * 0.05 * c, -drop * 0.7, 0.1 * c))
		_move(p, "Thigh" + side, Vector3(out * 0.05 * c, -drop * 0.7, 0.12 * c))
		_move(p, "Shin" + side, Vector3(out * 0.03 * c, -drop * 0.3, 0.12 * c))
	# El torso se va un poco hacia adelante al agacharse.
	_turn(p, "Torso", Vector3(0.18 * c, 0.0, 0.0))


## Dobla el torso desde la cintura (rot: x = hacia el pecho, y = girar los
## hombros, z = hacia la punta): mueve la cabeza y las manos con él.
static func _bend(p: Dictionary, rot: Vector3) -> void:
	var b := Basis.from_euler(rot)
	_turn(p, "Torso", rot)
	_turn(p, "Head", rot * 0.6)
	for part in ["Head", "HandL", "HandR"]:
		var base: Vector3 = BASE[part] + p[part].pos
		var rel := base - WAIST
		p[part].pos += (b * rel) - rel


## Patada alternada (pies y canillas hacia adelante y atrás).
static func _kick(p: Dictionary, phase: float, amount: float) -> void:
	var k := sin(phase) * amount
	_move(p, "FootL", Vector3(0.0, 0.0, k))
	_move(p, "FootR", Vector3(0.0, 0.0, -k))
	_move(p, "ShinL", Vector3(0.0, 0.0, k * 0.6))
	_move(p, "ShinR", Vector3(0.0, 0.0, -k * 0.6))
