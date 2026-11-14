"""The Guardian's second option: a human-made Mixamo character as the body,
wearing the gear of the final blockout (helm trims, eye slit, antlers, cowl,
pauldrons, gold, the ragged cape on bone chains, the greatsword).

Run headless:
  blender --background --python tools/blender/make_guardian_mixamo.py -- <mixamo character .fbx> <out .glb>

The .fbx is a character downloaded from mixamo.com in T-pose (see
assets/models/characters/mixamo/README.md for which one and how). The script:
imports it, applies its transforms, scales it so its neck is as high as the
blockout's, renames the Mixamo bones to the names the game's CharacterModel
uses (Godot's humanoid names; "Spine2" becomes "Chest", where the gear hangs),
replaces its materials by the Guardian's dark armour (the game puts its shared
character shader on every surface anyway), measures the body from its bones
and builds the gear to those measures (make_character_blockouts.guardian_gear),
adds the gear's bones (cape chains, Sword) to the same rig and exports one .glb.

BLOCKOUT PLACEHOLDER, like the others. A Mixamo character may be used in the
game but must not be redistributed on its own: keep the downloaded .fbx out
of the repository (assets/models/characters/mixamo/ ignores it).
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_character_blockouts as blockouts  # noqa: E402

# Mixamo bone -> the name used by the game. Bones not listed keep their name
# (fingers...), without the "mixamorig:" prefix.
NAMES = {
    "Spine2": "Chest",
    "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm",
    "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm",
    "LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftToeBase": "LeftToes",
    "RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightToeBase": "RightToes",
}
NEEDED = ("Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot")
# A real head (with a helmet) is larger than the blockout's small one.
HEAD_SIZE = (0.105, 0.12, 0.125)


def apply_transforms(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for item in objects:
        item.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(arguments) < 2:
        raise SystemExit("usage: -- <mixamo character .fbx> <out .glb>")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=arguments[0], automatic_bone_orientation=True)
    rigs = [item for item in bpy.context.scene.objects if item.type == "ARMATURE"]
    meshes = [item for item in bpy.context.scene.objects if item.type == "MESH"]
    if len(rigs) != 1 or not meshes:
        raise SystemExit("expected one rigged character in %s (found %d rigs, %d meshes)" % (arguments[0], len(rigs), len(meshes)))
    rig = rigs[0]
    apply_transforms([rig] + meshes)

    for bone in rig.data.bones:
        short = bone.name.split(":")[-1]
        bone.name = NAMES.get(short, short)
    missing = [name for name in NEEDED if name not in rig.data.bones]
    if missing:
        raise SystemExit("not a Mixamo rig: bones missing: %s" % ", ".join(missing))

    # As tall as the blockout (by the neck), feet on the floor.
    size = dict(blockouts.GUARDIAN_FINAL_SIZE)
    lowest = min((item.matrix_world @ vertex.co).z for item in meshes for vertex in item.data.vertices)
    scale = size["neck"] / (rig.data.bones["Neck"].head_local.z - lowest)
    for item in [rig] + [mesh for mesh in meshes if mesh.parent != rig]:
        item.scale = (scale, scale, scale)
        item.location.z -= lowest * scale
    bpy.context.view_layer.update()
    apply_transforms([rig] + meshes)

    def at(name):
        return rig.data.bones[name].head_local

    # The body's measures, for the gear.
    size["hip"] = at("Hips").z
    size["waist"] = at("Spine").z
    size["chest"] = at("Chest").z
    size["neck"] = at("Neck").z
    size["head_r"] = HEAD_SIZE
    size["head"] = at("Head").z + HEAD_SIZE[2] * 0.75
    size["head_y"] = at("Head").y - 0.02
    size["shoulder_x"] = abs(at("LeftUpperArm").x)
    size["elbow_x"] = abs(at("LeftLowerArm").x)
    size["wrist_x"] = abs(at("LeftHand").x)
    size["hand_x"] = size["wrist_x"] + 0.11
    size["shoulder"] = at("LeftUpperArm").z + size["arm_r"][0] * 0.6
    size["leg_x"] = abs(at("LeftUpperLeg").x) / 1.05
    size["knee"] = at("LeftLowerLeg").z

    armour = blockouts.material("guardian_armor")
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(armour)

    gear = blockouts.Model("guardian_mixamo_gear")
    blockouts.guardian_gear(gear, size)
    made = gear.build(rig=rig)

    bpy.ops.object.select_all(action="DESELECT")
    for item in [rig] + meshes + made:
        item.select_set(True)
    os.makedirs(os.path.dirname(os.path.abspath(arguments[1])), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=arguments[1], export_format="GLB", use_selection=True, export_yup=True,
        export_texcoords=False, export_normals=True, export_skins=True, export_animations=False,
        export_materials="EXPORT")
    triangles = sum(len(polygon.vertices) - 2 for mesh in meshes for polygon in mesh.data.polygons)
    print("GUARDIAN ON MIXAMO BODY: %s -> %s (body %d triangles + gear %d, scaled x%.3f, head at %.2f)" % (
        arguments[0], arguments[1], triangles, gear.triangle_count(), scale, size["head"]))


main()
