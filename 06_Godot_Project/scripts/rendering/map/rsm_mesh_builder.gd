class_name RsmMeshBuilder
extends RefCounted
## Bakes an RsmFile (first animation frame) into an ArrayMesh in RO model space.
##
## RO space: y grows downward. The caller converts to Godot space with
## RO_TO_GODOT (x, -y, -z), which is a proper rotation, so it can be folded
## into the instance transform.
##
## RSM 1.x (High confidence, matches roBrowser/BrowEdit):
##   node_world = parent_world * T(translation) * R(rot_key or angle/axis) * S(scale)
##   vertex     = centre * node_world * [T(position) unless single node] * offset * v
##   centre     = T(-bbox.center.x, -bbox.max.y, -bbox.center.z)
## RSM 2.x (Medium confidence, verify visually):
##   node_world = parent_world * T(pos_key or position) * R(rot_key) * S(scale_key)
##   vertex     = node_world * offset * v   (no centring)

const SHADER := preload("res://scripts/rendering/map/model.gdshader")
const RO_TO_GODOT := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))

var rsm: RsmFile
## Callable(texture_name_latin1: String) -> Texture2D
var texture_loader: Callable


func build() -> ArrayMesh:
	var by_name := {}
	for n in rsm.nodes:
		by_name[n.name] = n
	var world := {}  # node name -> Transform3D (hierarchical, RO space)
	for n in rsm.nodes:
		_world_of(n, by_name, world, 0)
	var v2 := rsm.version >= 0x0202
	var single := rsm.nodes.size() == 1
	# Per-node vertex transform before centring.
	var xf := {}
	for n in rsm.nodes:
		var t: Transform3D = world[n.name]
		if not v2 and not single:
			t = t * Transform3D(Basis.IDENTITY, n.position)
		xf[n.name] = t * Transform3D(n.offset, Vector3.ZERO)
	var centre := Transform3D.IDENTITY
	if not v2:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for n in rsm.nodes:
			var t: Transform3D = xf[n.name]
			for v in n.vertices:
				var p: Vector3 = t * v
				lo = lo.min(p)
				hi = hi.max(p)
		if lo.x != INF:
			var c := (lo + hi) / 2.0
			centre = Transform3D(Basis.IDENTITY, Vector3(-c.x, -hi.y, -c.z))
	var buckets := {}  # texture name -> {v, n, uv}
	for n in rsm.nodes:
		_emit_node(n, centre * xf[n.name], buckets)
	return _commit(buckets)


func _world_of(n: Dictionary, by_name: Dictionary, cache: Dictionary, depth: int) -> Transform3D:
	if cache.has(n.name):
		return cache[n.name]
	var parent_t := Transform3D.IDENTITY
	if n.parent != "" and n.parent != n.name and by_name.has(n.parent) and depth < 64:
		parent_t = _world_of(by_name[n.parent], by_name, cache, depth + 1)
	var basis := Basis.IDENTITY
	if n.rot_key != null:
		basis = Basis(n.rot_key.normalized())
	elif absf(n.rot_angle) > 0.0001 and n.rot_axis.length() > 0.0001:
		basis = Basis(n.rot_axis.normalized(), n.rot_angle)
	var s: Vector3 = n.scale_key if n.scale_key != null else n.scale
	basis = basis.scaled_local(s)
	var origin: Vector3
	if rsm.version >= 0x0202:
		origin = n.pos_key if n.pos_key != null else n.position
	else:
		origin = n.translation
	var t := parent_t * Transform3D(basis, origin)
	cache[n.name] = t
	return t


func _emit_node(n: Dictionary, t: Transform3D, buckets: Dictionary) -> void:
	var verts: PackedVector3Array = n.vertices
	var uvs: PackedVector2Array = n.uvs
	var faces: PackedInt32Array = n.faces
	var smooth: PackedInt32Array = n.smooth
	var tex_names: PackedStringArray = n.textures
	var world := PackedVector3Array()
	world.resize(verts.size())
	for i in verts.size():
		world[i] = t * verts[i]
	var face_count := faces.size() / 8
	var face_n := PackedVector3Array()
	face_n.resize(face_count)
	var vert_n := {}  # "vertex:group" -> summed normal (smooth shading)
	for f in face_count:
		var b := f * 8
		var a: int = faces[b]
		var c: int = faces[b + 1]
		var d: int = faces[b + 2]
		if a >= world.size() or c >= world.size() or d >= world.size():
			continue
		var nn := (world[c] - world[a]).cross(world[d] - world[a])
		face_n[f] = nn.normalized() if nn.length() > 0.000001 else Vector3.UP
		if rsm.shade_type == RsmFile.Shade.SMOOTH:
			for k in 3:
				var key := "%d:%d" % [faces[b + k], smooth[f]]
				vert_n[key] = vert_n.get(key, Vector3.ZERO) + nn
	for f in face_count:
		var b := f * 8
		var tex_idx: int = faces[b + 6]
		var tex_name := tex_names[tex_idx] if tex_idx < tex_names.size() else ""
		if not buckets.has(tex_name):
			buckets[tex_name] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}
		var bk: Dictionary = buckets[tex_name]
		var ok := true
		for k in 3:
			if faces[b + k] >= world.size() or faces[b + 3 + k] >= uvs.size():
				ok = false
		if not ok:
			continue
		# Typed locals share the stored packed arrays; an `as` cast would copy them.
		var bv: PackedVector3Array = bk.v
		var buv: PackedVector2Array = bk.uv
		var bn: PackedVector3Array = bk.n
		for k in 3:
			var vi: int = faces[b + k]
			bv.append(world[vi])
			buv.append(uvs[faces[b + 3 + k]])
			var nrm := face_n[f]
			if rsm.shade_type == RsmFile.Shade.SMOOTH:
				var s: Vector3 = vert_n.get("%d:%d" % [vi, smooth[f]], nrm)
				nrm = s.normalized() if s.length() > 0.000001 else nrm
			bn.append(nrm)


func _commit(buckets: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for tex_name in buckets:
		var bk: Dictionary = buckets[tex_name]
		if (bk.v as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bk.v
		arrays[Mesh.ARRAY_NORMAL] = bk.n
		arrays[Mesh.ARRAY_TEX_UV] = bk.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var tex: Texture2D = texture_loader.call(tex_name) if texture_loader.is_valid() and tex_name != "" else null
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("use_lighting", rsm.shade_type != RsmFile.Shade.NONE)
		mat.set_shader_parameter("alpha", rsm.alpha / 255.0)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## Instance transform for an RSW model entry, in Godot space.
## RO: T(pos + map half-extent) * Rz * Rx * Ry * S, positions relative to the map centre.
static func instance_transform(entry: Dictionary, gnd: GndFile) -> Transform3D:
	var half := Vector3(gnd.width * gnd.zoom / 2.0, 0.0, gnd.height * gnd.zoom / 2.0)
	var rot: Vector3 = entry.rot
	var b := Basis(Vector3(0, 0, 1), deg_to_rad(rot.z)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(rot.x)) \
		* Basis(Vector3(0, 1, 0), deg_to_rad(rot.y))
	b = b.scaled_local(entry.scale)
	var ro := Transform3D(b, entry.pos + half)
	return Transform3D(RO_TO_GODOT, Vector3.ZERO) * ro
