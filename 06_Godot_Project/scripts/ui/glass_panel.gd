class_name GlassPanel
extends PanelContainer
## PanelContainer drawn with the frosted glass shader. Content children are
## laid out over the glass with the given padding.

const SHADER := preload("res://scripts/ui/glass_panel.gdshader")

@export var chamfer := 12.0
@export var padding := Vector4(14, 10, 14, 12)  # left, top, right, bottom
@export var sweep := true

var glass: ColorRect
var _mat := ShaderMaterial.new()


func _init() -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_right = padding.z
	sb.content_margin_bottom = padding.w
	add_theme_stylebox_override("panel", sb)
	glass = ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.show_behind_parent = true
	_mat.shader = SHADER
	glass.material = _mat
	add_child(glass, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	_mat.set_shader_parameter("chamfer", chamfer)
	_mat.set_shader_parameter("sweep", 1.0 if sweep else 0.0)
	resized.connect(_fit)
	# The container also lays out internal children inside the padding; re-fit
	# the glass to the full panel after every sort.
	sort_children.connect(_fit)
	_fit()


func _fit() -> void:
	glass.position = Vector2.ZERO
	glass.size = size
	_mat.set_shader_parameter("size", size)


## Briefly brightens the border (alerts, focus).
func set_glow(v: float) -> void:
	_mat.set_shader_parameter("glow", clampf(v, 0.0, 1.0))
