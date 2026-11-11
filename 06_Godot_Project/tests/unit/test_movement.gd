extends RefCounted
## Pathfinding and cell movement on synthetic GAT grids.


## Builds a GAT from rows of '.' (walkable) and '#' (blocked); row 0 is the
## northernmost (highest y), like a map drawn north-up.
static func _gat(rows: Array) -> GatFile:
	var g := GatFile.new()
	g.height = rows.size()
	g.width = (rows[0] as String).length()
	g.heights.resize(g.width * g.height * 4)
	g.types.resize(g.width * g.height)
	for r in rows.size():
		var y: int = g.height - 1 - r
		for x in g.width:
			g.types[x + y * g.width] = GatFile.CellType.BLOCKED if rows[r][x] == "#" else GatFile.CellType.WALKABLE
	return g


func test_straight_and_diagonal_path(_t) -> Variant:
	var pf := GridPathfinder.new(_gat([".....", ".....", ".....", ".....", "....."]))
	var p := pf.find_path(Vector2i(0, 0), Vector2i(4, 4))
	if p.size() != 4 or p[-1] != Vector2i(4, 4):
		return "diagonal path should take 4 steps: %s" % str(p)
	p = pf.find_path(Vector2i(0, 0), Vector2i(4, 0))
	return true if p.size() == 4 else "straight path wrong: %s" % str(p)


func test_wall_detour_and_no_corner_cutting(_t) -> Variant:
	# Wall at x=2 except a gap at the top row (y=4).
	var pf := GridPathfinder.new(_gat([".....", "..#..", "..#..", "..#..", "..#.."]))
	var p := pf.find_path(Vector2i(0, 0), Vector2i(4, 0))
	if p.is_empty() or not p.has(Vector2i(2, 4)):
		return "should detour through the gap: %s" % str(p)
	var prev := Vector2i(0, 0)
	for c in p:
		if c.x != prev.x and c.y != prev.y:
			if not pf.is_walkable(Vector2i(c.x, prev.y)) or not pf.is_walkable(Vector2i(prev.x, c.y)):
				return "cut a corner from %s to %s" % [prev, c]
		prev = c
	return true


func test_unreachable_and_blocked(_t) -> Variant:
	var pf := GridPathfinder.new(_gat(["..#..", "..#..", "..#.."]))
	if not pf.find_path(Vector2i(0, 0), Vector2i(4, 0)).is_empty():
		return "path through a solid wall"
	if not pf.find_path(Vector2i(0, 0), Vector2i(2, 0)).is_empty():
		return "path to a blocked cell"
	if pf.nearest_walkable(Vector2i(2, 1), 2) == Vector2i(-1, -1):
		return "nearest walkable not found"
	return true


func test_path_length_limit(_t) -> Variant:
	var row := ""
	for i in 80:
		row += "."
	var pf := GridPathfinder.new(_gat([row]))
	if not pf.find_path(Vector2i(0, 0), Vector2i(79, 0)).is_empty():
		return "79-step path should exceed the limit"
	return true if pf.find_path(Vector2i(0, 0), Vector2i(60, 0)).size() == 60 else "60-step path refused"


func test_walker_timing(_t) -> Variant:
	var w := GridWalker.new(Vector2i(0, 0))
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 1)]
	w.walk(path)
	if w.direction != 6:
		return "east should be direction 6, got %d" % w.direction
	w.advance(75.0)  # half of a 150 ms straight step
	if not w.position().is_equal_approx(Vector2(1.0, 0.5)):
		return "mid-step position wrong: %s" % w.position()
	w.advance(75.0)
	if w.cell != Vector2i(1, 0) or w.direction != 5:
		return "after step: cell %s dir %d" % [w.cell, w.direction]
	w.advance(209.0)  # diagonal takes 210 ms
	if w.cell != Vector2i(1, 0):
		return "diagonal finished too early"
	w.advance(1.0)
	return true if w.cell == Vector2i(2, 1) and not w.is_moving() else "did not arrive"


func test_walker_reclick_finishes_current_step(_t) -> Variant:
	var w := GridWalker.new(Vector2i(0, 0))
	var east: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	w.walk(east)
	w.advance(100.0)
	if w.planning_origin() != Vector2i(1, 0):
		return "planning origin should be the cell being entered"
	var north: Array[Vector2i] = [Vector2i(1, 1)]
	w.walk(north)
	w.advance(50.0)  # completes the step into (1, 0)
	if w.cell != Vector2i(1, 0):
		return "current step was not completed: %s" % w.cell
	w.advance(150.0)
	return true if w.cell == Vector2i(1, 1) else "re-routed path not followed: %s" % w.cell


func test_sprite_direction_with_camera_yaw(_t) -> Variant:
	if PlayerAvatar.sprite_direction(6, 0.0) != 6 or PlayerAvatar.sprite_direction(6, 90.0) != 0:
		return "yaw mapping wrong"
	return true if PlayerAvatar.sprite_direction(1, -45.0) == 0 else "negative yaw wrong"
