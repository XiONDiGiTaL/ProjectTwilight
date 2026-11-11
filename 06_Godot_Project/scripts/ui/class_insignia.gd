class_name ClassInsignia
extends Control
## Class shield insignia shown beside the class title.
##
## Looks up the class in data/prerenewal/classes.json and displays its painted
## emblem from res://assets/ui/class_emblems/<Rank>/<class>.png. Until that
## file exists it draws the shared shield silhouette in the rank's material
## (a temporary stand-in that still communicates the rank).

const CLASSES_PATH := "res://data/prerenewal/classes.json"
const EMBLEM_ROOT := "res://assets/ui/class_emblems/"
const SHADER := preload("res://scripts/ui/class_insignia.gdshader")

## Rank materials: body dark/light, rim dark/light, wood grain.
const TIER_MATERIALS := {
	"novice":       [Color(0.32, 0.19, 0.09), Color(0.62, 0.42, 0.24), Color(0.27, 0.17, 0.08), Color(0.55, 0.4, 0.25), true],
	"first":        [Color(0.36, 0.18, 0.08), Color(0.78, 0.48, 0.28), Color(0.3, 0.15, 0.06), Color(0.95, 0.66, 0.42), false],
	"second":       [Color(0.42, 0.44, 0.48), Color(0.86, 0.88, 0.92), Color(0.32, 0.33, 0.37), Color(0.98, 0.98, 1.0), false],
	"high_novice":  [Color(0.32, 0.19, 0.09), Color(0.62, 0.42, 0.24), Color(0.36, 0.52, 0.66), Color(0.78, 0.92, 1.0), true],
	"high_first":   [Color(0.36, 0.18, 0.08), Color(0.78, 0.48, 0.28), Color(0.36, 0.52, 0.66), Color(0.8, 0.94, 1.0), false],
	"transcendent": [Color(0.45, 0.3, 0.05), Color(0.98, 0.8, 0.32), Color(0.4, 0.26, 0.04), Color(1.0, 0.92, 0.6), false],
}

static var _classes: Dictionary = {}

var class_id := ""
var _tex_rect: TextureRect
var _fallback: ColorRect


static func classes() -> Dictionary:
	if _classes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLASSES_PATH))
		if parsed is Dictionary:
			_classes = parsed
			_classes.erase("_doc")
	return _classes


static func emblem_path(id: String) -> String:
	var c: Dictionary = classes().get(id, {})
	return EMBLEM_ROOT + String(c.get("emblem", "")) if not c.is_empty() else ""


static func tier_of(id: String) -> String:
	return String(classes().get(id, {}).get("tier", "novice"))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_rect = TextureRect.new()
	_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_rect)
	_fallback = ColorRect.new()
	_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback.material = ShaderMaterial.new()
	(_fallback.material as ShaderMaterial).shader = SHADER
	add_child(_fallback)
	if class_id != "":
		set_class(class_id)


func set_class(id: String) -> void:
	class_id = id
	if _tex_rect == null:
		return
	var c: Dictionary = classes().get(id, {})
	tooltip_text = String(c.get("name", id))
	var path := emblem_path(id)
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	elif path != "" and FileAccess.file_exists(path):
		tex = ImageTexture.create_from_image(Image.load_from_file(path))
	_tex_rect.texture = tex
	_tex_rect.visible = tex != null
	_fallback.visible = tex == null
	if tex == null:
		var m: Array = TIER_MATERIALS.get(tier_of(id), TIER_MATERIALS.novice)
		var mat := _fallback.material as ShaderMaterial
		mat.set_shader_parameter("body_dark", m[0])
		mat.set_shader_parameter("body_light", m[1])
		mat.set_shader_parameter("rim_dark", m[2])
		mat.set_shader_parameter("rim_light", m[3])
		mat.set_shader_parameter("wood_grain", m[4])


func has_painted_emblem() -> bool:
	return _tex_rect != null and _tex_rect.visible
