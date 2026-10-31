@tool
class_name MeshMerger
extends RefCounted
## Draw-call reduction for primitive-built scenes (Compatibility renderer: web, Android).
##
## Every mesh surface is a draw call, and the moon's shadow pass draws every caster again.
## Measured on Godot 4.7.1 (Phase 3e): omni lights WITHOUT shadows cost no extra draw
## calls (they are shaded in the same pass, up to 8 per mesh), so cells only need to
## keep each mesh within that light limit. Tools:
##  - merge_static(): bakes static meshes into one mesh per (material family, cell);
##    colour variants of one material share a palette material (vertex colours).
##  - build_shadow_proxies(): depth-only stand-ins for the moon's shadow pass.
##  - merge_grass_chunks() / merge_children_by_cell(): fewer grass and ground chunks.
##  - bake_character(): bakes the pieces under each animated pivot into one
##    vertex-coloured mesh (one matte + one metal material for all characters).
## Original nodes are hidden, not freed, so their colliders keep working.

const SKIP_META := "no_merge"
## ShaderMaterial splats store their variation seed here; it is baked into
## vertex colour (COLOR.r) because merged meshes share one instance.
const SEED_META := "seed01"
## Merge cells by cull distance (every material+cell is a draw call). A merged chunk is
## culled by its centre, so a bigger cell moves each piece's cut-off by up to half a cell:
## only where that cut-off sits deep in the fog (>= FOG_RANGE m, or never culled) do cells
## grow to FAR_CELL; scenery culled at MID_RANGE..FOG_RANGE (silhouettes still show
## against the sky there) uses MID_CELL, near-culled detail NEAR_CELL. Lights stay within
## budget (merge_static splits; tools/bake_world.gd checks).
const FOG_RANGE := 130.0
const MID_RANGE := 90.0
const FAR_CELL := 160.0
const MID_CELL := 40.0
const NEAR_CELL := 20.0
## Omni lights a merged mesh may carry: the Compatibility renderer's per-mesh limit (8,
## rendering/limits/opengl/max_lights_per_object) minus room for the moving ones (the
## player's lantern and a pickup glint).
const LIGHT_BUDGET := 6

static var _character_matte: StandardMaterial3D
static var _character_metal: StandardMaterial3D
## Palette families (see palette_family): signature -> shared material, and the per-source cache.
static var _families: Dictionary = {}
static var _family_of: Dictionary = {}


