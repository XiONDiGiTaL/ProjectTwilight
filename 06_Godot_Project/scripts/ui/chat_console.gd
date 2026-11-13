class_name ChatConsole
extends Control
## Bottom-left Twilight Glass chat dock.
##
## It keeps the classic RO placement and the Enter-to-talk flow, then adds a
## compact message log, channel tabs, private-message tabs with unread glow,
## a community roster and a small chat-options drawer at the end of the tabs.
## The window automatically fades to a quiet translucent strip when idle.

signal submitted(text: String)
signal dm_reply_requested(to: String, text: String)
signal settings_requested
signal portrait_capture_requested

const MAX_HISTORY := 20
const MAX_MESSAGES := 140
const WAKE_SECONDS := 7.0
const IDLE_ALPHA := 0.36
const FADE_IN_SPEED := 8.0
const FADE_OUT_SPEED := 1.6
const TAB_HEIGHT := 23.0
## New DM tabs built per refresh; bursts stage over frames instead of forcing
## one large tab-row relayout.
const TAB_BUILD_BUDGET := 3
const CHANNEL_COLORS := {
	"say": UiTheme.TEXT,
	"system": UiTheme.ACCENT,
	"guild": UiTheme.EXP_JOB,
	"combat": UiTheme.HP_MID,
	"dm": UiTheme.ACCENT_2,
}

var input: LineEdit
var tabs: HBoxContainer
var log_scroll: ScrollContainer
var log_box: VBoxContainer
var community_scroll: ScrollContainer
var community_box: VBoxContainer
var dm_popup: ChatDmPopup
var settings_panel: GlassPanel

var _panel: GlassPanel
var _tabs_scroll: ScrollContainer
var _dm_tabs: HBoxContainer
var _tabs_buttons: Dictionary = {}
var _messages: Array = []
var _threads: Dictionary = {}       # display name -> {messages, unread, contact}
var _contacts: Array = []
var _friends: Array = []
var _active := "all"
var _history: Array = []
var _history_index := 0
var _hint: Label
var _input_row: HBoxContainer
var _timestamps := true
var _dm_popups := true
var _fade_when_idle := true
var _settings_open := false
var _wake := WAKE_SECONDS
var _last_unread := -1
var _self_portrait := ""
var _log_dirty := false
var _next_message_id := 1
var _shown_rows: Dictionary = {}   # message id -> existing row
var _shown_view := ""
var _empty_log: Label
var _tabs_dirty := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_load_options()
	_build_panel()
	_load_friends()
	_build_popup()
	_build_settings_panel()
	_refresh_tabs()
	_refresh_log()
	modulate.a = 1.0


func _build_panel() -> void:
	_panel = GlassPanel.new()
	_panel.chamfer = 8.0
	_panel.sweep = false
	_panel.padding = Vector4(9, 6, 9, 7)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	_tabs_scroll = ScrollContainer.new()
	_tabs_scroll.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	_tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(_tabs_scroll)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	_tabs_scroll.add_child(tabs)

	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	log_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(log_scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 3)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_scroll.add_child(log_box)

	community_scroll = ScrollContainer.new()
	community_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	community_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	community_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	community_scroll.visible = false
	community_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(community_scroll)
	community_box = VBoxContainer.new()
	community_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	community_box.add_theme_constant_override("separation", 4)
	community_scroll.add_child(community_box)

	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 7)
	_input_row.visible = false
	col.add_child(_input_row)
	_hint = UiTheme.label("SAY", 9, UiTheme.ACCENT, 700, 2)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_input_row.add_child(_hint)
	input = LineEdit.new()
	input.placeholder_text = "Say something   ·   /w <name> <message>   ·   /g <message>   ·   @help"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(220, 26)
	UiTheme.style_line_edit(input)
	input.add_theme_font_size_override("font_size", 12)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input)
	_input_row.add_child(input)


func open(prefill := "") -> void:
	_input_row.visible = true
	_hint.text = "COMMAND" if prefill.begins_with("@") else "SAY"
	input.text = prefill
	input.grab_focus()
	input.caret_column = input.text.length()
	_wake = WAKE_SECONDS
	_panel.set_glow(0.2)


