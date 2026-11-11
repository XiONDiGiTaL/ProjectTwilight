class_name RoMap
extends Node3D
## A loaded classic map: ground mesh, water plane and walkability data.
## Rendering only reads GAT/GND/RSW; gameplay queries go through `gat`.

const TEXTURE_DIR := "data\\texture\\"

var map_name := ""
var gat: GatFile
var gnd: GndFile
var rsw: RswFile
var ground: MeshInstance3D
var load_ms := 0

var _textures: Dictionary = {}
## The RoResources VFS node (looked up at runtime so tools and tests can use RoMap).
var res: Node


## Loads "<name>.rsw/.gnd/.gat" through res. Returns false on failure.
func load_map(name: String) -> bool:
	var t0 := Time.get_ticks_msec()
	map_name = name
	if res == null:
		res = (Engine.get_main_loop() as SceneTree).root.get_node("RoResources")
	rsw = RswFile.decode(res.read("data\\%s.rsw" % name))
	var gnd_name := rsw.gnd_file if rsw and rsw.gnd_file != "" else name + ".gnd"
	var gat_name := rsw.gat_file if rsw and rsw.gat_file != "" else name + ".gat"
	gnd = GndFile.decode(res.read("data\\" + Cp949.decode_latin1(gnd_name)))
	gat = GatFile.decode(res.read("data\\" + Cp949.decode_latin1(gat_name)))
	if gnd == null:
		push_warning("Map %s: no ground (%s)" % [name, res.last_error])
		return false
	var builder := GroundMeshBuilder.new()
	builder.gnd = gnd
	builder.rsw = rsw
	builder.texture_loader = _load_texture
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = builder.build()
	add_child(ground)
	_add_water()
	load_ms = Time.get_ticks_msec() - t0
	return true


## Map extents in world units (x, z) and centre.
func world_size() -> Vector2:
	return Vector2(gnd.width * gnd.zoom, gnd.height * gnd.zoom)


func center() -> Vector3:
	var s := world_size()
	return Vector3(s.x / 2.0, 0.0, -s.y / 2.0)


## Godot position of the centre of GAT cell (x, y), on the ground.
func cell_to_world(x: int, y: int) -> Vector3:
	var half := gnd.zoom / 2.0
	var hgt := -gat.height_at(x, y) if gat else 0.0
	return Vector3((x + 0.5) * half, hgt, -(y + 0.5) * half)


func world_to_cell(p: Vector3) -> Vector2i:
	var half := gnd.zoom / 2.0
	return Vector2i(floori(p.x / half), floori(-p.z / half))


func _load_texture(latin1_name: String) -> Texture2D:
	if _textures.has(latin1_name):
		return _textures[latin1_name]
	var path := TEXTURE_DIR + Cp949.decode_latin1(latin1_name)
	var img := TextureLoader.load_image(res.read(path), path)
	var tex: Texture2D = null
	if img:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_textures[latin1_name] = tex
	return tex


func _add_water() -> void:
	var w: Dictionary = gnd.water if not gnd.water.is_empty() else (rsw.water if rsw else {})
	if w.is_empty():
		return
	var plane := MeshInstance3D.new()
	plane.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = world_size()
	plane.mesh = pm
	plane.position = center() + Vector3(0, -float(w.level), 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.55)
	var tex_path := "data\\texture\\워터\\water%d00.jpg" % int(w.type)
	var img := TextureLoader.load_image(res.read(tex_path), tex_path)
	if img:
		img.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.uv1_scale = Vector3(world_size().x / 40.0, world_size().y / 40.0, 1)
	else:
		mat.albedo_color = Color(0.2, 0.4, 0.6, 0.5)
	plane.material_override = mat
	add_child(plane)
