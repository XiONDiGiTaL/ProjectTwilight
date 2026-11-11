class_name RaHost
extends RefCounted
## What an rAthena NPC script talks to: the dialog box, notices, warps and
## effects. This base class is headless (used by tests and the dedicated
## server path): dialog lines are collected in `transcript`, menu and input
## answers come from the `answers` queue (1-based for menus). The field scene
## subclass (FieldNpcHost) drives the real glass dialog.

var transcript: Array = []      # every mes line, notice and choice, in order
var answers: Array = []         # scripted answers for select / menu / input
var warps: Array = []           # [map, x, y] requested by warp
var storages: Array = []        # storage opens requested by scripts (true = opened)
var guild_storages: Array = []  # guildopenstorage results (true = opened, false = busy / refused)
var effects: Array = []
var closed := false
var aborted := false        # the player cancelled a menu: the script stops
var current_speaker := ""   # NPC display name (set by RaInterpreter)


func mes(speaker: String, text: String) -> void:
	transcript.append(text)


func next() -> void:
	transcript.append("<next>")


## Shows the options; returns the 1-based choice, or 255 for cancel.
func select(speaker: String, options: Array) -> int:
	transcript.append("<select %s>" % "|".join(options))
	if answers.is_empty():
		aborted = true
		return 255
	var c := int(answers.pop_front())
	if c == 255:
		aborted = true
	return c


func input_number(speaker: String, lo: int, hi: int) -> int:
	return clampi(int(answers.pop_front()) if not answers.is_empty() else lo, lo, hi)


func input_text(speaker: String) -> String:
	return String(answers.pop_front()) if not answers.is_empty() else ""


## close / close2: the player dismisses the dialog.
func close_dialog() -> void:
	transcript.append("<close>")
	closed = true


## The script ended without close (end;): hide any open dialog.
func finish() -> void:
	closed = true


func notify(text: String) -> void:
	transcript.append("<notice %s>" % text)


func warp(map: String, x: int, y: int) -> void:
	warps.append([map, x, y])


func effect(name: String) -> void:
	effects.append(name)


## A script ran openstorage; the field host shows the storage window.
func storage_opened(ok: bool) -> void:
	storages.append(ok)


## A script ran guildopenstorage; the field host shows the guild window.
func guild_storage_opened(ok: bool) -> void:
	guild_storages.append(ok)


## The player's look changed (setlook / jobchange): rebuild the sprite.
func appearance_changed() -> void:
	pass


## Strips rAthena colour codes (^RRGGBB) for plain display.
static func plain(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\^[0-9A-Fa-f]{6}")
	return re.sub(text, "", true)
