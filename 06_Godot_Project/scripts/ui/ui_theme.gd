class_name UiTheme
extends RefCounted
## "Twilight Glass" design system: colours, fonts and label factories shared
## by every HUD element, so the interface stays consistent.

# Palette — anime-MMO "system window" look (SAO plates, PSO2 blue windows).
const TEXT := Color(0.95, 0.98, 1.0)
const TEXT_DIM := Color(0.66, 0.78, 0.9)
const ACCENT := Color(0.36, 0.78, 1.0)        # PSO2-style system blue
const ACCENT_2 := Color(0.62, 0.52, 1.0)      # violet secondary
const GLASS := Color(0.05, 0.14, 0.27, 0.62)  # translucent navy body
const HEADER := Color(0.2, 0.55, 0.95)        # title band gradient start
const BORDER := Color(0.62, 0.88, 1.0, 0.6)
const HP_HIGH := Color(0.62, 0.88, 0.2)       # SAO lime green
const HP_MID := Color(1.0, 0.82, 0.2)
const HP_LOW := Color(1.0, 0.28, 0.3)
const SP := Color(0.3, 0.62, 1.0)
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


## Applies the glass button look. primary = accent-filled call to action.
static func style_button(b: BaseButton, primary := false, danger := false, font_size := 13) -> void:
	var accent := HP_LOW if danger else ACCENT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(600, 3))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT if primary else TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.35))
	var make := func(bg_a: float, border_a: float) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent, bg_a)
		sb.border_color = Color(accent, border_a)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		return sb
	b.add_theme_stylebox_override("normal", make.call(0.2 if primary else 0.05, 0.75 if primary else 0.3))
	b.add_theme_stylebox_override("hover", make.call(0.35 if primary else 0.14, 0.95))
	b.add_theme_stylebox_override("pressed", make.call(0.45, 1.0))
	b.add_theme_stylebox_override("hover_pressed", make.call(0.45, 1.0))
	b.add_theme_stylebox_override("disabled", make.call(0.02, 0.12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Glass-styled single-line text input.
static func style_line_edit(e: LineEdit) -> void:
	e.add_theme_font_override("font", font(600, 1))
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(TEXT_DIM, 0.5))
	e.add_theme_color_override("caret_color", ACCENT)
	for state in ["normal", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.05, 0.09, 0.6)
		sb.border_color = Color(ACCENT, 0.8 if state == "focus" else 0.3)
		sb.border_width_bottom = 2 if state == "focus" else 1
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		e.add_theme_stylebox_override(state, sb)


## HP colour by remaining fraction (green -> amber -> red), blended smoothly.
static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return HP_MID.lerp(HP_HIGH, clampf((frac - 0.5) / 0.2, 0.0, 1.0))
	return HP_LOW.lerp(HP_MID, clampf((frac - 0.2) / 0.15, 0.0, 1.0))
