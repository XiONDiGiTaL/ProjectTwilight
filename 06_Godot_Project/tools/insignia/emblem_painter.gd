class_name EmblemPainter
extends Node2D
## Draws one class emblem as a relief mask for the insignia renderer.
##
## Colour convention (read by insignia_render.gdshader):
##   WHITE  raised metal (takes the rank's emblem metal)
##   INK    engraved recess lines
##   other  coloured enamel (crystals, potions, flames, ribbons...)
## Emblem space: (0, 0) is the emblem centre, 1 unit = UNIT pixels, y down.

const CANVAS := 512
const CENTRE := Vector2(256, 234)
const UNIT := 156.0

const WHITE := Color(1, 1, 1)
const INK := Color(0, 0, 0)
const CRYSTAL_BLUE := Color(0.35, 0.65, 1.0)
const ICE := Color(0.7, 0.9, 1.0)
const ARCANE := Color(0.55, 0.3, 0.95)
const POTION := Color(0.7, 0.2, 0.85)
const RUBY := Color(0.85, 0.12, 0.15)
const FAN_PINK := Color(0.95, 0.45, 0.55)
const RIBBON := Color(0.85, 0.2, 0.35)
const GOLD_RIBBON := Color(1.0, 0.78, 0.25)
const WOOD := Color(0.62, 0.4, 0.2)
const FLAME_BLUE := Color(0.3, 0.6, 1.0)
const FLAME_PINK := Color(0.95, 0.35, 0.7)
const AURA := Color(1.0, 0.8, 0.3)

var class_id := "novice"
## Badge mode: Novice-family classes get a simple glyph instead of a blank shield.
var badge_mode := false


func _draw() -> void:
	draw_set_transform(CENTRE, 0.0, Vector2(UNIT, UNIT))
	if has_method("_e_" + class_id):
		call("_e_" + class_id)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Class emblems -------------------------------------------------------------

func _e_novice() -> void:
	if badge_mode:
		_novice_glyph(false)
	# Shield mode: blank shield; the renderer adds the central rivet.

func _e_high_novice() -> void:
	if badge_mode:
		_novice_glyph(true)


## Sprouting seedling: the Novice's beginning.
func _novice_glyph(high: bool) -> void:
	_capsule(Vector2(0, 0.75), Vector2(0, -0.1), 0.07)
	for sx in [-1.0, 1.0]:
		var leaf := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			var a := t * PI
			leaf.append(Vector2(sx * (0.05 + t * 0.62), -0.1 - sin(a) * 0.26 - t * 0.18))
		for i in range(20, -1, -1):
			var t := i / 20.0
			var a := t * PI
			leaf.append(Vector2(sx * (0.05 + t * 0.62), -0.1 + sin(a) * 0.08 - t * 0.18))
		_poly(leaf)
	if high:
		_star(Vector2(0, -0.78), 0.26, 0.11, 4, WHITE)

func _e_swordman() -> void:
	_sword(Vector2(0, 0), -0.75, 2.2)
	_sword(Vector2(0, 0), 0.75, 2.2)
	_small_shield(Vector2(0, 0.08), 0.55, false)

func _e_high_swordman() -> void:
	_sunburst(Vector2(0, -0.05), 0.95, 16, ICE, 0.05)
	_e_swordman()
	_gem(Vector2(0, -0.02), 0.11, CRYSTAL_BLUE)

func _e_mage() -> void:
	_rune_ring(Vector2(0, 0.05), 0.92)
	_crystal(Vector2(0, 0.0), 0.62, ARCANE)

func _e_high_mage() -> void:
	_ring(Vector2(0, 0.05), 1.12, 0.05, ICE)
	_e_mage()

func _e_archer() -> void:
	_bow(Vector2(-0.15, 0), 1.0, false)

func _e_high_archer() -> void:
	_bow(Vector2(-0.15, 0), 1.0, true)

func _e_merchant() -> void:
	_hand(Vector2(0.05, 0.38), 0.95, -0.25)
	_coin(Vector2(-0.12, -0.55), 0.3)
	_arc_motion(Vector2(0.1, -0.15), 0.55, PI * 1.05, PI * 1.55)

func _e_high_merchant() -> void:
	_scale_balance(Vector2(0, 0.1), 1.0)
	_coin(Vector2(0, -0.62), 0.24)
	_crown(Vector2(0, -0.98), 0.32, ICE)

func _e_thief() -> void:
	_hand(Vector2(-0.05, 0.3), 0.95, 0.35)
	_coin(Vector2(0.42, -0.45), 0.24, true)
	_arc_motion(Vector2(0.2, -0.05), 0.5, PI * 1.5, PI * 1.95)

func _e_high_thief() -> void:
	_e_thief()
	_ring(Vector2(0.42, -0.45), 0.36, 0.04, ICE)
	_flame(Vector2(-0.55, -0.45), 0.35, -0.3, ICE)

func _e_acolyte() -> void:
	_ring(Vector2(0, -0.82), 0.32, 0.06)
	_cross(Vector2(0, 0.1), 1.0, false)

func _e_high_acolyte() -> void:
	_ring(Vector2(0, 0.05), 1.0, 0.06, ICE)
	_ring(Vector2(0, -0.82), 0.32, 0.06)
	_cross(Vector2(0, 0.1), 1.0, false)

func _e_knight() -> void:
	_lance(Vector2(0, 0), 0.75, 2.4, false)
	_sword(Vector2(0, 0), -0.75, 2.1)
	_horse_head(Vector2(0, 0.05), 0.55)

func _e_crusader() -> void:
	_sunburst(Vector2(0, 0), 1.05, 12, WHITE, 0.07)
	_small_shield(Vector2(0, 0.05), 1.15, true)

func _e_wizard() -> void:
	_staff(Vector2(0, 0.1), 2.1, 0.0)
	_star(Vector2(0, -0.82), 0.42, 0.18, 8, ARCANE)

func _e_sage() -> void:
	_book(Vector2(0, 0.3), 1.0)
	_quill(Vector2(0.45, -0.25), 1.0, 0.55)
	_rune_glyph(Vector2(-0.35, -0.55), 0.3, CRYSTAL_BLUE)

func _e_hunter() -> void:
	_bow(Vector2(0, 0.35), 0.75, false, true)
	_falcon(Vector2(0, -0.45), 0.75)

func _e_bard() -> void:
	_lute(Vector2(-0.05, 0.1), 1.0, -0.6)
	_note(Vector2(0.55, -0.55), 0.5)

func _e_dancer() -> void:
	_ribbon(Vector2(0, 0.1), 1.0, RIBBON)
	_fan(Vector2(0, -0.1), 1.0, FAN_PINK)

