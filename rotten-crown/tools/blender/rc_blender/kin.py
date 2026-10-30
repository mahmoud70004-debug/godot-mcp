"""Kinematics for non-humanoid sprite creatures (many legs, arches, roots).

A MatrixRig is a normal armature (rig.build_armature) whose bones are all parentless; each bone is
driven by a rigid motion M in character space (Z up, facing -Y, left = +X): "move everything that was
modelled on this bone in the rest pose by M". Forward kinematics and IK are done here in Python, so
there are no roll / bone-axis conventions to remember:
  - pivot(M_parent, p, x, y, z): rotate about the rest-pose point p, in the parent's character axes.
    +x bends an upward part forward (towards -Y), +y rolls it to its left (+X), +z turns it to its left.
  - ik2(hip, foot, a, b, pole): two-bone IK, knee pushed towards `pole`.
  - segment_motion(rest_a, rest_b, a, b): rigid motion taking a rest segment onto a posed one (no twist).
Meshes are modelled in the rest pose and attached with MatrixRig.attach (rigid, like creature.py).
"""
import math

import bmesh
from mathutils import Matrix, Vector

from . import geo, rig

I4 = Matrix.Identity(4)


def V(*p):
    return Vector(p[0] if len(p) == 1 else p)


def rot(x=0.0, y=0.0, z=0.0):
    """Degrees; X first, then Y, then Z (fixed character axes)."""
    return (Matrix.Rotation(math.radians(z), 4, "Z") @ Matrix.Rotation(math.radians(y), 4, "Y")
            @ Matrix.Rotation(math.radians(x), 4, "X"))


def pivot(parent, p, x=0.0, y=0.0, z=0.0):
    p = V(p)
    return parent @ Matrix.Translation(p) @ rot(x, y, z) @ Matrix.Translation(-p)


def move(parent, offset):
    return Matrix.Translation(V(offset)) @ parent


def segment_motion(rest_a, rest_b, a, b, scale_to_fit=False):
    """Rigid motion (no twist) taking rest segment rest_a->rest_b onto a->b."""
    rest_a, rest_b, a, b = V(rest_a), V(rest_b), V(a), V(b)
    d0 = (rest_b - rest_a).normalized()
    d1 = (b - a).normalized()
    q = d0.rotation_difference(d1).to_matrix().to_4x4()
    return Matrix.Translation(a) @ q @ Matrix.Translation(-rest_a)