func close() -> void:
	_input_row.visible = false
	input.release_focus()
	_hint.text = "SAY"
	_wake = WAKE_SECONDS


func is_open() -> bool:
	# The field scene uses this to decide whether Enter should open the chat
	# line or leave a focused DM reply alone. A focused DM card is also text
	# input, so it counts as open.
	return (_input_row != null and _input_row.visible) \
		or (dm_popup != null and dm_popup.is_open() and dm_popup.reply_has_focus())


func _on_submit(text: String) -> void:
	var clean := text.strip_edges()
	if clean != "":
		_history.append(clean)
		if _history.size() > MAX_HISTORY:
			_history.remove_at(0)
	_history_index = _history.size()
	submitted.emit(clean)
	close()


func _on_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_ESCAPE:
			close()
			accept_event()
		KEY_UP:
			_recall(-1)
			accept_event()
		KEY_DOWN:
			_recall(1)
			accept_event()


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + step, 0, _history.size())
	input.text = "" if _history_index == _history.size() else String(_history[_history_index])
	input.caret_column = input.text.length()


## Adds a public/say line from a remote player or from the local player.
func add_say(from: String, text: String, own := false) -> void:
	add_message("say", from, text, own)


## Adds an ordinary system notice mirroring the HUD toast into the SYSTEM tab.
func add_system(text: String) -> void:
	add_message("system", "SYSTEM", text)


func add_guild(from: String, text: String) -> void:
	add_message("guild", from, text)


func add_combat(text: String) -> void:
	add_message("combat", "COMBAT", text)


func add_message(channel: String, from: String, text: String, own := false) -> void:
	var clean := text.strip_edges()
	if clean == "":
		return
	_messages.append(_new_message(channel, from, clean, own))
	while _messages.size() > MAX_MESSAGES:
		var dropped: Dictionary = _messages[0]
		if _active == String(dropped.get("channel", "")):
			_log_dirty = true
		_messages.remove_at(0)
	_wake = WAKE_SECONDS
	if _active == channel or _active == "all":
		# Several events can arrive in one frame. Rebuild the visible log once
		# in _process instead of once per message (and never rebuild tabs for
		# ordinary channel traffic).
		_log_dirty = true


## Called by FieldScene when a private message arrives from the session.
func receive_dm(from: String, text: String) -> void:
	var clean := text.strip_edges()
	if clean == "" or from == "":
		return
	var thread := _ensure_thread(from)
	thread.messages.append(_new_message("dm", from, clean, false))
	var same_thread := _active == "dm:" + from
	if not same_thread:
		thread.unread = int(thread.unread) + 1
		_tabs_dirty = true
	_wake = WAKE_SECONDS
	if same_thread:
		_log_dirty = true
		if dm_popup != null and dm_popup.is_open():
			_show_popup(from, true, false)
	elif _dm_popups:
		# The card is a notification, not an acknowledgement: keep the tab
		# glowing until the player actually selects the conversation. The
		# unread tab was already refreshed above.
		_show_popup(from, false, false)
	_panel.set_glow(0.35 if _unread_total() > 0 else 0.0)


## Adds an outgoing private line locally, before NetSession sends it.
func record_outgoing_dm(to: String, text: String) -> void:
	var clean := text.strip_edges()
	if to == "" or clean == "":
		return
	var is_new_thread := not _threads.has(to)
	var thread := _ensure_thread(to)
	thread.messages.append(_new_message("dm", "You", clean, true))
	var was_unread := int(thread.unread) > 0
	thread.unread = 0
	_wake = WAKE_SECONDS
	if is_new_thread or was_unread:
		_tabs_dirty = true
	if _active == "dm:" + to:
		_log_dirty = true
	if dm_popup != null and dm_popup.is_open():
		_show_popup(to)


func send_dm(to: String, text: String) -> void:
	record_outgoing_dm(to, text)
	dm_reply_requested.emit(to, text)


## Opens an existing thread, or creates one for a roster contact.
func open_dm(name: String) -> void:
	_ensure_thread(name)
	_select_tab("dm:" + name)