func _e_blacksmith() -> void:
	_anvil(Vector2(0, 0.45), 1.0)
	_hammer(Vector2(0.1, -0.3), 1.0, -0.6)

func _e_alchemist() -> void:
	_flask(Vector2(0, 0.1), 1.0, POTION)

func _e_assassin() -> void:
	_katar(Vector2(0, 0), -0.7, 1.0)
	_katar(Vector2(0, 0), 0.7, 1.0)

func _e_rogue() -> void:
	_dagger(Vector2(0, 0.05), 0.7, 1.0)
	_mask(Vector2(0, -0.1), 0.85)

func _e_priest() -> void:
	_wings(Vector2(0, 0), 1.0, WHITE)
	_cross(Vector2(0, 0.05), 1.0, true)

func _e_monk() -> void:
	_beads(Vector2(0, 0.05), 0.95, 18)
	_fist(Vector2(0, 0.05), 0.85)

func _e_dark_knight() -> void:
	_sword(Vector2(0, 0), -0.75, 2.2)
	# Crossed war axe: haft plus a crescent blade.
	var haft_a := Vector2(-0.75, 0.85)
	var haft_b := Vector2(0.62, -0.72)
	_capsule(haft_a, haft_b, 0.055)
	var blade := PackedVector2Array()
	for i in 13:
		var t := -1.0 + i / 6.0
		blade.append(Vector2(0.6, -0.72) + Vector2(0.38 * cos(t), 0.38 * sin(t)).rotated(-0.75))
	blade.append(Vector2(0.62, -0.72))
	_poly(blade)
	# Horned crest.
	_poly(PackedVector2Array([Vector2(-0.34, -0.55), Vector2(-0.6, -1.08), Vector2(-0.2, -0.68)]))
	_poly(PackedVector2Array([Vector2(0.34, -0.55), Vector2(0.6, -1.08), Vector2(0.2, -0.68)]))
	_gem(Vector2(0, -0.62), 0.13, RUBY)


func _e_shaman() -> void:
	_ring(Vector2(0, 0.05), 0.88, 0.05)
	_staff(Vector2(0, 0.1), 2.0, 0.0)
	var cols := [RUBY, ICE, Color(0.45, 0.85, 0.35), GOLD_RIBBON]
	for i in 4:
		var ang := PI * 0.25 + i * PI * 0.5
		_gem(Vector2(cos(ang), sin(ang)) * 0.62 + Vector2(0, 0.05), 0.14, cols[i])


func _e_lord_knight() -> void:
	_lance(Vector2(0, 0), 0.75, 2.4, true)
	_sword(Vector2(0, 0), -0.75, 2.3, true)
	_crown(Vector2(0, -0.95), 0.36, RUBY)

func _e_paladin() -> void:
	_sunburst(Vector2(0, 0.05), 1.1, 16, AURA, 0.07)
	_small_shield(Vector2(0, 0.15), 1.05, true)
	_crown(Vector2(0, -0.82), 0.4, RUBY)

func _e_high_wizard() -> void:
	_rune_ring(Vector2(0, -0.78), 0.5)
	_staff(Vector2(0, 0.15), 2.1, 0.0)
	_star(Vector2(0, -0.78), 0.55, 0.22, 8, ARCANE)
	_gem(Vector2(0, -0.78), 0.12, WHITE)

func _e_professor() -> void:
	_book(Vector2(0, 0.25), 1.05)
	for i in 4:
		var a := -PI / 2.0 + (i - 1.5) * 0.55
		var p := Vector2(0, 0.2) + Vector2(cos(a), sin(a)) * 1.05
		_elemental_mark(p, 0.2, i)

func _e_sniper() -> void:
	_bow(Vector2(-0.25, 0.2), 0.9, true, true)
	_falcon(Vector2(0.25, -0.5), 0.7, true)

func _e_clown() -> void:
	_lute(Vector2(0.35, 0.3), 0.75, -0.7)
	_jester_mask(Vector2(-0.15, -0.2), 0.8)

func _e_gypsy() -> void:
	_ribbon(Vector2(0, 0.1), 1.1, GOLD_RIBBON)
	_fan(Vector2(0, -0.1), 1.05, FAN_PINK)
	_gem(Vector2(0, 0.42), 0.1, RUBY)

func _e_whitesmith() -> void:
	_anvil(Vector2(0, 0.5), 1.05)
	_hammer(Vector2(0, -0.3), 1.15, -0.5, true)
	_sunburst(Vector2(0.05, -0.6), 0.45, 10, AURA, 0.04)

func _e_creator() -> void:
	_flask(Vector2(0, 0.15), 1.05, Color(0.35, 0.85, 0.5))
	_star(Vector2(0, 0.35), 0.25, 0.1, 4, AURA)
	_ring(Vector2(0, 0.25), 0.82, 0.04)

func _e_assassin_cross() -> void:
	_katar(Vector2(0, 0), -0.7, 1.1, true)
	_katar(Vector2(0, 0), 0.7, 1.1, true)
	_gem(Vector2(0, -0.05), 0.14, RUBY)

func _e_stalker() -> void:
	_mask(Vector2(0, -0.1), 0.95, true)
	_dagger(Vector2(0, 0.1), -0.7, 1.0)

func _e_high_priest() -> void:
	_wings(Vector2(0, 0), 1.15, WHITE)
	_ring(Vector2(0, -0.9), 0.3, 0.06)
	_cross(Vector2(0, 0.08), 1.05, true)
	_gem(Vector2(0, -0.12), 0.1, CRYSTAL_BLUE)

func _e_champion() -> void:
	_sunburst(Vector2(0, 0.05), 1.1, 18, AURA, 0.06)
	_beads(Vector2(0, 0.05), 0.95, 18)
	_fist(Vector2(0, 0.05), 0.85)

func _e_taekwon_kid() -> void:
	_kick_leg(Vector2(0.2, -0.2), 1.0)
	_fist(Vector2(-0.4, 0.45), 0.55)

func _e_ninja() -> void:
	_kunai(Vector2(0, 0), -0.75, 1.0)
	_kunai(Vector2(0, 0), 0.75, 1.0)
	_shuriken(Vector2(0, 0), 0.38)

func _e_gunslinger() -> void:
	_revolver(Vector2(-0.05, 0), -0.7, 1.0)
	_revolver(Vector2(0.05, 0), 0.7, 1.0, true)
	_bullet(Vector2(0, 0.5), 0.35)

func _e_super_novice() -> void:
	_star(Vector2(0, -0.1), 0.95, 0.42, 5, WHITE)
	_sword(Vector2(0.15, 0.25), 0.6, 1.4, false, WOOD)

