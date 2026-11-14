"""Cuts a character reference sheet (front, side and back side by side) into
one image per view. Only cuts pictures: it makes no shapes.

Run headless:
  blender --background --python tools/blender/crop_reference.py -- docs/ref/echo_final_ref.png docs/ref/echo

writes docs/ref/echo_front.png, echo_side.png and echo_back.png. Every view
keeps the same height and the same rows of the sheet, so the three share one
scale and the soles stay on the same line (setup_reference.py relies on it).

VIEWS holds where each view sits in echo_final_ref.png (pixels, measured from
it). The side view's tail and the back view's hand overlap a few columns, so
each view also lists boxes that belong to its neighbour: they are painted
with the background colour. Another sheet needs its own numbers.
"""

import os
import sys

import bpy
import numpy as np

# name: (first column, end column, [boxes of the neighbour: x0, y0, x1, y1]);
# rows counted from the top of the sheet.
VIEWS = {
    "front": (0, 577, []),
    "side": (577, 1012, [(990, 380, 1012, 450)]),
    "back": (990, 1536, [(990, 700, 1009, 860)]),
}
# Rows kept (all views): a margin above the antennae and below the soles.
TOP = 95
BOTTOM = 940
# Pixels this close to the background colour count as background.
BACKGROUND_TOLERANCE = 0.06


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(arguments) < 2:
        raise SystemExit("usage: -- <sheet.png> <out prefix, e.g. docs/ref/echo>")
    sheet = bpy.data.images.load(os.path.abspath(arguments[0]))
    width, height = sheet.size
    # Blender stores rows from the bottom up: flip to rows from the top.
    pixels = np.array(sheet.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1]
    background = np.median(pixels[:20, :20, :].reshape(-1, 4), axis=0)
    for name, (x0, x1, foreign) in VIEWS.items():
        view = pixels[TOP:BOTTOM, x0:x1].copy()
        for bx0, by0, bx1, by1 in foreign:
            view[max(by0 - TOP, 0):by1 - TOP, max(bx0 - x0, 0):bx1 - x0] = background
        content = np.abs(view[:, :, :3] - background[:3]).max(axis=2) > BACKGROUND_TOLERANCE
        rows = np.where(content.any(axis=1))[0]
        out = bpy.data.images.new("crop_" + name, x1 - x0, BOTTOM - TOP, alpha=True)
        out.pixels[:] = view[::-1].ravel()
        path = os.path.abspath("%s_%s.png" % (arguments[1], name))
        out.filepath_raw = path
        out.file_format = "PNG"
        out.save()
        print("REFERENCE %s: %dx%d px, figure rows %d..%d -> %s" % (name, x1 - x0, BOTTOM - TOP, rows.min(), rows.max(), path))


main()