func set_contacts(contacts: Array) -> void:
	var by_name := {}
	for raw in contacts:
		if not (raw is Dictionary):
			continue
		var c := _normalize_contact(raw)
		var n := String(c.get("name", ""))
		if n != "":
			by_name[n] = c
	for friend in _friends:
		var n := String(friend)
		if n != "" and not by_name.has(n):
			by_name[n] = {"name": n, "online": false, "friend": true}
	_contacts = by_name.values()
	_contacts.sort_custom(func(a, b):
		var ao := bool(a.get("online", false))
		var bo := bool(b.get("online", false))
		if ao != bo:
			return ao
		return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower())
	for name in _threads:
		if by_name.has(name):
			_threads[name]["contact"] = by_name[name]
	if _active == "community":
		_render_community()


func set_my_portrait(path: String) -> void:
	_self_portrait = path
	var s := _settings()
	if s:
		s.set_value("social", "portrait_path", path)
	for c in _contacts:
		if bool(c.get("self", false)):
			c["portrait_path"] = path
	if _active == "community":
		_render_community()
	if dm_popup != null and dm_popup.is_open():
		_show_popup(String(dm_popup.get_meta("thread_name", "")), false, false)


func my_portrait() -> String:
	return _self_portrait


func is_friend(name: String) -> bool:
	return _friends.has(name)


func add_friend(name: String) -> void:
	var clean := name.strip_edges()
	if clean == "" or _friends.has(clean):
		return
	_friends.append(clean)
	_save_friends()
	_wake = WAKE_SECONDS
	if _active == "community":
		_render_community()
	if dm_popup != null and dm_popup.is_open():
		dm_popup.set_friend(true)
	add_message("system", "SYSTEM", "%s added to your community." % clean)


func _normalize_contact(raw: Dictionary) -> Dictionary:
	var c := raw.duplicate(true)
	c["name"] = String(c.get("name", ""))
	c["job"] = String(c.get("job", "novice"))
	c["level"] = int(c.get("level", 0))
	c["job_level"] = int(c.get("job_level", 0))
	c["map"] = String(c.get("map", ""))
	c["online"] = bool(c.get("online", true))
	c["male"] = bool(c.get("male", true))
	c["hair_style"] = int(c.get("hair_style", 0))
	c["hair_color"] = int(c.get("hair_color", 0))
	c["cloth_color"] = int(c.get("cloth_color", 0))
	c["sprite"] = String(c.get("sprite", c.get("job_sprite", "초보자")))
	c["self"] = bool(c.get("self", false))
	c["friend"] = _friends.has(String(c.get("name", "")))
	if bool(c.self) and _self_portrait != "":
		c["portrait_path"] = _self_portrait
	return c


func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _load_friends() -> void:
	_friends = []
	var s := _settings()
	var stored: Variant = s.get_value("social", "friends", []) if s else []
	if stored is Array or stored is PackedStringArray:
		for n in stored:
			var clean := String(n).strip_edges()
			if clean != "" and not _friends.has(clean):
				_friends.append(clean)
	var path := String(s.get_value("social", "portrait_path", "") if s else "")
	if path != "" and FileAccess.file_exists(path):
		_self_portrait = path


func _save_friends() -> void:
	var s := _settings()
	if s:
		s.set_value("social", "friends", _friends)


func _load_options() -> void:
	var s := _settings()
	_fade_when_idle = bool(s.get_value("chat", "fade_when_idle", true)) if s else true
	_dm_popups = bool(s.get_value("chat", "dm_popups", true)) if s else true
	_timestamps = bool(s.get_value("chat", "timestamps", true)) if s else true


func _set_option(key: String, value: bool) -> void:
	match key:
		"fade_when_idle":
			_fade_when_idle = value
		"dm_popups":
			_dm_popups = value
		"timestamps":
			_timestamps = value
	var s := _settings()
	if s:
		s.set_value("chat", key, value)
	_wake = WAKE_SECONDS
	_refresh_log()


