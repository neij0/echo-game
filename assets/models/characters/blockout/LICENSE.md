# Character blockouts (the Echo and the Guardian)

**BLOCKOUT PLACEHOLDERS, NOT FINAL ART.** Stylised low-poly shapes made to choose a
silhouette for each character; they are replaced when the final models are made.

- Made for this project by `tools/blender/make_character_blockouts.py` (Blender 5.2, run
  headless), from nothing but the script: tubes, ribbons, balls and turned shapes built in
  code. No source model, no external asset, no AI-generated art. The pictures in `docs/ref/`
  were mood references only: nothing was traced or copied from them, and they are not part
  of the game.
- Licence: the project's own.
- Made: 2026-11-14.
- Files (one rigged `.glb` per variant, about 2,000-2,300 triangles, no UVs; the materials
  only carry a name, a colour and a glow, the game puts its shared character shader on them):
  - `echo_blockout_a` "Leaf", `echo_blockout_b` "Comet", `echo_blockout_c` "Bell"
  - `guardian_blockout_a` "Stag", `guardian_blockout_b` "Spire", `guardian_blockout_c` "Bulwark"
  - `mixamo_upload/guardian_blockout_body.fbx`: the bare body of the Guardian (T-pose, no
    cloak, antlers, sword or rig), the mesh to upload to Mixamo for its automatic rig. Not
    read by the game (the folder has a `.gdignore`).
- Rig: the bone names of the humanoid profile of Godot (so Mixamo animations retargeted to
  that profile play on it), plus bone chains named `<Name>_1 ... <Name>_end` (antennae,
  ears, tails, cloak, scarf) that the game moves with springs (`BoneSway`), and a `Sword`
  bone on the right hand of the Guardian.
- Rebuild: `blender --background --python tools/blender/make_character_blockouts.py -- assets/models/characters/blockout assets/models/characters/blockout/mixamo_upload`
