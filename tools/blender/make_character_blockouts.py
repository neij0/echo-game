"""Builds the BLOCKOUT models of the Echo and the Guardian (three silhouette
variants each) and exports one rigged .glb per variant.

Run headless:
  blender --background --python tools/blender/make_character_blockouts.py -- <out folder> [mixamo folder]

BLOCKOUT PLACEHOLDERS, NOT FINAL ART: stylised low-poly shapes to choose a
silhouette with. Everything is made from nothing but this script (no source
model; the pictures in docs/ref are mood references only, never traced):
tapered tubes, flat ribbons, balls and turned shapes, each skinned to a simple
rig. Faces -Y here (+Z in Godot), +X is the character's left, 1 unit = 1 world
unit, feet on z = 0, T-pose.

Rig: a humanoid with the bone names of Godot's humanoid profile (Hips, Spine,
Chest, Neck, Head, Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg,
LowerLeg, Foot, Toes), so animations retargeted to that profile (Mixamo)
play on it. Everything that should sway is a bone chain named <Name>_1 ...
<Name>_end (the Echo's antennae, ears and tails, the Guardian's cloak and
scarf): Godot drives those with springs (BoneSway). The Guardian's sword has
its own bone (Sword) on his right hand.

Materials only carry a name, a colour and a glow (emission); the game puts
its shared character shader on every surface (CharacterModel).

With a second folder, the Guardian's bare body (no cloak, antlers or sword;
T-pose, no rig; the same for every variant) is also written there as .fbx:
the mesh to upload to Mixamo for its automatic rig.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

SHARP_DEGREES = 38.0

# name: (colour, glow colour or None, glow strength)
MATERIALS = {
    # The Echo: pale silver, glowing in the cyan / white of her pulse.
    "echo_body": ((0.56, 0.66, 0.84), None, 0.0),
    "echo_shade": ((0.26, 0.36, 0.52), None, 0.0),
    "echo_glow": ((0.75, 0.95, 1.0), (0.55, 0.92, 1.0), 3.4),
    "echo_glow_soft": ((0.45, 0.75, 0.9), (0.3, 0.8, 1.0), 1.5),
    # The Guardian: dark, with amber / gold trims and blade.
    "guardian_armor": ((0.035, 0.035, 0.05), None, 0.0),
    "guardian_cloak": ((0.022, 0.024, 0.045), None, 0.0),
    "guardian_mantle": ((0.04, 0.042, 0.075), None, 0.0),
    "guardian_antler": ((0.07, 0.06, 0.055), None, 0.0),
    "guardian_trim": ((0.5, 0.36, 0.14), (1.0, 0.66, 0.2), 1.1),
    "guardian_blade": ((0.9, 0.6, 0.2), (1.0, 0.62, 0.16), 3.2),
    "guardian_eye": ((0.9, 0.85, 0.7), (1.0, 0.9, 0.7), 1.6),
}


def V(x, y, z):
    return Vector((x, y, z))


def flip(point, side):
    return Vector((point[0] * side, point[1], point[2]))


def resample(points, count):
    """count points at equal distances along a line of points."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    out = []
    j = 0
    for i in range(count):
        distance = lengths[-1] * i / (count - 1)
        while j < len(points) - 2 and lengths[j + 1] < distance:
            j += 1
        span = lengths[j + 1] - lengths[j]
        t = (distance - lengths[j]) / span if span > 1e-9 else 0.0
        out.append(points[j].lerp(points[j + 1], t))
    return out


def spline(control, count):
    """count points at equal distances along a smooth curve through control."""
    pts = [Vector(p) for p in control]
    ext = [pts[0] * 2.0 - pts[1]] + pts + [pts[-1] * 2.0 - pts[-2]]
    dense = []
    steps = 14
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(steps):
            t = s / steps
            dense.append(0.5 * (p1 * 2.0 + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t * t
                + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t * t * t))
    dense.append(pts[-1])
    return resample(dense, count)


def ramp(keys, t):
    """keys (numbers or (a, b) pairs) at equal steps -> the (a, b) at t."""
    pairs = [(k, k) if isinstance(k, (int, float)) else k for k in keys]
    if len(pairs) == 1:
        return pairs[0]
    at = max(0.0, min(1.0, t)) * (len(pairs) - 1)
    i = min(int(at), len(pairs) - 2)
    f = at - i
    return (pairs[i][0] + (pairs[i + 1][0] - pairs[i][0]) * f, pairs[i][1] + (pairs[i + 1][1] - pairs[i][1]) * f)


def chain_weights(names, t):
    """Weights of a point at share t along a chain of equal bones."""
    at = t * len(names) - 0.5
    if at <= 0.0:
        return {names[0]: 1.0}
    if at >= len(names) - 1:
        return {names[-1]: 1.0}
    i = int(at)
    f = at - i
    return {names[i]: 1.0 - f, names[i + 1]: f}


