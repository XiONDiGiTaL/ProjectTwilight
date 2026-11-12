class_name NetNpcHost
extends RaHost
## RaHost for a remote co-op player: the NPC script runs on the host, and its
## dialog is shown on the player's own screen. Pages, menus and number inputs
## travel as "dialog" messages; each answer comes back through the peer's
## PeerLink. A player who disconnects mid-dialog answers 255 (cancel).

var session: Node            # NetSession
var peer_id := 0
var link: RefCounted         # NetSession.PeerLink
var _page: Array = []


func _init(p_session: Node, p_peer: int, p_link: RefCounted) -> void:
	session = p_session
	peer_id = p_peer
	link = p_link


func _send(kind: String, payload: Dictionary) -> void:
	if session.multiplayer.multiplayer_peer != null and session._peers.has(peer_id):
		session._s_dialog.rpc_id(peer_id, kind, payload)


func mes(_speaker: String, text: String) -> void:
	_page.append(text)


func next() -> void:
	_send("page", {"speaker": current_speaker, "text": "\n".join(_page), "options": ["Next"]})
	var v: Variant = await link.answered
	_page.clear()
	if v is int and int(v) == 255:
		aborted = true


func select(speaker: String, options: Array) -> int:
	_send("select", {"speaker": speaker, "text": "\n".join(_page), "options": options})
	var v: Variant = await link.answered
	if not (v is int) or int(v) < 0 or int(v) >= options.size():
		aborted = true
		_send("close", {})
		return 255
	return int(v) + 1


func input_number(speaker: String, lo: int, hi: int) -> int:
	_send("number", {"speaker": speaker, "text": "\n".join(_page), "lo": lo, "hi": hi})
	var v: Variant = await link.answered
	_page.clear()
	return clampi(int(v) if v is int else lo, lo, hi)


func input_text(_speaker: String) -> String:
	return ""


func close_dialog() -> void:
	if not _page.is_empty():
		_send("page", {"speaker": current_speaker, "text": "\n".join(_page), "options": ["Close"]})
		await link.answered
	_page.clear()
	_send("close", {})
	closed = true


func finish() -> void:
	_page.clear()
	_send("close", {})
	closed = true


func notify(text: String) -> void:
	if session._peers.has(peer_id):
		session._s_notice.rpc_id(peer_id, text, true)


func warp(map: String, x: int, y: int) -> void:
	_send("close", {})
	session.script_warp_for(peer_id, map, x, y)


func effect(name: String) -> void:
	_send("effect", {"name": name})


func storage_opened(ok: bool) -> void:
	super.storage_opened(ok)
	if ok:
		_send("storage", {})


func guild_storage_opened(ok: bool) -> void:
	super.guild_storage_opened(ok)
	if ok:
		_send("guild_storage", {})