## range_end > 0 culls merged chunks beyond that distance (fog hides them anyway).
## centered: cells are centred on root's origin instead of starting there (a compact
## site around its origin, like the Outer Ward, then fits one cell).
## A cell whose merged box would be reached by more than LIGHT_BUDGET of root's omni
## lights is split in halves until it fits (or is NEAR_CELL small).
## shadow_cell: a merged chunk casts a shadow like the first piece of its material in a
## shadow_cell square did when chunks were that small (the merge used to copy the first
## piece's setting); every piece keeps that setting so shadows stay as they were, and a
## lone object-space triplanar piece of that grouping stays unmerged (texture frame).
static func merge_static(root: Node3D, cell_size: float = 20.0, range_end: float = 0.0, centered := false,
		shadow_cell := NEAR_CELL) -> int:
	var groups: Dictionary = {}
	var inverse_root := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var first_cast: Dictionary = {}
	var legacy_count: Dictionary = {}
	var pieces: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _mergeable(mi):
			continue
		var xf := _relative_transform(root, mi, inverse_root)
		var shadow_key := "%d|%s" % [mi.material_override.get_instance_id(), Vector3i((xf.origin / shadow_cell).floor())]
		if not first_cast.has(shadow_key):
			first_cast[shadow_key] = mi.cast_shadow
		legacy_count[shadow_key] = int(legacy_count.get(shadow_key, 0)) + 1
		pieces.append([mi, xf, shadow_key])
	for piece in pieces:
		var mi: MeshInstance3D = piece[0]
		var xf: Transform3D = piece[1]
		var shadow_key: String = piece[2]
		# Object-space triplanar texturing follows the mesh's own frame: a piece the
		# shadow_cell grouping left alone keeps it (merging would slide its texture).
		if int(legacy_count[shadow_key]) < 2 and _object_triplanar(mi.material_override) \
				and not xf.is_equal_approx(Transform3D.IDENTITY):
			continue
		var cast: int = first_cast[shadow_key]
		var cell := Vector3i((xf.origin / cell_size + (Vector3.ONE * 0.5 if centered else Vector3.ZERO)).floor())
		var family := palette_family(mi.material_override)
		var material: Material = family[0] if family else mi.material_override
		var key := "%d|%d|%s" % [material.get_instance_id(), cast, cell]
		if not groups.has(key):
			groups[key] = {"material": material, "cast": cast, "members": []}
		var seed_color := Color(float(mi.get_meta(SEED_META, 1.0)), 1.0, 1.0)
		(groups[key]["members"] as Array).append([mi, xf, family[1] if family else seed_color])
	var lights: Array = []
	for l in root.find_children("*", "OmniLight3D", true, false):
		lights.append([_relative_transform(root, l as Node3D, inverse_root).origin, (l as OmniLight3D).omni_range])
	var merged := 0
	for key in groups:
		var g: Dictionary = groups[key]
		for members in _split_for_lights(g["members"], lights, cell_size):
			if (members as Array).size() < 2:
				continue
			var acc := _new_acc()
			for m in members:
				_append(acc, (m[0] as MeshInstance3D).mesh, m[1], m[2])
			var out := MeshInstance3D.new()
			out.name = "Merged"
			out.mesh = _commit(acc)
			out.material_override = g["material"]
			out.cast_shadow = g["cast"] as GeometryInstance3D.ShadowCastingSetting
			out.visibility_range_end = _spread_range(out.mesh, members, range_end)
			root.add_child(out)
			for m in members:
				(m[0] as MeshInstance3D).visible = false
				merged += 1
	return merged


## A merged chunk is culled from its own centre: extend its range so every member stays
## visible as far as it did on its own (members culled from their own centres).
static func _spread_range(mesh: Mesh, members: Array, range_end: float) -> float:
	if range_end <= 0.0:
		return 0.0
	var mid := mesh.get_aabb().get_center()
	var spread := 0.0
	for m in members:
		var mi := m[0] as MeshInstance3D
		var centre: Vector3 = (m[1] as Transform3D) * mi.mesh.get_aabb().get_center()
		spread = maxf(spread, mid.distance_to(centre))
	return range_end + spread + 0.5


## [[MeshInstance3D, Transform3D, Color], ...] -> list of member lists whose merged box
## each reaches at most LIGHT_BUDGET lights ([origin, range] pairs), halving the longer
## side of the box until it fits or is no wider than NEAR_CELL.
static func _split_for_lights(members: Array, lights: Array, size: float) -> Array:
	if lights.is_empty() or members.size() < 2:
		return [members]
	var box := AABB()
	for i in members.size():
		var b: AABB = (members[i][1] as Transform3D) * (members[i][0] as MeshInstance3D).get_aabb()
		box = b if i == 0 else box.merge(b)
	var touching := 0
	for l in lights:
		var p: Vector3 = l[0]
		if p.clamp(box.position, box.end).distance_to(p) < float(l[1]):
			touching += 1
	if touching <= LIGHT_BUDGET or size <= NEAR_CELL:
		return [members]
	var along_x := box.size.x >= box.size.z
	var mid := box.get_center()
	var low: Array = []
	var high: Array = []
	for m in members:
		var o: Vector3 = (m[1] as Transform3D).origin
		if (o.x if along_x else o.z) < (mid.x if along_x else mid.z):
			low.append(m)
		else:
			high.append(m)
	if low.is_empty() or high.is_empty():
		return [members]
	return _split_for_lights(low, lights, size * 0.5) + _split_for_lights(high, lights, size * 0.5)


