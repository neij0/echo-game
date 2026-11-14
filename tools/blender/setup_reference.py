"""Creates the Blender file the Echo is modelled in by hand: art/echo/echo_model.blend.
Technical setup only: it makes no character shapes.

Run headless (from the project folder):
  blender --background --python tools/blender/setup_reference.py
  blender --background --python tools/blender/setup_reference.py -- --force   (replace an existing file)

What the file holds:
- Units like Godot: metric, 1 Blender unit = 1 metre = 1 Godot world unit. The
  floor is z = 0 and the Echo faces -Y (front view, numpad 1), which becomes
  +Z (forward) in Godot. glTF export turns Blender's Z-up into Godot's Y-up.
- An empty collection "Echo" (active): the model goes here, and only this
  collection is exported (export_to_godot.py).
- A collection "Reference" (not selectable, never exported):
  - the front, side and back pictures (docs/ref/echo_front.png ...) as image
    empties that show only in the matching orthographic view (front: numpad 1,
    side: numpad 3, back: ctrl + numpad 1), half transparent, behind the model;
  - "Blockout scale guide": the Echo blockout mesh as a wireframe, hidden (eye
    icon to show it).
- Scale: the pictures are sized so the top of the head (the centre column of
  the front picture) is as high as the top of the blockout's head, with the
  soles on the floor. So the drawn body has the blockout's in-game height.

It refuses to replace an existing echo_model.blend (your work) unless --force.
"""

import os
import sys

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLEND = os.path.join(ROOT, "art", "echo", "echo_model.blend")
BLOCKOUT = os.path.join(ROOT, "assets", "models", "characters", "blockout", "echo_blockout.glb")
PICTURES = os.path.join(ROOT, "docs", "ref", "echo_%s.png")
# view: (rotation in degrees, where the picture stands: behind the model as
# seen from that view's side).
VIEWS = {
    "front": ((90.0, 0.0, 0.0), (0.0, 1.5, 0.0)),
    "side": ((90.0, 0.0, 90.0), (-1.5, 0.0, 0.0)),
    "back": ((90.0, 0.0, 180.0), (0.0, -1.5, 0.0)),
}
# How transparent the pictures are (0 = invisible, 1 = solid).
PICTURE_OPACITY = 0.5
BACKGROUND_TOLERANCE = 0.06
# Columns either side of the body's middle searched for the top of the head,
# and the share of the figure's height (from the soles) taken as the feet.
HEAD_BAND = 4
FEET_SHARE = 0.03
# Half width of the blockout's middle column (its head top, without the
# antennae).
GUIDE_BAND = 0.02


def picture_marks(path):
    """Size of a picture and, in pixels from its top left: the row of the
    soles, the column in the middle of the feet, and the top of the head
    in that column."""
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1]
    background = np.median(pixels[:10, :10, :3].reshape(-1, 3), axis=0)
    content = np.abs(pixels[:, :, :3] - background).max(axis=2) > BACKGROUND_TOLERANCE
    rows = np.where(content.any(axis=1))[0]
    top, sole = rows.min(), rows.max()
    feet_rows = content[int(sole - (sole - top) * FEET_SHARE):sole + 1]
    feet = np.where(feet_rows.any(axis=0))[0]
    middle = (feet.min() + feet.max()) * 0.5
    band = content[:, int(middle) - HEAD_BAND:int(middle) + HEAD_BAND + 1]
    head = np.where(band.any(axis=1))[0].min()
    return image, width, height, sole, middle, head


def blockout_head_top():
    """Imports the blockout, keeps only its mesh (as a wireframe guide) and
    returns the height of the top of its head."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BLOCKOUT)
    made = [item for item in bpy.data.objects if item not in before]
    meshes = [item for item in made if item.type == "MESH"]
    if not meshes:
        return 0.0, None
    # The character mesh (the importer may add small helper meshes).
    guide = max(meshes, key=lambda item: len(item.data.vertices))
    points = [guide.matrix_world @ vertex.co for vertex in guide.data.vertices]
    top = max([point.z for point in points if abs(point.x) < GUIDE_BAND], default=0.0)
    world = guide.matrix_world.copy()
    guide.parent = None
    guide.matrix_world = world
    guide.modifiers.clear()
    for item in made:
        if item != guide:
            bpy.data.objects.remove(item)
    for collection in list(bpy.data.collections):
        if collection.name.startswith("glTF_"):
            bpy.data.collections.remove(collection)
    return top, guide


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if os.path.exists(BLEND) and "--force" not in arguments:
        raise SystemExit("%s exists (your work?): nothing done. Add -- --force to replace it." % BLEND)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"

    echo = bpy.data.collections.new("Echo")
    reference = bpy.data.collections.new("Reference")
    scene.collection.children.link(echo)
    scene.collection.children.link(reference)
    reference.hide_select = True
    reference.hide_render = True

    head_top, guide = blockout_head_top()
    if guide is None or head_top <= 0.0:
        raise SystemExit("could not read the blockout: %s" % BLOCKOUT)
    for collection in list(guide.users_collection):
        collection.objects.unlink(guide)
    reference.objects.link(guide)
    guide.name = "Blockout scale guide"
    guide.display_type = "WIRE"
    guide.hide_set(True)

    _, _, _, sole, _, head = picture_marks(PICTURES % "front")
    metres_per_pixel = head_top / float(sole - head)
    for name, (rotation, location) in VIEWS.items():
        image, width, height, sole, middle, _ = picture_marks(PICTURES % name)
        empty = bpy.data.objects.new("Reference " + name, None)
        reference.objects.link(empty)
        empty.empty_display_type = "IMAGE"
        empty.data = image
        empty.empty_display_size = max(width, height) * metres_per_pixel
        # The middle of the feet on x = 0, the soles on the floor.
        empty.empty_image_offset = (-middle / width, -(height - sole) / height)
        empty.rotation_euler = [value * np.pi / 180.0 for value in rotation]
        empty.location = location
        empty.empty_image_depth = "BACK"
        empty.show_empty_image_perspective = False
        empty.show_empty_image_orthographic = True
        empty.show_empty_image_only_axis_aligned = True
        empty.use_empty_image_alpha = True
        empty.color[3] = PICTURE_OPACITY

    # New objects go into "Echo".
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children["Echo"]
    # Every 3D view starts in the front orthographic view.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.region_3d.view_perspective = "ORTHO"
                    space.region_3d.view_rotation = (0.7071068, 0.7071068, 0.0, 0.0)
                    space.region_3d.view_location = (0.0, 0.0, head_top * 0.6)
                    space.region_3d.view_distance = head_top * 1.6

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    # Picture paths relative to the .blend, so the project folder can move.
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("SETUP: %s (head top %.3f m = blockout; %.5f m per picture pixel)" % (BLEND, head_top, metres_per_pixel))


main()
