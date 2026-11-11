class_name Minimap
extends Control
## Corner map overview in the Twilight Glass style: the walkability silhouette
## of the GAT grid, warp portals, monsters, the local player and the CPU
## adventurers as blips. Presentation only: it reads simulation state and
## never writes it.

const MAX_TEX := 192
const WATER := Color(0.07, 0.16, 0.3, 0.95)
const BLOCKED := Color(0.03, 0.06, 0.1, 0.85)
const WALKABLE := Color(0.15, 0.26, 0.38, 0.95)

var gat: GatFile
var sim: FieldSimulation
var player_id := 0

var _tex: ImageTexture
var _tex_size := Vector2i.ZERO
var _scale := 1.0
var _origin := Vector2.ZERO


## Walkability silhouette of a GAT grid, downsampled to at most MAX_TEX pixels
## on the longer side. Static so it can be tested without a scene.
static func build_image(g: GatFile) -> Image:
	if g == null or g.width <= 0 or g.height <= 0:
		return null
	var step := maxi(1, int(ceil(maxf(g.width, g.height) / float(MAX_TEX))))
	var w := maxi(1, g.width / step)
	var h := maxi(1, g.height / step)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var cx := mini(g.width - 1, x * step + step / 2)
			var cy := mini(g.height - 1, y * step + step / 2)
			var col := BLOCKED
			if g.is_walkable(cx, cy):
				col = WALKABLE
			elif g.cell_type(cx, cy) == GatFile.CellType.WATER:
				col = WATER
			img.set_pixel(x, y, col)
	return img


func setup(g: GatFile, p_sim: FieldSimulation, p_player_id: int) -> void:
	gat = g
	sim = p_sim
	player_id = p_player_id
	var img := build_image(g)
	if img == null:
		return
	_tex = ImageTexture.create_from_image(img)
	_tex_size = img.get_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_fit)
	_fit()
	queue_redraw()


func _fit() -> void:
	if _tex_size.x <= 0 or _tex_size.y <= 0:
		return
	_scale = minf(size.x / _tex_size.x, size.y / _tex_size.y)
	_origin = (size - Vector2(_tex_size) * _scale) / 2.0


## Cell -> pixel inside this control.
func _cell_px(c: Vector2i, w: int, h: int) -> Vector2:
	var px := _origin + Vector2(
		(float(c.x) + 0.5) / float(maxi(1, w)) * _tex_size.x,
		(float(c.y) + 0.5) / float(maxi(1, h)) * _tex_size.y) * _scale
	return px


func _process(_delta: float) -> void:
	if sim != null:
		queue_redraw()


func _draw() -> void:
	if _tex == null or sim == null or gat == null:
		return
	draw_texture_rect(_tex, Rect2(_origin, Vector2(_tex_size) * _scale), false)
	var w := gat.width
	var h := gat.height
	# Portals: cyan rings, the classic "way out" marker.
	for wp in sim.warps:
		var p := _cell_px(wp.cell, w, h)
		draw_circle(p, 3.2, Color(0.32, 0.82, 1.0, 0.95))
		draw_arc(p, 5.4, 0.0, TAU, 16, Color(0.62, 0.94, 1.0, 0.55), 1.0)
	# Monsters: small embers.
	for id in sim.units:
		var u: SimUnit = sim.units[id]
		if u.is_player() or u.dead:
			continue
		draw_circle(_cell_px(u.walker.cell, w, h), 1.6, Color(1.0, 0.42, 0.38, 0.65))
	# CPU adventurers: role-coloured blips with a soft halo while they live.
	for id in sim.units:
		var u: SimUnit = sim.units[id]
		if not u.is_bot:
			continue
		var p := _cell_px(u.walker.cell, w, h)
		var col: Color = BotBrain.ROLE_COLORS.get(u.bot_role, Color(0.8, 0.9, 1.0))
		if u.dead:
			draw_circle(p, 2.0, Color(0.55, 0.6, 0.7, 0.5))
			continue
		draw_circle(p, 4.4, Color(col, 0.18))
		draw_circle(p, 2.5, col)
	# The local player on top: white core, accent ring.
	var me: SimUnit = sim.units.get(player_id)
	if me != null:
		var p := _cell_px(me.walker.cell, w, h)
		draw_circle(p, 5.2, Color(0.36, 0.78, 1.0, 0.25))
		draw_circle(p, 2.8, Color(1.0, 1.0, 1.0, 0.98))
		draw_arc(p, 4.6, 0.0, TAU, 18, Color(0.62, 0.88, 1.0, 0.8), 1.2)
