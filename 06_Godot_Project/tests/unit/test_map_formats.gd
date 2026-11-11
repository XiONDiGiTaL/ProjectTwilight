extends RefCounted
## Synthetic GAT/GND/RSW fixtures built from the documented layouts.


static func _u32(b: PackedByteArray, v: int) -> void:
	for i in 4:
		b.append((v >> (8 * i)) & 0xFF)


static func _f32(b: PackedByteArray, v: float) -> void:
	var t := PackedByteArray(); t.resize(4); t.encode_float(0, v); b.append_array(t)


static func _fixed(b: PackedByteArray, s: String, n: int) -> void:
	var t := s.to_ascii_buffer(); t.resize(n); b.append_array(t)


func _make_gat() -> PackedByteArray:
	var b := "GRAT".to_ascii_buffer()
	b.append(1); b.append(2)
	_u32(b, 2); _u32(b, 1)
	for h in [0.0, 0.0, -10.0, -10.0]: _f32(b, h)  # cell (0,0): rises to the north
	_u32(b, 0)
	for h in [0.0, 0.0, 0.0, 0.0]: _f32(b, h)
	_u32(b, 1)  # blocked
	return b


func test_gat(_t) -> Variant:
	var g := GatFile.decode(_make_gat())
	if g == null or g.width != 2 or g.height != 1 or g.version != 0x0102:
		return "header wrong"
	if not g.is_walkable(0, 0) or g.is_walkable(1, 0) or g.is_walkable(5, 5):
		return "walkability wrong"
	if not is_equal_approx(g.height_at(0, 0, 0.5, 0.5), -5.0):
		return "interpolated height %f" % g.height_at(0, 0)
	return true


func _make_gnd(version_minor: int) -> PackedByteArray:
	var b := "GRGN".to_ascii_buffer()
	b.append(1); b.append(version_minor)
	_u32(b, 1); _u32(b, 1); _f32(b, 10.0)
	_u32(b, 1); _u32(b, 80); _fixed(b, "grass.bmp", 80)
	_u32(b, 1); _u32(b, 8); _u32(b, 8); _u32(b, 1)
	var lm := PackedByteArray(); lm.resize(256); lm.fill(255); b.append_array(lm)
	_u32(b, 1)  # one surface
	for u in [0.0, 1.0, 0.0, 1.0]: _f32(b, u)
	for v in [0.0, 0.0, 1.0, 1.0]: _f32(b, v)
	b.append_array(PackedByteArray([0, 0, 0, 0]))  # texture 0, lightmap 0
	b.append_array(PackedByteArray([10, 20, 30, 255]))  # B,G,R,A
	for h in [0.0, 0.0, 0.0, 0.0]: _f32(b, h)
	_u32(b, 0); _u32(b, 0xFFFFFFFF); _u32(b, 0xFFFFFFFF)
	if version_minor >= 8:
		_f32(b, 3.0); _u32(b, 2); _f32(b, 1.0); _f32(b, 2.0); _f32(b, 50.0); _u32(b, 3); _u32(b, 1); _u32(b, 1)
		_f32(b, 3.0)
	return b


func test_gnd_17_and_18(_t) -> Variant:
	for minor in [7, 8]:
		var g := GndFile.decode(_make_gnd(minor))
		if g == null:
			return "1.%d decode failed" % minor
		if g.textures[0] != "grass.bmp" or g.surface_count() != 1 or g.cube_top[0] != 0 or g.cube_front[0] != -1:
			return "1.%d fields wrong" % minor
		var c: Color = g.surf_color[0]
		if c.r8 != 30 or c.g8 != 20 or c.b8 != 10:
			return "BGRA order wrong"
		if minor == 8 and (g.water.get("type", -1) != 2 or not is_equal_approx(g.water.level, 3.0)):
			return "water wrong: %s" % g.water
	return true


func test_ground_mesh_builds(_t) -> Variant:
	var builder := GroundMeshBuilder.new()
	builder.gnd = GndFile.decode(_make_gnd(7))
	var mesh := builder.build()
	if mesh.get_surface_count() != 1:
		return "expected 1 surface"
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.size() != 6 or normals[0].dot(Vector3.UP) < 0.99:
		return "top face wrong: %d verts, n=%s" % [verts.size(), normals[0]]
	# North is -Z: the NW corner of cell (0,0) is at z = -10.
	if not verts.has(Vector3(0, 0, -10)):
		return "coordinate mapping wrong: %s" % verts
	return true