## Shadow-only stand-ins: the depth of every static caster under `root` is merged into
## one SHADOWS_ONLY mesh per (cull mode, cull distance, `cell_size` square) - per material
## too for alpha-tested ones - and the originals stop casting. The moon's shadow pass then
## draws a handful of meshes instead of every chunk, with the same depth (same triangles).
## A caster with a cull distance joins only if, beyond that distance, its shadow could not
## reach `shadow_distance` (moon ~30 deg up: shadows reach 1.75x the height); its stand-in
## is culled late enough that it casts wherever the original did. Animated nodes (any
## scripted ancestor) and vertex-displacing shaders keep their own shadow.
static func build_shadow_proxies(root: Node3D, cell_size: float, shadow_distance: float) -> int:
	var groups: Dictionary = {}
	var casters: Array[MeshInstance3D] = []
	var inverse_root := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.visibility_range_begin > 0.0:
			continue
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var cull := _shadow_cull(mi)
		if cull < 0 or not _static_under(root, mi):
			continue
		var xf := inverse_root * mi.global_transform
		var box := xf * mi.get_aabb()
		var range_end := mi.visibility_range_end
		if range_end > 0.0:
			var reach := box.size.y * 1.75 + maxf(box.size.x, box.size.z) * 0.5
			if range_end - reach < shadow_distance:
				continue
		var mat := mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		var alpha_tested := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			cull = BaseMaterial3D.CULL_DISABLED
		var center := box.get_center()
		casters.append(mi)
		if not alpha_tested:
			# Opaque depth is split per triangle into cells: a big merged chunk would
			# otherwise give its stand-in (and the moon's shadow depth range) its full size.
			_append_depth_cells(groups, "%d|%d|0" % [cull, roundi(range_end * 10.0)],
				{"cull": cull, "range": range_end, "alpha": null}, mi.mesh, xf, cell_size, center)
			continue
		var key := "%d|%d|%d|%d|%d" % [cull, roundi(range_end * 10.0), mat.get_instance_id(),
			floori(center.x / cell_size), floori(center.z / cell_size)]
		if not groups.has(key):
			groups[key] = {"cull": cull, "range": range_end, "alpha": mat, "acc": _new_acc(), "centers": []}
		var g: Dictionary = groups[key]
		_append(g["acc"], mi.mesh, xf, Color.WHITE)
		(g["centers"] as Array).append(center)
	var materials: Dictionary = {}
	var count := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var cull: int = g["cull"]
		var mat: BaseMaterial3D = g["alpha"]
		if mat != null:
			if mat.cull_mode != cull:
				mat = mat.duplicate() as BaseMaterial3D
				mat.cull_mode = cull as BaseMaterial3D.CullMode
		else:
			if not materials.has(cull):
				var plain := StandardMaterial3D.new()
				plain.cull_mode = cull as BaseMaterial3D.CullMode
				materials[cull] = plain
			mat = materials[cull]
		var mesh: ArrayMesh
		if g["alpha"] != null:
			mesh = _commit(g["acc"])
		else:
			var acc: Dictionary = g["acc"]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = acc["v"]
			arrays[Mesh.ARRAY_INDEX] = acc["i"]
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var out := MeshInstance3D.new()
		out.name = "ShadowProxy"
		out.mesh = mesh
		out.material_override = mat
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		out.set_meta(SKIP_META, true)
		var range_end: float = g["range"]
		if range_end > 0.0:
			# Culled from its own centre: reach every original's centre distance.
			var mid := mesh.get_aabb().get_center()
			var spread := 0.0
			for c in g["centers"]:
				spread = maxf(spread, mid.distance_to(c as Vector3))
			out.visibility_range_end = range_end + spread + 0.5
		root.add_child(out)
	for mi in casters:
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			mi.visible = false
			mi.mesh = null
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return casters.size()