func _e_star_gladiator() -> void:
	_sunburst(Vector2(0, 0), 1.05, 14, AURA, 0.07)
	_fist(Vector2(0, 0.02), 0.72)

func _e_soul_linker() -> void:
	_flame(Vector2(-0.42, 0.1), 0.95, 0.35, FLAME_BLUE)
	_flame(Vector2(0.42, 0.1), 0.95, -0.35, FLAME_PINK)
	_orb(Vector2(0, 0.05), 0.4, Color(0.6, 0.45, 1.0))


# --- Primitives ----------------------------------------------------------------

func _rot(points: PackedVector2Array, at: Vector2, angle: float, s := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(at + (p * s).rotated(angle))
	return out


func _poly(points: PackedVector2Array, color := WHITE) -> void:
	draw_colored_polygon(points, color)


func _capsule(a: Vector2, b: Vector2, r: float, color := WHITE) -> void:
	var d := (b - a).normalized().orthogonal() * r
	_poly(PackedVector2Array([a + d, b + d, b - d, a - d]), color)
	draw_circle(a, r, color)
	draw_circle(b, r, color)


func _line(a: Vector2, b: Vector2, w := 0.025, color := INK) -> void:
	draw_line(a, b, color, w)


func _ring(c: Vector2, r: float, w: float, color := WHITE) -> void:
	draw_arc(c, r, 0.0, TAU, 96, color, w)


func _ellipse(c: Vector2, rx: float, ry: float, angle := 0.0, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	return pts


func _star(c: Vector2, r_out: float, r_in: float, points: int, color := WHITE) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI / 2.0 + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	_poly(pts, color)
	if color != WHITE:
		for i in points:
			var a := -PI / 2.0 + TAU * i / points
			_line(c, c + Vector2(cos(a), sin(a)) * r_out * 0.8, 0.02, color.lightened(0.5))


func _gem(c: Vector2, r: float, color: Color) -> void:
	_poly(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
	_poly(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.4, -r * 0.1), c + Vector2(-r * 0.4, -r * 0.1)]), color.lightened(0.5))


func _sword(c: Vector2, angle: float, length: float, ornate := false, color := WHITE) -> void:
	var h := length / 2.0
	var w := 0.115 * length / 2.0
	var guard_y := h - 0.42
	var blade := PackedVector2Array([Vector2(0, -h), Vector2(w, -h + 0.18), Vector2(w, guard_y), Vector2(-w, guard_y), Vector2(-w, -h + 0.18)])
	_poly(_rot(blade, c, angle), color)
	var gw := 0.3 if not ornate else 0.38
	var guard := PackedVector2Array([Vector2(-gw, guard_y), Vector2(gw, guard_y), Vector2(gw - 0.05, guard_y + 0.08), Vector2(-gw + 0.05, guard_y + 0.08)])
	_poly(_rot(guard, c, angle), color)
	if ornate:
		draw_circle(c + Vector2(-gw, guard_y + 0.04).rotated(angle), 0.06, color)
		draw_circle(c + Vector2(gw, guard_y + 0.04).rotated(angle), 0.06, color)
	var grip := PackedVector2Array([Vector2(-0.035, guard_y + 0.08), Vector2(0.035, guard_y + 0.08), Vector2(0.035, h - 0.08), Vector2(-0.035, h - 0.08)])
	_poly(_rot(grip, c, angle), color)
	draw_circle(c + Vector2(0, h - 0.04).rotated(angle), 0.065, color)
	_line(c + Vector2(0, -h + 0.22).rotated(angle), c + Vector2(0, guard_y - 0.06).rotated(angle), 0.022)


func _small_shield(c: Vector2, s: float, with_cross: bool) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(Vector2(lerpf(-0.5, 0.5, t), -0.55 + 0.04 * sin(t * PI)))
	for i in 21:
		var t := float(i) / 20.0
		var y := lerpf(-0.1, 0.62, t)
		pts.append(Vector2(0.5 * sqrt(maxf(0.0, 1.0 - t * t)), y))
	for i in range(20, -1, -1):
		var t := float(i) / 20.0
		var y := lerpf(-0.1, 0.62, t)
		pts.append(Vector2(-0.5 * sqrt(maxf(0.0, 1.0 - t * t)), y))
	_poly(_rot(pts, c, 0.0, s))
	var inner := _rot(pts, c + Vector2(0, 0.02 * s), 0.0, s * 0.8)
	inner.append(inner[0])
	draw_polyline(inner, INK, 0.025)
	if with_cross:
		_cross(c + Vector2(0, -0.02 * s), s * 0.62, true, RUBY)


func _cross(c: Vector2, s: float, ornate: bool, color := WHITE) -> void:
	var t := 0.13 * s
	var arm := 0.42 * s
	var top := 0.62 * s
	var bottom := 0.78 * s
	var v := PackedVector2Array([Vector2(-t, -top), Vector2(t, -top), Vector2(t, bottom), Vector2(-t, bottom)])
	var hz := PackedVector2Array([Vector2(-arm, -t - 0.2 * s), Vector2(arm, -t - 0.2 * s), Vector2(arm, t - 0.2 * s), Vector2(-arm, t - 0.2 * s)])
	_poly(_rot(v, c, 0.0), color)
	_poly(_rot(hz, c, 0.0), color)
	if ornate:
		for e in [Vector2(0, -top), Vector2(0, bottom), Vector2(-arm, -0.2 * s), Vector2(arm, -0.2 * s)]:
			draw_circle(c + e, t * 1.25, color)
	if color == WHITE:
		_line(c + Vector2(0, -top + t), c + Vector2(0, bottom - t), 0.02)
		_line(c + Vector2(-arm + t, -0.2 * s), c + Vector2(arm - t, -0.2 * s), 0.02)


func _sunburst(c: Vector2, r: float, rays: int, color: Color, width: float) -> void:
	for i in rays:
		var a := TAU * i / rays
		var len := r * (1.0 if i % 2 == 0 else 0.78)
		var d := Vector2(cos(a), sin(a))
		var o := d.orthogonal() * width
		_poly(PackedVector2Array([c + d * r * 0.35 + o, c + d * len, c + d * r * 0.35 - o]), color)