func _build_popup() -> void:
	dm_popup = ChatDmPopup.new()
	add_child(dm_popup)
	dm_popup.replied.connect(func(to, text): send_dm(to, text))
	dm_popup.friend_requested.connect(add_friend)
	dm_popup.dismissed.connect(func(): _wake = WAKE_SECONDS)


func _build_settings_panel() -> void:
	settings_panel = GlassPanel.new()
	settings_panel.chamfer = 10.0
	settings_panel.padding = Vector4(12, 9, 12, 10)
	settings_panel.custom_minimum_size = Vector2(320, 0)
	settings_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	settings_panel.offset_left = 4
	settings_panel.offset_right = 324
	settings_panel.offset_top = -232
	settings_panel.offset_bottom = -4
	settings_panel.visible = false
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	settings_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := UiTheme.label("CHAT OPTIONS", 10, UiTheme.ACCENT, 700, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close chat options"
	UiTheme.style_hud_button(close, 9)
	close.pressed.connect(func(): _toggle_settings(false))
	head.add_child(close)
	_toggle_option(col, "fade_when_idle", "FADE WHEN IDLE", _fade_when_idle)
	_toggle_option(col, "dm_popups", "DM POPUPS", _dm_popups)
	_toggle_option(col, "timestamps", "TIMESTAMPS", _timestamps)
	var capture := Button.new()
	capture.text = "CAPTURE MY PORTRAIT"
	capture.tooltip_text = "Save a close-up of your character as your community avatar"
	UiTheme.style_hud_button(capture, 9)
	capture.pressed.connect(func(): portrait_capture_requested.emit())
	col.add_child(capture)
	var all := Button.new()
	all.text = "ALL SETTINGS"
	all.tooltip_text = "Open the full in-game Settings overlay"
	UiTheme.style_hud_button(all, 9)
	all.pressed.connect(func(): settings_requested.emit())
	col.add_child(all)


func _toggle_option(parent: VBoxContainer, key: String, text: String, value: bool) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = value
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_hud_button(b, 9)
	b.add_theme_color_override("font_color", UiTheme.ACCENT if value else UiTheme.TEXT_DIM)
	b.pressed.connect(func():
		_set_option(key, b.button_pressed)
		b.add_theme_color_override("font_color", UiTheme.ACCENT if b.button_pressed else UiTheme.TEXT_DIM))
	parent.add_child(b)


func _toggle_settings(show: Variant = null) -> void:
	_settings_open = (not _settings_open) if show == null else bool(show)
	settings_panel.visible = _settings_open
	if _settings_open:
		settings_panel.move_to_front()
		settings_panel.modulate.a = 0.0
		var target := settings_panel.position
		settings_panel.position = target + Vector2(0, 16)
		var tw := create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(settings_panel, "position", target, 0.18)
		tw.tween_property(settings_panel, "modulate:a", 1.0, 0.16)
	_wake = WAKE_SECONDS
	_refresh_tabs()


func _select_tab(id: String) -> void:
	if id == "settings":
		_toggle_settings()
		return
	_active = id
	_wake = WAKE_SECONDS
	if id.begins_with("dm:"):
		var name := id.substr(3)
		var thread := _ensure_thread(name)
		thread.unread = 0
		_panel.set_glow(0.0)
		if dm_popup != null:
			_show_popup(name)
			dm_popup.focus_reply()
	else:
		_refresh_tabs()
	if id == "community":
		log_scroll.visible = false
		community_scroll.visible = true
		_input_row.visible = false
		_render_community()
	else:
		community_scroll.visible = false
		log_scroll.visible = true
		_refresh_log()


func _refresh_tabs() -> void:
	if tabs == null:
		return
	_tabs_dirty = false
	var wanted := {}
	var index := 0
	for spec in [
		["all", "ALL", false, false],
		["system", "SYSTEM", false, false],
		["guild", "GUILD", false, false],
		["combat", "COMBAT", false, false],
	]:
		var id := String(spec[0])
		wanted[id] = true
		var button := _ensure_tab(id, String(spec[1]), bool(spec[2]), bool(spec[3]), tabs)
		if button.get_index() != index:
			tabs.move_child(button, index)
		index += 1

	# DM tabs live in their own HBox. A new conversation only appends to that
	# group, instead of moving every new button past the fixed tail tabs.
	if _dm_tabs == null:
		_dm_tabs = HBoxContainer.new()
		_dm_tabs.add_theme_constant_override("separation", 3)
		_dm_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		tabs.add_child(_dm_tabs)
	if _dm_tabs.get_index() != index:
		tabs.move_child(_dm_tabs, index)
	index += 1
	var dm_index := 0
	var built := 0
	var pending := false
	for name in _threads.keys():
		var thread: Dictionary = _threads[name]
		var unread := int(thread.get("unread", 0))
		var dm_id := "dm:" + String(name)
		wanted[dm_id] = true
		var existing: Button = _tabs_buttons.get(dm_id)
		if existing == null:
			if built >= TAB_BUILD_BUDGET:
				pending = true
				continue
			built += 1
		var button := _ensure_tab(dm_id, ("● " if unread > 0 else "") + String(name).left(14), unread > 0, false, _dm_tabs)
		if button.get_index() != dm_index:
			_dm_tabs.move_child(button, dm_index)
		dm_index += 1
	_dm_tabs.visible = dm_index > 0
	if pending:
		_tabs_dirty = true

	for spec in [
		["community", "COMMUNITY", false, false],
		["settings", "⚙", false, true],
	]:
		var id := String(spec[0])
		wanted[id] = true
		var button := _ensure_tab(id, String(spec[1]), bool(spec[2]), bool(spec[3]), tabs)
		if button.get_index() != index:
			tabs.move_child(button, index)
		index += 1

	for id in _tabs_buttons.keys():
		if not wanted.has(id):
			var old: Button = _tabs_buttons[id]
			_tabs_buttons.erase(id)
			var parent := old.get_parent()
			if parent != null:
				parent.remove_child(old)
			old.queue_free()


func _ensure_tab(id: String, label: String, unread: bool, settings: bool, parent: Container) -> Button:
	var button: Button = _tabs_buttons.get(id)
	if button == null:
		button = _new_tab(id)
		# Style and label the button while it is detached. Applying theme
		# overrides after insertion forces the whole tab row to re-sort once
		# per new DM.
		_update_tab(button, id, label, unread, settings)
		_tabs_buttons[id] = button
		parent.add_child(button)
	else:
		_update_tab(button, id, label, unread, settings)
	return button


func _new_tab(id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_hud_button(b, 9)
	b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.set_meta("tab_active", false)
	b.set_meta("tab_unread", false)
	b.pressed.connect(func(): _select_tab(id))
	return b


func _update_tab(b: Button, id: String, label: String, unread: bool, settings: bool) -> void:
	if b.text != label:
		b.text = label
	var tip := "Chat options" if settings else label
	if b.tooltip_text != tip:
		b.tooltip_text = tip
	var active := _active == id and not settings
	var old_active := bool(b.get_meta("tab_active", false))
	var old_unread := bool(b.get_meta("tab_unread", false))
	if active != old_active or unread != old_unread:
		b.add_theme_color_override("font_color", UiTheme.ACCENT if active else (UiTheme.HP_MID if unread else UiTheme.TEXT_DIM))
	if unread != old_unread:
		if unread:
			b.add_theme_color_override("font_shadow_color", Color(UiTheme.HP_MID, 0.9))
			b.add_theme_constant_override("shadow_offset_x", 0)
			b.add_theme_constant_override("shadow_offset_y", 0)
			b.add_theme_constant_override("shadow_outline_size", 8)
		else:
			b.remove_theme_color_override("font_shadow_color")
			b.remove_theme_constant_override("shadow_offset_x")
			b.remove_theme_constant_override("shadow_offset_y")
			b.remove_theme_constant_override("shadow_outline_size")
	b.set_meta("tab_active", active)
	b.set_meta("tab_unread", unread)


func _new_message(channel: String, from: String, text: String, own: bool) -> Dictionary:
	var m := {
		"id": _next_message_id,
		"channel": channel,
		"from": from,
		"text": text,
		"self": own,
		"time": Time.get_time_string_from_system().substr(0, 5),
	}
	_next_message_id += 1
	return m


func _message_id(m: Dictionary) -> int:
	if not m.has("id"):
		m["id"] = _next_message_id
		_next_message_id += 1
	return int(m.get("id", 0))


func _visible_messages() -> Array:
	var shown: Array = []
	if _active.begins_with("dm:"):
		var thread: Dictionary = _threads.get(_active.substr(3), {})
		shown = thread.get("messages", [])
	else:
		for m in _messages:
			if _active == "all" or String(m.get("channel", "")) == _active:
				shown.append(m)
	return shown


func _log_view_key() -> String:
	return _active + ("|timestamps" if _timestamps else "|plain")


func _refresh_log() -> void:
	_log_dirty = false
	if log_box == null:
		return
	var view_key := _log_view_key()
	var shown := _visible_messages()
	if view_key != _shown_view:
		_rebuild_log(shown, view_key)
		return
	if shown.is_empty():
		if not _shown_rows.is_empty() or _empty_log == null:
			_rebuild_log(shown, view_key)
		return
	if _empty_log != null:
		log_box.remove_child(_empty_log)
		_empty_log.queue_free()
		_empty_log = null

	# Remove rows whose messages fell out of the retained history (the cap) or
	# changed channel, then insert only the genuinely new rows. Existing rows
	# are moved into order instead of being recreated.
	var wanted := {}
	for m in shown:
		wanted[_message_id(m)] = true
	for id in _shown_rows.keys():
		if not wanted.has(id):
			var old: Control = _shown_rows[id]
			_shown_rows.erase(id)
			if is_instance_valid(old):
				log_box.remove_child(old)
				old.queue_free()
	var index := 0
	for m in shown:
		var id := _message_id(m)
		var row: Control = _shown_rows.get(id)
		if row == null:
			row = _add_message_row(m)
			_shown_rows[id] = row
			log_box.add_child(row)
		if row.get_index() != index:
			log_box.move_child(row, index)
		index += 1
	scroll_to_end.call_deferred()


func _rebuild_log(shown: Array, view_key: String) -> void:
	for child in log_box.get_children():
		log_box.remove_child(child)
		child.queue_free()
	_shown_rows.clear()
	_empty_log = null
	_shown_view = view_key
	if shown.is_empty():
		_empty_log = UiTheme.label("NO MESSAGES YET   ·   PRESS ENTER TO TALK", 9, UiTheme.TEXT_DIM, 500, 2)
		log_box.add_child(_empty_log)
	else:
		for m in shown:
			var row := _add_message_row(m)
			_shown_rows[_message_id(m)] = row
			log_box.add_child(row)
	scroll_to_end.call_deferred()


func _add_message_row(m: Dictionary) -> Control:
	var channel := String(m.get("channel", "say"))
	var color: Color = CHANNEL_COLORS.get(channel, UiTheme.TEXT)
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head)
	if _timestamps:
		head.add_child(UiTheme.label(String(m.get("time", "")), 8, Color(UiTheme.TEXT_DIM, 0.7), 400, 1))
	var tag: String = String({"guild": "GUILD", "combat": "COMBAT", "dm": "DM", "system": "SYS"}.get(channel, ""))
	if tag != "":
		head.add_child(UiTheme.label(tag, 8, color, 700, 1))
	var from := String(m.get("from", ""))
	if from != "" and tag != "SYS":
		head.add_child(UiTheme.label(from, 10, color, 600, 1))
	var body := UiTheme.label(String(m.get("text", "")), 11, UiTheme.TEXT if channel != "system" else Color(UiTheme.TEXT_DIM, 0.95), 400, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return row


func scroll_to_end() -> void:
	if log_scroll == null:
		return
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _render_community() -> void:
	if community_box == null:
		return
	for child in community_box.get_children():
		community_box.remove_child(child)
		child.queue_free()
	if _contacts.is_empty():
		community_box.add_child(UiTheme.label("NO OTHER ADVENTURERS YET   ·   JOIN A CO-OP SESSION TO MEET PLAYERS", 9, UiTheme.TEXT_DIM, 500, 1))
		return
	for c in _contacts:
		var name := String(c.get("name", ""))
		if name == "":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var avatar := ChatAvatar.new()
		avatar.custom_minimum_size = Vector2(38, 38)
		avatar.set_contact(c)
		row.add_child(avatar)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 5)
		var n := UiTheme.label(name, 11, UiTheme.TEXT, 700, 1)
		name_row.add_child(n)
		var status := UiTheme.label("YOU" if bool(c.get("self", false)) else ("ONLINE" if bool(c.get("online", true)) else "OFFLINE"),
			8, UiTheme.HP_HIGH if bool(c.get("online", true)) else UiTheme.TEXT_DIM, 700, 1)
		name_row.add_child(status)
		info.add_child(name_row)
		var job := String(c.get("job", "")).capitalize()
		var level := int(c.get("level", 0))
		var map := String(c.get("map", ""))
		var detail := "%s  ·  Lv %d" % [job, level] if level > 0 else job
		if map != "":
			detail += "  ·  " + map
		var d := UiTheme.label(detail, 9, UiTheme.TEXT_DIM, 400, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
		row.add_child(info)
		if not bool(c.get("self", false)) and bool(c.get("online", true)):
			var dm := Button.new()
			dm.text = "DM"
			dm.tooltip_text = "Open a private conversation with %s" % name
			UiTheme.style_hud_button(dm, 9)
			dm.pressed.connect(open_dm.bind(name))
			row.add_child(dm)
		if not bool(c.get("self", false)):
			var friend := Button.new()
			var already := is_friend(name)
			friend.text = "FRIEND" if already else "ADD"
			friend.disabled = already
			friend.tooltip_text = "Already in your community list" if already else "Add %s to your community" % name
			UiTheme.style_hud_button(friend, 9)
			friend.pressed.connect(add_friend.bind(name))
			row.add_child(friend)
		community_box.add_child(row)
		var line := ColorRect.new()
		line.custom_minimum_size = Vector2(0, 1)
		line.color = Color(UiTheme.BORDER, 0.12)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		community_box.add_child(line)


func _ensure_thread(name: String) -> Dictionary:
	if not _threads.has(name):
		_threads[name] = {"messages": [], "unread": 0, "contact": _find_contact(name)}
	return _threads[name]


func _find_contact(name: String) -> Dictionary:
	for c in _contacts:
		if String(c.get("name", "")) == name:
			return c
	return {"name": name, "online": false, "job": "adventurer", "level": 0, "map": ""}


func _show_popup(name: String, mark_read := true, refresh_tabs := true) -> void:
	if dm_popup == null or name == "":
		return
	var thread := _ensure_thread(name)
	if mark_read:
		thread.unread = 0
	dm_popup.set_meta("thread_name", name)
	dm_popup.set_thread(thread.get("contact", {}), thread.get("messages", []))
	dm_popup.set_friend(is_friend(name))
	dm_popup.open_popup()
	_panel.set_glow(0.0)
	if refresh_tabs:
		_refresh_tabs()


func _unread_total() -> int:
	var total := 0
	for name in _threads:
		total += int(_threads[name].get("unread", 0))
	return total


func _process(delta: float) -> void:
	if _panel == null:
		return
	_wake = maxf(0.0, _wake - delta)
	if _log_dirty and log_scroll != null and log_scroll.visible:
		_refresh_log()
	if _tabs_dirty:
		_refresh_tabs()
	var pointer := get_global_rect().has_point(get_global_mouse_position())
	var popup_open := dm_popup != null and dm_popup.is_open()
	var active := pointer or popup_open or _settings_open or is_open() or _wake > 0.0 or not _fade_when_idle
	var target := 1.0 if active else IDLE_ALPHA
	var speed := FADE_IN_SPEED if target > modulate.a else FADE_OUT_SPEED
	modulate.a = move_toward(modulate.a, target, delta * speed)
	var unread := _unread_total()
	if unread != _last_unread:
		_last_unread = unread
		_panel.set_glow(0.35 if unread > 0 else 0.0)
