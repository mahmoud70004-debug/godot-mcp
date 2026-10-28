"""Armature helpers. Bones are built with a fixed roll so every bone's local X is the
character's +X (its left); rotation order ZYX (sideways first, then forward). Consequences used by the pose helpers:
  - upward bones (spine, neck, head): +X rotation bends forward
  - downward bones (arms, legs, cloak): +X rotation swings backward, -X forward;
    +Z moves the tail towards -X (inwards for a left limb)
  - forward bones (feet): +X rotation points the toe down
"""
import math

import bpy
from mathutils import Euler, Vector


def build_armature(name, bones, collection=None):
    """bones: list of (name, head, tail, parent_or_None). Returns the armature object."""
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    (collection or bpy.context.scene.collection).objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, tail, parent in bones:
        eb = arm.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        d = Vector(tail) - Vector(head)
        if abs(d.z) >= max(abs(d.x), abs(d.y)):
            eb.align_roll((0, -1, 0) if d.z > 0 else (0, 1, 0))
        else:
            eb.align_roll((0, 0, -1))
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in obj.pose.bones:
        # Z (sideways) is applied first, then Y (twist), then X (forward): a raised arm
        # keeps its outward offset instead of crossing over the head.
        pb.rotation_mode = "ZYX"
    return obj


def parent_to_bone(obj, rig, bone):
    """Rigidly attach obj (modelled in rest-pose world space) to a bone."""
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    pb = rig.pose.bones[bone]
    # Bone parenting is relative to the bone tail; compensate so the object stays put.
    bone_mat = rig.matrix_world @ pb.bone.matrix_local
    tail_offset = Vector((0, pb.bone.length, 0))
    from mathutils import Matrix
    obj.matrix_parent_inverse = (bone_mat @ Matrix.Translation(tail_offset)).inverted()
    obj.matrix_world = mw


def skin_by_height(obj, rig, bands):
    """Soft-skin cloth to bones by world height. bands: list of (bone, z) from top to bottom;
    each vertex is weighted between the two bands around its height."""
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    mod = obj.modifiers.new("armature", "ARMATURE")
    mod.object = rig
    groups = {b: obj.vertex_groups.new(name=b) for b, _ in bands}
    mw = obj.matrix_world
    for v in obj.data.vertices:
        z = (mw @ v.co).z
        if z >= bands[0][1]:
            groups[bands[0][0]].add([v.index], 1.0, "REPLACE")
            continue
        if z <= bands[-1][1]:
            groups[bands[-1][0]].add([v.index], 1.0, "REPLACE")
            continue
        for (b0, z0), (b1, z1) in zip(bands, bands[1:]):
            if z1 <= z <= z0:
                t = (z0 - z) / max(z0 - z1, 1e-6)
                t = t * t * (3 - 2 * t)
                groups[b0].add([v.index], 1.0 - t, "REPLACE")
                groups[b1].add([v.index], t, "REPLACE")
                break


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_euler = Euler((0, 0, 0))
        pb.location = Vector((0, 0, 0))


def rot(rig, bone, x=0.0, y=0.0, z=0.0):
    """Add a rotation (degrees) to a pose bone."""
    pb = rig.pose.bones[bone]
    e = pb.rotation_euler
    pb.rotation_euler = Euler((e.x + math.radians(x), e.y + math.radians(y), e.z + math.radians(z)))


def arm(rig, side, forward=0.0, out=0.0, twist=0.0, elbow=0.0, wrist=0.0):
    """side 'L'/'R'. forward: swing the upper arm forward (deg); out: raise sideways;
    elbow: bend forward; wrist: bend the hand forward."""
    s = 1.0 if side == "L" else -1.0
    rot(rig, "upper_arm." + side, x=-forward, y=twist * s, z=-out * s)
    rot(rig, "forearm." + side, x=-elbow)
    rot(rig, "hand." + side, x=-wrist)


def leg(rig, side, forward=0.0, out=0.0, knee=0.0, ankle=0.0):
    """forward: swing the thigh forward; knee: bend (positive); ankle: toe down (positive)."""
    s = 1.0 if side == "L" else -1.0
    rot(rig, "thigh." + side, x=-forward, z=-out * s)
    rot(rig, "shin." + side, x=knee)
    rot(rig, "foot." + side, x=ankle)


def lerp_pose(a, b, t):
    """Blend two pose dicts {key: float} (missing keys are 0)."""
    keys = set(a) | set(b)
    return {k: a.get(k, 0.0) + (b.get(k, 0.0) - a.get(k, 0.0)) * t for k in keys}


def sample_keys(keys, t, loop):
    """keys: list of (time, pose_dict), times ascending in [0, 1]. Smooth (cosine-eased)
    interpolation; loops wrap from the last key to the first."""
    if loop:
        t = t % 1.0
        keys = keys + [(1.0, keys[0][1])]
    t = min(max(t, keys[0][0]), keys[-1][0])
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            u = 0.5 - 0.5 * math.cos(math.pi * u)
            return lerp_pose(p0, p1, u)
    return dict(keys[-1][1])