class Model:
    """Collects the shapes and bones of one character."""

    def __init__(self, name, body_only=False):
        self.name = name
        self.body_only = body_only
        self.verts = []
        self.weights = []
        self.faces = []
        self.face_materials = []
        self.materials = []
        self.bones = []

    def bone(self, name, head, tail, parent=None, connect=False):
        self.bones.append((name, Vector(head), Vector(tail), parent, connect))

    def chain(self, prefix, path, count, parent):
        """count bones along the path (<prefix>_1 ...), plus a short <prefix>_end."""
        joints = resample(path, count + 1)
        names = []
        for i in range(count):
            name = "%s_%d" % (prefix, i + 1)
            self.bone(name, joints[i], joints[i + 1], names[-1] if names else parent, bool(names))
            names.append(name)
        end = joints[-1] + (joints[-1] - joints[-2]).normalized() * 0.03
        self.bone(prefix + "_end", joints[-1], end, names[-1], True)
        return names

    def _material(self, name):
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def _skin(self, skin, t, i, point):
        if isinstance(skin, str):
            return {skin: 1.0}
        if callable(skin):
            return skin(point)
        if isinstance(skin[0], dict):
            return skin[i]
        return chain_weights(skin, t)

    def rings(self, ring_points, material, weight_at, start=None, end=None):
        """A skin over rings of points; faces look outward when the points of a
        ring go round a -> b with b = (direction of the next ring) x a."""
        index = self._material(material)
        base = len(self.verts)
        sides = len(ring_points[0])
        count = len(ring_points)
        for i, ring in enumerate(ring_points):
            for point in ring:
                self.verts.append(point)
                self.weights.append(weight_at(i, point))
        for i in range(count - 1):
            for k in range(sides):
                a = base + i * sides + k
                b = base + i * sides + (k + 1) % sides
                self.faces.append((a, b, b + sides, a + sides))
                self.face_materials.append(index)
        if start is not None:
            middle = len(self.verts)
            self.verts.append(Vector(start))
            self.weights.append(weight_at(0, start))
            for k in range(sides):
                self.faces.append((middle, base + (k + 1) % sides, base + k))
                self.face_materials.append(index)
        if end is not None:
            middle = len(self.verts)
            self.verts.append(Vector(end))
            self.weights.append(weight_at(count - 1, end))
            last = base + (count - 1) * sides
            for k in range(sides):
                self.faces.append((middle, last + k, last + (k + 1) % sides))
                self.face_materials.append(index)

    def tube(self, path, radii, material, skin, sides=6, wide=(1.0, 0.0, 0.0), caps=(True, True), body=False):
        """A tube along a path. radii: keys along it, numbers or (half width
        along "wide", half thickness). sides = 4 with a thin pair: a ribbon."""
        if self.body_only and not body:
            return
        path = [Vector(p) for p in path]
        count = len(path)
        side = None
        ring_points = []
        for i, point in enumerate(path):
            along = (path[min(i + 1, count - 1)] - path[max(i - 1, 0)]).normalized()
            hint = side if side is not None else Vector(wide)
            a = hint - along * hint.dot(along)
            if a.length < 1e-5:
                a = along.orthogonal()
            a.normalize()
            side = a
            b = along.cross(a)
            ra, rb = ramp(radii, i / (count - 1))
            ring_points.append([point + a * (ra * math.cos(math.tau * k / sides)) + b * (rb * math.sin(math.tau * k / sides))
                for k in range(sides)])
        self.rings(ring_points, material, lambda i, p: self._skin(skin, i / (count - 1), i, p),
            path[0] if caps[0] else None, path[-1] if caps[1] else None)

    def ball(self, center, radii, material, skin, sides=8, rings=4, axis=(0.0, 0.0, 1.0), wide=(1.0, 0.0, 0.0), body=False):
        """radii: along "wide", across, along the axis."""
        if self.body_only and not body:
            return
        center = Vector(center)
        axis = Vector(axis).normalized()
        a = Vector(wide) - axis * Vector(wide).dot(axis)
        if a.length < 1e-5:
            a = axis.orthogonal()
        a.normalize()
        b = axis.cross(a)
        ring_points = []
        for j in range(1, rings + 1):
            angle = math.pi * j / (rings + 1)
            ring_points.append([center - axis * (radii[2] * math.cos(angle))
                + a * (radii[0] * math.sin(angle) * math.cos(math.tau * k / sides))
                + b * (radii[1] * math.sin(angle) * math.sin(math.tau * k / sides)) for k in range(sides)])
        self.rings(ring_points, material, lambda i, p: self._skin(skin, 0.0, 0, p),
            center - axis * radii[2], center + axis * radii[2])

    def lathe(self, profile, material, skin, sides=12, caps=(False, True), jag=0.0, body=False):
        """Rings round the upright axis. profile: (z, rx, ry, middle y), from
        the top down (or from the bottom up). jag: every second point of the
        last ring hangs this much lower (a ragged hem)."""
        if self.body_only and not body:
            return
        along = Vector((0.0, 0.0, 1.0 if profile[1][0] > profile[0][0] else -1.0))
        a = Vector((1.0, 0.0, 0.0))
        b = along.cross(a)
        ring_points = []
        for i, (z, rx, ry, middle) in enumerate(profile):
            ring = []
            for k in range(sides):
                point = Vector((0.0, middle, z)) + a * (rx * math.cos(math.tau * k / sides)) + b * (ry * math.sin(math.tau * k / sides))
                if jag and i == len(profile) - 1 and k % 2 == 1:
                    point.z -= jag
                ring.append(point)
            ring_points.append(ring)
        first = profile[0]
        last = profile[-1]
        self.rings(ring_points, material, lambda i, p: self._skin(skin, i / (len(profile) - 1), i, p),
            Vector((0.0, first[3], first[0])) if caps[0] else None, Vector((0.0, last[3], last[0])) if caps[1] else None)

    def ribbon(self, prefix, control, bones, parent, widths, material, thick=0.008, wide=(1.0, 0.0, 0.0),
            glow=None, glow_widths=None, sides=4, samples=0):
        """A flat strip (or thin tube) along a smooth curve, on its own bone
        chain (bones = 0: fixed to the parent bone). glow: a second, narrower
        strip of that material showing on both faces. Returns (path, bones)."""
        if self.body_only:
            return [], []
        path = spline(control, samples if samples else max(bones, 2) * 2 + 1)
        names = self.chain(prefix, path, bones, parent) if bones else parent
        self.tube(path, [w if isinstance(w, tuple) else (w, thick) for w in widths], material, names, sides, wide)
        if glow:
            keys = glow_widths if glow_widths else [w * 0.4 for w in widths]
            self.tube(path, [(w, thick + 0.004) for w in keys], glow, names, sides, wide)
        return path, names

    def triangle_count(self):
        return sum(len(face) - 2 for face in self.faces)

    def build(self, with_rig=True):
        """Makes the Blender objects; returns them."""
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        for name in self.materials:
            mesh.materials.append(material(name))
        for polygon, index in zip(mesh.polygons, self.face_materials):
            polygon.material_index = index
        work = bmesh.new()
        work.from_mesh(mesh)
        limit = math.radians(SHARP_DEGREES)
        for face in work.faces:
            face.smooth = True
        for edge in work.edges:
            edge.smooth = len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) < limit
        work.to_mesh(mesh)
        work.free()
        body = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(body)
        if not with_rig:
            return [body]
        groups = {}
        for i, weights in enumerate(self.weights):
            total = sum(weights.values())
            for bone, value in weights.items():
                if value <= 0.0:
                    continue
                if bone not in groups:
                    groups[bone] = body.vertex_groups.new(name=bone)
                groups[bone].add([i], value / total, "REPLACE")
        known = {bone[0] for bone in self.bones}
        missing = sorted(set(groups) - known)
        if missing:
            raise SystemExit("%s: weights on bones that do not exist: %s" % (self.name, missing))
        armature = bpy.data.armatures.new(self.name + "_rig")
        rig = bpy.data.objects.new("Armature", armature)
        bpy.context.scene.collection.objects.link(rig)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode="EDIT")
        for name, head, tail, parent, connect in self.bones:
            bone = armature.edit_bones.new(name)
            bone.head = head
            bone.tail = tail
            if parent:
                bone.parent = armature.edit_bones[parent]
                bone.use_connect = connect
        bpy.ops.object.mode_set(mode="OBJECT")
        body.parent = rig
        modifier = body.modifiers.new("Armature", "ARMATURE")
        modifier.object = rig
        return [body, rig]


