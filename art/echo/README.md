# Modelling the Echo in Blender

`echo_model.blend` is where the final Echo is modelled by hand. The scripts in
`tools/blender/` only prepare the file, check the model and export it: they never make or
change a shape.

All commands are run from the project folder (`C:\Users\NEIJ0\echo-game`) in a terminal.
`blender` below means:
`"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"`

## Open the file
Double-click `art/echo/echo_model.blend`, or in Blender: **File > Open**.

What is in it:
- **Echo** (collection, top right in the Outliner): empty, and the active one, so
  everything you add goes here. Only this collection is exported.
- **Reference** (not selectable): the front, side and back pictures, and a hidden
  wireframe of the old blockout ("Blockout scale guide"; click its eye icon to compare).
- Units: metres. 1 Blender metre = 1 unit in the game. The floor is z = 0: keep the soles
  on it. The Echo faces **-Y** (towards you in the front view).
- The pictures are sized so the top of her head is at 1.007 m, the blockout's height.

## Front, side and back views
Move the mouse over the 3D view, then press (number pad keys):
- **1**: front. **3**: side (right). **Ctrl + 1**: back. **7**: top.
- **5**: switch between orthographic and perspective. The pictures only show in the
  orthographic front / side / back views.
- No number pad? **Edit > Preferences > Input > Emulate Numpad** (then the top-row
  numbers work), or click the X / Y / Z circles at the top right of the 3D view.
- **Middle mouse drag**: turn the view, **Shift + middle mouse**: move it,
  **wheel**: zoom, **Home**: show everything.
- The pictures are half transparent. To change it: click the picture in the Outliner,
  then Properties (right) > Object Data tab (picture icon) > **Opacity**. Its eye icon
  in the Outliner hides it.

Save often (**Ctrl + S**). Blender also writes `echo_model.blend1` backups: git ignores them.

## Check the model
```
blender --background art/echo/echo_model.blend --python tools/blender/check_model.py
```
It prints, for each mesh in the Echo collection: triangles (the total against a budget
of 8,000), flipped normals, parts that are inside out, non-manifold edges (3+ faces
on one edge = a problem; open edges = a warning, fine on thin fins), loose vertices and
edges, unapplied scale / rotation (fix with **Ctrl + A > All Transforms**), the height,
and the file size. It ends with `CHECK: n problem(s), m warning(s)`. It only reports:
fix things yourself in Blender. Save in Blender first: it reads the saved file.

Another budget: `... --python tools/blender/check_model.py -- --budget 6000`

## Export to Godot
```
blender --background art/echo/echo_model.blend --python tools/blender/export_to_godot.py
```
writes `assets/models/characters/final/echo.glb` (everything in the Echo collection;
modifiers applied; Blender's Z-up becomes Godot's Y-up). It does not change or save the
.blend. Godot imports the new file the next time the editor opens. The game does not use
it yet: wiring it in comes after you are happy with the model.

## Start again (careful)
The file was made by:
```
blender --background --python tools/blender/setup_reference.py
```
It refuses to touch an existing `echo_model.blend`. `... -- --force` replaces it: that
**deletes your model**. The pictures come from cutting `docs/ref/echo_final_ref.png`:
```
blender --background --python tools/blender/crop_reference.py -- docs/ref/echo_final_ref.png docs/ref/echo
```

## Git
The .blend is in git while it is small. If it grows past 50 MB (`check_model.py` warns),
add the line `art/echo/*.blend` to `.gitignore`, run `git rm --cached art/echo/echo_model.blend`,
and keep a copy somewhere safe (or use Git LFS).