func _make_rsw_21() -> PackedByteArray:
	var b := "GRSW".to_ascii_buffer()
	b.append(2); b.append(1)
	_fixed(b, "", 40); _fixed(b, "test.gnd", 40); _fixed(b, "test.gat", 40); _fixed(b, "", 40)
	_f32(b, 5.0); _u32(b, 1); _f32(b, 1.0); _f32(b, 2.0); _f32(b, 50.0); _u32(b, 3)
	_u32(b, 45); _u32(b, 30)
	for v in [1.0, 1.0, 1.0, 0.3, 0.3, 0.3, 0.5]: _f32(b, v)
	for v in [-500, 500, -500, 500]: _u32(b, v & 0xFFFFFFFF)
	_u32(b, 1)
	_u32(b, 1)  # model
	_fixed(b, "tree", 40); _u32(b, 0); _f32(b, 1.0); _u32(b, 0)
	_fixed(b, "tree.rsm", 80); _fixed(b, "", 80)
	for v in [1.0, 2.0, 3.0, 0.0, 90.0, 0.0, 1.0, 1.0, 1.0]: _f32(b, v)
	return b


func test_rsw_21(_t) -> Variant:
	var r := RswFile.decode(_make_rsw_21())
	if r == null or r.gnd_file != "test.gnd" or r.gat_file != "test.gat":
		return "header wrong"
	if r.water.type != 1 or r.light.latitude != 30 or not is_equal_approx(r.light.opacity, 0.5):
		return "water/light wrong"
	if not r.objects_complete or r.models.size() != 1 or r.models[0].file != "tree.rsm" or r.models[0].rot != Vector3(0, 90, 0):
		return "model wrong: %s" % str(r.models)
	return true


func _make_rsm_14() -> PackedByteArray:
	var b := "GRSM".to_ascii_buffer()
	b.append(1); b.append(4)
	_u32(b, 0); _u32(b, 1)  # anim length, shade FLAT
	b.append(255)  # alpha
	b.resize(b.size() + 16)
	_u32(b, 1); _fixed(b, "wall.bmp", 40)
	_fixed(b, "root", 40)
	_u32(b, 1)  # one node
	_fixed(b, "root", 40); _fixed(b, "", 40)
	_u32(b, 1); _u32(b, 0)  # texture ref 0
	for v in [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]: _f32(b, v)  # offset = identity
	for v in [0.0, 0.0, 0.0]: _f32(b, v)  # position
	for v in [0.0, 0.0, 0.0]: _f32(b, v)  # translation
	_f32(b, 0.0)
	for v in [0.0, 1.0, 0.0]: _f32(b, v)  # rot axis
	for v in [1.0, 1.0, 1.0]: _f32(b, v)  # scale
	_u32(b, 3)  # triangle spanning x 0..10, RO y -20..0 (up is negative), z 0
	for v in [0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 0.0, -20.0, 0.0]: _f32(b, v)
	_u32(b, 3)
	for uv in [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]]:
		_u32(b, 0xFFFFFFFF); _f32(b, uv[0]); _f32(b, uv[1])
	_u32(b, 1)  # one face
	for i in [0, 1, 2, 0, 1, 2, 0, 0]:
		b.append(i & 0xFF); b.append(0)
	_u32(b, 0); _u32(b, 0)  # two_sided, smooth group
	_u32(b, 0)  # rot keys
	_u32(b, 0); _u32(b, 0)  # trailer
	return b


func test_rsm_decode_and_centre(_t) -> Variant:
	var rsm := RsmFile.decode(_make_rsm_14())
	if rsm == null or rsm.nodes.size() != 1 or rsm.textures[0] != "wall.bmp":
		return "decode failed"
	var n: Dictionary = rsm.nodes[0]
	if n.vertices.size() != 3 or n.uvs.size() != 3 or n.faces.size() != 8:
		return "node counts wrong"
	var builder := RsmMeshBuilder.new()
	builder.rsm = rsm
	var mesh := builder.build()
	if mesh.get_surface_count() != 1:
		return "expected 1 surface"
	# Centring: x centred (-5..5), RO max y moved to 0 (model sits on the ground).
	var aabb := mesh.get_aabb()
	if not aabb.position.is_equal_approx(Vector3(-5, -20, 0)) or not Vector2(aabb.size.x, aabb.size.y).is_equal_approx(Vector2(10, 20)):
		return "centring wrong: %s" % aabb
	# In Godot space (RO_TO_GODOT) the model must rise upward from y = 0.
	var g := Transform3D(RsmMeshBuilder.RO_TO_GODOT, Vector3.ZERO) * aabb
	if not is_equal_approx(g.position.y, 0.0) or not is_equal_approx(g.end.y, 20.0):
		return "not upright in Godot space: %s" % g
	return true
