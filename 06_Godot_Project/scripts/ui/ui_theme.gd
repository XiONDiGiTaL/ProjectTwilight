class_name UiTheme
extends RefCounted
## "Twilight Glass" design system: colours, fonts and label factories shared
## by every HUD element, so the interface stays consistent.

# Palette
const TEXT := Color(0.93, 0.97, 1.0)
const TEXT_DIM := Color(0.62, 0.72, 0.82)
const ACCENT := Color(0.42, 0.86, 1.0)        # cyan system accent
const ACCENT_2 := Color(0.62, 0.52, 1.0)      # violet secondary
const GLASS := Color(0.035, 0.06, 0.1, 0.58)
const BORDER := Color(0.55, 0.88, 1.0, 0.55)
const HP_HIGH := Color(0.32, 0.95, 0.66)
const HP_MID := Color(1.0, 0.78, 0.3)
const HP_LOW := Color(1.0, 0.3, 0.38)
const SP := Color(0.38, 0.62, 1.0)
const EXP_BASE := Color(0.45, 0.88, 1.0)
const EXP_JOB := Color(0.72, 0.56, 1.0)
const DAMAGE_TAKEN := Color(1.0, 0.36, 0.42)
const CRIT := Color(1.0, 0.86, 0.42)

static var _fonts: Dictionary = {}


## Condensed DIN-style system font (Bahnschrift on Windows), with fallbacks.
## weight: 300 light, 400 regular, 600 semibold, 700 bold. spacing: extra px per glyph.
static func font(weight := 400, spacing := 0, italic_skew := 0.0) -> Font:
	var key := "%d:%d:%.2f" % [weight, spacing, italic_skew]
	if _fonts.has(key):
		return _fonts[key]
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	base.font_weight = weight
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	if italic_skew != 0.0:
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(italic_skew, 1), Vector2.ZERO)
	_fonts[key] = v
	return v


static func label(text: String, size: int, color := TEXT, weight := 400, spacing := 0, glow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = font(weight, spacing)
	s.font_size = size
	s.font_color = color
	if glow:
		s.outline_size = 6
		s.outline_color = Color(color.r, color.g, color.b, 0.22)
	else:
		s.outline_size = 3
		s.outline_color = Color(0.0, 0.02, 0.05, 0.55)
	s.shadow_size = 2
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_offset = Vector2(0, 1)
	l.label_settings = s
	return l


## HP colour by remaining fraction (green -> amber -> red), blended smoothly.
static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return HP_MID.lerp(HP_HIGH, clampf((frac - 0.5) / 0.2, 0.0, 1.0))
	return HP_LOW.lerp(HP_MID, clampf((frac - 0.2) / 0.15, 0.0, 1.0))
