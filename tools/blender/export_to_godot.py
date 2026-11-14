"""Exports the hand-made Echo (the "Echo" collection of the .blend) to Godot.
It changes nothing in the .blend and never saves it.

Run headless (from the project folder):
  blender --background art/echo/echo_model.blend --python tools/blender/export_to_godot.py
  ... --python tools/blender/export_to_godot.py -- <out.glb> <collection>

Default out: assets/models/characters/final/echo.glb. Exported: every object
in the collection (meshes, an armature, its actions if there are any), with
modifiers applied, materials, normals and UVs; glTF turns Blender's Z-up into
Godot's Y-up, and 1 Blender metre is 1 Godot unit. The reference pictures
and the blockout guide (collection "Reference") are never exported.
Run check_model.py first. Godot imports the file the next time the editor
opens (or: godot --headless --path . --import).
"""

import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_OUT = os.path.join(ROOT, "assets", "models", "characters", "final", "echo.glb")
DEFAULT_COLLECTION = "Echo"


def find_layer_collection(layer, name):
    if layer.name == name:
        return layer
    for child in layer.children:
        found = find_layer_collection(child, name)
        if found:
            return found
    return None


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(arguments[0]) if arguments else DEFAULT_OUT
    name = arguments[1] if len(arguments) > 1 else DEFAULT_COLLECTION
    layer = find_layer_collection(bpy.context.view_layer.layer_collection, name)
    if layer is None:
        raise SystemExit("EXPORT: no collection named \"%s\" in %s" % (name, bpy.data.filepath))
    objects = list(layer.collection.all_objects)
    if not any(item.type == "MESH" for item in objects):
        raise SystemExit("EXPORT: the collection \"%s\" has no mesh yet: nothing exported" % name)
    bpy.context.view_layer.active_layer_collection = layer
    os.makedirs(os.path.dirname(out), exist_ok=True)
    has_actions = len(bpy.data.actions) > 0
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_active_collection=True,
        use_active_collection_with_nested=True, export_yup=True, export_apply=True,
        export_texcoords=True, export_normals=True, export_materials="EXPORT", export_skins=True,
        export_animations=has_actions)
    triangles = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for item in objects:
        if item.type == "MESH":
            evaluated = item.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            triangles += sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)
            evaluated.to_mesh_clear()
    print("EXPORT: %d object(s), %d triangles%s -> %s" % (len(objects), triangles,
        ", with animations" if has_actions else "", out))


main()