## Grass draw calls: joins the chunk MeshInstance3Ds under `group` (children with a
## custom_aabb, one per small cell, culled at their visibility_range_end) into chunks
## `factor` times wider. Each vertex keeps its old chunk's cull centre in CUSTOM0 and the
## material's `chunk_range` uniform hides it exactly where its old chunk was culled, so
## the field looks the same (meadow_grass / thornfield_wheat shaders).
static func merge_grass_chunks(group: Node3D, chunk_size: float, factor: int) -> int:
	var supers: Dictionary = {}
	var range_end := 0.0
	for child in group.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.material_override is ShaderMaterial:
			continue
		range_end = mi.visibility_range_end
		var cell := Vector2i(floori(mi.position.x / (chunk_size * factor) + 0.001), floori(mi.position.z / (chunk_size * factor) + 0.001))
		if not supers.has(cell):
			supers[cell] = []
		(supers[cell] as Array).append(mi)
	var made := 0
	for cell in supers:
		var parts: Array = supers[cell]
		var first := parts[0] as MeshInstance3D
		var origin := first.position
		var v_out := PackedVector3Array()
		var n_out := PackedVector3Array()
		var uv_out := PackedVector2Array()
		var c_out := PackedColorArray()
		var cull_out := PackedFloat32Array()
		var i_out := PackedInt32Array()
		var box := AABB()
		var centers: Array[Vector3] = []
		for k in parts.size():
			var mi := parts[k] as MeshInstance3D
			var offset := mi.position - origin
			var own: AABB = mi.mesh.custom_aabb if mi.mesh.custom_aabb.size != Vector3.ZERO else mi.mesh.get_aabb()
			var center: Vector3 = mi.position + own.get_center()
			centers.append(center)
			box = AABB(own.position + offset, own.size) if k == 0 else box.merge(AABB(own.position + offset, own.size))
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var base := v_out.size()
			for vtx in verts:
				v_out.append(vtx + offset)
				cull_out.append_array(PackedFloat32Array([center.x, center.y, center.z]))
			n_out.append_array(arrays[Mesh.ARRAY_NORMAL])
			uv_out.append_array(arrays[Mesh.ARRAY_TEX_UV])
			c_out.append_array(arrays[Mesh.ARRAY_COLOR])
			for idx in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
				i_out.append(base + idx)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v_out
		arrays[Mesh.ARRAY_NORMAL] = n_out
		arrays[Mesh.ARRAY_TEX_UV] = uv_out
		arrays[Mesh.ARRAY_COLOR] = c_out
		arrays[Mesh.ARRAY_CUSTOM0] = cull_out
		arrays[Mesh.ARRAY_INDEX] = i_out
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.custom_aabb = box
		var mat := first.material_override as ShaderMaterial
		mat.set_shader_parameter("chunk_range", range_end)
		var out := MeshInstance3D.new()
		out.name = "Chunk_%d_%d" % [cell.x, cell.y]
		out.mesh = mesh
		out.material_override = mat
		out.position = origin
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Drawn while any of its old chunks would have been.
		var mid := origin + box.get_center()
		var spread := 0.0
		for c in centers:
			spread = maxf(spread, mid.distance_to(c))
		out.visibility_range_end = range_end + spread + 0.5
		out.set_meta(SKIP_META, true)
		for mi in parts:
			group.remove_child(mi)
			(mi as Node).free()
		group.add_child(out)
		made += 1
	return made


