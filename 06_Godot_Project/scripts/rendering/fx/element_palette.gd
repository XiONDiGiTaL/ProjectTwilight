class_name ElementPalette
extends RefCounted
## Colours and circle motifs per element, shared by casting circles, spell
## effects, auras and UI (cast bar). Original design.
##
## motif: 0 hexagram, 1 crescent cross (ghost / shadow), 2 flame petals,
##        3 lightning star, 4 square sigil (earth), 5 wave rings (water).

const ELEMENTS := {
	"neutral": {"core": Color(0.85, 0.92, 1.0), "glow": Color(0.45, 0.7, 1.0), "motif": 0},
	"water":   {"core": Color(0.6, 0.98, 1.0),  "glow": Color(0.1, 0.72, 0.95), "motif": 5},
	"earth":   {"core": Color(0.82, 1.0, 0.55), "glow": Color(0.3, 0.85, 0.3), "motif": 4},
	"fire":    {"core": Color(1.0, 0.85, 0.45), "glow": Color(1.0, 0.32, 0.08), "motif": 2},
	"wind":    {"core": Color(0.85, 0.85, 1.0), "glow": Color(0.42, 0.42, 1.0), "motif": 3},
	"poison":  {"core": Color(0.95, 0.7, 1.0),  "glow": Color(0.72, 0.2, 0.85), "motif": 1},
	"holy":    {"core": Color(1.0, 0.96, 0.75), "glow": Color(1.0, 0.78, 0.3), "motif": 0},
	"shadow":  {"core": Color(0.8, 0.55, 1.0),  "glow": Color(0.42, 0.08, 0.7), "motif": 1},
	"ghost":   {"core": Color(0.92, 0.8, 1.0),  "glow": Color(0.66, 0.42, 1.0), "motif": 1},
	"undead":  {"core": Color(0.75, 1.0, 0.85), "glow": Color(0.35, 0.7, 0.55), "motif": 1},
}


static func core(element: String) -> Color:
	return ELEMENTS.get(element, ELEMENTS.neutral).core


static func glow(element: String) -> Color:
	return ELEMENTS.get(element, ELEMENTS.neutral).glow


static func motif(element: String) -> int:
	return int(ELEMENTS.get(element, ELEMENTS.neutral).motif)