func _crystal(c: Vector2, s: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -1.0), Vector2(0.42, -0.45), Vector2(0.42, 0.45), Vector2(0, 1.0), Vector2(-0.42, 0.45), Vector2(-0.42, -0.45)])
	_poly(_rot(pts, c, 0.0, s), color)
	_poly(_rot(PackedVector2Array([Vector2(0, -1.0), Vector2(0.42, -0.45), Vector2(0, -0.2), Vector2(-0.42, -0.45)]), c, 0.0, s), color.lightened(0.45))
	_poly(_rot(PackedVector2Array([Vector2(0, -0.2), Vector2(0.42, -0.45), Vector2(0.42, 0.45), Vector2(0, 1.0)]), c, 0.0, s), color.darkened(0.25))


func _rune_ring(c: Vector2, r: float) -> void:
	_ring(c, r, 0.07)
	_ring(c, r * 0.8, 0.035)
	for i in 12:
		var a := TAU * i / 12.0
		var p := c + Vector2(cos(a), sin(a)) * r * 0.9
		_line(p - Vector2(cos(a + 1.2), sin(a + 1.2)) * 0.05, p + Vector2(cos(a + 1.2), sin(a + 1.2)) * 0.05, 0.03)


func _rune_glyph(c: Vector2, s: float, color: Color) -> void:
	_ring(c, s, 0.05, color)
	_line(c + Vector2(0, -s * 0.7), c + Vector2(0, s * 0.7), 0.06, color)
	_line(c + Vector2(0, -s * 0.2), c + Vector2(s * 0.5, -s * 0.6), 0.06, color)
	_line(c + Vector2(0, s * 0.1), c + Vector2(-s * 0.5, -s * 0.3), 0.06, color)


func _bow(c: Vector2, s: float, crystal_tip: bool, horizontal := false) -> void:
	var ang := -PI / 2.0 if horizontal else 0.0
	var pts := PackedVector2Array()
	var n := 32
	for i in n + 1:
		var t := float(i) / n
		var a := lerpf(-1.15, 1.15, t)
		pts.append(Vector2(-cos(a) * 0.55 + 0.55, sin(a) * 0.95) * s)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in pts.size():
		var t := float(i) / n
		var thick := (0.055 + 0.07 * sin(t * PI)) * s
		var tangent := (pts[mini(i + 1, n)] - pts[maxi(i - 1, 0)]).normalized()
		outer.append(pts[i] - tangent.orthogonal() * thick)
		inner.append(pts[i] + tangent.orthogonal() * thick)
	inner.reverse()
	var body := outer + inner
	_poly(_rot(body, c, ang))
	var tip_a := Vector2(-cos(-1.15) * 0.55 + 0.55, sin(-1.15) * 0.95) * s
	var tip_b := Vector2(-cos(1.15) * 0.55 + 0.55, sin(1.15) * 0.95) * s
	_line(c + tip_a.rotated(ang), c + tip_b.rotated(ang), 0.025, WHITE)
	# Arrow nocked on the string, pointing away from the grip.
	var nock := Vector2(tip_a.x, 0)
	var head := Vector2(1.25 * s, 0)
	_line(c + nock.rotated(ang), c + head.rotated(ang), 0.075, WHITE)
	var hc := WHITE if not crystal_tip else ICE
	_poly(_rot(PackedVector2Array([head + Vector2(0.22 * s, 0), head + Vector2(0, -0.1 * s), head + Vector2(0, 0.1 * s)]), c, ang), hc)
	for k in 2:
		var fy := (0.1 if k == 0 else -0.1) * s
		_poly(_rot(PackedVector2Array([nock + Vector2(0.05 * s, 0), nock + Vector2(0.22 * s, 0), nock + Vector2(0.12 * s, fy)]), c, ang))


func _coin(c: Vector2, r: float, edge_on := false) -> void:
	if edge_on:
		_poly(_ellipse(c, r, r * 0.45, -0.5))
		draw_polyline(_ellipse(c, r * 0.75, r * 0.32, -0.5) + PackedVector2Array([_ellipse(c, r * 0.75, r * 0.32, -0.5)[0]]), INK, 0.025)
		return
	draw_circle(c, r, WHITE)
	_ring(c, r * 0.78, 0.03, INK)
	_star(c, r * 0.45, r * 0.2, 5, WHITE)
	_ring(c, r * 0.45, 0.0001, WHITE)


func _arc_motion(c: Vector2, r: float, a0: float, a1: float) -> void:
	for k in 3:
		draw_arc(c, r + k * 0.06, a0 + k * 0.08, a1 - k * 0.05, 24, WHITE, 0.03 - k * 0.006)


func _hand(c: Vector2, s: float, angle: float) -> void:
	# Open palm facing up, fingers curled slightly, thumb to the left.
	var palm := PackedVector2Array([Vector2(-0.38, -0.1), Vector2(0.4, -0.12), Vector2(0.46, 0.18), Vector2(0.2, 0.42), Vector2(-0.3, 0.38), Vector2(-0.45, 0.12)])
	_poly(_rot(palm, c, angle, s))
	var fingers := [[Vector2(0.38, -0.12), Vector2(0.62, -0.42), 0.075], [Vector2(0.2, -0.15), Vector2(0.38, -0.55), 0.08],
		[Vector2(0.0, -0.15), Vector2(0.1, -0.58), 0.08], [Vector2(-0.2, -0.12), Vector2(-0.18, -0.48), 0.075]]
	for f in fingers:
		_capsule(c + (f[0] * s).rotated(angle), c + (f[1] * s).rotated(angle), f[2] * s)
	_capsule(c + (Vector2(-0.38, 0.08) * s).rotated(angle), c + (Vector2(-0.68, -0.18) * s).rotated(angle), 0.085 * s)
	# Sleeve cuff.
	_poly(_rot(PackedVector2Array([Vector2(-0.32, 0.36), Vector2(0.22, 0.4), Vector2(0.2, 0.62), Vector2(-0.34, 0.58)]), c, angle, s))
	_line(c + (Vector2(-0.32, 0.38) * s).rotated(angle), c + (Vector2(0.22, 0.42) * s).rotated(angle), 0.03)
	_line(c + (Vector2(-0.1, 0.0) * s).rotated(angle), c + (Vector2(0.25, 0.12) * s).rotated(angle), 0.02)


func _scale_balance(c: Vector2, s: float) -> void:
	_capsule(c + Vector2(0, -0.45) * s, c + Vector2(0, 0.55) * s, 0.04 * s)
	_capsule(c + Vector2(-0.7, -0.35) * s, c + Vector2(0.7, -0.35) * s, 0.035 * s)
	_poly(PackedVector2Array([c + Vector2(-0.3, 0.6) * s, c + Vector2(0.3, 0.6) * s, c + Vector2(0.2, 0.5) * s, c + Vector2(-0.2, 0.5) * s]))
	for sx in [-1.0, 1.0]:
		var top := c + Vector2(0.7 * sx, -0.35) * s
		_line(top, top + Vector2(-0.22, 0.45) * s, 0.02, WHITE)
		_line(top, top + Vector2(0.22, 0.45) * s, 0.02, WHITE)
		draw_arc(top + Vector2(0, 0.45) * s, 0.24 * s, 0.0, PI, 16, WHITE, 0.07 * s)


