extends Control
## Title screen in the Twilight Glass style over a live map backdrop.

const CHARACTER_SELECT := "res://scenes/ui/character_select.tscn"
const SPRITE_VIEWER := "res://scenes/tools/sprite_viewer.tscn"
const MAP_VIEWER := "res://scenes/tools/map_viewer.tscn"
const SETTINGS_WINDOW := preload("res://scripts/ui/settings_window.gd")
const RESET_CONFIRMATION := "UI layout reset."
const RESET_CONFIRMATION_SECONDS := 2.5

var _status: Label
var _path_edit: LineEdit
var _play: Button
var _settings_window: GlassWindow
var _reset_status_token := 0


func _ready() -> void:
	var settings := get_node("/root/Settings")
	var res := get_node("/root/RoResources")
	if not res.is_mounted and settings.client_path() != "":
		res.mount(settings.client_path())
	if res.is_mounted:
		add_child(MenuBackdrop.new())
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.04, 0.08)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(440, 330)  # 4:3, matches Logo.png
	col.add_child(logo)

	var panel := GlassPanel.new()
	panel.padding = Vector4(22, 16, 22, 18)
	col.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	_play = Button.new()
	_play.text = "PLAY"
	_play.custom_minimum_size = Vector2(0, 42)
	UiTheme.style_button(_play, true, false, 16)
	_play.pressed.connect(func(): get_tree().change_scene_to_file(CHARACTER_SELECT))
	inner.add_child(_play)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	inner.add_child(tools)
	for spec in [["MAP VIEWER", MAP_VIEWER], ["SPRITE VIEWER", SPRITE_VIEWER]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b, false, false, 12)
		var target: String = spec[1]
		b.pressed.connect(func(): get_tree().change_scene_to_file(target))
		tools.add_child(b)
	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(settings_btn, false, false, 12)
	settings_btn.pressed.connect(_open_settings)
	tools.add_child(settings_btn)
	var coop := Button.new()
	coop.text = "PRIVATE CO-OP  ·  COMING SOON"
	coop.disabled = true
	UiTheme.style_button(coop, false, false, 12)
	inner.add_child(coop)

	inner.add_child(UiTheme.label("RAGNAROK DATA FOLDER  ·  CLIENT OR .GRF ARCHIVES  (read-only)", 10, UiTheme.ACCENT, 600, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "Client folder, or a folder containing data.grf"
	_path_edit.text = settings.client_path()
	_path_edit.custom_minimum_size = Vector2(380, 0)
	UiTheme.style_line_edit(_path_edit)
	_path_edit.add_theme_font_size_override("font_size", 12)
	row.add_child(_path_edit)
	var mount_btn := Button.new()
	mount_btn.text = "MOUNT"
	UiTheme.style_button(mount_btn, false, false, 12)
	mount_btn.pressed.connect(_on_mount)
	row.add_child(mount_btn)
	_status = UiTheme.label("", 11, UiTheme.TEXT_DIM, 400, 1)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 0)
	inner.add_child(_status)
	var quit := Button.new()
	quit.text = "QUIT"
	UiTheme.style_button(quit, false, true, 12)
	quit.pressed.connect(func(): get_tree().quit())
	inner.add_child(quit)
	_update_status()


func _update_status() -> void:
	var res := get_node("/root/RoResources")
	_play.disabled = not res.is_mounted
	if res.is_mounted:
		var n := 0
		for a in res.archives:
			n += a.entry_count()
		_status.text = "Client mounted  ·  %d archive(s)  ·  %s files" % [res.archives.size(), InventoryWindow._fmt_zeny(n)]
	else:
		_status.text = "Project Twilight ships no game data. Point it at your own Ragnarok client folder — or any folder of .grf archives — and press MOUNT."


func _open_settings() -> void:
	if _settings_window == null:
		_settings_window = SETTINGS_WINDOW.new()
		_settings_window.storage_key = SETTINGS_WINDOW.MENU_STORAGE_KEY
		add_child(_settings_window)
		_settings_window.reset_layout_requested.connect(_reset_ui_layout)
	_settings_window.toggle()


func _reset_ui_layout() -> void:
	_settings_window.center_position()
	_reset_status_token += 1
	var token := _reset_status_token
	_status.text = RESET_CONFIRMATION
	_status.modulate.a = 1.0
	await get_tree().create_timer(RESET_CONFIRMATION_SECONDS).timeout
	if token != _reset_status_token or _status.text != RESET_CONFIRMATION:
		return
	var out := create_tween()
	out.tween_property(_status, "modulate:a", 0.0, 0.2)
	await out.finished
	if token != _reset_status_token or _status.text != RESET_CONFIRMATION:
		_status.modulate.a = 1.0
		return
	_update_status()
	var back := create_tween()
	back.tween_property(_status, "modulate:a", 1.0, 0.25)


func _on_mount() -> void:
	var p := _path_edit.text.strip_edges()
	_status.text = "Indexing client archives…"
	await get_tree().process_frame
	var res := get_node("/root/RoResources")
	if res.mount(p):
		get_node("/root/Settings").set_client_path(p)
		get_tree().reload_current_scene()
	else:
		_status.text = res.last_error
		_play.disabled = true