def material(name):
    found = bpy.data.materials.get(name)
    if found:
        return found
    colour, glow, strength = MATERIALS[name]
    found = bpy.data.materials.new(name)
    if found.node_tree is None:
        found.use_nodes = True
    shader = found.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*colour, 1.0)
    shader.inputs["Roughness"].default_value = 0.9
    if glow:
        shader.inputs["Emission Color"].default_value = (*glow, 1.0)
        shader.inputs["Emission Strength"].default_value = strength
    return found


# ---------------------------------------------------------------- humanoid

ECHO_SIZE = {
    "hip": 0.50, "waist": 0.58, "chest": 0.67, "shoulder": 0.745, "neck": 0.775,
    "head": 0.895, "head_y": -0.012, "head_r": (0.115, 0.12, 0.112), "neck_r": 0.026,
    "torso": [(0.035, 0.03), (0.082, 0.06), (0.057, 0.045), (0.078, 0.056), (0.072, 0.047), (0.028, 0.028)],
    "shoulder_x": 0.088, "elbow_x": 0.205, "wrist_x": 0.315, "hand_x": 0.375,
    "arm_r": (0.027, 0.023, 0.018), "hand_r": (0.034, 0.017, 0.024),
    "leg_x": 0.046, "knee": 0.27, "ankle": 0.05, "leg_r": (0.052, 0.037, 0.024),
    "foot": 0.11, "heel": 0.03, "foot_w": 0.029,
}

GUARDIAN_SIZE = {
    "hip": 0.86, "waist": 1.0, "chest": 1.2, "shoulder": 1.37, "neck": 1.43,
    "head": 1.535, "head_y": -0.01, "head_r": (0.085, 0.095, 0.1), "neck_r": 0.045,
    "torso": [(0.06, 0.05), (0.15, 0.1), (0.12, 0.085), (0.175, 0.11), (0.185, 0.1), (0.05, 0.05)],
    "shoulder_x": 0.2, "elbow_x": 0.47, "wrist_x": 0.71, "hand_x": 0.81,
    "arm_r": (0.058, 0.047, 0.036), "hand_r": (0.055, 0.032, 0.045),
    "leg_x": 0.09, "knee": 0.46, "ankle": 0.09, "leg_r": (0.08, 0.058, 0.042),
    "foot": 0.25, "heel": 0.07, "foot_w": 0.052,
}


