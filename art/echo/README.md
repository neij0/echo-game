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

The side picture is centred on the legs (not the toes or the tail), so the body is over the origin in every view. The back picture is hidden by default (it sits on the same axis as the front one): toggle any reference picture with its **eye icon** in the Outliner (Reference collection).

Save often (**Ctrl + S**). Blender also writes `echo_model.blend1` backups: git ignores them.

## Check the model
```
blender --background art/echo/echo_model.blend --python tools/blender/check_model.py
```
It prints, for each mesh and bevelled curve in the Echo collection (after modifiers,
as exported): triangles (the total against a budget of 16,000), flipped normals, parts that are inside out, non-manifold edges (3+ faces
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

## The rig (EchoRig)
`EchoRig` (in the Echo collection) is the skeleton, made by
`tools/blender/rig_echo.py` (it refuses to run again once EchoRig exists). Every part is
parented to it and has an **Armature** modifier (after Mirror / Curve, before Subdivision /
Solidify). Bone names: `.L` = her left (+X), `.R` = her right. The body bones match
Godot's humanoid skeleton; the extras are the toes, three tails, antennae + lanterns,
ears, skirt leaves, crown and cheek tufts (`_end` bones only mark tips).
Two originals are kept, hidden, in the collection **Echo sources (not exported)**: the
Antenna curve (the Antenna is now a mesh of the same shape: curves cannot hold weights)
and the Eye with its Shrinkwrap (applied in the Eye; it would drag the eyes when the head
turns). Do not delete EchoRig's Armature modifiers.

Test poses (pictures + a list of spots that stretch; it saves nothing):
```
blender --background art/echo/echo_model.blend --python tools/blender/pose_test_echo.py -- docs/character_blockouts/final_echo/rig_poses
```

## Fix weights by hand
**Pose Mode** (to bend the skeleton and see the problem):
1. Click **EchoRig** in the Outliner. In the 3D view press **Ctrl + Tab** (or the mode menu
   at the top left: **Pose Mode**). The bones turn blue.
2. Click a bone, press **R** and move the mouse to turn it (**R X**, **R Y**, **R Z** turns
   about one axis; type a number such as `R Z 45` + **Enter**). **Esc** cancels.
3. To go back to the rest pose: **A** (select all bones), then **Alt + R** (and **Alt + G**).
   Never save the file with a pose left on (or reset it first).

**Weight Paint** (to change which bone moves which part):
1. In Pose Mode with a bone posed, go back to **Object Mode** (Ctrl + Tab), click the part
   (e.g. `Cube`), then **Ctrl + click** EchoRig too (both selected, the part first).
2. Switch to **Weight Paint** (mode menu). Now **Ctrl + click** a bone to pick it: red =
   that bone moves this spot fully, blue = not at all.
3. Paint with the left mouse button. At the top: **Weight** (1 = add, 0 = remove) and
   **Strength**. The brush **Blur** (Shift + click the brush list, or the tool bar on the
   left) softens a hard edge between two bones; this is the usual fix for creases.
4. Paint only on the **right half of the body (+X, her left)**: the Mirror modifier copies
   it to the other side. Parts without Mirror (SkirtFront, the tails, ChestCrystal, Crown)
   are painted as they are.
5. Check by posing the bone again (in Weight Paint, **Ctrl + click** a bone, then **R** works
   too), then reset the pose and save.

Good to know: the body weights came from Blender's automatic weights on a cleaned copy (the
thumb bases have duplicate points that stop the automatic weights; merging them with **M >
By Distance** in Edit Mode fixes that for next time).

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
