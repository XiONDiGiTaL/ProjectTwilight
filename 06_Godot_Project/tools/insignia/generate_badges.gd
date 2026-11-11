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

## Class family colours.
const FAMILY := {
	"novice": Color(0.36, 0.44, 0.52), "sword": Color(0.78, 0.16, 0.2), "mage": Color(0.38, 0.27, 0.85),
	"archer": Color(0.2, 0.62, 0.27), "acolyte": Color(0.1, 0.58, 0.64), "merchant": Color(0.9, 0.47, 0.1),
	"thief": Color(0.34, 0.17, 0.46), "taekwon": Color(0.92, 0.62, 0.12), "ninja": Color(0.52, 0.1, 0.16),
	"gunslinger": Color(0.5, 0.33, 0.16), "super_novice": Color(0.88, 0.36, 0.62), "soul_linker": Color(0.26, 0.38, 0.88),
}
const CLASS_FAMILY := {
	"novice": "novice", "high_novice": "novice", "super_novice": "super_novice",
	"swordman": "sword", "knight": "sword", "crusader": "sword", "high_swordman": "sword", "lord_knight": "sword", "paladin": "sword",
	"mage": "mage", "wizard": "mage", "sage": "mage", "high_mage": "mage", "high_wizard": "mage", "professor": "mage",
	"archer": "archer", "hunter": "archer", "bard": "archer", "dancer": "archer", "high_archer": "archer",
	"sniper": "archer", "clown": "archer", "gypsy": "archer",
	"acolyte": "acolyte", "priest": "acolyte", "monk": "acolyte", "high_acolyte": "acolyte", "high_priest": "acolyte", "champion": "acolyte",
	"merchant": "merchant", "blacksmith": "merchant", "alchemist": "merchant", "high_merchant": "merchant", "whitesmith": "merchant", "creator": "merchant",
	"thief": "thief", "assassin": "thief", "rogue": "thief", "high_thief": "thief", "assassin_cross": "thief", "stalker": "thief",
	"taekwon_kid": "taekwon", "star_gladiator": "taekwon", "ninja": "ninja", "gunslinger": "gunslinger", "soul_linker": "soul_linker",
}
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
