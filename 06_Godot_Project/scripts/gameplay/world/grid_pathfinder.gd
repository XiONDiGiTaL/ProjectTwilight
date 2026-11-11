class_name GridPathfinder
extends RefCounted
## A* over a GAT walkability grid, 8-directional like the classic client.
## Diagonal steps are only allowed when both adjacent orthogonal cells are
## walkable (no corner cutting). Costs: 10 straight, 14 diagonal.
## Pure gameplay logic: shared by offline play, the co-op host and servers.

const MAX_PATH_LENGTH := 64  # classic client limit on click-to-walk distance (Medium confidence)

var _astar := AStarGrid2D.new()
var width := 0
var height := 0


func _init(gat: GatFile = null) -> void:
	if gat:
		setup(gat)


func setup(gat: GatFile) -> void:
	width = gat.width
	height = gat.height
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in height:
		for x in width:
			if not gat.is_walkable(x, y):
				_astar.set_point_solid(Vector2i(x, y), true)


func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


## Returns the cells to step through (excluding `from`), or [] if unreachable,
## blocked, or longer than max_length steps.
func find_path(from: Vector2i, to: Vector2i, max_length: int = MAX_PATH_LENGTH) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to or not is_walkable(from) or not is_walkable(to):
		return out
	var pts := _astar.get_id_path(from, to)
	if pts.size() < 2 or pts.size() - 1 > max_length:
		return out
	for i in range(1, pts.size()):
		out.append(pts[i])
	return out


## Nearest walkable cell to `cell` within `radius` (Chebyshev), or (-1, -1).
func nearest_walkable(cell: Vector2i, radius: int = 8) -> Vector2i:
	if is_walkable(cell):
		return cell
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_walkable(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return Vector2i(-1, -1)