def humanoid(m, d, skin):
    """The rig and the bare body: torso, head, arms out sideways (T-pose),
    straight legs and flat, human feet (heel, sole and toes on the floor)."""
    hip, waist, chest, shoulder, neck = d["hip"], d["waist"], d["chest"], d["shoulder"], d["neck"]
    head = d["head"]
    head_r = d["head_r"]
    head_base = head - head_r[2] * 0.7
    m.bone("Hips", V(0, 0, hip), V(0, 0, waist))
    m.bone("Spine", V(0, 0, waist), V(0, 0, chest), "Hips", True)
    m.bone("Chest", V(0, 0, chest), V(0, 0, neck), "Spine", True)
    m.bone("Neck", V(0, 0, neck), V(0, 0, head_base), "Chest", True)
    m.bone("Head", V(0, 0, head_base), V(0, 0, head + head_r[2]), "Neck", True)
    torso = d["torso"]
    m.tube([V(0, 0, hip - torso[1][0] * 0.8), V(0, 0, hip), V(0, 0, waist), V(0, 0, chest), V(0, 0, shoulder), V(0, 0, neck)],
        torso, skin, [{"Hips": 1.0}, {"Hips": 1.0}, {"Hips": 0.5, "Spine": 0.5}, {"Spine": 0.5, "Chest": 0.5},
        {"Chest": 1.0}, {"Chest": 1.0}], sides=8, body=True)
    m.tube([V(0, 0, neck - 0.01), V(0, 0, head_base + 0.02)], [d["neck_r"]], skin, "Neck", sides=6, body=True)
    m.ball(V(0, d["head_y"], head), head_r, skin, "Head", sides=10, rings=5, body=True)
    arm_z = shoulder - d["arm_r"][0] * 0.6
    for side, name in ((1.0, "Left"), (-1.0, "Right")):
        s = V(side * d["shoulder_x"], 0, arm_z)
        e = V(side * d["elbow_x"], 0.004, arm_z)
        w = V(side * d["wrist_x"], 0, arm_z)
        h = V(side * d["hand_x"], 0, arm_z)
        m.bone(name + "Shoulder", V(side * d["shoulder_x"] * 0.25, 0, arm_z), s, "Chest")
        m.bone(name + "UpperArm", s, e, name + "Shoulder", True)
        m.bone(name + "LowerArm", e, w, name + "UpperArm", True)
        m.bone(name + "Hand", w, h, name + "LowerArm", True)
        r0, r1, r2 = d["arm_r"]
        upper, lower, hand = name + "UpperArm", name + "LowerArm", name + "Hand"
        m.ball(s, (r0 * 1.2, r0 * 1.2, r0 * 1.2), skin, name + "Shoulder", sides=6, rings=3, body=True)
        m.tube([s, s.lerp(e, 0.5), e, e.lerp(w, 0.5), w], [r0, r0 * 0.95, r1, r1 * 0.9, r2], skin,
            [{upper: 1.0}, {upper: 1.0}, {upper: 0.5, lower: 0.5}, {lower: 1.0}, {lower: 0.6, hand: 0.4}],
            sides=6, wide=(0, 0, 1), body=True)
        m.ball(w.lerp(h, 0.55), d["hand_r"], skin, hand, sides=6, rings=3, axis=(0, 0, 1), body=True)

        leg_x = side * d["leg_x"]
        top = V(leg_x, 0, hip - 0.01)
        knee = V(leg_x * 1.05, -d["leg_r"][1] * 0.3, d["knee"])
        ankle = V(leg_x * 1.05, d["leg_r"][2] * 0.3, d["ankle"])
        length = d["foot"]
        ball_of_foot = V(leg_x * 1.05, -length * 0.62, d["ankle"] * 0.4)
        toe = V(leg_x * 1.05, -length, d["ankle"] * 0.3)
        m.bone(name + "UpperLeg", top, knee, "Hips")
        m.bone(name + "LowerLeg", knee, ankle, name + "UpperLeg", True)
        m.bone(name + "Foot", ankle, ball_of_foot, name + "LowerLeg", True)
        m.bone(name + "Toes", ball_of_foot, toe, name + "Foot", True)
        l0, l1, l2 = d["leg_r"]
        thigh, shin, foot, toes = name + "UpperLeg", name + "LowerLeg", name + "Foot", name + "Toes"
        m.tube([top + V(0, 0, l0 * 0.5), top.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5), ankle], [l0, l0 * 0.9, l1, l1 * 0.85, l2],
            skin, [{thigh: 1.0}, {thigh: 1.0}, {thigh: 0.5, shin: 0.5}, {shin: 1.0}, {shin: 0.6, foot: 0.4}], sides=6, body=True)
        # A flat human foot: heel behind the ankle, sole and toes ahead of it.
        high = d["ankle"]
        wide = d["foot_w"]
        m.tube([V(leg_x * 1.05, d["heel"], high * 0.5), V(leg_x * 1.05, 0, high * 0.6), V(leg_x * 1.05, -length * 0.62, high * 0.45),
            V(leg_x * 1.05, -length, high * 0.32)],
            [(wide * 0.75, high * 0.45), (wide * 0.9, high * 0.6), (wide, high * 0.44), (wide * 0.7, high * 0.3)], skin,
            [{foot: 1.0}, {foot: 1.0}, {foot: 0.5, toes: 0.5}, {toes: 1.0}], sides=6, body=True)


# -------------------------------------------------------------------- Echo

def echo_antennae(m, control, bones, tip, radius=0.009):
    for side, name in ((1.0, "L"), (-1.0, "R")):
        path, names = m.ribbon("Antenna" + name, [flip(p, side) for p in control], bones, "Head",
            [radius, radius * 0.8, radius * 0.55], "echo_body", sides=5)
        along = (path[-1] - path[-2]).normalized()
        m.ball(path[-1] + along * tip[2] * 0.6, tip, "echo_glow", names[-1], sides=6, rings=3, axis=along)


def echo_ears(m, control, bones, widths, wide):
    for side, name in ((1.0, "L"), (-1.0, "R")):
        m.ribbon("Ear" + name, [flip(p, side) for p in control], bones, "Head", widths, "echo_body",
            thick=0.009, wide=flip(wide, side), glow="echo_glow_soft")


