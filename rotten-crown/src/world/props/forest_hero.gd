class_name ForestHero
extends RefCounted
## The close-up trunks of the conifer styles (Aether): sculpted in Blender (tools/blender/trees/aether_trees.py --
## export), ~10k triangles with the furrows, buttress roots and moss cushions as real geometry, baked to
## data/trees/hero_<style>.res by tools/bake_aether_hero.sh. Drawn only within ForestTrees.HERO_END of
## the camera, over the coarse trunk of the same tree (which carries the middle distance).

static var _meshes: Dictionary = {}


## The close-up mesh of a style, or null (only the conifer styles have one).
static func mesh(style: int) -> Mesh:
	if not _meshes.has(style):
		var path := "res://data/trees".path_join("hero_%s.res" % String(ForestTrees.NAMES[style]).to_lower())
		var ok: bool = ForestTrees.CONIFER and style in ForestTrees.CONIFER_STYLES and ResourceLoader.exists(path)
		_meshes[style] = load(path) if ok else null
	return _meshes[style]


## Builds a hero mesh from the Blender export (build/aether/hero_<name>.json; tools/bake_aether_hero.gd).
## No material: the instance carries ForestTrees.material("hero"), so the resource stays plain data.
static func from_json(data: Dictionary) -> ArrayMesh:
	var acc := ForestTrees._acc()
	var v: Array = data["v"]
	var n: Array = data["n"]
	var c: Array = data["c"]
	for k in v.size() / 3:
		ForestTrees._vert(acc, Vector3(v[k * 3], v[k * 3 + 1], v[k * 3 + 2]), Vector3(n[k * 3], n[k * 3 + 1], n[k * 3 + 2]),
			Color(c[k * 3], c[k * 3 + 1], c[k * 3 + 2]), ForestTrees.SOLID_UV)
	var idx: PackedInt32Array = acc["i"]
	for i: float in data["i"]:
		idx.append(int(i))
	var out := ArrayMesh.new()
	ForestTrees._commit(out, acc, null)
	return out


## "Hero_<Style>" MultiMeshes of one hero cell (ForestBuilder: small cells, a drawn cell pays the vertices of
## every tree in it): same instance data as the Near mesh, the shader dissolves them out at HERO_END.
static func cell(node: Node3D, trees: Array, members: Array, reach: Array) -> void:
	var made := false
	for k in ForestBuilder.STYLES.size():
		var m := mesh(k)
		if m == null:
			continue
		var items: Array = []
		for i: int in members:
			var t: Array = trees[i]
			if int(t[3]) == k:
				var foot: Vector3 = t[0]
				var shift := fposmod(foot.x * 0.618 + foot.z * 0.377, 1.0)
				items.append([ForestBuilder._xf(t, node.position), Color(0.0, 0.0, float(t[8]), shift), t[7]])
		if items.is_empty():
			continue
		var mmi := ForestBuilder._multimesh(m, items, reach[k] as Vector2)
		mmi.name = "Hero_" + ForestBuilder.STYLE_NAMES[k]
		mmi.material_override = ForestTrees.material("hero")
		mmi.visibility_range_end = ForestTrees.HERO_END + ForestTrees.HERO_FADE + ForestBuilder._spread(items) + 2.0
		node.add_child(mmi)
		made = true
	if not made:
		node.queue_free()
