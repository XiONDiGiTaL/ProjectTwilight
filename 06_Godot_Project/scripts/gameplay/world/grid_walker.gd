class_name GridWalker
extends RefCounted
## Cell-based movement state for one entity (player, monster, NPC).
##
## Pure logic, advanced with explicit time steps so it is deterministic and can
## run on a co-op host or server. Rendering reads `position()` and `direction`.
##
## Classic behaviour: walk_speed is milliseconds per straight cell (default 150,
## High confidence for Novice base speed); diagonal steps take 1.4x as long.
## Directions follow the client convention:
##   0 S, 1 SW, 2 W, 3 NW, 4 N, 5 NE, 6 E, 7 SE   (y grows northward)

signal arrived(cell: Vector2i)
signal stepped(cell: Vector2i)

const DEFAULT_WALK_SPEED := 150.0
const DIAGONAL_FACTOR := 1.4
const DIR_VECTORS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1),
]

var cell := Vector2i.ZERO
var direction := 0
var walk_speed := DEFAULT_WALK_SPEED
var path: Array[Vector2i] = []
var _progress := 0.0  # milliseconds into the current step


func _init(start: Vector2i = Vector2i.ZERO) -> void:
	cell = start


func is_moving() -> bool:
	return not path.is_empty()


## Cell new paths should be planned from: the cell being stepped into while
## moving (the current step always completes), otherwise the current cell.
func planning_origin() -> Vector2i:
	return path[0] if not path.is_empty() else cell


## Starts walking `new_path`, which must have been planned from planning_origin().
func walk(new_path: Array[Vector2i]) -> void:
	if not path.is_empty():
		var current := path[0]
		path = [current]
		path.append_array(new_path)
	else:
		path = new_path.duplicate()
		_progress = 0.0
	if not path.is_empty():
		direction = direction_to(cell, path[0])


func stop() -> void:
	path.clear()
	_progress = 0.0


## Advances by `ms` milliseconds; returns true while still moving.
func advance(ms: float) -> bool:
	while not path.is_empty() and ms > 0.0:
		var next := path[0]
		var cost := step_duration(cell, next)
		var need := cost - _progress
		if ms < need:
			_progress += ms
			return true
		ms -= need
		cell = next
		path.remove_at(0)
		_progress = 0.0
		stepped.emit(cell)
		if path.is_empty():
			arrived.emit(cell)
		else:
			direction = direction_to(cell, path[0])
	return not path.is_empty()


## Continuous position in cell units (cell centre = integer + 0.5).
func position() -> Vector2:
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	if path.is_empty():
		return p
	var t := _progress / step_duration(cell, path[0])
	return p.lerp(Vector2(path[0]) + Vector2(0.5, 0.5), clampf(t, 0.0, 1.0))


func step_duration(a: Vector2i, b: Vector2i) -> float:
	var diagonal := a.x != b.x and a.y != b.y
	return walk_speed * (DIAGONAL_FACTOR if diagonal else 1.0)


static func direction_to(a: Vector2i, b: Vector2i) -> int:
	var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var i := DIR_VECTORS.find(d)
	return i if i >= 0 else 0
