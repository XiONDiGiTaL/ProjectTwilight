class_name ChatDmPopup
extends GlassPanel
## Compact messenger-style private conversation. It slides up above the chat
## dock, keeps the character name and portrait visible, and never grabs the
## keyboard until the reply field is clicked or the popup is opened explicitly.

signal replied(to: String, text: String)
signal friend_requested(name: String)
signal dismissed

const WIDTH := 360.0
const MAX_HISTORY := 7

var _contact: Dictionary = {}
var _messages: Array = []
var _avatar: ChatAvatar
var _name: Label
var _status: Label
var _friend: Button
var _history: VBoxContainer
var _scroll: ScrollContainer
var _reply: LineEdit
var _send: Button


func _ready() -> void:
	super._ready()
	chamfer = 10.0
	padding = Vector4(12, 9, 12, 10)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	col.add_child(header)
	_avatar = ChatAvatar.new()
	_avatar.custom_minimum_size = Vector2(42, 42)
	header.add_child(_avatar)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(who)
	_name = UiTheme.label("DIRECT MESSAGE", 14, UiTheme.TEXT, 700, 2)
	who.add_child(_name)
	_status = UiTheme.label("", 10, UiTheme.TEXT_DIM, 500, 1)
	who.add_child(_status)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close conversation"
	close.custom_minimum_size = Vector2(24, 24)
	UiTheme.style_hud_button(close, 10)
	close.add_theme_color_override("font_color", UiTheme.TEXT)
	close.pressed.connect(close_popup)
	header.add_child(close)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	col.add_child(actions)
	_friend = Button.new()
	_friend.text = "ADD FRIEND"
	_friend.tooltip_text = "Add this adventurer to your community list"
	UiTheme.style_hud_button(_friend, 9)
	_friend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend.pressed.connect(func(): friend_requested.emit(String(_contact.get("name", ""))))
	actions.add_child(_friend)
	var hint := UiTheme.label("PRIVATE · ONLY THE TWO OF YOU", 9, UiTheme.ACCENT, 600, 1)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hint)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 92)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_history = VBoxContainer.new()
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.add_theme_constant_override("separation", 4)
	_scroll.add_child(_history)

	var reply_row := HBoxContainer.new()
	reply_row.add_theme_constant_override("separation", 7)
	col.add_child(reply_row)
	_reply = LineEdit.new()
	_reply.placeholder_text = "Reply privately…"
	_reply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply.text_submitted.connect(func(_text): _send_reply())
	UiTheme.style_line_edit(_reply)
	_reply.add_theme_font_size_override("font_size", 12)
	reply_row.add_child(_reply)
	_send = Button.new()
	_send.text = "SEND"
	UiTheme.style_hud_button(_send, 10)
	_send.pressed.connect(_send_reply)
	reply_row.add_child(_send)


func set_thread(contact: Dictionary, messages: Array) -> void:
	_contact = contact.duplicate(true)
	_messages = messages
	# open_popup() owns the render; doing it here as well duplicated every
	# conversation bubble each time a DM arrived or a tab was opened.


func set_friend(is_friend: bool) -> void:
	if _friend == null:
		return
	_friend.text = "FRIEND" if is_friend else "ADD FRIEND"
	_friend.disabled = is_friend
	_friend.tooltip_text = "Already in your community list" if is_friend else "Add this adventurer to your community list"


func open_popup() -> void:
	if _contact.is_empty():
		return
	visible = true
	move_to_front()
	await _render_thread()
	if not visible:
		return
	_place()
	var target := position
	position = target + Vector2(0, 20)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", target, 0.22)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)


func close_popup() -> void:
	if not visible:
		return
	visible = false
	_reply.release_focus()
	dismissed.emit()


func is_open() -> bool:
	return visible


## The field scene treats a focused reply box as text input, so movement keys
## are not stolen while the notification card is merely sitting on screen.
func reply_has_focus() -> bool:
	return _reply != null and _reply.has_focus()


func focus_reply() -> void:
	_reply.grab_focus()
	_reply.caret_column = _reply.text.length()


func _render_thread() -> void:
	var name := String(_contact.get("name", "DIRECT MESSAGE"))
	_name.text = name
	var job := String(_contact.get("job_name", _contact.get("job", "Adventurer")))
	var level := int(_contact.get("level", 0))
	var map := String(_contact.get("map", ""))
	var online := bool(_contact.get("online", true))
	var bits: Array = []
	if online:
		bits.append("Lv %d" % level if level > 0 else "ONLINE")
		if job != "":
			bits.append(job.capitalize())
		if map != "":
			bits.append(map)
	else:
		bits.append("OFFLINE")
		if map != "":
			bits.append("last seen in %s" % map)
	_status.text = "  ·  ".join(PackedStringArray(bits)).to_upper()
	_status.add_theme_color_override("font_color", UiTheme.HP_HIGH if online else UiTheme.TEXT_DIM)
	_avatar.set_contact(_contact)
	for child in _history.get_children():
		_history.remove_child(child)
		child.queue_free()
	var start := maxi(0, _messages.size() - MAX_HISTORY)
	for i in range(start, _messages.size()):
		_add_bubble(_messages[i])
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _add_bubble(message: Dictionary) -> void:
	var mine := bool(message.get("self", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mine:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.ACCENT, 0.18) if mine else Color(0.04, 0.1, 0.18, 0.72)
	sb.border_color = Color(UiTheme.ACCENT, 0.46) if mine else Color(UiTheme.BORDER, 0.36)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	bubble.add_theme_stylebox_override("panel", sb)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var text := UiTheme.label(String(message.get("text", "")), 11, UiTheme.TEXT, 400, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(0, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(text)
	row.add_child(bubble)
	if not mine:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	_history.add_child(row)


func _send_reply() -> void:
	var text := _reply.text.strip_edges()
	if text == "":
		return
	_reply.text = ""
	replied.emit(String(_contact.get("name", "")), text.left(200))


func _place() -> void:
	if not visible:
		return
	reset_size()
	position = Vector2(0, -size.y - 8.0)