func _crown(c: Vector2, s: float, gem_color: Color) -> void:
	var pts := PackedVector2Array([Vector2(-0.6, 0.3), Vector2(-0.65, -0.3), Vector2(-0.3, 0.0), Vector2(0, -0.45), Vector2(0.3, 0.0), Vector2(0.65, -0.3), Vector2(0.6, 0.3)])
	_poly(_rot(pts, c, 0.0, s))
	for p in [Vector2(-0.65, -0.3), Vector2(0, -0.45), Vector2(0.65, -0.3)]:
		draw_circle(c + p * s, 0.09 * s, WHITE)
	_line(c + Vector2(-0.58, 0.15) * s, c + Vector2(0.58, 0.15) * s, 0.025)
	_gem(c + Vector2(0, 0.05) * s, 0.12 * s, gem_color)


func _lance(c: Vector2, angle: float, length: float, dragon: bool) -> void:
	var h := length / 2.0
	var shaft := PackedVector2Array([Vector2(-0.045, -h + 0.5), Vector2(0.045, -h + 0.5), Vector2(0.045, h), Vector2(-0.045, h)])
	_poly(_rot(shaft, c, angle))
	var cone := PackedVector2Array([Vector2(0, -h), Vector2(0.11, -h + 0.55), Vector2(-0.11, -h + 0.55)])
	_poly(_rot(cone, c, angle))
	var vamp := PackedVector2Array([Vector2(-0.07, h - 0.62), Vector2(0.07, h - 0.62), Vector2(0.2, h - 0.4), Vector2(-0.2, h - 0.4)])
	_poly(_rot(vamp, c, angle))
	_line(c + Vector2(0, -h + 0.08).rotated(angle), c + Vector2(0, -h + 0.5).rotated(angle), 0.02)
	if dragon:
		_dragon_head(c + Vector2(0, -h + 0.72).rotated(angle), 0.32, angle)


func _horse_head(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([Vector2(-0.05, -0.75), Vector2(0.12, -0.55), Vector2(0.45, -0.3), Vector2(0.62, -0.05),
		Vector2(0.58, 0.12), Vector2(0.38, 0.1), Vector2(0.2, 0.02), Vector2(0.1, 0.25), Vector2(0.25, 0.75),
		Vector2(-0.45, 0.75), Vector2(-0.4, 0.15), Vector2(-0.3, -0.35), Vector2(-0.18, -0.62)])
	_poly(_rot(pts, c, 0.0, s))
	draw_circle(c + Vector2(0.18, -0.3) * s, 0.06 * s, INK)
	for i in 4:
		var y := -0.55 + i * 0.22
		_line(c + Vector2(-0.3 + i * 0.02, y) * s, c + Vector2(-0.12 + i * 0.02, y + 0.12) * s, 0.025)
	_line(c + Vector2(-0.45, 0.62) * s, c + Vector2(0.25, 0.62) * s, 0.03)


func _dragon_head(c: Vector2, s: float, angle := 0.0) -> void:
	var pts := PackedVector2Array([Vector2(0, -0.9), Vector2(0.25, -0.45), Vector2(0.55, -0.6), Vector2(0.38, -0.2),
		Vector2(0.45, 0.35), Vector2(0.15, 0.8), Vector2(0, 0.95), Vector2(-0.15, 0.8), Vector2(-0.45, 0.35),
		Vector2(-0.38, -0.2), Vector2(-0.55, -0.6), Vector2(-0.25, -0.45)])
	_poly(_rot(pts, c, angle, s))
	for sx in [-1.0, 1.0]:
		draw_circle(c + (Vector2(0.17 * sx, 0.0) * s).rotated(angle), 0.07 * s, RUBY)
	_line(c + (Vector2(0, 0.3) * s).rotated(angle), c + (Vector2(0, 0.75) * s).rotated(angle), 0.02)


func _staff(c: Vector2, length: float, angle: float) -> void:
	var h := length / 2.0
	_capsule(c + Vector2(0, -h + 0.45).rotated(angle), c + Vector2(0, h).rotated(angle), 0.05)
	for y in [0.15, 0.45]:
		_poly(_rot(PackedVector2Array([Vector2(-0.09, y - 0.04), Vector2(0.09, y - 0.04), Vector2(0.09, y + 0.04), Vector2(-0.09, y + 0.04)]), c, angle))
	# Head: crescent cradle holding the crystal.
	var head_c := c + Vector2(0, -h + 0.35).rotated(angle)
	draw_arc(head_c, 0.26, 0.15, PI - 0.15, 24, WHITE, 0.07)


func _book(c: Vector2, s: float) -> void:
	for sx in [-1.0, 1.0]:
		var page := PackedVector2Array([Vector2(0, -0.32), Vector2(0.72 * sx, -0.45), Vector2(0.75 * sx, 0.3), Vector2(0, 0.42)])
		_poly(_rot(page, c, 0.0, s))
		for i in 5:
			var y := -0.28 + i * 0.12
			_line(c + Vector2(0.12 * sx, y + 0.03) * s, c + Vector2(0.6 * sx, y - 0.02) * s, 0.02)
	_line(c + Vector2(0, -0.32) * s, c + Vector2(0, 0.42) * s, 0.035)
	var cover := PackedVector2Array([Vector2(-0.8, 0.32), Vector2(0, 0.48), Vector2(0.8, 0.32), Vector2(0.8, 0.4), Vector2(0, 0.56), Vector2(-0.8, 0.4)])
	_poly(_rot(cover, c, 0.0, s))


func _quill(c: Vector2, s: float, angle: float) -> void:
	var vane := PackedVector2Array([Vector2(0, -0.8), Vector2(0.16, -0.5), Vector2(0.14, 0.0), Vector2(0.03, 0.35), Vector2(-0.06, 0.1), Vector2(-0.12, -0.4)])
	_poly(_rot(vane, c, angle, s))
	_line(c + (Vector2(0, -0.75) * s).rotated(angle), c + (Vector2(0.02, 0.6) * s).rotated(angle), 0.025)
	_line(c + (Vector2(0.02, 0.35) * s).rotated(angle), c + (Vector2(0.03, 0.65) * s).rotated(angle), 0.04, WHITE)
	for i in 5:
		var y := -0.55 + i * 0.16
		_line(c + (Vector2(0.0, y) * s).rotated(angle), c + (Vector2(0.12, y - 0.08) * s).rotated(angle), 0.015)


func _falcon(c: Vector2, s: float, flying := false) -> void:
	var lift := -0.25 if flying else 0.0
	for sx in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0.08 * sx, -0.05), Vector2(0.55 * sx, -0.45 + lift), Vector2(0.95 * sx, -0.5 + lift),
			Vector2(0.85 * sx, -0.3 + lift), Vector2(0.95 * sx, -0.22 + lift), Vector2(0.78 * sx, -0.08 + lift),
			Vector2(0.85 * sx, 0.02 + lift), Vector2(0.6 * sx, 0.08), Vector2(0.15 * sx, 0.2)])
		_poly(_rot(wing, c, 0.0, s))
		for k in 3:
			_line(c + Vector2((0.3 + k * 0.17) * sx, -0.1 - k * 0.05 + lift * 0.5) * s, c + Vector2((0.45 + k * 0.17) * sx, -0.35 - k * 0.03 + lift) * s, 0.018)
	_poly(_ellipse(c + Vector2(0, 0.12) * s, 0.16 * s, 0.32 * s))
	_poly(_rot(PackedVector2Array([Vector2(-0.14, 0.38), Vector2(0.14, 0.38), Vector2(0.2, 0.62), Vector2(-0.2, 0.62)]), c, 0.0, s))
	draw_circle(c + Vector2(0, -0.25) * s, 0.13 * s, WHITE)
	_poly(_rot(PackedVector2Array([Vector2(0.08, -0.28), Vector2(0.24, -0.22), Vector2(0.1, -0.16)]), c, 0.0, s))
	draw_circle(c + Vector2(0.04, -0.28) * s, 0.028 * s, INK)


