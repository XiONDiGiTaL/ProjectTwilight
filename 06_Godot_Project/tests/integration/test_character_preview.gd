extends RefCounted
## The character-select preview must show the whole composed character: feet
## through the tallest hair pixel, in every direction and for every installed
## male/female hairstyle.

const PREVIEW := preload("res://scripts/ui/character_preview.gd")


func test_preview_frames_every_installed_hairstyle(t: SceneTree) -> Variant:
	var res = t.root.get_node_or_null("/root/RoResources")
	if res == null:
		return "SKIP no RoResources autoload"
	if not res.is_mounted and not res.mount():
		return "SKIP no Ragnarok client configured"
	var preview: CharacterPreview = PREVIEW.new()
	preview.position = Vector2(440, 150)
	preview.size = Vector2(300, 380)
	t.root.add_child(preview)
	await t.process_frame
	var checked := 0
	var failures: Array = []
	for male in [true, false]:
		for style in range(1, CharacterRules.HAIR_STYLES + 1):
			if not CharacterPreview.has_style(male, style):
				continue
			preview.set_look(male, style, 0, "초보자", 0)
			await t.process_frame
			if preview._sprite == null or preview._sprite.texture == null:
				continue
			if preview._sprite.body_spr == null or preview._sprite.head_spr == null:
				failures.append("%s style %d: body or head sprite did not load" % ["M" if male else "F", style])
				continue
			var bounds: Vector2 = preview._sprite.frame_bounds()
			if bounds.y <= 0.0:
				continue
			var aspect: float = preview._vp.size.x / maxf(preview._vp.size.y, 1.0)
			var frame_h: float = preview._cam.size
			var view_top: float = preview._cam.position.y + frame_h * 0.5
			var view_bottom: float = preview._cam.position.y - frame_h * 0.5
			if view_top + 0.001 < bounds.y or view_bottom - 0.001 > 0.0:
				failures.append("%s style %d: vertical frame does not contain the sprite" % ["M" if male else "F", style])
			elif frame_h * aspect + 0.001 < bounds.x:
				failures.append("%s style %d: frame width %.2f < sprite width %.2f" % ["M" if male else "F", style, frame_h * aspect, bounds.x])
			checked += 1
	preview.queue_free()
	await t.process_frame
	if checked == 0:
		return "SKIP no hairstyles were available from the client"
	if not failures.is_empty():
		return "%d/%d hairstyle frames clip: %s" % [failures.size(), checked, failures[0]]
	return true
