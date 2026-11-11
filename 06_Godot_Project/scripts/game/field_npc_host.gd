class_name FieldNpcHost
extends RaHost
## RaHost for the offline field: rAthena dialog commands drive the glass
## NpcDialog (mes lines accumulate on a page, next/close add a button,
## select/menu show a choice list with CANCEL), notices go to the HUD feed,
## warps go through the field scene's travel.

var field: Node      # the field scene (field_scene.gd)
var _page: Array = []


func _init(p_field: Node) -> void:
	field = p_field


func _dialog() -> NpcDialog:
	return field.hud.dialog


func mes(speaker: String, text: String) -> void:
	_page.append(text)


func next() -> void:
	_dialog().show_page(_speaker(), "\n".join(_page), ["Next"])
	await _dialog().chosen
	_page.clear()


func select(speaker: String, options: Array) -> int:
	_dialog().show_page(speaker, "\n".join(_page), options, true)
	var i: int = await _dialog().chosen
	# Like the client, the text stays after a menu choice until the next "next".
	if i < 0:
		aborted = true
		_dialog().close()
		return 255
	return i + 1


func input_number(speaker: String, lo: int, hi: int) -> int:
	_dialog().ask_number(speaker, "\n".join(_page), lo, hi)
	var v: int = await _dialog().number_entered
	_page.clear()
	return clampi(v, lo, hi)


func input_text(speaker: String) -> String:
	return ""


func close_dialog() -> void:
	if not _page.is_empty():
		_dialog().show_page(_speaker(), "\n".join(_page), ["Close"])
		await _dialog().chosen
	_page.clear()
	_dialog().close()
	closed = true


func finish() -> void:
	_page.clear()
	_dialog().close()
	closed = true


func notify(text: String) -> void:
	field.hud.notify(text, UiTheme.ACCENT)


func warp(map: String, x: int, y: int) -> void:
	_dialog().close()
	field.script_warp(map, x, y)


func effect(name: String) -> void:
	if name.contains("HEAL") or name == "312" or name == "313":
		field.script_effect("heal")
	elif name != "":
		field.script_effect("sparkle")


func appearance_changed() -> void:
	field.script_appearance_changed()



func _speaker() -> String:
	return current_speaker