## Joins the MeshInstance3D children of `parent` that share a material into one mesh
## per `cell_size` square, unless the joined box would be touched by more than
## `light_budget` of `lights` (OmniLight3D); those squares keep their pieces. Children
## must sit at the identity (vertices in parent space, like the terrain chunks).
static func merge_children_by_cell(parent: Node3D, cell_size: float, lights: Array, light_budget: int) -> int:
	var groups: Dictionary = {}
	for child in parent.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible or mi.transform != Transform3D.IDENTITY:
			continue
		var center := mi.get_aabb().get_center()
		var key := "%d|%d|%d|%d" % [mi.material_override.get_instance_id() if mi.material_override else 0,
			roundi(mi.visibility_range_end * 10.0), floori(center.x / cell_size), floori(center.z / cell_size)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(mi)
	var merged := 0
	for key in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var box := (parts[0] as MeshInstance3D).get_aabb()
		for mi in parts:
			box = box.merge((mi as MeshInstance3D).get_aabb())
		if _lights_touching(parent, box, lights) > light_budget:
			continue
		var first := parts[0] as MeshInstance3D
		var acc := _new_acc()
		for mi in parts:
			_append(acc, (mi as MeshInstance3D).mesh, Transform3D.IDENTITY, Color.WHITE, true)
		var out := MeshInstance3D.new()
		out.name = first.name
		out.mesh = _commit(acc)
		out.material_override = first.material_override
		out.cast_shadow = first.cast_shadow
		out.visibility_range_end = first.visibility_range_end
		for mi in parts:
			parent.remove_child(mi)
			(mi as Node).free()
		parent.add_child(out)
		merged += parts.size()
	return merged


## Omni lights whose sphere reaches `box` (in `space`'s coordinates).
static func _lights_touching(space: Node3D, box: AABB, lights: Array) -> int:
	var to_local := space.global_transform.affine_inverse()
	var n := 0
	for l in lights:
		var light := l as OmniLight3D
		var p := to_local * light.global_position
		if p.clamp(box.position, box.end).distance_to(p) < light.omni_range:
			n += 1
	return n


## Merge cell size for scenery culled at `range_end` (0 = never culled).
static func cell_for(range_end: float) -> float:
	if range_end <= 0.0 or range_end >= FOG_RANGE:
		return FAR_CELL
	return MID_CELL if range_end >= MID_RANGE else NEAR_CELL


static func bake_character(root: Node3D) -> void:
	if _character_matte == null:
		_character_matte = StandardMaterial3D.new()
		_character_matte.vertex_color_use_as_albedo = true
		_character_matte.roughness = 0.85
		_character_metal = StandardMaterial3D.new()
		_character_metal.vertex_color_use_as_albedo = true
		_character_metal.metallic = 0.75
		_character_metal.roughness = 0.35
	var pivots: Array[Node3D] = [root]
	for node in root.find_children("*", "Node3D", true, false):
		if not node is MeshInstance3D:
			pivots.append(node as Node3D)
	for pivot in pivots:
		var accs := {"matte": _new_acc(), "metal": _new_acc()}
		var used := {"matte": [], "metal": []}
		for child in pivot.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.material_override is StandardMaterial3D:
				continue
			var mat := mi.material_override as StandardMaterial3D
			var kind := "metal" if mat.metallic > 0.3 else "matte"
			var color: Color = mat.get_meta("swatch", mat.albedo_color)
			_append(accs[kind], mi.mesh, mi.transform, color)
			(used[kind] as Array).append(mi)
		for kind in ["matte", "metal"]:
			if (used[kind] as Array).is_empty():
				continue
			var out := MeshInstance3D.new()
			out.name = "Baked_" + kind
			out.mesh = _commit(accs[kind])
			out.material_override = _character_metal if kind == "metal" else _character_matte
			pivot.add_child(out)
			for mi in used[kind]:
				(mi as MeshInstance3D).queue_free()


## Opaque StandardMaterial3Ds that differ only in albedo colour share one material that
## reads the colour from the vertices (COLOR, sRGB like albedo_color), so one merged mesh
## draws them all. Returns [family material, vertex colour], or [] when the material
## must stay as it is (vertex colours already in use, alpha, colour outside 0..1).
static func palette_family(mat: Material) -> Array:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return []
	var id := sm.get_instance_id()
	if _family_of.has(id):
		return _family_of[id]
	var out: Array = []
	var c := sm.albedo_color
	if not sm.vertex_color_use_as_albedo and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and sm.next_pass == null and is_equal_approx(c.a, 1.0) and c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0:
		var sig := _signature(sm)
		if not _families.has(sig):
			var fam := sm.duplicate() as StandardMaterial3D
			fam.resource_name = "palette"
			fam.albedo_color = Color.WHITE
			fam.vertex_color_use_as_albedo = true
			fam.vertex_color_is_srgb = true
			_families[sig] = fam
		out = [_families[sig], Color(c.r, c.g, c.b, 1.0)]
	_family_of[id] = out
	return out


## Every stored property except the albedo colour (shared sub-resources by identity).
static func _signature(sm: StandardMaterial3D) -> String:
	var parts := PackedStringArray()
	for prop in sm.get_property_list():
		var prop_name: String = prop["name"]
		if not (int(prop["usage"]) & PROPERTY_USAGE_STORAGE) or prop_name in ["albedo_color", "resource_name", "resource_path", "script"]:
			continue
		var v: Variant = sm.get(prop_name)
		if v is Object:
			v = (v as Object).get_instance_id()
		parts.append("%s=%s" % [prop_name, var_to_str(v)])
	return "|".join(parts)


static func _object_triplanar(mat: Material) -> bool:
	var bm := mat as BaseMaterial3D
	return bm != null and ((bm.uv1_triplanar and not bm.uv1_world_triplanar) or (bm.uv2_triplanar and not bm.uv2_world_triplanar))


static func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.visible or mi.has_meta(SKIP_META):
		return false
	if mi.material_override is StandardMaterial3D:
		return true
	return mi.material_override is ShaderMaterial and mi.has_meta(SEED_META)


## Cull mode the shadow pass uses for this instance, or -1 if its depth is not a plain
## function of the mesh and material (alpha blend, triplanar alpha test, grown or
## billboarded vertices, vertex shaders).
static func _shadow_cull(mi: MeshInstance3D) -> int:
	var array_mesh := mi.mesh as ArrayMesh
	if array_mesh:
		for s in array_mesh.get_surface_count():
			if array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return -1
	var mat := mi.material_override
	if mat == null and mi.mesh.get_surface_count() == 1:
		mat = mi.mesh.surface_get_material(0)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		var alpha_ok := sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
				or (sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not sm.uv1_triplanar)
		if not alpha_ok or sm.grow or sm.use_point_size \
				or sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or sm.heightmap_enabled \
				or sm.next_pass != null:
			return -1
		return sm.cull_mode
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).next_pass == null:
		var code := (mat as ShaderMaterial).shader.code
		var writes_vertex := RegEx.create_from_string("VERTEX(\\.[xyz]+)?\\s*[-+*/]?=[^=]").search(code)
		if writes_vertex or code.contains("discard") or code.contains("ALPHA") or code.contains("skip_vertex_transform") \
				or code.contains("world_vertex_coords") or code.contains("POSITION"):
			return -1
		if code.contains("cull_disabled"):
			return BaseMaterial3D.CULL_DISABLED
		if code.contains("cull_front"):
			return BaseMaterial3D.CULL_FRONT
		return BaseMaterial3D.CULL_BACK
	return -1