func _lute(c: Vector2, s: float, angle: float) -> void:
	_poly(_rot(_ellipse(Vector2(0, 0.25), 0.42, 0.5), c, angle, s))
	draw_circle(c + (Vector2(0, 0.15) * s).rotated(angle), 0.12 * s, INK)
	_poly(_rot(PackedVector2Array([Vector2(-0.07, -0.25), Vector2(0.07, -0.25), Vector2(0.06, -0.95), Vector2(-0.06, -0.95)]), c, angle, s))
	_poly(_rot(PackedVector2Array([Vector2(-0.08, -0.95), Vector2(0.08, -0.95), Vector2(0.16, -1.2), Vector2(0.02, -1.22)]), c, angle, s))
	for k in 4:
		var x := -0.045 + k * 0.03
		_line(c + (Vector2(x, -0.95) * s).rotated(angle), c + (Vector2(x * 1.5, 0.55) * s).rotated(angle), 0.01)
	_poly(_rot(PackedVector2Array([Vector2(-0.18, 0.5), Vector2(0.18, 0.5), Vector2(0.18, 0.56), Vector2(-0.18, 0.56)]), c, angle, s), INK)


func _note(c: Vector2, s: float) -> void:
	_poly(_ellipse(c + Vector2(-0.12, 0.3) * s, 0.17 * s, 0.12 * s, -0.4))
	_capsule(c + Vector2(0.03, 0.28) * s, c + Vector2(0.03, -0.45) * s, 0.03 * s)
	_poly(PackedVector2Array([c + Vector2(0.03, -0.48) * s, c + Vector2(0.3, -0.25) * s, c + Vector2(0.24, -0.1) * s, c + Vector2(0.03, -0.25) * s]))


func _fan(c: Vector2, s: float, color: Color) -> void:
	var pivot := c + Vector2(0, 0.55) * s
	var pts := PackedVector2Array([pivot])
	var a0 := -PI + 0.35
	var a1 := -0.35
	for i in 25:
		var a := lerpf(a0, a1, i / 24.0)
		pts.append(pivot + Vector2(cos(a), sin(a)) * 1.05 * s)
	_poly(pts, color)
	for i in 9:
		var a := lerpf(a0, a1, i / 8.0)
		_line(pivot, pivot + Vector2(cos(a), sin(a)) * 1.05 * s, 0.035, WHITE)
	draw_arc(pivot, 1.05 * s, a0, a1, 32, WHITE, 0.05)
	draw_arc(pivot, 0.35 * s, a0, a1, 16, WHITE, 0.05)
	draw_circle(pivot, 0.08 * s, WHITE)


