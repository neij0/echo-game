"""Rigs the hand-made Echo (art/echo/echo_model.blend): adds the armature
"EchoRig", binds every part of the "Echo" collection to it and saves the
file. Technical work only: no vertex is moved and no shape or colour is
changed; the script checks that the rest shape stays identical.

Run headless (from the project folder; it refuses if EchoRig exists):
  blender --background art/echo/echo_model.blend --python tools/blender/rig_echo.py
  ... -- --save-failed <copy.blend>   (if the check fails, a copy to look at)

What it does:
- EchoRig, in the model's T-pose, symmetric about the body's mirror plane
  (the Cube's Mirror modifier: the armature object stands on it):
  - a humanoid body that maps onto Godot's SkeletonProfileHumanoid (Root,
    Hips, Spine, Chest, UpperChest, Neck, Head, Eye, Shoulder, UpperArm,
    LowerArm, Hand, Thumb / Index / Middle / Ring / Little _1 _2 _3,
    UpperLeg, LowerLeg, Foot, Toes; .L / .R): its joints were measured on
    the mesh (edge loops of the elbows, knees, knuckles..., see BODY);
  - extra bones, computed from each part's own geometry: Toe1-5 (2 each,
    under Toes), the three tails (TailMid / TailLeft / TailRight _1-_6 +
    _end, along their TailPath curves), the antennae (Antenna_1-_4 +
    Lantern), the ears (Ear_1-_3 + _end), one chain per skirt leaf
    (Skirt1-7 .L / .R, SkirtFront, SkirtBack: _1 _2 + _end), Crown,
    CheekTuft. _end bones only mark the tips (no deform).
- Weights: the body (Cube) gets Blender's automatic (bone heat) weights,
  computed on a copy with its Mirror applied (a closed body) and copied
  back to the modelled half (the Mirror modifier mirrors them, .L <-> .R).
  Thin parts (ears, skirt leaves, tails, antennae, cheek tufts) get smooth
  weights along their chain, blended into the parent bone at the root.
  Rigid parts follow one bone: ChestCrystal -> UpperChest, Eye -> Eye,
  Lantern -> Lantern, Crown + CrownSide -> Crown.
- Modifiers: an Armature modifier goes after Mirror / Curve (so the
  mirrored half and the curved tails deform) and before Subdivision /
  Solidify (they follow the deformed shape). Two modifiers cannot work
  under an armature and are applied, the shape staying identical:
  the Antenna curve becomes a mesh (curves cannot hold weights), and the
  Eye's Shrinkwrap is applied (it would pull the eyes back to their rest
  place when the head turns). The originals are kept in the collection
  "Echo sources (not exported)" (excluded from the view layer).
- Kept as they look: an empty vertex group read by a modifier (the side
  tails' Solidify "Thick") is filled with 1 once bone weights exist (an
  empty group counts as 0 then); a collapsed skirt island (all its points
  in one spot) only follows the hips; the body's duplicate points and
  zero-area faces stay (only the copy for the automatic weights is
  cleaned); the mirrored parts get the other side's (empty) groups so the
  Mirror modifier hands the mirrored half to the .R bones.
- Every part is parented to EchoRig (keeping its place), the TailPath
  curves too, so the whole character moves together in Object Mode.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

RIG = "EchoRig"
SOURCES = "Echo sources (not exported)"
# Body joints in the armature's space (x = from the mirror plane, the left
# side; metres). Measured on echo_model.blend's T-pose: edge loops of the
# arm (shoulder ~0.06, elbow ~0.21, wrist 0.345), the leg (knee ~0.33,
# ankle ~0.06), the knuckle loops of every finger, the toes.
SPINE = [  # name, head, tail
    ("Hips", (0.0, -0.028, 0.490), (0.0, -0.032, 0.575)),
    ("Spine", (0.0, -0.032, 0.575), (0.0, -0.045, 0.632)),
    ("Chest", (0.0, -0.045, 0.632), (0.0, -0.050, 0.690)),
    ("UpperChest", (0.0, -0.050, 0.690), (0.0, -0.045, 0.765)),
    ("Neck", (0.0, -0.045, 0.765), (0.0, -0.036, 0.810)),
    ("Head", (0.0, -0.036, 0.810), (0.0, -0.050, 0.945)),
]
ARM = [  # name, head, tail, parent (left side)
    ("Shoulder", (0.012, -0.045, 0.758), (0.062, -0.045, 0.758), "UpperChest"),
    ("UpperArm", (0.062, -0.045, 0.758), (0.210, -0.046, 0.744), "Shoulder"),
    ("LowerArm", (0.210, -0.046, 0.744), (0.345, -0.047, 0.732), "UpperArm"),
    ("Hand", (0.345, -0.047, 0.732), (0.393, -0.053, 0.731), "LowerArm"),
]
HAND_Z = 0.731
FINGERS = {  # x of the knuckle loops (base, two inner loops, tip), y of the finger's middle
    "Index": ((0.399, 0.426, 0.450, 0.471), -0.070),
    "Middle": ((0.393, 0.4245, 0.4535, 0.4765), -0.053),
    "Ring": ((0.3875, 0.416, 0.446, 0.466), -0.035),
    "Little": ((0.3835, 0.400, 0.4225, 0.4365), -0.020),
}
# The thumb points forward: its base loop on the palm, two loops, the tip.
THUMB = [(0.3804, -0.0744), (0.391, -0.087), (0.4014, -0.0992), (0.410, -0.1074)]
LEG = [
    ("UpperLeg", (0.035, -0.025, 0.475), (0.025, -0.013, 0.330), "Hips"),
    ("LowerLeg", (0.025, -0.013, 0.330), (0.021, -0.002, 0.058), "UpperLeg"),
    ("Foot", (0.021, -0.002, 0.058), (0.026, -0.0975, 0.008), "LowerLeg"),
    ("Toes", (0.026, -0.0975, 0.008), (0.026, -0.112, 0.006), "Foot"),
]
TOE_BASE_Y = -0.0975
TOE_Z = 0.007
TOES = [(0.0078, -0.1138), (0.019, -0.1119), (0.0288, -0.1106), (0.0388, -0.1094), (0.047, -0.1075)]  # x, tip y (big toe first)
# Chains: bones per chain, the parent bone they hang from (root blend).
TAILS = {"Tail": ("TailMid", "TailPath"), "Tail.001": ("TailRight", "TailPath.001"), "Tail.002": ("TailLeft", "TailPath.002")}
TAIL_BONES = 6
TAIL_PARENT = "Spine"
ANTENNA_BONES = 4
EAR_BONES = 3
SKIRT_BONES = 2
SKIRT_PARENT = "Hips"
HEAD_PARENT = "Head"
# Share of the first bone over which a chain blends into its parent (and
# how much of the root goes to the parent), and how far two neighbouring
# bones of a chain blend into each other (share of a bone).
ROOT_BLEND = 0.35
ROOT_PARENT_SHARE = 0.5
# Bones the body's automatic weights may use (the rest are extras).
BODY_BONE_PREFIXES = ("Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "Shoulder", "UpperArm", "LowerArm", "Hand",
                      "Thumb_", "Index_", "Middle_", "Ring_", "Little_", "UpperLeg", "LowerLeg", "Foot", "Toe1_", "Toe2_",
                      "Toe3_", "Toe4_", "Toe5_")
TOLERANCE = 1e-5
# Points closer than this are merged in the body copy for the automatic
# weights (duplicates), faces smaller than its square are dissolved.
CLEAN_DISTANCE = 1e-5
# A skirt island smaller than this (metres from its middle) is not a leaf.
MIN_LEAF_SIZE = 0.005


def log(*parts):
    print("RIG", *parts)


def mirror(point):
    return Vector((-point[0], point[1], point[2]))


def sides():
    return ((".L", 1.0), (".R", -1.0))


# --- shape reference -------------------------------------------------------

def evaluated_points(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return points


def shape_of(collection):
    return {obj.name: evaluated_points(obj) for obj in collection.all_objects if obj.type in ("MESH", "CURVE")}


def compare(before, after):
    worst = 0.0
    for name, points in before.items():
        other = after.get(name)
        if other is None or len(other) != len(points):
            raise SystemExit("RIG FAILED: %s changed its vertex count (%s -> %s)" % (name, len(points), other and len(other)))
        moved = max((a - b).length for a, b in zip(points, other)) if points else 0.0
        if moved > TOLERANCE:
            log("  %s moved %.6f m at rest" % (name, moved))
        worst = max(worst, moved)
    return worst


# --- the two modifiers that cannot stay -------------------------------------

def sources_collection():
    collection = bpy.data.collections.get(SOURCES)
    if collection is None:
        collection = bpy.data.collections.new(SOURCES)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_sources(obj, new_name):
    sources = sources_collection()
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    sources.objects.link(obj)
    obj.name = new_name


def copy_modifier(source, target):
    made = target.modifiers.new(source.name, source.type)
    for prop in source.bl_rna.properties:
        if prop.is_readonly or prop.identifier in ("name", "type"):
            continue
        try:
            setattr(made, prop.identifier, getattr(source, prop.identifier))
        except (AttributeError, TypeError):
            pass
    return made


def bake_modifiers(obj, keep_types, new_name_of_source):
    """A mesh object with the modifiers NOT in keep_types applied (in rest),
    the kept ones copied; the original goes to the sources collection."""
    kept = [m for m in obj.modifiers if m.type in keep_types]
    states = [(m, m.show_viewport) for m in kept]
    for m in kept:
        m.show_viewport = False
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    for m, state in states:
        m.show_viewport = state
    baked = bpy.data.objects.new(obj.name, mesh)
    for collection in obj.users_collection:
        collection.objects.link(baked)
    baked.matrix_world = obj.matrix_world.copy()
    for m in kept:
        copy_modifier(m, baked)
    name = obj.name
    move_to_sources(obj, new_name_of_source)
    baked.name = name
    return baked


# --- the armature -----------------------------------------------------------

def new_bone(bones, name, head, tail, parent=None, up=(0.0, 0.0, 1.0), deform=True, connect=False):
    bone = bones.new(name)
    bone.head = Vector(head)
    bone.tail = Vector(tail)
    axis = (bone.tail - bone.head).normalized()
    up = Vector(up)
    if abs(axis.dot(up.normalized())) > 0.95:
        up = Vector((0.0, -1.0, 0.0)) if abs(axis.y) < 0.95 else Vector((0.0, 0.0, 1.0))
    bone.align_roll(up)
    bone.use_deform = deform
    if parent:
        bone.parent = bones[parent]
        bone.use_connect = connect and (bones[parent].tail - bone.head).length < 1e-6
    return bone


def chain_points(points, root, count):
    """Joints of a chain through a part: from root to the farthest point,
    each joint the middle of the points around it along the way."""
    tip = max(points, key=lambda p: (p - root).length)
    axis = tip - root
    length = axis.length
    axis.normalize()
    joints = [root.copy()]
    for k in range(1, count):
        share = k / count
        near = [p for p in points if abs((p - root).dot(axis) / length - share) < 0.5 / count]
        joints.append(sum(near, Vector()) / len(near) if near else root + axis * length * share)
    joints.append(tip)
    return joints


def polyline_points(polyline, count):
    """count + 1 joints at equal arc lengths along a polyline."""
    lengths = [0.0]
    for a, b in zip(polyline, polyline[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    joints = []
    for k in range(count + 1):
        target = lengths[-1] * k / count
        for i in range(len(polyline) - 1):
            if lengths[i + 1] >= target - 1e-9:
                span = max(lengths[i + 1] - lengths[i], 1e-9)
                joints.append(polyline[i].lerp(polyline[i + 1], (target - lengths[i]) / span))
                break
    return joints


def add_chain(bones, prefix, suffix, joints, parent, end=True):
    names = []
    previous = parent
    for k in range(len(joints) - 1):
        name = "%s_%d%s" % (prefix, k + 1, suffix)
        new_bone(bones, name, joints[k], joints[k + 1], previous, connect=k > 0)
        names.append(name)
        previous = name
    if end:
        direction = (joints[-1] - joints[-2]).normalized()
        new_bone(bones, "%s_end%s" % (prefix, suffix), joints[-1], joints[-1] + direction * 0.01, previous, deform=False, connect=True)
    return names


# --- weights -------------------------------------------------------------------

def pre_armature_points(obj, keep_types):
    """World positions of the object's own vertices with only the modifiers
    that come before the armature (Mirror / Curve) applied."""
    states = []
    for m in obj.modifiers:
        states.append((m, m.show_viewport))
        m.show_viewport = m.type in keep_types
    bpy.context.view_layer.update()
    points = evaluated_points(obj)
    for m, state in states:
        m.show_viewport = state
    bpy.context.view_layer.update()
    return points[:len(obj.data.vertices)]


def chain_weights(points, joints, names, parent):
    """Smooth weights along a chain: linear between the middles of two
    neighbouring bones, the root shared with the parent bone."""
    weights = []
    count = len(names)
    for p in points:
        best = None
        for i in range(count):
            a, b = joints[i], joints[i + 1]
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
            d = (a + ab * t - p).length
            if best is None or d < best[0]:
                best = (d, i + t)
        u = best[1]
        w = {}
        if count == 1 or u <= 0.5:
            w[names[0]] = 1.0
        elif u >= count - 0.5:
            w[names[-1]] = 1.0
        else:
            k = int(math.floor(u - 0.5))
            f = (u - 0.5) - k
            w[names[k]] = 1.0 - f
            w[names[k + 1]] = f
        if parent and u < ROOT_BLEND:
            share = ROOT_PARENT_SHARE * (1.0 - u / ROOT_BLEND)
            w = {n: v * (1.0 - share) for n, v in w.items()}
            w[parent] = w.get(parent, 0.0) + share
        weights.append(w)
    return weights


def keep_vertex_group_modifiers(obj):
    """A modifier that reads a vertex group (the tails' Solidify "Thick")
    ignores it while the mesh has no weights at all; once bone weights are
    added it reads an empty group as 0. Where the mesh has no weights yet,
    the group is filled with 1, which is what the modifier showed."""
    if any(vertex.groups for vertex in obj.data.vertices):
        return
    for modifier in obj.modifiers:
        name = getattr(modifier, "vertex_group", "")
        group = obj.vertex_groups.get(name) if name else None
        if group is not None:
            group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
            log("%s: the %s modifier's empty group \"%s\" filled with 1 (keeps its look)" % (obj.name, modifier.type.lower(), name))


def set_weights(obj, weights):
    keep_vertex_group_modifiers(obj)
    for i, w in enumerate(weights):
        total = sum(w.values())
        for name, value in w.items():
            group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
            group.add([i], value / total, "REPLACE")
    # The Mirror modifier only gives the mirrored half the other side's
    # bones (.L <-> .R) when a group of that name exists on the object.
    if any(m.type == "MIRROR" and m.use_mirror_vertex_groups for m in obj.modifiers):
        for group in list(obj.vertex_groups):
            for this, other in ((".L", ".R"), (".R", ".L")):
                if group.name.endswith(this):
                    twin = group.name[:-len(this)] + other
                    if obj.vertex_groups.get(twin) is None:
                        obj.vertex_groups.new(name=twin)


def body_weights(cube, rig):
    """Automatic (bone heat) weights on a copy of the body with its Mirror
    applied, copied back to the modelled half. The copy is cleaned first
    (duplicate points merged, zero-area faces dissolved): the bone heat
    finds no solution at all with them. The model keeps them."""
    count = len(cube.data.vertices)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    states = [(m, m.show_viewport) for m in cube.modifiers]
    for m in cube.modifiers:
        m.show_viewport = m.type == "MIRROR"
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    full = bpy.data.meshes.new_from_object(cube.evaluated_get(depsgraph))
    for m, state in states:
        m.show_viewport = state
    for i in range(count):
        if (full.vertices[i].co - cube.data.vertices[i].co).length > TOLERANCE:
            raise SystemExit("RIG FAILED: the mirrored body does not keep the vertex order")
    mesh = bmesh.new()
    mesh.from_mesh(full)
    doubles = len(mesh.verts)
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=CLEAN_DISTANCE)
    doubles -= len(mesh.verts)
    degenerate = sum(1 for face in mesh.faces if face.calc_area() < CLEAN_DISTANCE ** 2)
    bmesh.ops.dissolve_degenerate(mesh, edges=mesh.edges, dist=CLEAN_DISTANCE * 0.1)
    clean = bpy.data.meshes.new("EchoBodyHeat")
    mesh.to_mesh(clean)
    mesh.free()
    log("body copy for the automatic weights: %d duplicate point(s) merged, %d zero-area face(s) dissolved" % (doubles, degenerate))
    finder = KDTree(len(clean.vertices))
    for vertex in clean.vertices:
        finder.insert(vertex.co, vertex.index)
    finder.balance()
    copy = bpy.data.objects.new("EchoBodyHeat", clean)
    bpy.context.scene.collection.objects.link(copy)
    copy.matrix_world = cube.matrix_world.copy()
    extras = []
    for bone in rig.data.bones:
        if bone.use_deform and not bone.name.startswith(BODY_BONE_PREFIXES):
            bone.use_deform = False
            extras.append(bone.name)
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    copy.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    with bpy.context.temp_override(active_object=rig, object=rig, selected_objects=[copy, rig], selected_editable_objects=[copy, rig]):
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for name in extras:
        rig.data.bones[name].use_deform = True
    groups = {group.index: group.name for group in copy.vertex_groups}
    weights = []
    empty = 0
    for i in range(count):
        _, index, distance = finder.find(full.vertices[i].co)
        if distance > CLEAN_DISTANCE:
            raise SystemExit("RIG FAILED: no point of the cleaned body copy at vertex %d" % i)
        w = {groups[g.group]: g.weight for g in clean.vertices[index].groups if g.weight > 1e-4}
        if not w:
            empty += 1
        weights.append(w)
    bpy.data.objects.remove(copy)
    bpy.data.meshes.remove(full)
    bpy.data.meshes.remove(clean)
    return weights, empty


def nearest_bone_fill(weights, points, rig, allowed):
    """Vertices the heat left without weights: the nearest allowed bone."""
    filled = 0
    for i, w in enumerate(weights):
        if w:
            continue
        best = None
        for bone in rig.data.bones:
            if not bone.name in allowed:
                continue
            a = rig.matrix_world @ bone.head_local
            b = rig.matrix_world @ bone.tail_local
            ab = b - a
            t = max(0.0, min(1.0, (points[i] - a).dot(ab) / max(ab.length_squared, 1e-12)))
            d = (a + ab * t - points[i]).length
            if best is None or d < best[0]:
                best = (d, bone.name)
        weights[i] = {best[1]: 1.0}
        filled += 1
    return filled


def add_armature_modifier(obj, rig, after_types):
    """The Armature modifier after the last Mirror / Curve modifier."""
    index = 0
    for i, m in enumerate(obj.modifiers):
        if m.type in after_types:
            index = i + 1
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True
    modifier.use_bone_envelopes = False
    modifier.use_deform_preserve_volume = False
    obj.modifiers.move(len(obj.modifiers) - 1, index)
    return modifier


def parent_keep(obj, rig):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    obj.matrix_world = world


# --- main ---------------------------------------------------------------------

def main():
    echo = bpy.data.collections.get("Echo")
    if echo is None:
        raise SystemExit("RIG: no collection Echo")
    if bpy.data.objects.get(RIG):
        raise SystemExit("RIG: %s already exists: nothing done" % RIG)
    objects = {obj.name: obj for obj in echo.all_objects}
    before = shape_of(echo)
    log("shape reference:", len(before), "objects")

    cube = objects["Cube"]
    plane = cube.matrix_world.translation.x

    # 1. The two modifiers that cannot stay under an armature.
    antenna = bake_modifiers(objects["Antenna"], ("MIRROR",), "Antenna (curve source)")
    eye = bake_modifiers(objects["Eye"], ("MIRROR",), "Eye (shrinkwrap source)")
    bpy.context.view_layer.layer_collection.children[SOURCES].exclude = True
    objects = {obj.name: obj for obj in echo.all_objects}
    log("antenna curve -> mesh,", len(antenna.data.vertices), "verts; eye shrinkwrap applied")

    # 2. The armature, standing on the mirror plane.
    armature = bpy.data.armatures.new(RIG)
    armature.display_type = "STICK"
    rig = bpy.data.objects.new(RIG, armature)
    echo.objects.link(rig)
    rig.location = (plane, 0.0, 0.0)
    rig.show_in_front = True
    bpy.context.view_layer.update()
    to_local = rig.matrix_world.inverted()
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = armature.edit_bones
    new_bone(bones, "Root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.08), deform=False, up=(0.0, -1.0, 0.0))
    parent = "Root"
    for name, head, tail in SPINE:
        new_bone(bones, name, head, tail, parent, up=(0.0, -1.0, 0.0), connect=parent != "Root")
        parent = name
    chains = {}  # object name -> list of (points-filter, joints, names, parent)
    for suffix, sign in sides():
        def p(point):
            return Vector((point[0] * sign, point[1], point[2]))
        for name, head, tail, parent in ARM:
            new_bone(bones, name + suffix, p(head), p(tail), parent + (suffix if parent != "UpperChest" else ""), up=(0.0, 0.0, 1.0), connect=name != "Shoulder")
        for finger, (xs, y) in FINGERS.items():
            joints = [p((x, y, HAND_Z)) for x in xs]
            previous = "Hand" + suffix
            for k in range(3):
                bone = "%s_%d%s" % (finger, k + 1, suffix)
                new_bone(bones, bone, joints[k], joints[k + 1], previous, connect=k > 0)
                previous = bone
        previous = "Hand" + suffix
        for k in range(3):
            bone = "Thumb_%d%s" % (k + 1, suffix)
            new_bone(bones, bone, p((THUMB[k][0], THUMB[k][1], HAND_Z)), p((THUMB[k + 1][0], THUMB[k + 1][1], HAND_Z)), previous, connect=k > 0)
            previous = bone
        for name, head, tail, parent in LEG:
            new_bone(bones, name + suffix, p(head), p(tail), parent + (suffix if parent != "Hips" else ""), up=(0.0, -1.0, 0.0),
                     deform=name != "Toes", connect=name in ("LowerLeg", "Foot", "Toes"))
        for k, (x, tip_y) in enumerate(TOES):
            base = p((x, TOE_BASE_Y, TOE_Z))
            tip = p((x, tip_y, TOE_Z - 0.001))
            mid = base.lerp(tip, 0.5)
            new_bone(bones, "Toe%d_1%s" % (k + 1, suffix), base, mid, "Toes" + suffix)
            new_bone(bones, "Toe%d_2%s" % (k + 1, suffix), mid, tip, "Toe%d_1%s" % (k + 1, suffix), connect=True)

    def local(points):
        return [to_local @ point for point in points]

    def side_of(points):
        return ".L" if sum(point.x for point in points) / len(points) >= 0.0 else ".R"

    head_middle = (Vector(SPINE[-1][1]) + Vector(SPINE[-1][2])) * 0.5

    # Eyes, crown, cheek tufts, ears, antennae + lanterns (on the head).
    eye_points = local(pre_armature_points(eye, ("MIRROR",)))
    eye_side = side_of(eye_points)
    eye_centre = sum(eye_points, Vector()) / len(eye_points)
    for suffix, sign in sides():
        centre = eye_centre if suffix == eye_side else mirror(eye_centre)
        new_bone(bones, "Eye" + suffix, centre, centre + Vector((0.0, -0.02, 0.0)), HEAD_PARENT, up=(0.0, 0.0, 1.0))
    crown_points = local(pre_armature_points(objects["Crown"], ()) + pre_armature_points(objects["CrownSide"], ("MIRROR",)))
    low = min(point.z for point in crown_points)
    high = max(point.z for point in crown_points)
    new_bone(bones, "Crown", Vector((0.0, sum(pt.y for pt in crown_points) / len(crown_points), low)),
             Vector((0.0, sum(pt.y for pt in crown_points) / len(crown_points), high)), HEAD_PARENT, up=(0.0, -1.0, 0.0))

    def part_chain(obj_name, prefix, count, parent, keep=("MIRROR",), end=True, centre_x=False, root=None, polyline=None):
        obj = objects[obj_name]
        points = local(pre_armature_points(obj, keep))
        mirrored = any(m.type == "MIRROR" for m in obj.modifiers)
        suffix = side_of(points) if mirrored and not centre_x else ""
        if polyline is not None:
            joints = polyline_points(local(polyline), count)
        else:
            start = root(points)
            joints = chain_points(points, start, count)
        if centre_x:
            joints = [Vector((0.0, j.y, j.z)) for j in joints]
        names = add_chain(bones, prefix, suffix, joints, parent, end)
        if mirrored and suffix:
            other = ".R" if suffix == ".L" else ".L"
            add_chain(bones, prefix, other, [mirror(j) for j in joints], parent, end)
        chains.setdefault(obj_name, []).append((None, joints, names, parent))
        return points, joints, names

    def nearest_to(target):
        def pick(points):
            ranked = sorted(points, key=lambda pt: (pt - target).length)
            near = ranked[:max(3, len(ranked) // 8)]
            return sum(near, Vector()) / len(near)
        return pick

    part_chain("Ear", "Ear", EAR_BONES, HEAD_PARENT, root=nearest_to(head_middle))
    part_chain("CheekTuft", "CheekTuft", 1, HEAD_PARENT, end=False, root=nearest_to(head_middle))
    # Antenna: along the source curve (its base side).
    source = bpy.data.objects["Antenna (curve source)"]
    spline_points = []
    for spline in source.data.splines:
        if spline.type == "BEZIER":
            for a, b in zip(spline.bezier_points, spline.bezier_points[1:]):
                for k in range(16):
                    t = k / 16.0
                    point = (((1 - t) ** 3) * a.co + 3 * ((1 - t) ** 2) * t * a.handle_right + 3 * (1 - t) * t * t * b.handle_left + t ** 3 * b.co)
                    spline_points.append(source.matrix_world @ point)
            spline_points.append(source.matrix_world @ spline.bezier_points[-1].co)
    _, antenna_joints, _ = part_chain("Antenna", "Antenna", ANTENNA_BONES, HEAD_PARENT, end=False, polyline=spline_points)
    lantern_points = local(pre_armature_points(objects["Lantern"], ("MIRROR",)))
    lantern_side = side_of(lantern_points)
    lantern_centre = sum(lantern_points, Vector()) / len(lantern_points)
    direction = (antenna_joints[-1] - antenna_joints[-2]).normalized()
    antenna_side = ".L" if antenna_joints[-1].x >= 0 else ".R"
    for suffix, sign in sides():
        centre = lantern_centre if suffix == lantern_side else mirror(lantern_centre)
        d = direction if suffix == antenna_side else mirror(direction)
        new_bone(bones, "Lantern" + suffix, centre - d * 0.012, centre + d * 0.012, "Antenna_%d%s" % (ANTENNA_BONES, suffix))

    # Tails along their TailPath curves.
    for obj_name, (prefix, path_name) in TAILS.items():
        path = bpy.data.objects[path_name]
        polyline = evaluated_points(path)
        part_chain(obj_name, prefix, TAIL_BONES, TAIL_PARENT, keep=("CURVE",), polyline=polyline)

    # Skirt: one chain per leaf (island), numbered front to back.
    skirt = objects["SkirtSide"]
    skirt_points = local(pre_armature_points(skirt, ("MIRROR",)))
    mesh = bmesh.new()
    mesh.from_mesh(skirt.data)
    islands = []
    seen = set()
    for vertex in mesh.verts:
        if vertex.index in seen:
            continue
        stack = [vertex]
        seen.add(vertex.index)
        island = []
        while stack:
            current = stack.pop()
            island.append(current.index)
            for edge in current.link_edges:
                other = edge.other_vert(current)
                if other.index not in seen:
                    seen.add(other.index)
                    stack.append(other)
        islands.append(island)
    mesh.free()
    islands.sort(key=lambda isl: sum(skirt_points[i].y for i in isl) / len(isl))
    skirt_side = side_of(skirt_points)
    skirt_chains = []
    collapsed = []
    number = 0
    for island in islands:
        points = [skirt_points[i] for i in island]
        centre = sum(points, Vector()) / len(points)
        if max((pt - centre).length for pt in points) < MIN_LEAF_SIZE:
            # Collapsed leftover geometry (all its points in one spot): no
            # bones, it just follows the hips.
            collapsed.append(island)
            continue
        number += 1
        top = max(pt.z for pt in points)
        rim = [pt for pt in points if pt.z > top - 0.03]
        joints = chain_points(points, sum(rim, Vector()) / len(rim), SKIRT_BONES)
        names = add_chain(bones, "Skirt%d" % number, skirt_side, joints, SKIRT_PARENT)
        add_chain(bones, "Skirt%d" % number, ".R" if skirt_side == ".L" else ".L", [mirror(j) for j in joints], SKIRT_PARENT)
        skirt_chains.append((island, joints, names))

    def top_root(points):
        top = max(pt.z for pt in points)
        rim = [pt for pt in points if pt.z > top - 0.03]
        return sum(rim, Vector()) / len(rim)

    part_chain("SkirtFront", "SkirtFront", SKIRT_BONES, SKIRT_PARENT, keep=(), root=top_root)
    part_chain("SkirtBack", "SkirtBack", SKIRT_BONES, SKIRT_PARENT, centre_x=True, root=top_root)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("bones:", len(armature.bones))

    # 3. Weights.
    weights, empty = body_weights(cube, rig)
    body_points = pre_armature_points(cube, ("MIRROR",))
    allowed = {bone.name for bone in armature.bones if bone.use_deform and bone.name.startswith(BODY_BONE_PREFIXES)}
    filled = nearest_bone_fill(weights, body_points, rig, allowed)
    set_weights(cube, weights)
    log("body: automatic weights,", len(weights), "verts,", filled, "filled from the nearest bone")

    def local_points(obj, keep):
        return local(pre_armature_points(obj, keep))

    for obj_name, entries in chains.items():
        obj = objects[obj_name]
        keep = ("CURVE",) if obj_name in TAILS else ("MIRROR",)
        points = local_points(obj, keep)
        _, joints, names, parent = entries[0]
        set_weights(obj, chain_weights(points, joints, names, parent))
    skirt_weights = [None] * len(skirt.data.vertices)
    for island, joints, names in skirt_chains:
        island_weights = chain_weights([skirt_points[i] for i in island], joints, names, SKIRT_PARENT)
        for i, w in zip(island, island_weights):
            skirt_weights[i] = w
    for island in collapsed:
        for i in island:
            skirt_weights[i] = {SKIRT_PARENT: 1.0}
    if collapsed:
        log("SkirtSide: %d collapsed island(s) (%s vertices in one spot) only follow %s" % (
            len(collapsed), ", ".join(str(len(isl)) for isl in collapsed), SKIRT_PARENT))
    set_weights(skirt, skirt_weights)
    rigid = {"ChestCrystal": "UpperChest", "Crown": "Crown", "CrownSide": "Crown"}
    for obj_name, bone in rigid.items():
        set_weights(objects[obj_name], [{bone: 1.0}] * len(objects[obj_name].data.vertices))
    set_weights(eye, [{"Eye" + eye_side: 1.0}] * len(eye.data.vertices))
    set_weights(objects["Lantern"], [{"Lantern" + lantern_side: 1.0}] * len(objects["Lantern"].data.vertices))

    # 4. Armature modifiers and parents.
    for obj in echo.all_objects:
        if obj.type == "MESH":
            add_armature_modifier(obj, rig, ("MIRROR", "CURVE"))
        if obj != rig and obj.type in ("MESH", "CURVE"):
            parent_keep(obj, rig)
    bpy.context.view_layer.update()

    # 5. Every vertex weighted, and the rest shape identical.
    for obj in echo.all_objects:
        if obj.type != "MESH":
            continue
        unweighted = sum(1 for v in obj.data.vertices if not any(g.weight > 0.0 and obj.vertex_groups[g.group].name in armature.bones for g in v.groups))
        if unweighted:
            raise SystemExit("RIG FAILED: %s has %d vertices without bone weights" % (obj.name, unweighted))
    after = shape_of(echo)
    after["Antenna"] = after.pop("Antenna")
    worst = compare(before, after)
    log("rest shape: largest difference %.8f m over %d objects" % (worst, len(before)))
    if worst > TOLERANCE:
        arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        if "--save-failed" in arguments:
            bpy.ops.wm.save_as_mainfile(filepath=arguments[arguments.index("--save-failed") + 1], copy=True)
        raise SystemExit("RIG FAILED: the rest shape changed (%.6f m): not saved" % worst)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.wm.save_mainfile()
    log("saved", bpy.data.filepath)


main()
