extends Control
## Developer tool: browse SPR/ACT pairs in the mounted client and play their actions.

const PRESETS := [
	"data/sprite/몬스터/poring",
	"data/sprite/몬스터/lunatic",
	"data/sprite/몬스터/fabre",
	"data/sprite/인간족/몸통/남/초보자_남",
	"data/sprite/인간족/몸통/여/초보자_여",
	"data/sprite/인간족/몸통/남/검사_남",
	"data/sprite/인간족/몸통/여/마법사_여",
]

var _sprite: ActSprite
var _path: LineEdit
var _info: Label
var _action: SpinBox
var _zoom := 3.0


func _ready() -> void:
	if not RoResources.is_mounted:
		RoResources.mount()
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.2, 0.17)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8; bar.offset_top = 8; bar.offset_right = -8
	add_child(bar)
	var back := Button.new(); back.text = "◀ Menu"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	bar.add_child(back)
	var presets := OptionButton.new()
	for p in PRESETS:
		presets.add_item(p.get_file())
	presets.item_selected.connect(func(i): _path.text = PRESETS[i]; _load())
	bar.add_child(presets)
	_path = LineEdit.new()
	_path.text = PRESETS[0]
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.text_submitted.connect(func(_t): _load())
	bar.add_child(_path)
	bar.add_child(_labelled("Action"))
	_action = SpinBox.new(); _action.min_value = 0; _action.max_value = 0
	_action.value_changed.connect(func(v): if _sprite: _sprite.action = int(v); _sprite.set_process(true))
	bar.add_child(_action)

	_info = Label.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_left = 8; _info.offset_top = -32
	add_child(_info)

	_sprite = ActSprite.new()
	_sprite.scale = Vector2(_zoom, _zoom)
	add_child(_sprite)
	_center()
	get_viewport().size_changed.connect(_center)
	_load()


func _labelled(t: String) -> Label:
	var l := Label.new(); l.text = t
	return l


func _center() -> void:
	if _sprite:
		_sprite.position = get_viewport_rect().size * Vector2(0.5, 0.62)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom + 0.5, 10.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom - 0.5, 1.0)
		_sprite.scale = Vector2(_zoom, _zoom)


func _load() -> void:
	var base := _path.text.strip_edges()
	var spr := RoResources.load_spr(base + ".spr")
	var act := RoResources.load_act(base + ".act")
	if spr == null or act == null:
		_info.text = "Could not load %s: %s" % [base, RoResources.last_error]
		_sprite.setup(null, null)
		return
	_sprite.setup(spr, act)
	_sprite.set_process(true)
	_action.max_value = act.actions.size() - 1
	_action.value = 0
	_info.text = "%s  |  SPR v0x%X (%d indexed, %d rgba)  |  ACT v0x%X, %d actions  |  wheel = zoom" % [
		base, spr.version, spr.indexed_frames.size(), spr.rgba_frames.size(), act.version, act.actions.size()]