def build_echo(variant, body_only=False):
    m = Model("echo_blockout_" + variant, body_only)
    d = ECHO_SIZE
    humanoid(m, d, "echo_body")
    # The core in her chest, small lights at the wrists and ankles, eyes.
    m.ball(V(0, -0.047, 0.675), (0.03, 0.02, 0.042), "echo_glow", "Chest", sides=6, rings=3)
    for side, name in ((1.0, "Left"), (-1.0, "Right")):
        m.ball(V(side * d["wrist_x"], 0, d["shoulder"] - d["arm_r"][0] * 0.6), (0.02, 0.02, 0.012), "echo_glow_soft",
            name + "LowerArm", sides=6, rings=2, axis=(1, 0, 0), wide=(0, 1, 0))
        m.ball(V(side * d["leg_x"] * 1.05, 0.004, d["ankle"] + 0.03), (0.026, 0.026, 0.012), "echo_glow_soft",
            name + "LowerLeg", sides=6, rings=2)
        m.ball(V(side * 0.047, -0.112, 0.905), (0.02, 0.008, 0.027), "echo_glow_soft", "Head", sides=6, rings=2)

    tail_root = V(0, 0.045, 0.5)
    if variant == "a":
        # "Leaf": broad leaf ears swept out and back, arcing antennae with
        # teardrop tips, a petal skirt and one broad plume tail with two streamers.
        echo_ears(m, [V(0.085, 0.01, 0.93), V(0.22, 0.05, 1.0), V(0.38, 0.13, 0.99), V(0.5, 0.22, 0.9)], 3,
            [0.02, 0.075, 0.062, 0.004], V(0.0, 0.55, 0.85))
        echo_antennae(m, [V(0.035, -0.04, 0.975), V(0.1, -0.02, 1.2), V(0.26, 0.08, 1.37), V(0.43, 0.2, 1.32), V(0.5, 0.27, 1.17)],
            5, (0.022, 0.022, 0.042))
        for k in range(6):
            angle = math.tau * (k + 0.5) / 6.0
            out = V(math.cos(angle), math.sin(angle), 0.0)
            m.ribbon("", [V(0, 0, 0.57) + out * 0.045, V(0, 0, 0.47) + out * 0.12, V(0, 0, 0.36) + out * 0.16], 0, "Hips",
                [0.03, 0.045, 0.004], "echo_shade", thick=0.008, wide=V(-out.y, out.x, 0.0))
        m.ribbon("Tail", [tail_root, V(0, 0.2, 0.43), V(0, 0.4, 0.26), V(0.03, 0.62, 0.15), V(0.0, 0.86, 0.2)], 7, "Hips",
            [0.028, 0.085, 0.105, 0.075, 0.004], "echo_body", thick=0.012, glow="echo_glow_soft",
            glow_widths=[0.003, 0.012, 0.032, 0.03, 0.003])
        for side, name in ((1.0, "L"), (-1.0, "R")):
            path, names = m.ribbon("Tail" + name, [flip(p, side) for p in
                [V(0.05, 0.04, 0.5), V(0.13, 0.25, 0.36), V(0.18, 0.5, 0.27), V(0.16, 0.74, 0.32)]], 4, "Hips",
                [0.012, 0.022, 0.016, 0.003], "echo_shade", thick=0.007)
            m.ball(path[-1], (0.016, 0.016, 0.03), "echo_glow", names[-1], sides=6, rings=3, axis=path[-1] - path[-2])
    elif variant == "b":
        # "Comet": tall upright ears, a crest, antennae streaming back behind
        # the head, no skirt, small fins on the forearms, three long tail
        # streamers with lit ends.
        echo_ears(m, [V(0.06, 0.0, 0.955), V(0.09, 0.03, 1.15), V(0.115, 0.09, 1.35), V(0.105, 0.17, 1.48)], 3,
            [0.018, 0.048, 0.036, 0.004], V(1.0, 0.0, 0.0))
        m.ribbon("", [V(0, -0.05, 0.975), V(0, 0.05, 1.08), V(0, 0.2, 1.1)], 0, "Head", [0.03, 0.045, 0.004],
            "echo_shade", thick=0.008, wide=V(0, 0, 1), glow="echo_glow_soft")
        echo_antennae(m, [V(0.035, -0.045, 0.97), V(0.07, 0.0, 1.07), V(0.11, 0.2, 1.1), V(0.15, 0.45, 1.04), V(0.17, 0.68, 0.92)],
            5, (0.016, 0.016, 0.055))
        for spread, name, length in ((0.0, "", 1.0), (1.0, "L", 0.86), (-1.0, "R", 0.86)):
            control = [tail_root + V(spread * 0.03, 0, 0), V(spread * 0.09, 0.3 * length, 0.39), V(spread * 0.17, 0.62 * length, 0.31),
                V(spread * 0.22, 0.97 * length, 0.35)]
            path, names = m.ribbon("Tail" + name, control, 6, "Hips", [0.02, 0.034, 0.026, 0.004], "echo_body", thick=0.009,
                glow="echo_glow_soft", glow_widths=[0.003, 0.012, 0.014, 0.003])
            m.ball(path[-1], (0.02, 0.02, 0.04), "echo_glow", names[-1], sides=6, rings=3, axis=path[-1] - path[-2])
        for side, name in ((1.0, "Left"), (-1.0, "Right")):
            m.ribbon("", [V(side * 0.25, 0.01, 0.73), V(side * 0.28, 0.07, 0.72), V(side * 0.33, 0.12, 0.7)], 0, name + "LowerArm",
                [0.016, 0.024, 0.003], "echo_shade", thick=0.006, wide=V(1, 0, 0))
    else:
        # "Bell": a frill of short ear fins, two upright antennae carrying big
        # lanterns, a bell skirt and one wide veil tail.
        for side in (1.0, -1.0):
            for out, length in ((V(0.75, 0.15, 0.65), 0.2), (V(1.0, 0.25, 0.1), 0.23), (V(0.8, 0.35, -0.5), 0.17)):
                start = V(side * 0.085, 0.0, 0.9)
                reach = flip(out.normalized(), side) * length
                m.ribbon("", [start, start + reach * 0.55, start + reach], 0, "Head", [0.016, 0.032, 0.003], "echo_body",
                    thick=0.008, wide=V(0.0, 0.5, 0.85), glow="echo_glow_soft")
        echo_antennae(m, [V(0.035, -0.035, 0.975), V(0.12, -0.02, 1.17), V(0.23, 0.0, 1.33), V(0.3, 0.04, 1.42)], 4,
            (0.046, 0.046, 0.05), radius=0.01)
        m.lathe([(0.585, 0.052, 0.04, 0.0), (0.52, 0.11, 0.095, 0.005), (0.43, 0.165, 0.15, 0.01), (0.34, 0.2, 0.185, 0.015)],
            "echo_body", "Hips", sides=12, jag=0.035)
        m.lathe([(0.375, 0.193, 0.178, 0.014), (0.352, 0.201, 0.186, 0.015)], "echo_glow_soft", "Hips", sides=12, caps=(False, False))
        path, names = m.ribbon("Tail", [tail_root, V(0, 0.24, 0.38), V(0, 0.5, 0.22), V(0, 0.78, 0.14)], 6, "Hips",
            [0.03, 0.1, 0.19, 0.27], "echo_body", thick=0.011, glow="echo_glow_soft", glow_widths=[0.003, 0.012, 0.035, 0.06])
        for k in range(5):
            m.ball(path[-1] + V((k - 2) * 0.115, 0.012, 0.0), (0.022, 0.022, 0.022), "echo_glow", names[-1], sides=6, rings=3)
    return m


