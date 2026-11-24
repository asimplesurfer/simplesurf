class_name ExoticTrick
extends RefCounted
## Exotic tricks: special moves done on a wave, with a balance minigame, that
## share the same rules:
##   - while doing one, points pile up (POINTS_PER_SEC) and the music rises
##     (Rider.exotic_progress, read by AudioManager);
##   - falling keeps what was piled up;
##   - finishing gives a bonus (BONUS) and motivation (a speed boost).
## Each kind is a rider state (see `state` below) that calls
## Rider.start_exotic / update_exotic / finish_exotic. TrickAttack adds the
## points; the rest happens in Rider.
##
## To add a new one: a value in Kind, its row in each table, and its state.

enum Kind { NONE = -1, LIP, TUBE }

## Display name (for the HUD).
const NAMES := {Kind.LIP: "Borde", Kind.TUBE: "Tubo"}
## Points per second while doing it (trick mode).
const POINTS_PER_SEC := {Kind.LIP: 150.0, Kind.TUBE: 500.0}
## Bonus for finishing it (trick mode).
const BONUS := {Kind.LIP: 2000, Kind.TUBE: 6000}
## Rider state that runs it.
const STATES := {Kind.LIP: &"lip", Kind.TUBE: &"tube"}


static func points_per_sec(kind: Kind) -> float:
	return float(POINTS_PER_SEC.get(kind, 0.0))


static func bonus(kind: Kind) -> int:
	return int(BONUS.get(kind, 0))


static func display_name(kind: Kind) -> String:
	return String(NAMES.get(kind, ""))