## True when nothing between `root` and `node` (inclusive) runs a script, i.e. it never moves.
static func _static_under(root: Node, node: Node) -> bool:
	var n := node
	while n != null and n != root:
		if n.get_script() != null or (n is PhysicsBody3D and not (n is StaticBody3D)):
			return false
		n = n.get_parent()
	return true


## Appends `mesh`'s triangles (transformed by `xf`) to depth groups keyed
## "<prefix>|cell x|cell z" by triangle centroid; `info` seeds a new group. Each group
## remembers the centres of the instances that fed it (`center`).
static func _append_depth_cells(groups: Dictionary, prefix: String, info: Dictionary, mesh: Mesh,
		xf: Transform3D, cell_size: float, center: Vector3) -> void:
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var verts := PackedVector3Array()
		verts.resize(src.size())
		for k in src.size():
			verts[k] = xf * src[k]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(verts.size())
			for k in verts.size():
				indices[k] = k
		var remaps: Dictionary = {}
		for t in range(0, indices.size() - 2, 3):
			var a := verts[indices[t]]
			var b := verts[indices[t + 1]]
			var c := verts[indices[t + 2]]
			var mid := (a + b + c) / 3.0
			var key := "%s|%d|%d" % [prefix, floori(mid.x / cell_size), floori(mid.z / cell_size)]
			if not groups.has(key):
				var g := info.duplicate()
				g["acc"] = _new_depth_acc()
				g["centers"] = []
				groups[key] = g
			var group: Dictionary = groups[key]
			if not remaps.has(key):
				remaps[key] = {}
				(group["centers"] as Array).append(center)
			var remap: Dictionary = remaps[key]
			var v_out: PackedVector3Array = group["acc"]["v"]
			var i_out: PackedInt32Array = group["acc"]["i"]
			group["acc"]["v"] = null
			group["acc"]["i"] = null
			for k in 3:
				var idx := indices[t + k]
				if not remap.has(idx):
					remap[idx] = v_out.size()
					v_out.append(verts[idx])
				i_out.append(int(remap[idx]))
			group["acc"]["v"] = v_out
			group["acc"]["i"] = i_out