# ---------------------------------------------------------------- Guardian

CLOAK_ANGLES = (("L", 0.0), ("FL", 60.0), ("FR", 120.0), ("R", 180.0), ("BR", 240.0), ("BL", 300.0))
CLOAK_BONES = 3
# Share of the cloak's height that stays fixed to the chest.
CLOAK_FIXED = 0.14


def cloak_row(keys, z):
    """(z, rx, ry, middle y) of the cloak at height z (keys go from the top down)."""
    z = max(keys[-1][0], min(keys[0][0], z))
    j = 0
    while j < len(keys) - 2 and keys[j + 1][0] > z:
        j += 1
    f = (keys[j][0] - z) / (keys[j][0] - keys[j + 1][0])
    return tuple(keys[j][n] + (keys[j + 1][n] - keys[j][n]) * f for n in range(4))


def cloak(m, keys, jag, material="guardian_cloak", rings=9):
    """The cloak: a closed, turned shape hanging from the shoulders, on six
    bone chains round the body, with a gold band above the hem. Returns its
    skinning (for parts sewn onto it)."""
    if m.body_only:
        return None
    top = keys[0][0]
    hem = keys[-1][0]
    profile = [cloak_row(keys, top + (hem - top) * i / (rings - 1)) for i in range(rings)]

    def surface(degrees, z):
        row = cloak_row(keys, z)
        angle = math.radians(degrees)
        return V(row[1] * math.cos(angle), row[3] - row[2] * math.sin(angle), z)

    chains = []
    for name, degrees in CLOAK_ANGLES:
        path = [surface(degrees, top + (hem - top) * (CLOAK_FIXED + (1.0 - CLOAK_FIXED) * j / CLOAK_BONES))
            for j in range(CLOAK_BONES + 1)]
        chains.append(m.chain("Cloak" + name, path, CLOAK_BONES, "Chest"))

    def skin(point):
        t = max(0.0, min(1.0, (top - point.z) / (top - hem)))
        if t <= CLOAK_FIXED:
            return {"Chest": 1.0}
        middle = cloak_row(keys, point.z)[3]
        around = math.degrees(math.atan2(-(point.y - middle), point.x)) % 360.0 / 60.0
        first = int(around) % 6
        share = around - int(around)
        at = (t - CLOAK_FIXED) / (1.0 - CLOAK_FIXED) * CLOAK_BONES - 0.5
        weights = {}
        for chain, part in ((chains[first], 1.0 - share), (chains[(first + 1) % 6], share)):
            if part <= 0.0:
                continue
            if at < 0.0:
                weights["Chest"] = weights.get("Chest", 0.0) + part * -at * 2.0
                weights[chain[0]] = part * (1.0 + at * 2.0)
            else:
                for bone, value in chain_weights(chain, (at + 0.5) / CLOAK_BONES).items():
                    weights[bone] = part * value
        return weights

    m.lathe(profile, material, skin, sides=12, caps=(True, True), jag=jag)
    last = profile[-1]
    m.lathe([(hem + 0.075, last[1] * 0.98 + 0.006, last[2] * 0.98 + 0.006, last[3]),
        (hem + 0.035, last[1] + 0.006, last[2] + 0.006, last[3])], "guardian_trim", skin, sides=12, caps=(False, False))
    return skin


def antlers(m, beam, tines, radius):
    """beam: control points of the left antler; tines: (share along the beam,
    direction, length). The tips glow gold."""
    for side in (1.0, -1.0):
        path = spline([flip(p, side) for p in beam], 9)
        m.tube(path[:7], [radius, radius * 0.85, radius * 0.6], "guardian_antler", "Head", sides=5)
        m.tube(path[6:], [radius * 0.6, radius * 0.15], "guardian_trim", "Head", sides=5)
        for share, direction, length in tines:
            start = path[int(round(share * (len(path) - 1)))]
            out = flip(direction, side).normalized()
            points = spline([start, start + out * length * 0.55 + V(0, 0, length * 0.08), start + out * length + V(0, 0, length * 0.28)], 5)
            m.tube(points[:4], [radius * 0.7, radius * 0.45], "guardian_antler", "Head", sides=5)
            m.tube(points[3:], [radius * 0.45, radius * 0.1], "guardian_trim", "Head", sides=5)


