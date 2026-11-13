extends RefCounted
## Twilight Glass chat dock: channels, private-message tabs, the messenger
## card, the community roster and the chat-options drawer. These tests use
## temporary settings values and restore them before returning.

const CHAT := preload("res://scripts/ui/chat_console.gd")


func _chat(t: SceneTree) -> ChatConsole:
	var c := CHAT.new()
	c.position = Vector2(12, 300)
	c.size = Vector2(372, 230)
	t.root.add_child(c)
	return c


func test_chat_dock_builds_tabs_and_messages(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	c.add_system("System ready")
	c.add_say("Aria", "hello there")
	await t.process_frame
	var ids: Array = c._tabs_buttons.keys()
	if not c._tabs_buttons.has("all") or not c._tabs_buttons.has("system") \
			or not c._tabs_buttons.has("guild") or not c._tabs_buttons.has("combat"):
		return "the dock should expose ALL, SYSTEM, GUILD and COMBAT channels"
	if ids[-1] != "settings":
		return "the settings tab should be last in the tab row: %s" % [ids]
	if c._messages.size() != 2:
		return "system and say messages should be retained in the log"
	var texts: Array = []
	for row in c.log_box.get_children():
		for child in row.get_children():
			if child is Label:
				texts.append(child.text)
			for sub in child.get_children():
				if sub is Label:
					texts.append(sub.text)
	if not ("hello there" in texts):
		return "the ALL log should render the public message: %s" % [texts]
	c.queue_free()
	await t.process_frame
	return true


func test_dm_tab_glows_until_the_thread_is_opened(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	c.receive_dm("Aria", "are you there?")
	await t.process_frame
	var thread: Dictionary = c._threads.get("Aria", {})
	if int(thread.get("unread", 0)) != 1:
		return "an incoming DM should be unread until its tab is selected"
	if not c._tabs_buttons.has("dm:Aria"):
		return "an incoming DM should add a private tab"
	var tab: Button = c._tabs_buttons["dm:Aria"]
	if not tab.text.begins_with("●"):
		return "an unread DM tab should carry a visible notification dot: %s" % tab.text
	if not c.dm_popup.visible:
		return "an incoming DM should open the messenger card"
	if c.dm_popup._name.text != "Aria":
		return "the messenger card should name the sender: %s" % c.dm_popup._name.text
	c._select_tab("dm:Aria")
	await t.process_frame
	thread = c._threads.get("Aria", {})
	if int(thread.get("unread", 0)) != 0:
		return "opening the DM tab should clear its unread count"
	tab = c._tabs_buttons.get("dm:Aria")
	if tab != null and tab.text.begins_with("●"):
		return "the notification dot should clear after opening the DM tab"
	var replies: Array = []
	c.dm_reply_requested.connect(func(to, text): replies.append([to, text]))
	c.send_dm("Aria", "I am here")
	await t.process_frame
	if replies.size() != 1 or replies[0][0] != "Aria" or replies[0][1] != "I am here":
		return "sending a DM should emit the target and text: %s" % [replies]
	if int(c._threads["Aria"].get("messages", []).size()) != 2:
		return "outgoing DMs should be kept in the same thread"
	c.queue_free()
	await t.process_frame
	return true


func test_community_roster_and_friend_buttons(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old_friends: Variant = settings.get_value("social", "friends", [])
	settings.set_value("social", "friends", [])
	var c := _chat(t)
	await t.process_frame
	c.set_contacts([
		{"name": "Aria", "job": "hunter", "level": 42, "map": "Payon Forest", "online": true, "self": false},
		{"name": "Borin", "job": "priest", "level": 31, "map": "Prontera", "online": true, "self": false},
	])
	await t.process_frame
	c._select_tab("community")
	await t.process_frame
	if not c.community_scroll.visible or c.log_scroll.visible:
		return "the COMMUNITY tab should replace the log with the roster"
	var names: Array = []
	for contact in c._contacts:
		names.append(String(contact.get("name", "")))
	if not ("Aria" in names) or not ("Borin" in names):
		return "the community list should include online players: %s" % [names]
	var aria: Dictionary = {}
	for contact in c._contacts:
		if String(contact.get("name", "")) == "Aria":
			aria = contact
	if int(aria.get("level", 0)) != 42 or String(aria.get("map", "")) != "Payon Forest":
		return "the roster should expose level and current map: %s" % [aria]
	c.add_friend("Aria")
	await t.process_frame
	if not c.is_friend("Aria"):
		return "Add Friend should update the local friend list"
	var stored: Variant = settings.get_value("social", "friends", [])
	if not (stored is Array) or not ("Aria" in stored):
		return "the friend list should persist through Settings: %s" % [stored]
	c.add_friend("Aria")
	if c._friends.count("Aria") != 1:
		return "adding the same friend twice should not duplicate it"
	c.queue_free()
	settings.set_value("social", "friends", old_friends)
	await t.process_frame
	return true


func test_chat_tabs_reuse_buttons_when_unread_changes(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	var all_id: int = c._tabs_buttons["all"].get_instance_id()
	var settings_id: int = c._tabs_buttons["settings"].get_instance_id()
	c.receive_dm("Aria", "are you there?")
	await t.process_frame
	if c._tabs_buttons["all"].get_instance_id() != all_id:
		return "receiving a DM must not recreate unrelated tabs"
	if c._tabs_buttons["settings"].get_instance_id() != settings_id:
		return "receiving a DM must not recreate the settings tab"
	var aria: Button = c._tabs_buttons["dm:Aria"]
	var aria_id := aria.get_instance_id()
	if not aria.text.begins_with("●"):
		return "the new DM tab should glow while unread: %s" % aria.text
	c.receive_dm("Aria", "second message")
	await t.process_frame
	if c._tabs_buttons["dm:Aria"].get_instance_id() != aria_id:
		return "an unread-count change must update the existing DM button"
	c.receive_dm("Borin", "hello")
	await t.process_frame
	if c._tabs_buttons["dm:Aria"].get_instance_id() != aria_id:
		return "adding another DM thread must not recreate existing DM buttons"
	c._select_tab("dm:Aria")
	await t.process_frame
	if c._tabs_buttons["dm:Aria"].get_instance_id() != aria_id:
		return "opening a DM must update its existing tab button"
	if c._tabs_buttons["dm:Aria"].text.begins_with("●"):
		return "the existing tab should lose its unread dot after opening"
	var children := c.tabs.get_children()
	if children[-1] != c._tabs_buttons["settings"]:
		return "the settings tab should remain last after cached updates"
	c.queue_free()
	await t.process_frame
	return true


func test_many_dm_tabs_are_built_across_frames(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	c._dm_popups = false
	for i in 10:
		c.receive_dm("Player %d" % i, "ping")
	await t.process_frame
	var first_count := c._tabs_buttons.size()
	if first_count >= 16:
		return "a burst of DMs should build tabs progressively, not all at once: %d" % first_count
	for i in 12:
		await t.process_frame
	if c._tabs_buttons.size() != 16:
		return "all DM tabs should exist after the staged build: %d" % c._tabs_buttons.size()
	for i in 10:
		if not c._tabs_buttons.has("dm:Player %d" % i):
			return "missing staged DM tab Player %d" % i
	var children := c.tabs.get_children()
	if children[-1] != c._tabs_buttons["settings"]:
		return "staged DM tabs must not push settings out of place"
	c.queue_free()
	await t.process_frame
	return true


func test_chat_log_reuses_rows_when_appending(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	for i in 12:
		c.add_say("Aria", "line %d" % i)
	await t.process_frame
	if c.log_box.get_child_count() != 12:
		return "the visible log should have one row per message: %d" % c.log_box.get_child_count()
	var first_id := c.log_box.get_child(0).get_instance_id()
	var last_id := c.log_box.get_child(11).get_instance_id()
	c.add_say("Aria", "appended")
	await t.process_frame
	if c.log_box.get_child_count() != 13:
		return "appending a message should add exactly one row: %d" % c.log_box.get_child_count()
	if c.log_box.get_child(0).get_instance_id() != first_id:
		return "appending a message must not recreate the existing first row"
	if c.log_box.get_child(12).get_instance_id() == last_id:
		return "the new message should get a new row"
	if c._shown_rows.size() != 13:
		return "the row cache should track every visible message"
	for i in 150:
		c.add_say("Aria", "cap %d" % i)
	await t.process_frame
	if c.log_box.get_child_count() != ChatConsole.MAX_MESSAGES:
		return "the visible log should retain the history cap: %d" % c.log_box.get_child_count()
	if c._shown_rows.size() != ChatConsole.MAX_MESSAGES:
		return "the row cache should match the capped history: %d" % c._shown_rows.size()
	c._select_tab("system")
	await t.process_frame
	if c.log_box.get_child_count() != 1 or c._empty_log == null:
		return "switching to an empty channel should show the empty-log placeholder"
	c._select_tab("all")
	await t.process_frame
	if c.log_box.get_child_count() != ChatConsole.MAX_MESSAGES:
		return "switching back should rebuild only the newly selected channel"
	c.queue_free()
	await t.process_frame
	return true


func test_chat_active_channel_refreshes_when_eviction_removes_its_row(t: SceneTree) -> Variant:
	var c := _chat(t)
	await t.process_frame
	c._select_tab("system")
	await t.process_frame
	for i in ChatConsole.MAX_MESSAGES:
		c.add_system("system %d" % i)
	await t.process_frame
	c.add_say("Aria", "new public line")
	await t.process_frame
	if c.log_box.get_child_count() != ChatConsole.MAX_MESSAGES - 1:
		return "evicting a visible SYSTEM row should refresh the active SYSTEM tab: %d" % c.log_box.get_child_count()
	c._select_tab("system")
	await t.process_frame
	if c.log_box.get_child_count() != ChatConsole.MAX_MESSAGES - 1:
		return "the SYSTEM tab should retain the capped history after eviction: %d" % c.log_box.get_child_count()
	c.queue_free()
	await t.process_frame
	return true


func test_chat_options_slide_and_fade_controls(t: SceneTree) -> Variant:
	var settings = t.root.get_node_or_null("/root/Settings")
	if settings == null:
		return "Settings autoload is missing"
	var old_fade: Variant = settings.get_value("chat", "fade_when_idle", true)
	var old_popups: Variant = settings.get_value("chat", "dm_popups", true)
	var old_stamps: Variant = settings.get_value("chat", "timestamps", true)
	var c := _chat(t)
	await t.process_frame
	if c.settings_panel.visible:
		return "chat options should start hidden"
	c._toggle_settings(true)
	await t.process_frame
	if not c.settings_panel.visible:
		return "the settings tab should open the chat-options drawer"
	c._set_option("dm_popups", false)
	c._set_option("fade_when_idle", false)
	await t.process_frame
	if c._dm_popups or c._fade_when_idle:
		return "chat option toggles should update the live console"
	if bool(settings.get_value("chat", "dm_popups", true)) != false:
		return "chat option toggles should persist through Settings"
	c.open()
	if not c.is_open() or not c._input_row.visible:
		return "open() should reveal the chat input row"
	c.close()
	if c.is_open():
		return "close() should hide the chat input row"
	c._toggle_settings(false)
	c.queue_free()
	settings.set_value("chat", "fade_when_idle", old_fade)
	settings.set_value("chat", "dm_popups", old_popups)
	settings.set_value("chat", "timestamps", old_stamps)
	await t.process_frame
	return true
