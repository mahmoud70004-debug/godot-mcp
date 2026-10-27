class_name ItemPickup
extends Interactable
## A carried item lying in the world. Builds a placeholder model from the
## item's category until real art exists, plus a faint "item glint" light.

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
		add_child(_visual)
	var glint := OmniLight3D.new()
	glint.light_color = item.tint.lerp(Color(0.9, 0.85, 0.6), 0.5) if item else Color.WHITE
	glint.light_energy = 0.5
	glint.omni_range = 1.4
	glint.shadow_enabled = false
	glint.position = Vector3(0, 0.25, 0)
	add_child(glint)


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
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item.tint
	mat.roughness = 0.7
	match item.category:
		ItemData.Category.LORE:
			var paper := BoxMesh.new()
			paper.size = Vector3(0.22, 0.01, 0.3)
			mesh.mesh = paper
			mesh.rotation = Vector3(0.25, 0.4, 0.1)
		ItemData.Category.CONSUMABLE:
			var jar := CylinderMesh.new()
			jar.top_radius = 0.05
			jar.bottom_radius = 0.07
			jar.height = 0.16
			jar.radial_segments = 6
			jar.rings = 1
			mesh.mesh = jar
			mat.emission_enabled = true
			mat.emission = item.tint
			mat.emission_energy_multiplier = 0.6
		ItemData.Category.RELIC:
			var orb := SphereMesh.new()
			orb.radius = 0.07
			orb.height = 0.14
			orb.radial_segments = 8
			orb.rings = 4
			mesh.mesh = orb
			mat.metallic = 0.6
			mat.roughness = 0.2
			mat.emission_enabled = true
			mat.emission = item.tint
			mat.emission_energy_multiplier = 1.2
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.12, 0.12, 0.12)
			mesh.mesh = box
	mesh.material_override = mat
	root.add_child(mesh)
	return root
