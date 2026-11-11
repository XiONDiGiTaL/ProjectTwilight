extends SceneTree
## Generates SAO-style square class badges for every class.
##   godot --path 06_Godot_Project -s res://tools/insignia/generate_badges.gd
## (Needs a rendering device, so do not pass --headless.)
## Output: res://assets/ui/class_badges/<class>.png (256 px) and a review sheet
## user://captures/badge_sheet.png. Glyphs come from EmblemPainter.

const SIZE := 512
const OUT_SIZE := 256
const OUT_DIR := "res://assets/ui/class_badges/"
const SHADER := preload("res://tools/insignia/badge_render.gdshader")

## Family colours live in ClassInsignia (shared with the in-game auras).
const FAMILY := ClassInsignia.FAMILY
const CLASS_FAMILY := ClassInsignia.CLASS_FAMILY

## Tier frames: [colour, double frame, star].
const TIER_FRAME := {
	"novice": [Color(0.85, 0.9, 0.95, 0.75), false, false],
	"first": [Color(1, 1, 1, 0.95), false, false],
	"second": [Color(0.88, 0.92, 1.0, 1.0), true, false],
	"high_novice": [Color(0.62, 0.9, 1.0, 1.0), false, true],
	"high_first": [Color(0.62, 0.9, 1.0, 1.0), true, true],
	"transcendent": [Color(1.0, 0.84, 0.4, 1.0), true, true],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var classes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prerenewal/classes.json"))
	classes.erase("_doc")
	var mask_vp := SubViewport.new()
	mask_vp.size = Vector2i(SIZE, SIZE)
	mask_vp.transparent_bg = true
	mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mask_vp)
	var painter := EmblemPainter.new()
	painter.badge_mode = true
	mask_vp.add_child(painter)
	var out_vp := SubViewport.new()
	out_vp.size = Vector2i(SIZE, SIZE)
	out_vp.transparent_bg = true
	out_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(out_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("emblem_tex", mask_vp.get_texture())
	rect.material = mat
	out_vp.add_child(rect)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ids := classes.keys()
	var cols := 10
	var sheet := Image.create_empty(cols * 80, ceili(ids.size() / float(cols)) * 80, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.12, 0.18))
	for i in ids.size():
		var id: String = ids[i]
		painter.class_id = id
		painter.queue_redraw()
		mat.set_shader_parameter("base_color", FAMILY[CLASS_FAMILY.get(id, "novice")])
		var frame: Array = TIER_FRAME.get(String(classes[id].tier), TIER_FRAME.first)
		mat.set_shader_parameter("frame_color", frame[0])
		mat.set_shader_parameter("double_frame", frame[1])
		mat.set_shader_parameter("star", frame[2])
		for _f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := out_vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT_DIR + id + ".png"))
		var thumb := img.duplicate() as Image
		thumb.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), Vector2i((i % cols) * 80 + 8, (i / cols) * 80 + 8))
	DirAccess.make_dir_recursive_absolute("user://captures")
	sheet.save_png("user://captures/badge_sheet.png")
	print("wrote %d badges" % ids.size())
	quit(0)