func _ribbon(c: Vector2, s: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			pts.append(c + Vector2(sx * (0.1 + t * 0.85), 0.5 + sin(t * TAU * 1.2) * 0.18 - t * 0.2) * s)
		draw_polyline(pts, color, 0.09 * s)


func _hammer(c: Vector2, s: float, angle: float, ornate := false) -> void:
	_poly(_rot(PackedVector2Array([Vector2(-0.05, -0.2), Vector2(0.05, -0.2), Vector2(0.05, 0.85), Vector2(-0.05, 0.85)]), c, angle, s))
	var head := PackedVector2Array([Vector2(-0.42, -0.42), Vector2(0.42, -0.42), Vector2(0.42, -0.12), Vector2(-0.42, -0.12)])
	_poly(_rot(head, c, angle, s))
	_line(c + (Vector2(-0.25, -0.42) * s).rotated(angle), c + (Vector2(-0.25, -0.12) * s).rotated(angle), 0.025)
	_line(c + (Vector2(0.25, -0.42) * s).rotated(angle), c + (Vector2(0.25, -0.12) * s).rotated(angle), 0.025)
	if ornate:
		_gem(c + (Vector2(0, -0.27) * s).rotated(angle), 0.09 * s, RUBY)


func _anvil(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([Vector2(-0.85, -0.3), Vector2(0.55, -0.3), Vector2(0.7, -0.18), Vector2(0.3, -0.05),
		Vector2(0.25, 0.15), Vector2(0.45, 0.32), Vector2(-0.45, 0.32), Vector2(-0.25, 0.15), Vector2(-0.3, -0.05), Vector2(-0.6, -0.12)])
	_poly(_rot(pts, c, 0.0, s))
	_line(c + Vector2(-0.8, -0.2) * s, c + Vector2(0.5, -0.2) * s, 0.025)


func _flask(c: Vector2, s: float, liquid: Color) -> void:
	var bulb := c + Vector2(0, 0.25) * s
	draw_circle(bulb, 0.55 * s, WHITE)
	# Liquid fills the lower part of the bulb.
	var pts := PackedVector2Array()
	for i in 33:
		var a := lerpf(-0.15, PI + 0.15, i / 32.0)
		pts.append(bulb + Vector2(cos(a), sin(a)) * 0.45 * s)
	_poly(pts, liquid)
	for b in [Vector2(-0.15, 0.25), Vector2(0.12, 0.38), Vector2(0.02, 0.12), Vector2(0.22, 0.18)]:
		draw_circle(bulb + b * s, 0.05 * s, liquid.lightened(0.55))
	_poly(PackedVector2Array([c + Vector2(-0.14, -0.62) * s, c + Vector2(0.14, -0.62) * s, c + Vector2(0.14, -0.2) * s, c + Vector2(-0.14, -0.2) * s]))
	_poly(PackedVector2Array([c + Vector2(-0.2, -0.68) * s, c + Vector2(0.2, -0.68) * s, c + Vector2(0.2, -0.6) * s, c + Vector2(-0.2, -0.6) * s]))
	_poly(PackedVector2Array([c + Vector2(-0.11, -0.92) * s, c + Vector2(0.11, -0.92) * s, c + Vector2(0.13, -0.68) * s, c + Vector2(-0.13, -0.68) * s]), WOOD)
	draw_arc(bulb, 0.5 * s, PI * 1.15, PI * 1.45, 12, INK, 0.02)


func _katar(c: Vector2, angle: float, s: float, ornate := false) -> void:
	var blade := PackedVector2Array([Vector2(0, -1.05), Vector2(0.13, -0.6), Vector2(0.13, 0.2), Vector2(-0.13, 0.2), Vector2(-0.13, -0.6)])
	_poly(_rot(blade, c, angle, s))
	_line(c + (Vector2(0, -0.9) * s).rotated(angle), c + (Vector2(0, 0.15) * s).rotated(angle), 0.025)
	for sx in [-1.0, 1.0]:
		_poly(_rot(PackedVector2Array([Vector2(0.15 * sx, 0.18), Vector2(0.24 * sx, 0.18), Vector2(0.24 * sx, 0.95), Vector2(0.15 * sx, 0.95)]), c, angle, s))
	_poly(_rot(PackedVector2Array([Vector2(-0.16, 0.55), Vector2(0.16, 0.55), Vector2(0.16, 0.63), Vector2(-0.16, 0.63)]), c, angle, s))
	if ornate:
		draw_circle(c + (Vector2(0, 0.2) * s).rotated(angle), 0.08 * s, RUBY)


func _dagger(c: Vector2, angle: float, s: float) -> void:
	# Curved blade: right edge and left edge share the curve, meeting at the tip.
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		var bend := 0.22 * sin(t * PI * 0.5) * t
		var half := 0.1 * (1.0 - t)
		right.append(Vector2(bend + half, -0.15 - t * 0.85))
		if i < 12:
			left.append(Vector2(bend - half, -0.15 - t * 0.85))
	left.reverse()
	_poly(_rot(right + left, c, angle, s))
	_line(c + (Vector2(0.0, -0.2) * s).rotated(angle), c + (Vector2(0.12, -0.75) * s).rotated(angle), 0.02)
	_poly(_rot(PackedVector2Array([Vector2(-0.25, -0.17), Vector2(0.25, -0.17), Vector2(0.25, -0.08), Vector2(-0.25, -0.08)]), c, angle, s))
	_capsule(c + (Vector2(0, -0.08) * s).rotated(angle), c + (Vector2(0, 0.35) * s).rotated(angle), 0.06 * s)
	draw_circle(c + (Vector2(0, 0.42) * s).rotated(angle), 0.08 * s, WHITE)


func _mask(c: Vector2, s: float, shadowed := false) -> void:
	var pts := PackedVector2Array([Vector2(-0.7, -0.2), Vector2(-0.35, -0.38), Vector2(0, -0.3), Vector2(0.35, -0.38),
		Vector2(0.7, -0.2), Vector2(0.6, 0.12), Vector2(0.25, 0.2), Vector2(0, 0.05), Vector2(-0.25, 0.2), Vector2(-0.6, 0.12)])
	_poly(_rot(pts, c, 0.0, s), WHITE if not shadowed else Color(0.25, 0.22, 0.35))
	for sx in [-1.0, 1.0]:
		_poly(_ellipse(c + Vector2(0.33 * sx, -0.08) * s, 0.15 * s, 0.07 * s, 0.25 * sx), INK)
	if shadowed:
		draw_polyline(_rot(pts, c, 0.0, s) + PackedVector2Array([_rot(pts, c, 0.0, s)[0]]), WHITE, 0.035)


func _jester_mask(c: Vector2, s: float) -> void:
	_poly(_ellipse(c, 0.42 * s, 0.5 * s))
	for sx in [-1.0, 1.0]:
		_poly(_ellipse(c + Vector2(0.17 * sx, -0.1) * s, 0.1 * s, 0.06 * s, 0.3 * sx), INK)
		_poly(_rot(PackedVector2Array([Vector2(0.15 * sx, -0.45), Vector2(0.75 * sx, -0.85), Vector2(0.55 * sx, -0.35)]), c, 0.0, s), RUBY)
		draw_circle(c + Vector2(0.75 * sx, -0.85) * s, 0.08 * s, AURA)
	draw_arc(c + Vector2(0, 0.12) * s, 0.2 * s, 0.3, PI - 0.3, 16, INK, 0.035)


func _wings(c: Vector2, s: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		for k in 5:
			var a := -0.25 - k * 0.22
			var len := (1.05 - k * 0.1) * s
			var base := c + Vector2(0.18 * sx, -0.05 - k * 0.02) * s
			var dir := Vector2(cos(a) * sx, sin(a))
			var tip := base + dir * len
			var o := dir.orthogonal() * 0.09 * s
			_poly(PackedVector2Array([base + o, tip, base - o]), color)
			_line(base, base + dir * len * 0.85, 0.015)


func _fist(c: Vector2, s: float) -> void:
	var palm := PackedVector2Array([Vector2(-0.45, -0.3), Vector2(0.45, -0.3), Vector2(0.48, 0.35), Vector2(0.25, 0.6), Vector2(-0.3, 0.6), Vector2(-0.5, 0.3)])
	_poly(_rot(palm, c, 0.0, s))
	for i in 4:
		var x := -0.34 + i * 0.225
		draw_circle(c + Vector2(x, -0.32) * s, 0.13 * s, WHITE)
		_line(c + Vector2(x + 0.112, -0.38) * s, c + Vector2(x + 0.112, -0.12) * s, 0.025)
	_capsule(c + Vector2(-0.45, 0.12) * s, c + Vector2(0.15, 0.0) * s, 0.12 * s)
	_line(c + Vector2(-0.4, -0.05) * s, c + Vector2(0.18, -0.12) * s, 0.025)
	_poly(_rot(PackedVector2Array([Vector2(-0.3, 0.6), Vector2(0.25, 0.6), Vector2(0.22, 0.85), Vector2(-0.28, 0.85)]), c, 0.0, s))
	_line(c + Vector2(-0.3, 0.62) * s, c + Vector2(0.25, 0.62) * s, 0.03)


func _beads(c: Vector2, r: float, n: int) -> void:
	for i in n:
		var a := TAU * i / n
		draw_circle(c + Vector2(cos(a), sin(a)) * r, 0.085, WHITE if i % 6 != 0 else RUBY)
	_capsule(c + Vector2(0, r), c + Vector2(0, r + 0.15), 0.04)


func _shuriken(c: Vector2, s: float) -> void:
	_star(c, s, s * 0.32, 4, WHITE)
	draw_circle(c, s * 0.14, INK)


func _kunai(c: Vector2, angle: float, s: float) -> void:
	_poly(_rot(PackedVector2Array([Vector2(0, -1.0), Vector2(0.15, -0.55), Vector2(0.06, -0.3), Vector2(-0.06, -0.3), Vector2(-0.15, -0.55)]), c, angle, s))
	_line(c + (Vector2(0, -0.9) * s).rotated(angle), c + (Vector2(0, -0.35) * s).rotated(angle), 0.02)
	_capsule(c + (Vector2(0, -0.3) * s).rotated(angle), c + (Vector2(0, 0.6) * s).rotated(angle), 0.045 * s)
	for k in 4:
		var y := -0.15 + k * 0.18
		_line(c + (Vector2(-0.05, y) * s).rotated(angle), c + (Vector2(0.05, y + 0.08) * s).rotated(angle), 0.02)
	draw_arc(c + (Vector2(0, 0.75) * s).rotated(angle), 0.13 * s, 0.0, TAU, 24, WHITE, 0.05 * s)


func _revolver(c: Vector2, angle: float, s: float, mirror := false) -> void:
	var m := -1.0 if mirror else 1.0
	_poly(_rot(PackedVector2Array([Vector2(-0.075, -1.0), Vector2(0.075, -1.0), Vector2(0.075, -0.2), Vector2(-0.075, -0.2)]), c, angle, s))
	_poly(_rot(PackedVector2Array([Vector2(-0.14, -0.28), Vector2(0.18, -0.28), Vector2(0.18, 0.16), Vector2(-0.14, 0.16)]), c, angle, s))
	_poly(_rot(PackedVector2Array([Vector2(-0.04, 0.1), Vector2(0.16, 0.1), Vector2(0.16 + 0.2 * m, 0.66), Vector2(-0.04 + 0.2 * m, 0.7)]), c, angle, s))
	var drum := c + (Vector2(0.02, -0.06) * s).rotated(angle)
	draw_circle(drum, 0.15 * s, WHITE)
	for k in 3:
		draw_circle(drum + Vector2(cos(k * 2.1), sin(k * 2.1)) * 0.08 * s, 0.032 * s, INK)
	_line(c + (Vector2(0, -0.95) * s).rotated(angle), c + (Vector2(0, -0.3) * s).rotated(angle), 0.02)
	draw_arc(c + (Vector2(-0.02, 0.25) * s).rotated(angle), 0.12 * s, 0.0, PI, 12, WHITE, 0.035 * s)


func _bullet(c: Vector2, s: float) -> void:
	_poly(PackedVector2Array([c + Vector2(0, -0.5) * s, c + Vector2(0.14, -0.25) * s, c + Vector2(0.14, 0.45) * s, c + Vector2(-0.14, 0.45) * s, c + Vector2(-0.14, -0.25) * s]), AURA)
	_line(c + Vector2(-0.14, -0.05) * s, c + Vector2(0.14, -0.05) * s, 0.03)


func _kick_leg(c: Vector2, s: float) -> void:
	var hip := c + Vector2(-0.55, 0.5) * s
	var knee := c + Vector2(-0.05, 0.0) * s
	var ankle := c + Vector2(0.55, -0.45) * s
	_capsule(hip, knee, 0.17 * s)
	_capsule(knee, ankle, 0.13 * s)
	_poly(PackedVector2Array([ankle + Vector2(-0.1, -0.12) * s, ankle + Vector2(0.28, -0.32) * s, ankle + Vector2(0.36, -0.18) * s, ankle + Vector2(0.08, 0.1) * s]))
	_line(knee + Vector2(-0.1, -0.05) * s, knee + Vector2(0.1, 0.08) * s, 0.025)
	for k in 3:
		draw_arc(ankle, (0.42 + k * 0.12) * s, PI * 0.55, PI * 0.95, 14, WHITE, 0.035)


func _flame(c: Vector2, s: float, lean: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var t := i / 32.0
		var a := t * TAU
		var r := 0.35 * (1.0 - 0.75 * maxf(0.0, -sin(a)))
		var p := Vector2(cos(a) * r, sin(a) * 0.4)
		if sin(a) < 0.0:
			p.y = -pow(-sin(a), 0.6) * 0.95
			p.x += lean * (-p.y) * 0.5
		pts.append(c + p * s)
	_poly(pts, color)
	var core := PackedVector2Array()
	for p in pts:
		core.append(c + (p - c) * 0.55 + Vector2(0, 0.08) * s)
	_poly(core, color.lightened(0.5))


func _orb(c: Vector2, r: float, color: Color) -> void:
	draw_circle(c, r, color)
	draw_circle(c + Vector2(-0.3, -0.3) * r, r * 0.3, color.lightened(0.7))
	_ring(c, r, 0.05)


func _elemental_mark(c: Vector2, s: float, which: int) -> void:
	var colors := [Color(1.0, 0.45, 0.2), Color(0.3, 0.6, 1.0), Color(0.6, 0.85, 0.35), Color(0.75, 0.75, 1.0)]
	draw_circle(c, s, colors[which])
	_ring(c, s, 0.035)
	match which:
		0: _flame(c + Vector2(0, 0.05), s * 0.75, 0.0, Color(1, 0.85, 0.5))
		1: _poly(_ellipse(c + Vector2(0, 0.05), s * 0.35, s * 0.5), Color(0.8, 0.95, 1.0))
		2: _poly(PackedVector2Array([c + Vector2(-0.6, 0.5) * s, c + Vector2(0, -0.6) * s, c + Vector2(0.6, 0.5) * s]), Color(0.4, 0.3, 0.15))
		_: _line(c + Vector2(-0.5, -0.2) * s, c + Vector2(0.5, 0.2) * s, 0.04, WHITE)
