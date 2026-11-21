"""Checks a hand-made model before it goes to Godot. REPORT ONLY: it never
changes a shape and never saves the file.

Run headless (from the project folder):
  blender --background art/echo/echo_model.blend --python tools/blender/check_model.py
  ... --python tools/blender/check_model.py -- --collection Echo --budget 6000

For every mesh and curve in the collection (default "Echo"; modifiers
applied, as the export will see it: a bevelled curve exports as a mesh, a
curve without thickness, e.g. a Curve modifier's path, exports nothing):
- triangles (and the total against the budget);
- flipped normals: faces whose winding disagrees with a neighbour (one of the
  two is flipped), and closed parts that are inside out;
- non-manifold edges: open edges (holes, the rim of a single-sided ribbon:
  fine for thin fins) and edges shared by 3+ faces (always a problem);
- loose vertices and loose edges (not part of any face);
- unapplied scale / rotation (also on the armature), negative scale;
- the model's height and its lowest point, after modifiers (soles at z = 0);
- the size of the .blend (keep it in git only while it is under 50 MB).
Ends with "CHECK: n problem(s), m warning(s)"; the exit code is 1 when there
are problems.
"""

import os
import sys

import bmesh
import bpy

DEFAULT_COLLECTION = "Echo"
# Triangles for the whole character (the hand-made Echo, Subdivision at its
# viewport level as exported).
DEFAULT_BUDGET = 16000
# Object types whose evaluated geometry is exported as a mesh.
GEOMETRY_TYPES = ("MESH", "CURVE")
# Bigger .blend files should leave git (see art/echo/README.md).
BLEND_LIMIT_MB = 50.0
EPSILON = 1e-4


def arguments():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"collection": DEFAULT_COLLECTION, "budget": DEFAULT_BUDGET}
    for i, arg in enumerate(args[:-1]):
        if arg == "--collection":
            options["collection"] = args[i + 1]
        elif arg == "--budget":
            options["budget"] = int(args[i + 1])
    return options


def signed_volume(mesh):
    """Positive for a closed shape whose faces look outward."""
    total = 0.0
    for face in mesh.faces:
        first = face.verts[0].co
        for i in range(1, len(face.verts) - 1):
            total += first.dot(face.verts[i].co.cross(face.verts[i + 1].co))
    return total / 6.0


def inconsistent_edges(mesh):
    """Edges between two faces that run along it in the same direction: one
    of the two faces is flipped."""
    count = 0
    for edge in mesh.edges:
        if len(edge.link_faces) != 2:
            continue
        directions = []
        for face in edge.link_faces:
            for loop in face.loops:
                if loop.edge == edge:
                    directions.append(loop.vert == edge.verts[0])
        if len(directions) == 2 and directions[0] == directions[1]:
            count += 1
    return count


def check_object(item, depsgraph, report):
    evaluated = item.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    heights = [(evaluated.matrix_world @ vertex.co).z for vertex in data.vertices]
    mesh = bmesh.new()
    mesh.from_mesh(data)
    evaluated.to_mesh_clear()
    if item.type == "CURVE" and not mesh.faces:
        mesh.free()
        print("  %s: curve without thickness (a path: exports nothing)" % item.name)
        check_transform(item, report)
        return 0, None, None
    triangles = sum(len(face.verts) - 2 for face in mesh.faces)
    open_edges = sum(1 for edge in mesh.edges if len(edge.link_faces) == 1)
    crowded = sum(1 for edge in mesh.edges if len(edge.link_faces) > 2)
    loose_verts = sum(1 for vert in mesh.verts if not vert.link_edges)
    loose_edges = sum(1 for edge in mesh.edges if not edge.link_faces)
    flipped = inconsistent_edges(mesh)
    # Each closed part on its own: inside out if its volume is negative.
    inside_out = 0
    seen = set()
    for face in mesh.faces:
        if face.index in seen:
            continue
        part = []
        stack = [face]
        seen.add(face.index)
        while stack:
            current = stack.pop()
            part.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        if all(len(edge.link_faces) == 2 for current in part for edge in current.edges):
            piece = bmesh.new()
            mapping = {}
            for current in part:
                for vert in current.verts:
                    if vert not in mapping:
                        mapping[vert] = piece.verts.new(vert.co)
                piece.faces.new([mapping[vert] for vert in current.verts])
            if signed_volume(piece) < 0.0:
                inside_out += 1
            piece.free()
    mesh.free()

    line = "  %s: %d triangles%s" % (item.name, triangles, " (curve)" if item.type == "CURVE" else "")
    print(line)
    if flipped:
        report.problem(item.name, "%d edge(s) between faces that look opposite ways (flipped normals: Mesh > Normals > Recalculate Outside)" % flipped)
    if inside_out:
        report.problem(item.name, "%d closed part(s) inside out (all normals point in)" % inside_out)
    if crowded:
        report.problem(item.name, "%d non-manifold edge(s) shared by 3 or more faces" % crowded)
    if open_edges:
        report.warning(item.name, "%d open edge(s) (holes, or the rim of a single-sided part: fine for a thin fin)" % open_edges)
    if loose_verts:
        report.problem(item.name, "%d loose vertex / vertices (Mesh > Clean Up > Delete Loose)" % loose_verts)
    if loose_edges:
        report.warning(item.name, "%d loose edge(s) (no face)" % loose_edges)
    check_transform(item, report)
    if not heights:
        return triangles, None, None
    return triangles, min(heights), max(heights)