def sword(m, d, blade_length, blade_width, grip, guard, tip=0.16, core=0.62, one_edge=False):
    """The sword in his right hand, on its own bone, lying along the arm in
    the T-pose (the game aims the bone)."""
    if m.body_only:
        return
    arm_z = d["shoulder"] - d["arm_r"][0] * 0.6
    hand = V(-(d["wrist_x"] + d["hand_x"]) * 0.5, 0, arm_z)
    out = V(-1, 0, 0)
    m.bone("Sword", hand, hand + out * 0.3, "RightHand")
    m.tube([hand - out * grip * 0.55, hand + out * grip * 0.45], [0.018], "guardian_armor", "Sword", sides=6)
    m.ball(hand - out * (grip * 0.55 + 0.02), (0.03, 0.03, 0.03), "guardian_trim", "Sword", sides=6, rings=3)
    start = hand + out * grip * 0.45
    m.tube([start + V(0, guard, 0), start, start - V(0, guard, 0)], [(0.03, 0.022), (0.04, 0.03), (0.03, 0.022)],
        "guardian_armor", "Sword", sides=4, wide=(1, 0, 0))
    m.ball(start, (0.035, 0.035, 0.035), "guardian_trim", "Sword", sides=6, rings=3)
    end = start + out * blade_length
    shoulder = start + out * blade_length * (1.0 - tip)
    if one_edge:
        # A cleaver: a straight back, the edge on one side, a slanted end.
        m.tube([start, shoulder, end], [(blade_width, 0.014), (blade_width * 1.15, 0.014), (blade_width * 0.5, 0.008)],
            "guardian_armor", "Sword", sides=4, wide=(0, 1, 0))
        m.tube([start + V(0, -blade_width * 0.72, 0), shoulder + V(0, -blade_width * 0.86, 0), end + V(0, -blade_width * 0.3, 0)],
            [(blade_width * 0.3, 0.017), (blade_width * 0.32, 0.017), (blade_width * 0.2, 0.011)], "guardian_blade", "Sword",
            sides=4, wide=(0, 1, 0))
    else:
        m.tube([start, shoulder, end], [(blade_width, 0.013), (blade_width * 0.9, 0.013), (0.004, 0.004)],
            "guardian_armor", "Sword", sides=4, wide=(0, 1, 0))
        m.tube([start + out * 0.02, shoulder, end - out * blade_length * tip * 0.25],
            [(blade_width * core, 0.017), (blade_width * core * 0.9, 0.017), (0.003, 0.006)], "guardian_blade", "Sword",
            sides=4, wide=(0, 1, 0))


def guardian_head(m, hood_top, point_back):
    """Hood, a beaked mask and two faint eyes."""
    m.ball(V(0, 0.012, 1.545), (0.118, 0.128, 0.125), "guardian_mantle", "Head", sides=10, rings=5)
    m.tube([V(0, 0.0, 1.6), V(0, point_back * 0.5, hood_top), V(0, point_back, hood_top - 0.03)], [0.085, 0.05, 0.006],
        "guardian_mantle", "Head", sides=6)
    m.tube([V(0, -0.07, 1.555), V(0, -0.13, 1.52), V(0, -0.175, 1.455)], [(0.06, 0.05), (0.04, 0.035), (0.006, 0.006)],
        "guardian_armor", "Head", sides=5, wide=(1, 0, 0))
    for side in (1.0, -1.0):
        m.ball(V(side * 0.038, -0.118, 1.55), (0.014, 0.008, 0.008), "guardian_eye", "Head", sides=6, rings=2)


