"""Builds the Ocean rock kit (boulders, slabs, columns, a spire, overhangs,
angular chunks, rubble and pebbles) and exports it as one .glb.

Run headless:
  blender --background --python tools/blender/make_rock_kit.py -- <out.glb> [seed]

Every piece is made the same way, from nothing but this script (no source
model): an icosphere is stretched to the profile of the piece, pushed in and
out with layered noise, chipped flat by random planes (broken faces), cut
flat just under the floor so it sits in the sand, reduced to a few hundred
triangles and given hard edges where faces meet sharply. The origin is the
middle of the base on the floor; +Z is up here (+Y in Godot); 1 unit = 1
world unit. No UVs and no materials: the rock shader of the game textures
every piece in world space, so pieces of any size and turn read as one rock.
"""

import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

# name: (kind, size x / y / z, noise strength, chips, triangles)
PIECES = {
    "boulder_a": ("boulder", (2.0, 1.7, 1.3), 0.28, 13, 300),
    "boulder_b": ("boulder", (1.6, 1.8, 1.1), 0.32, 15, 280),
    "boulder_c": ("boulder", (2.3, 1.5, 1.0), 0.26, 12, 300),
    "boulder_d": ("boulder", (1.4, 1.3, 1.4), 0.30, 14, 260),
    "slab_a": ("slab", (2.6, 1.7, 0.7), 0.20, 14, 260),
    "slab_b": ("slab", (2.1, 2.0, 0.6), 0.22, 15, 260),
    "slab_c": ("slab", (2.9, 1.3, 0.8), 0.20, 13, 260),
    "column_a": ("column", (1.1, 1.0, 2.0), 0.22, 15, 280),
    "column_b": ("column", (0.9, 1.1, 1.7), 0.24, 14, 260),
    "spire_a": ("spire", (1.2, 1.1, 2.1), 0.22, 13, 260),
    "overhang_a": ("overhang", (1.7, 1.4, 1.5), 0.24, 13, 300),
    "overhang_b": ("overhang", (1.5, 1.6, 1.3), 0.26, 14, 280),
    "chunk_a": ("chunk", (1.7, 1.5, 1.2), 0.16, 16, 240),
    "chunk_b": ("chunk", (1.5, 1.8, 1.0), 0.16, 18, 240),
    "rubble_a": ("rubble", (1.8, 1.5, 0.6), 0.28, 5, 320),
    "rubble_b": ("rubble", (1.5, 1.7, 0.5), 0.28, 5, 320),
    "pebbles_a": ("pebbles", (1.2, 1.1, 0.16), 0.22, 3, 220),
    "pebbles_b": ("pebbles", (1.0, 1.3, 0.14), 0.22, 3, 220),
}

SINK = 0.12  # how far the flat base lies under the floor
SHARP_DEGREES = 24.0


def layered_noise(point, offset, octaves=4):
    value = 0.0
    amplitude = 1.0
    frequency = 1.0
    total = 0.0
    for _ in range(octaves):
        value += amplitude * noise.noise(point * frequency + offset)
        total += amplitude
        amplitude *= 0.5
        frequency *= 2.1
    return value / total


def lump(rng, size, strength, chips, kind):
    """One rock as a bmesh, base on z = 0 (cut at -SINK)."""
    mesh = bmesh.new()
    bmesh.ops.create_icosphere(mesh, subdivisions=3, radius=1.0)
    offset = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    half = Vector((size[0] * 0.5, size[1] * 0.5, size[2] * 0.5))
    for vertex in mesh.verts:
        direction = vertex.co.normalized()
        # Big shapes, then a ridged layer for broken, uneven faces.
        broad = layered_noise(direction * 1.3, offset, 3)
        ridged = 1.0 - abs(layered_noise(direction * 2.6, offset * 1.7, 3)) * 2.0
        radius = 1.0 + strength * (broad * 1.6 + ridged * 0.6)
        vertex.co = direction * radius
    # Chips: random planes that flatten whatever sticks out past them.
    for _ in range(chips):
        normal = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.5, 1))).normalized()
        distance = rng.uniform(0.6, 0.95)
        for vertex in mesh.verts:
            over = vertex.co.dot(normal) - distance
            if over > 0.0:
                vertex.co -= normal * over
    slab_tilt = math.sin(offset.z) * 0.16
    for vertex in mesh.verts:
        co = vertex.co
        co.x *= half.x
        co.y *= half.y
        # The middle of the sphere sits a little under the floor: a wide base.
        co.z = (co.z + 0.72) / 1.72 * size[2]
        t = max(0.0, min(1.0, co.z / size[2]))
        if kind == "spire":
            taper = 1.0 - 0.68 * t ** 1.3
            co.x *= taper
            co.y *= taper
        elif kind == "overhang":
            grow = 0.72 + 0.6 * t
            co.x = co.x * grow + 0.38 * size[0] * t * t
            co.y *= 0.85 + 0.3 * t
        elif kind == "column":
            co.x += 0.12 * math.sin(t * 2.6 + offset.x) * size[0]
            co.y += 0.10 * math.sin(t * 2.1 + offset.y) * size[1]
            waist = 1.0 - 0.14 * math.sin(t * math.pi)
            co.x *= waist
            co.y *= waist
        elif kind == "slab":
            co.z += slab_tilt * co.x
    # Flat base just under the floor.
    for vertex in mesh.verts:
        if vertex.co.z < -SINK:
            vertex.co.z = -SINK
    return mesh


