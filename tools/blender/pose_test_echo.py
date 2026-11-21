"""Test poses for the rigged Echo (art/echo/echo_model.blend), to judge the
weights. It changes nothing: the poses are set in memory, never saved.

Run headless (from the project folder):
  blender --background art/echo/echo_model.blend --python tools/blender/pose_test_echo.py -- <folder>

For each pose (arms down, knees bent, fist, head turn, tail curl): a
picture (front, side and three-quarter, or a close view), and a list of
the places where the surface stretches or squashes a lot (an edge longer
than STRETCH x or shorter than SQUASH x its rest length), by the nearest
bone: the spots to check by hand in Weight Paint.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

RIG = "EchoRig"
STRETCH = 1.4
SQUASH = 0.6
SIZE = 640


def arguments():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: -- <folder>")
    return os.path.abspath(args[0])


def rotate(rig, name, axis, degrees):
    """Turns a bone about an axis of the armature's space (its head stays)."""
    bone = rig.pose.bones[name]
    bpy.context.view_layer.update()
    matrix = bone.matrix.copy()
    head = matrix.translation.copy()
    turn = Matrix.Rotation(math.radians(degrees), 4, Vector(axis).normalized())
    bone.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ matrix
    bpy.context.view_layer.update()


def side(name, suffix):
    return name + suffix


def pose_arms_down(rig):
    for suffix, sign in ((".L", 1.0), (".R", -1.0)):
        rotate(rig, "UpperArm" + suffix, (0.0, 1.0, 0.0), 70.0 * sign)
        rotate(rig, "LowerArm" + suffix, (0.0, 0.0, 1.0), 25.0 * sign)


def pose_knees_bent(rig):
    for suffix in (".L", ".R"):
        rotate(rig, "UpperLeg" + suffix, (1.0, 0.0, 0.0), 60.0)
        rotate(rig, "LowerLeg" + suffix, (1.0, 0.0, 0.0), -100.0)
        rotate(rig, "Foot" + suffix, (1.0, 0.0, 0.0), 30.0)


def pose_fist(rig):
    for suffix, sign in ((".L", 1.0), (".R", -1.0)):
        for finger in ("Index", "Middle", "Ring", "Little"):
            for k in (1, 2, 3):
                rotate(rig, "%s_%d%s" % (finger, k, suffix), (0.0, 1.0, 0.0), 75.0 * sign)
        for k, angle in ((1, 25.0), (2, 45.0), (3, 45.0)):
            rotate(rig, "Thumb_%d%s" % (k, suffix), (1.0 * sign, 0.6, 0.0), angle)


def pose_head_turn(rig):
    rotate(rig, "Neck", (0.0, 0.0, 1.0), 15.0)
    rotate(rig, "Head", (0.0, 0.0, 1.0), 35.0)
    rotate(rig, "Head", (1.0, 0.0, 0.0), -10.0)


def pose_tail_curl(rig):
    for prefix in ("TailMid", "TailLeft", "TailRight"):
        for k in range(1, 7):
            rotate(rig, "%s_%d" % (prefix, k), (1.0, 0.0, 0.0), -22.0)


POSES = [
    ("arms_down", pose_arms_down, "body"),
    ("knees_bent", pose_knees_bent, "body"),
    ("fist", pose_fist, "hand"),
    ("head_turn", pose_head_turn, "head"),
    ("tail_curl", pose_tail_curl, "body"),
]
# view: target, ortho size, directions
FRAMES = {
    "body": ((0.0, 0.05, 0.55), 1.25, [(0.0, -1.0, 0.15), (1.0, 0.0, 0.15), (0.8, -1.0, 0.45)]),
    "hand": ((0.40, -0.06, 0.70), 0.26, [(0.0, -1.0, 0.3), (0.3, -0.4, 1.0), (1.0, -0.5, 0.2)]),
    "head": ((0.0, -0.03, 0.88), 0.55, [(0.0, -1.0, 0.15), (1.0, 0.0, 0.1), (0.8, -1.0, 0.45)]),
}


def evaluated(objects):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    result = {}
    for obj in objects:
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        points = np.array([tuple(ev.matrix_world @ v.co) for v in mesh.vertices])
        edges = np.array([tuple(e.vertices) for e in mesh.edges])
        ev.to_mesh_clear()
        result[obj.name] = (points, edges)
    return result


def bad_spots(rest, posed, rig):
    """Edges stretched / squashed past the limits, counted by nearest bone."""
    heads = [(b.name, (rig.matrix_world @ ((b.head_local + b.tail_local) * 0.5))) for b in rig.data.bones if b.use_deform]
    names = [n for n, _ in heads]
    centres = np.array([tuple(p) for _, p in heads])
    found = {}
    for obj_name, (points, edges) in rest.items():
        moved = posed[obj_name][0]
        if len(edges) == 0 or len(moved) != len(points):
            continue
        before = np.linalg.norm(points[edges[:, 0]] - points[edges[:, 1]], axis=1)
        after = np.linalg.norm(moved[edges[:, 0]] - moved[edges[:, 1]], axis=1)
        ok = before > 1e-6
        ratio = np.where(ok, after / np.maximum(before, 1e-9), 1.0)
        bad = np.where((ratio > STRETCH) | (ratio < SQUASH))[0]
        for e in bad:
            middle = (points[edges[e, 0]] + points[edges[e, 1]]) * 0.5
            bone = names[int(np.argmin(np.linalg.norm(centres - middle, axis=1)))]
            key = (obj_name, bone)
            entry = found.setdefault(key, [0, 1.0, 1.0])
            entry[0] += 1
            entry[1] = min(entry[1], ratio[e])
            entry[2] = max(entry[2], ratio[e])
    return found


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = False
    scene.render.film_transparent = False
    scene.world = scene.world or bpy.data.worlds.new("World")
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = "PNG"
    camera_data = bpy.data.cameras.new("PoseCamera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("PoseCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def shoot(camera, frame, path):
    target, size, directions = FRAMES[frame]
    pictures = []
    for direction in directions:
        d = Vector(direction).normalized()
        camera.location = Vector(target) + d * 4.0
        camera.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = size
        bpy.context.scene.render.filepath = path + "_tmp.png"
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(path + "_tmp.png")
        pictures.append(np.array(image.pixels[:]).reshape(SIZE, SIZE, 4))
        bpy.data.images.remove(image)
    os.remove(path + "_tmp.png")
    sheet = np.concatenate(pictures, axis=1)
    out = bpy.data.images.new(os.path.basename(path), sheet.shape[1], sheet.shape[0])
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = path + ".png"
    out.file_format = "PNG"
    out.save()


def main():
    folder = arguments()
    os.makedirs(folder, exist_ok=True)
    rig = bpy.data.objects[RIG]
    meshes = [obj for obj in bpy.data.collections["Echo"].all_objects if obj.type == "MESH"]
    camera = setup_render()
    rig.hide_render = True
    rest = evaluated(meshes)
    shoot(camera, "body", os.path.join(folder, "pose_0_rest"))
    for number, (name, pose, frame) in enumerate(POSES, 1):
        for bone in rig.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        pose(rig)
        posed = evaluated(meshes)
        shoot(camera, frame, os.path.join(folder, "pose_%d_%s" % (number, name)))
        spots = bad_spots(rest, posed, rig)
        print("POSE %s: %d spot(s)" % (name, len(spots)))
        for (obj_name, bone), (count, low, high) in sorted(spots.items(), key=lambda item: -item[1][0]):
            print("  %-12s near %-14s %3d edge(s), length x%.2f .. x%.2f" % (obj_name, bone, count, low, high))
    print("POSES saved in", folder)


main()