def build_guardian(variant, body_only=False):
    m = Model("guardian_blockout_" + variant, body_only)
    d = GUARDIAN_SIZE
    humanoid(m, d, "guardian_armor")
    if variant == "a":
        # "Stag": wide branching antlers, a pointed hood, a ragged shoulder
        # mantle over a long ragged cloak, a greatsword.
        guardian_head(m, 1.7, 0.2)
        antlers(m, [V(0.07, 0.02, 1.62), V(0.23, 0.05, 1.8), V(0.4, 0.04, 1.98), V(0.48, -0.02, 2.2)],
            [(0.3, V(0.1, -0.55, 0.8), 0.24), (0.55, V(0.7, -0.15, 0.7), 0.24), (0.78, V(-0.55, 0.0, 0.85), 0.2)], 0.038)
        cloak(m, [(1.43, 0.085, 0.075, 0.01), (1.36, 0.225, 0.14, 0.015), (1.2, 0.27, 0.19, 0.02), (0.9, 0.315, 0.25, 0.03),
            (0.55, 0.37, 0.31, 0.04), (0.2, 0.43, 0.37, 0.05)], 0.1)
        m.lathe([(1.45, 0.095, 0.085, 0.01), (1.38, 0.27, 0.17, 0.015), (1.26, 0.325, 0.225, 0.02), (1.15, 0.345, 0.25, 0.025)],
            "guardian_mantle", "Chest", sides=12, caps=(True, True), jag=0.07)
        m.ball(V(0, -0.215, 1.27), (0.035, 0.012, 0.055), "guardian_trim", "Chest", sides=4, rings=3)
        sword(m, d, 0.95, 0.055, 0.24, 0.13)
    elif variant == "b":
        # "Spire": a tall narrow shape: a high hood, upright lyre antlers, a
        # high collar, a slim long cloak, a long scarf down the back, a long thin blade.
        guardian_head(m, 1.8, 0.1)
        antlers(m, [V(0.06, 0.02, 1.66), V(0.14, 0.03, 1.9), V(0.16, 0.03, 2.16), V(0.09, 0.02, 2.38)],
            [(0.35, V(0.8, -0.1, 0.6), 0.17), (0.65, V(0.85, 0.0, 0.5), 0.15)], 0.032)
        skin = cloak(m, [(1.44, 0.085, 0.075, 0.01), (1.37, 0.205, 0.13, 0.015), (1.2, 0.235, 0.17, 0.02), (0.8, 0.265, 0.215, 0.03),
            (0.4, 0.295, 0.245, 0.04), (0.07, 0.315, 0.265, 0.045)], 0.0)
        # The collar: a wall round the neck, closed on the inside.
        m.lathe([(1.4, 0.15, 0.125, 0.02), (1.5, 0.185, 0.16, 0.035), (1.6, 0.2, 0.175, 0.05), (1.6, 0.17, 0.145, 0.05),
            (1.46, 0.1, 0.09, 0.02)], "guardian_mantle", "Chest", sides=12, caps=(False, False))
        m.lathe([(1.585, 0.203, 0.178, 0.05), (1.61, 0.203, 0.178, 0.05), (1.61, 0.168, 0.143, 0.05)], "guardian_trim", "Chest",
            sides=12, caps=(False, False))
        for side, name in ((1.0, "L"), (-1.0, "R")):
            m.ribbon("Scarf" + name, [V(side * 0.07, 0.13, 1.42), V(side * 0.1, 0.24, 1.2), V(side * 0.13, 0.3, 0.9),
                V(side * 0.15, 0.36, 0.6), V(side * 0.16, 0.44, 0.34)], 5, "Chest", [0.035, 0.05, 0.05, 0.045, 0.006],
                "guardian_mantle", thick=0.01, wide=V(1, 0, 0), glow="guardian_trim", glow_widths=[0.006, 0.01, 0.01, 0.012, 0.004])
        if skin:
            m.tube([V(0, -0.135, 1.36), V(0, -0.2, 1.0), V(0, -0.255, 0.45), V(0, -0.27, 0.1)], [(0.012, 0.006)], "guardian_trim",
                skin, sides=4, wide=(1, 0, 0))
        sword(m, d, 1.2, 0.034, 0.26, 0.07, tip=0.3, core=0.7)
    else:
        # "Bulwark": broad: heavy pauldrons, antlers sweeping wide and back, a
        # short cape to the knee over armoured legs, a heavy cleaver.
        guardian_head(m, 1.66, 0.14)
        antlers(m, [V(0.09, 0.03, 1.6), V(0.3, 0.1, 1.68), V(0.52, 0.22, 1.72), V(0.66, 0.3, 1.9)],
            [(0.45, V(0.1, -0.1, 1.0), 0.24), (0.7, V(0.15, 0.0, 1.0), 0.26), (0.88, V(0.3, 0.9, 0.2), 0.15)], 0.044)
        cloak(m, [(1.44, 0.1, 0.085, 0.01), (1.36, 0.32, 0.17, 0.02), (1.2, 0.37, 0.24, 0.03), (0.85, 0.4, 0.29, 0.04),
            (0.5, 0.42, 0.32, 0.05)], 0.09)
        for side, name in ((1.0, "Left"), (-1.0, "Right")):
            m.ball(V(side * 0.3, 0.0, 1.4), (0.17, 0.14, 0.105), "guardian_mantle", "Chest", sides=8, rings=4)
            m.tube([V(side * 0.34, 0.0, 1.47), V(side * 0.47, 0.0, 1.56), V(side * 0.56, 0.02, 1.7)], [0.045, 0.03, 0.004],
                "guardian_trim", "Chest", sides=5)
            m.ball(V(side * 0.095, -0.02, 0.47), (0.075, 0.075, 0.06), "guardian_trim", name + "LowerLeg", sides=6, rings=3)
        m.ball(V(0, -0.19, 1.3), (0.06, 0.014, 0.06), "guardian_trim", "Chest", sides=4, rings=3)
        sword(m, d, 0.82, 0.095, 0.26, 0.11, tip=0.2, one_edge=True)
    return m


# ------------------------------------------------------------------ export

def export(model, folder):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for item in model.build():
        item.select_set(True)
    path = os.path.join(folder, model.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
        export_texcoords=False, export_normals=True, export_skins=True, export_animations=False,
        export_materials="EXPORT")
    print("BLOCKOUT %s: %d triangles, %d bones, %d materials, height %.2f, half width %.2f (T-pose)" % (
        model.name, model.triangle_count(), len(model.bones), len(model.materials),
        max(v.z for v in model.verts), max(abs(v.x) for v in model.verts)))


def export_body(model, folder):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for item in model.build(False):
        item.select_set(True)
    path = os.path.join(folder, "guardian_blockout_body.fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, axis_forward="-Z", axis_up="Y")
    print("BLOCKOUT body for Mixamo: %s (%d triangles)" % (path, model.triangle_count()))


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not arguments:
        raise SystemExit("usage: -- <out folder> [mixamo folder]")
    os.makedirs(arguments[0], exist_ok=True)
    for variant in ("a", "b", "c"):
        export(build_echo(variant), arguments[0])
        export(build_guardian(variant), arguments[0])
    if len(arguments) > 1:
        os.makedirs(arguments[1], exist_ok=True)
        export_body(build_guardian("a", True), arguments[1])
    print("BLOCKOUTS done -> %s" % arguments[0])


main()
