extends SceneTree
## Generates the Project Twilight class insignia collection.
##   godot --path 06_Godot_Project -s res://tools/insignia/generate_insignia.gd
## (Needs a rendering device, so do not pass --headless.)
##
## For every class in data/prerenealal classes.json: paint the emblem mask
## (EmblemPainter), render the shield (insignia_render.gdshader) with the
## rank's material, and save a 512x512 transparent PNG to
## res://assets/ui/class_emblems/<Rank>/<class>.png. Also writes a contact
## sheet (user://captures/insignia_sheet.png) and 64 px previews for review.

const SIZE := 512
const OUT_ROOT := "res://assets/ui/class_emblems/"
const RENDER_SHADER := preload("res://tools/insignia/insignia_render.gdshader")

## Rank material definitions (sRGB colours).
const MATERIALS := {
	"novice": {
		"body_dark": Color(0.3, 0.17, 0.08), "body_light": Color(0.66, 0.44, 0.24),
		"rim_dark": Color(0.22, 0.13, 0.06), "rim_light": Color(0.55, 0.38, 0.22),
		"emblem_dark": Color(0.4, 0.25, 0.12), "emblem_light": Color(0.75, 0.55, 0.32),
		"wood": true, "rivet": true, "studs": false,
	},
	"high_novice": {
		"body_dark": Color(0.3, 0.17, 0.08), "body_light": Color(0.66, 0.44, 0.24),
		"rim_dark": Color(0.22, 0.13, 0.06), "rim_light": Color(0.55, 0.38, 0.22),
		"emblem_dark": Color(0.4, 0.25, 0.12), "emblem_light": Color(0.75, 0.55, 0.32),
		"wood": true, "rivet": true, "blue_trim": true, "studs": true,
	},
	"first": {
		"body_dark": Color(0.33, 0.16, 0.07), "body_light": Color(0.78, 0.47, 0.27),
		"rim_dark": Color(0.3, 0.15, 0.06), "rim_light": Color(0.95, 0.66, 0.42),
		"emblem_dark": Color(0.55, 0.32, 0.15), "emblem_light": Color(1.0, 0.8, 0.55),
		"patina": true,
	},
	"high_first": {
		"body_dark": Color(0.33, 0.16, 0.07), "body_light": Color(0.78, 0.47, 0.27),
		"rim_dark": Color(0.3, 0.15, 0.06), "rim_light": Color(0.95, 0.66, 0.42),
		"emblem_dark": Color(0.55, 0.32, 0.15), "emblem_light": Color(1.0, 0.82, 0.6),
		"blue_trim": true, "engraved": true,
	},
	"second": {
		"body_dark": Color(0.3, 0.32, 0.37), "body_light": Color(0.72, 0.74, 0.79),
		"rim_dark": Color(0.3, 0.31, 0.35), "rim_light": Color(0.97, 0.97, 1.0),
		"emblem_dark": Color(0.34, 0.36, 0.42), "emblem_light": Color(0.98, 0.99, 1.0),
		"engraved": true,
	},
	"transcendent": {
		"body_dark": Color(0.42, 0.27, 0.04), "body_light": Color(0.95, 0.75, 0.3),
		"rim_dark": Color(0.4, 0.25, 0.03), "rim_light": Color(1.0, 0.9, 0.55),
		"emblem_dark": Color(0.6, 0.4, 0.08), "emblem_light": Color(1.0, 0.95, 0.7),
		"engraved": true, "ornate": true,
	},
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
	mask_vp.add_child(painter)

	var out_vp := SubViewport.new()
	out_vp.size = Vector2i(SIZE, SIZE)
	out_vp.transparent_bg = true
	out_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(out_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = RENDER_SHADER
	mat.set_shader_parameter("emblem_tex", mask_vp.get_texture())
	rect.material = mat
	out_vp.add_child(rect)

	var ids := classes.keys()
	var cols := 8
	var cell := 128
	var sheet := Image.create_empty(cols * cell, ceili(ids.size() / float(cols)) * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.16))
	var small_sheet := Image.create_empty(cols * 72, ceili(ids.size() / float(cols)) * 72, false, Image.FORMAT_RGBA8)
	small_sheet.fill(Color(0.12, 0.12, 0.16))
	var written := 0
	for i in ids.size():
		var id: String = ids[i]
		var c: Dictionary = classes[id]
		painter.class_id = id
		painter.queue_redraw()
		_apply_material(mat, MATERIALS[c.tier])
		for _f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := out_vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var path := OUT_ROOT + String(c.emblem)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var err := img.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("Failed to save %s" % path)
			continue
		written += 1
		var thumb := img.duplicate() as Image
		thumb.resize(cell - 8, cell - 8, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), Vector2i((i % cols) * cell + 4, (i / cols) * cell + 4))
		var tiny := img.duplicate() as Image
		tiny.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		small_sheet.blend_rect(tiny, Rect2i(Vector2i.ZERO, tiny.get_size()), Vector2i((i % cols) * 72 + 4, (i / cols) * 72 + 4))
	DirAccess.make_dir_recursive_absolute("user://captures")
	sheet.save_png("user://captures/insignia_sheet.png")
	small_sheet.save_png("user://captures/insignia_sheet_64.png")
	print("wrote %d insignia; sheet: %s" % [written, ProjectSettings.globalize_path("user://captures/insignia_sheet.png")])
	quit(0)


func _apply_material(mat: ShaderMaterial, m: Dictionary) -> void:
	for k in ["body_dark", "body_light", "rim_dark", "rim_light", "emblem_dark", "emblem_light"]:
		mat.set_shader_parameter(k, m[k])
	for k in ["wood", "patina", "engraved", "ornate", "blue_trim", "rivet"]:
		mat.set_shader_parameter(k, m.get(k, false))
	mat.set_shader_parameter("studs", m.get("studs", true))