def check_transform(item, report):
    scale = item.scale
    if any(value < 0.0 for value in scale):
        report.problem(item.name, "negative scale %s (mirrored: flips normals in the game)" % (tuple(round(v, 3) for v in scale),))
    elif any(abs(value - 1.0) > EPSILON for value in scale):
        report.problem(item.name, "unapplied scale %s (Object > Apply > Scale)" % (tuple(round(v, 3) for v in scale),))
    if any(abs(value) > EPSILON for value in item.rotation_euler) and item.rotation_mode != "QUATERNION":
        report.problem(item.name, "unapplied rotation %s degrees (Object > Apply > Rotation)" % (tuple(
            round(v * 57.2958, 1) for v in item.rotation_euler),))
    if item.rotation_mode == "QUATERNION" and abs(item.rotation_quaternion.w - 1.0) > EPSILON:
        report.problem(item.name, "unapplied rotation (quaternion) (Object > Apply > Rotation)")


class Report:
    def __init__(self):
        self.problems = 0
        self.warnings = 0

    def problem(self, name, text):
        self.problems += 1
        print("  PROBLEM  %s: %s" % (name, text))

    def warning(self, name, text):
        self.warnings += 1
        print("  warning  %s: %s" % (name, text))


def main():
    options = arguments()
    report = Report()
    collection = bpy.data.collections.get(options["collection"])
    print("CHECK %s, collection \"%s\"" % (bpy.data.filepath or "(unsaved)", options["collection"]))
    if collection is None:
        print("  PROBLEM  no collection named \"%s\"" % options["collection"])
        print("CHECK: 1 problem(s), 0 warning(s)")
        sys.exit(1)
    objects = list(collection.all_objects)
    meshes = [item for item in objects if item.type in GEOMETRY_TYPES]
    if not any(item.type == "MESH" for item in meshes):
        report.warning(options["collection"], "no mesh yet")
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    low = high = None
    lowest_name = ""
    for item in meshes:
        triangles, item_low, item_high = check_object(item, depsgraph, report)
        total += triangles
        if item_low is None:
            continue
        if low is None or item_low < low:
            low = item_low
            lowest_name = item.name
        high = item_high if high is None else max(high, item_high)
    for item in objects:
        if item.type == "ARMATURE":
            print("  %s: armature, %d bones" % (item.name, len(item.data.bones)))
            check_transform(item, report)
        elif item.type not in GEOMETRY_TYPES + ("ARMATURE", "EMPTY"):
            report.warning(item.name, "a %s is in the collection: it will not export as a mesh" % item.type.lower())
    if meshes and low is not None:
        print("  total: %d triangles (budget %d)" % (total, options["budget"]))
        if total > options["budget"]:
            report.problem(options["collection"], "%d triangles, over the budget of %d" % (total, options["budget"]))
        print("  height: %.3f m (lowest point %.3f m, %s; the soles belong on z = 0)" % (high - low, low, lowest_name))
        if abs(low) > 0.05:
            report.warning(options["collection"], "the lowest point is at z = %.3f: the feet should stand on the floor (z = 0)" % low)
    if bpy.data.filepath:
        size = os.path.getsize(bpy.data.filepath) / (1024.0 * 1024.0)
        print("  file: %.1f MB" % size)
        if size > BLEND_LIMIT_MB:
            report.warning("file", "over %d MB: take it out of git (art/echo/README.md)" % BLEND_LIMIT_MB)
    print("CHECK: %d problem(s), %d warning(s)" % (report.problems, report.warnings))
    sys.exit(1 if report.problems else 0)


main()
