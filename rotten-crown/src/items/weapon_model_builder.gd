@tool
class_name WeaponModelBuilder
extends RefCounted
## Builds low-poly placeholder weapon models from primitive boxes.
## Models point "up" along +Y with the grip at the origin.

const WOOD := Color(0.24, 0.15, 0.09)
const LEATHER := Color(0.16, 0.1, 0.07)


static func build(weapon: WeaponData) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	if weapon == null:
		return root
	match weapon.weapon_type:
		WeaponData.WeaponType.AXE:
			_build_axe(root, weapon.tint)
		WeaponData.WeaponType.MACE:
			_build_mace(root, weapon.tint)
		_:
			_build_sword(root, weapon.tint)
	return root


static func _build_sword(root: Node3D, metal: Color) -> void:
	_part(root, Vector3(0.035, 0.2, 0.035), Vector3(0, 0.0, 0), LEATHER)
	_part(root, Vector3(0.06, 0.05, 0.05), Vector3(0, -0.12, 0), metal.darkened(0.3), 0.7)
	_part(root, Vector3(0.24, 0.035, 0.05), Vector3(0, 0.115, 0), metal.darkened(0.2), 0.7)
	_part(root, Vector3(0.055, 0.82, 0.014), Vector3(0, 0.54, 0), metal, 0.8)
	# Rust bloom near the tip.
	_part(root, Vector3(0.057, 0.12, 0.016), Vector3(0, 0.82, 0), metal.lerp(Color(0.35, 0.16, 0.06), 0.6), 0.3)


static func _build_axe(root: Node3D, metal: Color) -> void:
	_part(root, Vector3(0.04, 0.85, 0.04), Vector3(0, 0.3, 0), WOOD)
	_part(root, Vector3(0.05, 0.1, 0.05), Vector3(0, -0.12, 0), LEATHER)
	_part(root, Vector3(0.24, 0.17, 0.025), Vector3(0.11, 0.62, 0), metal, 0.7)
	_part(root, Vector3(0.04, 0.24, 0.03), Vector3(0.24, 0.62, 0), metal.lightened(0.15), 0.8)


static func _build_mace(root: Node3D, metal: Color) -> void:
	_part(root, Vector3(0.04, 0.7, 0.04), Vector3(0, 0.25, 0), WOOD)
	_part(root, Vector3(0.16, 0.18, 0.16), Vector3(0, 0.66, 0), metal, 0.7)
	_part(root, Vector3(0.22, 0.05, 0.05), Vector3(0, 0.66, 0), metal.darkened(0.2), 0.7)
	_part(root, Vector3(0.05, 0.05, 0.22), Vector3(0, 0.66, 0), metal.darkened(0.2), 0.7)


static func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.55
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
