class_name GameAudioFalloff
extends RefCounted
## Loudness by distance from the listener, in map cells: full volume next to
## the player, silent beyond REACH (about a screen and a half).

const REACH := 24.0
const FULL := 4.0


static func at(distance_cells: float) -> float:
	if distance_cells <= FULL:
		return 1.0
	return clampf(1.0 - (distance_cells - FULL) / (REACH - FULL), 0.0, 1.0)
