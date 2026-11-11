class_name StatHexagon
extends Control
## Classic creation stat hexagon as a glowing radar chart. Opposing stats sit
## on opposite vertices (STR/INT, AGI/LUK, VIT/DEX); clicking a vertex raises
## that stat by one and lowers its opposite, keeping each pair at 10.

signal changed(stats: Dictionary)

## Vertex order clockwise from the top; index i is opposite index i + 3.
const ORDER := ["str", "agi", "vit", "int", "luk", "dex"]

var stats := CharacterRules.stats_from_pairs(5, 5, 5)
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 240)


func _vertex(i: int, r: float) -> Vector2:
	var a := -PI / 2.0 + TAU * i / 6.0
	return size / 2.0 + Vector2(cos(a), sin(a)) * r


func _radius() -> float:
	return minf(size.x, size.y) * 0.34


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _vertex_at(e.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _vertex_at(e.position)
		if i >= 0:
			raise(ORDER[i])
			accept_event()


func _vertex_at(p: Vector2) -> int:
	for i in 6:
		if p.distance_to(_vertex(i, _radius() + 26.0)) < 26.0 or p.distance_to(_vertex(i, _radius())) < 18.0:
			return i
	return -1


## Raises `stat` by one at the expense of its opposite, within 1..9.
func raise(stat: String) -> void:
	var i := ORDER.find(stat)
	var opp: String = ORDER[(i + 3) % 6]
	if int(stats[stat]) >= CharacterRules.MAX_STAT:
		return
	stats[stat] = int(stats[stat]) + 1
	stats[opp] = int(stats[opp]) - 1
	queue_redraw()
	changed.emit(stats)


func set_stats(s: Dictionary) -> void:
	stats = s.duplicate()
	queue_redraw()


func _draw() -> void:
	var r := _radius()
	var c := size / 2.0
	# Grid rings and spokes.
	for ring in [0.33, 0.66, 1.0]:
		var pts := PackedVector2Array()
		for i in 7:
			pts.append(_vertex(i % 6, r * ring))
		draw_polyline(pts, Color(UiTheme.ACCENT, 0.18 if ring < 1.0 else 0.4), 1.0, true)
	for i in 6:
		draw_line(c, _vertex(i, r), Color(UiTheme.ACCENT, 0.15), 1.0, true)
	# Stat polygon.
	var poly := PackedVector2Array()
	for i in 6:
		poly.append(_vertex(i, r * float(stats[ORDER[i]]) / CharacterRules.MAX_STAT))
	draw_colored_polygon(poly, Color(UiTheme.ACCENT, 0.18))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(UiTheme.ACCENT, 0.35), 5.0, true)
	draw_polyline(outline, Color(0.85, 0.97, 1.0, 0.95), 1.5, true)
	for p in poly:
		draw_circle(p, 3.5, Color(0.9, 0.98, 1.0))
	# Labels and values at each vertex.
	var f := UiTheme.font(600, 2)
	for i in 6:
		var k: String = ORDER[i]
		var at := _vertex(i, r + 26.0)
		var label := k.to_upper()
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var col := Color.WHITE if i == _hover else Color(UiTheme.ACCENT, 0.9)
		if i == _hover:
			draw_circle(at, 22.0, Color(UiTheme.ACCENT, 0.12))
		draw_string(f, at + Vector2(-lw / 2.0, -2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		var v := str(stats[k])
		var vw := UiTheme.font(700).get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(UiTheme.font(700), at + Vector2(-vw / 2.0, 16), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.TEXT)
