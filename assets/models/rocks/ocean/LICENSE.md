# Ocean rock kit

- Made for this project by `tools/blender/make_rock_kit.py` (Blender 5.2, run headless),
  from nothing but the script: no source model, no external asset.
- Licence: the project's own.
- Made: 2026-11-14 (seed 7).
- 18 pieces: boulder a-d, slab a-c, column a-b, spire a, overhang a-b, chunk a-b,
  rubble a-b, pebbles a-b; 220-320 triangles each, no UVs, no materials (the rock shader
  textures them in world space).
- Rebuild: `blender --background --python tools/blender/make_rock_kit.py -- assets/models/rocks/ocean/ocean_rock_kit.glb`