## Depth-only geometry: positions and indices (normal bias is applied by the receiver).
static func _new_depth_acc() -> Dictionary:
	return {"v": PackedVector3Array(), "i": PackedInt32Array()}


static func _relative_transform(root: Node3D, node: Node3D, inverse_root: Transform3D) -> Transform3D:
	if node.is_inside_tree() and root.is_inside_tree():
		return inverse_root * node.global_transform
	var xf := node.transform
	var p := node.get_parent() as Node3D
	while p and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


static func _new_acc() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}


## Appends `mesh` transformed by `xf`; every vertex gets `color`, or its own colour when
## `keep_colors` (and the mesh has them).
static func _append(acc: Dictionary, mesh: Mesh, xf: Transform3D, color: Color, keep_colors := false) -> void:
	var normal_basis := xf.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if keep_colors and arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		# Take the arrays out of the dictionary first: packed arrays are
		# copy-on-write, and a second reference would copy them on every append.
		var v_out: PackedVector3Array = acc["v"]
		var n_out: PackedVector3Array = acc["n"]
		var uv_out: PackedVector2Array = acc["uv"]
		var c_out: PackedColorArray = acc["c"]
		var i_out: PackedInt32Array = acc["i"]
		for key in ["v", "n", "uv", "c", "i"]:
			acc[key] = null
		var base := v_out.size()
		for k in verts.size():
			v_out.append(xf * verts[k])
			n_out.append((normal_basis * normals[k]).normalized() if k < normals.size() else Vector3.UP)
			uv_out.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
			c_out.append(colors[k] if k < colors.size() else color)
		if indices.is_empty():
			for k in verts.size():
				i_out.append(base + k)
		else:
			for idx in indices:
				i_out.append(base + idx)
		acc["v"] = v_out
		acc["n"] = n_out
		acc["uv"] = uv_out
		acc["c"] = c_out
		acc["i"] = i_out


static func _commit(acc: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc["v"]
	arrays[Mesh.ARRAY_NORMAL] = acc["n"]
	arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
	arrays[Mesh.ARRAY_COLOR] = acc["c"]
	arrays[Mesh.ARRAY_INDEX] = acc["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