def cluster(rng, size, strength, chips, kind):
    """Several small stones side by side (rubble, pebbles)."""
    mesh = bmesh.new()
    count = rng.randint(4, 6) if kind == "rubble" else rng.randint(7, 10)
    each = 320 // count
    for _ in range(count):
        if kind == "rubble":
            stone = (rng.uniform(0.45, 0.9), rng.uniform(0.4, 0.8), size[2] * rng.uniform(0.5, 1.0))
        else:
            stone = (rng.uniform(0.12, 0.3), rng.uniform(0.1, 0.26), size[2] * rng.uniform(0.45, 1.0))
        part = lump(rng, stone, strength, chips, "boulder")
        # Small stones need few triangles: thin each one before joining.
        bmesh.ops.remove_doubles(part, verts=part.verts, dist=0.002)
        angle = rng.uniform(0.0, math.tau)
        reach = math.sqrt(rng.random())
        shift = Vector((math.cos(angle) * reach * size[0] * 0.38, math.sin(angle) * reach * size[1] * 0.38, 0.0))
        turn = rng.uniform(0.0, math.tau)
        for vertex in part.verts:
            x, y = vertex.co.x, vertex.co.y
            vertex.co.x = x * math.cos(turn) - y * math.sin(turn) + shift.x
            vertex.co.y = x * math.sin(turn) + y * math.cos(turn) + shift.y
        data = bpy.data.meshes.new("part")
        part.to_mesh(data)
        part.free()
        stone_object = bpy.data.objects.new("part", data)
        bpy.context.scene.collection.objects.link(stone_object)
        reduce_to(stone_object, each)
        mesh.from_mesh(stone_object.data)
        bpy.data.objects.remove(stone_object)
        bpy.data.meshes.remove(data)
    return mesh


def reduce_to(piece, triangles):
    faces = len(piece.data.polygons)
    if faces <= triangles:
        return
    bpy.context.view_layer.objects.active = piece
    piece.select_set(True)
    modifier = piece.modifiers.new("reduce", "DECIMATE")
    modifier.ratio = triangles / faces
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    piece.select_set(False)


def finish(name, mesh, triangles, weld):
    if weld:
        bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=0.004)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    mesh.free()
    piece = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(piece)
    if weld:
        reduce_to(piece, triangles)
    # Smooth shading with hard edges where faces meet sharply.
    work = bmesh.new()
    work.from_mesh(piece.data)
    limit = math.radians(SHARP_DEGREES)
    for face in work.faces:
        face.smooth = True
    for edge in work.edges:
        edge.smooth = len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) < limit
    work.normal_update()
    work.to_mesh(piece.data)
    work.free()
    return piece


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not arguments:
        raise SystemExit("usage: -- <out.glb> [seed]")
    seed = int(arguments[1]) if len(arguments) > 1 else 7
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = []
    for index, (name, (kind, size, strength, chips, triangles)) in enumerate(PIECES.items()):
        rng = random.Random(seed * 1000 + index)
        grouped = kind in ("rubble", "pebbles")
        if grouped:
            mesh = cluster(rng, size, strength, chips, kind)
        else:
            mesh = lump(rng, size, strength, chips, kind)
        piece = finish("rock_" + name, mesh, triangles, not grouped)
        low = min(v.co.z for v in piece.data.vertices)
        high = max(v.co.z for v in piece.data.vertices)
        wide = max(max(abs(v.co.x), abs(v.co.y)) for v in piece.data.vertices)
        piece.data.calc_loop_triangles()
        report.append("%s: %d triangles, z %.2f..%.2f, reach %.2f" % (piece.name, len(piece.data.loop_triangles), low, high, wide))
    bpy.ops.export_scene.gltf(filepath=arguments[0], export_format="GLB", export_materials="NONE",
        export_texcoords=False, export_normals=True, export_yup=True)
    print("\n".join(report))
    print("ROCK KIT: %d pieces -> %s" % (len(report), arguments[0]))


main()
