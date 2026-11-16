class_name ItemPickup
extends Interactable
## A carried item lying in the world: a small worn object built from the item's category (scroll,
## flask, amulet, pouch) with a faint glimmer, until real art exists.

@export var item: ItemData
@export_range(1, 99) var quantity := 1
@export var hover := true

var _visual: Node3D
var _time := 0.0


func _ready() -> void:
	super()
	_time = randf() * TAU
	_visual = _build_visual()
	if _visual:
		# Bobs in _process: interpolating it against physics ticks would make it stutter.
		_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_visual)


func get_prompt() -> String:
	return "Take %s" % item.display_name if item else prompt_text


func interact(by: Node) -> void:
	if item == null:
		return
	var leftover := GameState.inventory.add_item(item, quantity)
	var taken := quantity - leftover
	if taken <= 0:
		Events.show_message("You cannot carry any more.")
		return
	Events.item_picked_up.emit(item, taken)
	if item is LoreData:
		GameState.discover_lore(item as LoreData)
	super(by)
	if leftover > 0:
		quantity = leftover
	else:
		queue_free()


func _process(delta: float) -> void:
	if not hover or _visual == null:
		return
	_time += delta
	_visual.position.y = sin(_time * 1.6) * 0.04
	_visual.rotation.y += delta * 0.6


func _build_visual() -> Node3D:
	if item == null:
		return null
	if item is WeaponData:
		var model := WeaponModelBuilder.build(item as WeaponData)
		var holder := Node3D.new()
		model.rotation = Vector3(0, 0, PI * 0.5)
		model.position = Vector3(0.45, 0, 0)
		holder.add_child(model)
		return holder
	var root := Node3D.new()
	# V24: small worn objects (a scroll, a flask, an amulet, a pouch), matte and dark like the rest of
	# the world, plus a faint glimmer: no flat bright square. The tint only leans on the colours.
	match item.category:
		ItemData.Category.LORE:
			_scroll(root)
		ItemData.Category.CONSUMABLE:
			_flask(root)
		ItemData.Category.RELIC:
			_amulet(root)
		_:
			_pouch(root)
	root.add_child(_glimmer())
	return root


func _part(parent: Node3D, mesh: Mesh, colour: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = item.tint
		mat.emission_energy_multiplier = glow
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A rolled scroll lying down, a dark ribbon round it.
func _scroll(root: Node3D) -> void:
	var paper := Color(0.42, 0.37, 0.27).lerp(item.tint, 0.15)
	var roll := CylinderMesh.new()
	roll.top_radius = 0.032
	roll.bottom_radius = 0.032
	roll.height = 0.26
	roll.radial_segments = 8
	roll.rings = 1
	_part(root, roll, paper, Vector3.ZERO, Vector3(0, 0.5, PI * 0.5))
	var ends := CylinderMesh.new()
	ends.top_radius = 0.04
	ends.bottom_radius = 0.04
	ends.height = 0.02
	ends.radial_segments = 8
	ends.rings = 1
	var dir := Vector3(cos(0.5) * 0.13, 0.0, -sin(0.5) * 0.13)
	_part(root, ends, paper.darkened(0.35), dir, Vector3(0, 0.5, PI * 0.5))
	_part(root, ends, paper.darkened(0.35), -dir, Vector3(0, 0.5, PI * 0.5))
	var band := CylinderMesh.new()
	band.top_radius = 0.037
	band.bottom_radius = 0.037
	band.height = 0.03
	band.radial_segments = 8
	band.rings = 1
	_part(root, band, Color(0.22, 0.05, 0.05), Vector3.ZERO, Vector3(0, 0.5, PI * 0.5))


## A small glass flask: body, neck, cork; the liquid glows faintly.
func _flask(root: Node3D) -> void:
	var body := CylinderMesh.new()
	body.top_radius = 0.035
	body.bottom_radius = 0.052
	body.height = 0.1
	body.radial_segments = 8
	body.rings = 1
	_part(root, body, item.tint.darkened(0.55), Vector3(0, 0.0, 0), Vector3.ZERO, 0.35)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.016
	neck.bottom_radius = 0.022
	neck.height = 0.06
	neck.radial_segments = 6
	neck.rings = 1
	_part(root, neck, Color(0.18, 0.2, 0.2), Vector3(0, 0.08, 0))
	var cork := CylinderMesh.new()
	cork.top_radius = 0.02
	cork.bottom_radius = 0.016
	cork.height = 0.03
	cork.radial_segments = 6
	cork.rings = 1
	_part(root, cork, Color(0.3, 0.2, 0.12), Vector3(0, 0.125, 0))


## A tarnished ring with a dim stone.
func _amulet(root: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.06
	ring.rings = 10
	ring.ring_segments = 6
	_part(root, ring, Color(0.3, 0.28, 0.22), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	var gem := SphereMesh.new()
	gem.radius = 0.028
	gem.height = 0.056
	gem.radial_segments = 6
	gem.rings = 3
	_part(root, gem, item.tint.darkened(0.4), Vector3(0, 0, 0), Vector3.ZERO, 0.8)


## A small leather pouch tied at the neck.
func _pouch(root: Node3D) -> void:
	var bag := SphereMesh.new()
	bag.radius = 0.07
	bag.height = 0.1
	bag.radial_segments = 8
	bag.rings = 4
	_part(root, bag, Color(0.24, 0.17, 0.11).lerp(item.tint, 0.12), Vector3(0, -0.01, 0))
	var tie := CylinderMesh.new()
	tie.top_radius = 0.03
	tie.bottom_radius = 0.016
	tie.height = 0.05
	tie.radial_segments = 6
	tie.rings = 1
	_part(root, tie, Color(0.16, 0.11, 0.07), Vector3(0, 0.065, 0))


## A faint soft glow that breathes slowly (a billboard, additive, no light node: lights cost draws).
func _glimmer() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.name = "Glimmer"
	mi.material_override = _glimmer_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 26.0
	mi.position = Vector3(0, 0.04, 0)
	return mi


static var _glimmer_mat: StandardMaterial3D


func _glimmer_material() -> StandardMaterial3D:
	if _glimmer_mat == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = tex
		mat.albedo_color = Color(0.5, 0.62, 0.8, 0.22)
		mat.disable_receive_shadows = true
		_glimmer_mat = mat
	return _glimmer_mat
