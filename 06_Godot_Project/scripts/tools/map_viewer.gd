extends Node3D
## Developer tool: load any classic map by name and fly around it.

const PRESETS := ["prontera", "prt_fild08", "izlude", "geffen", "payon", "morocc", "alberta", "aldebaran", "pay_dun00"]

var _map: RoMap
var _camera: RoCamera
var _name_edit: LineEdit
var _info: Label
var _lightmap_on := true


func _ready() -> void:
	if not RoResources.is_mounted:
		RoResources.mount()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.8)
	add_child(env)
	_camera = RoCamera.new()
	add_child(_camera)

	var ui := CanvasLayer.new()
	add_child(ui)
	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 8)
	ui.add_child(bar)
	var back := Button.new(); back.text = "◀ Menu"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	bar.add_child(back)
	var presets := OptionButton.new()
	for p in PRESETS:
		presets.add_item(p)
	presets.item_selected.connect(func(i): _name_edit.text = PRESETS[i]; _load())
	bar.add_child(presets)
	_name_edit = LineEdit.new()
	_name_edit.text = PRESETS[0]
	_name_edit.custom_minimum_size = Vector2(200, 0)
	_name_edit.text_submitted.connect(func(_t): _load())
	bar.add_child(_name_edit)
	var lm := CheckButton.new(); lm.text = "Lightmaps"; lm.button_pressed = true
	lm.toggled.connect(_set_lightmaps)
	bar.add_child(lm)
	_info = Label.new()
	_info.position = Vector2(8, 690)
	ui.add_child(_info)
	_load()


func _load() -> void:
	if _map:
		_map.queue_free()
	_map = RoMap.new()
	add_child(_map)
	var name := _name_edit.text.strip_edges().to_lower()
	if not _map.load_map(name):
		_info.text = "Could not load %s: %s" % [name, RoResources.last_error]
		return
	_camera.focus = _map.center()
	_set_lightmaps(_lightmap_on)
	_info.text = "%s  |  GND %dx%d v%x, %d textures, %d surfaces  |  RSW v%x: %d models (not drawn yet)  |  built in %d ms  |  WASD pan, right-drag rotate, wheel zoom" % [
		name, _map.gnd.width, _map.gnd.height, _map.gnd.version, _map.gnd.textures.size(),
		_map.gnd.surface_count(), _map.rsw.version if _map.rsw else 0,
		_map.rsw.models.size() if _map.rsw else 0, _map.load_ms]


func _set_lightmaps(on: bool) -> void:
	_lightmap_on = on
	if _map and _map.ground:
		var mesh := _map.ground.mesh
		for s in mesh.get_surface_count():
			(mesh.surface_get_material(s) as ShaderMaterial).set_shader_parameter("use_lightmap", on)
