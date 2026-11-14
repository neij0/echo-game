# Mixamo downloads (the Guardian's rig and animations)

Files downloaded from mixamo.com go in this folder. Mixamo animations are made by
people, free to use in a game (Adobe account needed), but **not CC0 and not to be
redistributed on their own**: the `.gitignore` here keeps the raw `.fbx` files out of
the repository, and the `.gdignore` keeps Godot from importing them. Only what the
Blender scripts make from them goes into the game.

The Guardian keeps our own body (a Mixamo knight as the body was tried as an idea and
dropped: its realistic style clashes with the world). Mixamo is only for his rig and
animations:

1. https://www.mixamo.com, sign in, **Upload Character**:
   `assets/models/characters/blockout/mixamo_upload/guardian_blockout_body.fbx`
   (his bare body in T-pose: no scarf, cape, antlers or sword).
2. In the auto-rigger place the markers (chin, wrists, elbows, knees, groin), keep
   "Standard Skeleton (65)", finish.
3. Download the rigged character: `FBX Binary`, `T-pose` -> `guardian_rigged.fbx`.
4. Animations (search each, download as `FBX Binary`, **Without Skin**, 30 fps):
   - `Great Sword Idle` -> `guardian_idle.fbx`
   - `Great Sword Walk` (tick **In Place**) -> `guardian_walk.fbx`
   - `Great Sword Slash` -> `guardian_slash.fbx`

   (Names from memory: pick the closest if one is called differently.) Put them here.
   Using them in the game (retargeted to Godot's humanoid names, which the blockout rig
   already has) comes after the blockout is approved; until then the game plays its own
   simple animations made in code (`GuardianMoves`).
