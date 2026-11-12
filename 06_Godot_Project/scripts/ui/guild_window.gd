class_name GuildWindow
extends GlassWindow
## Guild roster and management: members, pending invitations, invite, kick
## and leave. This window only emits intents; FieldSimulation validates and
## applies them through GuildStore, like every other gameplay action.

signal invite_requested(name: String)
signal kick_requested(name: String)
signal leave_requested
signal accept_requested(gid: String)
signal decline_requested(gid: String)

var _store: GuildStore
var _player: SimUnit
var _title: Label
var _status: Label
var _roster_scroll: ScrollContainer
var _roster: VBoxContainer
var _invites_box: VBoxContainer
var _invite_row: HBoxContainer
var _invite_input: LineEdit
var _leave: Button
var _empty: Label


func _init() -> void:
	super._init()
	title = "GUILD"
	window_id = "guild"


func _ready() -> void:
	super._ready()
	_title = _title_bar.get_child(0) as Label
	_status = UiTheme.label("", 10, Color(UiTheme.ACCENT, 0.85), 600, 2)
	body.add_child(_status)
	_roster_scroll = ScrollContainer.new()
	_roster_scroll.custom_minimum_size = Vector2(380, 190)
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_roster_scroll)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 3)
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_scroll.add_child(_roster)
	_empty = UiTheme.label("", 12, UiTheme.TEXT_DIM, 400, 2)
	body.add_child(_empty)
	_invites_box = VBoxContainer.new()
	_invites_box.add_theme_constant_override("separation", 3)
	body.add_child(_invites_box)
	_invite_row = HBoxContainer.new()
	_invite_row.add_theme_constant_override("separation", 6)
	body.add_child(_invite_row)
	_invite_input = LineEdit.new()
	_invite_input.placeholder_text = "Invite by name"
	_invite_input.custom_minimum_size = Vector2(220, 26)
	_invite_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_input.text_submitted.connect(func(_t): _send_invite())
	_invite_row.add_child(_invite_input)
	var invite := _button("INVITE", true)
	invite.pressed.connect(_send_invite)
	_invite_row.add_child(invite)
	_leave = _button("LEAVE GUILD", false)
	_leave.pressed.connect(func(): leave_requested.emit())
	body.add_child(_leave)
	visible = false


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 24)
	b.add_theme_font_override("font", UiTheme.font(600, 3))
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.ACCENT, 0.22 if primary else 0.08)
	sb.border_color = Color(UiTheme.ACCENT, 0.8 if primary else 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UiTheme.ACCENT, 0.4 if primary else 0.18)
	b.add_theme_stylebox_override("hover", hover)
	return b


func bind(store: GuildStore, p: SimUnit) -> void:
	_store = store
	_player = p
	refresh()


func open(store: GuildStore, p: SimUnit) -> void:
	_store = store
	_player = p
	refresh()
	toggle(true)


func refresh() -> void:
	if _roster == null or _store == null or _player == null:
		return
	_clear(_roster)
	_clear(_invites_box)
	_leave.visible = false
	_invite_row.visible = false
	_roster_scroll.visible = false
	_empty.visible = false
	var g: Dictionary = _store.get_guild(_player.guild_id)
	if g.is_empty():
		_title.text = "◆  GUILD"
		_status.text = "NOT IN A GUILD"
		_empty.text = "Found a guild with  @guild create <name>\nor accept an invitation below."
		_empty.visible = true
		var invites := _store.invites_for(_player.name)
		for inv in invites:
			_invites_box.add_child(_invite_row_for(inv))
		if invites.is_empty():
			_invites_box.add_child(UiTheme.label("No pending invitations.", 11, UiTheme.TEXT_DIM, 400, 1))
		return
	_title.text = "◆  GUILD  ·  " + String(g.name).to_upper()
	var members: Array = g.get("members", [])
	var leader := String(g.get("leader", ""))
	var bag: Inventory = g.get("storage")
	_status.text = "LEADER  %s        MEMBERS  %d        STORAGE  %d / %d" % [
		leader, members.size(), bag.entries.size() if bag else 0, SimUnit.STORAGE_SLOTS]
	_roster_scroll.visible = true
	for m in members:
		_roster.add_child(_member_row(String(m), leader))
	_leave.visible = true
	_invite_row.visible = leader == _player.name


func _member_row(member: String, leader: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 28)
	var name := UiTheme.label(member + ("   (YOU)" if member == _player.name else ""), 12, UiTheme.TEXT, 600, 1)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var is_leader := member == leader
	row.add_child(UiTheme.label("LEADER" if is_leader else "MEMBER", 10,
		Color(UiTheme.ACCENT, 0.9) if is_leader else UiTheme.TEXT_DIM, 600, 2))
	if leader == _player.name and member != _player.name:
		var kick := _button("KICK", false)
		kick.custom_minimum_size = Vector2(54, 22)
		kick.pressed.connect(func(): kick_requested.emit(member))
		row.add_child(kick)
	return row


func _invite_row_for(inv: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 28)
	var name := UiTheme.label(String(inv.get("name", "Guild")), 12, UiTheme.TEXT, 600, 1)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var accept := _button("ACCEPT", true)
	accept.custom_minimum_size = Vector2(64, 22)
	accept.pressed.connect(func(): accept_requested.emit(String(inv.id)))
	row.add_child(accept)
	var decline := _button("DECLINE", false)
	decline.custom_minimum_size = Vector2(64, 22)
	decline.pressed.connect(func(): decline_requested.emit(String(inv.id)))
	row.add_child(decline)
	return row


func _send_invite() -> void:
	var n := _invite_input.text.strip_edges()
	if n == "":
		return
	invite_requested.emit(n)
	_invite_input.clear()


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
