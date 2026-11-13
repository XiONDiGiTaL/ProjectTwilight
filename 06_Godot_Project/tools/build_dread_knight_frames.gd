extends SceneTree
## Exports the body-only Thanatos frames used by the Dread Knight sheet.
##
## The client's Thanatos SPR/ACT is read from the mounted Ragnarok data. Sword
## and effect layers (sprite index >= 54) are skipped, so the resulting frames
## can be drawn over the equipped weapon layer instead of the built-in sword.
##
## Run:
##   godot --headless --path 06_Godot_Project -s res://tools/build_dread_knight_frames.gd
##
## Output is local-only under Resources/DreadKnight/raw/composed and is never
## redistributed with the project.

const SOURCE := "data/sprite/몬스터/thanatos"
const OUT := "../Resources/DreadKnight/raw/composed"
const WEAPON_LAYER_START := 54
const CANVAS := 512
const FEET := Vector2i(256, 400)

## action index -> frame indices.  Groups are 8 directions each:
## idle 0-7, walk 8-15, attack 16-23, hurt 24-31, dead 32-39.
const FRAMES := {
	0: [0],                          # idle
	1: [0, 3, 6, 9, 12, 15],         # walk
	2: [0, 2, 4, 6],                  # attack (body-only wind-up; weapon layer swings)
	3: [0, 2, 4, 6],                 # hurt
	4: [12, 14, 16, 18, 20, 21],     # dead
}


func _initialize() -> void:
	var res: Node = root.get_node("RoResources")
	if not res.is_mounted and not res.mount():
		push_error("No Ragnarok client mounted: %s" % res.last_error)
		quit(1)
		return
	var spr := SprFile.decode(res.read(SOURCE + ".spr"))
	var act := ActFile.decode(res.read(SOURCE + ".act"))
	if spr == null or act == null:
		push_error("Could not decode %s" % SOURCE)
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var count := 0
	for base in FRAMES:
		for direction in 8:
			var action_index: int = int(base) * 8 + direction
			if action_index >= act.actions.size():
				continue
			for frame_index in FRAMES[base]:
				var image := _compose(spr, act, action_index, int(frame_index))
				if image == null:
					continue
				var name := "a%02d_f%02d.png" % [action_index, int(frame_index)]
				image.save_png(out_dir.path_join(name))
				count += 1
	print("exported %d Dread Knight frames to %s" % [count, out_dir])
	quit(0)


func _compose(spr: SprFile, act: ActFile, action_index: int, frame_index: int) -> Image:
	var action: Dictionary = act.actions[action_index]
	if frame_index < 0 or frame_index >= action.frames.size():
		return null
	var frame: Dictionary = action.frames[frame_index]
	var canvas := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var drew := false
	for layer in frame.layers:
		if layer.sprite < 0 or layer.sprite >= WEAPON_LAYER_START:
			continue
		var tint: Color = layer.color
		if tint.a <= 0.01:
			continue
		var src := spr.image_for(layer.sprite, layer.type)
		if src == null:
			continue
		var img := src.duplicate() as Image
		if not tint.is_equal_approx(Color.WHITE):
			_tint(img, tint)
		if layer.mirror:
			img.flip_x()
		var sc: Vector2 = layer.scale
		if not sc.is_equal_approx(Vector2.ONE) and sc.x > 0.01 and sc.y > 0.01:
			img.resize(maxi(1, roundi(img.get_width() * sc.x)), maxi(1, roundi(img.get_height() * sc.y)), Image.INTERPOLATE_NEAREST)
		var tl: Vector2i = FEET + layer.pos - Vector2i(img.get_width() / 2, img.get_height() / 2)
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), tl)
		drew = true
	return canvas if drew else null


static func _tint(img: Image, c: Color) -> void:
	var px := img.get_data()
	var r := c.r8
	var g := c.g8
	var b := c.b8
	var a := c.a8
	for i in range(0, px.size(), 4):
		px[i] = px[i] * r / 255
		px[i + 1] = px[i + 1] * g / 255
		px[i + 2] = px[i + 2] * b / 255
		px[i + 3] = px[i + 3] * a / 255
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)
