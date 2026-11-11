extends Control
## Title screen. Built in code so it stays readable in diffs.

const SPRITE_VIEWER := "res://scenes/tools/sprite_viewer.tscn"
const MAP_VIEWER := "res://scenes/tools/map_viewer.tscn"
const FIELD_SCENE := "res://scenes/game/field.tscn"

var _status: Label
var _path_edit: LineEdit


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(520, 0)
	center.add_child(col)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(520, 390)  # 4:3, matches Logo.png
	col.add_child(logo)

	var row := HBoxContainer.new()
	col.add_child(row)
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "Path to your Ragnarok client folder (read-only)"
	_path_edit.text = Settings.client_path()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_path_edit)
	var mount_btn := Button.new()
	mount_btn.text = "Mount"
	mount_btn.pressed.connect(_on_mount)
	row.add_child(mount_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	_add_button(col, "Explore (offline prototype)", func(): get_tree().change_scene_to_file(FIELD_SCENE))
	_add_button(col, "Private Co-op (planned)", Callable(), true)
	_add_button(col, "Map Viewer", func(): get_tree().change_scene_to_file(MAP_VIEWER))
	_add_button(col, "Sprite Viewer", func(): get_tree().change_scene_to_file(SPRITE_VIEWER))
	_add_button(col, "Quit", func(): get_tree().quit())

	if _path_edit.text != "":
		_on_mount.call_deferred()
	else:
		_status.text = "Project Twilight ships no game data. Point it at your own client folder."


func _add_button(parent: Control, text: String, cb: Callable, disabled_if_empty := false) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	if cb.is_valid():
		b.pressed.connect(cb)
	else:
		b.disabled = disabled_if_empty
	parent.add_child(b)


func _on_mount() -> void:
	var p := _path_edit.text.strip_edges()
	_status.text = "Indexing client archives…"
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	if RoResources.mount(p):
		Settings.set_client_path(p)
		var n := 0
		for a in RoResources.archives:
			n += a.entry_count()
		_status.text = "Mounted %d archive(s), %d files in %d ms." % [RoResources.archives.size(), n, Time.get_ticks_msec() - t0]
	else:
		_status.text = RoResources.last_error
