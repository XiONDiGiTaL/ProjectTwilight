class_name GuildWindow
extends GlassWindow
## Guild roster and management: members with rank chips, pending
## invitations, invite, kick, promote / demote, transfer, disband and leave.
## This window only emits intents; FieldSimulation validates and applies them
## through GuildStore, like every other gameplay action. Controls appear only
## when GuildStore.can() allows them for the local player's rank:
##   officer-level (invite, kick a member)   blue accent buttons
##   leader-only (promote, demote, transfer, disband)   gold buttons
## Transfer and disband ask for confirmation before the intent is emitted.

signal invite_requested(name: String)
signal kick_requested(name: String)
signal leave_requested
signal accept_requested(gid: String)
signal decline_requested(gid: String)
signal promote_requested(name: String)
signal demote_requested(name: String)
signal transfer_requested(name: String)
signal disband_requested

const LEADER_TINT := Color(1.0, 0.8, 0.35)     # leader-only controls and the leader chip
const DANGER_TINT := Color(1.0, 0.36, 0.38)

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
var _disband: Button
var _footer: HBoxContainer
var _confirm_row: HBoxContainer
var _confirm_text: Label
var _confirm_action: Callable
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
	_roster_scroll.custom_minimum_size = Vector2(500, 190)
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
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	body.add_child(_footer)
	_leave = _button("LEAVE GUILD", false)
	_leave.pressed.connect(func(): leave_requested.emit())
	_footer.add_child(_leave)
	_disband = _button("DISBAND", false, DANGER_TINT)
	_disband.tooltip_text = "Leader only. Removes the guild and its storage for good."
	_disband.pressed.connect(_ask_disband)
	_footer.add_child(_disband)
	# Inline confirmation for irreversible actions.
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override("separation", 8)
	body.add_child(_confirm_row)
	_confirm_text = UiTheme.label("", 11, LEADER_TINT, 600, 1)
	_confirm_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(300, 0)
	_confirm_row.add_child(_confirm_text)
	var yes := _button("CONFIRM", true, DANGER_TINT)
	yes.pressed.connect(confirm_pending)
	_confirm_row.add_child(yes)
	var no := _button("CANCEL", false)
	no.pressed.connect(_cancel_confirm)
	_confirm_row.add_child(no)
	_confirm_row.visible = false
	visible = false


func _ask_disband() -> void:
	_ask("Disband the guild and destroy its storage? This cannot be undone.", func(): disband_requested.emit())


## Shows the confirmation bar; `action` runs only on CONFIRM.
func _ask(text: String, action: Callable) -> void:
	_confirm_text.text = text
	_confirm_action = action
	_confirm_row.visible = true
	reset_size()


func _cancel_confirm() -> void:
	_confirm_action = Callable()
	_confirm_row.visible = false
	reset_size()


func is_confirming() -> bool:
	return _confirm_row != null and _confirm_row.visible


## CONFIRM: runs the pending irreversible action (also used by tests / captures).
func confirm_pending() -> void:
	var act := _confirm_action
	_cancel_confirm()
	if act.is_valid():
		act.call()


func _button(text: String, primary: bool, tint := UiTheme.ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 24)
	b.add_theme_font_override("font", UiTheme.font(600, 3))
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint, 0.22 if primary else 0.08)
	sb.border_color = Color(tint, 0.8 if primary else 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(tint, 0.4 if primary else 0.2)
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
	_footer.visible = false
	_disband.visible = false
	_invite_row.visible = false
	_roster_scroll.visible = false
	_empty.visible = false
	if _confirm_row.visible:
		_cancel_confirm()
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
	var mine := my_rank()
	_status.text = "LEADER  %s      MEMBERS  %d      STORAGE  %d / %d      YOUR RANK  %s" % [
		leader, members.size(), bag.entries.size() if bag else 0, SimUnit.STORAGE_SLOTS, mine.to_upper()]
	_roster_scroll.visible = true
	# Leader first, then officers, then members (roster order within a rank).
	for wanted in GuildStore.RANKS:
		for m in members:
			if _store.rank_of(String(g.id), String(m)) == wanted:
				_roster.add_child(_member_row(String(g.id), String(m)))
	_footer.visible = true
	_disband.visible = GuildStore.can(mine, "disband")
	_invite_row.visible = GuildStore.can(mine, "invite")


## The local player's rank in their guild ("" when guildless).
func my_rank() -> String:
	return _store.rank_of(_player.guild_id, _player.name) if _store != null and _player != null else ""


## Button captions offered for `member` to the local player (tests read this).
func actions_for(member: String) -> Array:
	var out: Array = []
	if _store == null or _player == null or member == _player.name:
		return out
	var mine := my_rank()
	var theirs := _store.rank_of(_player.guild_id, member)
	if theirs == "":
		return out
	if GuildStore.can(mine, "promote") and theirs == GuildStore.RANK_MEMBER:
		out.append("PROMOTE")
	if GuildStore.can(mine, "demote") and theirs == GuildStore.RANK_OFFICER:
		out.append("DEMOTE")
	if GuildStore.can(mine, "transfer"):
		out.append("TRANSFER")
	if GuildStore.can(mine, "kick", theirs):
		out.append("KICK")
	return out


## True when the invite row / disband button are offered (tests read these).
func offers_invite() -> bool:
	return _invite_row != null and _invite_row.visible


func offers_disband() -> bool:
	return _disband != null and _disband.visible and _footer.visible


func _member_row(gid: String, member: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(480, 28)
	row.add_theme_constant_override("separation", 6)
	var name := UiTheme.label(member + ("   (YOU)" if member == _player.name else ""), 12, UiTheme.TEXT, 600, 1)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(_rank_chip(_store.rank_of(gid, member)))
	for action in actions_for(member):
		row.add_child(_action_button(String(action), member))
	return row


func _action_button(action: String, member: String) -> Button:
	var b: Button
	match action:
		"PROMOTE":
			b = _button("PROMOTE", false, LEADER_TINT)
			b.tooltip_text = "Leader only: make %s an officer." % member
			b.pressed.connect(func(): promote_requested.emit(member))
		"DEMOTE":
			b = _button("DEMOTE", false, LEADER_TINT)
			b.tooltip_text = "Leader only: make %s an ordinary member." % member
			b.pressed.connect(func(): demote_requested.emit(member))
		"TRANSFER":
			b = _button("TRANSFER", false, LEADER_TINT)
			b.tooltip_text = "Leader only: hand the guild to %s." % member
			b.pressed.connect(_ask_transfer.bind(member))
		_:
			b = _button("KICK", false)
			b.tooltip_text = "Remove %s from the guild." % member
			b.pressed.connect(func(): kick_requested.emit(member))
	b.custom_minimum_size = Vector2(50 if action == "KICK" else 74, 22)
	return b


func _ask_transfer(member: String) -> void:
	_ask("Make %s the guild leader? You will become an officer." % member, func(): transfer_requested.emit(member))


## Rank chip: gold for the leader, accent for officers, dim for members.
func _rank_chip(rank: String) -> Label:
	var color := UiTheme.TEXT_DIM
	if rank == GuildStore.RANK_LEADER:
		color = LEADER_TINT
	elif rank == GuildStore.RANK_OFFICER:
		color = UiTheme.ACCENT
	var chip := UiTheme.label(rank.to_upper(), 10, color, 600, 2)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.custom_minimum_size = Vector2(66, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.12)
	sb.border_color = Color(color, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	chip.add_theme_stylebox_override("normal", sb)
	return chip


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