def ik2(hip, foot, a, b, pole):
    """Knee position for thigh length a, shin length b, bending towards the direction `pole`."""
    hip, foot, pole = V(hip), V(foot), V(pole)
    d_vec = foot - hip
    d = max(min(d_vec.length, a + b - 1e-4), abs(a - b) + 1e-4)
    u = d_vec.normalized()
    x = (a * a - b * b + d * d) / (2.0 * d)
    h = math.sqrt(max(a * a - x * x, 0.0))
    p = pole - u * pole.dot(u)
    if p.length < 1e-6:
        p = Vector((0, 0, 1)) - u * u.z
    return hip + u * x + p.normalized() * h


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def keys(seq, t, loop=False):
    """seq: [(time, value_or_tuple)]; cosine-eased interpolation of floats or tuples."""
    if loop:
        t = t % 1.0
        seq = list(seq) + [(1.0, seq[0][1])]
    t = min(max(t, seq[0][0]), seq[-1][0])
    for (t0, v0), (t1, v1) in zip(seq, seq[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            u = 0.5 - 0.5 * math.cos(math.pi * u)
            if isinstance(v0, (tuple, list)):
                return tuple(c0 + (c1 - c0) * u for c0, c1 in zip(v0, v1))
            return v0 + (v1 - v0) * u
    return seq[-1][1]


def viewer_yaw(rig_obj):
    """Degrees the body is yawed by (render direction), wrapped to [-180, 180)."""
    yaw = math.degrees(rig_obj.rotation_euler.z)
    return (yaw + 180.0) % 360.0 - 180.0


class MatrixRig:
    def __init__(self, name, bones):
        """bones: list of (name, head, tail) in the rest pose (character space)."""
        self.obj = rig.build_armature(name, [(n, tuple(h), tuple(t), None) for n, h, t in bones])
        self.rest = {n: (V(h), V(t)) for n, h, t in bones}
        self.local = {n: self.obj.data.bones[n].matrix_local.copy() for n, _, _ in bones}
        self.local_inv = {n: m.inverted() for n, m in self.local.items()}
        self.motion = {}

    def attach(self, obj, bone):
        rig.parent_to_bone(obj, self.obj, bone)
        return obj

    def head(self, bone):
        return self.rest[bone][0]

    def tail(self, bone):
        return self.rest[bone][1]

    def set(self, bone, m):
        self.motion[bone] = m
        return m

    def set_segment(self, bone, a, b):
        ra, rb = self.rest[bone]
        return self.set(bone, segment_motion(ra, rb, a, b))

    def apply(self):
        for name, pb in self.obj.pose.bones.items():
            m = self.motion.get(name, I4)
            pb.matrix_basis = self.local_inv[name] @ m @ self.local[name]
        self.motion = {}


# ---------------------------------------------------------------- meshes

def _frame(t, prev_n):
    n = prev_n - t * prev_n.dot(t)
    if n.length < 1e-6:
        n = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
        n = n - t * n.dot(t)
    n.normalize()
    return n, t.cross(n)


def tube(name, pts, radii, material, segments=10, cap=True, squash=1.0, smooth_shade=True, normal=None):
    """Tube along a 3D polyline. radii: one per point (0 = closes to a point). `squash` scales the
    cross-section along tangent x normal; `normal` (vector) is the cross-section axis kept full size."""
    pts = [V(p) for p in pts]
    if isinstance(radii, (int, float)):
        radii = [radii] * len(pts)
    bm = bmesh.new()
    loops = []
    n = Vector((0, 0, 1))
    tangents = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tangents.append((b - a).normalized())
    n = Vector((1, 0, 0)) if abs(tangents[0].x) < 0.9 else Vector((0, 1, 0))
    if normal is not None:
        n = V(normal)
    for p, t, r in zip(pts, tangents, radii):
        n, bvec = _frame(t, n)
        if r <= 1e-5:
            loops.append([bm.verts.new(p)])
            continue
        loops.append([bm.verts.new(p + (n * math.cos(a) + bvec * math.sin(a) * squash) * r)
                      for a in (math.tau * k / segments for k in range(segments))])
    for a, b in zip(loops, loops[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1 or len(b) == 1:
            tip, ring = (a[0], b) if len(a) == 1 else (b[0], a)
            for k in range(len(ring)):
                bm.faces.new((ring[k], ring[(k + 1) % len(ring)], tip))
            continue
        for k in range(segments):
            bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
    if cap:
        for lp in (loops[0], loops[-1]):
            if len(lp) > 2:
                bm.faces.new(lp)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return geo.mesh_object(name, bm, material, smooth_shade)


def bezier(p0, p1, p2, n, p3=None):
    """Quadratic (or cubic with p3) curve points, n samples."""
    p0, p1, p2 = V(p0), V(p1), V(p2)
    out = []
    for i in range(n):
        t = i / (n - 1)
        if p3 is None:
            out.append(p0 * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + p2 * t * t)
        else:
            q3 = V(p3)
            out.append(p0 * (1 - t) ** 3 + p1 * 3 * (1 - t) ** 2 * t + p2 * 3 * (1 - t) * t * t + q3 * t ** 3)
    return out


def blob(name, center, radius, material, scale=(1, 1, 1), segments=12, rings=8, rotation=(0, 0, 0)):
    obj = geo.sphere(name, radius, tuple(center), material, scale=scale, segments=segments, rings=rings)
    obj.rotation_euler = tuple(math.radians(a) for a in rotation)
    return obj
